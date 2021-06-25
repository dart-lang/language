# Static Metaprogramming

Authors: Jacob MacDonald, Bob Nystrom

Status: **Work In Progress**

## Motivation

See the [intro](intro.md) document for the motivation for this proposal.

## Overview - Multi-Phase Approach

At a high level, the idea of this proposal is to split macros into three
separate phases. Each phase has different capabilities in terms of both program
introspection, and program modification. As you move through the phases you
generally get more introspective power, but less power to mutate the program.

In general, the introspection apis are limited such that only things produced
by previous phases can be introspected upon. This ensures we always give
accurate and complete information in these apis.

A single macro can run in multiple phases if needed. A common use case for this
is running in an early phase to define the signature of a new declaration, and
then filling in the implementation of that declaration later on when more
introspection power is available.

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
reference is resolved to, and can ask questions about subtype relations, etc.

### Phase 2: Declaration Macros

In this phase, macros can contribute new (non-type) declarations to the program,
these can be new members on classes as well as top level declarations.

When running on classes, these macros can also introspect on the members of the
class that they annotate, as well as the classes in their super chain, but they
*cannot* introspect on the members of other types.

When multiple macros in this phase are applied to the same declaration, they are
able to see the declarations added by previously applied macros, but not later
applied ones (see [Macro Ordering](#macro-ordering)).

### Phase 3: Definition Macros

The primary job of these macros is to fill in implementations of existing
declarations (which must be abstract or external).

They are also allowed to wrap existing methods or constructors, by injecting
some code before and/or after those method bodies. These statements do share
a scope with each other, but not with the original function body.

In addition these macros can add supporting declarations to the surrounding
scope, but these are private to the macro generated code, and never show up in
introspection apis.

These macros can fully introspect on any type reachable from the declarations
they annotate, including introspecting on members of classes, etc.

### Macro Ordering

Macros are applied to inner declarations first - so for instance macros on class
members are applied before macros on the class.

When multiple macros are applied to the same declaration, they are applied right
to left.

Macros applied to different declarations in the same scope can be applied in any
order.

## APIs

The specific apis for macros are being prototyped currently, and the docs are
hosted [here][docs].

### Macro API

All macro interfaces implement the [Macro][Macro] class, so you can follow the
"Implementors" links to see all the available types of macros. Here are some
direct links to the root interfaces for each phase:

- [TypeMacro][TypeMacro]
- [DeclarationMacro][DeclarationMacro]
- [DefinitionMacro][DefinitionMacro]

Each of these has more specific implementations for the specific type of
declaration that they annotate. So for instance the
[ClassDeclarationMacro][ClassDeclarationMacro] is the interface used for macros
that apply to classes, and run in the "declaration" phase.

### Introspection API

The first argument to any method that you override in your macro is the
introspection object. This is a representation of the declaration that was
annotated with the macro.

For example, lets look at the [ClassDeclarationMacro][ClassDeclarationMacro]
API, which has the following method that you must override:

```dart
class ClassDeclarationMacro implements DeclarationMacro {
  void visitClassDeclaration(
      ClassDeclaration declaration, ClassDeclarationBuilder builder);
}
```

The [ClassDeclaration][ClassDeclaration] instance you get here provides all the
introspective information to you that is available for classes in the
`declaration` phase.

The `builder` instances also provide an api that allows you to retrieve an
introspection object for any `Type` object available to the macro itself, so
for instance the [DeclarationBuilder][DeclarationBuilder] class (which
[ClassDeclarationBuilder][ClassDeclarationBuilder] extends), exposes the
[typeDeclarationOf][typeDeclarationOf] api.

### Code Building API

At the root of the API for generating code, are the [Code][Code] and
`*Builder` classes. The `*Builder` instance is always passed as the second
argument to the methods you override in your macro.

In your macro, you will generally use the introspection api you are given in
order to construct the desired [Code][Code], and then pass that to an api from
the builder instance in order to add it to the program.

There is a different type of `*Builder` for each specific type of macro, for
instance if you look at the [DeclarationBuilder][DeclarationBuilder] class, you
will see this interface method `void addToLibrary(Declaration declaration)`.
The [Declaration][Declaration] class here is a subtype of [Code][Code].

Most subtypes of [Code][Code] require fully syntactically valid code in order to
be constructed, but where you need to build up something in smaller pieces you
can use the [Fragment][Fragment] subtype. Any arbitrary String can be passed to
this class, allowing you to build up your code fragments however you like.

## Scoping

**TODO**: Fill in this section with more detail and a real proposal.

Macros will likely want to introduce references to identifiers that are not in
the scope of the library in which they are running, but are in the scope of the
macro itself.

We will want some way of providing an affordance to emit a reference to
something from the macro scope, but in the code generated for the original
library.

We do have the start of something like this already available in the `builder`
api - these have apis to get a reference to a `Type` object. We will want to add
the ability to do the same for any arbitrary identifier, and then the ability
to emit references to these inside of [Code][Code] objects.

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
