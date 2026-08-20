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

We say that a type parameter of a generic class, mixin, or enum is
_covariant_ if it has no variance modifier or it has the modifier `out`; we
say that it is _contravariant_ if it has the modifier `in`; and we say that
it is _invariant_ if it has the modifier `inout`.

The language specification defines what it means for a type to occur
covariantly, contravariantly, or invariantly in another type. No
changes are needed in these definitions.

However, these definitions rely on the notion that each _position_ in
a type has a specific variance, and those definitions are replaced by
the ones that are given in this section.

*The position of a type in another type is a property of each occurrence of
the former. For example, the first occurrence of `X` in the type `X
Function(X)` is in a covariant position, and the second occurrence is in a
contravariant position.*

We say that a type `S` occurs in a covariant position in a type `T` if at
least one of the following conditions is true:
  - `T` is `S`.
  - `T` is an interface type `C<T1, ..., Tk>`, `j` is in `1..k`, and:
    - the `j`th type parameter of `C` is covariant
      and `S` occurs in a covariant position in `Tj`, or
    - the `j`th type parameter of `C` is contravariant
      and `S` occurs in a contravariant position in `Tj`.
  - `T` is `FutureOr<U>` and `S` occurs in a covariant position in `U`.
  - `T` is `U Function<X1 extends B1, ...., Xk extends Bk>(T1 x1, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])` and:
    - `S` occurs in a covariant position in `U`, or
    - `S` occurs in a contravariant position in `Tj` for some `j` in `1..m`.
  - `T` is `U Function<X1 extends B1, ...., Xk extends Bk>(T1 x1, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})` and:
    - `S` occurs in a covariant position in `U`, or
    - `S` occurs in a contravariant position in `Tj` for some `j` in `1..m`.
  - `T` is `U?` and `S` occurs in a covariant position in `U`.
  - `T` is `X &amp; U` and `S` occurs in a covariant position in `U`.

`S` occurs in a contravariant position in a type `T` if at least one of the
following conditions is true:
  - `T` is an interface type `C<T1, ..., Tk>`, `j` is in `1..k`, and:
    - the `j`th type parameter of `C` is covariant
      and `S` occurs in a contravariant position in `Tj`, or
    - the `j`th type parameter of `C` is contravariant
      and `S` occurs in a covariant position in `Tj`.
  - `T` is `FutureOr<U>` and `S` occurs in a contravariant position in `U`.
  - `T` is `U Function<X1 extends B1, ...., Xk extends Bk>(T1 x1, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])` and:
    - `S` occurs in a contravariant position in `U`, or
    - `S` occurs in a covariant position in `Tj` for some `j` in `1..m`.
  - `T` is `U Function<X1 extends B1, ...., Xk extends Bk>(T1 x1, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})` and:
    - `S` occurs in a contravariant position in `U`, or
    - `S` occurs in a covariant position in `Tj` for some `j` in `1..m`.
  - `T` is `U?` and `S` occurs in a contravariant position in `U`.
  - `T` is `X &amp; U` and `S` occurs in a contravariant position in `U`.

`S` occurs in an invariant position in a type `T` if at least one of the
following conditions is true:
  - `T` is an interface type `C<T1, ..., Tk>` and
    `S` occurs in an invariant position in `Tj` for some `j` in `1..k`.
  - `T` is `FutureOr<U>` and `S` occurs in an invariant position in `U`.
  - `T` is `U Function<X1 extends B1, ...., Xk extends Bk>(T1 x1, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])` and:
    - `S` occurs in a invariant position in `U`, or
    - `S` occurs in a invariant position in `Tj` for some `j` in `1..m`, or
    - `S` occurs in `Bj` (*at any position*) for some `j` in `1..k`.
  - `T` is `U Function<X1 extends B1, ...., Xk extends Bk>(T1 x1, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})` and:
    - `S` occurs in a invariant position in `U`, or
    - `S` occurs in a invariant position in `Tj` for some `j` in `1..m`, or
    - `S` occurs in `Bj` (*at any position*) for some `j` in `1..k`.
  - `T` is `U?` and `S` occurs in an invariant position in `U`.
  - `T` is `X &amp; U` and `S` occurs in an invariant position in `U`.

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

*Variance _can_ be used with a generic enum declaration.*

The definition of the variance of a type parameter of a type alias remains
unchanged.

*In particular, a type parameter _X_ of a type alias _F_ is covariant if it
occurs in covariant positions in the body of _F_, but not in contravariant
nor invariant positions; it is contravariant if it occurs in contravariant
positions in the body of _F_, but in covariant or invariant positions; and 
it _is invariant_ if it occurs in invariant positions and/or it occurs
in covariant as well as in contravariant positions.*

