# Macros

Authors: Jacob MacDonald, Bob Nystrom

Status: **Work In Progress**

- [Introduction](#introduction)
- [Ordering](#ordering)
  - [Macro compilation order](#macro-compilation-order)
  - [Macro application order](#macro-application-order)
  - [Introspection of macro modifications](#introspection-of-macro-modifications)
  - [Complete macro application order](#complete-macro-application-order)
- [Macro phases](#macro-phases)
  - [Phase 1: Type macros](#phase-1-type-macros)
  - [Phase 2: Declaration macros](#phase-2-declaration-macros)
  - [Phase 3: Definition macros](#phase-3-definition-macros)
- [APIs](#apis)
  - [Macro API](#macro-api)
  - [Introspection API](#introspection-api)
  - [Code Building API](#code-building-api)
- [Scoping](#scoping)
- [Limitations](#limitations)

## Introduction

The [motivation](motivation.md) document has context on why we are looking at
static metaprogramming. This proposal introduces macros to Dart. A **macro
declaration** is a user-defined Dart class that implements one or more new
built-in macro interfaces. These interfaces allow the macro class to introspect
over parts of the program and then produce new declarations or modify
declarations. A **macro appplication** tells a Dart implementation to invoke the
given macro on the given code. We use the existing metadata annotation syntax to
apply macros. For example:

```dart
@myCoolMacro
class MyClass {}
```

Here, if `myCoolMacro` resolves to an instance of a class implementing one or
more of the macro interfaces, then the annotation is treated as an application
of the `myCoolMacro` macro to the class MyClass. The macro may then look at
the member declarations in the class, define new members, fill in method bodies,
etc.

You can think of macros as exposing functionality similar to existing [code
generation tools][codegen], but integrated more fully into the language.

[codegen]: https://dart.dev/tools/build_runner

**TODO: Describe scope and limitations of macros. What kinds of things they are
and are not allowed to do and why. Are there simple principles we can use to
define the boundary?**

## Ordering

A Dart program may contain a mixture of macros that introspect over portions of
the Dart program, macro applications that change that Dart program, and macros
are themselves implemented in Dart and thus potentially affected by changes
to the Dart code too. That raises a number of questions about how to compile and
apply macros in a well-defined way.

Our basic principles are:

1.  When possible, macro application order is *not* user-visible. Most macro
    applications are isolated from each other. This makes it easier for users to
    reason about them separately, and gives implementations freedom to evaluate
    (or re-evaluate) them in whatever order is most efficient.

1.  When users apply macros to the *same* portions of the program where the
    ordering does matter, they can easily control that ordering.

Here is how we resolve cases where ordering comes into play:

### Macro compilation order

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

**TODO: Instead of the above rules, we are considering a more formal notion of
"[modules]" or "library groups" to enforce this acyclicity.**

[modules]: https://github.com/dart-lang/language/tree/master/working/modules

### Macro application order

Multiple macros may be applied to the same declaration, or to declarations that
contain one another. For example, you may apply two macros to the same class, or
to a class and a method in the same class. Since those macros may introspect
over the declaration as well as modify it, the order that those macros are
applied is potentially user-visible.

Fortunately, since they are all applied to the same textual piece of code, the
user can *control* that order. We use syntactic order to control application
order of macros:

*   **Macros are applied to inner declarations before outer ones.** Macros on
    class members are applied before macros on the class, macros on top-level
    declarations are applied before a macro on the entire library, etc.

*   **Macros applied to the same declaration are applied right to left.** For
    example:

    ```dart
    @third
    @second
    @first
    class C {}
    ```

    Here, the macros applied to C are run `first`, `second`, then `third`.

Otherwise, macros are constrained so that any other evaluation order is not user
visible. For example, if two macros applied to two methods in the same class,
there is no way for those macros to interfere with each other such that the
application order can be detected.

### Introspection of macro modifications

Imagine you have the following:

```dart
@serialize class Foo {
  Bar bar;
}

class Bar {
  @memoize int three() => 3;
}
```

The `@memoize` macro on Bar adds a field, `_memo`, to the surrounding class to
store the memoized value. The `@serialize` on Foo generates a `toJson()` method
that recursively serializes all of the fields on Foo. Since it does so
recursively, it would end up traversing into and introspecting on the fields of
Bar. When that happens, does the `@serialize` macro see the `_memo` field added
by `@memoize`? The answer depends on which macro runs first. But, since these
are unrelated macros on essentially unrelated declarations, that order shouldn't
be user visible.

Our solution to this is stratify macro application into phases. The
introspection API is restricted so that macros within a phase cannot see any
changes made by other macros in the same phase. The phases are described in
detail below.

### Complete macro application order

When all of these are put together, an idealized compilation and macro
application of a Dart program looks like this:

1.  For each library, ordered topologically by imports:

    1.  For each declaration, with nested declarations ordered first:

        1.  Apply each phase 1 macro to the declaration, from right to left.

    1.  At this point, all top level identifiers can be resolved.

    1.  For each declaration, with nested declarations ordered first:

        1.  Apply each phase 2 macro to the declaration, from right to left.

    1.  At this point, all declarations and their signatures exist. The library
        can be type checked.

    1.  For each declaration, with nested declarations ordered first:

        1.  Apply each phase 3 macro to the declaration, from right to left.

    1.  Now all macros have been applied, all imperative code exists, and the
        library can be completely compiled. Any macros defined in this library
        are ready to be used by later libraries.

## Macro phases

The basic idea is to build the program up in a series of steps. In each phase,
macros only have access to the parts of the program that are already complete,
and produce information for later phases. As the program is incrementally
"pinned down", later phases gain more introspective power, but have less power
to mutate the program.

A single macro class can participate in multiple phases by implementing more
than one of the macro phase interfaces. For example, a macro might declare a new
member in an early phase and then provide its implementation in a later phase.

There are three phases:

### Phase 1: Type macros

Here, macros contribute new types to the program&mdash;classes, typedefs, enums,
etc. This is the only phase where a macro can introduce a new visible name into
the top level scope.

Very little reflective power is provided in this phase. Since other macros
running in parallel may be declaring new types, we can't even assume that all
top-level identifiers can be resolved. You can see the names of types that are
referenced in the declaration the macro is applied to, but you can't ask if they
are a subtype of a known type, type hierarchies have not been resolved yet. Even
a type which could be resolved to an existing type might not actually resolve to
that type once macros are done (a new type could be introduced which shadows the
original one).

After this phase completes, all top-level names are declared. Subsequent phases
know exactly which type any named reference resolves to, and can ask questions
about subtype relations, etc.

### Phase 2: Declaration macros

In this phase, macros declare functions, variables, and members. "Declaring"
here means specifying the name and type signature, but not the body of a
function or initializer for a variable. In other words, macros in this phase
specify the declarative structure but no imperative code.

When applied to a class, a macro can introspect on all of the members of that
class and its superclasses, but they cannot introspect on the members of other
types.

### Phase 3: Definition macros

In the final phase, macros provide the imperative code to fill in abstract or
external members.

Macros in this phase can also wrap existing methods or constructors, by
injecting some code before and/or after those method bodies. These statements
share a scope with each other, but not with the original function body.

Phase three macros can add new supporting declarations to the surrounding
scope, but these are private to the macro generated code, and never show up in
introspection APIs.

These macros can fully introspect on any type reachable from the declarations
they annotate, including introspecting on members of classes, etc.

## APIs

The specific APIs for macros are being prototyped currently, and the docs are
hosted [here][docs].

### Macro API

Every macro is a user-defined class that implements one or more special macro
interfaces. Every macro interface is a subtype of a root [Macro][] type. There
are interfaces for each kind of declaration macros can be applied to — class,
function, etc. Then, for each of those, there is an interface for each macro
phase — type, declaration, and definition.

A single macro class can implement as many of these interfaces as it wants to.
This can allow a single macro to participate in multiple phases and to support
being applied to multiple kinds of declarations.

Here are some direct links to the root interfaces for each phase:

- [TypeMacro][]
- [DeclarationMacro][]
- [DefinitionMacro][]

As an example, the interface you should implement for a macro that runs on
classes in the declaration phase is [ClassDeclarationMacro][].

### Introspection API

The first argument to any method that you implement in your macro is the
introspection object. This is a representation of the declaration that the macro
was applied to.

For example, lets look at the [ClassDeclarationMacro][] API, which has the
following method that you must override:

```dart
class ClassDeclarationMacro implements DeclarationMacro {
  void visitClassDeclaration(
      ClassDeclaration declaration, ClassDeclarationBuilder builder);
}
```

The [ClassDeclaration][] instance you get here provides all the
introspective information to you that is available for classes in the
`declaration` phase.

The `builder` parameter also provides an API that allows you to retrieve an
introspection object for any `Type` object available to the macro at runtime.
The introspection capabilites of these objects are limited to the information
produced by the previous macro phase of macros, similar to the capabilites
provided for type references on the declaration.

### Metadata Annotations

The ability to introspect on metadata annotations is important for macros, as
it is expected to be a common way to configure them. For instance a class level
macro may want some per-declaration configuration, and annotations are an
intuitive way to provide that.

Allowing access to metadata does present some challenges though.

#### Annotations that Require Macro Expansion

This could happen if the annotation class has macros applied to it, or if
some argument(s) to the annotation constructor use macros.

Because macros are not allowed to generate code that shadows an identifier
in the same library, we know that if an annotation class or any arguments to it
could be resolved, then we can assume that resolution is correct.

This allows us to provide an API for macro authors to attempt to instantiate an
annotation in _any phase_. The API may fail (if it requires more macro
expansion to be done), but that is not expected to be a common situation. In
the case where it does fail, users should typically be able to move some of
their code to a separate library (which they import). Then things from that
library can safely be used in annotations in the current library, and reflected
on by macros.

Instantiation must fail if there are any macros left to be expanded on the
annotation class or any arguments to the annotation constructor.

#### Are Macro Applications Introspectable?

Macro applications share the same syntax as annotations, and users may expect
macros to be able to see the other macros as a result.

For now we are choosing not to expose other macro applications as if they were
metadata. While they do share a syntax they are conceptually different.

#### Modifying Metadata Annotations

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

TODO: Define the API for adding metadata to existing declarations.

#### The Annotation Introspection API

We could try to give users access to an actual instance of the annotation, or
we could give something more like the [DartObject][] class from the analyzer.

Since macros may need to introspect on classes that they do not actually
import (or are not transitively available to them), we choose to expose a more
abstract API (similar to [DartObject][]).

TODO: Define the exact API.

### Code Building API

At the root of the API for generating code, are the [Code][] and `*Builder`
classes.

- The [Code][] class and its subtypes are first-class representations of
  pieces of Dart programs, essentially abstract syntax trees.
- The `*Builder` instance is always passed as the second argument to the methods
  you implement in your macro, and is what you use to actually augment the
  program with [Code][].

There is a different type of `*Builder` for each specific type of macro, for
instance if you look at the [DeclarationBuilder][] class, you will see this
interface method `void addToLibrary(Declaration declaration)`. The
[Declaration][] class here is a subtype of [Code][].

Most subtypes of [Code][] require fully syntactically valid code in order to
be constructed, but where you need to build up something in smaller pieces you
can use the [Fragment][] subtype. Any arbitrary String can be passed to this
class, allowing you to build up your code fragments however you like.

### Adding New Macro Applications

Macros are allowed to add new macro applications in two ways:

#### Adding Macro Applications to New Declarations

When creating [Code][] instances, a macro may generate code which includes
macro applications. These macro applications must be from either the current
phase or a later phase, but cannot be from previous phases.

If a macro application is added which implements an earlier phase, that phase
is not ran. This should result in a warning if the macro does not also
implement some phase that will be ran.

If a macro application is added which runs in the same phase as the current
one, then it is immediately expanded after execution of the current macro,
following the normal ordering rules.

#### Adding Macro Applications to Existing Declarations

Macro applications can be added to existing declarations through the `*Builder`
APIs. Macros added in this way are always prepended to the list of existing
macros on the declaration (which makes them run _last_).

Note that macros can already _immediately_ invoke another macro on a given
declaration manually, by simply instantiating the macro and then invoking
it.

TODO: Update the builder apis to allow this.

#### Note About Ordering Violations

Note that both of these mechanisms allow for normal macro ordering to be
circumvented. Consider the following example, where all macros run in the
Declaration phase:

```dart
@macroA
@macroB
class X {
  @macroC // Added by `@macroA`, runs after both `@macroB` and `@macroA`
  int? a; 

  // Generated by `@macroC`, not visible to `@macroB`.
  int? b;
}
```

Normally, macros always run "inside-out". But in this case `@macroC` runs after
both `@macroB` and `@macroC` which were applied to the class.

We still allow this because it doesn't cause any ambiguity in ordering, even
though it violates the normal rules.

We could instead only allow adding macros from _later_ phases, but that would
restrict the functionality in unnecessary ways.

## Scoping

### Resolved identifiers

Macros will likely want to introduce references to identifiers that are not in
the scope of the library in which they are running, but are in the scope of the
macro itself, or possibly even references which are not in scope of either the
macro itself or the library where it is applied.

Even if an identifier is in scope of the library in which the macro is applied
(lets say its exported by the macro library), that identifier could be shadowed
by another identifier in the library.

**TODO**: Investigate other approaches to the proposal below, see discussion
at https://github.com/dart-lang/language/pull/1779#discussion_r683843130.

To enable a macro to safely emit a reference to a known identifier, there is
a `Identifier` subtype of `Code`. This class takes both a simple name for the
identifier (no prefix allowed), as well as a library URI, where that identifier
should be looked up.

The generated code should be equivalent to adding a new import to the library,
with the specified URI and a unique prefix. In the code the identifier will be
emitted with that unique prefix followed by its simple name.

Note that technically this allows macros to add references to libraries that
the macro itself does not depend on, and the users application also may not
depend on. This is discouraged, but not prevented, and should result in an error
if it happens.

### Generated declarations

A key use of macros is to generate new declarations, and handwritten code may
refer to them—it may call macro-generated functions, read macro-generated
fields, construct macro-generated classes, etc. This means that before macros
are applied, code may contain identifiers that cannot be resolved. This is not
an error. Any identifier that can't be resolved before the macro is applied is
allowed to be resolved to a macro-produced identifier after macros are applied.

All the rules below apply only to the library in which a macro is applied—macro
applications in imported libraries are considered to be fully expanded already
and are treated exactly the same as handwritten code.

Macros are not permitted to introduce declarations that directly conflict with
existing declarations in the same library. These rules are the same as if the
code were handwritten.

Macros may also add declarations which shadow existing symbols in the library,
but don't directly conflict. In this case we want to ensure that the intent of
any user written code is always clear. Consider the following example:

```dart
int get x => 1;

@generateX 
class Bar {
  // Generated: int get x => 2;

  // Should this return the top level `x`, or the generated instance getter?
  int get y => x; 
}
```

There are several potential choices to we could make here:

1.  We could say that any identifier that can be resolved before macro
    application keeps its original resolution (so `x` would still resolve to the
    original, top level `x`).
2.  We could re-resolve all identifiers after the macros are applied, which can
    possibly change what they resolve to (in this case `x` would resolve to the
    generated instance getter `x`).
3.  We could make it some kind of error for a macro to introduce an identifier
    that shadows another.
4.  We could make it a compile-time error to *use* an identifier shadowed by one
    produced by a macro.

The first two choices could be very confusing to users, some will expect one
behavior while others expect the other. The third choice would work but might be
overly restrictive. The final option still avoids the ambiguity, and is a bit
more permissive than the third.

It similarly also is not allowed for one macro to produce a declaration that the
identifier resolves to and then another macro to produce another declaration
that then shadows that one. In other words, any hand-authored identifier may be
resolved at any point during macro application, but it may only be resolved
once.

These constraints produce this rule:

*   It is a compile-time error if any hand-authored identifier in a library
    containing a macro application would bind to a different declaration when
    resolved before and after macro expansion in that library. In other words,
    it is a compile-time error if a macro introduces an identifier that shadows
    a handwritten identifier that is used in the same library.

This follows from the general principle that macros should not alter the
meaning of existing code. Adding the getter `x` in the example above shadows the
top level `x`, changing the meaning of the original code.

Note, that if the getter were written as `int get y => this.x;`, then a macro
*would* be allowed to introduce the new getter `x`, because `this.x` could not
previously be resolved.

## Macro Execution Environment

The execution environment for macros is different from that of normal code.
Specifically, we have some semantics that we want to uphold (to the extent
that is feasible) which puts some constraints on the environment.

- No direct access to the host device (except through the `Resource` API).
- No ability to spawn arbitrary processes or isolates.
- Can only run synchronous code.
  - TODO: Evaluate feasibility of this requirement, and the cost/benefit
    tradeoffs involved.
- The ordering of macros in the same phase should not be observable.
- Macros should always generate the same code, regardless of host environment,
  target environment, or non-file based configuration.
  - This means no access to system environment variables, Dart environment
    variables (-D defines), command line arguments, or other such configuration.
  - The "host environment" here refers to the environment in which the macro
    itself is running.

These general principles are what drives the various requirements for the
execution environment in which macros run.

### Access to Core Libraries

Only the core libraries which don't violate the above rules are allowed, the
full list of _allowed_ core libraries is as follows:  

- `dart:async`
  - Note that this library is allowed because it is essentially unavoidable, but
    actually scheduling async work is prohibited.
  - Semantically it should be as if the macro runs in a zone where
    `scheduleMicrotask` throws an `UnsupportedError`.
- `dart:collection`
- `dart:convert`
- `dart:core`
- `dart:math`
- `dart:typed_data`

All other SDK libraries are not available.

### Side Effects

Macros should not be able to observe the order in which they are ran with
respect to other macros in the same phase. If macros touch shared global state
then they would be able to observe the ordering, and may rely on that ordering
in ways that get broken by future changes or are generally unstable.

There are several possible approaches to this problem that are being considered:

1. Don't allow macro code to mutate global state at all.
    - This is probably overly-restrictive, and may be hard to enforce. There are
      some legitimate cases in library code (`package:logging` as an example).
2. Run each macro application in a completely new isolate.
    - Good from a semantics and flexibility perspective, but may be too slow.
3. Reset all static state between macro invocations.
    - Good option if it is feasible on the tooling sie of things and it can be
      fast.
4. Document mutating global state as a bad practice, but don't block it. Give no
   guarantees around static state persistance between macro applications.
    - In practice this would likely be fine, but it isn't ideal. Some authors
      are likely to exploit this in weird ways, and we could get stuck
      maintaining behavior that we don't want to.
    - Would likely be the most performant solution, global objects would be
      shared across macro applications instead of being re-instantiated for
      each.
    - Also the easiest solution, no work required.

**TODO**: Choose a solution.

### Platform Specific Semantics

Macros may execute in different environments which have different semantics than
than the target environment, for instance in the case of numbers. Macros are
executed with the normal semantics of the host environment, whatever those are.

- **Note**: This is a violation of the rule that macros should always generate
  the same code regardless of the host environment.

Macros do not have visibility into the target environment, and they can only
detect the host environment using existing mechanisms (`0 is double` style
checks).

This means that code which executes inside a macro may have a different result
than the same code executed at runtime, if the environments are different.

### Dart Environment Variables

Macros _do not_ have access to the Dart environment variables, and all
`fromEnvironment` constructors will return the default values.

While it could be useful for macros to read environment variables it would
be very problematic for development tools to deal with. Having a single,
consistent version of generated code is more predictable for both tools and
users.

### System Environment Variables

Macros _do not_ have access to the system environment variables, since they do
not have access to `dart:io` where they are exposed.

## Language and API Evolution

### Language Versioning

Macros generate code directly into existing libraries, and we want to maintain
the behavior that a library only has one language version. Thus, the language
version of macro generated code is always that of the library it is generating
code _into_.

This means that macros need the ability to ask for the language version of a
given library. This will be allowed through the library introspection class,
which is available from the introspection apis on all declarations via a
`library` getter.

TODO: Fully define the library introspection api for each phase. 

### API Versioning

TODO: Finalize the approach here.

It is possible that future language changes would require a breaking change to
an existing imperative macro API. For instance you could consider what would
happen if we added multiple return values from functions. That would
necessitate a change to many apis so that they would support multiple return
types instead of a single one.

#### Proposal: Ship Macro APIs as a Pub Package

Likely, this package would only export directly an existing `dart:` uri, but
it would be able to be versioned like a public package, including tight sdk
constraints (likely on minor version ranges). This would work similar to the
`dart:_internal` library.

This approach would involve more work on our end (to release this package with
each dart release). But it would help keep users on the rails, and give us a
lot of flexibility with the API going forward.

## Limitations

- Macros cannot be applied from within the same library cycle as they are
  defined.
  - **TODO**: Explain library cycles, and why they are a problem.
- Macros cannot write arbitrary files to disk, and read them in later. They
  can only generate code into the library where they are applied.
  - **TODO**: Full list of available `dart:` APIs.
  - **TODO**: Design a safe API for read-only access to files.

[Code]: https://jakemac53.github.io/macro_prototype/doc/api/definition/Code-class.html
[ClassDeclaration]: https://jakemac53.github.io/macro_prototype/doc/api/definition/ClassDeclaration-class.html
[ClassDeclarationBuilder]: https://jakemac53.github.io/macro_prototype/doc/api/definition/ClassDeclarationBuilder-class.html
[ClassDeclarationMacro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/ClassDeclarationMacro-class.html
[DartObject]: https://pub.dev/documentation/analyzer/latest/dart_constant_value/DartObject-class.html
[Declaration]: https://jakemac53.github.io/macro_prototype/doc/api/definition/Declaration-class.html
[DeclarationBuilder]: https://jakemac53.github.io/macro_prototype/doc/api/definition/DeclarationBuilder-class.html
[DeclarationMacro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/DeclarationMacro-class.html
[DefinitionMacro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/DefinitionMacro-class.html
[docs]: https://jakemac53.github.io/macro_prototype/doc/api/definition/definition-library.html
[Fragment]: https://jakemac53.github.io/macro_prototype/doc/api/definition/Fragment-class.html
[Macro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/Macro-class.html
[typeDeclarationOf]: https://jakemac53.github.io/macro_prototype/doc/api/definition/DeclarationBuilder/typeDeclarationOf.html
[TypeMacro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/TypeMacro-class.html
