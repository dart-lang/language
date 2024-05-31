# Static Extensions

Author: Erik Ernst

Status: Draft

Version: 1.0

Experiment flag: static-extensions

This document specifies static extensions. This is a feature that supports
the addition of static members and/or factory constructors to an existing
declaration that can have such members, in a way which is somewhat similar
to the addition of instance members using a plain `extension` declaration.

## Introduction

A feature like static extensions was requested already several years ago in
[language issue #723][issue 723], and elsewhere.

[issue 723]: https://github.com/dart-lang/language/issues/723

The main motivation for this feature is that developers wish to add
constructors or static members to an existing class, mixin, enum, or
extension type declaration, but they do not have the ability to directly
edit the source code of said declaration.

This feature allows static members to be declared in static extensions of a
given class/mixin/etc. declaration, and they can be invoked as if they had
been declared in said declaration.

Here is an example:

```dart
class Distance {
  final int value;
  const Distance(this.value);
}

static extension E1 on Distance {
  factory Distance.fromHalf(int half) => Distance(2 * half);
}

void walk(Distance d) {...}

void main() {
  walk(Distance.fromHalf(10));
}
```

A static extension declaration is associated with an _on-class_ (as opposed
to a plain extension declaration which is associated with an on-type). In
the example above, the on-class of `E1` is `Distance`.

When the on-class of a static extension declaration is a generic class `G`,
the on-class may be denoted by a raw type `G`, or by a parameterized type
`G<T1, .. Tk>`.

When the on-class is denoted by a raw type, the static extension cannot
declare any constructors, it can only declare static members. In this case
the type arguments of the on-class are ignored, which is what the `static`
members must do anyway.

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
  factory Map.fromJson(Map<String, Object?> source) => Map.from(source);
}

var jsonMap = <String, Object?>{"key": 42};
var typedMap = Map<String, int>.fromJson(jsonMap);
// `Map<int, int>.fromJson(...)` is an error: Violates the bound of `K`.
```

Another motivation for this mechanism is that it supports constructors of
generic classes whose invocation is only allowed when the given actual type
arguments satisfy some constraints that are stronger than the ones required
by the class itself.

For example, we might have a class `SortedList<X>` where the regular
constructors (in the class itself) require an argument of type
`Comparator<X>`, but a static extension provides an extra constructor that
does not require the `Comparator<X>` argument. This extra constructor would
have a constraint on the actual type argument, namely that it is an `X` such
that `X extends Comparable<X>`.

```dart
class SortedList<X> {
  final Comparator<X> _comparator;
  SortedList(Comparator<X> this._comparator);
  // ... lots of stuff that doesn't matter here ...
}

static extension<X extends Comparable<X>> on SortedList<X> {
  SortedList.ofComparable(): super((X a, X b) => a.compareTo(b));
}
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
    <staticExtensionConstructor> |
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

<constructorNameList> ::=
    <constructorName> (',' <constructorName>)*;
```

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
class, or an extension type.

A compile-time error occurs if a static extension has an on-clause of the
form `on C` where `C` denotes a generic class and no type arguments are
passed to `C` *(i.e., it is a raw type)*, and the static extension contains
one or more constructor declarations.

*In other words, if the static extension ignores the type parameters of the
on-class then it can only contain `static` members. Note that if the
on-class is non-generic then `C` is not a raw type, and the static
extension can contain constructors.*

A compile-time error occurs if a static extension has an on-clause of the
form `on C<T1 .. Tk>`, and the actual type parameters passed to `C` do not
satisfy the bounds declared by `C`.  The static extension may declare one
or more type parameters `X1 extends B1 .. Xs extends Bs`, and these type
variables may occur in the types `T1 .. Tk`. During the bounds check, the
bounds `B1 .. Bs` are assumed to hold for the type variables `X1 .. Xs`.

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
// Assume that `FreshE` is the implicitly induced extra name for `E`.
static extension E on C {
  static void foo() {}
}

void f<E>() {
  // Name clash: type parameter shadows static extension.
  C.foo(); // Resolved as `FreshE.foo()`.
}
```

Tools may report diagnostic messages like warnings or lints in certain
situations. This is not part of the specification, but here is one
recommended message:

A compile-time message is emitted if a static extension _D_ declares a
constructor or a static member with the same name as a constructor or a
static member in the on-class of _D_.

*In other words, a static extension should not have name clashes with its
on-class.*

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
analysis as static members in other declarations.

A factory constructor in a static extension introduces scopes in the same
way as other factory constructor declarations. The return type of the
factory constructor is the constructor return type of the static
extension *(that is, the type in the `on` clause)*.

Type variables of a static extension `E` are in scope in static member
declarations in `E`, but any reference to such type variables in a static
member declaration is a compile-time error. *The same rule applies for
static members of classes, mixins, etc.*

#### Static extension accessibility

A static extension declaration _D_ is _accessible_ if _D_ is declared in
the current library, or if _D_ is imported and not hidden.

*In particular, it is accessible even in the case where there is a name
clash with another locally declared or imported declaration with the same
name.*

#### Invocation of a static member of a static extension

An _explicitly resolved invocation_ of a static member of a static
extension named `E` is an expression of the form `E.m()` (or any other
member access, *e.g., `E.m`, `E.m = e`, etc*), where `m` is a static member
declared by `E`.

*This can be used to invoke a static member of a specific static extension
in order to manually resolve a name clash.*

A static member invocation on a class `C`, of the form `C.m()` (or any
other member access), is resolved by looking up static members in `C` named
`m` and looking up static members of every accessible static extension with
on-class `C` and a member named `m`.

If `C` contains such a declaration then the expression is an invocation of
that static member of `C`, with the same static analysis and dynamic
behavior as before the introduction of this feature.

