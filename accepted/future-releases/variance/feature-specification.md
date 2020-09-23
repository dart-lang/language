# Sound and Explicit Declaration-Site Variance

Author: eernst@google.com

Status: Draft


## CHANGELOG

2020.09.22:
- Initial version uploaded.


## Summary

This document specifies sound and explicit declaration-site
[variance](https://github.com/dart-lang/language/issues/524)
in Dart.

Issues on topics related to this proposal can be found
[here](https://github.com/dart-lang/language/issues?utf8=%E2%9C%93&q=is%3Aissue+label%3Avariance+).

Currently, a parameterized class type is covariant in every type parameter.
For example, `List<int>` is a subtype of `List<num>` because `int` is a
subtype of `num` (so the list type and its type argument "co-vary").

This is sound for all covariant occurrences of such type parameters in the
class body (for instance, the getter `first` of a list has return type `E`,
which is sound). It is also sound for contravariant occurrences when a
sufficiently exact receiver type is known (e.g., for a literal like
`<num>[].add(4.2)`, or for a generative constructor
`SomeClass<num>.foo(4.2)`).

However, in general, every member access where a covariant type parameter
occurs in a non-covariant position may cause a dynamic type error, because
the actual type annotation at run time&mdash;say, the type of a parameter
of a method&mdash;is a subtype of the one which occurs in the static type.

This feature introduces explicit variance modifiers for type parameters. It
includes compile-time restrictions on type declarations and on the use of
objects whose static type includes these modifiers, ensuring that the
above-mentioned dynamic type errors cannot occur.

In order to ease the transition where types with explicit variance are
created and used, this proposal allows for certain subtype relationships
where dynamic type checks are still needed when using legacy types (where
type parameters are _implicitly_ covariant) to access an object, even in
the case where the object has a type with explicit variance. For example,
it is allowed to declare `class MyList<out E> implements List<E> {...}`,
even though this means that `MyList` has members such as `add` that require
dynamic checks and may incur a dynamic type error.


## Syntax

The grammar is adjusted as follows:

```
<typeParameter> ::= // Modified rule.
    <metadata> <typeParameterVariance>? <typeIdentifier>
    ('extends' <typeNotVoid>)?

<typeParameterVariance> ::= // New rule.
    'out' | 'inout' | 'in'
```

`out` and `inout` are added to the set of built-in identifiers (* and `in`
is already a reserved word*).


## Static Analysis

This feature allows type parameters to be declared with a _variance
modifier_ which is one of `out`, `inout`, or `in`. This implies that the
use of such a type parameter is restricted, in return for improved static
type safety. Moreover, the rules for other topics like subtyping and for
determining the variance of a subterm in a type are adjusted.


### Subtype Rules

The interface compositionality rule in [subtyping.md] is updated
as follows:

[subtyping.md]: https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md

- **Interface Compositionality**: `T0` is an interface type `C0<S0, ..., Sk>`
  and `T1` is `C0<U0, ..., Uk>`. For `i` in `0..k`, let `vi` be the declared
  variance of the `i`th type parameter of `C0`. Then, for each `i` in `0..k`,
  one of the following holds:
  - `Si <: Ui` and `vi` is absent or `out`.
  - `Ui <: Si` and `vi` is `in`.
  - `Si <: Ui` and `Ui <: Si`, and `vi` is `inout`.


### Variance Rules

The rules for determining the variance of a position are updated as follows:

We say that a type parameter of a generic class is _covariant_ if it has no
variance modifier or it has the modifier `out`; we say that it is
_contravariant_ if it has the modifier `in`; and we say that it is
_invariant_ if it has the modifier `inout`.

The covariant occurrences of a type (schema) `T` in another type (schema)
`S` are:

  - if `S` and `T` are the same type,
    - `S` is a covariant occurrence of `T`.
  - if `S` is `Future<U>`
    - the covariant occurrences of `T` in `U`
  - if `S` is `FutureOr<U>`
    - the covariant occurrencs of `T` in `U`
  - if `S` is an interface type `C<T0, ..., Tk>`
    - the union of the covariant occurrences of `T` in `Ti`
      for `i` in `0, ..., k` where the `i`th type parameter of `C` is
      covariant, and
      the contravariant occurrences of `T` in `Ti`
      for `i` in `0, ..., k` where the `i`th type parameter of `C` is
      contravariant.
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])`,
      the union of:
    - the covariant occurrences of `T` in `U`
    - the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the covariant occurrences of `T` in `U`
    - the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., m`

