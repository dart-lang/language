# Static Extensions

Author: Erik Ernst

Status: Draft

Version: 1.1

Experiment flag: static-extensions

This document specifies static extensions. This is a feature that supports
the addition of static members and/or constructors to an existing
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

A static extension declaration is associated with an _on-declaration_ (as
opposed to a plain extension declaration which is associated with an
on-type). In the example above, the on-declaration of `E1` is `Distance`.

When the on-declaration of a static extension declaration is a generic
class `G`, the on-declaration may be denoted by a raw type `G`, or by a
parameterized type `G<T1, .. Tk>`.

When the on-declaration is denoted by a raw type, the static extension
cannot declare any constructors, it can only declare static members. In
this case the type arguments of the on-declaration are ignored, which is
what the `static` members must do anyway.

When the on-declaration is denoted by a parameterized type `T`,
constructors in the static extension must return an object whose type is
`T`.

For example:

```dart
// Omit extension type parameters when the static extension only
// has static members. Type parameters are just noise for static
// members, anyway.
static extension E2 on Map {
  static Map<K2, V> castFromKey<K, V, K2>(Map<K, V> source) =>
      Map.castFrom<K, V, K2, V>(source);
}

// Declare extension type parameters, to be used by constructors.
// The type parameters can have stronger bounds than the
// on-declaration.
static extension E3<K extends String, V> on Map<K, V> {
  factory Map.fromJson(Map<String, Object?> source) =>
      Map.from(source);
}

var jsonMap = <String, Object?>{"key": 42};
var typedMap = Map<String, int>.fromJson(jsonMap);

// But `Map<int, int>.fromJson(...)` is an error: It violates the
// bound of `K`.
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
  SortedList.ofComparable(): this((X a, X b) => a.compareTo(b));
}
```

A static extension with type parameters can be specialized for specific
values of specific type arguments by specifying actual type arguments of
the on-declaration to be types that depend on each other, or types with no
type variables:

```dart
static extension E4<X> on Map<X, List<X>> {
  factory Map.listValue(X x) => {x: [x]};
}

var int2intList = Map.listValue(1); // `Map<int, List<int>>`.
// `Map<int, double>.listValue(...)` is an error.

static extension E6<Y> on Map<String, Y> {
  factory Map.fromString(Y y) => {y.toString(): y};
}

var string2bool = Map.fromString(true); // `Map<String, bool>`.
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
    'static' 'extension' <identifier>? <typeParameters>?
    'on' <type>
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
```

In a static extension of the form `static extension E on C {...}` where `C`
is an identifier or an identifier with an import prefix, we say that the
on-declaration of the static extension is `C`.

If `C` denotes a non-generic class, mixin, mixin class, or extension
type then we say that the _constructor return type_ of the static extension
is `C`.

If `C` denotes a generic declaration then `E` is treated as
`static extension E on C<T1 .. Tk> {...}`
where `T1 .. Tk` are obtained by instantiation to bound.

In a static extension of the form `static extension E on C<T1 .. Tk> {...}`
where `C` is an identifier or prefixed identifier, we say that the
on-declaration of `E` is `C`, and the _constructor return type_ of `E` is
`C<T1 .. Tk>`.

In both cases, `E` is an identifer `id` which is optionally followed by a
term derived from `<typeParameters>`. We say that the identifier `id` is
the _name_ of the static extension. *Note that `T1 .. Tk` above may contain
occurrences of those type parameters.*

### Static Analysis

At first, we establish some sanity requirements for a static extension
declaration by specifying several errors.

A compile-time error occurs if the on-declaration of a static extension
does not resolve to an enum declaration or a declaration of a class, a
mixin, a mixin class, or an extension type.

A compile-time error occurs if a static extension has an on-clause of the
form `on C` where `C` denotes a generic class and no type arguments are
passed to `C` *(i.e., it is a raw type)*, and the static extension contains
one or more constructor declarations.

*In other words, if the static extension ignores the type parameters of the
on-declaration then it can only contain `static` members. Note that if the
on-declaration is non-generic then `C` is not a raw type, and the static
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

A compile-time diagnostic is emitted if a static extension _D_ declares a
constructor or a static member with the same basename as a constructor or a
static member in the on-declaration of _D_.

*In other words, a static extension should not have name clashes with its
on-declaration. The warning above is aimed at static members and
constructors, but a similar warning would probably be useful for name
clashes with instance members as well.*

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

A constructor in a static extension introduces scopes in the same way as
other constructor declarations. The return type of the constructor is the
constructor return type of the static extension *(that is, the type in the
`on` clause)*.

Type variables of a static extension `E` are in scope in static member
declarations in `E`, but any reference to such type variables in a static
member declaration is a compile-time error. *The same rule applies for
static members of classes, mixins, etc.*

#### Static extension accessibility

A static extension declaration _D_ is _accessible_ if _D_ is declared in
the current library, or if _D_ is imported and not hidden.

