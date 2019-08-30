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

However, in general, every member access where a covariant type parameter occurs in a contravariant position may cause a dynamic type error, because the actual type annotation at run time&mdash;say, the type of a parameter of a method&mdash;is a subtype of the one which is known at compile-time.

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

This feature allows type parameters to be declared with a _variance modifier_ which is one of `out`, `inout`, or `in`. This implies that the use of such a type parameter is restricted as follows.

It is a compile-time error if a type parameter declared by a static extension has a variance modifier.

*Variance is not relevant to static extensions, because there is no notion of subsumption. Each usage will be a single call site, and the value of every type argument associated with an extension method invocation is statically known at the call site.*

It is a compile-time error if a type parameter _X_ declared by a type alias has a variance modifier, unless it is `inout`; or unless it is `out` and the right hand side of the type alias has only covariant occurrences of _X_; or unless it is `in` and the right hand side of the type alias has only contravariant occurrences of _X_.

*The variance for each type parameter of a type alias is restricted based on the body of the type alias. Explicit variance modifiers may be used to document how the type parameter is used on the right hand side, and they may be used to impose more strict constraints than those implied by the right hand side.*

Let _D_ be the declaration of a class or mixin, and let _X_ be a type parameter declared by _D_.

If _X_ has the variance modifier `out` then it is a compile-time error for _X_ to occur in a non-covariant position in a member signature in the body of _D_. *For instance, _X_ can not be the type of a method parameter, and it can not be the bound of a type parameter of a generic method.*

If _X_ has the variance modifier `in` then it is a compile-time error for _X_ to occur in a non-contravariant position in a member signature in the body of _D_. *For instance, _X_ can not be the return type of a method or getter, and it can not be the bound of a type parameter of a generic method.*

*If _X_ has the variance modifier `inout` then there are no variance related restrictions on the positions where it can occur.*

The [subtype rule](https://github.com/dart-lang/language/blob/e3010343a8e6f608a831078b0a04d4f1eeca46d4/specification/dartLangSpec.tex#L14845) for interface types that is concerned with the relationship among type arguments is modified as follows:

In order to conclude that _C&lt;S<sub>1</sub>,... S<sub>s</sub>  &gt; <: C&lt;T<sub>1</sub>,... T<sub>s</sub> &gt;_ the current rule requires that _S<sub>j</sub> <: T<sub>j</sub>_ for each _j_ in 1 .. _s_. *This means that, to be a subtype, all actual type arguments must be subtypes.*

The rule is updated as follows in order to take variance modifiers into account:

For each _j_ in 1 .. _s_ where the corresponding type parameter _X<sub>j</sub>_ has no variance modifier, or it has the variance modifier `out`, we require _S<sub>j</sub> <: T<sub>j</sub>_.

For each _j_ in 1 .. _s_ where the corresponding type parameter _X<sub>j</sub>_ has the variance modifier `in`, we require _T<sub>j</sub> <: S<sub>j</sub>_.

For each _j_ in 1 .. _s_ where the corresponding type parameter _X<sub>j</sub>_ has the variance modifier `inout`, we require _S<sub>j</sub> <: T<sub>j</sub>_ as well as _T<sub>j</sub> <: S<sub>j</sub>_.

The rules for determining the variance of an position are updated as follows:

We say that a type _S_ occurs in a _covariant position_ in a type _T_ iff one of the following conditions is true:

- _T_ is _S_.

- _T_ is of the form _G&lt;S<sub>1</sub>,... S<sub>n</sub>&gt;_ where _G_ denotes a generic class and _S_ occurs in a covariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_ where the corresponding type parameter of _G_ has no variance modifier or it has the variance modifier `out`; or in a contravariant position where the corresponding type parameter has the variance modifier `in`.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...>(S<sub>1</sub> x<sub>1</sub>, ...)_ where the type parameter list may be omitted, and _S_ occurs in a covariant position in _S<sub>0</sub>_.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...&gt;(S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, [S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ..., S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>])_ or of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...&gt; (S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, {S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ..., S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>})_ where the type parameter list and each default value may be omitted, and _S_ occurs in a contravariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_.

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic type alias such that _j_ in 1 .. _n_, the formal type parameter corresponding to _S<sub>j</sub>_ is covariant, and _S_ occurs in a covariant position in _S<sub>j</sub>_.

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic type alias such that _j_ in 1 .. _n_, the formal type parameter corresponding to _S<sub>j</sub>_ is contravariant, and _S_ occurs in a contravariant position in _S<sub>j</sub>_.

We say that a type _S_ occurs in a _contravariant position_ in a type _T_ iff one of the following conditions is true:

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic class and _S_ occurs in a contravariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_ where the corresponding type parameter of _G_ has no variance modifier or it has the variance modifier `out`; or in a covariant position where the corresponding type parameter has the variance modifier `in`.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...>(S<sub>1</sub> x<sub>1</sub>, ...)_ where the type parameter list may be omitted, and _S_ occurs in a contravariant position in _S<sub>0</sub>_.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...&gt; S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, [S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ... S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>])_ or of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ...&gt; S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, {S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ... S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>})_ where the type parameter list and each default value may be omitted, and _S_ occurs in a covariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_.

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic type alias such that _j_ in 1 .. _n_, the formal type parameter corresponding to _S<sub>j</sub>_ is covariant, and _S_ occurs in a contravariant position in _S<sub>j</sub>_.

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic type alias such that _j_ in 1 .. _n_, the formal type parameter corresponding to _S<sub>j</sub>_ is contravariant, and _S_ occurs in a covariant position in _S<sub>j</sub>_.

We say that a type _S_ occurs in an _invariant position_ in a type _T_ iff one of the following conditions is true:

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic class or a generic type alias, and _S_ occurs in an invariant position in _S<sub>j</sub>_ for some _j_ in 1 .. _n_; or _S_ occurs (in any position) in _S<sub>j</sub>_, and the corresponding type parameter of _G_ has the variance modifier `inout`.

- _T_ is of the form _S<sub>0</sub> Function&lt;X<sub>1</sub> extends B<sub>1</sub>, ... X<sub>m</sub> extends B<sub>m</sub>&gt; S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, [S<sub<k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ... S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>])_ or of the form _S<sub>0</sub> function&lt;X<sub>1</sub> extends B<sub>1</sub>, ... X<sub>m</sub> extends B<sub>m</sub>&gt;_S<sub>1</sub> x<sub>1</sub>, ... S<sub>k</sub> x<sub>k</sub>, {S<sub>k+1</sub> x<sub>k+1</sub> = d<sub>k+1</sub>, ... S<sub>n</sub> x<sub>n</sub> = d<sub>n</sub>})_ where the type parameter list and each default value may be omitted, and _S_ occurs in an invariant position in _S<sub>j</sub>_ for some _j_ in 0 .. _n_, or _S_ occurs in _B<sub>i</sub>_ for some _i_ in 1 .. _m_.

- _T_ is of the form _G&lt;S<sub>1</sub>, ... S<sub>n</sub>&gt;_ where _G_ denotes a generic type alias, _j_ in 1 .. _n_, the formal type parameter corresponding to _S<sub>j</sub>_ is invariant, and _S_ occurs (in any position) in _S<sub>j</sub>_.

!!!TODO!!! Constraints on the occurrence of type parameters with a variance modifier in superinterfaces. Maybe this is easy? `inout` can occur anywhere, `out` can occur in a covariant position, and `in` can occur in a contravariant position. Think about soundness!

!!!TODO!!! Everything about use-site invariance.
