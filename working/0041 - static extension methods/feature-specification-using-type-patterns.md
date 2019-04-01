# Scoped Static Extension Methods.

Author: eernst@google.com (@eernstg)

Version: 0.1.

This document is a feature specification of scoped static extension
methods which is based on using
[type patterns](https://github.com/dart-lang/language/issues/170)
to provide access to the actual type arguments of the receiver. Only
the core of the mechanism is specified, e.g., the declaration of an
extension cannot contain any `static` declarations. We expect the
omitted parts to be relatively easy to specify later on, when we have
established that the core is well-defined.

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
by a primitive type pattern to a value. For instance, `List<num>` will
match `List<var X>` and bind `X` to `num`.*


## Static Analysis

Let _E_ be a term derived from `<extensionDeclaration>`. We then say
that _E_ is an _extension declaration_.

In the case where the name of _E_ is omitted, a globally fresh name is
assumed. (*In this case no source code can refer to the name, but in
specifications like this, every extension can be assumed to have a
name.*)

Assume that _E_ is of the form `extension E on P { ... }`. It is a
compile-time error unless `P` is subtype robust.

*The notion of being subtype robust is defined in the
[type patterns](https://github.com/dart-lang/language/issues/170)
documentation. The point is that when a type pattern
`P` is subtype robust and a given type `T` matches `P`, then every
subtype of `T` also matches `P`.*

Assume that `P` contains the following primitive type patterns, in
that textual order: `var X1 extends B1`, `var X2 extends B2`, .. `var
Xk extends Bk`, where `extends Object` is used in the case where the
bound is omitted.

When `k > 0`, a type parameter scope is associated with _E_, enclosed
by the library scope of the enclosing library and enclosing the body
scope of _E_. For each `j` in `1 .. k`, the type parameter `Xj` is
introduced into the type parameter scope of _E_, and associated with
the bound `Bj`.

*Note that no relations between the type variables `X1 .. Xk` can be
introduced by the bounds (for instance, no F-bounds can exist),
because `P` is subtype robust.*

Otherwise (*when `k` is zero*) the body scope of _E_ is enclosed
directly in the library scope of the enclosing library.

The variance of each type parameter is determined as follows: `Xj` is
covariant or contravariant if the corresponding primitive type pattern
where `Xj` is introduced occurs in a covariant respectively
contravariant position in `P`.

*The corresponding primitive type pattern is well-defined because it
is an error to introduce the same type variable twice in `P`. Also,
a primitive pattern cannot occur as the bound of a type variable in a
generic function type.*

During the static analysis of the body of a member declaration in _E_,
the identifier `this` is considered to have the static type which is
obtained by _erasing_ `P` _to a type_, that is, replacing `var Xj` and
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

*Note that this makes it an error if no extension is applicable, and
also if multiple extensions are applicable, but none of them is most
specific.*

*The
[type patterns](https://github.com/dart-lang/language/issues/170)
documentation defines what the matched type is. The brief hint is that
a type `T` is matched with a type pattern `P`, the match succeeded,
and the binding of type variables was `X1: S1` .. `Xk: Sk`, then the
matched type is `[U1/X1..Uk/Xk]V`, where `V` is the type which is
obtained by erasing the pattern `P` to a type. Note that the match
will not succeed in the case where one or more of the bounds are
violated.*

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
patterns in `P`, ordered textually, and using `extends Object` in the
case where the bound is omitted. Let

```dart
T0 m<Y1 extends Bb1, .. , Ys extends Bbs>(T1 a1, .. Tm am) { ... }
```

be a method declared in the body of _E_. Assume that the identifier
sets `Y1 .. Ys` and `X1 .. Xk` are distinct (which can be achieved by
local renaming of variables in `Y1 .. Ys`). Let `Tp` be the result of
erasing `P` to a type. The _extension desugared method_ `m` is then
the following:

```dart
T0 m<X1 extends B1 .. Xk extends Bk,
    Y1 extends Bb1, .. , Ys extends Bbs>(
    Tp this, T1 a1, .. Tm am) { ... }
```

For each `Ti`, `i` in `1 .. m` (*but not for `Tp`*), the corresponding
parameter `ai` is treated as covariant-by-class if there exists a `j`
in `1 .. k` such that `Xj` is covariant and occurs covariantly in
`Ti`, or `Xj` is contravariant and occurs contravariantly in `Ti`.

*A primitive type pattern cannot occur as the bound of a type variable
in a generic function type, and it occurs only once in a subtype
robust pattern, so the above step is well-defined.*

*Being covariant-by-class, and unless soundness can be proven
otherwise, a dynamic check must be performed before the body of `m` is
executed, in order to verify that the actual argument passed for `ai`
has the type `Ti`. This is because the pattern matching step on the
run-time type of the receiver may result in `Ti` being a proper
subtype of the type which was assumed to be the type annotation for
`ai` during the static analysis of the call site.*

A similar construction produces an extension desugared method for
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
an invocation of a member `m` of extension _E_, and assume that `e` is
the subexpression of `e0` which is the receiver of said invocation.

The extension member invocation proceeds as follows:

Evaluate `e` to an object `o`. Let `Tr` be the run-time type of `o`.
Perform matching of `Tr` with the pattern `P` in the `on` clause of
_E_, and let `X1: V1, .. Xk: Vk` be the resulting bindings of the type
variables of _E_. Then invoke the extension desugared method for `m`
with actual type arguments obtained by passing `V1 .. Vk` followed by
the actual type arguments passed to `m` at the call site; and passing
`o` as the first positional argument followed by the actual arguments
passed to `m` at the call site. If this function invocation evaluates
to an object `r` then `r` is the result of the evaluation of `e1`, and
if the function invocation throws an exception _x_ and stack trace _s_
then the evaluation of `e1` also throws _x_ and _s_.


## Discussion

Assume that `xs` has static type `List<num>`. Unless otherwise proven
safe (say, because `xs` has an exact type), an invocation like
`xs.add(42)` is subject to a dynamic check, because the actual type
argument of `xs` at `List` can be a proper subtype of the statically
known value `num`.

It is therefore not surprising that a dynamic check will also be
performed on the argument passed to `add2` in `main` in the following
situation:

```dart
extension E on List<var X> {
  void add2(X x) => this.add(x);
}

main() {
  List<num> ys = <int>[];
  ys.add2(42); // Dynamic check needed.
}
```

A dynamic check is needed for both the regular instance method
invocation on `xs` and the static extension method invocation on
`ys`, because the requirement on the actual argument `42` is that it
has a type which is a subtype of the actual type argument `X` of the
given list. But that type cannot be used for a compile-time check at
the call site (because it is only known by an upper bound, `num`), and
it cannot be denoted at the call site (unless we introduce an
existential open operation which would basically have to be invoked
with a copy of the pattern of the given extension).

Consequently, it is checked in the body of the callee for the instance
method that all actual arguments for parameters that are covariant
have the required type.

*This specification is worded in the expectation that a similar
approach is used for static extension methods. Tools may of course
implement it differently as long as the behavior is unchanged, and
soundness is maintained. But it is also a hint that existing
techniques should suffice for this purpose as well.*

However, there is no need to perform a dynamic check on the actual
argument in the invocation of `add` that occurs in the body of
`add2`. The reason for this is that the value of `X` at run time is
guaranteed to be the actual value of the type argument (at the type
`List`) of the value of `this`, because there is no other way to call
`add2` than via a static extension method invocation, and they will
always provide a set of type arguments and `this` parameter where this
consistency property holds. In other words, the invocation of `add` in
the body of `add2` is safe in the same way as an invocation of `add`
in the body of `List` can be, when the actual argument has static type
`E` (which is the type variable declared by the class `List`).

Hence, the proper static type of `this` in `add2` could in fact be
considered to be `List<invariant X>`, using the notation introduced in
the
[use-site invariance](https://github.com/dart-lang/language/issues/229)
proposal.


With use-site invariance in place, it would be possible to encounter
call sites where the receiver has a type where some of the type
arguments are invariant. In this case we could call a variant of the
target method where the corresponding dynamic checks are omitted (for
improved performance) and we can reclassify the call site as
statically safe (which might affect the presentation of said call site
in an IDE, or it might allow us to eliminate some hints/lints/errors).

```dart
extension E on List<var X> {
  void add2(X x) {
    x as X;
    return this.add(x); // Safe invocation of `add`.
  }

  // Generated entry, for statically safe call sites.
  void add2_safeX(X x) {
    return this.add(x); // Safe invocation of `add`.
  }
}

main() {
  List<invariant num> xs = <num>[];
  xs.add2(42); // Compiled to call `add2_safeX`.
}
```

An unchecked entry point like `add2_safeX` can be called whenever it
is guaranteed that the static value of each of the type arguments
bound by the primitive type patterns in `E` are equal to the dynamic
ones, for all invocations at this call site.

In particular, when the receiver has a type which is invariant on the
relevant type arguments, which includes the case when the receiver has
an exact type (say, because it is a literal, or it is obtained by an
instance creation expression that calls a generative constructor), we
can call the unchecked entry point.

The improved static type information for such extension method
invocations may also give rise to a more precise treatment of the
return type. In the case where a covariant type variable `Xj`
introduced by `P` occurs contravariantly in the return type, or `Xj`
is contravariant and occurs covariantly in the return type, a
caller-side check which would otherwise have been inserted can be
omitted. (And if we switch over to give such expressions a type which
is a sound approximation from above, we would be able to give the
returned result a more precise type.)


## Revisions

*   Version 0.1, March 22, 2019: Initial version.
