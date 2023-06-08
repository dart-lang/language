# Inline Classes can Implement the Representation Type

Author: eernst@google.com

Status: Draft.

This is an addendum to the [inline class feature specification][],
proposing an additional feature: An inline class `V` may have its
representation type `R` as a superinterface. This causes `V` to be a
subtype of `R`, and it enables invocations of members of `R` on a receiver
of type `V`.

[inline class feature specification]: https://github.com/dart-lang/language/blob/main/accepted/future-releases/inline-classes/feature-specification.md

## Change Log

## Summary

This is a proposal to add a new feature to inline classes: An inline class `V`
may include a superinterface in its `implements` clause which is a
supertype `R0` of the ultimate representation type `R` of `V` (this allows
`implements R` as a special case). This causes `V` to be a subtype of `R0`,
and it enables invocations of members of `R0` on a receiver of type `V`.

As it is currently
[specified](https://github.com/dart-lang/language/blob/main/accepted/future-releases/inline-classes/feature-specification.md),
the `implements` clause of an inline class declaration is used to establish
a subtype relationship to other inline classes. This allows the given
inline class to "inherit" member implementations from those other inline
classes, and it establishes a subtype relationship. For example:

```dart
inline class A {
  final int i;
  A(this.i);
  int get next => i + 1;
}

inline class B implements A {
  final int i;
  B(this.i);
}

var b = B(1).next; // OK.
A a = b; // OK.
int i = b; // Error: `B` is not assignable to `int`.
```

Another subtype relationship which can safely be adopted is that the inline
class is a subtype of its representation type, or any supertype of the
representation type. This proposal broadens the applicability of the
`implements` clause to establish that kind of subtype relationship as well:

```dart
inline class A implements int { // `A` is a subtype of `int`.
  final int i;
  A(this.i);
}

var a = A(2);
int i = a; // OK.
List<int> list = <A>[a]; // OK.
```

This subtype relationship is sound because the run-time value of an
expression of type `A` is an instance of `int`. 

This subtype relationship may be desirable in the case where there is no
need to protect an object accessed as an `A` against being accessed as an
`int`, and it is even considered to be useful that it will readily "become
an `int` whenever needed".

We need to introduce the _ultimate representation type_ of an inline type
`V<T1 .. Tk>`: This is the instantiated representation type `R` of `V` if
that is a type that is not and does not contain any inline
types. Otherwise, assume that `R` is `V1<U1 .. Us>`, then the ultimate
representation type of `V` is the ultimate representation type of
`V1<W1 .. Ws>` where `Wj` is the ultimate representation type of `Uj`, for
`j` in `1 .. s`. Similarly for function types and other composite types.

*In this document it is assumed that the ultimate representation type
exists. This is ensured by means of a static check on each inline class
declaration, as specified in the inline class feature specification.*

The corresponding change to the feature specification is be that the
following sentence in the section
[Composing inline classes](https://github.com/dart-lang/language/blob/main/accepted/future-releases/inline-classes/feature-specification.md#composing-inline-classes)
is adjusted:

> A compile-time error occurs if _V1_ is a type name or a parameterized type which occurs as a superinterface in an inline class declaration _DV_, but _V1_ does not denote an inline type.

It is adjusted to end as follows:

> ... declaration _DV_, unless _V1_ denotes an inline type, or _V1_ is a supertype of the ultimate representation type of _DV_.


Moreover, a compile-time error occurs if the implements clause of _DV_
contains two or more types that are non-inline types. A compile-time error
occurs if the implements clause of _DV_ contains a non-inline type that
occurs in any other position than the last one.

*This ensures that it is only necessary for a reader of the declaration to
check the last implemented type in order to see whether or not it is using
this feature. It is somewhat similar to the rule that `super(...)` can only
occur as the last element in a constructor initializer list.*

Let _DV_ be an inline class declaration named `V` with representation type
`R` and assume that the `implements` clause of _DV_ includes the non-inline
type `R0`. *We then have `R <: R0`, because anything else is an error.*

Invocations of members declared by `V` or declared by an inline
superinterface of _DV_ are unaffected by the fact that _DV_ implements
`R0`.

Let `m` be a member name which is not declared by _DV_. Assume that the
interface of `R0` has a member named `m`. A compile-time error occurs if an
inline superinterface of _DV_ also declares a member named `m`.

Let `m` be a member name which is not declared by _DV_ and not declared by
an inline superinterface of _DV_. Assume that the interface of `R0`
has a member named `m`. An invocation of `m` on a receiver of type `V` (or
`V<T1 .. Ts>` if _DV_ is generic) is then treated as the same invocation,
but with receiver type `R0`.

*In other words: Conflicts among superinterfaces are treated the same,
whether it is an inline or a non-inline superinterface. In both cases, _DV_
can resolve the conflict by redeclaring the given member. No override check
is applied, any signature with the given name will resolve the conflict. If
there is no conflict then _DV_ will "forward to" the members of `R0`.*

*An implementation may choose to implicitly induce forwarding members into
_DV_ in order to enable invocation of members of `R0`. However, such
forwarding members must preserve the semantics of a direct invocation. In
particular, if an invocation omits some optional parameters then the
invocation of a member of `R0` must use the default value for that
parameter, not a statically known value.*

```dart
class C {
  int m([int i = 0]) => i;
}

class D extends C {
  int m([int i = 42, j = -1]) => i;
}

inline class V implements C {
  final C it;
  V(this.it);
}

void main() {
  V v = V(D());
  // v.m(3, 4); // Compile-time error: `m` signature is from `C`.
  v.m(); // Returns 42, not 0.
}
```

It is an implementation specific behavior whether a closurization
*(also known as a tear-off)* of an inline class instance member which is
obtained from the interface of `R0` is a tear-off of the member of the
representation object, or it is a tear-off of an implicitly induced
forwarding method.

*This makes no difference for the behavior of an invocation of the
tear-off, but it does change the results returned by `==`.*

A member of the interface of _DV_ which is obtained from `R0` is available
for subtypes in the same manner as members obtained from other
superinterfaces of _DV_ and members declared by _DV_. *For example:*

```dart
inline class A implements int {
  final int i;
  A(this.i);
}

inline class B implements A {
  final int i;
  B(this.i);
}

void main() {
  B b = B(42);
  b.isEven; // OK.
}
```

TODO!!!

```dart
inline class A(num n) {}
inline class B(A a) implements num {} // OK
```

## Discussion

We have discussed how to provide access to members of the representation
type of an inline class in a more flexible manner.

One approach would be to say that every abstract declaration in an inline
class is a request for a forwarding method (or an inlined forwarding
semantics) with respect to the interface of the representation type.

```dart
inline class V {
  final int i;
  V(this.i);
  bool get isEven; // Abstract, requests forwarder to `i.isEven`.
}
```

Another approach would be to use an `export` directive of sorts,
cf. https://github.com/dart-lang/language/issues/2506.

```dart
inline class V {
  final int i;
  V(this.i);
  export i show isEven;
}
```

There are many trade-offs. For example, the abstract method may seem more
familiar, but the export mechanism avoids redeclaring the
signature. Further discussions about this topic can be seen in github
issues, in particular the one mentioned above.
