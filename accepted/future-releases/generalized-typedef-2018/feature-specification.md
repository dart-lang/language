# Design Document for Generalized Type Aliases 2018.

Author: eernst@google.com (@eernstg).

Version: 0.3.

## Motivation and Scope

Parameterized types in Dart can be verbose. An example is here:

```dart
Map<ScaffoldFeatureController<SnackBar, SnackBarClosedReason>,
    SnackBar>
```

Such verbose types may be needed repeatedly, and there may also be a need
for several different variants of them, only differing in
specific subterms. For instance, we might also need this one:

```dart
Map<ScaffoldFeatureController<SandwichBar, SandwichBarClosedReason>,
    SandwichBar>
```

This type is unlikely to work as intended if the second type argument of
`Map` is changed to `SnackBar`, but such mistakes could easily happen
during development. It may not even be easy to detect exactly where the
mistake occurred, in cases where the erroneous type is used in some
declaration, and expressions whose types depend on that declaration
unexpectedly get flagged as compile-time errors, or the IDE completions
in such expressions fail to list some of the expected choices.

This document describes how type aliases are generalized in Dart 2.2
to make such verbose types more concise and consistent.


## Feature Specification

The precise definition of the changes is given in the language
specification, with a proposed form in
[this CL](https://dart-review.googlesource.com/c/sdk/+/81414).
The following sections summarize the changes.


### Syntax

The grammar is modified as follows in order to support this feature:

```
typeAlias ::=
  metadata 'typedef' typeAliasBody |
  metadata 'typedef' identifier typeParameters? '=' type ';' // CHANGED
```

*The modification is that a type alias declaration of the form that uses
`=` can define the type alias to denote any type, not just a function
type.*

When we refer to the _body_ of a type alias of the form that includes `=`,
it refers to the `type` to the right of `=`. When we refer to the body of a
type alias of the form that does not include `=`, it refers to the function
type which is expressed by substituting `Function` for the name of the type
alias in the given `typeAliasBody`.


### Static Analysis 

There is no change in the treatment of existing syntax, so we describe only
the treatment of syntactic forms that can be new when this feature is added.

The effect of a non-generic type alias declaration of the form that uses
`=` with name `F` is to bind the name `F` in the library scope of the
enclosing library to the type denoted by the right hand side of `=` in that
declaration.

*This is not new, but it applies to a larger set of situations now that the
right hand side can be any type. Let us call that type on the right hand
side `T`. This means that `F` can be used as a type annotation, and the
entity which is given type `F` is considered to have type `T`, with the
same meaning as in the declaration of `F` (even if some declaration in the
current library gives a new meaning to an identifier in `T`).*

The effect of a generic type alias declaration of the form

```dart
typedef F<X1 extends B1 .. Xk extends Bk> = T;
```

where metadata is omitted but may be present, is to bind the name `F` in
the library scope of the enclosing library to a mapping from type argument
lists to types, such that a parameterized type of the form `F<T1..Tk>` is
an application of that mapping that denotes the type `[T1/X1 .. Tk/Xk]T`.

Let _F_ be a generic type alias of the form that uses `=` with type
parameter declarations
_X<sub>1</sub> extends B<sub>1</sub> .. X<sub>k</sub> extends B<sub>k</sub>_.
It is a compile-time error unless satisfaction of the declared bounds
_B<sub>1</sub> .. B<sub>k</sub>_ implies that the right hand side is
regular-bounded, and all types that occur as subterms of the right hand
side are well-bounded.
Any self reference in a type alias, either directly or recursively via another
type alias, is a compile-time error.

Let `F<T1..Tn>` be a parameterized type where `F` denotes a declaration of
the form
```dart
typedef F<X1 extends B1 .. Xk extends Bk> = T;
```
where metadata is omitted but may be present. It is a compile-time error if
`n != k` and it is a compile-time error if `F<T1..Tn>` is not well-bounded.

*These errors are not new, but they apply to a larger set of situations now
that the right hand side can be any type.*

When a `typeName` (*that is, `identifier` or `identifier.identifier`*)
that resolves to a generic type alias declaration is used as a type or
evaluated as an expression, it is subject to instantiation to bound.

*This treatment of generic type aliases is again the same as it was
previously, but it involves a larger set of types.*

A type alias application _A_ of the form _F_ or the form
_F&lt;T<sub>1</sub>..T<sub>k</sub>&gt;_ can be used as a type annotation,
as a type argument, as part of a function type or a function signature, as
a type literal, in an `on` clause of a `try` statement, in a type test
(`e is A`), and in a type cast (`e as A`).

A type alias application of the form _F_ or the form
_F&lt;T<sub>1</sub>..T<sub>k</sub>&gt;_ denoting a class can be used in a
position where a class is expected: in the `extends`, `with`, `implements`,
and `on` clause of a class or mixin declaration; and in an instance
creation expression (*e.g., `new F()`, `const F<String>.named('Hello!')`*).

A type alias application of the form _F_ (*that is, not
_F&lt;T<sub>1</sub>..T<sub>k</sub>&gt;_*) denoting a class _C_ or a
parameterized type _C&lt;S<sub>1</sub>..S<sub>m</sub>&gt;_
can be used to access the member _m_,
when _C_ is a class that declares a static member _m_.

*For instance, an expression like `F.m(42)` can be used to invoke `m` when
`F` denotes `C<String>` where `C` is some generic class that declares a
static method named `m`, even though it would have been a compile-time
error to invoke it with `C<String>.m(42)`. Other kinds of access are also
possible, such as an invocation of a getter or a setter, or a tear-off of a
method. Of course, the invocation must pass a suitable number of parameters
with suitable types, the only "permitted error" is the indirect ability to
pass type arguments to the class. However, `G<int>.m()` is a compile-time
error when `G<int>` is a type alias application that denotes a class `C` or
a parameterized type like `C<String, int>`, even in the case where `C`
declares a static method named `m`.*


### Dynamic Semantics

*The dynamic semantics relies on elaborations on the program performed
during compilation. In particular, instantiation to bound has occurred, and
hence some `typeName`s in the source code have been transformed into
parameterized types, even when a type is used as an expression such that it
would be a syntax error to actually add the type arguments explicitly in
the source program. This means that every generic type alias receives
actual type arguments at all locations where it is used. At run time it is
also known that the program has no compile-time errors.*

For dynamic type checks, type tests, and expression evaluations, an
identifier `F` resolving to a non-generic type alias and a parameterized
type `F<T1..Tk>` where `F` resolves to a generic type alias are treated
identically to the same type checks and type tests performed with the type
denoted by that identifier or parameterized type, and the evaluation of `F`
respectively `F<T1..Tk>` as an expression works the same as evaluation of a
fresh type variable bound to the denoted type.


## Versions

* Nov 29th, 2018, version 0.3: Allowing type aliases to be used as classes,
  including for invocation of static methods.

* Nov 8th, 2018, version 0.2: Marking the design decision of where to allow
  usages of type aliases denoting classes as under discussion.

* Nov 6th, 2018, version 0.1: Initial version of this document.
