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
static extension E4<X> on Map<X, List<X>> {
  factory Map.listValue(X x) => {x: [x]};
}

var int2intList = Map.listValue(1); // Inferred as `Map<int, List<int>>`.
// `Map<int, double>.listValue(...)` is an error.

static extension E6<Y> on Map<String, Y> {
  factory Map.fromString(Y y) => {y.toString(): y};
}

var string2bool = Map.fromString(true); // Inferred as `Map<String, bool>`.
Map<String, List<bool>> string2listOfBool = Map.fromString([]);
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
    <factoryConstructorSignature> <functionBody> |
    <redirectingFactoryConstructorSignature> ';';

<staticExtensionVariableDeclaration> ::= // New rule.
    ('final' | 'const') <type>? <staticFinalDeclarationList> |
    'late' 'final' <type>? <initializedIdentifierList> |
    'late'? <varOrType> <initializedIdentifierList>;
```

The identifier `implicit` is now mentioned in the grammar, but it is not a
built-in identifier nor a reserved word. *The parser does not need that.*

In a static extension of the form `static extension E on C {...}` where `C`
is an identifier or an identifier with an import prefix, we say that the
on-class of the static extension is `C`. If `C` resolves to a non-generic
class then we say that the _constructor return type_ of the static
extension is `C`.

*If `C` resolves to a generic class then the static extension does not have
a constructor return type.*

In a static extension of the form `static extension E on C<T1 .. Tk> {...}`
where `C` is an identifier or prefixed identifier, we say that the on-class
of `E` is `C`, and the _constructor return type_ of `E` is `C<T1 .. Tk>`.

In both cases, `E` is an identifer `id` which is optionally followed by a
term derived from `<typeParameters>`. We say that the identifier `id` is
the _name_ of the static extension. *Note that `T1 .. Tk` above may contain
occurrences of those type parameters.*

### Static Analysis

At first, we establish some sanity requirements for a static extension
declaration by specifying several errors.

A compile-time error occurs if the on-class of a static extension does not
resolve to an enum declaration or a declaration of a class, a mixin, a mixin
class, or an inline class.

A compile-time error occurs if a static extension has an on-clause of the form
`on C` where `C` denotes a generic class and no type arguments are passed to `C`
*(i.e., it is a raw type)*, and the static extension contains one or more
constructor declarations.

*In other words, if the static extension ignores the type parameters of the
on-class then it can only contain `static` members. Note that if the
on-class is non-generic then it is not a raw type, and the static extension
can contain constructors.*

A compile-time error occurs if a static extension has an on-clause of the
form `on C<T1 .. Tk>`, and the actual type parameters passed to `C` do not
satisfy the bounds declared by `C`.  The static extension may declare one
or more type parameters `X1 extends B1 .. Xs extends Bs`, and these type
variables may occur in the types `T1 .. Tk`. During the bounds check, the
bounds `B1 .. Bs` are assumed for the type variables `X1 .. Xs`.

A compile-time error occurs if a static extension _D_ declares a
constructor with the same name as a constructor in the on-class of _D_.
*In other words, a constructor in a static extension can never have a name
clash with a constructor declared by its on-class.*

A compile-time error occurs if a static extension declares an
`implicit` constructor whose formal parameter list accepts a number of
positional paremeters which is different from one, or if it accepts any
named parameters.

Consider a static extension declaration _D_ named `E` which is declared in
the current library or present in any exported namespace of an import
*(that is, _D_ is declared in the current library or it is imported and
not hidden, but it could be imported and have a name clash with some other
imported declaration)*. A fresh name `FreshE` is created, and _D_ is
entered into the library scope with the fresh name.

*This means that a `static extension` declaration gets a fresh name in
addition to the declared name, just like `extension` declarations.*

*This makes it possible to resolve an implicit reference to a static
extension, e.g., an invocation of a static member or constructor declared
by the static extension, even in the case where there is a different
declaration in scope with the same name. For example:*

```dart
static extension E on C { // `FreshE` is an extra name for `E`.
  static void foo() {}
}

