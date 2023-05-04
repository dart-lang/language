# Implicit Constructors

Author: Erik Ernst

Status: Draft

Version: 1.0

Experiment flag: implicit-constructors

This document specifies implicit constructors as a kind of member that
static extensions can declare, and it specifies static extensions.

_Implicit constructors_ are factory constructors that take exactly one
argument and have the modifier `implicit`. They allow user-written
conversions to take place implicitly, based on a mismatch between the
actual type of an expression and the type expected by the context.

_Static extensions_ is a mechanism that adds static members and/or factory
constructors to a specified class, the _on-class_ of the static
extension. It could be viewed as a static variant of the existing mechanism
known as extension methods.

The fact that implicit constructors are provided by a static extension
ensures that implicit conversions from a type `S` to a type `T` can be
declared even in the case where neither the declaration of `S` nor the
declaration of `T` can be edited.

## Introduction

Implicit constructors were proposed already several years ago in
[language issue #108][kevmoo proposal], and elsewhere.

[kevmoo proposal]: https://github.com/dart-lang/language/issues/108

The main motivating situation was, and is, that an object of some type `S`
is available, but an object of some other type `T` is required, and the
conversion from `S` to `T` is considered to be a tedious detail that should
occur implicitly.

For example, in a situation where a function `walk` accepts an argument of
type `Distance`, and the static type of `e` is `int`, the invocation
`walk(e)` could be implicitly transformed into `walk(Distance(e))` (or
`walk(const Distance(e))`, if `e` is a constant expression).

The assumption is that the code is more convenient to write _and_ just as
easy or even easier to read when this conversion occurs implicitly.
See the 'Discussion' section for a broader discussion about this topic.

Here is an example:

```dart
class Distance {
  final int value;
  const Distance(this.value);
}

static extension E1 on Distance {
  implicit const factory Distance.fromInt(int i) = Distance;
}

void walk(Distance d) {...}

void main() {
  walk(Distance(1)); // OK, normal invocation.
  walk(1); // Also OK, invokes the constructor in E1 implicitly.
}
```

A static extension declaration is associated with an on-class (as opposed
to a plain extension declaration which is associated with an on-type). In
the example above, the on-class of `E1` is `Distance`.

When the on-class of a static extension declaration is a generic class `G`,
the on-class may be denoted by a raw type `G`, or by a parameterized type
`G<T1, .. Tk>`.

When the on-class is denoted by a raw type, the static extension cannot
declare any constructors. In this case the type arguments of the on-class
are ignored, which is what the `static` members must do anyway.

When the on-class is denoted by a parameterized type `T`, constructors in the
static extension must return an object whose type is `T`.

For example:

```dart
// Omit extension type parameters when the static extension only has static
// members. Type parameters are just noise for static members, anyway.
static extension E2 on Map {
  static Map<K2, V> castFromKey<K, V, K2>(Map<K, V> source) =>
      Map.castFrom<K, V, K2, V>(source);
}

// Declare extension type parameters, to be used by constructors. The
// type parameters can have stronger bounds than the on-class.
static extension E3<K extends String, V> on Map<K, V> {
  factory Map.fromJson(Map<String, dynamic> source) => Map.from(source);
}

var jsonMap = <String, dynamic>{"key": 42};
var typedMap = Map<String, int>.fromJson(jsonMap);
// `Map<int, int>.fromJson(...)` is an error: Violates the bound of `K`.
```

A static extension with type parameters can be specialized for specific
values of specific type arguments by specifying actual type arguments of
the on-class to be types that depend on each other, or types with no type
variables:

```dart
static extension E5<X> on Map<X, List<X>> {
  factory Map.listValue(X x) => {x: [x]};
}

var int2intList = Map.listValue(1); // Inferred as `Map<int, List<int>>`.
// `Map.listValue<int, double>(...)` is an error.

static extension E6<Y> on Map<String, Y> {
  factory Map.fromString(Y y) => {y.toString(): y};
}

var string2int = Map.fromString(true); // Inferred as `Map<String, bool>`.
```

The support for implicit construction is managed via the import
mechanism. A particular static extension `E` containing an implicit
constructor _k_ is accessible if the library that declares `E` is imported,
and `E` is not hidden. Implicit construction only occurs with an accessible
implicit constructor. If several such constructors are accessible, the most
specific one is selected (detailed rules below). If there is no most
specific implicit constructor then a compile-time error occurs.

## Specification

### Syntax

The grammar is modified as follows:

```ebnf
<topLevelDefinition> ::= // Add a new alternative.
    <classDeclaration> |
    <mixinDeclaration> |
    <extensionDeclaration> |
    <staticExtensionDeclaration> | // New alternative.
    <enumType> |
    ...;

<staticExtensionDeclaration> ::= // New rule.
    'static' 'extension' <identifier>? <typeParameters>? 'on' <type>
    '{' (<metadata> <staticExtensionMemberDeclaration>)* '}';

<staticExtensionMemberDeclaration> ::= // New rule.
    'static' <staticExtensionMethodSignature> <functionBody> |
    'implicit'? <staticExtensionConstructor> |
    'static' <staticExtensionVariableDeclaration> ';';

<staticExtensionMethodSignature> ::= // New rule.
    <functionSignature> |
    <getterSignature> |
    <setterSignature>;

<staticExtensionConstructor> ::= // New rule.
    <staticExtensionFactoryConstructorSignature> <functionBody> |
    <staticExtensionRedirectingFactoryConstructorSignature> ';';

<staticExtensionFactoryConstructorSignature> ::= // New rule.
    'factory' <constructorName> <formalParameterList>;

<staticExtensionRedirectingFactoryConstructorSignature> ::= // New rule.
    'const'? 'factory' <constructorName> <formalParameterList> '='
    <constructorDesignation>;

<staticExtensionVariableDeclaration> ::= // New rule.
    ('final' | 'const') <type>? <staticFinalDeclarationList> |
    'late' 'final' <type>? <initializedIdentifierList> |
    'late'? <varOrType> <initializedIdentifierList>;
```

The identifier `implicit` is now mentioned in the grammar, but it is not a
built-in identifier nor a reserved word. *The parser does not need that.*

In a static extension of the form `static extension E on C {...}` where `C`
is an identifier or an identifier with an import prefix, we say that the
on-class of `E` is `C`.

In a static extension of the form `static extension E on C<T1 .. Tk> {...}`
where `C` is an identifier or prefixed identifier, we say that the on-class
of `E` is `C`, and the _constructor return type_ of `E` is `C<T1 .. Tk>`.

In both cases, `E` is an identifer which is optionally followed by a term
derived from `<typeParameters>`.

### Static Analysis

At first, we establish some sanity requirements for a static extension
declaration by specifying several errors.

A compile-time error occurs if the on-class of a static extension does not
resolve to a declaration of a class, a mixin, a mixin class, or an inline
class.

A compile-time error occurs if a static extension has a generic on-class
which is specified as a raw type, and the static extension contains one or
more constructor declarations.

*In other words, if the static extension ignores the type parameters of the
on-class then it can only contain `static` members. Note that if the
on-class is non-generic then it is not a raw type, and the static extension
can contain constructors.*

A compile-time error occurs if a static extension has an on-class which is
specified as a parameterized type `C<T1 .. Tk>`, and the actual type
parameters passed to `C` do not satisfy the bounds declared by `C`.
The static extension may declare one or more type parameters
`X1 extends B1 .. Xs extends Bs`, and these type variables may occur in the
types `T1 .. Tk`. During the bounds check, the bounds `B1 .. Bs` are
assumed for the type variables `X1 .. Xs`.

A compile-time error occurs if a static extension _D_ declares a
constructor with the same name as a constructor in the on-class of _D_.

Static extensions introduce several scopes:

The current scope for the on-class of a static extension declaration _D_
that does not declare any type parameters is the enclosing scope of _D_,
that is the library scope of the current library.

A static extension _D_ that declares type variables introduces a type
variable scope whose enclosing scope is the library scope. The current
scope for the on-class of _D_ is the type variable scope.

A static extension _D_ introduces a body scope, which is the current scope
for the member declarations. The enclosing scope for the body scope is the
type parameter scope, if any, and otherwise the library scope.

Static members in a static extension are subject to the same static
analysis as static members in other declarations. There is one extra rule:
It is a compile-time error if a static member of a static extension has a
name which is also the name of a static member of the on-class.

A factory constructor in a static extension introduces scopes in the same
way as other factory constructor declarations. The return type of the
factory constructor is the constructor return type of the static
extension *(that is, the type in the `on` clause)*.

A static extension _D_ is _accessible_ if _D_ is declared in the current
library, or if _D_ is imported and not hidden.

A static member invocation on a class `C`, of the form `C.m()` or similar,
is resolved by looking up static members in `C` named `m` and looking up
static members of every accessible static extension with on-class `C` and a
member named `m`. An error occurs if fewer than one or more than one
declaration named `m` was found.

Once the invocation has been resolved to a static member declaration, the
static analysis of the invocation proceeds identically for a static member
in a static extension and a static member in a class, mixin, or other
declaration.

Explicit constructor invocations are similar:

A constructor invocation of the form `C<T1 .. Tk>.name(args)` is resolved
by looking up a constructor named `C.name` in the class `C` and in every
accessible static extension with on-class `C`. A compile-time error occurs
if fewer than one or more than one such constructor is found.

If the invocation `C<T1 .. Tk>.name(args)` has been resolved to a
declaration in a static extension _D_ then the type parameters `X1 .. Xs`
of _D_ are found such that the constructor return type of _D_ is 
`C<T1 .. Tk>`. A compile time error occurs if this is not possible.

Otherwise we have a binding of each type variable `Xj`, `j` in `1 .. s`
to a type `Sj`. We say that `S1 .. Ss` is the list of actual type arguments
to _D_ for this invocation of `C.name`.

Implicit invocations of static extension constructors are handled as
follows during static analysis:

An expression can occur in an _assignment position_. This includes being
the right hand side of an assignment, an initializing expression in a
variable declaration, an actual argument in a function or method
invocation, and more.

*This concept is already used to determine whether a coercion like generic
function instantiation is applicable. In this document we rely on this
concept being defined already. Currently it has been implemented, but not
specified.*

If an expression `e` with static type `S` occurs in an assignment position
with context type schema `P`, and `S` is not assignable to the greatest
closure `T` of `P`, and `e` is not subject to any built-in coercion *(at
this time that means generic function instantiation and call method
tear-offs)* then `e` is _potentially subject to implicit construction_
with _source type_ `S` and _target type schema_ `P`.

If an expression `e` is potentially subject to implicit construction with
source type `S` and target type schema `P` then the following steps are
performed:

- Gather every accessible static extension whose constructor return type
  can be instantiated such that it is assignable to the greatest closure of
  `P`. Call this set _M0_
- The above-mentioned instantiation determines a value for all type
  parameters of each static extension, and this determines a signature for
  each constructor in the static extension. Each of these signatures has
  one parameter type *(because they must accept exactly one argument)*.
- Select the constructor with the most special parameter type.
  A compile-time error occurs if no such constructor exists.

Otherwise, let `C.name` be the selected constructor. Then transform `e` to
`C.name(e)` and perform type analysis and inference with context type
schema `P`.

### Dynamic Semantics

The dynamic semantics of static members of a static extension is the same
as the dynamic semantics of other static functions.

The dynamic semantics of an explicit invocation of a constructor in a
static extension is determined by the normal semantics of function
invocation, except that the actual value of the type parameters of the
static extension is as determined by the static analysis.

## Discussion

The language C++ has had a [similar mechanism][C++ implicit conversions]
for many years. It includes the notion of [converting constructors][] and
another notion of user-defined [conversion functions][].

[C++ implicit conversions]: https://en.cppreference.com/w/cpp/language/implicit_conversion
[converting constructors]: https://en.cppreference.com/w/cpp/language/converting_constructor
[conversion functions]: https://en.cppreference.com/w/cpp/language/cast_operator

Scala is another language where implicit conversions have been supported
for a long time, as described [here][Scala implicit conversions].

[Scala implicit conversions]: https://docs.scala-lang.org/tour/implicit-conversions.html

The experience from both C++ and Scala is that implicit conversions need to
be kept simple and comprehensible: It is simply not helpful if arbitrary
typing mistakes anywhere in the code can be implicitly masked by the
introduction of one or more unintended user-defined type conversions.

With that in mind, the implicit conversions proposed here are subject to
some rather strict rules:

- They can only be declared as `implicit` constructors in static
  extensions.
- A static extension needs to be imported directly in order to have any
  effect, and it can be hidden in imports.

Scala even requires that the entity that provides implicit conversions is
explicitly imported (using something similar to `show` in an import). We
could consider doing that, but the current proposal is a little more
permissive.

### Changelog

1.0 - May 3, 2023

* First version of this document released.
