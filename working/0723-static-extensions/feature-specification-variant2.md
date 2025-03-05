# Extensions with Static Capabilities

Author: Erik Ernst

Status: Draft

Version: 1.2

Experiment flag: static-extensions

This document specifies extensions with static capabilities. This is a
feature that supports the addition of static members and/or constructors to
an existing declaration that can have such members, based on a
generalization of the features offered by `extension` declarations.

## Introduction

A feature like extensions with static capabilities was requested already
several years ago in [language issue #723][issue 723], and elsewhere.

[issue 723]: https://github.com/dart-lang/language/issues/723

The main motivation for this feature is that developers wish to add
constructors or static members to an existing class, mixin, enum, or
extension type declaration, but they do not have the ability to directly
edit the source code of said declaration.

This feature allows static members and constructors declared in an
`extension` on a given class/mixin/etc. declaration _D_ to be invoked as if
they were static members respectively constructors declared by _D_.

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
constraints, we say that the class/mixin/etc. which is referred in the
on-type is the _on-declaration_ of the extension.

The enhancements specified for `extension` declarations in this document
are only applicable to extensions that have an on-declaration, all other
extensions will continue to work exactly as they do today. In the example
above, the on-declaration of `E1` is `Distance`.

Here is an example where a static member is added to a class:

```dart
// Static members must ignore the type parameters. It may be useful
// to omit the type parameters from the extension in the case where
// every member is static.
extension E2 on Map {
  static Map<K2, V> castFromKey<K, V, K2>(Map<K, V> source) =>
      Map.castFrom<K, V, K2, V>(source);
}
```

An extension with a generic on-declaration _D_ which is a class or an
enumerated type can implicitly inject certain kinds of constructors into
_D_, and they are able to use the type parameters of the extension. For
example:

```dart
extension E3<K extends String, V> on Map<K, V> {
  factory Map.fromJson(Map<String, Object?> source) =>
      Map.from(source);
}

var jsonMap = <String, Object?>{"key": 42};
var typedMap = Map<String, int>.fromJson(jsonMap);
// `Map<int, int>.fromJson(...)` is an error: It violates the
// bound of `K`.
```

This situation is just an abbreviated notation for a declaration where the
constructor declares its own handling of genericity:

```dart
// We could keep the type parameters of the extension, but they are now
// unused because the constructor declares its own type parameters.
extension SameAsE3 on Map {
  factory Map<K, V>.fromJson<K extends String, V>(
    Map<String, Object?> source
  ) => Map.from(source);
}
```

An extension can declare factories and redirecting generative constructors,
but it cannot declare a non-redirecting generative constructor.

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
  SortedList.ofComparable(): this((X a, X b) => a.compareTo(b));
}
```

An extension with type parameters can be used to constrain the possible
type arguments passed to a constructor invocation:

```dart
extension E4<X> on Map<X, List<X>> {
  factory Map.listValue(X x) => {x: [x]};
}

var map = Map.listValue(1); // Inferred as `Map<int, List<int>>`.
// `Map<int, double>.listValue(...)` is an error.

extension E6<Y> on Map<String, Y> {
  factory Map.fromString(Y y) => {y.toString(): y};
}

