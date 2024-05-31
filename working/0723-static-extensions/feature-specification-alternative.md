# Extensions with Static Capabilities

Author: Erik Ernst

Status: Draft

Version: 1.0

Experiment flag: static-extensions

This document specifies extensions with static capabilities. This is a
feature that supports the addition of static members and/or factory
constructors to an existing declaration that can have such members, based
on a generalization of the features offered by `extension` declarations.

## Introduction

A feature like extensions with static capabilities was requested already
several years ago in [language issue #723][issue 723], and elsewhere.

[issue 723]: https://github.com/dart-lang/language/issues/723

The main motivation for this feature is that developers wish to add
constructors or static members to an existing class, mixin, enum, or
extension type declaration, but they do not have the ability to directly
edit the source code of said declaration.

This feature allows static members declared in an `extension` on a given
class/mixin/etc. declaration _D_ to be invoked as if they were static
members of _D_.

Here is an example:

```dart
class Distance {
  final int value;
  const Distance(this.value);
}

extension E1 on Distance {
  factory Distance.fromHalf(int half) => Distance(2 * half);
}

void walk(Distance d) {...}

void main() {
  walk(Distance.fromHalf(10));
}
```

In the case where the on-type of an extension declaration satisfies some
constraints, we say that it is the _on-class_ of the extension.

The enhancements specified for `extension` declarations in this document
are only applicable to extensions that have an on-class, all other
extensions will continue to work exactly as they do today. In the example
above, the on-class of `E1` is `Distance`.

For example:

```dart
// Static members must ignore the type parameters. It may be useful to omit
// the type parameters in the case where every member is static.
extension E2 on Map {
  static Map<K2, V> castFromKey<K, V, K2>(Map<K, V> source) =>
      Map.castFrom<K, V, K2, V>(source);
}

// Type parameters are used by constructors.
extension E3<K extends String, V> on Map<K, V> {
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
`Comparator<X>`, but an extension provides an extra constructor that does
not require the `Comparator<X>` argument. This extra constructor would have
a constraint on the actual type argument, namely that it is an `X` such
that `X extends Comparable<X>`.

```dart
class SortedList<X> {
  final Comparator<X> _comparator;
  SortedList(Comparator<X> this._comparator);
  // ... lots of stuff that doesn't matter here ...
}

extension<X extends Comparable<X>> on SortedList<X> {
  SortedList.ofComparable(): super((X a, X b) => a.compareTo(b));
}
```

An extension with type parameters can be used to constrain the possible
type arguments passed to a constructor invocation:

```dart
extension E4<X> on Map<X, List<X>> {
  factory Map.listValue(X x) => {x: [x]};
}

var int2intList = Map.listValue(1); // Inferred as `Map<int, List<int>>`.
// `Map<int, double>.listValue(...)` is an error.

extension E6<Y> on Map<String, Y> {
  factory Map.fromString(Y y) => {y.toString(): y};
}

var string2bool = Map.fromString(true); // Inferred as `Map<String, bool>`.
Map<String, List<bool>> string2listOfBool = Map.fromString([]);
```

## Specification

### Syntax

The grammar remains unchanged.

However, it is no longer an error to declare a factory constructor in an
extension declaration that has an on-class, be it redirecting or not,
constant or not.  *Such declarations may of course give rise to errors as
usual, e.g., if a redirecting factory constructor redirects to a
constructor that does not exist, or there is a redirection cycle.*

In an extension declaration of the form `extension E on C {...}` where `C`
is an identifier or an identifier with an import prefix that resolves to a
class, mixin, enum, or extension type declaration, we say that the
_on-class_ of the extension is `C`. If `C` resolves to a non-generic class
then we say that the _constructor return type_ of the extension is `C`.

*If `C` resolves to a generic class then the extension does not have a
constructor return type.*

In a extension of the form `extension E on C<T1 .. Tk> {...}`
where `C` is an identifier or prefixed identifier that resolves to a class,
mixin, enum, or extension type declaration, we say that the _on-class_
of `E` is `C`, and the _constructor return type_ of `E` is `C<T1 .. Tk>`.

In all other cases, an extension declaration does not have an on-class.

*For example, an extension whose on-type is a type variable does not have
an on-class, and neither does an extension whose on-type is a function
type.*

### Static Analysis

At first, we establish some sanity requirements for an extension declaration
by specifying several errors.

A compile-time error occurs if an extension has an on-clause of the
form `on C` where `C` denotes a generic class and no type arguments are
passed to `C` *(i.e., it is a raw type)*, and the extension contains
one or more constructor declarations.

Tools may report diagnostic messages like warnings or lints in certain
situations. This is not part of the specification, but here is one
recommended message:

A compile-time message is emitted if a extension _D_ declares a
constructor or a static member with the same name as a constructor or a
static member in the on-class of _D_.

*In other words, an extension should not have name clashes with its
on-class. The warning above is aimed at static members and constructors,
but a similar warning would probably be useful for instance members as
well.*

#### Invocation of a static member of an extension

An _explicitly resolved invocation_ of a static member of an extension
named `E` is an expression of the form `E.m()` (or any other member access,
*e.g., `E.m`, `E.m = e`, etc*), where `m` is a static member declared by
`E`.

*This can be used to invoke a static member of a specific extension in
order to manually resolve a name clash. At the same time, in current Dart
(without the feature which is specified in this document), this is the only 
way we can invoke a static member of an extension, so it may be useful for
backward compatibility reasons.*

A static member invocation on a class `C`, of the form `C.m()` (or any
other member access), is resolved by looking up static members in `C` named
`m` and looking up static members of every accessible extension with
on-class `C` and a static member named `m`.

If `C` contains such a declaration then the expression is an invocation of
that static member of `C`, with the same static analysis and dynamic
behavior as before the introduction of this feature.

Otherwise, an error occurs if fewer than one or more than one declaration
named `m` was found. *They would necessarily be declared in extensions.*

Otherwise, the invocation is resolved to the given static member
declaration in an extension named `Ej`, and the invocation is treated
as `Ej.m()` *(this is an explicitly resolved invocation, which is specified
above)*.

#### The instantiated constructor return type of an extension

We associate an extension declaration _D_ named `E` with formal type
parameters `X1 extends B1 .. Xs extends Bs` and an actual type argument
list `T1 .. Ts` with a type known as the _instantiated constructor return
type of_ _D_ _with type arguments_ `T1 .. Ts`.

When an extension declaration _D_ named `E` has an on-clause which is
a non-generic class `C`, the instantiated constructor return type is `C`,
for any list of actual type arguments.

*It is not very useful to declare a type parameter of an extension
which isn't used in the constructor return type, because it can only be
passed in an explicitly resolved constructor invocation, e.g.,
`E<int>.C(42)`. In all other invocations, the value of such type variables
is determined by instantiation to bound. In any case, the type parameters
are always ignored by static member declarations, they are only relevant to
constructors.*

When an extension declaration _D_ has no formal type parameters, and
it has an on-type `C<S1 .. Sk>`, the instantiated constructor return type
of _D_ is `C<S1 .. Sk>`. *In this case the on-type is a fixed type (also
known as a ground type), e.g., `List<int>`. This implies that the
constructor return type of D is the same for every call site.*

Finally we have the general case: Consider an extension declaration
_D_ named `E` with formal type parameters `X1 extends B1 .. Xs extends Bs`
and a constructor return type `C<S1 .. Sk>`. With actual type arguments
`T1 .. Ts`, the instantiated constructor return type of _D_ with type
arguments `T1 .. Ts` is `[T1/X1 .. Ts/Xs]C<S1 .. Sk>`.

#### Explicit invocation of a constructor in an extension

Explicit constructor invocations are similar to static member invocations,
but they need more detailed rules because they can use the formal type
parameters declared by an extension.

An _explicitly resolved invocation_ of a constructor named `C.name` in a
extension declaration _D_ named `E` with `s` type parameters and on-class
`C` can be expressed as `E<S1 .. Ss>.C.name(args)`, 
`E.C<U1 .. Uk>.name(args)`, or `E<S1 .. Ss>.C<U1 .. Uk>.name(args)` (and
similarly for a constructor named `C` using `E<S1 .. Ss>.C(args)`, etc).

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
extensions are an exception in real code, usable in the case where a
name clash prevents an implicitly resolved invocation. However, implicitly
resolved invocations are specified in the rest of this section by reducing
them to explicitly resolved ones.*

A constructor invocation of the form `C<T1 .. Tm>.name(args)` is partially
resolved by looking up a constructor named `C.name` in the class `C` and in
every accessible extension with on-class `C`. A compile-time error
occurs if no such constructor is found. Similarly, an invocation of the
form `C<T1 ... Tm>(args)` uses a lookup for constructors named `C`.

If a constructor in `C` with the requested name was found, the pre-feature
static analysis and dynamic semantics apply. *That is, the class always
wins.*

Otherwise, the invocation is partially resolved to a set of candidate
constructors found in extensions. Each of the candidates _kj_ is
vetted as follows:

Assume that _kj_ is a constructor declared by a extension _D_ named
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
`C.name` (or `C`) declared by a extension named `E`, the invocation
is treated as `E.C.name(args)` (respectively `E.C(args)`).

Otherwise, when there are two or more candidates from extensions,
an error occurs. *We do not wish to specify an approach whereby `args` is
subject to type inference multiple times, and hence we do not support type
inference for `C.name(args)` in the case where there are multiple distinct
declarations whose signature could be used during the static analysis of
that expression.*

### Dynamic Semantics

The dynamic semantics of static members of an extension is the same
as the dynamic semantics of other static functions.

The dynamic semantics of an explicitly resolved invocation of a constructor
in an extension is determined by the normal semantics of function
invocation, except that the type parameters of the extension are
bound to the actual type arguments passed to the extension in the
invocation.

An implicitly resolved invocation of a constructor declared by a static
extension is reduced to an explicitly resolved one during static analysis.
This fully determines the dynamic semantics of this feature.

### Changelog

1.0 - May 31, 2024

* First version of this document released.