*In particular, it is accessible even in the case where there is a name
clash with another locally declared or imported declaration with the same
name. This is also true if _D_ is imported with a prefix. Similarly, it is
accessible even in the case where _D_ does not have a name, if it is
declared in the current library.*

#### Invocation of a static member

*The language specification defines the notion of a _member invocation_ in
the section [Member Invocations][], which is used below. This concept
includes method invocations like `e.aMethod<int>(24)`, property extractions
like `e.aGetter` or `e.aMethod` (tear-offs), operator invocations like
`e1 + e2` or `aListOrNull?[1] = e`, function invocations like `f()`.  Each
of these expressions has a _syntactic receiver_ and an _associated member
name_.  With `e.aMethod<int>(24)`, the receiver is `e` and the associated
member name is `aMethod`, with `e1 + e2` the receiver is `e1` and the
member name is `+`, and with `f()` the receiver is `f` and the member name
is `call`. Note that the syntactic receiver is a type literal in the case
where the member invocation invokes a static member. In the following we
will specify invocations of static members using this concept.*

[Member Invocations]: https://github.com/dart-lang/language/blob/94194cee07d7deadf098b1f1e0475cb424f3d4be/specification/dartLangSpec.tex#L13903

Consider an expression `e` which is a member invocation with syntactic
receiver `E` and associated member name `m`, where `E` denotes a static
extension and `m` is a static member declared by `E`. We say that `e` is an
_explicitly resolved invocation_ of said static member of `E`.

*This can be used to invoke a static member of a specific static extension
in order to manually resolve a name clash.

Consider an expression `e` which is a member invocation with syntactic
receiver `C` and an associated member name `m`, where `C` denotes a class
and `m` is a static member declared by `C`. The static analysis and dynamic
semantics of this expression is the same as in Dart before the introduction
of this feature.

When `C` declares a static member whose basename is the basename of `m`,
but `C` does not declare a static member named `m` or a constructor named
`C.m`, a compile-time error occurs. *This is the same behavior as in
pre-feature Dart. It's about "near name clashes" involving a setter.*

In the case where `C` does not declare any static members whose basename is
the basename of `m`, and `C` does not declare any constructors named `C.m2`
where `m2` is the basename of `m`, let _M_ be the set containing each
accessible extension whose on-declaration is `C`, and whose static members
include one with the name `m`, or which declares a constructor named `C.m`.

*If `C` does declare a constructor with such a name `C.m2` then the given
expression is not a static member invocation. This case is described in a
section below.*

Otherwise *(when `C` does not declare such a constructor)*, an error occurs
if _M_ is empty or _M_ contains more than one member.

Otherwise *(when no error occurred)*, assume that _M_ contains exactly one
element which is an extension `E` that declares a static member named
`m`. The invocation is then treated as `E.m()` *(this is an explicitly
resolved invocation, which is specified above)*.

Otherwise *(when `E` does not declare such a static member)*, _M_ will
contain exactly one element which is a constructor named `C.m`. This is not
a static member invocation, and it is specified in a section below.

In addition to these rules for invocations of static members of a static
extension or a class, a corresponding set of rules exist for a static
extension and the following: An enumerated declaration *(`enum ...`)*, a
mixin class, a mixin, and an extension type. They only differ by being
concerned with a different kind of on-declaration.

In addition to the member invocations specified above, it is also possible
to invoke a static member of the enclosing declaration based on lexical
lookup. This case is applicable when an expression in a class, enum, mixin
or extension type resolves to an invocation of a static member of the
enclosing declaration.

*This invocation will never invoke a static member of a static extension
which is not the enclosing declaration. In other words, there is nothing
new in this case.*

#### The instantiated constructor return type of a static extension

Assume that _D_ is a generic static extension declaration named `E` with
formal type parameters `X1 extends B1, ..., Xs extends Bs` and constructor
return type `C<S1 .. Sk>`. Let `T1, ..., Ts` be a list of types. The
_instantiated constructor return type_ of _D_ _with actual type arguments_
`T1 .. Ts` is then the type `[T1/X1 .. Ts/Xs]C<S1 .. Sk>`.

*As a special case, assume that _D_ has an on-type which denotes a
non-generic class `C`. In this case, the instantiated constructor return
type is `C`, for any list of actual type arguments.*

*Note that such type arguments can be useful, in spite of the fact that
they do not occur in the type of the newly created object. For example:*

```dart
class A {
  final int i;
  A(this.i);
}

static extension E<X> on A {
  A.computed(X x, int Function(X) fun): this(fun(x));
}

void main() {
  // We can create an `A` "directly".
  A a = A(42);

  // We can also use a function to compute the `int`.
  a = A.computed('Hello!', (s) => s.length);
}
```

*As another special case, assume that _D_ has no formal type parameters,
and it has a constructor return type of the form `C<S1 .. Sk>`. In this
case the instantiated constructor return type of _D_ is `C<S1 .. Sk>`,
which is a ground type, and it is the same for all call sites.*

#### Invocation of a constructor in a static extension

Explicit constructor invocations are similar to static member invocations,
but they need more detailed rules because they can use the formal type
parameters declared by a static extension.