The contravariant occurrences of a type `T` in another type `S` are:
  - if `S` is `Future<U>`
    - the contravariant occurrences of `T` in `U`
  - if `S` is `FutureOr<U>`
    - the contravariant occurrencs of `T` in `U`
  - if `S` is an interface type `C<T0, ..., Tk>`
    - the union of the contravariant occurrences of `T` in `Ti`
      for `i` in `0, ..., k` where the `i`th type parameter of `C` is
      covariant, and
      the covariant occurrences of `T` in `Ti`
      for `i` in `0, ..., k` where the `i`th type parameter of `C` is
      contravariant,
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])`,
      the union of:
    - the contravariant occurrences of `T` in `U`
    - the covariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the contravariant occurrences of `T` in `U`
    - the covariant occurrences of `T` in `Ti` for `i` in `0, ..., m`

The invariant occurrences of a type `T` in another type `S` are:
  - if `S` is `Future<U>`
    - the invariant occurrences of `T` in `U`
  - if `S` is `FutureOr<U>`
    - the invariant occurrencs of `T` in `U`
  - if `S` is an interface type `C<T0, ..., Tk>`
    - the union of the invariant occurrences of `T` in `Ti`
      for `i` in `0, ..., k` where the `i`th type parameter of `C` is
      covariant or contravariant, and
      all occurrences of `T` in `Ti`
      for `i` in `0, ..., k` where the `i`th type parameter of `C` is
      invariant,
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])`,
      the union of:
    - the invariant occurrences of `T` in `U`
    - the invariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
    - all occurrences of `T` in `Bi` for `i` in `0, ..., k`
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the invariant occurrences of `T` in `U`
    - the invariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
    - all occurrences of `T` in `Bi` for `i` in `0, ..., k`

It is a compile-time error if a variance modifier is specified for a type
parameter declared by a static extension, a generic function type, a
generic function or method, or a type alias.

*Variance is not relevant to static extensions, because there is no notion
of subsumption. Each usage will be a single call site, and the value of
every type argument associated with an extension method invocation is
statically known at the call site. Similar reasons apply for functions and
function types. Finally, the variance of a type parameter declared by a
type alias is determined by the usage of that type parameter in the body of
the type alias.*

We say that a type parameter _X_ of a type alias _F_ _is covariant_ if it
only occurs covariantly in the body of _F_; that it _is contravariant_ if
it occurs contravariantly in the body of _F_ and does not occur covariantly
or invariantly; that it _is invariant_ if it occurs invariantly in the body
of _F_ (*with no constraints on other occurrences*), or if it occurs both
covariantly and contravariantly.

*In particular, an unused type parameter is considered covariant.*

Let _D_ be the declaration of a class or mixin, and let _X_ be a type
parameter declared by _D_.

If _X_ has the variance modifier `out` then it is a compile-time error for
_X_ to occur in a non-covariant position in a member signature in the body
of _D_, except that it is not an error if it occurs in a covariant position
in the type annotation of a covariant formal parameter (*this is a
contravariant position in the member signature as a whole*).

*In particular, _X_ can not be the type of a method parameter (unless
covariant), and it can not be the bound of a type parameter of a generic
method.*

If _X_ has the variance modifier `in` then it is a compile-time error for
_X_ to occur in a non-contravariant position in a member signature in the
body of _D_, except that it is not an error if it occurs in a contravariant
position in the type of a covariant formal parameter. *For instance, _X_
can not be the return type of a method or getter, and it can not be the
bound of a type parameter of a generic method.*

*If _X_ has the variance modifier `inout` then there are no variance
related restrictions on the positions where it can occur.*

*For superinterfaces we need slightly stronger rules than the ones that
apply for types in the body of a type declaration.*

Let _D_ be a class or mixin declaration, let _S_ be a direct superinterface
of _D_, and let _X_ be a type parameter declared by _D_.

It is a compile-time error if _X_ has no variance modifier and _X_ occurs
in an actual type argument in _S_ such that the corresponding type
parameter has a variance modifier. It is a compile-time error if _X_ has
the modifier `out`, and _X_ occurs in a non-covariant position in _S_. It
is a compile-time error if _X_ has the variance modifier `in`, and _X_
occurs in a non-contravariant position in _S_.

*A type parameter with variance modifier `inout` can occur in any position
in a superinterface, and other variance modifiers have constraints such
that if we consider type arguments _Args1_ and _Args2_ passed to _D_ such
that the former produces a subtype, then we also have _S1 <: S2_ where _S1_
and _S2_ are the corresponding instantiations of _S_.*

```dart
class A<out X, inout Y, in Z> {}
class B<out U, inout V, in W> implements
    A<U Function(W), V Function(V), W Function(V)> {}

// B<int, String, num> <: B<num, String, int>, and hence
// A<int Function(num), String Function(String), num Function(String)> <:
// A<num Function(int), String Function(String), int Function(String)>.
```

*But a type parameter without a variance modifier can not be used in an
actual type argument for a parameter with a variance modifier, not even
when that modifier is `out`. The reason for this is that the sound treatment
of type parameters should not silently change to an unsound treatment
in a subtype.*

