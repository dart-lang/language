# Scoped Static Extension Methods &ndash; Static Type Patterns.

Author: eernst@google.com (@eernstg)

Version: 0.1.

This document is a feature specification of scoped static extension
methods which is based on using
[type patterns](https://github.com/dart-lang/language/issues/170) 
to provide access to the statically known type arguments of the
receiver. Only the core of the mechanism is specified, e.g., the
declaration of an extension cannot contain any `static`
declarations. We expect the omitted parts to be relatively easy to
specify later on, when we have established that the core is
well-defined.

For the design considerations behind scoped static extension methods,
please look [here](lrn-strawman.md).


## Grammar

The Dart grammar is modified as follows in order to support scoped static
extension methods:

```
<extensionDeclaration> ::=
    'extension' <typeIdentifier>? 'on' <typePatterns>
    '{' (<metadata> <extensionMemberDefinition>)* '}'
  
<extensionMemberDefinition> ::=
    <instanceMethodSignature> <functionBody>
  
<instanceMethodSignature> ::=
    <functionSignature>
  | <getterSignature>
  | <setterSignature>
  | <operatorSignature>
```

The `<typePatterns>` non-terminal is defined in the
[type patterns](https://github.com/dart-lang/language/issues/170)
documentation.

*Briefly, a `<typePatterns>` term is a comma separated list of type
patterns, each derived from `<typePattern>`, and the latter is like a
`<type>` except that it also allows for subterms of the form `var X`
or `var X extends T` where a type could occur in a `<type>`, which is
known as a _primitive_ type pattern. The idea is that a type patterns
construct is a constraint on types (some types match and others do
not), and when it matches it will bind each type variable introduced
by a primitive type pattern to a value. For instance `List<num>` will
match `List<var X>` and bind `X` to `num`.*


## Static Analysis

Let _E_ be a term derived from `<extensionDeclaration>`; we then say
that _E_ is an _extension declaration_.

In the case where the name of _E_ is omitted, a globally fresh name is
assumed. (*In this case no source code can refer to the name, but in
specifications like this, every extension can be assumed to have a
name.*)

Assume that _E_ is of the form `extension E on P { ... }`.  Assume
that `P` contains the following primitive type patterns, in that
textual order: `var X1 extends B1`, `var X2 extends B2`, .. `var Xk
extends Bk`, where `extends Object` is used in the case where the
bound is omitted.

When `k > 0` a type parameter scope is associated with
_E_, enclosed by the library scope of the enclosing library and
enclosing the body scope of _E_. For each `j` in `1 .. k`, the type
parameter `Xj` is introduced into the type parameter scope of _E_, and
associated with the bound `Bj`.

Otherwise (*when `k` is zero*) the body scope of _E_ is enclosed
directly in the library scope of the enclosing library.

The variance of each type parameter is determined as follows: `Xj` is
covariant or contravariant if the corresponding primitive type pattern
where `Xj` is introduced occurs in a covariant respectively
contravariant position in `P`.

*The corresponding primitive type pattern is well-defined because it
is an error to introduce the same type variable twice in `P`.*

During the static analysis of the body of a member declaration in _E_,
the identifier `this` is considered to have the static type which is
obtained by _erasing_ `P` to a type, that is, replacing `var Xj` and
`var Xj extends Bj` by `Xj`.

*Consider the mechanism which implies that `id` means `this.id` in the
case where there is no declaration named `id` in scope; that mechanism
applies in the body of instance methods, and it applies in the body of
extension methods as well. This means that member accesses on `this`
can be made implicitly, again just like instance methods.*

Consider the situation where an expression `e` is used in a member
access `e0` (*that is, `e0` is an instance
method/getter/setter/operator invocation or tear-off, conditional,
unconditional, or cascading, and `e` is the receiver*), where `e` has
a type `T` which is not `dynamic`, and the requested member `m` does
not occur in the interface of `T`.

In this situation, let _M_ be the set of extension declarations that
are in scope at the location where `e` occurs, and let
_E<sub>1</sub> .. E<sub>n</sub>_ be the greatest subset of _M_ such
that `T` matches the type pattern in the `on` clause of each
_E<sub>j</sub>_, _j_ in 1 .. _n_. Assume that the corresponding
matched type is _S<sub>j</sub>_, _j_ in 1 .. _n_. If there exists an
_i_ in 1 .. _n_ such that _S<sub>i</sub> <: S<sub>j</sub>_ for all
_j_ in 1 .. _n_ then let _i0_ be _i_; if no such _i_ exists
then a compile-time error occurs.

*The 
[type patterns](https://github.com/dart-lang/language/issues/170)
documentation defines what the matched type
is. The brief hint is that a type `T` is matched with a type pattern
`P`, the match succeeded, and the binding of type variables was `X1:
S1` .. `Xk: Sk`, then the matched type is `[U1/X1..Uk/Xk]V`, where
`V` is the type which is obtained by erasing the pattern `P`. Note
that the match will not succeed in the case where one or more of the
bounds are violated.*

Let `F` be the member signature of `m` in _E<sub>i0</sub>_, let `X1
.. Xk` be the type variables introduced by the `on` pattern `Pi0` in
_E<sub>i0</sub>_, let `X1: U1 .. Xk: Uk` be the bindings produced by
matching `T` with `Pi0`.

Static analysis of `e0` (*the member access of `m` that has `e` as its
receiver*) then proceeds considering the signature of `m` to be
`[U1/X1 .. Uk/Xk]F`.

*That is, we use the results from matching the static type `T` of the
receiver with the extension pattern.*

In this case, we say that `e0` has been _statically resolved_ as an
extension method invocation of `m` on _E<sub>i0</sub>_.


## Dynamic Semantics

There are no run-time entities associated with a scoped static
extension declaration _E_.

*That is, there are no instances of _E_, and _E_ has no state. However,
there will of course be a representation of the compiled code of its
methods.*

Let _E_ of the form `extension E on P { ... }` be a static extension,
let `var X1 extends B1` .. `var Xk extends Bk` be the primitive type
patterns in `P`, ordered textually. Let

```dart
T0 m<Y1 extends Bb1, .. , Ys extends Bbs>(T1 a1, .. Tm am) { ... }
```

be a method declared in the body of _E_. Assume that each `Yj` is
named such that it does not occur in `X1 .. Xk`. Let `Tp` be the
result of erasing `P` to a type (replacing `var Xj extends Bj` and
`var Xj` by `X`). The _extension desugared_ method `m` is then the
following:

```dart
T0 m<X1 extends B1 .. Xk extends Bk, 
    Y1 extends Bb1, .. , Ys extends Bbs>(
    Tp this, T1 a1, .. Tm am) { ... }
```

A similar construction produces an _extension desugared_ member for
each getter, setter and operator declared by _E_.

*Note that these must all be methods, because getters, setters, and
operators cannot be generic, and it is not possible to append an extra
parameter declaration. Based on the fact that an extension method can
only be invoked based on the static type of the receiver, it is
statically known which call sites will invoke any particular extension
member, and those call sites must then be adjusted correspondingly.
The approach used for static extension methods at call sites,
as described below, is then applied for all kinds of members.*

Consider an expression `e0` which has been statically resolved to be
an invocation of a member `m` of extension _E_, binding the type
variables introduced by the type pattern of _E_ as follows:
`X1: V1, .. Xk: Vk`. Assume that `e` is the subexpression of `e0`
which is the receiver of said invocation.

The extension member invocation proceeds as follows:

Evaluate `e` to an object `o`. Let `Tr` be the run-time type of `o`.
Invoke the extension desugared method for `m` with actual type
arguments obtained by passing `V1 .. Vk` followed by the actual type
arguments passed to `m` at the call site; and passing `o` as the first
positional argument followed by the actual arguments passed to `m` at
the call site. If this function invocation evaluates to an object `r`
then `r` is the result of the evaluation of `e1`, and if the function
invocation throws an exception _x_ and stack trace _s_ then the
evaluation of `e1` also throws _x_ and _s_.


## Discussion

This proposal is similar to the proposal in 
[language PR #284](https://github.com/dart-lang/language/pull/284).
It differs by using a purely static binding of the type parameters of
the extension, whereas PR &#35;284 uses a static match plus a run-time
match, to establish the applicability of the extension statically, and
then to extract the values of type variables from the run-time type of
the receiver.

This gives rise to two different trade-offs: (1) The static type
patterns can be more powerful, and (2) the dynamic type pattern
matching provides an 'existential open' mechanism which is otherwise
not expressible in Dart.

The enhanced expressive power of static type patterns can be
illustrated by some examples:

```dart
extension Twice on X Function(var X) {
  X Function(X) get twice => (X x) => this(this(x));
}

main() {
  int foo(num n) => (n + 2).floor;
  foo.twice(42.5);
}
```

The extension `Twice` introduces the type variable `X` as the
parameter type of the receiver, and requires that the static return
type of the receiver is a subtype of `X` (such that the whole function
type is a subtype of `T Function(T)`, where `T` is the binding of
`X`).

Dart cannot otherwise quantify over all function types taking one
parameter, such that the return type is a subtype of the parameter
type (which is needed in order to safely call it twice).

```dart
extension MakeIdempotent on Map<var X, var Y extends X> {
  Map<X, Y> get makeIdempotent {
    for (var v in this.values) this[v] = v;
    return this;
  }
}

main() {
  var map = {1: 2, 3: 4};
  print(map.makeIdempotent); // '{1: 2, 3: 4, 2: 2, 4: 4}'.
}
```

The extension `MakeIdempotent` matches every `Map` whose statically
known type arguments are such that the former is a subtype of the
latter, and it preserves both the statically known type and the
dynamic type (because it returns `this`).

Again, Dart cannot otherwise quantify over the map types that have
this property.

We can illustrate in which ways it matters that the static type
patterns do _not_ embody an 'existential open' mechanism:

```dart
extension Singleton on Iterable<var X> {
  List<X> singleton() => [this.first];
}

main() {
  List<num> xs = <int>[20];
  var singleton = xs.singleton();
  print("${singleton.runtimeType}");
}
```

With static type patterns, the value of the type variable `X` is bound
to the statically known type argument at the call site (`num`), so the
resulting object is a `List<num>`.

With type patterns as in PR &#35;284 (where there is a static match
plus a dynamic match), the same extension method would be executed,
but the type argument would be `int` and the resulting object would be
a `List<int>`.

Note that the extension method works in a way that is similar to a
global function or static method with static type patterns, and it
works similarly to an instance method (here: in `Iterable`) with
dynamic matching.


## Revisions

*   Version 0.1, March 29, 2019: Initial version.