An _explicitly resolved invocation_ of a constructor named `C.name` in a
static extension declaration _D_ named `E` with `s` type parameters and
on-declaration `C` can be expressed as `E<S1 .. Ss>.C.name(args)`,
`E.C<U1 .. Uk>.name(args)`, or `E<S1 .. Ss>.C<U1 .. Uk>.name(args)`
(and similarly for a constructor named `C` using `E<S1 .. Ss>.C(args)`,
etc).

*The point is that an explicitly resolved invocation has a static analysis
and dynamic semantics which is very easy to understand, based on the
information. In particular, the actual type arguments passed to the
extension determines the actual type arguments passed to the class, which
means that the explicitly resolved invocation typically has quite some
redundancy (but it is very easy to check whether it is consistent, and it
is an error if it is inconsistent). Every other form is reduced to this
explicitly resolved form.*

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
static extensions are a rare exception in real code, usable in the case
where a name clash prevents an implicitly resolved invocation. However,
implicitly resolved invocations are specified in the rest of this section
by reducing them to explicitly resolved ones.*

A constructor invocation of the form `C<T1 .. Tm>.name(args)` is partially
resolved by looking up a constructor named `C.name` in the class `C` and in
every accessible static extension with on-declaration `C`. A compile-time
error occurs if no such constructor is found. Similarly, an invocation of
the form `C<T1 ... Tm>(args)` uses a lookup for constructors named `C`.

*Note that, as always, a constructor named `C` can also be denoted by
`C.new` (and it must be denoted as such in a constructor tear-off).*

If a constructor in `C` with the requested name was found, the pre-feature
static analysis and dynamic semantics apply. *That is, the class always
wins.*

Otherwise, the invocation is partially resolved to a set of candidate
constructors found in static extensions. Each of the candidates _kj_ is
vetted as follows:

If `m` is zero and `E` is an accessible extension with on-declaration `C`
that declares a static member whose basename is `name` then the invocation
is a static member invocation *(which is specified in an earlier section)*.

Otherwise, assume that _kj_ is a constructor declared by a static extension
_D_ named `E` with type parameters `X1 extends B1 .. Xs extends Bs`,
on-declaration `C`, and on-type `C<S1 .. Sm>`. Find actual values
`U1 .. Us` for `X1 .. Xs` satisfying the bounds `B1 .. Bs`, such that
`([U1/X1 .. Us/Xs]C<S1 .. Sm>) == C<T1 .. Tm>`. This may determine the
value of some of the actual type arguments `U1 .. Us`, and others may be
unconstrained (because they do not occur in `C<T1 .. Tm>`). Actual type
arguments corresponding to unconstrained type parameters are given as `_`
(and they are subject to inference later on, where the types of the actual
arguments `args` may influence their value). If this inference fails
then remove _kj_ from the set of candidate constructors.  Otherwise note
that _kj_ uses actual type arguments `U1 .. Us`.

If all candidate constructors have been removed, or more than one candidate
remains, a compile-time error occurs. Otherwise, the invocation is
henceforth treated as `E<U1 .. Us>.C<T1 .. Tm>.name(args)` (respectively
`E<U1 .. Us>.C<T1 .. Tm>(args)`). *This is an explicitly resolved static
extension constructor invocation, which is specified above.*

A constructor invocation of the form `C.name(args)` (respectively
`C(args)`) where `C` denotes a non-generic class is resolved in the
same manner, with `m == 0`.

Consider a constructor invocation of the form `C.name(args)` (and similarly
for `C(args)`) where `C` denotes a generic class. As usual, the
invocation is treated as in the pre-feature language when it denotes a
constructor declared by the class `C`.

In the case where the context type schema for this invocation
determines some actual type arguments of `C`, the expression is changed to
receive said actual type arguments, `C<T1 .. Tm>.name(args)` (where the
unconstrained actual type arguments are given as `_` and inferred later).
The expression is then treated as described above.

Next, we construct a set _M_ containing all accessible static extensions
with on-declaration `C` that declare a constructor named `C.name`
(respectively `C`).

In the case where _M_ contains exactly one extension `E` that declares a
constructor named `C.name` (respectively `C`), the invocation is treated as
`E.C.name(args)` (respectively `E.C(args)`).

Otherwise, when there are two or more candidates from static extensions, an
error occurs. *We do not wish to specify an approach whereby `args` is
subject to type inference multiple times, and hence we do not support type
inference for `C.name(args)` in the case where there are multiple distinct
declarations whose signature could be used during the static analysis of
that expression. The workaround is to specify the actual type arguments
explicitly.*

In addition to these rules for invocations of constructors of a static
extension or a class, a corresponding set of rules exist for a static
extension and the following: An enumerated declaration *(`enum ...`)*, a
mixin class, a mixin, and an extension type. They only differ by being
concerned with a different kind of declaration.

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

1.1 - August 30, 2024

* Clarify many parts.

1.0 - May 31, 2024

* First version of this document released.
