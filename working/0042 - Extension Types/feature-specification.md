# Static Extension Types

eernst@google.com

Status: Draft

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
this case that name `E` is bound to the labeled type `(T : E)`.

In the case where `k` is positive, that is, `E` is generic, `E` is bound to
a mapping that maps `k` types `S1 .. Sk` to `([S1/X1, ... Sk/Xk]T :
E)`. (*So the parameterized type `E<S1, ... Sk>` denotes the labeled type
`(T0 : E)` where `T0` is obtained from `T` by substituting `Sj` for `Xj`,
for each `j` in 1..k).

Assignability for labeled types is defined recursively on the structure of
the given type, with the following atomic case:

- `(T1 : E)` is assignable to `(T2 : E)` if `T1` is assignable to `T2`.

*For example, we can assign an `(int : E)` to a variable of type `(num :
E)` for any extension type `E`, but we cannot assign an expression of type
`(int : E1)` to a variable of type `(int : E2)` unless `E1` and `E2` is the
same extension type. There is no notion of subtyping among extension types,
they have to be the same.*

*An example of the recursive case is that `List<(int : E)>` is assignable
to a variable of type `Iterable<(int : E)>`.*

*Note that the `implements` clause allows developers to maintain
consistency with given class types (such that the extension type "can do
the same things"), but it does not introduce any additional
assignability. The reason for this is that extension types are intended to
allow for zero-cost abstractions. So it is simply not supported to step
outside the realm where the underlying representation is known at
compile-time.*

Consider a member access `e.s` where `s` is a selector for a member named
`m`, and the static type of `e` is `(T : E)`. If the declaration of `E`
uses `on` then it is a compile-time error unless `E` declares an instance
member `m`. If the declaration uses `extends` then it is a compile-time
error unless the interface of `T` or `E` declares an instance member `m`.
When both are declared, the instance member of `T` is chosen.

Static checks on actual arguments passed in a method invocation (including
operators and setters) involving declarations in `E` are performed as if it
were an instance method with the same signature in a class with the same
enclosing scope and the same type parameter declarations as `E`.

Let `e0` be an expression of type `U`. Assume that
`Sj <: [S1/X1, ..., Sk/Xk]Bj` for all `j` in 1..k, let `T0` be the type
`[S1/X1, ..., Sk/Xk]T`, and assume that `U` is assignable to `T0`. Then
`E<S1, ..., Sk>(e)` is an expression of type `(T0 : E)`. We say that this
is an _extension type creation_ expression.

An extension type creation expression can be introduced by type inference
in the case where an expression `e` of type `T` occurs with context type
`(T0 : E)`, if suitable type arguments can be determined.


## Dynamic Semantics





## Discussion

We do not support more than one expression for validation or more than one
`on/extends` type, because we need to ensure that the underlying
representation type is statically known.

We do not support 