Let _D_ be the declaration of a class or mixin, and let _X_ be a type
parameter declared by _D_.

If _X_ has the variance modifier `out` then it is a compile-time error for
_X_ to occur in a non-covariant position in a member signature in the body
of _D_, except that it is not an error if it occurs in a covariant position
in the type annotation of a formal parameter which is covariant (*this is a
contravariant position in the member signature as a whole*).

*In particular, _X_ can not be the type of a method parameter (unless
it is covariant). It can never be the bound of a type parameter of a
generic method.*

If _X_ has the variance modifier `in` then it is a compile-time error for
_X_ to occur in a non-contravariant position in a member signature in the
body of _D_, except that it is not an error if it occurs in a contravariant
position in the type of a formal parameter which is covariant. *For
instance, _X_ can never be the return type of a method or getter, and it can
never be the bound of a type parameter of a generic method.*

*If _X_ has the variance modifier `inout` then there are no variance
related restrictions on the positions where it can occur in member
signatures.*

Let _D_ be a class or mixin declaration, let _S_ be a direct superinterface
of _D_, and let _X_ be a type parameter declared by _D_.  It is a
compile-time error if _X_ is covariant, and _X_ occurs in a non-covariant
position in _S_. It is a compile-time error if _X_ is contravariant, and
_X_ occurs in a non-contravariant position in _S_.  In these rules, type
inference of _S_ is assumed to have taken place already.

*An invariant type parameter can occur in any position in a superinterface.
These constraints on allowed locations for type parameters ensure that if
we consider type arguments _Args1_ and _Args2_ passed to _D_ such that the
former produces a subtype, then we also have _S1 <: S2_ where _S1_ and _S2_
are the corresponding instantiations of _S_.*

```dart
class A<out X, inout Y, in Z> {}
class B<out U, inout V, in W> implements
    A<U Function(W), V Function(V), W Function(V)> {}

// B<int, String, num> <: B<num, String, int>, and hence
// A<int Function(num), String Function(String), num Function(String)> <:
// A<num Function(int), String Function(String), int Function(String)>.
```

*In a superinterface, a type parameter without a variance modifier can be
used in an actual type argument for a parameter with a variance modifier,
and vice versa. This creates a subtype hierarchy where sound and unsound
variance is mixed, which is helpful during a transitional period where
sound variance is introduced, or even as a more permanent choice if some
widely used classes (say, `List`) cannot be migrated to use sound
variance. However, it causes dynamic type checks to occur.*

```dart
// Superinterface uses sound variance, subtype uses legacy.

abstract class A<out X> {
  X get x;
}

class B<X> implements A<X> {
  late X x;
}

void main() {
  B<num> b = B<int>();
  b.x = 3.7; // Dynamic error.
}
```

*Hence, no additional type safety is obtained when a class using legacy
variance has a supertype which uses sound variance.*

```dart
// Superinterface uses legacy covariance, subtype uses sound variance.

abstract class C<X> {
  X x;
  C(this.x);
}

class D<in X> extends C<void Function(X)> {
  D(): super((X x) {});
}

void main() {
  D<int> d = D<num>();
  d.x(24); // OK.
  d.x = (int i) {}; // Dynamic error.
}
```

*The class `D` inherits a setter with argument type `void Function(X)` even
though it is an error to declare such a setter in `D`. It would be easy to
prohibit invocations of that setter on an instance of type `D<...>`, but the
invocation could then be performed using an upcast to `C`, so there is no
real protection against executing such methods on that instance.*

*Note that the subclass _can_ be written in such a way that the potential
dynamic type error is eliminated, if it is possible to write a useful
implementation with a safe signature:*

```dart
class SafeD<in X> extends C<void Function(X)> {
  set x(void Function(Never) value) { 
    if (value is void Function(X)) super.x = value;
  }
  SafeD(): super((X x) {});
}
```

*Otherwise, the modifier `covariant` can be used to avoid the compile-time
error for the member signature:*

```dart
class ExplicitlyUnsafeD<in X> extends C<void Function(X)> {
  set x(covariant void Function(X) value);
  ExplicitlyUnsafeD(): super((X x) {});
}
```

*This makes it possible to declare method implementations with unsafe
signatures, even in the case where the relevant type parameters of the
enclosing class use sound variance.*


### Type Inference

During type inference, downwards resolution produces constraints on type
variables with a variance modifier, rather than fixing them to a specific
value in a partial solution. Upwards resolution will then include those
constraints.

