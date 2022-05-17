**Disclaimer**: This is just an ideas document, provided purely for discussion
at this time.

# Goals

The goal of this proposal is to solve the problem of duplicate helper code for
macros. Today, two macro applications, even running in the same library, cannot
realistically share helper code with each other. They may even attempt to
produce duplicate helpers and cause naming conflicts, without explicitly doing
anything "wrong".

## Aspect Macros

**NOTE**: This feature is a work in progress, and has many TODOs.

An AspectMacro is used by another macro, to generate shared helper code which
will not be duplicated across every library where that helper was needed.

Concretely, let's consider the following example:

```dart
@fromJsonExtension
class A {}

@fromJsonExtension
class B {
  final A a;

  B(this.a);
}

// Generated extension from the macro on A
extension AFromJson on Map<String, Object?> {
  A toA();
}

// Generated extension from the macro on B
extension BFromJson on Map<String, Object?> {
  A toA(); // This also needs to generate a helper for converting `A`!

  B toB();
}
```

Both of these macro applications need to generate the same shared code for
converting a Map into an instance of `A` (since `B` has a field of that type),
but they can't actually _see_ what each other has generated.

In the worst case, this would result in them both outputting conflicting
members, and in the best case they would end up generating duplicate code,
causing unnecessary code bloat.

Aspect Macros exist to solve this problem, by allowing macros to share these
implementations. This is done by associating a single, canonical declaration
with an Aspect Macro Instance + Declaration pair, and giving back an opaque
identifier for the resulting declaration.

### Applying an Aspect Macro

Aspect Macros can only be applied by other macros (including aspect macros),
while the macro is running. They do this through the following api:

```dart
Future<Identifier> applyAspect(AspectMacro macro, Declaration declaration);
```

This API does not promise to immediately invoke `macro` on `declaration`, it
only returns an opaque `Identifier`, which refers to the declaration that will
be produced by running `macro` on `declaration`. It returns a `Future` because
all `Identifier` objects must come from the host compiler, so there is some
async communication that has to happen.

When a macro implementation receives a call to `applyAspect`, it must register
that `macro` should be _eventually_ applied to `declaration`. Any two identical
calls to `applyAspect` must always return an "equal" `Identifier` object,
regardless of if they are compiled in separate modules.

  - Identical is defined by the concrete type of the Aspect Macro and the
    specific declaration it is attached to. Aspect Macros are not allowed to
    have fields so we do not need to do more than look at the type.

**TODO**: You may need to be able to navigate to the declaration of one of these
`Identifier`s, for instance in order to get a reference to one of its members or
inspect the shape of the generated declaration. How do we want to expose this?
Is it an ok restriction to just say you can't? See the section below on ordering
and invocation for possible constraints.

### Declaring an Aspect Macro

Aspect Macros are declared similarly to regular macros. They are classes with
the `macro` keyword, but implement one of the subtypes of `AspectMacro` instead
of `Macro`.

An example AspectMacro could be something like the following:

**TODO**: Fully flesh out all these APISs.

```dart
macro class FromJson extends ClassDeclarationsAspectMacro {
  FutureOr<Declaration> buildDeclarationForClass(
      ClassDeclaration clazz, MacroAspectBuilder builder) {
    // Implementation that returns a Declaration.
  }
}
```

#### Restrictions on Aspect Macros

- Aspect Macros must be serializable.
- The serializable aspect is enforced by not permitting Aspect Macros to have
  any fields, and they only have a single const constructor with no arguments.
  - **TODO**: Should we make this constructor explicit?
  - **TODO**: Should the api only take the Type of the aspect instead of an
    instance?

### Ordering of Aspect Macros

Aspect Macros are conceptually applied in a 4th macro phase. All non-aspect
macros must be invoked on a library prior to aspect macros being invoked on any
declaration in that library.

Aspect Macros are allowed to invoke other aspect macros, so this 4th phase is
iterative.

- This is only safe because we don't allow introspection of Aspect Macro
  generated identifiers today. If we did then we would need to figure out how
  that should work and how cycles should be handled.

### Modular compilation

Aspect Macros may be ran modularly, which may require merging of generated
declarations at link time. Esssentially, the result of each module should have
a table of all the outputs of the Aspect Macros it had to run, and if multiple
dependency modules ran on the same Aspect Module + Declaration pair, the results
should be deduplicated when reading them in.

### Location of Aspect Macro generated code

TODO: Figure this out. A special library "next" to each library which has aspect
macros applied to its declarations? A single "special" library with all aspects
merged in? A library per aspect macro application?

### Possible extra feature: Data Collection

**TODO**: Fully explore this use case.

Another possible use case for something like an Aspect Macro, would be to
generate a declaration at the top level of the program, which is based on only
information collected from the rest of the program.

In particular for dependency injection this would be useful, but also
potentially for other use cases such as generating an automatic route handler
for a server side framework, or possibly ORM applications as well.

Instead of generating declarations, these Aspect Macros would generate Data,
which would be merged/deduplicated in a similar fashion, and could be retreived
_at compile time_ by another macro.

## Other features under consideration

### Allow adding private declarations in phase 3, with an optional key

Instead of having another type of macro, we could possibly just allow any macro
to emit new, private declarations in Phase 3. You would not be able to control
the names of these declarations, and could not guess them in earlier phases.

This new API would have an optional `String? key` argument, or possibly a
`OpaqueKey? key` argument, which would allow you to create deduplicated helpers.

This gives the user control over the key used for deduplication, which has both
advantages and disadvantages.

### Make Aspect Macros run in phase 3

We could allow phase 3 macros to call an API similar to the one described above,
to generate deduplicated helpers. They would not pass a user computed key, but
instead rely on deduplication in the same manner as above.

We could likely still allow cyclic aspect macros, as we would not synchronously
be invoking them.

We could also possibly not allow aspect macros to call other aspect macros.
