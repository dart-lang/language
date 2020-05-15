# Dart 2.0 Type Normalization

leafp@google.com

With union, intersection, and bottom types, there are types which are
syntactically different, but are equal in the sense that they are mutual
subtypes.  This document defines a proposed normalization procedure for choosing
a canonical representative of equivalence classes of types.  Such a procedure
might provide a basis for choosing between mutual subtypes when computing upper
and lower bounds.  It might also provide a more efficient implementation of type
equality, since normal forms for types could be eagerly or lazy computed and
cached.

## Types

The syntactic set of types used in this draft are a slight simplification of
full Dart types, as described in the subtyping
document
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md)

We assume that type aliases are fully expanded, and that prefixed types are
resolved to a canonical name.

## Normalization

The **NORM** relation defines the canonical representative of classes of
equivalent types.  In the absence of legacy (*) types, it should be the case
that for any two types which are mutual subtypes, their normal forms are
syntactically identical up to identification of top types (`dynamic`, `void`,
`Object?`).

This is based on the following equations:
- `T?? == T?`
- `T?* == T?`
- `T*? == T?`
- `T** == T*`
- `Null? == Null`
- `Never? == Null`
- `dynamic? == dynamic`
- `void? == void`
- `dynamic* == dynamic`
- `void* == void`
- `FutureOr<T> == T` if `Future<T> <: T`
- `FutureOr<T> == Future<T>` if `T <: Future<T>`
- `X extend Never == Never`
- `X & T == T` if `T <: X`
- `X & T == X` if `X <: T`


Applying these equations recursively and making a canonical choice when multiple
equations apply gives us something like the following:

- **NORM**(`T`) = `T` if `T` is primitive
- **NORM**(`FutureOr<T>`) =
  - let `S` be **NORM**(`T`)
  - if `S` is a top type then `S`
  - if `S` is `Object` then `S`
  - if `S` is `Object*` then `S`
  - if `S` is `Never` then `Future<Never>`
  - if `S` is `Null` then `Future<Null>?`
  - else `FutureOr<S>`
- **NORM**(`T?`) = 
  - let `S` be **NORM**(`T`)
  - if `S` is a top type then `S`
  - if `S` is `Never` then `Null`
  - if `S` is `Never*` then `Null`
  - if `S` is `Null` then `Null`
  - if `S` is `FutureOr<R>` and `R` is nullable then `S`
  - if `S` is `FutureOr<R>*` and `R` is nullable then `FutureOr<R>`
  - if `S` is `R?` then `R?`
  - if `S` is `R*` then `R?`
  - else `S?`
- **NORM**(`T*`) = 
  - let `S` be **NORM**(`T`)
  - if `S` is a top type then `S`
  - if `S` is `Null` then `Null`
  - if `S` is `R?` then `R?`
  - if `S` is `R*` then `R*`
  - else `S*`
- **NORM**(`X extends T`) =
  - let `S` be **NORM**(`T`)
  - if `S` is `Never` then `Never`
  - else `X extends T`
- **NORM**(`X & T`) =
  - let `S` be **NORM**(`T`)
   - if `S` is `Never` then `Never`
   - if `S` is a top type then `X`
   - if `S` is `X` then `X`
   - if `S` is `Object` and **NORM(B)** is `Object` where `B` is the bound of `X` then `X`
  - else `X & S`
- **NORM**(`C<T0, ..., Tn>`) = `C<R0, ..., Rn>` where `Ri` is **NORM**(`Ti`)
- **NORM**(`R Function<X extends B>(S)`) = `R1 Function<X extends B1>(S1)`
  - where `R1` = **NORM**(`R`)
  - and `B1` = **NORM**(`B`)
  - and `S1` = **NORM**(`S`)