var map2 = Map.fromString(true); // Infers `Map<String, bool>`.
Map<String, List<bool>> map3 = Map.fromString([]);
```

## Specification

This specification assumes that generic constructors have already been
added to Dart.

### Syntax

The grammar remains unchanged.

However, it is no longer an error to declare a factory constructor,
redirecting or not, or a redirecting generative constructor in an extension
declaration that has an on-declaration (defined later in this section),
and both kinds can be constant or not.

*Such declarations may of course give rise to errors as usual, e.g., if a
redirecting factory constructor redirects to a constructor that does not
exist, or there is a redirection cycle.*

In an extension declaration of the form `extension E on C {...}` where `C`
is an identifier (or an identifier with an import prefix) that denotes a
class, mixin, enum, or extension type declaration, we say that the
_on-declaration_ of the extension is `C`.

If `C` denotes a generic class then `E` is treated as
`extension E on C<T1 .. Tk> {...}` where `T1 .. Tk` are obtained by
instantiation to bound.

In an extension of the form `extension E on C<T1 .. Tk> {...}`  where `C`
is an identifier or prefixed identifier that denotes a class, mixin, enum,
or extension type declaration, we say that the _on-declaration_ of `E` is
`C`.

In an extension of the form `extension E on F<T1 .. Tk> {...}` where `F` is
a type alias whose transitive alias expansion denotes a class, mixin, enum,
or extension type `C`, we say that the _on-declaration_ of `E` is `C`, and
the declaration is treated as if `F<T1 .. Tk>` were replaced by its
transitive alias expansion.

In all other cases, an extension declaration does not have an
on-declaration.

For the purpose of identifying the on-declaration of a given extension, the
types `void`, `dynamic`, and `Never` are not considered to be classes, and
neither are record types or function types.

*Also note that none of the following types are classes:*

- *A type of the form `T?` or `FutureOr<T>`, for any type `T`.*
- *A type variable.*
- *An intersection type*.

*It may well be possible to allow record types and function types to be
extended with constructors that are declared in an extension, but this is
left as a potential future enhancement. It could be useful to be able to
denote a set of specific functions of a given type by declaring them as
static members of an extension on that function type.*

### Static Analysis

At first, we establish some sanity requirements for an extension declaration
by specifying several errors.

It is a compile-time error to declare a constructor with no type parameters
in an extension whose on-type is not regular-bounded, assuming that the
type parameters declared by the extension satisfy their bounds.

*This constructor is desugared into a generic constructor which is
guaranteed to have a compile-time error. As a consequence, it is not
possible to invoke a constructor of an extension passing actual type
arguments (written or inferred) such that the on-type of the extension
is not regular-bounded.*

Tools may report diagnostic messages like warnings or lints in certain
situations. This is not part of the specification, but here is one
recommended message:

A compile-time diagnostic is emitted if an extension _D_ declares a
constructor or a static member with the same basename as a constructor or a
static member in the on-declaration of _D_.

*In other words, an extension should not have name clashes with its
on-declaration. The warning above is aimed at static members and
constructors, but a similar warning would probably be useful for name
clashes with instance members as well.*

#### Invocation of a static member

*The language specification defines the notion of a _member invocation_ in
the section [Member Invocations][], which is used below. This concept
includes method invocations like `e.aMethod<int>(24)`, property extractions
like `e.aGetter` or `e.aMethod` (tear-offs), operator invocations like
`e1 + e2` or `aListOrNull?[1] = e`, and function invocations like `f()`.
Each of these expressions has a _syntactic receiver_ and an _associated
member name_.  With `e.aMethod<int>(24)`, the receiver is `e` and the
associated member name is `aMethod`, with `e1 + e2` the receiver is `e1`
and the member name is `+`, and with `f()` the receiver is `f` and the
member name is `call`. Note that the syntactic receiver is a type literal
in the case where the member invocation invokes a static member. In the
following we will specify invocations of static members using this
concept.*

[Member Invocations]: https://github.com/dart-lang/language/blob/94194cee07d7deadf098b1f1e0475cb424f3d4be/specification/dartLangSpec.tex#L13903

Consider an expression `e` which is a member invocation with syntactic
receiver `E` and associated member name `m`, where `E` denotes an extension
in scope and `m` is a static member declared by `E`. We say that `e` is an
_explicitly resolved invocation_ of said static member of `E`.

*This can be used to invoke a static member of a specific extension in
order to manually resolve a name clash. At the same time, in Dart without
the feature which is specified in this document, this is the only way we
can invoke a static member of an extension (except when it is in scope, see
below), so it can also be useful because it avoids breaking existing code.*

In the following, we assume that `C` denotes a type introducing membered
declaration _D_ (that is, a class, a mixin class, a mixin, an enum, or an
extension type declaration). `C` may be a type identifier, or it may be of
the form `prefix.id` where `prefix` and `id` are type identifiers, `prefix`
denotes an import prefix, and `id` denotes said type introducing membered
declaration in the namespace of that prefix.

Consider an expression `e` which is a member invocation with syntactic
receiver `C` and an associated member name `m`. Assume that `m` is a static
member declared by _D_. The static analysis and dynamic semantics of this
expression is the same as in Dart before the introduction of this feature.

*In other words, existing invocations of static members will continue to
have the same meaning as they had before this feature was introduced.*

When _D_ declares a static member whose basename is the basename of `m`,
but _D_ does not declare a static member named `m` or a constructor named
`C.m`, a compile-time error occurs. *This is the same behavior as in
pre-feature Dart. It's about "near name clashes" involving a setter.*

In the case where _D_ does not declare any static members whose basename is
the basename of `m`, and _D_ does not declare any constructors named `C.m2`
where `m2` is the basename of `m`, let _M_ be the set containing each
accessible extension whose on-declaration is _D_, and whose static members
include one with the name `m`, or which declares a constructor named `C.m`.

*If _D_ does declare a constructor with such a name `C.m2` then the given
expression is not a static member invocation. This case is described in a
section below.*

Otherwise *(when _D_ does not declare such a constructor)*, an error occurs
if _M_ is empty, or _M_ contains more than one member.

*In other words, no attempt is made to disambiguate static member
invocations based on their signature or the on-type of the enclosing
extension declaration.*

Otherwise *(when no error occurred)* _M_ contains exactly one element.
Assume that it is an extension `E` that declares a static member named
`m`. The invocation is then treated as `E.m()` *(this is an explicitly
resolved invocation, which is specified above)*.

Otherwise *(when `E` does not declare such a static member)*, _M_ will
contain exactly one element which is a constructor named `C.m`. This is not
a static member invocation, and it is specified in a section below.

In addition to the member invocations specified above, it is also possible
to invoke a static member of the enclosing declaration based on lexical
lookup. This case is applicable when an expression in an extension
declaration resolves to an invocation of a static member of the enclosing
extension.

*There is nothing new in this treatment of lexically resolved invocations.*

#### Declarations of constructors in extensions

This proposal relies on the [generic constructor proposal][]. In
particular, this proposal uses concepts and definitions from the generic
constructor proposal, and it is assumed that generic constructors are
supported by the underlying Dart language.

[generic constructor proposal]: https://github.com/dart-lang/language/pull/4265

With this proposal, it is also supported to declare a generic constructor
in an extension, with the same syntax as in a class and in other type
introducing membered declarations.

It is a compile-time error if an extension declares a generic constructor
which is non-redirecting and generative. *These constructors are only
supported inside the type introducing membered declaration of whose type
they are creating instances.*

It is a compile-time error if an extension declaration _D_ declares a
generic constructor whose name is `C` (which includes declarations using
`C.new`) or `C.name` for some identifier `name`, if _D_ does not have an
on-declaration, or the name of the on-declaration is not `C`. Note that `C`
may be an identifier, or an identifier which is prefixed by an import
prefix.

An extension can declare a constructor which is not generic, that is, it
does not declare any formal type parameters, and the constructor return
type does not receive any actual type arguments.

If an extension declaration _D_ named `E` declares a non-generic
constructor _D1_ and the on-declaration of _D_ is non-generic then _D1_ is
treated as a generic constructor that declares zero type parameters and
passes zero actual type arguments to the constructor return type.

*In other words, these constructors get the same treatment as generic
constructors, except that the type inference step is a no-op.*

If an extension declaration _D_ named `E` declares a non-generic
constructor _D1_ and the on-declaration of _D_ is generic then _D1_ is
treated as a generic constructor that declares exactly the same type
parameters as _D_, and it passes exactly the same actual type arguments to
the constructor return type as the ones that are passed to the
on-declaration in the on-type.

*For example:*

```dart
extension E1<X, Y> on C<X, List<Y>, int> {
  C.name(X x, Iterable<Y> ys): this(x, ys, 14);
  // The previous line has the same meaning as the next line:
  C<X, List<Y>, int>.name<X, Y>(X x, Iterable<Y> ys): this(x, ys, 14);
}

