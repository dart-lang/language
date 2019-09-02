# Sound and Explicit Variance

Author: eernst@google.com

Status: Draft


## CHANGELOG

2019.08.30:
- Initial version uploaded.


## Summary

This document proposes a specification for sound and explicit management of [variance](https://github.com/dart-lang/language/issues/213) in Dart.

Issues on topics related to this proposal can be found [here](https://github.com/dart-lang/language/issues?utf8=%E2%9C%93&q=is%3Aissue+label%3Avariance+).

Currently, a parameterized class type is covariant in every type parameter. For example, `List<int>` is a subtype of `List<num>` because `int` is a subtype of `num` (so the list type and its type argument "co-vary").

This is sound for all covariant occurrences of such type parameters in the class body (for instance, the getter `first` of a list has return type `E`, which is sound). It is also sound for contravariant occurrences when a sufficiently exact receiver type is known (e.g., for a literal like `<num>[].add(4.2)`, or for a generative constructor `SomeClass<num>.foo(4.2)`).

However, in general, every member access where a covariant type parameter occurs in a non-covariant position may cause a dynamic type error, because the actual type annotation at run time&mdash;say, the type of a parameter of a method&mdash;is a subtype of the one which occurs in the static type.

This proposal introduces explicit variance modifiers for type parameters, as well as invariance modifiers for actual type arguments. It includes compile-time restrictions on the use of objects whose static type includes these modifiers, ensuring that the above-mentioned dynamic type errors cannot occur.

In order to ease the transition where types with explicit variance are created and used, this proposal allows for certain subtype relationships where dynamic type checks are still needed when using legacy types (where type parameters are _implicitly_ covariant) to access an object, even in the case where the object has a type with explicit variance.


## Syntax

The grammar is adjusted as follows:

```
<typeParameter> ::= // Modified.
    <metadata> <typeParameterVariance>? <typeIdentifier>
    (('extends'|'super') <typeNotVoid>)?

<typeParameterVariance> ::= // New.
    'out' | 'inout' | 'in'

<typeArguments> ::= // Modified.
    '<' <typeArgumentList> '>'

<typeArgumentList> ::= // New.
    <typeArgument> (',' <typeArgument>)*

<typeArgument> ::= // New.
    'exactly'? <type>
```

Moreover, `'exactly'` is added to the set of built-in identifiers.


## Static Analysis

This feature allows type parameters to be declared with a _variance modifier_ which is one of `out`, `inout`, or `in`. This implies that the use of such a type parameter is restricted, in return for improved static type safety. Moreover, the rules for other topics like subtyping and for determining the variance of a subterm in a type are adjusted.


### Subtype Rules

The [subtype rule](https://github.com/dart-lang/language/blob/e3010343a8e6f608a831078b0a04d4f1eeca46d4/specification/dartLangSpec.tex#L14845) for interface types that is concerned with the relationship among type arguments ('class covariance') is modified as follows:

In order to conclude that _C&lt;S<sub>1</sub>,... S<sub>s</sub>&gt; <: C&lt;T<sub>1</sub>,... T<sub>s</sub>&gt;_ the current rule requires that _S<sub>j</sub> <: T<sub>j</sub>_ for each _j_ in 1 .. _s_. *This means that, to be a subtype, all actual type arguments must be subtypes.*

The rule is updated as follows in order to take variance modifiers into account:

Let _j_ in 1 .. _s_. If none of _S<sub>j</sub>_ or _T<sub>j</sub>_ have the modifier `exactly` then the following rules apply:

If the corresponding type parameter _X<sub>j</sub>_ has no variance modifier, or it has the variance modifier `out`, we require _S<sub>j</sub> <: T<sub>j</sub>_.

If the corresponding type parameter _X<sub>j</sub>_ has the variance modifier `in`, we require _T<sub>j</sub> <: S<sub>j</sub>_.

If the corresponding type parameter _X<sub>j</sub>_ has the variance modifier `inout`, we require _S<sub>j</sub> <: T<sub>j</sub>_ as well as _T<sub>j</sub> <: S<sub>j</sub>_.

If both _S<sub>j</sub>_ and _T<sub>j</sub>_ have the modifier `exactly` then let _S1<sub>j</sub>_ be _S<sub>j</sub>_ except that `exactly` has been eliminated, and similarly for _T1<sub>j</sub>_; we then require _S1<sub>j</sub> <: T1<sub>j</sub>_ as well as _T1<sub>j</sub> <: S1<sub>j</sub>_ (*whether or not the corresponding type parameter has a variance modifier, and no matter which one*).

A new subtype rule for type arguments where `exactly` does not occur symmetrically is added:

_C&lt;S<sub>1</sub>,... S<sub>s</sub>&gt; <: T_ whenever _C&lt;T<sub>1</sub>,... T<sub>s</sub>&gt; <: T_, where we have the relationship for each _j_ in 1 .. _s_ that either _S<sub>j</sub>_ is _T<sub>j</sub>_ or _S<sub>j</sub>_ is _exactly T<sub>j</sub>_.

*For instance:*

```dart
// Not runnable code, just examples of subtype relationships:
List<exactly num> <: List<num> <: List<Object> <: Object
List<exactly List<num>> <: List<List<num>> <: List<Object>
List<exactly List<exactly num>> <: List<List<exactly num>> <: List<List<num>>
List<exactly num> <: Iterable<exactly num> <: Iterable<num>

// But the subtype relation does _not_ include the following:
List<num> <\: List<exactly num>
List<exactly List<exactly num>> <\: List<exactly List<num>>
```

*We cannot assign an expression of type `List<num>` to a variable of type `List<exactly num>` without a dynamic type check. Similarly, we cannot assign an expression of type `List<exactly List<exactly num>>` to a variable of type `List<exactly List<num>>`. Here is an example illustrating why this is so.*

```dart
main() {
  List<num> xs = <int>[];
  List<exactly num> ys = xs; // This must be an error because:
  ys.add(3.41); // Safe, based on the type of `ys`, but it should throw.
  
  List<exactly List<exactly num>> zs = [];
  List<exactly List<num>> ws = zs; // This must be an error because:
  ws.add(<int>[]); // Safe, based on the type of `ws`, but it should throw.
  zs[0][0] = 4.31; // Safe, based on the type of `zs`, but it should throw.
}
```

*In the above example, an execution that maintains heap soundness would throw already at `ws.add(<int>[])`, because `List<int>` is not a subtype of `List<exactly num>`. Otherwise, we can proceed to `zs[0][0] = 4.31` and cause a base level type error, which illustrates that we cannot just ignore the distinction between `List<exactly num>` and `List<num>` as a type argument, neither statically nor dynamically.*


### Variance Rules

The rules for determining the variance of a position are updated as follows:

We say that a type _S_ occurs in a _covariant position_ in a type _T_ iff one of the following conditions is true:

- _T_ is _S_.

- _T_ is of the form _G&lt;S<sub>1</sub>,... S<sub>n</sub>&gt;_ where _G_ denotes a generic class or type alias and _S_ occurs in a covariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_ where the corresponding type parameter of _G_ is covariant; or in a contravariant position where the corresponding type parameter is contravariant.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...>(...)_ where the type parameter list may be omitted, and _S_ occurs in a covariant position in _S<sub>0</sub>_.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...&gt;(S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, [S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ..., S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>])_ or of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...&gt; (S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, {S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ..., S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>})_ where the type parameter list and each default value may be omitted, and _S_ occurs in a contravariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_.

We say that a type _S_ occurs in a _contravariant position_ in a type _T_ iff one of the following conditions is true:

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic class or type alias and _S_ occurs in a contravariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_ where the corresponding type parameter of _G_ is covariant; or in a covariant position where the corresponding type parameter is contravariant.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...>(...)_ where the type parameter list may be omitted, and _S_ occurs in a contravariant position in _S<sub>0</sub>_.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...&gt; S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, [S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ... S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>])_ or of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...&gt; S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, {S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ... S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>})_ where the type parameter list and each default value may be omitted, and _S_ occurs in a covariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_.

We say that a type _S_ occurs in an _invariant position_ in a type _T_ iff one of the following conditions is true:

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic class or type alias, and _S_ occurs in an invariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_; or _S_ occurs (in any position) in _S<sub>j</sub>_, and the corresponding type parameter of _G_ is invariant.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ... X<sub>m</sub> extends B<sub>m</sub>&gt;(S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, [S<sub<k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ... S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>])_ or of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ... X<sub>m</sub> extends B<sub>m</sub>&gt;(S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, {S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ... S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>})_ where the type parameter list and each default value may be omitted, and _S_ occurs in an invariant position in _S<sub>j</sub>_ for some _j_ in 0 .. _n_, or _S_ occurs (in any position) in _B<sub>i</sub>_ for some _i_ in 1 .. _m_.

It is a compile-time error if a type parameter declared by a static extension has a variance modifier.

*Variance is not relevant to static extensions, because there is no notion of subsumption. Each usage will be a single call site, and the value of every type argument associated with an extension method invocation is statically known at the call site.*

It is a compile-time error if a type parameter _X_ declared by a type alias has a variance modifier, unless it is `inout`; or unless it is `out` and the right hand side of the type alias has only covariant occurrences of _X_; or unless it is `in` and the right hand side of the type alias has only contravariant occurrences of _X_.

*The variance for each type parameter of a type alias is restricted based on the body of the type alias. Explicit variance modifiers may be used to document how the type parameter is used on the right hand side, and they may be used to impose more strict constraints than those implied by the right hand side.*

We say that a type parameter _X_ of a type alias _F_ _is covariant/invariant/contravariant_ if it has the variance modifier `out`/`inout`/`in`, respectively. We say that it is _covariant/contravariant_ if it has no variance modifier, and it occurs only covariantly/contravariantly, respectively, on the right hand side of `=` in the type alias (*for an old-style type alias, rewrite it to the form using `=` and then check*). Otherwise (*when _X_ has no modifier, but occurs invariantly or both covariantly and contravariantly*), we say that _X_ _is invariant_.

Let _D_ be the declaration of a class or mixin, and let _X_ be a type parameter declared by _D_.

We say that _X_ _is covariant_ if it has no variance modifier or it has the variance modifier `out`; that it _is invariant_ if it has the variance modifier `inout`; and that it _is contravariant_ if it has the variance modifier `in`.

If _X_ has the variance modifier `out` then it is a compile-time error for _X_ to occur in a non-covariant position in a member signature in the body of _D_. *For instance, _X_ can not be the type of a method parameter, and it can not be the bound of a type parameter of a generic method.*

If _X_ has the variance modifier `in` then it is a compile-time error for _X_ to occur in a non-contravariant position in a member signature in the body of _D_. *For instance, _X_ can not be the return type of a method or getter, and it can not be the bound of a type parameter of a generic method.*

*If _X_ has the variance modifier `inout` then there are no variance related restrictions on the positions where it can occur.*

*For superinterfaces we need slightly stronger rules than the ones that apply for types in the body of a type declaration.*

Let _D_ be a class or mixin declaration, let _S_ be a superinterface of _D_, and let _X_ be a type parameter declared by _D_.

It is a compile-time error if _X_ has no variance modifier and _X_ occurs in an actual type argument in _S_ such that the corresponding type parameter has a variance modifier. It is a compile-time error of _X_ has the modifier `out`, and _X_ occurs in a non-covariant position in _S_. It is a compile-time error if _X_ has the variance modifier `in`, and _X_ occurs in a non-contravariant position in _S_.

*A type parameter with variance modifier `inout` can occur in any position in a superinterface, and other variance modifiers have constraints such that if we consider type arguments _Args1_ and _Args2_ passed to _D_ such that the former produces a subtype, then we also have _S1 <: S2_ where _S1_ and _S2_ are the corresponding instantiations of _S_.*

```dart
class A<out X, inout Y, in Z> {}
class B<out U, inout V, in W> implements
    A<U Function(W), V Function(V), W Function(V)> {}

// B<int, String, num> <: B<num, String, int>, and
// A<int Function(num), String Function(String), num Function(String)> <:
// A<num Function(int), String Function(String), int Function(String)> <:
```

*But a type parameter without a variance modifier can not be used in an actual type argument for a parameter with a variance modifier, not even when that modifier is `out`. The reason for this is that it would allow a subtype to introduce the potential for dynamic errors with a member which is in the interface of the supertype and considered safe.*

```dart
abstract class A<out X> {
  Object foo();
}

class B<X> extends A<X> {
  // The following declaration would be an error with `class B<out X>`,
  // so we do not allow it in a subtype of `class A<out X>`.
  void Function(X) foo() => (X x) {};
}
```

*On the other hand, to ease migration, it _is_ allowed to create the opposite relationship:*

```dart
abstract class A<X> {
  void foo(X x);
}

class B<out X> extends A<X> {}

main() {
  B<num> myB = B<int>();
  ...
  myB.foo(42.1);
}
```

*In this situation, the invocation `myB.foo(42.1)` is subject to a dynamic type check (and it will fail if `myB` is still a `B<int>` when that invocation takes place), but it is statically known at the call site that `foo` has this property for any subtype of `A`, so we can deal with the situation statically, e.g., via a lint.*

*An upcast (like `(myB as A<num>).foo()`) could be used to silence any diagnostic messages, so a strict rule whereby a member access like `myB.foo(42.1)` is a compile-time error may not be very helpful in practice.*

*Note that the class `B` _can_ be written in such a way that the potential dynamic type error is eliminated:*

```dart
// Same A.

class B<out X> extends A<X> {
  void foo(Object? o) {...}
}
```

*In this case an invocation of `foo` on a `B` will never incur a dynamic error due to the run-time type of its argument, which might be a useful migration strategy in the case where a lot of call sites are flagged by a lint, especially when `B.foo` is genuinely able to perform its task with objects whose type is not `X`.*

*However, in the more likely case where `foo` does require an argument of type `X`, we do not wish to insist that developers declare an apparently safe member signature like `void foo(Object?)`, and then throw an exception in the body of `foo`. That would just eliminate some compile-time errors at call sites which are actually justified.*

*If such a method needs to be overridden, the modifier `covariant` must be used, in order to avoid the compile-time error for member signatures involving an `out` type parameter:*

```dart
// Same A.

class B<out X> extends A<X> {
  void foo(covariant X x) {...}
}
```
