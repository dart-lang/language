# Static Extension Types

eernst@google.com

Status: Draft

Version: 0.1

This document is a feature specification which describes a possible
concretization of the concept of static extension types which is described
in issue [#42](https://github.com/dart-lang/language/issues/42). It uses
many elements from the discussion in that issue.


## Summary

Static extension types provide support for zero-cost abstraction, in the
sense that they make it possible for a program to work on an object `o` of
dynamic type `T` using an interface `S` where `T` and `S` can be unrelated,
without incurring a dynamic time or space overhead.

The motivation for having such a feature includes the following:

- It allows the usage of an object or object graph to be constrained
  statically beyond that which is required by its dynamic type. For
  instance, a `List<dynamic>` might be the root of an object tree _t_ which
  is intended to be accessed according to a specific protobuf message type
  _M_. We could impose a certain discipline on the use of _t_ by writing a
  wrapper class `M` corresponding to _M_, where _t_ is stored in a private
  field `_pb` and operations on `_pb` are only performed by `M`
  methods. However, static extension types allow us to achieve the same
  discipline without allocating an instance of `M`.

- It allows the type of an object to be _branded_, similarly to Haskells
  `newtype`, such that a given representation (say, an `int`) can be
  handled with several different incompatible types for different
  purposes. For instance, an `int` could be typed as an `Age` or as a
  `Height`, and the type system would prevent assignments, returns
  etc. from mixing up those two types. Again, we could achieve the same
  thing by wrapping the `int` in two different classes `Age` and `Height`,
  but with static extension types we avoid the cost in type and space that
  is incurred when we use a wrapper.


## Syntax

The grammar is modified as follows:

```
<topLevelDefinition> ::= <classDeclaration>
  | <mixinDeclaration>
  | <extensionTypeDeclaration> // New alternative.
  | ...

<extensionTypeDeclaration> ::= // New rule.
  'typedef' <typeIdentifier> <typeParameters>?
  ('on' | 'extends') <typeNotVoidNotFunction>
  'implements' <typeNotVoidNotFunctionList>
  '{' <extensionTypeValidity>?
  (<metadata> <extensionTypeMemberDefinition>)* '}'

<extensionTypeValidity> ::= // New rule.
  'where' <expression> ';'

<extensionTypeMemberDefinition> ::= // New rule.
  <classMemberDefinition>
```

It is a compile-time error if an `<extensionTypeMemberDefinition>` declares
an instance variable, if it declares a constructor which is not a
factory, and if it declares an abstract instance member. (*We mention this
here because it could as well be expressed in the grammar.*)


## Static Analysis

Consider an extension type declaration _E_ of the form

```dart
typedef E<X1 extends B1, ..., Xk extends Bk> on T implements I1, ..., Im {
  where e;
  D1;
  ...
  Dn;
}
```

where `T` and `I1, ..., Im` are types which may refer to `X1 .. Xk`. Let
_I_ be the combined interface of `I1, ..., Im`; for each member signature
_s_ in _I_, it is a compile-time error unless there is a `j` such that `Dj`
is a correct override of _s_. It is a compile-time error unless `e` has
type `bool`.

During static checks of `D1, ..., Dn`, the reserved word `this` is
considered to have the type `T` and it is assumed that `Xj <: Bj` for all
`j` in 1..k.

The declaration _E_ introduces the name `E` into the current library
scope.

Consider the case where `k` is zero, that is, `E` is non-generic. In
this case that name `E` is bound to the extension type `(T, E, [])`.

With any extension type `(T, E, A)`, it is a compile-time error for `T` to
be an extension type, and for any type in `A` to be an extension type.

In the case where `k` is positive (*so `E` is generic*), `E` is bound to a
mapping that maps a sequence of `k` types `S1 .. Sk` to
`([S1/X1, ... Sk/Xk]T, E, [S1, ..., Sk])`.

*So the parameterized type `E<S1, ... Sk>` denotes the
extension type `(T0, E, [S1, ... Sk])` where `T0` is obtained from `T` by
substituting `Sj` for `Xj`, for each `j` in 1..k. Just like other
parameterized types, `E<S1, ... Sk>` is a compile-time error if it is not
well-bounded.*

Assignability for extension types is defined recursively on the structure,
with the following atomic case:

- `(T1, E, A1)` is assignable to `(T2, E, A2)` if `T1` is assignable to
  `T2`.
  
*Note that `A1` and `A2` do not play a role here. For example, we can
assign an `(int, E, [])` to a variable of type `(num, E, [])` for any
extension type `E`, but we cannot assign an expression of type `(int, E1,
[])` to a variable of type `(int, E2, [])` unless `E1` and `E2` is the same
extension type.*

*An example of the recursive case is that an expression of type `List<(int,
E, [])>` is assignable to a variable of type `Iterable<(int, E, [])>`.*

*Note that the `implements` clause allows developers to maintain
consistency with given class types (such that the extension type "can do
the same things"), but it does not introduce any additional
assignability. The reason for this is that extension types are intended to
allow for zero-cost abstractions. So it is not supported to step outside
the realm where the underlying representation is known at compile-time.*

Consider a member access `e.s` where `s` is a selector for a member named
`m`, and the static type of `e` is `(T, E, A)`. If the declaration of `E`
uses `on` then it is a compile-time error unless `E` declares an instance
member `m`. If the declaration uses `extends` then it is a compile-time
error unless the interface of `T` or `E` declares an instance member `m`.
When both are declared, the instance member of `T` is chosen for the
subsequent static checks.

Static checks on actual arguments passed in a method invocation (*including
operators and setters*) of a method declared in `E` are performed as if
it were an instance method with the same signature in a class with the same
enclosing scope and the same type parameter declarations as `E`,
substituting actual type arguments in `A` for formal type parameters in the
declaration of `E`. The static type of the invocation is obtained from the
return type of that signature, with substitutions from `A`.

For invocations of a method in the interface of `T` (*which is only
possible when `E` uses `extends`, not `on`*), the static checks and the
static type of the invocation are obtained using the signature of `m` from
`T`.

Let `e0` be an expression of type `U`. Assume that
`Sj <: [S1/X1, ..., Sk/Xk]Bj` for all `j` in 1..k, let `T0` be the type
`[S1/X1, ..., Sk/Xk]T`, and assume that `U` is assignable to `T0`. Then
`E<S1, ..., Sk>(e)` is an expression of type `(T0, E, [S1, ... Sk])`. We
say that this is an _extension type creation_ expression.

An extension type creation expression can be introduced by type inference
in the case where an expression `e` of type `T` occurs with context type
`(T0, E, [S1, ... Sk])`.


## Dynamic Semantics

Evaluation of an extension type creation expression `e1` of the form `E<S1,
... Sk>(e)` proceeds to evaluate `e` to an object `o`. In the case where the
declaration of `E` includes a `where` clause with expression `w`, `w` is
evaluated with `this` bound to `o`, yielding an object `b`. A dynamic error
occurs if `b` is `false`. Otherwise (*if `b` is true or `E` has no `where`
clause*), `e1` evaluates to `o`.

Member accesses are disambiguated by the static analysis: When a member
access `e.s` where `s` is a selector for a member named `m` was statically
determined to refer to an instance member `m` of the type `T` where `e` has
the extension type `(T, E, A)`, it is executed as a regular instance member
access.

Otherwise (*when `m` is declared by the extension type `E`*), `m` is
executed as follows: `e` is evaluated to an object `o`; actual arguments
are evaluated and passed as for any other function call; finally, `m` is
executed with `this` bound to `o`, and the formal type parameters bound to
the actual type arguments in `A`.

*An implementation may, for instance, achieve this result by compiling each
method in `E` to a top-level function where the receiver is passed as an
argument `_this`, and implicit member access in the body of `m` are made
explicit by recursively rewriting expressions from `e` to `_this.e`.*


## Updates

- Version 0.1, June 12th 2019: Initial version of this document.