extension E2<X, Y> on D { // D is non-generic.
  D.new(X x, Y y);
  // Same as:
  D.new<X, Y>(X x, Y y);
}
```

#### Resolution of a constructor in an extension

Assume that `E` denotes an extension declaration _D_ with on-declaration
_D1_ named `C`, and assume that _D_ declares a constructor whose name is
`C`.

In that case an invocation of the form `E.new<TypeArguments>(arguments)` or
the form `E.new(arguments)` is a fully resolved invocation of said
constructor declaration.

Similarly, if _D_ declares a constructor whose name is `C.name` then an
invocation of the form `E.name<TypeArguments>(arguments)` or
`E.name(arguments)` is a fully resolved invocation of said constructor
declaration.

*This just means that there is no doubt about which constructor declaration
named `C` respectively `C.name` is denoted by this invocation.*

If this invocation does not include actual type arguments and the denoted
constructor declares one or more type parameters then the invocation is
subject to type inference in the same manner as an invocation of a generic
constructor which is declared in a type introducing membered declaration
*(e.g., a class)*.

Fully resolved invocations of constructors declared in extensions are not
expected to be common in actual source code. However, such invocations can
be used in order to resolve name clashes when multiple extensions are
accessible and two or more of them declare a constructor with the same
name, or one declares a constructor named `C.name` and another declares a
static member named `name`. Also, they define the semantics of extension
declared constructors with other forms, because those other forms are
reduced to the fully resolved form.

The forms `E<TypeArguments>.name(arguments)` and
`E<TypeArguments1>.name<TypeArguments2>(arguments)` are compile-time
errors when `E` denotes an extension.

*Consider the case where the extension declares type parameters and has a
generic on-declaration, and the constructor does not declare any type
parameters and does not pass any actual type arguments to the class: It
would be misleading to allow the extension as such to accept actual type
arguments in the same way as the class name in an invocation of a generic
constructor: The extension may declare a different number of type
parameters than the class, and it may not pass them directly (e.g., the
class might declare `<X, Y>` and the extension could declare `<X extends
num>` and pass `<X, List<X>>` to the class in its on-type). It would also
be misleading to allow the extension as such to receive actual type
arguments matching the declared type parameters of the extension, because
those type arguments should be passed after the period: they are being
passed to the constructor.*

*Consider the case where the constructor declares its own type parameters:
In this case it certainly does not make sense to pass any type parameters
to the extension as such.*

Consider an instance creation expression of the form
`C<TypeArguments1>.name<TypeArguments2>(arguments)`, where
`<TypeArguments1>` and `<TypeArguments2>` may be absent. Assume that `C`
denotes a type introducing membered declaration _D_ (where `C` may include
an import prefix). Assume that _D_ does not declare a constructor named
`C.name`.

Let _M_ be the set of accessible extensions with on-declaration _D_ that
declare a constructor named `C.name` or a static member named `name`.

A compile-time error occurs if _M_ includes extensions with constructors as
well as static members.

Otherwise, if _M_ only includes static members then this is not an instance
creation expression, it is a static member invocation and it is specified
in an earlier section.

Otherwise, _M_ only includes extensions containing constructors with the
requested name. A compile-time error occurs if _M_ is empty, or _M_
contains two or more elements. Otherwise, the invocation denotes an
invocation of the constructor named `C.name` which is declared by
the extension declaration that _M_ contains.

*Note that no attempt is made to determine that some constructors are "more
specific" or "less specific", it is simply a conflict if there are multiple
constructors with the requested name in the accessible extensions.*

### Dynamic Semantics

The dynamic semantics of static members of an extension is the same
as the dynamic semantics of other static functions.

The dynamic semantics of an explicitly resolved invocation of a constructor
in an extension is determined by the normal semantics of generic
constructor invocations.

An implicitly resolved invocation of a constructor declared by a static
extension is resolved as an invocation of a specific constructor in a
specific extension as described in the previous section. 

The semantics of the constructor invocation is the same for a generic
constructor which is declared in the type introducing membered declaration
*(at "home")* and for a constructor which is declared in an extension.

### Changelog

1.2 - Mar 5, 2025

* Change the text to rely on generic constructor declarations, rather
  than introducing a new mechanism which is only used with extensions.

1.1 - Aug 21, 2024

* Extensive revision of this document based on thorough review.

1.0 - May 31, 2024

* First version of this document released.
