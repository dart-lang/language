# Macros

Authors: Jacob MacDonald, Bob Nystrom

Status: **Work In Progress**

## Introduction

The [motivation][] document explains why we are working on static
metaprogramming. This proposal introduces macros to Dart. A **macro** is a piece
of code that can modify other parts of the program at compile time. A **macro
application** invokes the given macro on the declaration it is applied to. The
macro **introspects** over the declaration it was applied to and based on that
**generates code** to modify the declaration or add new ones.

A **macro declaration** is a user-defined Dart class that implements one or more
new built-in macro interfaces. Macros in Dart are written in normal imperative
Dart code. There is not a separate "macro language".

[motivation]: motivation.md

You can think of macros as exposing functionality similar to existing [code
generation tools][codegen], but integrated more fully into the language.

[codegen]: https://dart.dev/tools/build_runner

### Introspection

Most macros don't simply generate new code from scratch. Instead, they add code
to a library based on existing properties of the program. For example, a macro
that adds JSON serialization to a class might look at the fields the class
declares and from that synthesize a `toJson()` method that serializes those
fields to a JSON object.

This means that when a macro executes, it often **introspects** over some part
of the program to look at its existing structure. A macro can look at the
declaration that it is applied to. For example, a macro applied to a class can
see the class's name, superclasses, members, etc. Some of those properties are
type annotations, like the superclass or the return type of a method. From that
type annotation, the macro may be able to traverse to the declaration that the
annotation refers to. In this way, a macro applied to one part of the program
may ultimately access information about distant parts of the program.

Allowing deep introspection like this in cases where a macro needs it while
ensuring that users can understand the system and tools can implement it
efficiently is a central challenge of this proposal.

#### Omitted Type Annotations and Inference

In general, the introspection APIs will only provide exactly what the user has
written for the types of declarations. However, this presents problems when the
type is omitted, and in particular when the type is omitted but a useful type
would be inferred. For example, see this class:

```dart
class Foo extends Bar {
  final inferred = someFunction();

  final String name;

  Foo(this.name, {super.baz});
}

class Bar {
  final String? baz;

  Bar({this.baz});
}
```

When introspecting on the `inferred` field, the `this.name` parameter, or the
`super.baz` parameter, there is no hand written type to use. However, a macro
may need to know the actual inferred type, in order to emit an equivalent type
annotation in generated code elsewhere in the program.

In order to resolve this, there will be a special `OmittedTypeAnnotation`
subtype of `TypeAnnotation`. It will have no fields, and is just a pointer to
the place where the type annotation was omitted.

There are two things you can do with an `OmittedTypeAnnotation`:

- Pass it directly as a part of a `Code` object.
  - This is only allowed after phase one (the types phase). Using an omitted
    type in phase one is not allowed and will cause an exception.
    - Users should be instructed to add a type to the location where the
      omitted type came from in this case. It is guaranteed to be in the same
      file as the macro annotation, so they can always do this.
  - When the final augmentation library is created, the actual type that was
    inferred will be used (or `dynamic` if no type was inferred).
- Explicitly ask to infer the type of it through the builder APIs (only
  available in phase 3).
  - We don't allow augmentations of existing declarations to contribute to
    inference, so in phase 3 type inference can be performed.

This allows you to generate correct signatures for any declarations you need to
create in Phase 1 or 2, without actually performing inference in those phases.
At the same time it allows you to get the inferred type in phase 3, where you
are creating the bodies of functions and may need to know the actual inferred
type (for instance you might want to do something for all fields that implement
a given interface).

The primary limitation of this approach is that you will not be able to inspect
the actual types of declarations where the type was omitted prior to phase 3,
but this situation will also be made very explicit to macro authors.

#### Conditional URI directives

When introspecting on a program, which conditional uri directives are selected
(even transitively) may affect what a macro sees. This means that macros may
produce different code based on the conditions present in these directives and
the compilation environment.

It is necessary that it works this way (as opposed to choosing the default for
instance), because we do not require anything other than the selected URI to be
present during compilation. Even the default URI may be missing.

In particular this complicates the debugging experience, as the analysis
environment in the IDE would ideally match up with the compilation environment
for an app during debugging, otherwise stack traces, breakpoints, etc may not
match up. It is generally anticipated that these situations should be rare,
because typically the APIs exposed from conditional directives are identical.

### Ordering in metaprogramming

Macros can read the user's Dart program and modify it. They are also written in
Dart as part of the same program. When you have lots of macros all looking at
and modifying the same program while it is in the middle of being compiled, it
can be hard to define a coherent compilation and macro expansion order. Can a
macro body call a method generated by another macro? Does a macro that looks at
the fields on a class see the fields generated by some other macro?

The rest of the proposal addresses these specific ordering challenges in detail,
but the basic principles are:

1.  When possible, macro application order is *not* user-visible. Most macro
    applications are isolated from each other. This makes it easier for users to
    reason about them separately, and gives implementations freedom to evaluate
    (or re-evaluate) them in whatever order is most efficient.

1.  When users apply macros to the *same* portions of the program where the
    ordering is important, they can easily *control* that ordering.

In other words, in cases where you care about the order that macros run, you
should be able to control it to get what you want. And in most other cases, the
system should ensure that you don't have to care.

## Macro applications

Macros are applied to declarations using the existing metadata annotation
syntax. For example:

```dart
@MyCoolMacro()
class MyClass {}
```

Here, if the `MyCoolMacro` type is a `macro class`, then the annotation is
treated as an application of the `MyCoolMacro()` macro to the class MyClass.