```dart
abstract class A<out X> {
  Object foo();
}

class B<X> extends A<X> { // Error!
  // If allowed, `X` could occur contravariantly, which is unsafe.
  void Function(X) foo() => (X x) {};
}
```

*On the other hand, to ease migration, it _is_ allowed to create the
opposite relationship:*

```dart
class A<X> {
  void foo(X x) {}
}

class B<out X> extends A<X> {}

main() {
  B<num> myB = B<int>();
  ...
  myB.foo(42.1);
}
```

*In this situation, the invocation `myB.foo(42.1)` is subject to a dynamic
type check (and it will fail if `myB` is still a `B<int>` when that
invocation takes place), but it is statically known at the call site that
`foo` has this property for any subtype of `A`, so we can deal with the
situation statically, e.g., via a lint.*

*An upcast (like `(myB as A<num>).foo()`) could be used to silence any
diagnostic messages, so a strict rule whereby a member access like
`myB.foo(42.1)` is a compile-time error may not be very helpful in
practice.*

*Note that the class `B` _can_ be written in such a way that the potential
dynamic type error is eliminated:*

```dart
class A<X> {
  void foo(X x) {}
}

class B<out X> extends A<X> {
  void foo(Object? o) {...}
}
```

*In this case an invocation of `foo` on a `B` will never incur a dynamic
error due to the run-time type of its argument, which might be a useful
migration strategy in the case where a lot of call sites are flagged by a
lint, especially when `B.foo` is genuinely able to perform its task with
objects whose type is not `X`.*

*However, in the more likely case where `foo` does require an argument of
type `X`, we do not wish to insist that developers declare an apparently
safe member signature like `void foo(Object?)`, and then throw an exception
in the body of `foo`. That would just eliminate some compile-time errors at
call sites which are actually justified.*

*If such a method needs to be implemented, the modifier `covariant` must be
used, in order to avoid the compile-time error for member signatures
involving an `out` type parameter:*

```dart
class A<X> {
  void foo(X x) {}
}

class B<out X> extends A<X> { // or `implements`.
  void foo(covariant X x) {...}
}
```


### Type Inference

During type inference, downwards resolution produces constraints on type
variables with a variance modifier, rather than fixing them to a specific
value in a partial solution. Upwards resolution will then include those
constraints.

Detailed rules will be specified in
[inference.md]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md


## Dynamic Semantics

This feature causes the dynamic semantics to change in only one way:
The subtype relationship specified in the section on the static analysis
is different from the subtype relationship without this feature, and the
updated rules are used during run-time type tests and type checks.


## Migration

This proposal supports migration of code using dynamically checked
covariance to code where some explicit variance modifiers are used, thus
eliminating the potential for some dynamic type errors. There are two
scenarios.

Let _legacy class_ denote a generic class that has one or more type
parameters with no variance modifiers.

If a new class _A_ has no direct or indirect superinterface which is a
legacy class then all non-dynamic member accesses to instances
of _A_ and its subtypes will be statically safe.

*In other words, when using sound, explicit variance only with type
declarations that are not "connected to" unsoundly covariant type
parameters then there is no migration.*

However, there is a need for migration support in the case where an
existing legacy class _B_ is modified such that an explicit variance
modifier is added to one or more of its type parameters.

In particular, an existing subtype _C_ of _B_ must now add variance
modifiers in order to remain error free, and this may conflict with the
existing member signatures of _C_:

```dart
// Before the update.
class B<X> {}
class C<X> implements B<X> {
  void f(X x) {}
}

// After the update of `B`.
class B<out X> {}
class C<X> implements B<X> { // Error.
  void f(X x) {} // If we just make it `C<out X>` then this is an error.
}

// Adjusting `C` to eliminate the errors.
class B<out X> {}
class C<out X> implements B<X> {
  void f(covariant X x) {}
}
```

This approach can be used in a scenario where all parts of the program are
migrated to the new language level where explicit variance is supported.

In the other scenario, some libraries will opt in using a suitable language
level, and others will not.

If a library _L1_ is at a language level where explicit variance is not
supported (so it is 'opted out') then code in an 'opted in' library _L2_ is
seen from _L1_ as erased, in the sense that (1) the variance modifiers
`out` and `inout` are ignored, and (2) it is a compile-time error to pass a
type argument `T` to a type parameter with variance modifier `in`, unless
`T` is a top type; (3) any type argument `T` passed to an `in` type
parameter in opted-in code is seen in opted-out code as `Object?`.

Conversely, a declaration in _L1_ (opted out) is seen from _L2_ (opted in)
without changes. So class type parameters declared in _L1_ are considered
to be unsoundly covariant by both opted in and opted out code. Types of
entities exported from _L1_ to _L2_ are seen as erased (which matters when
_L1_ imports entities from some other opted-in library).