void f<E>() {
  // Name clash: type parameter shadows static extension.
  C.foo(); // Resolved as `FreshE.foo()`.
}
```

#### Static extension scopes

Static extensions introduce several scopes:

The current scope for the on-clause of a static extension declaration _D_
that does not declare any type parameters is the enclosing scope of _D_,
that is the library scope of the current library.

A static extension _D_ that declares type variables introduces a type
parameter scope whose enclosing scope is the library scope. The current
scope for the on-clause of _D_ is the type parameter scope.

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

Type variables of a static extension `E` are in scope in static member
declarations in `E`, but any reference to such type variables in a static
member declaration is a compile-time error. *The same rule applies for
static members of classes, mixins, etc.*

#### Static extension accessibility

A static extension _D_ is _accessible_ if _D_ is declared in the current
library, or if _D_ is imported and not hidden.

#### Invocation of a static member of a static extension

An _explicitly resolved invocation_ of a static member of a static
extension `E` *(with zero or more type parameters, which are ignored in
this context)*, is an expression of the form `E.m()` (or any other member
access), where `m` is a static member declared by `E`.

*This can be used to invoke a static member of a specific static extension
in order to manually resolve a name clash.*

A static member invocation on a class `C`, of the form `C.m()` (or any
other member access), is resolved by looking up static members in `C` named
`m` and looking up static members of every accessible static extension with
on-class `C` and a member named `m`. An error occurs if fewer than one or
more than one declaration named `m` was found.

If the invocation has been resolved to a static member declared by the
class `C` then the static analysis and dynamic semantics are the same as in
the pre-feature language.

Otherwise, when the invocation has been resolved to a static member
declaration in a static extension `E`, the invocation is treated as
`E.m()`, which is an invocation of a specific static function, analyzed and
executed as usual.

#### The instantiated constructor return type of a static extension

We associate a static extension `E` with formal type parameters
`X1 extends B1 .. Xs extends Bs` and an actual type argument list
`T1 .. Ts` with a type known as the _instantiated constructor return type
of_ `E` _with type arguments_ `T1 .. Ts`.

When a static extension `E` has an on-clause which is a non-generic class
`C`, the instantiated constructor return type is `C`, for any list of
actual type arguments. *It is not very useful to declare a type parameter
of a static extension which isn't used in the constructor return type,
because it can only be passed in an explicitly resolved constructor
invocation, e.g., `E<int>.C(42)`. In all other invocations, the value of
such type variables is determined by instantiation to bound.*

When a static extension has no formal type parameters, and it has an
on-type `C<S1 .. Sk>`, the instantiated constructor return type is
`C<S1 .. Sk>`. *In this case the on-type is a fixed type (also known as a
ground type), e.g., `List<int>`. The point is that there are no type
variables in the type, and hence it is the same for every call site.*

Consider a static extension `E` with formal type parameters
`X1 extends B1 .. Xs extends Bs` and a constructor return type
`C<S1 .. Sk>`. With actual type arguments `T1 .. Ts`, the instantiated
constructor return type of `E` with type arguments `T1 .. Ts` is
`[T1/X1 .. Ts/Xs]C<S1 .. Sk>`.

#### Explicit invocation of a constructor in a static extension

Explicit constructor invocations are similar to static member invocations,
but they need more detailed rules because they can use the formal type
parameters declared by the static extension.

An _explicitly resolved invocation_ of a constructor named `C.name` in a
static extension `E` with `s` type parameters and on-class `C` can be
expressed as `E<S1 .. Ss>.C.name(args)`, `E.C<U1 .. Uk>.name(args)`, or
`E<S1 .. Ss>.C<U1 .. Uk>.name(args)` (and similarly for a constructor
named `C` using `E<S1 .. Ss>.C(args)` etc).

A compile-time error occurs if the type arguments passed to `E` violate the
declared bounds. A compile-time error occurs if no type arguments are
passed to `E`, and type arguments `U1 .. Uk` are passed to `C`, but no list
of actual type arguments for the type variables of `E` can be found such
that the instantiated constructor return type of `E` with said type
arguments is `C<U1 .. Uk>`.

A compile-time error occurs if the invocation passes actual type arguments
to both `E` and `C`, `S1 .. Ss` and `U1 .. Uk`, respectively, unless the
instantiated constructor return type of `E` with actual type arguments
`S1 .. Ss` is `C<U1 .. Uk>`. In this type comparison, top types like
`dynamic` and `Object?` are considered different, and no type normalization
occurs. *In other words, the types must be identical, not just mutual
subtypes.*

*Note that explicitly resolved invocations of constructors declared in
static extensions are an exception in real code, usable in the case where a
name clash prevents an implicitly resolved invocation. Implicitly resolved
invocations are specified in the rest of this section by reducing them to
explicitly resolved ones. Also note that implicitly resolved invocations is
not the same thing as implicit invocations (which are specified in a later
section).*

A constructor invocation of the form `C<T1 .. Tm>.name(args)` is partially
resolved by looking up a constructor named `C.name` in the class `C` and in
every accessible static extension with on-class `C`. A compile-time error
occurs if no such constructor is found. Similarly, an invocation of the
form `C<T1 ... Tm>(args)` uses a lookup for constructors named `C`.

*It is not possible to find a mixture consisting of one constructor in the
on-class and one or more constructors in static extensions: That's already
a compile-time error at the declarations in the static extension. Hence,
the invocation is resolved to a single constructor in `C`, or it is
partially resolved to a set of constructors in static extensions.*

If the invocation resolves to a constructor in `C`, the pre-feature static
analysis and dynamic semantics apply.

Otherwise, the invocation is partially resolved to a set of candidate
constructors found in static extensions. Each of the candidates _kj_ is
vetted as follows:

Assume that _kj_ is a constructor declared by a static extension `E` with
type parameters `X1 extends B1 .. Xs extends Bs` and on-type `C<S1 .. Sm>`.
Find actual values `U1 .. Us` for `X1 .. Xs` satisfying the bounds `B1
.. Bs`, such that `[U1/X1 .. Us/Xs]C<S1 .. Sm> == C<T1 .. Tm>`.  If this
fails then remove _kj_ from the set of candidate constructors.  Otherwise
note that _kj_ uses actual type arguments `U1 .. Us`.

If all candidate constructors have been removed, or more than one candidate
remains, a compile-time error occurs. Otherwise, the invocation is
henceforth treated as `E<U1 .. Us>.C<T1 .. Tm>.name(args)`.

A constructor invocation of the form `C.name(args)` (respectively
`C(args)`) where `C` resolves to a non-generic class is resolved in the
same manner, with `m == 0`. *In this case, type parameters declared by `E`
will be bound to values selected by instantiation to bound.*

Consider a constructor invocation of the form `C.name(args)` (and similarly
for `C(args)`) where `C` resolves to a generic class. As usual, the
invocation is treated as in the pre-feature language when it resolves to a
constructor declared by the class `C`.

In the case where the context type schema for this invocation fully
determines the actual type arguments of `C`, the expression is changed to
receive said actual type arguments, `C<T1 .. Tm>.name(args)`, and treated
as described above.

In the case where the invocation resolves to exactly one constructor
`C.name` (or `C`) declared by a static extension `E`, the invocation is
treated as `E.C.name(args)` (respectively `E.C(args)`).

Otherwise, when there are two or more candidates from static extensions,
an error occurs. *We do not wish to specify an approach whereby `args` is
subject to type inference multiple times, and hence we do not support type
inference for `C.name(args)` in the case where there are multiple distinct
declarations whose signature could be used during the static analysis of
that expression.*

#### Implicit constructor specificity

Let `E` be a static extension with type parameters
`X1 extends B1 .. Xs extends Bs`
that declares an `implicit` constructor _k_ whose formal parameter has type
`U` *(which may contain some of `X1 .. Xs`)*.

*Note that an `implicit` constructor must always have exactly one formal
parameter.*

Let `T1 .. Ts` be types satisfying the bounds `B1 .. Bs`. We then say that
the _instantiated parameter type_ of the implicit constructor _k_ with
actual type arguments `T1 .. Ts` is `[T1/X1 .. Ts/Xs]U`.


Let `E1` be a static extension with `s` type parameters, let `T1 .. Ts`
be types that satisfy the bounds of `E1`, and assume that _k1_ is an
`implicit` constructor declared by `E1`.
Let `E2` be a static extension with `t` type parameters, let `S1 .. St`
be types that satisfy the bounds of `E2`, and assume that _k2_ is an
`implicit` constructor declared by `E2`.

We then say that _k1_ is _more specific_ than _k2_ with said actual type
arguments iff the instantiated parameter type of _k1_ with actual type
arguments `T1 .. Ts` is a proper subtype of the instantiated parameter type
of _k2_ with the actual type arguments `S1 .. St`.

If the two instantiated parameter types are mutual subtypes then we say
that the two constructors are equally specific.

With a list of extensions `E1 .. En` and corresponding actual type
arguments and implicit constructors _k1 .. km_, we say that the most
specific one is _kj_ iff that constructor with the given type arguments is
more specific than each of the others.

#### Static extension applicability

Let `E` be a static extension with type parameters
`X1 extends B1 .. Xs extends Bs` and constructor return type
`C<T1 .. Tk>`. Let `P` be a context type schema.

Let `f` be a function declared as follows, also known as the 
_applicability function_ of `E`:

```dart
C<T1 .. Tk> f<X1 extends B1 .. Xs extends Bs>() => f();
```

We say that `E` is _applicable with context type schema_ `P` 
_yielding actual type arguments_ `S1 .. Ss` iff type inference of the
invocation `f()` with context type schema `P` yields a list of actual type
arguments `S1 .. Ss` to `f` such that `[S1/X1 .. Ss/Xs]C<T1 .. Tk>` is
assignable to the greatest closure of `P`.

#### Implicit invocation of a constructor in a static extension

A static extension constructor marked with the modifier `implicit` can be
invoked implicitly.

*For example, we can have a declaration `Distance d = 1;`, and it may be
transformed into `Distance d = Distance.fromInt(1);` where
`Distance.fromInt` is an implicit constructor declared in an accessible
static extension with on-class `Distance` whose parameter type is `int`.*

First, we need to introduce the notion of an _assignment position_.
An expression can occur in an assignment position. This includes being
the right hand side of an assignment, an initializing expression in a
variable declaration, an actual argument in a function or method
invocation, and more.

*This concept is already used to determine whether a coercion like generic
function instantiation is applicable. In this document we rely on this
concept being defined already. Currently it has been implemented, but not
specified.*

Assume that an expression `e` occurs in an assignment position with context
type schema `P`. In this situation, type inference is performed on `e` with
context type schema `P`, and the resulting expression `e1` has some type
`T0`. Assume that `e1` is not subject to any built-in coercions *(at this
time this means generic function instantiation or call method tear-off)*,
and `T0` is not assignable to the greatest closure of `P`. In this case we
say that `e` is _potentially subject to implicit construction with source
type_ `T0`.

If an expression `e` is potentially subject to implicit construction with
source type `T0`, the following steps are performed:

- Gather every accessible static extension that declares one or more
  `implicit` constructors, and that is applicable with context type schema
  `P`. Assume that the result is the set `E1 .. En` of static extensions,
  each with an actual type argument list `A1 .. An` *(each `Aj` is a list
  of types, whose length is the same as the type parameter list of `Ej`)*.
  The candidate constructors are then all constructors in `E1 .. En` which
  are marked `implicit`.
- For each candidate constructor _k_, eliminate _k_ from the set of
  candidates if `T0` is not assignable to the instantiated parameter type
  of _k_ with the actual type arguments `Aj` of the static extension `Ej`
  that declares _k_.
- If the set of candidate constructors is empty, a compile-time error
  occurs.
- Otherwise, if none of the candidate constructors is most specific with
  the given actual type arguments of the enclosing static extension, an
  error occurs.
- Otherwise, one specific static extension `Ej` with actual type arguments
  `Aj`, and one constructor _k_ declared by `Ej` is most specific. Let
  `C.name` (respectively `C`) be the name of _k_.
- The expression `e` is then replaced by `Ej<Aj>.C.name(e0)`
  (respectively `Ej<Aj>.C(e0)`).

*Note that no further type inference is applied to this expression: The
static extension `Ej` has received actual type arguments `Aj`, and this
fully determines the type arguments passed to `C`. Finally, `e0` has been
subject to type inference in the first step.*

### Dynamic Semantics

The dynamic semantics of static members of a static extension is the same
as the dynamic semantics of other static functions.

The dynamic semantics of an explicitly resolved invocation of a constructor
in a static extension is determined by the normal semantics of function
invocation, except that the type parameters of the static extension are
bound to the actual type arguments passed to the static extension in the
invocation.

An implicitly resolved invocation of a constructor declared by a static
extension is reduced to an explicitly resolved one during static analysis.
The same is true for implicit invocations of `implicit` constructors.
This fully determines the dynamic semantics of this feature.

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