Macro applications can also be passed arguments, either in the form of
[Code][] expressions, [TypeAnnotation][]s, or certain
types of literal values. See [Macro Arguments](#Macro-arguments) for more
information on how these arguments are handled when executing macros.

Macro applications must always be constructor invocations. It is an error to
annotate a declaration with a constant reference to a macro instance. In the
future we may explore a more concise macro application syntax.

### Code Arguments

Consider this example macro application:

```dart
int get a => 1;
const b = 2;

class SomeClass {
  @Add(1, a + b)
  int addThem(); // Generates: => 1 + a + b;
}
```

Here, `Add` is a macro that takes its arguments as expressions and produces a
function body that adds them using `+` and returns the result.

Because macros are applied at compile time, the arguments are passed to the
macro as objects representing unevaluated expressions. Here, the `Add` macro
receives objects that represent the *literal* `1` and *the expression* `a + b`.
It takes those and composes them into a function body like:

```dart
=> 1 + a + b
```

Most of the time, like here, a macro takes the arguments you pass it and
interpolates them back into code that it generates, so passing the arguments as
code is what you want.

### Type annotation arguments

If you want to be able to introspect on a type passed in as an argument, you can
do that as well, consider the following:

```dart
@GenerateSerializers(MyType)
library my.library;

class MyType {
  final String myField;

  MyType({required this.myField});
}

/// Generated by introspecting on the fields of [MyType].
class MyTypeSerializer implements Serializer<MyType> {
  Map<String, Object?> serialize(MyType instance) => {
    'myField': instance.myField,
  };
}

class MyTypeDeserializer implements Deserializer<MyType> {
  MyType deserialize(Map<String, Object> json) =>
      MyType(myField: json['myField'] as String);
}
```

Here the macro takes an `Identifier` argument, and introspects on it to know
how to generate the desired serialization and deserialization classes.

### Value arguments

Sometimes, though, the macro wants to receive an actual argument value. For
example, a macro for defining vector classes might take the dimension as an
integer and need to know the actual passed integer value at compile time to know
how many fields to define. To support that, macros can also accept arguments as
values. However, only built-in value types (int, bool, etc.) are allowed and
arguments must be *simple literal expressions*.

**TODO**: Metadata annotations currently only allow expression arguments. Do we
want to expand this to allow statements or other grammatical constructs (#1928)?

### Application order

Multiple macros may be applied to the same declaration, or to declarations that
contain one another. For example, you may apply two macros to the same class, or
to a class and a method in the same class. Since those macros may introspect
over the declaration as well as modify it, the order that those macros are
applied can matter.

Fortunately, since they are all applied to the same textual piece of code, the
user can *control* that order. We use syntactic order to control application
order of macros:

*   **Macros are applied to inner declarations before outer ones.** Macros
    applied to members are applied before macros on the surrounding type.
    Macros on top-level declarations are applied before macros on the main
    `library` directive.

*   **Macros applied to the same declaration are applied right to left.** For
    example:

    ```dart
    @Third()
    @Second()
    @First()
    class C {}
    ```

    Here, the macros applied to C are run `First()`, `Second()`, then `Third()`.

*   **Macros are applied to superclasses, mixins, and interfaces first, in**
    **Phase 2** For example:

    ```dart
    @Third()
    class B extends A with C implements D {}

    @Second()
    class A implements C {}

    @First()
    class C {}

    @first
    class D {}
    ```

    Here, the macros on `A`, `C` and `D` run before the macros on `B`, and `C`
    also runs before `A`. But otherwise the ordering is not defined (it is not
    observable).

    This only applies to Phase 2, because it is the only phase where the order
    would be observable. In particular this allows macros running on `B` to see
    any members added to its super classes, mixins, or interfaces, by other
    macros running in phase 2.

Aside from these rules, macro introspection is limited so that evaluation order
is not user visible. For example, if two macros are applied to two methods in
the same class, there is no way for those macros to interfere with each other
such that the application order can be detected.

### Augmentation library structure and ordering

It is important that applying macros in a given library always results in a
consistent augmentation library. In particular, multiple tools should be able to
run the same macros with the same inputs, and get the same augmentation library.
This allows debugging and stack traces to work consistently, and be meaningful
and useful.

We have several rules based around maintaining the consistency of generated
output across tools.

#### Rule #1: Nested augmentations on type declarations are merged

When there are multiple augmentations of the same type declaration, they are
merged into a single `augment <type> {}` block. This is easier for end users to
understand. This includes multiple augmentations of the _same_ declaration, they
should appear as separate declarations within the same type augmentation.

This does result in constantly shifting source offsets between phases, and in
particular throughout Phase 2 of macro expansion, given that some macros can see
the outputs of other macros within that same phase.

For example, if both of these macros add a new declaration to `A`:

```dart
@AddB()
@AddC()
class A {}
```

Then the resulting library should have both declarations merged into one
augmentation of `A` like this:

```dart
augment class A {
  void b() {}
  void c() {}
}
```

Note that we previously considered an "append only" approach, with no merging of
augmentations. The goal was to avoid changing source offsets, but this doesn't
work since later augmentations may need to add additional imports, which would
result in shifting offsets anyways. Since we have to deal with the shifting
offsets either way, we might as well derive user value out of it.

#### Rule #2: Augmentations are sorted by phase, application, then source order

##### Sorting by phase

Augmentations from earlier phases appear before augmentations from later phases:

```dart
@AddMemberB() // Runs in phase 2, adds a member `b` to `A`.
class A {}

@AddTypeD() // Runs in the first phase, creates the class `D`.
class C {}
```

Would result in:

```dart
class D {}

augment class A {
  void b() {}
}
```

##### Sorting by application order

Where an application order is explicitly defined, the augmentations are appended
in that same order as the primary sort:

```dart
@AugmentB() // In phase 3, augments the member `b`.
class A {
  void b() {}

  @AugmentC(); // In phase 3, augments the member `c`
  void c() {}
}
```

Since inner macro applications run first, we get the augmentation of `c` first:

```dart
augment class A {
  augment void c() {}

  augment void b() {}
}
```

##### Sort by source offset of the application

If no order is defined between two macro applications, then their augmentations
are sorted based on the source offset of the macro application.

```dart
class A {
  @AugmentB() // In phase 3, augments the member `b`.
  void b() {}

  @AugmentC(); // In phase 3, augments the member `c`
  void c() {}
}
```

Since there is no defined application order, source order is used for the
augmentation ordering:

```dart
augment class A {
  augment void b() {}
  augment void c() {}
}
```

##### Merge type augmentations together

When augmenting a type declaration, if that type declaration has already been
augmented then the new augmentation(s) are merged into that augmentation per the
first rule. Ordering within that type augmentation follows all of these rules.

This only applies to `augment <type>` declarations and not _new_ type
declarations.

Note that when multiple applications are on the same declaration, there is a
defined order, which is the reverse source offset order.


```dart
@AddTopLevelFoo() // In phase two, adds a top level variable `foo`.
class A {
  @AddC() // In phase 2, augments the member `c`.
  @AugmentB() // In phase 3, augments the member `b`
  void b() {}
}
```

Since an augmentation to `A` is added in phase 2, the augmentation of it's
member `b` in phase 3 is merged into that augmentation, which puts it above the
variable `foo` which was added in phase 2 (this rule takes precedence over other
rules).

```dart
augment class A {
  void c() {} // Added in phase 2, ran before `AddTopLevelFoo()`.
  augment b() {} // Added in phase 3, but merged into the previous augmentation.
}

int foo = 1; // Added in phase 2, after `c` was added to `A`.
```

#### Rule #3: Each augmentation should be separated by one empty line

We need to ensure consistent whitespace across tools, and this follows standard
Dart style, which is to separate declarations with one empty line.

Note that if a given augmentation provides its own empty lines at the start,
these should not be trimmed, and so you may end up with more than one empty line
separating declarations.

In the future, we may decide to run `dart format` or some other lighter weight
formatter on augmentations which would also enforce consistent whitespace.

#### Rule #4: New types are declared separately from their augmentations

If a macro declares a new type and then later augments it, this will result in
separate type declarations. One normal one followed by an augmentation of that
type.

For example, if `MyMacro` defines a type in phase 1 and then augments it in
phase 2 by adding a field and a constructor:

```dart
@MyMacro()
library;
```

Would become:

```dart
@MyMacro()
library;

class A {}

augment class A {
  final int b;

  A(this.b);
}
```

It would arguably be more user friendly if we merged these new declarations from
phase 2 into the original declaration, but there are some technical challenges
with doing so, and we do not merge them today.

### Augmentation library source offsets

Any tool doing macro expansion will necessarily have to manage changing source
offsets throughout the macro expansion process. This is necessary in order to
facilitate a single augmentation library for the end user at the end.

It is likely that a tool would want to initially treat things as multiple
separate augmentations, and then merge them all at the end. This would avoid
parsing the entire augmentation library repeatedly. Although, the import
prefixes for identifiers may change once merged in this mode.

## Phases

Before we can get into how macro authors create macros, there is another
ordering problem to discuss. Imagine you have these two classes for tracking
pets and their humans:

```dart
@JsonSerializable()
class Human {
  final String name;
  final Pet? pet; // Optional, might not have a pet.
}

@JsonSerializable()
class Pet {
  final String name;
  final Human? owner; // Optional, might be feral.
}
```

You want to be able to save these to the cloud, so you use a
`@JsonSerializable()` macro that generates a `toJson()` method on each class the
macro is applied to. You want the methods to look like this:

```dart
class Human {
  ...
  Map<String, Object?> toJson() => {
    'name': name,
    'pet': pet?.toJson(),
  };
}

class Pet {
  ...
  Map<String, Object?> toJson() => {
    'name': name,
    'owner': owner?.toJson(),
  };
}
```

Note that the `pet` and `owner` fields are serialized by recursively calling
their `toJson()` methods. To generate that code, the `@JsonSerializable()` macro
needs to look at the type of each field to see if it declares a `toJson()`
method. The problem is that there is *no* order of macro application that will
give the right result. If we apply `@JsonSerializable()` to Human first, then it
won't call `toJson()` on `pet` because Pet doesn't have a `toJson()` method yet.
We get the opposite problem if we apply the macro to Pet first.

To address this, macros execute in **phases.** Earlier phases declare new types
and declarations while later phases fill them in. This way, we can declare the
existence of *all* of the `toJson()` methods in the above example before
generating the *bodies* of any of those `toJson()` methods where we need to
introspect over the fields.

In each phase, macros only have access to the parts of the program that are
already complete. This ensures that the evaluation order of unrelated macro
applications is not user visible. Each phase produces information accessible to
later phases. As the program is incrementally "pinned down", later phases gain
more introspective power, but have less power to mutate the program.

There are three phases:

### Phase 1: Types

Here, macros contribute new types to the program&mdash;classes, typedefs, enums,
etc. This is the only phase where a macro can introduce a new visible type into
the top level scope.

**Note**: Macro classes _cannot_ be generated in this way, but they can rely on
macro generated declarations for their implementation. This ensures that all
macros can be discovered prior to actually running any macros.

Very little introspective power is provided in this phase. Since other macros
may also be declaring new types, we can't even assume that all top-level
identifiers can be resolved. You can see the *names* of types that are
referenced in the declaration the macro is applied to, but you can't ask if they
are a subtype of a known type. Type hierarchies have not been resolved yet. Even
a type which could be resolved to an existing type might not actually resolve to
that type once macros are done (a new type could be introduced which shadows the
original one).

After this phase completes, all top-level names are declared. Subsequent phases
know exactly which type any named reference resolves to, and can ask questions
about subtype relations.

### Phase 2: Declarations

In this phase, macros declare functions, variables, and members. "Declaring"
here means specifying the name and type signature, but not necessarily the body
of a function or initializer for a variable. It is encouraged to provide a body
(or initializer) if possible, but you can opt to wait until the definition phase
if needed.

When applied to a class, enum, or mixin a macro in this phase can introspect on
all of the members of that class and its superclasses, but it cannot introspect
on the members of other types. For mixins, the `on` type is considered a
superclass and is introspectable. Note that generic type arguments are not
introspectable.

When applied to an extension, a macro in this phase can introspect on all of the
members of the `on` type, as well as its generic type arguments and the bounds
of any generic type parameters for the extension.

TODO: Define the introspection rules for extension types.

### Phase 3: Definitions

In the final phase, macros provide the imperative code to fill in abstract or
external members. Macros in this phase can also wrap existing methods or
constructors, by injecting some code before and/or after those method bodies.
These statements share a scope with each other, but not with the original
function body.

Phase three macros can add new supporting declarations to the surrounding scope,
but these are private to the macro generated code, and never show up in
introspection APIs. These macros can fully introspect on any type reachable from
the declarations they are applied to, including introspecting on members of
classes, etc.

## Macro declarations

Macros are a special type of class, which are preceded by the `macro` keyword,
and have some additional limitations that classes don't have.

This keyword allows compilers (and users) to identify macros at a glance,
without having to check the type hierarchy to see if they implement `Macro`.

See some example macros [here][examples].

[examples]: https://github.com/dart-lang/language/tree/master/working/macros/example

### Macro limitations/requirements

-  All macro constructors must be marked as const.
-  See the [Macro Arguments](#Macro-arguments) section to understand how macro
constructors are invoked, and their limitations.
-  All macros must implement at least one of the `Macro` interfaces.
-  Macros cannot be abstract.
-  Macro classes cannot be generated by other macros.
-  Macro classes cannot contain generic type parameters.
    - It is possible that in the future we could allow some restricted form of
      generic type parameters for macro classes, but it gets tricky because the
      types in the user code instantiating the macro are not necessarily present
      in the macros own transitive imports.

*Note: The Macro API is still being designed, and lives [here][API].*

[API]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api.dart

### Writing a Macro

Every macro interface is a subtype of a root [Macro][] [marker interface][].
There are interfaces for each kind of declaration macros can be applied to:
class, function, etc. Then, for each of those, there is an interface for each
macro phase: type, declaration, and definition. A single macro class can
implement as many of these interfaces as it wants to. This allows a single macro
to participate in multiple phases and to support being applied to multiple kinds
of declarations.

[Macro]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/macros.dart
[marker interface]: https://en.wikipedia.org/wiki/Marker_interface_pattern

Each macro interface declares a single method that the macro class must
implement in order to apply the macro in a given phase on a given declaration.
For example, a macro applied to classes in the declaration phase implements
`ClassDeclarationsMacro` and its `buildDeclarationsForClass` method.

When a Dart implementation executes macros, it invokes these builder methods at
the appropriate phase for the declarations the macro is applied to. Each builder
method is passed two arguments which give the macro the context and capabilities
it needs to introspect over the program and generate code.

### Declaration argument

The first argument to a builder method is an object describing the
declaration it is applied to. This argument contains only essentially the parsed
AST for the declaration itself, and does not include nested declarations.

For example, in `ClassDeclarationsMacro`, the introspection object is a
`ClassDeclaration`. This gives you access to the name of the class and access
to the immediate superclass, as well as any immediate mixins or interfaces,
but _not_ its members or entire class hierarchy.

### Builder argument

The second argument is an instance of a [builder][] class. It exposes both
methods to contribute new code to the program, as well as phase specific
introspection capabilities.

In `ClassDeclarationsMacro`, the builder is a `ClassDeclarationBuilder`. Its
primary method is `declareInClass`, which the macro can call to add a new member
to the class. It also implements the `ClassIntrospector` interface, which allows
you to get the members of the class, as well as its entire class hierarchy.

[builder]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/builders.dart

### Introspection API ordering

Macros may produce code based on the order in which the introspection APIs
return results. For instance when generating a constructor, a macro will likely
just iterate over the fields and create a parameter for each.

We need generated augmentations to be identical on all platforms for all the
same inputs, so we need to have a defined ordering when introspection APIs are
returning lists of declarations.

Therefore, whenever an implementation is returning a list of declarations, they
should always be given in lexicographical order. We use lexicographical order
instead of source text order, so that macro output does not have to be re-ran
when re-ordering members.

### Introspecting on metadata annotations

Prior to macros, most use of metadata annotations in Dart was to guide code
generation tools or static analysis. The tool would look for certain metadata
annotations in order to know how to generate code or produce custom diagnosics.
With macros, many of those metadata annotations would instead either *become*
macros or be *read* by them. The latter means that macros also need to be able
to introspect over non-macro metadata annotations applied to declarations.

For example, a `@JsonSerialization()` class macro might want to look for an
`@unseralized` annotation on fields to exclude them from serialization.

Some macros may need to evaluate the real values of metadata arguments, while
others may only need the ability to emit that same code back into the program.

#### The annotation introspection API

All declarations which can be annotated will have an
`Iterable<MetadataAnnotation> get metadata` getter.

All `MetadataAnnotation` objects have a `Code get code` getter, which gives
access to the annotation as a `Code` object.

In addition, there will be two subtypes of `MetadataAnnotation`:

- `IdentifierMetadataAnnotation`: A simple const identifier, has a single
  `Identifier get identifier` getter.
- `ConstructorMetadataAnnotation`: A const constructor invocation. This will
  have the following getters:
  - `Identifier get type`
  - `Identifier get constructor`
  - `Arguments get arguments`
    - The `Arguments` class will provide access to the positional and named
      arguments as separate `Code` objects.

For any macro which only wants to emit code from annotations back into the
program, these `Code` objects are sufficient.

For a macro which wants to access the actual _value_ of a given argument or
the metadata annotation as a whole, they can evaluate `Code` instances as
constants (see next section).

### Constant evaluation

Macros may want the ability to evaluate constant expressions, in particular
those found as arguments to metadata annotations.

We expose this ability through the `DartObject evaluate(Code code)` API, which
is available in all phases, with the following restrictions:

- No identifier in `code` may refer to a constant which refers to any
  system environment variable, Dart define, or other configuration which is not
  otherwise visible to macros.
- All identifiers in `code` must be defined outside of the current
  [strongly connected component][] (that is, the strongly connected component
  which triggered the current macro expansion).

The `DartObject` API is an abstract representation of an object, which can
represent types which are not visible to the macro itself. It will closely
mirror the [same API in the analyzer][DartObject].

The call to `evaluate` will throw a `ConstantEvaluationException` if the
evaluation fails due to a violation of one of the restrictions above.

[DartObject]: https://pub.dev/documentation/analyzer/latest/dart_constant_value/DartObject-class.html

#### Are macro applications introspectable?

Macro applications share the same syntax as annotations, and users may expect
macros to be able to see the other macros as a result.

For now we are choosing not to expose other macro applications as if they were
metadata. While they do share a syntax they are conceptually different.

#### Modifying metadata annotations

We will not allow modification or removal of existing annotations, in the same
way that we do not allow modification or removal of existing code.

However, there are potentially situations where it would be useful for a macro
to be able to add metadata annotations to existing declarations. These would
then be read in by other macros (or the same macro in a later phase). In
particular this may be useful when composing multiple macros together into a
single macro. That macro may have a different configuration annotation that it
uses, which it then splits up into the specific annotations that the other
macros it uses expect.

However, if we aren't careful then allowing adding metadata in this way would
expose the order in which macros are applied. For this reason metadata which is
added in this way is not visible to any other macros ran in the same phase.

This does have two interesting and possibly unexpected consequences:

- Macros may see different annotations on the same declaration, if they run in
  different phases.
- Metadata on entirely new declarations is visible in the same phase, but
  metadata added to existing declarations is only visible in later phases.

**TODO**: Define the API for adding metadata to existing declarations (#1931).

## Generating code

Macros attach new code to the declaration the macro is applied to by calling
methods on the builder object given to the macro. For example, a
declaration-phase macro applied to a class declaration is given a
[ClassMemberDeclarationBuilder]. That class exposes a
[`declareInClass()`][declareInClass] method that adds the given code to the
class as a new member.

[ClassMemberDeclarationBuilder]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/builders.dart#L93
[declareInClass]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/builders.dart#L95

The code itself is an instance of a special [Code][] class (or one of its
subclasses). This is a first-class object that represents a well-formed piece of
Dart code. We use this instead of bare strings containing Dart syntax because a
code object carries more than just the bare Dart code. In particular, it keeps
track of how identifiers in the code are resolved.

[Code]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/code.dart#L9

Also, when code objects are creating by combining fragments of other code (for
example arguments to macros), the resulting code object may keep track of the
original source locations of each fragment. This way, debuggers and other code
navigation tools can understand where a given piece of generated code came from.

### Code instances

There are subclasses of Code for the various major grammatical categories in
Dart syntax: expression, statement, declaration, etc. These exist mainly to
make APIs like the builder classes that accept code objects easier to use
correctly. We do not expose a separate Code subclass for every single grammar
production in Dart: unary expression, binary expression, etc. An API surface
area that broad becomes very brittle and hard to evolve. We wouldn't want the
Code API itself to prevent us from making future language changes.

**TODO**: Describe the API to create instances of Code classes (#1932).

**TODO**: To make it easier to create Code instances, we are considering adding
something like JavaScript's [tagged template][] syntax to Dart. Then, using
that, we could define templates for various grammar productions like expression
and statement. That would make creating code instances almost as simple as
string literals.

[tagged template]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Template_literals#tagged_templates

The Code objects themselves are also fairly opaque. They are "write-only".
Macros create them and compose them, but the API does not give macros the
ability to tear apart and introspect into the subcomponents and subexpressions
of a given pieces of syntax.

**TODO**: We are considering exposing more properties on Code objects to allow
introspection (#1933).

### Identifiers and resolution

The classic problem in macro systems since they were first invented in Lisp and
Scheme in the 70s is how identifiers are resolved. Because this proposal does
not allow local macros, macros that generate new syntax, or macro applications
inside local block scopes, the problems around scoping are somewhat reduced. But
challenges still remain.

#### Referring to generated declarations

A key use of macros is generating new declarations. Since these declarations
aren't useful if not called, it implies that handwritten code may contain
references to declarations produced by macros. This means that before macros are
applied, code may contain identifiers that cannot be resolved.

This is not an error. Any identifier that can't be resolved before the macro is
applied is allowed to be resolved to a macro-produced identifier after macros
are applied. (You might imagine that we could simply defer *all* identifier
resolution until after macro application is done, but we need to resolve at
least enough identifers to resolve *the macro application annotations
themselves*, and to enable the introspection API to describe known types and
members.)

It is a compile-time error if a macro adds a declaration to a library or class
that collides with an existing declaration (either handwritten or produced by a
macro). This is analogous to the existing error users get if handwritten code
has two colliding declarations.

#### Shadowing declarations

Macros may add member declarations that shadow top-level declarations in the
library. When that happens, we have to choose how references to that shadowed
member resolve. Consider the following example:

```dart
int get x => 1;

@GenerateX()
class Bar {
  // Generated
  int get x => 2;

  // Should this return the top level `x`, or the generated instance getter?
  int get y => x;
}
```

In this situation, resolution is done based on the final macro generated code,
as if it was written by hand. Effectively, this means that resolution of bodies
must be delayed until after macro execution is complete.

This (mostly) avoids the need for resolving method bodies multiple times, and
also means that all macro code could be replaced with a hand-authored library.

##### Constant evaluation, Identifiers, and shadowed declarations

Given that constant evaluation can be attempted in any phase, it is possible for
it to return a _different result_ for the same piece of code between phases. In
particular the types phase and declaration phase may introduce declarations
which shadow previously resolved identifiers from other libraries.

If this happens, it would always cause a constant evaluation failure in the
later phase, since identifiers from the current [strongly connected component][]
are not allowed during const evaluation. This is not enough however to catch all
situations, because a macro may not attempt const evaluation at that point, and
could have previously gotten an incorrect result.

Similarly, a Code object provided as a part of a metadata annotation argument
may have Identifiers which were originally resolved to one declaration, and then
later resolved to a different declaration.

In order to resolve these discrepancies we add this rule:

- **It is a compile time error for a macro to add a declaration which shadows**
  **any previously resolved identifier.**. These errors occur after a macro
  runs, when the compiler is merging in the macro results, and so it is not
  catchable or detectable by macros.

This situation can typically only happen because of one of the above scenarios
surrounding metadata annotations or const evaluation, and can typically be
resolved by adding an import prefix. To force resolution to the generated symbol
in the current library, a library can import itself with a prefix.

#### Resolving identifiers in generated code

When a macro generates code containing an identifier, the identifier must be
resolved in the context of some namespace to determine what declaration it
refers to. It's not enough to simply resolve generated code in the same
namespace where the macro is applied. The macro author may want to, for example,
generate a call to a utility function that the macro author knows about but that
the library applying the macro is unaware of. Or a macro may want to generate
code that creates an instance of some class that is an implementation detail of
the macro and not in scope where the macro is applied.

To support this, there is an `Identifier` subtype of `Code`. An instance of this
class represents an identifier resolved in the context of a known library's
namespace. When the `Identifier` object is inserted into other generated code,
it retains its original resolution.

*A compiler could implement this by generating an import of the library
containing the declaration that the identifier refers to. The compiler adds a
unique prefix to the import and then the identifier emitted as a prefixed
identifier followed by the identifier's simple name.*

Macros also build generated code using strings. Identifiers that appear in bare
strings are resolved where they appear in the generated code, and where that
generated code appears in the library, after all macros in the library have
finished executing. For example, if a macro is generating the body of an
instance method, an identifier in a string used to build that body might resolve
to a local variable declared inside that method, to an instance member on the
surrounding class (which may or may not have been produced by some macro), to a
static method, or to a top level identifier.

If a macro wants to generate code containing an identifier that unambigiously
refers to a top level declaration and can't inadvertently capture a local
variable in surrounding generated code, the macro can create an `Identifier` for
that top level declaration and insert that into the generated code.

**TODO: Define this API. See [here](https://github.com/dart-lang/language/pull/1779#discussion_r683843130).**

[Identifier]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/introspection.dart#L15
[TypeAnnotation]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/introspection.dart#L22

### Generating macro applications

Since macros are regular Dart code and classes, one macro can instantiate and
run the other macro's code directly as part of the first macro's execution. That
allows macros to be directly composed in some cases. But in cases where a macro
in one phase wants to invoke a macro in another phase (including itself), a
macro can generate code containing a macro application. Those in turn expanded
during compilation. This is allowed in two ways:

**TODO**: Consider more direct support for macros that declare and then
implement their own declarations (#1908).

#### Adding macro applications to new declarations

When creating [DeclarationCode][] instances, a macro may generate code which includes
macro applications. These macro applications must be from either the current
phase or a later phase, but cannot be from previous phases.

It is an error for a macro application to be added which would have applied to
its declaration in an earlier phase.

If a macro application is added which runs in the same phase as the current
one, then it is immediately expanded after execution of the current macro,
following the normal ordering rules.

[DeclarationCode]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/code.dart#L37

#### Ordering violations

Both of these mechanisms allow for normal macro ordering to be circumvented.
Consider the following example, where all macros run in the Declaration phase:

```dart
@MacroA()
@MacroB()
class X {
  @MacroC() // Added by `@MacroA()`, runs after both `@MacroB()` and `@MacroA()`
  int? a;

  // Generated by `@MacroC()`, not visible to `@MacroB()`.
  int? b;
}
```

Normally, macros always run "inside-out". But in this case `@MacroC()` runs after
both `@MacroB()` and `@MacroA()` which were applied to the class.

We still allow this because it doesn't cause any ambiguity in ordering, even
though it violates the normal rules. We could instead only allow adding macros
from *later* phases, but that would restrict the functionality in unnecessary
ways.

## Compiling macros

**TODO**: Explain library cycles and compiling to library augmentations.

### Library cycles

Applying a macro involves executing the Dart code inside the body of the macro.
Obviously, that code must be type-checked and compiled before it can be run. To
ensure that the code defining the macro can be compiled before it's applied, we
have the following restrictions:

*   **A macro cannot be applied in the same library where it is defined.** The
    macro must always be defined in some other library that you import into the
    library where it is applied. This way, the library where the macro is
    defined can be compiled first.

*   **There must be no import path from the library where a macro is defined to
    any library where it is used.** Since the library applying the macro *must*
    import the definition, this is another way of saying that there can't be any
    cyclic imports (directly or indirectly) between the library where a macro is
    defined and any library where it is used. This ensures that we can reliably
    compile the library where the macro is defined first because it doesn't
    depend on any of the libraries using the macro.

**TODO**: Instead of the above rules, we are considering a more formal notion of
"[modules]" or "library groups" to enforce this acyclicity.

[modules]: https://github.com/dart-lang/language/tree/master/working/modules

A Dart implementation can enforce this restriction by organizing a program into
**library cycles**. The build package [already does this][build lib cycle]. A
library cycle is a set of libraries containing import cycles. If two libraries
are not in the same cycle, it is guaranteed that there is no cyclic import
between them.

### Ideal compilation process

Here's a (non-normative) illustration of how a Dart implementation could compile
a Dart program containing macro applications:

#### 1. Break the program into library cycles

Starting at the entrypoint library, traverse all imports, exports, and
augmentation imports to collect the full graph of libraries to be compiled.
Calculate the [strongly connected component][]s of this graph. Each component is
a library cycle, and the edges between them determine how the cycles depend on
each other. Sort the library cycles in topological order based on the connected
component graph.

Report an error if macro application and its definition occur in the same
library cycle.

Each library cycle can now be fully compiled separately. When compiling a
library cycle, it is guaranteed that all macros used by the cycle have already
been compiled. Also, any types or other declarations used by that cycle have
either already been compiled, or are defined in that cycle.

[strongly connected component]: https://en.wikipedia.org/wiki/Strongly_connected_component

#### 2. Compile each cycle

Go through the library cycles in topological order. For each cycle, compile all
of its libraries. First, merge in any hand-authored library augmentations into
their libraries. At this point, you have a set of mutually interdependent
libraries. They may contain references to declarations that don't exist because
macros have yet to produce them.

Collect all the metadata annotations which are constructor invocations of
macro classes. Report an error if any application refers to a macro declared in
this cycle, or if any annotation is a reference to a const instance of a macro
class (they must be explicit constructor invocations).

**NOTE**: We may in the future allow constant references to macros in
annotations, or something similar to that, see discussion in
https://github.com/dart-lang/language/issues/1890.

#### 3. Apply macros

In a sandbox environment, likely a separate isolate or process, create an
instance of the corresponding macro class for each macro application. See
[Executing macros](#Executing-macros) for more explanation of how macros are
constructed and how their arguments are handled.

Run all of the macros in phase order (see also
[Application order](#Application-order) for ordering within each phase):

1.  Invoke the corresponding visit method for all macros that implement phase 1
    APIs.

1.  Invoke the corresponding visit method for all macros that implement phase 2
    APIs.

1.  Invoke the corresponding visit method for all macros that implement phase 3
    APIs.

While these are running, the macro will likely call back into the host
environment to introspect over code in the current library cycle or previously
compiled cycles. The introspection API is mostly syntactic and structural: a
macro can walk the members on a class declaration or look at the *name* of a
type annotation without the compiler having to do any resolution or type
checking.

When a macro wants to resolve an identifier in a type annotation, there is an
explicit API for that. When that happens, the implementation attempts to resolve
the identifier and return a reference to the resolved declaration. Macros do not
have introspection access to the imperative code of a library, so that code
doesn't need to be resolved or type-checked at this point.

Meanwhile, the macro is also producing new declarations and definitions. These
are collected and held by the macro processor. When introspecting over code, the
implementation needs to show not just the state of the code on disk, but any of
these new declarations produced previously by macros.

#### 4. Generate an augmentation library

Once all macro applications have finished running, the implementation creates a
new empty augmentation library for each library containing macro applications.
All of the declarations created by macros and held by the processor are now
added to the augmentation.

Entirely new declarations are simply added to the augmentation library as
declarations. Declarations that wrap the original declaration's code are added
as augmenting declarations. If a macro adds members to a type, then the type is
added to the augmentation library as an augmenting type, and the members are
added into that.

**TODO**: How are name collisions from private declarations handled?

The `Code` objects representing the signature and body of the declaration is
serialized to Dart source. `Code` objects created from strings are inserted
verbatim into the augmentation library. It's up to the macro author to take
care when using unqualified identifiers in string-based `Code` objects.

**TODO**: Do we want to find identifiers in string-based `Code` objects and
implicitly scope them somehow?

Instances of the `Identifier` class have special serialization. An import for
library that the identifier resolves to is added to the augmentation with a new
unique prefix identifier. The `Identifier` name is then serialized as a prefixed
identifier for that prefix. (A more sophisticated implementation could reuse
imports when multiple identifiers resolve to the same library, and may choose to
omit the prefix entirely if the resulting identifier will still resolve
correctly.)

This augmentation library may be written on disk in some implementation-defined
location. It should be accessible to users so that it's possible to step into
and debug macro-generated code. It should probably *not* be stored directly next
to their source code. We don't expect users to commit these generated files to
source control.

#### 5. Apply augmentation and compile

Finally, the implementation implicitly applies these macro-generated
augmentation libraries onto their corresponding main libraries. After that, all
of the libraries are fully complete. They should contain no unresolvable
identifiers, even in imperative code, and every declared member should have a
definition. Report an error if that's not true.

Otherwise, all of the libraries in the cycle can be fully compiled and the
implementation can move on to the next cycle. Any macros declared in this cycle
are ready to be loaded and executed when applied in libraries in later cycles.

## Executing macros

To apply a macro, a Dart compiler constructs an instance of the applied macro's
class and then invokes methods that implement macro API interfaces. Then it
disposes of the macro instance. Typically this is all done in a separate isolate
or process from the compiler itself.

Macros are full-featured Dart programs with complete access to the entire Dart
language (but limited access to core libraries). Macros are Turing-complete.

### Macro arguments

Each argument in the metadata annotation for the macro application is converted
to a form that the corresponding constructor on the macro class expects, which
it specifies through parameter types:

*   If the parameter type is `bool`, `double`, `int`, `Null`, `num`, `String`,
    `List`, `Set`, `Map`, `Object`, or `dynamic` (or the nullable forms of any
    of those), then the argument expression must be a constant expression
    containing only boolean, number, null, string, list, set, or map literals.
    Note that `Object` and `dynamic` are allowed as types but the actual values
    must still be of one of the supported types.

    * Any type arguments (inferred or explicit) must be one of the allowed
      parameter types, recursively.

*   If the parameter type is `Code` (or a subtype of `Code`), the argument
    expression is automatically converted to a corresponding `Code` instance.
    These provided code expressions may contain identifiers.

*   If the parameter type is `TypeAnnotation` then a literal type must be
    passed, and it will be converted to a corresponding `TypeAnnotation`
    instance.

Note that this implicit lifting of the argument expression only happens when
the macro constructor is invoked through a macro application. If a macro
class is directly constructed in Dart (for example, in test code for the
macro), then the caller is responsible for creating the Code object.

As usual, it is a compile-time error if the type of any argument value (which
may be a Code object) is not a subtype of the corresponding parameter type.

It is a compile-time error if a macro class constructor invoked by a macro
application has a parameter whose type is not Code, TypeAnnotation, or one of
the aforementioned primitive types (or a nullable type of any of those).

#### Identifier Scope

The following rules apply to any `Identifier` passed as an argument to a macro
application, whether as a part of a `Code` expression or `TypeAnnotation`.

The scope of any `Identifier` is the same as the scope in which the identifier
appears in the source code, which is the same as the argument scope for a
metadata annotation on a declaration. This means:

* Identifiers in macro application arguments may only refer to static and top
  level members.
* They cannot refer to local or instance variables, as those can never be in scope
  where a macro application appears.
* Identifiers referring to static class members may be unqualified if the
  annotation appears on a member of that class.
  * For qualified references, only the unqualified name is visible to the macro.
    When the identifier is interpolated into an augmentation library, it may be
    converted back into a fully qualified reference if needed (although the
    prefix may change, or a prefix may be added). This means all of the
    following examples are supported, and for each you would only see `myMember`
    as the `name` of the identifier:
    - `@MyMacro(some_prefix.myMember)`
    - `@MyMacro(SomeClass.myMember)`
    - `@MyMacro(some_prefix.SomeClass.myMember)`

All identifiers passed to macro constructors must resolve to a real declaration
by the time macro expansion has completed. They may resolve to generated
identifiers, including ones generated by the macro they were passed to,
although that design may be inadvisable.

### Runtime environment

Since macros are executed at compile time directly inside the compiler, they run
in a sandbox that tries to minimize the trouble a poorly (or maliciously)
written macro can cause. A well-behaved macro should not:

*   Reach out to the network or read arbitrary files on the user's machine.
    (Some files can be access by going through the Resource API because the
    user knows those files are permitted.)

*   Consume CPU resources or continue executing code after the macro's work is
    done.

*   Produce different results when run multiple times on the same code. A macro
    should be idempotent, and should always generate the same declarations from
    the same inputs.

*   Use mutable global state to pass objects or information derived from one
    phase to a macro (even itself) running in a later phase.

The macro system is *not* designed to provide hard security guarantees of the
above properties. Users should consider the macros that they apply to be trusted
code.

The restrictions in the following sections encourage the above properties as
much as possible.

### Core library restrictions

Dart code touches the outside world through core libraries. We prevent macros
from interacting with the outside world in unsafe ways by limiting access to
some `dart:` libraries and some operations inside those libraries. These
libraries are *allowed*:

* `dart:async`
* `dart:collection`
* `dart:convert`
* `dart:core`
* `dart:math`
* `dart:typed_data`

All other `dart:` libraries (`dart:io`, `dart:isolate`, etc.) are completely
prohibited. This ensures that macros cannot directly access the file system or
network, spawn processes, access configuration-specific data that would cause it
to produce different output on the same code, etc.

**TODO**: Define "prohibited" more precisely (#1916).

**TODO**: Specify prohibited APIs inside permitted core libraries (#1915).

### Static mutable state

A user should not be able observe the order in which unrelated macro
applications are executed. This makes it easier for macro authors to write
robust macros and for macro users to reason about their macro uses
independently. That order could become visible if separate macro applications
accessed the same static mutable state&mdash;top-level variables and static
fields.

In an ideal world we might run each macro invocation in its own sandbox, with
its own static state, but we don't do that. Instead, we simply state that a well
behaved macro should not use static state in an observable way. Not doing so may
lead to undefined behavior.

For example, it is OK to cache the result of an expensive computation in global
state, assuming the result would always be the same. However it would not be
advisable to cache information pertaining to the observed state of a program.
Global state should also not be used to pass such information between macros, or
the phases of a given macro.

Implementations also reserve the right to clear the global state of a macro at
any time, possibly even at random.

### Platform semantics

Macros execute in an environment which may have different semantics than the
environment the program being compiled targets. For instance, Dart numbers have
different semantics on the web than they do when compiled to native code.

The macro execution environment uses the semantics of the compiler or tool's
host environment, whatever those are. (Since most Dart tools are written in Dart
and compiled to native code, that means integers are usually 64 bits.)

**Note**: This is violates the rule that macros should always generate the same
code given the same input code.

This means that code which executes inside a macro may produce a different
result than the same code executed at runtime if the environments are different.
A macro that pre-computes some value and stores the result in the generated code
may need to take care that the computation isn't affected by the host
environment.

Macros do not have visibility into the target environment, and they can only
detect the host environment using existing mechanisms like `0 is double`.

### Environment variables and configuration

Macros do not have access to the system environment variables, since they do not
have access to `dart:io` where they are exposed. Macros also do not have access
to Dart environment variables (`-D` flags). All`fromEnvironment()` constructors
return their default values.

It would be useful for macros to be able to read environment variables so that
they can generate different code in different build configurations. For example,
a macro could generate logging code when applied in debug mode but skip it in a
release build.

However, configuration-specific macros increase the UX complexity of developer
tools and IDEs significantly since the user needs to be able to select which
configuration they want to view their program as. Making macros
configuration-free allows tools to give users a single, consistent version of
generated code.

## Language and API evolution

### Language versioning

Macros generate code directly into existing libraries, and we want to maintain
the behavior that a library only has one language version. Thus, the language
version of macro generated code is always that of the library it is generating
code _into_.

This means that macros need the ability to ask for the language version of a
given library. This will be allowed through the library introspection class,
which is available from the introspection APIs on all declarations via a
`library` getter.

### API versioning

It is expected that future language changes will require breaking changes to the
macro APIs. For instance you could consider what would happen if we added
multiple return values from functions. That would necessitate a change to many
APIs so that they would support multiple return types instead of a single one.

#### Design goals

* Enable us to make API changes when needed.
* Minimize churn for macro authors - most SDK versions will not be breaking and
  it would be ideal to not ask packages to have super tight SDK constraints.
* Give early and actionable error messages to consumers of macros when a macro
  they are using does not support a new language feature.
* Enable as much forwards/backwards compatibility as possible.

#### Solution: Ship macro APIs as a Pub package

The implementation of this package will always come from the SDK, through a
`dart:_macros` library, which will be exported by this package. The
`dart:_macros` library will be blocked from being imported or exported by any
library other than other `dart:` libraries and this package.

We use a `dart:` library here to ensure that the binaries shipped with the SDK
are compiled with exactly the same version of the API that macros are compiled
with. This ensures the communication protocol between macros and the SDK
binaries are compatible.

This package will have tight upper bound SDK constraints, constrained to the
minor release versions instead of major release versions.

The release/versioning strategy for the package is as follows:

- We will not allow any changes to the macro APIs in patch releases of the SDK,
  even non-breaking changes. The package restricts itself to minor releases and
  not patch releases of the SDK, so these changes would silently be visible to
  users in a way that wasn't versioned through the package.

- When a new version of the Dart SDK is released which **does not have any**
  changes to the macro API, then we will do a patch release of this package
  which simply expands the SDK upper bound to include that version (specifically
  it will be updated to less than the next minor version). For example,
  if version `3.5.0` of the SDK was just released, and it has no changes to the
  macro API, the new upper bound SDK constraint would be `<3.6.0` and the lower
  bound would remain unchanged.

  Since this is only a patch release of this package, all existing packages that
  depend on this package (with a standard version constraint) will support it
  already, so no work is required on macro authors' part to work with the new
  Dart SDK.

- When a new version of the Dart SDK is released which has **non-breaking**
  changes to the macro API, then we will do a minor release of this package,
  which increases the lower bound SDK constraint to the newly released version,
  and the upper bound to less than the next minor release version. For example,
  if version `3.5.0` of the SDK was just released, and it has **non-breaking**
  changes to the macro API, the new SDK constraint would be `>=3.5.0 <3.6.0`.

  Note that only users on the newest SDK will get this new version, but that is
  by design. The new features are being exposed only by the new SDK and are not
  available to older SDKs.

  Since this is only a minor release, all existing packages that depend on this
  package (with a standard version constraint) will support it already, so no
  work is required on macro authors' part to work with the new Dart SDK.

  If a macro author wants to **use** the new features, they must update their
  minimum constraint on this package to the latest version to ensure the new
  features are available.

- When a new version of the Dart SDK includes a **breaking** change to the macro
  API, then we will release a new major version of this package, and update the
  SDK constraints in the same way as non-breaking changes (update both the
  minimum and maximum SDK constraints, so only the current minor version is
  allowed). By default, existing packages containing macros will not accept that
  version of the macro package and thus will not work with the new Dart SDK.

  Authors of packages containing macros will need to test to see if their macro
  is compatible with the latest macro API. If so, they can ship a new patch
  version of their package with a constraint on the macro package that includes
  the new major version as well as the previous major version it's already known
  to work with. If their package is broken by the macro API change, then, they
  will fix their macro and ship a new version of their package with a dependency
  on the macro package that only allows the latest major versions.

This approach has several advantages for macro authors and users, which are
closely aligned with the design goals:

* Fewer releases for macro authors (this package shouldn't have very many
  breaking changes).
* Gives us flexibility with the API when needed.
* Gives early errors if a macro dependency doesn't support the users current
  SDK. The failure will be in the form of a failed version solve.
* Macros can easily depend on wide ranges of this package (if they are
  compatible).

There are some downsides to this approach as well:

* More work for us, we need to consistently prepare these releases for new SDKs.
* Version solve errors can sometimes be very cryptic to understand. This is a
  general problem though, and we will benefit from any improvements in this
  area.
* Dependency overrides on this package won't actually have any affect, which may
  be confusing to users. The API is always dictated by the `dart:` library and
  not the package itself. Note that this is different from `dart_internal`,
  which wraps the `dart:` APIs it exposes. I don't think this would be
  desireable for this use case, but we could see if it is feasible.
* It is possible we could forget to bump the min SDK when altering the internal
  API for the `dart:_macros` package. We should put some sort of check in place
  to help ensure we get this right.

## Resources

Some macros may wish to load resources (such as files). We do want to enable
this, but because macros are untrusted code that runs at analysis time, we
block macros from reading resources outside the scope of the original program.

In order to distinguish whether a resource is "in scope", we use the package
config file. Specifically, we allow access to any resource that exists under
the root URI of any package in the current package config. Note that this may
include resources outside of the `lib` directory of a package - even for
package dependencies - depending on how the package config file is configured.

If the URI points to a symlink it must be followed and the final physical file
location checked to be a valid path under a package root. Otherwise they could
be used to circumvent this check and load a resource that is outside the scope
of the program.

**TODO**: Evaluate whether this restriction is problematic for any current
compilation strategies, such as in bazel, and if so consider alternatives.

Resources are read via a [Uri][]. This may be a `package:` URI, or an absolute
URI of any other form as long as it exists under the root URI of some package
listed in the package config.

[Uri]: https://api.dart.dev/stable/2.13.4/dart-core/Uri-class.html

It is also intuitive for macros to accept a relative URI for resources. In
order to support this macros should compute the absolute URI from the current
libraries URI. This URI is accessible by introspecting on the library of the
declaration that a macro is applied to.

**TODO**: Support for relative URIs in part files (requires a part file
  abstraction)?

**TODO**: Should libraries report their fully resolved URI or the URI that was
used to import them? The latter would mean that files under `lib` could not read
resources outside of `lib`, which has both benefits and drawbacks.

**TODO**: Evaluate APIs for listing files and directories.

**TODO**: Consider adding `RandomAccessResource` API.

The specific API is as follows, and would only be available at compile time:

```dart
/// A read-only resource API for use in macro implementation code.
class Resource {
  /// Either a `package:` URI, or an absolute URI which is under the root of
  /// one or more packages in the current package config.
  final Uri uri;

  /// Creates a resource reference.
  ///
  /// The [uri] must be valid for this compilation, which means that it exists
  /// under the root URI of one or more packages in the package config file.
  ///
  /// Throws an [InvalidResourceException] if [uri] is not valid.
  Resource(this.uri);

  /// Whether or not a resource actually exists at [uri].
  bool get exists;

  /// Read this resource as a stream of bytes.
  Stream<Uint8List> openRead([int? start, int? end]);

  /// Asynchronously reads this resource as bytes.
  Future<Uint8List> readAsBytes();

  /// Synchronously reads this resource as bytes.
  Uint8List readAsBytesSync();

  /// Asynchronously reads this resource as text using [encoding].
  Future<String> readAsString({Encoding encoding = utf8});

  /// Synchronously reads this resource as text using [encoding].
  String readAsStringSync({Encoding encoding = utf8});

  /// Asynchronously reads the resource as lines of text using [encoding].
  Future<List<String>> readAsLines({Encoding encoding = utf8});

  /// Synchronously reads the resource as lines of text using [encoding].
  List<String> readAsLinesSync({Encoding encoding = utf8});
}
```

### Resource invalidation

Resources that are read should be treated as source inputs to the program, and
should invalidate the parts of the program that depended on them when they
change.

When a resource is read during compilation, it should either be cached for
subsequent reads to use or a hash of its contents stored. No two macros should
ever see different contents for the same resource, within the same build.

This implies that the compilers will need to be keeping track of which
resources have been read, and adding a dependency on those resources to the
library. The compilers (or tools invoking the compilers) will then need to
watch these resource files for changes in the same way that they watch source
files today.

This also includes tracking when resources are created or destroyed - so for
instance calling any method on a `Resource` should add a dependency on the
`uri` of that resource, whether it exists or not.

#### build_runner

In build_runner we run the compiler in a special directory and we only copy
over the files we know will be read (transitive dart files). How would we
know which resources to copy over, and more specifically which resources were
read by the compiler?

It is likely that we would need some special configuration from the users here
to make this work, at least a general glob of available resources for a package.

#### bazel

No additional complications, resources will need to be provided as data inputs
to the dart_library targets though.

#### frontend_server

The frontend server will need to communicate back the list of resources that
were depended on. This could likely work similarly to how it reports changes
to the Dart sources (probably just treat them in the same way as source files).

## Limitations

- Macros cannot be applied from within the same library cycle as they are
  defined.

- Macros cannot write arbitrary files to disk, and read them in later. They
  can only generate code into the library where they are applied.
  - **TODO**: Full list of available `dart:` APIs.
  - **TODO**: Design a safe API for read-only access to files.
