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
may include one or more superinterfaces in its `implements` clause which are
supertypes `R1 .. Rk` of the ultimate representation type `R` of `V` (this
allows `implements R` as a special case). This causes `V` to be a subtype
of each of `Rj`, `j` in `1 .. k`, and it enables invocations of members of
`Rj` on a receiver of type `V`.

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

## Specification

### Syntax

```ebnf
<inlineClassDeclaration> ::=
  'final'? 'inline' 'class' <typeIdentifier> <typeParameters>?
  <inlineInterfaces>?
  '{'
    (<metadata> <inlineMemberDeclaration>)*
  '}'

<inlineInterfaces> ::= 'implements' <typeList>
```

### Static analysis

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

The permission for an inline class declaration to have a non-inline
superinterface is expressed by changing the feature specification text
in the section [Composing inline
classes](https://github.com/dart-lang/language/blob/main/accepted/future-releases/inline-classes/feature-specification.md#composing-inline-classes)
which is currently as follows:

> A compile-time error occurs if _V1_ is a type name or a parameterized type which occurs as a superinterface in an inline class declaration _DV_, but _V1_ does not denote an inline type.

It is adjusted to end as follows:

> ... declaration _DV_, unless _V1_ denotes an inline type, or _V1_ is a supertype of the ultimate representation type of _DV_.

*The fact that the non-inline superinterface must be a supertype of the
ultimate representation type rather than just the representation type is
helpful in the case where the representation type is itself an inline
type:*

```dart
inline class A {
  final num n;
  A(this.n);
}

inline class B implements num { // OK.
  final A a;
  A(this.a);
}
```

*This is allowed because the representation object for an expression of
type `B` is an object of type `num`, because it is the representation
object of an expression of type `A`. Note that there is no need for (or any
problem with) a subtype relationship between `A` and `B`. The relationship
between an inline type and its instantiated representation type and the
subtype relationship for an inline type are independent concepts.*

A compile-time error occurs if `void` or `dynamic` occurs as a non-inline
superinterface of an inline class. A compile-time error occurs if a type
parameter occurs as a superinterface of an inline class.

*Note that almost any supertype of the representation type can occur as a
non-inline superinterface of an inline class. In particular, inline classes
do not have the same constraints on non-inline superinterfaces as
non-inline classes have on their superinterfaces. One such example was
already given: It is a compile-time error for a non-inline class which
isn't `int` or `double` to have `implements num`. Another example:*

```dart
inline class MapEntry<K, V> implements (K, V) {
  final (K, V) _it;
  MapEntry(K key, V value) : _it = (key, value);
  K get key => $1;
  V get value => $2;
}
```

It is not a compile-time error for an inline class declaration to have a
non-inline class `C` as a superinterface based on the class modifiers of `C`.

*For instance, `inline class V implements B ...` does not give rise to a
compile-time error because `B` is a class declared in a different library
which is `sealed`, `final`, or `base`. The justification for this non-error
is that the type `V` is a static device that allows us to work with an
instance of `B` in a convenient way, it is not a mechanism that allows
anything like "`V` is a subtype of `B`" to be a fact at run time (because
`V` doesn't even exist at run time).*

A compile-time error occurs if an inline class declaration _DV_ has two
direct superinterfaces of the form `V1<T1 .. Tn>` and `V2<S1 .. Sm>` such
that `V1` and `V2` resolve to the same declaration.

*This rule is similar to a rule for non-inline classes that makes
`class C implements B, B {}` an error.*

Assume that an inline class declaration _DV_ has two superinterfaces,
direct or indirect, of the form `V1<T1 .. Ts>` and `V2<S1 .. Ss>`. Assume
that `V1` and `V2` both denote the same declaration. A compile-time error
occurs if `Tj` and `Sj` are not the same type, for any `j` in `1 .. s`.
This rule applies also in the case where one or both of the two types is a
raw type, and the actual type arguments have been computed by instantiation
to bounds, or by any other implicit mechanism.

In this rule 'same type' is defined as in the section
[Runtime type equality operator][] in the null safety specification.

[Runtime type equality operator]: https://github.com/dart-lang/language/blob/main/accepted/2.12/nnbd/feature-specification.md#runtime-type-equality-operator

*This means that `Tj` and `Sj` are the same type if the normalized form of
both types are structurally identical up to names of type variables. For
instance, `prefix.C<int>` and `C<int>` are the same type if `prefix.C` and
`C` resolve to the same class declaration, and similarly for `int`;
`FutureOr<Object>` is the same type as `Object` because of the
normalization; and `void Function<X>(X)` and `void Function<Y>(Y)` are the
same type based on alpha equivalence (renaming of type variables).*

A similar rule applies for the case where _DV_ has two superinterfaces,
direct or indirect, which are function types or record types *(in which
case the types _must_ be non-inline types)*: They must also be the same
type.

Let _DV_ be an inline class declaration named `V` with representation type
`R` and assume that the `implements` clause of _DV_ includes the non-inline
types `R1 .. Rk`. *We then have `R <: Rj` for each `j`, because anything
else is an error.*

Assume that `m` is a member which not declared by _DV_, and none of _DV_'s
inline superinterfaces have a member named `m`, but one or more of the
interfaces of `R1 .. Rk` has a member named `m`. A compile-time error
occurs if there exists a member name `m` such that at least two of `R1 .. Rk`
have a member with that name, but `m` does not have a combined member
signature for `R1 .. Rk`.  Otherwise the member signature of `m` is that
combined member signature.  In this situation we say that this is the
member signature of `m` in `R1 .. Rk`.

Invocations of members declared by _DV_ or declared by an inline
superinterface of _DV_ and not declared by any of `Rj`, `j` in `1..k` are
unaffected by the fact that _DV_ implements `R1 .. Rk`.

*This could be an invocation of a member declared by _DV_, or by any of its
non-inline superinterfaces, or both, but the rules are unchanged.*

Let `m` be a member name which is not declared by _DV_. Assume that the
interface of `Rj` has a member named `m`. A compile-time error occurs if an
inline superinterface of _DV_ also declares a member named `m`.

Let `m` be a member name which is not declared by _DV_ and not declared by
an inline superinterface of _DV_. Assume that the interface of `Rj` has a
member named `m` with signature `s` in `R1 .. Rk`. An invocation of `m` on
a receiver of type `V` (or `V<T1 .. Ts>` if _DV_ is generic) is then
treated as the same invocation, but with signature `s`.

*It is already specified in the inline class feature specification to be an
error if two inline superinterfaces `V1, V2` of _DV_ both declare a member
with the same name `m`, and _DV_ does not redeclare `m`, and `m` in `V1`
resolves to a different declaration than `m` in `V2`.*

*In other words: Conflicts among superinterfaces are treated the same,
whether it is an inline or a non-inline superinterface. In both cases, _DV_
can resolve the conflict by redeclaring the given member. No override check
is applied, any signature with the given name will resolve the conflict. If
there is no conflict then _DV_ will "forward to" the members of `R1 .. Rk`.*

*Note, however, that conflicts are detected in a different way for an
inline/inline conflict, an inline/non-inline conflict, and for a
non-inline/non-inline conflict: With an inline/inline conflict, the two
declarations named `m` are looked up at compile time, and there is an
error if they are not the same declaration. With an inline/non-inline
conflict there is always an error if both have a member named `m`. With a
non-inline/non-inline conflict we just need to check that the signature is
well-defined; there is no way the representation object could have two
conflicting implementations named `m` at run time, but we do need to know
how to call it safely. (In all cases we know that _DV_ does not redeclare
`m` because there is no conflict if it does.)*

*An implementation may choose to implicitly induce forwarding members into
_DV_ in order to enable invocation of members of `R1 .. Rk`. However, such
forwarding members must preserve the semantics of a direct invocation. In
particular, if an invocation omits some optional parameters then the
invocation of a member of `R1 .. Rk` must use the default value for that
parameter of the actually invoked instance method, not a statically known
value.*

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
obtained from the interface of `R1 .. Rk` is a tear-off of the member of
the representation object, or it is a tear-off of an implicitly induced
forwarding method.

*This makes no difference for the behavior of an invocation of the
tear-off, but it does change the results returned by `==` on the function
object, and it could change the run-time type of the tear-off. We consider
this level of implementation specific variation acceptable, given that it
could be a sizable performance improvement to use a direct tear-off in some
situations, and it is not desirable to specify that a tear-off must be
implemented as a direct tear-off of a member of the representation object.*

When it is determined whether or not there is a compile-time error because
_DV_ has multiple superinterfaces that have a member named `m`, an
implicitly induced forwarder must be ignored (that is, we must check the
conflict based on the forwardee). *This means that `m` may resolve to the
same non-inline instance member even though this occurs via two different
implicitly induced forwarders.*

A member of the interface of _DV_ which is obtained from `R1 .. Rk` is
available for subtypes in the same manner as members obtained from other
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

## Dynamic Semantics

When an expression of the form `e.m(args)` (or any other member access,
e.g., `e.m` or `e.m = e2`) has a receiver `e` whose static type is an
inline type `V`, and `m` is a member of one or more non-inline
superinterfaces of `V`, it is performed as a member access of `m` as an
instance member of the ultimate representation type of `e`.

*In other words, invocations of members of non-inline superinterfaces of an
inline type receiver are forwarded to the representation object.*

*It is an implementation specific choice whether this invocation of an
instance member of the ultimate representation type is performed directly
or as an invocation of a forwarding function.*

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

We could allow an inline class to have two or more non-inline
superinterfaces which are different generic instantiations of the same
class (or different function types or record types, etc). The reason why
this is possible (even though the only case which is relevant for
non-inline classes makes this a compile-time error) is that inline classes
do not occur in situations with subsumption. That is, we never have a
static type `T` and a run-time value whose dynamic type is `S` such that
`S <: T`, `S != T`, and `S` is an inline type.

We could have a rule like the following:

Assume that an inline class declaration _DV_ has two superinterfaces,
direct or indirect, of the form `V1<T1 .. Ts>` and `V2<S1 .. Ss>`. Assume
that `V1` and `V2` both denote the same non-inline class declaration. A
compile-time error occurs unless one of these types is a subtype of the
other.

It follows that when _DV_ implements more than two such non-inline types,
it is an error unless one of them is at least as specific as all the
others.