Detailed rules will be specified in [inference.md].

[inference.md]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md


## Dynamic Semantics

This feature causes the dynamic semantics to change in only one way:
The subtype relationship specified in the section on the static analysis
is different from the subtype relationship without this feature, and the
updated rules are used during run-time type tests and type checks.


### Dynamic Type Checks by Example

This section is not normative, it explores some consequences of the design
specified in the previous sections. Consider the following declarations:

```dart
class L<X> {
  X m(X x) {}
}

class Co<out X> extends L<X> {}
class Contra<in X> extends L<X> {} // Error.
class In<inout X> extends L<X> {}
```

`Co` is allowed, but the implementation of `m` in an instance of `Co` must
perform a dynamic type check on the actual argument, because we could have
a `Co<int>` with static type `Co<num>`. It would be an error to declare `m`
in `Co` with the same signature as in `L`; it is allowed when the method is
inherited from a class where the declaration is not an error, but this also
means that there must be a dynamic type check, just like there must be a
dynamic type check in the implementation of `m` in an instance of `L`.

`Contra` is an error, because a contravariant type parameter occurs in a
non-contravariant position in a superinterface.

`In` is allowed, and the implementation of `m` in an instance of `In` must
again perform the dynamic type check. However, this is _also_ true if the
implementation of `m` is copied to `In` (which is not an error) and the
declaration in `L` is made abstract.

The situation is similar if we use `implements` rather than `extends`,
and write an implementation of `m` in the subtype, adding `covariant` as
needed (including: `Contra` is still an error, no matter how it declares
`m`).

```dart
class Co2<out X> {
  final X x;
  Co2(this.x);
  X m2() => x;
}

class Contra2<in X> {
  void m2(X x) {}
}

class In2<inout X> {
  X m2(X x) => x;
}

class Lco2<X> extends Co2<X> {
  Lco2(super.x);
}

class Lcontra2<X> extends Contra2<X> { // Error.
  ... // Doesn't matter, it's an error anyway.
}

class Lin2<X> extends In2<X> {}
```

`Lco2.m2` does not need any dynamic type checks, it can just be inherited
as is from `Co2`.

`Lcontra2` is again an error, no matter what's in the body.

`Lin2` cannot directly inherit `In2.m2`, it needs to have an implicitly
induced stub method which will check the type of the actual argument `x`
and then `return super.m2(x)`. This is necessary because an instance of
`Lin2<int>` could be the value of an expression whose static type is
`Lin2<num>`, and we could then pass `1.5` without any compile-time errors.

Note also that it is _not_ safe to assign an expression of type `Lin2<num>`
to a variable of type `In2<num>`, because the assigned object could have
dynamic type `Lin2<int>`, which is not a subtype of `In2<num>`. In other
words, with this type of hierarchy, some static superinterfaces may not be
dynamic superinterfaces (which is new).

If we use `implements` rather than `extends`, we get the following:

```dart
abstract class Co3<out X> {
  X m3();
}

class Contra3<in X> {
  void m3(X x);
}

class In3<inout X> {
  X m3(X x);
}

class Lco3<X> implements Co3<X> {
  X x;
  Lco3(this.x);
  X m3() => x;
}

class Lcontra3<X> implements Contra3<X> { // Error.
  ...
}

class Lin3<X> extends In3<X> {
  X m3(X x) => x;
}
```

`Lco3` needs the usual dynamic type check on the setter `x=`, but no checks
on `m3`. `Lcontra3` is an error. `Lin3.m3` needs a dynamic argument check
because it can be a `Lin3<int>` with static type `Lin3<num>`. Again,
assignment of an expression of type `Lin3<num>` to a variable of type
`In3<num>` requires a dynamic type check.


## Migration

This proposal supports migration of code using dynamically checked
covariance to code where some explicit variance modifiers are used, based
on language versions.

We use the phrase _legacy library_ to denote a library which is written in
a language version that does not support sound variance.


### Legacy libraries seen from a soundly variant library

When a library _L_ with sound variance imports a legacy library _L2_, the
declarations imported from _L2_ are seen in _L_ as if they had been
declared in the language with sound variance.

*In other words, source code in _L2_ is seen as having variance modifiers
available, but it is simply not using them.*


### Soundly variant libraries seen from a legacy library

When a legacy library _L_ imports a library _L2_ with sound variance, the
subtype relationships will take declaration-site variance into account.

*In other words, a library that uses an older version of the language
can use declaration-site variance, it just cannot declare types with
declaration-site variance.*
