# Generic constructors

Author: Erik Ernst

Status: Draft

Version: 1.0

Experiment flag: generic-constructors

This document specifies generic constructors, a feature that supports
constructors whose treatment of type parameters is more flexible and
expressive than constructors in current Dart.

## Introduction

This document specifies generic constructors. This is a feature that
supports the declaration of constructors whose treatment of type parameters
is more flexible and expressive than constructors in current Dart. 

In particular, it allows the constructor to have type parameters that are
not used in the return type (that is, the type of the newly created
object).  Such type parameters can, e.g., be used to specify relationships
between the formal parameters of the constructor. For example:

```dart
class C {
  final int i;
  C(this.i);
  C.computed<X>(X x, int Function(X) func): this(func(x));
}

void main() {
  C(42); // OK.
  C.computed('Hello', (s) => s.length); // OK.
  C.computed<String>('Hello', (s) => s.length); // OK.
}
```

Note that a constructor named `C` can be designated as `C.new`, which can
be used to declare and also to pass actual type arguments. So it is not
required for a generic constructor to have a name of the form `C.name`.

The constructor `C.computed` is generic. This can be detected directly from
the syntax because it declares a type parameter list after the second part
of the name, `computed<X>`. This type parameter list can declare any number
of type parameters, with bounds, as usual.

In this example, the type parameter `X` is used to specify a relationship
between the actual arguments of the constructor. Note that `X` is never
used as part of the type of the newly created object. This means that it is
not possible to specify the types of `x` and `func` using the currently
supported kinds of constructors in Dart, except by using much more general
types (like `Object?` and `Function`) such that the invocation `func(x)` is
not statically type safe.


```dart
// What we can do in current dart.

class C {
  final int i;
  C(this.i);
  C.computed(Object? x, Function func): this(func(x)); // Unsafe!
}
```

Another use case is _conditional constructors_. Using this feature, a
constructor can be conditional in the sense that it can be invoked with
some actual type arguments that are possible actual type arguments to the
class, but not with others. In contrast, every constructor in current dart
will accept _all_ actual type argument lists that satisfy the declared
bounds of the class.

The point is that the restriction to _some_ actual type argument lists
rather than _all_ of them allows us to single out some cases where the
constructor "knows more", and hence it can be more convenient. For example:

```dart
class D<X> {
  final X x;
  final int Function(X, X) _compare;
  D(this.x, this._compare);
  D<X>.ofComparable<X extends Comparable<X>>(X x):
      this(x, (x1, x2) => x1.compareTo(x2));
}

void main() {
  D.ofComparable(1); // OK, type argument `num <: Comparable<num>`.
  D.ofComparable<num>(1); // Also OK.
  D.ofComparable(C(42), (c1, c2) => c1.i.compareTo(c2.i)); // OK.
  D.ofComparable(C(42)); // Compile-time error.
}
```

The regular constructor `D` needs both a value `x` and a comparison
function `_compare`. However, consider the special case where the static
type of `x` allows the type variable `X` to satisfy
`X extends Comparable<X>` (which is true, for instance, when the static
type of `x` is `num` or a subtype thereof, or it is `String`, or in many
other cases). In this case it is possible to use the `compareTo` method
which is guaranteed to exist for `x`, so we only need one parameter.

In short, `D.ofComparable` is _conditional_ because it "exists" for certain
actual type argument values, and not for others.

Given that we may wish to create a `D<X>` for any `X`, it is not possible
to use the declaration of the type variable of the class to require that `X
extends Comparable<X>`. This implies that current Dart constructors can
only allow for a declaration that resembles `D.ofComparable` if it uses a
much less precise typing, and relies on some run-time type checks.

```dart
// What we can do in current Dart.

class D<X> {
  final X x;
  final int Function(X, X) _compare;
  D(this.x, this._compare);
  D.ofComparable(X x): // Unsafe!
      this(x, (dynamic x1, dynamic x2) => x1.compareTo(x2)) {
    // Check at run-time that `X extends Comparable<X>`.
    if (<X>[] is! List<Comparable<X>>) {
      throw ArgumentError("The type argument failed"
          " to satisfy `X extends Comparable<X>`.");
    }
  }
}
```

Another use case is to use a constructor to create objects whose type is a
special case of the enclosing class. For example:

```dart
// Simplified version of the real `Map` declaration in 'dart:core'.

class Map<K, V> {
  Map();
  factory Map<K, List<K>>.keyToList<K>(Iterable<K> keys) =>
      {for (key in keys) key: [key]};
}

void main() {
  var xs = <int>[1, 2, 3];
  var map = Map.keyToList(xs);
}
```

The constructor `Map.keyToList` is inherently going to create an instance of a
type of the form `Map<K, List<K>>` for some `K`. Current Dart doesn't allow
a constructor to express this kind of constraint, it can only declare
constructors whose actual type arguments are precisely the ones that
satisfy the bounds of the class, that is, "no extra constraints".

