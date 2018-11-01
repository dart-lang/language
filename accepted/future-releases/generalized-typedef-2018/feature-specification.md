# Design Document for Generalized Type Aliases 2018.

Author: eernst@google.com (@eernst).

Version: 0.1.


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
_B<sub>1</sub> .. B<sub>k</sub>_ implies that all all types that occur on
the right hand side of `=` are well-bounded.

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
evaluated as an expression, it is subject to instantiation to bound and
type inference.

*This treatment of generic type aliases is again the same as it was
previously, but it involves a larger set of types.*

### Dynamic Semantics

*The dynamic semantics relies on elaborations on the program performed
during compilation. In particular, instantiation to bound and type
inference has occurred, and hence some `typeName`s in the source code have
been transformed into parameterized types, even when a type is used as an
expression such that it would be a syntax error to actually add the type
arguments explicitly in the source program. This means that every generic
type alias receives actual type arguments at all locations where it is
used. At run time it is also known that the program has no compile-time
errors.*

For dynamic type checks, type tests, and expression evaluations, an
identifier `F` resolving to a non-generic type alias and a parameterized
type `F<T1..Tk>` where `F` resolves to a generic type alias are treated
identically to the same type checks, type tests, and expression evaluations
performed with the type denoted by that identifier or parameterized type.

## Versions

* Nov 1st, 2018, version 0.1: Initial version of this document.