Otherwise, an error occurs if fewer than one or more than one declaration
named `m` was found. *They would necessarily be declared in static
extensions.*

Otherwise, the invocation is resolved to the given static member
declaration in a static extension named `Ej`, and the invocation is treated
as `Ej.m()` *(this is an explicitly resolved invocation, which is specified
above)*.

#### The instantiated constructor return type of a static extension

We associate a static extension declaration _D_ named `E` with formal type
parameters `X1 extends B1 .. Xs extends Bs` and an actual type argument
list `T1 .. Ts` with a type known as the _instantiated constructor return
type of_ _D_ _with type arguments_ `T1 .. Ts`.

When a static extension declaration _D_ named `E` has an on-clause which is
a non-generic class `C`, the instantiated constructor return type is `C`,
for any list of actual type arguments.

*It is not very useful to declare a type parameter of a static extension
which isn't used in the constructor return type, because it can only be
passed in an explicitly resolved constructor invocation, e.g.,
`E<int>.C(42)`. In all other invocations, the value of such type variables
is determined by instantiation to bound. In any case, the type parameters
are always ignored by static member declarations, they are only relevant to
constructors.*

When a static extension declaration _D_ has no formal type parameters, and
it has an on-type `C<S1 .. Sk>`, the instantiated constructor return type
of _D_ is `C<S1 .. Sk>`. *In this case the on-type is a fixed type (also
known as a ground type), e.g., `List<int>`. This implies that the
constructor return type of D is the same for every call site.*

Finally we have the general case: Consider a static extension declaration
_D_ named `E` with formal type parameters `X1 extends B1 .. Xs extends Bs`
and a constructor return type `C<S1 .. Sk>`. With actual type arguments
`T1 .. Ts`, the instantiated constructor return type of _D_ with type
arguments `T1 .. Ts` is `[T1/X1 .. Ts/Xs]C<S1 .. Sk>`.

#### Explicit invocation of a constructor in a static extension

Explicit constructor invocations are similar to static member invocations,
but they need more detailed rules because they can use the formal type
parameters declared by a static extension.

An _explicitly resolved invocation_ of a constructor named `C.name` in a
static extension declaration _D_ named `E` with `s` type parameters and
on-class `C` can be expressed as `E<S1 .. Ss>.C.name(args)`,
`E.C<U1 .. Uk>.name(args)`, or `E<S1 .. Ss>.C<U1 .. Uk>.name(args)`
(and similarly for a constructor named `C` using `E<S1 .. Ss>.C(args)`,
etc).

A compile-time error occurs if the type arguments passed to `E` violate the
declared bounds. A compile-time error occurs if no type arguments are
passed to `E`, and type arguments `U1 .. Uk` are passed to `C`, but no list
of actual type arguments for the type variables of `E` can be found such
that the instantiated constructor return type of `E` with said type
arguments is `C<U1 .. Uk>`.

*Note that we must be able to choose the values of the type parameters
`X1 .. Xs` such that the instantiated constructor return type is
exactly `C<U1 .. Uk>`, it is not sufficient that it is a subtype thereof,
or that it differs in any other way.*

A compile-time error occurs if the invocation passes actual type arguments
to both `E` and `C`, call them `S1 .. Ss` and `U1 .. Uk`, respectively,
unless the instantiated constructor return type of _D_ with actual type
arguments `S1 .. Ss` is `C<U1 .. Uk>`. In this type comparison, top types
like `dynamic` and `Object?` are considered different, and no type
normalization occurs. *In other words, the types must be equal, not
just mutual subtypes.*

*Note that explicitly resolved invocations of constructors declared in
static extensions are an exception in real code, usable in the case where a
name clash prevents an implicitly resolved invocation. However, implicitly
resolved invocations are specified in the rest of this section by reducing
them to explicitly resolved ones.*

A constructor invocation of the form `C<T1 .. Tm>.name(args)` is partially
resolved by looking up a constructor named `C.name` in the class `C` and in
every accessible static extension with on-class `C`. A compile-time error
occurs if no such constructor is found. Similarly, an invocation of the
form `C<T1 ... Tm>(args)` uses a lookup for constructors named `C`.

If a constructor in `C` with the requested name was found, the pre-feature
static analysis and dynamic semantics apply. *That is, the class always
wins.*

Otherwise, the invocation is partially resolved to a set of candidate
constructors found in static extensions. Each of the candidates _kj_ is
vetted as follows:

Assume that _kj_ is a constructor declared by a static extension _D_ named
`E` with type parameters `X1 extends B1 .. Xs extends Bs` and on-type
`C<S1 .. Sm>`.  Find actual values `U1 .. Us` for `X1 .. Xs` satisfying the
bounds `B1 .. Bs`, such that `([U1/X1 .. Us/Xs]C<S1 .. Sm>) == C<T1 .. Tm>`.
If this fails then remove _kj_ from the set of candidate constructors.
Otherwise note that _kj_ uses actual type arguments `U1 .. Us`.

If all candidate constructors have been removed, or more than one candidate
remains, a compile-time error occurs. Otherwise, the invocation is
henceforth treated as `E<U1 .. Us>.C<T1 .. Tm>.name(args)` (respectively
`E<U1 .. Us>.C<T1 .. Tm>(args)`).

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
`C.name` (or `C`) declared by a static extension named `E`, the invocation
is treated as `E.C.name(args)` (respectively `E.C(args)`).

Otherwise, when there are two or more candidates from static extensions,
an error occurs. *We do not wish to specify an approach whereby `args` is
subject to type inference multiple times, and hence we do not support type
inference for `C.name(args)` in the case where there are multiple distinct
declarations whose signature could be used during the static analysis of
that expression.*

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
This fully determines the dynamic semantics of this feature.

### Changelog

1.0 - May 31, 2024

* First version of this document released.