The extra constraints can be helpful during inference. For instance,
`Map.keyToList(xs)` above would yield a `Map<int, List<int>>`. In contrast:

```dart
// What we may try to do in current Dart doesn't work...

class Map<K, V> {
  Map();
  factory Map.keyToList(Iterable<Object?> keys) =>
      <Object?, List<Object?>{for (key in keys) key: [key]};
}
```

However, that is a compile-time error because it returns a 
`Map<Object?, List<Object?>>` where the return type is `Map<K, V>`.
But we don't know `K` or `V`, and we can't assume that `V` is of the form
`List<K>` or a supertype thereof. We might try to cast the map literal to
`Map<K, V>`, and that might work, but an invocation like 
`Map<int, String>.keyToList(xs)` will then throw at run time because the
map literal isn't going to have the required type no matter which iterable
we are passing as `keys`.

With the generic constructor and with an invocation like 
`Map<int, String>.keyToList(xs)`, the actual type arguments will be used as
a context type for the constructor invocation. The generic constructor
`Map.keyToList` fails to infer actual type arguments such that the
resulting return type is a subtype of `Map<int, String>`, and hence the
invocation is a compile-time error.

It should be noted that the type parameters of the class are inaccessible in
a generic constructor declaration. In that sense, the generic constructor
declaration is similar to a static member declaration, in that it can
declare and use its own formal type parameters, but it cannot access the
type parameters from the enclosing class.

The similarity to generic static methods goes further. For example, we
could express `keyToList` as a generic static method in current Dart as
follows:

```dart
// Emulating `keyToList` as a static method in current Dart.

class Map<K, V> {
  Map();
  static Map<K, List<K>> keyToList<K>(Iterable<K> keys) =>
      {for (key in keys) key: [key]};
}

void main() {
  var xs = <int>[1, 2, 3];
  var map = Map.keyToList(xs); // Has type `Map<int, List<int>>`.
}
```

Works perfectly!

This illustrates that the new expressive power is not new for static
members (and the invocations can look exactly the same as a constructor
invocation in many cases), it is only new for constructors.

However, it is still useful to generalize constructors in this way because
certain situations require the use of a constructor rather than a static
method (for instance, constant expressions). Moreover, it is simply a lack
of consistency and completeness in the language design if most functions
can be generic, but constructors can not.

## Specification

### Syntax

The grammar is adjusted as follows:

```ebnf
<constructorSignature> ::= <constructorName> <formalParameterList>
  | <typeIdentifier> <typeArguments>? '.' <identifierOrNew> 
    <typeParameters> <formalParameterList>
  | <typeIdentifier> <typeArguments> '.' <identifierOrNew> 
    <formalParameterList>

<factoryConstructorSignature> ::= 
    'const'? 'factory' <constructorSignature>

<redirectingFactoryConstructorSignature> ::=
    'const'? 'factory' <constructorSignature> '=' 
    <constructorDesignation>

<constantConstructorSignature> ::= 
    'const' <constructorSignature>
```

A _type introducing_ declaration is a class declaration, a mixin
class declaration, a mixin declaration, an enum declaration, or an
extension type declaration.

A compile-time error occurs if the `<typeIdentifier>` in the constructor
signature is not the same as the name of the enclosing type introducing
declaration, or the name of the on-declaration of the enclosing extension
declaration.

### Static Analysis

A generic constructor declaration occurs as a member of a type introducing 
declaration or an extension declaration. Its current scope is the body
scope of the enclosing declaration. It introduces a type parameter scope
whose enclosing scope is the current scope of the generic constructor
declaration, and each type parameter declaration introduces that type
parameter into said scope. The type parameter scope is the current scope
for the entire generic constructor declaration. Further scopes inside the
type parameter scope are created in the same way as for non-generic
constructors.

*For example, a parameter of the form `this.p` is in scope in the
initializer list, if any, and other parameters are in scope in the body, as
usual.*

We establish some coherence conditions for generic constructors:

A compile-time error occurs if any identifier in a generic constructor
declaration resolves to a type parameter which is declared by the enclosing
type introducing declaration or extension declaration.

*In other words, a generic constructor cannot access the type parameters of
a class etc. directly. In this way they are similar to static members.*

Assume that _D_ is a generic constructor declaration whose constructor
signature includes a list of actual type arguments which are applied to the
`<typeIdentifier>`.

*For example, `C<X>.name<X extends num>()` applies `C` to `<X>`.*

It is a compile-time error if the enclosing type introducing declaration,
or the on-declaration of the enclosing extension declaration, does not
declare any type parameters, or if it declares a different number of type
parameters than the number of type arguments which are passed.

It is a compile-time error unless these type arguments satisfy the declared
bounds, assuming that the bounds of the generic constructor declaration
itself are satisfied.

*For example, with `C<X>.name<X extends num>()`, it is an error if `C` is
declared to have a type parameter `Y extends String`, but not if it is
declared as `Y extends Object`.*

Assume that _D_ is a generic constructor declaration whose constructor
signature does not include a list of actual type arguments which are
applied to the `<typeIdentifier>`.

