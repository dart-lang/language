# Static Metaprogramming

Authors: Jacob MacDonald, Bob Nystrom

Status: **Work In Progress**

## Motivation

See the [intro](intro.md) document for the motivation for this proposal.

## Usage

To a user, macros are essentially "active" metadata annotations that do some
processing at compile time to the declaration they are applied to.

```dart
@myCoolMacro
class MyClass {}
```

This syntax is familiar, and it already exists, so there isn't a compelling
motivation to invent new syntax for macro applications.

This also allows for intuitive configuration of macros via their constructor,
while simultaneously not allowing them to have mutable internal state which
we also want.

## Implementation Overview - Multi-Phase Approach

At a high level the idea is to build the program up in a series of steps with
macro phases interleaved between them. At each phase, macros only have access
to the parts of the program that are already complete, and can produce
information for later phases. Later phases generally get more introspective
power, but less power to mutate the program.

In general, the introspection APIs are limited such that only things produced
by previous phases can be introspected upon. This ensures we always give
accurate and complete information in these APIs.

A macro can contribute code in multiple phases if needed. A common usecase for
this is running in an early phase to define the signature of a new declaration,
and then filling in the implementation of that declaration in a later phase when
more introspection power is available.

When a macro adds a new declaration, it may also add a macro application to that
declaration, but only if that macro runs in a *later* phase than the current
one.

### Phase 1: Type Macros

In this phase, macros are allowed to contribute entirely new types to the
program. These could come in the form of classes, typedefs, enums, etc.

Since new types can be contributed to the program in this phase, very little
reflective power is provided to these macros. You can see the names of types
that are referenced in the declaration for instance, but you can't ask if they
are a subtype of a known type, because we don't know how the types will resolve
yet. Even a type which could be resolved to an existing type might not actually
resolve to that type once macros are done (a new type could be introduced which
shadows the original one).

Once this phase completes, all subsequent phases know exactly which type any
named reference is resolved to, and can ask questions about subtype relations,
etc.

### Phase 2: Declaration Macros

In this phase, macros can contribute new function, variable, and member
declarations to the program.

When applied to a class, a macro can introspect on the members of that class and
its superclasses, but they cannot introspect on the members of other types.

When multiple macros are applied to the same declaration, they are able to see
the declarations added by previously applied macros, but not later applied ones
(see [Macro Ordering](#macro-ordering)).

### Phase 3: Definition Macros

The primary job of these macros is to fill in implementations of existing
declarations (which must be abstract or external).

They are also allowed to wrap existing methods or constructors, by injecting
some code before and/or after those method bodies. These statements do share
a scope with each other, but not with the original function body.

In addition these macros can add supporting declarations to the surrounding
scope, but these are private to the macro generated code, and never show up in
introspection APIs.

These macros can fully introspect on any type reachable from the declarations
they annotate, including introspecting on members of classes, etc.

### Macro Ordering

Macros are applied to inner declarations first - so for instance macros on class
members are applied before macros on the class.

When multiple macros are applied to the same declaration, they are applied right
to left.

By design, users can't observe the order that macros on different declarations
are applied.

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

The `builder` parameter also provides an api that allows you to retrieve an
introspection object for any `Type` object available to the macro at runtime.
The introspection capabilites of these objects are limited to the information
produced by the previous macro phase of macros, similar to the capabilites
provided for type references on the declaration.

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

## Scoping

**TODO**: Fill in this section with more detail and a real proposal.

Macros will likely want to introduce references to identifiers that are not in
the scope of the library in which they are running, but are in the scope of the
macro itself.

We will want some way of providing an affordance to emit a reference to
something from the macro scope, but in the code generated for the original
library.

We do have the start of something like this already available in the `builder`
api - these have APIs to get a reference to a `Type` object. We will want to add
the ability to do the same for any arbitrary identifier, and then the ability
to emit references to these inside of [Code][] objects.

## Limitations

- Macros cannot be applied from within the same library cycle as they are
  defined.
  - **TODO**: Explain library cycles, and why they are a problem.
- Macros cannot write arbitrary files to disk, and read them in later. They
  can only generate code into the library where they are applied.
  - **TODO**: Full list of available `dart:` apis.
  - **TODO**: Design a safe api for read-only access to files.

[Code]: https://jakemac53.github.io/macro_prototype/doc/api/definition/Code-class.html
[ClassDeclaration]: https://jakemac53.github.io/macro_prototype/doc/api/definition/ClassDeclaration-class.html
[ClassDeclarationBuilder]: https://jakemac53.github.io/macro_prototype/doc/api/definition/ClassDeclarationBuilder-class.html
[ClassDeclarationMacro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/ClassDeclarationMacro-class.html
[Declaration]: https://jakemac53.github.io/macro_prototype/doc/api/definition/Declaration-class.html
[DeclarationBuilder]: https://jakemac53.github.io/macro_prototype/doc/api/definition/DeclarationBuilder-class.html
[DeclarationMacro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/DeclarationMacro-class.html
[DefinitionMacro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/DefinitionMacro-class.html
[docs]: https://jakemac53.github.io/macro_prototype/doc/api/definition/definition-library.html
[Fragment]: https://jakemac53.github.io/macro_prototype/doc/api/definition/Fragment-class.html
[Macro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/Macro-class.html
[typeDeclarationOf]: https://jakemac53.github.io/macro_prototype/doc/api/definition/DeclarationBuilder/typeDeclarationOf.html
[TypeMacro]: https://jakemac53.github.io/macro_prototype/doc/api/definition/TypeMacro-class.html