*For example, `C.name<X extends num>()` does not pass any type arguments to
`C`.*

A compile-time error occurs if `C` declares any type parameters.

*This is similar to saying that the "return type" of the generic
constructor must be specified explicitly, missing actual type arguments
will not be inferred.*

Assume that _D_ is a non-redirecting generative generic constructor
declaration whose constructor signature applies a list of actual type
arguments to the `<typeIdentifier>`, of the form `C<T1 .. Tk>`. (This
includes the case where `k` is zero, which again implies that `C` is a
non-generic class).

In this case, the super-initializer of the constructor (explicit or
implicit, and excepting `Object` that does not have a super-initializer)
will invoke the superconstructor with actual type arguments that correspond
to the type `C<T1 .. Tk>` of the current constructor invocation. 

That is, if `C` is declared with `k` type parameters `X1 .. Xk` and
superclass `B<U1 .. Us>` then the `j`th actual type argument to the super
constructor invocation is obtained as `[T1/X1 .. Tk/Xk]Uj`, for `j` in 
`1 .. s`.

Moreover, in the body of _D_, the reserved word `this` has static type
`C<T1 .. Tk>`.

It is a compile-time error if the super-initializer denotes a generic
constructor. *For example:*

```dart
class A<X> {
  A();
  A<X>.name<X extends num>();
}

class B<X> extends A<X> {
  B(): super.name(); // Error.
}
```

*The motivation for this error is that invocations like `B<String>()`
will fail to allow `A.name` to be invoked with any type arguments that
satisfy the declared bounds. It may be possible to lift this restriction
partially in the future, if the need turns out to be substantial.*

Assume that _D_ is a non-redirecting factory generic constructor
declaration whose constructor signature applies a list of actual type
arguments to the `<typeIdentifier>`, of the form `C<T1 .. Tk>`. (This
includes the case where `k` is zero, which again implies that `C` is a
non-generic class).

In this case, the return type of the constructor is `C<T1 .. Tk>`.

Assume that _D_ is a redirecting factory generic constructor declaration
whose constructor signature applies a list of actual type arguments to the
`<typeIdentifier>`, of the form `C<T1 .. Tk>`. (This includes the case
where `k` is zero, which again implies that `C` is a non-generic class).

In this case, the redirectee must have a type which is a subtype of 
`C<T1 .. Tk>`. Similarly, if the redirectee denotes a generic constructor
and no actual type arguments are provided then `C<T1 .. Tk>` is used as the
type to match when such type arguments are inferred.

Assume that _D_ is a redirecting generative generic constructor declaration
whose constructor signature applies a list of actual type arguments to the
`<typeIdentifier>`, of the form `C<T1 .. Tk>`. (This includes the case
where `k` is zero, which again implies that `C` is a non-generic class).

In this case, the denoted redirectee constructor is invoked with the same
actual type arguments, that is `T1 .. Tk`. It is a compile-time error if
the redirectee is a generic constructor.

*This restriction might also be relaxed in the future, if needed.*

#### Type inference

Assume that _D_ is a generic constructor declaration whose constructor
signature applies a list of actual type arguments to the
`<typeIdentifier>`, of the form `C<T1 .. Tk>`, for some `k > 0`.

Consider an invocation of this generic constructor of the form
`C.name(args)`, with context type `T`. This invocation is subjected to type
inference as if the generic constructor had been a static method of `C`
with the name `name`, with return type `C<T1 .. Tk>`, and the invocation
occurred with context type `T`.

*This corresponds to a very simple transformation of _D_: Add `static` at
the front of _D_, replace the '.' after `C<T1 .. Tk>` by a space, and
replace the initializer list (if any) and body by `=> throw 0;`. This yields
a static method declaration based on _D_, and invocations of _D_ are
inferred exactly like invocations of that static method.*

Consider an invocation of this generic constructor of the form
`C<S1 .. Sk>.name(args)`, with context type `T`. This invocation is
subjected to type inference as if the generic constructor had been the same
static method of `C` as in the previous case, but with context type 
`C<S1 .. Sk>`.

Warnings are not language specified entities, but the following warning is
recommended:

It is a warning if an invocation of `C<S1 .. Sk>.name(args)` as defined
above is inferred to have type `C<U1 .. Uk>` where there exists one or more
`j` such that `Uj` and `Sj` are not mutual subtypes.

*This is because it seems to be potentially highly confusing if an
expression like `C<num>.name()` actually yields an object of type
`C<int>.name()`, because of the declared bounds on the type parameters
declared by `C.name`. The recommended approach is to write `C<int>.name()`,
or to call some other constructor if the actual type argument must be
`num`.*

### Dynamic Semantics

The dynamic semantics of generic constructor invocations has no properties
that differ from the invocation of other constructors, except for the
consequences of the different typing of `this` in generative
non-redirecting constructors, and the modified return type in
non-redirecting factory constructors.

### Changelog

1.0 - Feb 13, 2025

* First version of this document released.
