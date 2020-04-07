# Dart 2.0 Upper and Lower bounds (including nullability)

leafp@google.com

## CHANGELOG

2020.03.30
  - **CHANGE** Update DOWN algorithm with extensions for FutureOr

This documents the currently implemented upper and lower bound computation,
modified to account for explicit nullability and the accompanying type system
changes (including the legacy types).  In the interest of backwards
compatibility, it does not try to fix the various issues with the existing
algorithm.  

## Types

The syntactic set of types used in this draft are a slight simplification of
full Dart types, as described in the subtyping
document
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md)

## Syntactic conventions

The predicates here are defined as algorithms and should be read from top to
bottom.  That is, a case in a predicate is considered to match only if none of
the cases above it have matched.

We assume that type variables have been alpha-varied as needed.

We assume that type aliases have been expanded, and that all types are named
(prefixed) canonically.

## Helper predicates

The **TOP** predicate is true for any type which is in the equivalence class of
top types.

- **TOP**(`T?`) is true iff **TOP**(`T`) or **OBJECT**(`T`)
- **TOP**(`T*`) is true iff **TOP**(`T`) or **OBJECT**(`T`)
- **TOP**(`dynamic`) is true
- **TOP**(`void`) is true
- **TOP**(`FutureOr<T>`) is **TOP**(T)
- **TOP**(T) is false otherwise

The **OBJECT** predicate is true for any type which is in the equivalence class
of `Object`.

- **OBJECT**(`Object`) is true
- **OBJECT**(`FutureOr<T>`) is **OBJECT**(T)
- **OBJECT**(T) is false otherwise

The **BOTTOM** predicate is true for things in the equivalence class of `Never`.

- **BOTTOM**(`Never`) is true
- **BOTTOM**(`X&T`) is true iff **BOTTOM**(`T`)
- **BOTTOM**(`X extends T`) is true iff **BOTTOM**(`T`)
- **BOTTOM**(`T`) is false otherwise

The **NULL** predicate is true for things in the equivalence class of `Null`

- **NULL**(`Null`) is true
- **NULL**(`T?`) is true iff **NULL**(`T`) or **BOTTOM**(`T`)
- **NULL**(`T*`) is true iff **NULL**(`T`) or **BOTTOM**(`T`)
- **NULL**(`T`) is false otherwise

The **MORETOP** predicate defines a total order on top and `Object` types.

- **MORETOP**(`void`, `T`) = true
- **MORETOP**(`T`, `void`) = false
- **MORETOP**(`dynamic`, `T`) = true
- **MORETOP**(`T`, `dynamic`) = false
- **MORETOP**(`Object`, `T`) = true
- **MORETOP**(`T`, `Object`) = false
- **MORETOP**(`T*`, `S*`) = **MORETOP**(`T`, `S`)
- **MORETOP**(`T`, `S*`) = true
- **MORETOP**(`T*`, `S`) = false
- **MORETOP**(`T?`, `S?`) = **MORETOP**(`T`, `S`)
- **MORETOP**(`T`, `S?`) = true
- **MORETOP**(`T?`, `S`) = false
- **MORETOP**(`FutureOr<T>`, `FutureOr<S>`) = **MORETOP**(T, S)

The **MOREBOTTOM** predicate defines an (almost) total order on bottom and
`Null` types.  This does not currently consistently order two different type
variables with the same bound.

- **MOREBOTTOM**(`Never`, `T`) = true
- **MOREBOTTOM**(`T`, `Never`) = false
- **MOREBOTTOM**(`Null`, `T`) = true
- **MOREBOTTOM**(`T`, `Null`) = false
- **MOREBOTTOM**(`T?`, `S?`) = **MOREBOTTOM**(`T`, `S`)
- **MOREBOTTOM**(`T`, `S?`) = true
- **MOREBOTTOM**(`T?`, `S`) = false
- **MOREBOTTOM**(`T*`, `S*`) = **MOREBOTTOM**(`T`, `S`)
- **MOREBOTTOM**(`T`, `S*`) = true
- **MOREBOTTOM**(`T*`, `S`) = false
- **MOREBOTTOM**(`X&T`, `Y&S`) = **MOREBOTTOM**(`T`, `S`)
- **MOREBOTTOM**(`X&T`, `S`) = true
- **MOREBOTTOM**(`S`, `X&T`) = false
- **MOREBOTTOM**(`X extends T`, `Y extends S`) = **MOREBOTTOM**(`T`, `S`)


## Upper bounds

We define the upper bound of two types T1 and T2 to be **UP**(`T1`,`T2`) as follows.


- **UP**(`T`, `T`) = `T`
- **UP**(`T1`, `T2`) where **TOP**(`T1`) and **TOP**(`T2`) =
  - `T1` if **MORETOP**(`T1`, `T2`)
  - `T2` otherwise
- **UP**(`T1`, `T2`) = `T1` if **TOP**(`T1`)
- **UP**(`T1`, `T2`) = `T2` if **TOP**(`T2`)

- **UP**(`T1`, `T2`) where **BOTTOM**(`T1`) and **BOTTOM**(`T2`) =
  - `T2` if **MOREBOTTOM**(`T1`, `T2`)
  - `T1` otherwise
- **UP**(`T1`, `T2`) = `T2` if **BOTTOM**(`T1`)
- **UP**(`T1`, `T2`) = `T1` if **BOTTOM**(`T2`)

- **UP**(`T1`, `T2`) where **NULL**(`T1`) and **NULL**(`T2`) =
  - `T2` if **MOREBOTTOM**(`T1`, `T2`)
  - `T1` otherwise

- **UP**(`T1`, `T2`) where **NULL**(`T1`) =
  - `T2` if  `T2` is nullable
  - `T2*` if `Null <: T2` or `T1 <: Object` (that is, `T1` or `T2` is legacy)
  - `T2?` otherwise

- **UP**(`T1`, `T2`) where **NULL**(`T2`) =
  - `T1` if  `T1` is nullable
  - `T1*` if `Null <: T1` or `T2 <: Object` (that is, `T1` or `T2` is legacy)
  - `T1?` otherwise

- **UP**(`T1`, `T2`) where **OBJECT**(`T1`) and **OBJECT**(`T2`) =
  - `T1` if **MORETOP**(`T1`, `T2`)
  - `T2` otherwise

- **UP**(`T1`, `T2`) where **OBJECT**(`T1`) =
  - `T1` if `T2` is non-nullable
  - `T1*` if `Null <: T2` (that is, `T2` is legacy)
  - `T1?` otherwise

- **UP**(`T1`, `T2`) where **OBJECT**(`T2`) =
  - `T2` if `T1` is non-nullable
  - `T2*` if `Null <: T1` (that is, `T1` is legacy)
  - `T2?` otherwise

- **UP**(`T1*`, `T2*`) = `S*` where `S` is **UP**(`T1`, `T2`)
- **UP**(`T1*`, `T2?`) = `S?` where `S` is **UP**(`T1`, `T2`)
- **UP**(`T1?`, `T2*`) = `S?` where `S` is **UP**(`T1`, `T2`)
- **UP**(`T1*`, `T2`) = `S*` where `S` is **UP**(`T1`, `T2`)
- **UP**(`T1`, `T2*`) = `S*` where `S` is **UP**(`T1`, `T2`)

- **UP**(`T1?`, `T2?`) = `S?` where `S` is **UP**(`T1`, `T2`)
- **UP**(`T1?`, `T2`) = `S?` where `S` is **UP**(`T1`, `T2`)
- **UP**(`T1`, `T2?`) = `S?` where `S` is **UP**(`T1`, `T2`)

- **UP**(`X1 extends B1`, `T2`) =
  - `T2` if `X1 <: T2`
  - otherwise `X1` if `T2 <: X1`
  - otherwise **UP**(`B1[Object/X1]`, `T2`)

- **UP**(`X1 & B1`, `T2`) =
  - `T2` if `X1 <: T2`
  - otherwise `X1` if `T2 <: X1`
  - otherwise **UP**(`B1[Object/X1]`, `T2`)

- **UP**(`T1`, `X2 extends B2`) =
  - `X2` if `T1 <: X2`
  - otherwise `T1` if `X2 <: T1`
  - otherwise **UP**(`T1`, `B2[Object/X2]`)

- **UP**(`T1`, `X2 & B2`) =
  - `X2` if `T1 <: X2`
  - otherwise `T1` if `X2 <: T1`
  - otherwise **UP**(`T1`, `B2[Object/X2]`)

- **UP**(`T Function<...>(...)`, `Function`) = `Function`
- **UP**(`Function`, `T Function<...>(...)`) = `Function`

- **UP**(`T0 Function<X0 extends B00, ... Xm extends B0m>(P00, ... P0k)`,
         `T1 Function<X0 extends B10, ... Xm extends B1m>(P10, ... P1l)`) =
   `R0 Function<X0 extends B20, ..., Xm extends B2m>(P20, ..., P2q)` if:
     - each `B0i` and `B1i` are equal types (syntactically)
     - Both have the same number of required positional parameters
     - `q` is min(`k`, `l`)
     - `R0` is **UP**(`T0`, `T1`)
     - `B2i` is `B0i`
     - `P2i` is **DOWN**(`P0i`, `P1i`)
- **UP**(`T0 Function<X0 extends B00, ... Xm extends B0m>(P00, ... P0k, Named0)`,
         `T1 Function<X0 extends B10, ... Xm extends B1m>(P10, ... P1k, Named1)`) =
   `R0 Function<X0 extends B20, ..., Xm extends B2m>(P20, ..., P2k, Named2)` if:
     - each `B0i` and `B1i` are equal types (syntactically)
     - All positional parameters are required
     - `Named0` contains an entry (optional or required) of the form `R0i xi`
       for every required named parameter `R1i xi` in `Named1`
     - `Named1` contains an entry (optional or required) of the form `R1i xi`
       for every required named parameter `R0i xi` in `Named0`
     - The result is defined as follows:
       - `R0` is **UP**(`T0`, `T1`)
       - `B2i` is `B0i`
       - `P2i` is **DOWN**(`P0i`, `P1i`)
       - `Named2` contains exactly `R2i xi` for each `xi` in both `Named0` and
         `Named1`
        - where `R0i xi` is in `Named0`
        - where `R1i xi` is in `Named1`
        - and `R2i` is **DOWN**(`R0i`, `R1i`)
        - and `R2i xi` is required if `xi` is required in either `Named0` or
          `Named1`

- **UP**(`T Function<...>(...)`, `S Function<...>(...)`) = `Function` otherwise
- **UP**(`T Function<...>(...)`, `T2`) = `Object`
- **UP**(`T1`, `T Function<...>(...)`) = `Object`
- **UP**(`T1`, `T2`) = `T2` if `T1` <: `T2`
  - Note that both types must be class types at this point
- **UP**(`T1`, `T2`) = `T1` if `T2` <: `T1`
  - Note that both types must be class types at this point
- **UP**(`C<T0, ..., Tn>`, `C<S0, ..., Sn>`) = `C<R0,..., Rn>` where `Ri` is **UP**(`Ti`, `Si`)
- **UP**(`C0<T0, ..., Tn>`, `C1<S0, ..., Sk>`) = least upper bound of two interfaces
  as in Dart 1.

## Lower bounds

We define the lower bound of two types T1 and T2 to be **DOWN**(T1,T2) as
follows.

- **DOWN**(`T`, `T`) = `T`

- **DOWN**(`T1`, `T2`) where **TOP**(`T1`) and **TOP**(`T2`) =
  - `T1` if **MORETOP**(`T2`, `T1`)
  - `T2` otherwise
- **DOWN**(`T1`, `T2`) = `T2` if **TOP**(`T1`)
- **DOWN**(`T1`, `T2`) = `T1` if **TOP**(`T2`)

- **DOWN**(`T1`, `T2`) where **BOTTOM**(`T1`) and **BOTTOM**(`T2`) =
  - `T1` if **MOREBOTTOM**(`T1`, `T2`)
  - `T2` otherwise
- **DOWN**(`T1`, `T2`) = `T2` if **BOTTOM**(`T2`)
- **DOWN**(`T1`, `T2`) = `T1` if **BOTTOM**(`T1`)


- **DOWN**(`T1`, `T2`) where **NULL**(`T1`) and **NULL**(`T2`) =
  - `T1` if **MOREBOTTOM**(`T1`, `T2`)
  - `T2` otherwise

- **DOWN**(`Null`, `T2`) =
  - `Null` if `Null <: T2`
  - `Never` otherwise

- **DOWN**(`T1`, `Null`) =
  - `Null` if `Null <: T1`
  - `Never` otherwise

- **DOWN**(`T1`, `T2`) where **OBJECT**(`T1`) and **OBJECT**(`T2`) =
  - `T1` if **MORETOP**(`T2`, `T1`)
  - `T2` otherwise

- **DOWN**(`T1`, `T2`) where **OBJECT**(`T1`) =
  - `T2` if `T2` is non-nullable
  - **NonNull**(`T2`) if **NonNull**(`T2`) is non-nullable
  - `Never` otherwise

- **DOWN**(`T1`, `T2`) where **OBJECT**(`T2`) =
  - `T1` if `T1` is non-nullable
  - **NonNull**(`T1`) if **NonNull**(`T1`) is non-nullable
  - `Never` otherwise

- **DOWN**(`T1*`, `T2*`) = `S*` where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`T1*`, `T2?`) = `S*` where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`T1?`, `T2*`) = `S*` where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`T1*`, `T2`) = `S` where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`T1`, `T2*`) = `S` where `S` is **DOWN**(`T1`, `T2`)

- **DOWN**(`T1?`, `T2?`) = `S?` where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`T1?`, `T2`) = `S` where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`T1`, `T2?`) = `S` where `S` is **DOWN**(`T1`, `T2`)

- **DOWN**(`T0 Function<X0 extends B00, ... Xm extends B0m>(P00, ... P0k)`,
         `T1 Function<X0 extends B10, ... Xm extends B1m>(P10, ... P1l)` =
   `R0 Function<X0 extends B20, ..., Xm extends B2m>(P20, ..., P2q)` if:
     - each `B0i` and `B1i` are equal types (syntactically)
     - `q` is max(`k`, `l`)
     - `R0` is **DOWN**(`T0`, `T1`)
     - `B2i` is `B0i`
     - `P2i` is **UP**(`P0i`, `P1i`) for `i` <= than min(`k`, `l`)
     - `P2i` is `P0i` for `k` < `i` <= `q`
     - `P2i` is `P1i` for `l` < `i` <= `q`
     - `P2i` is optional if `P0i` or `P1i` is optional, or if min(k, l) < i <= q
- **DOWN**(`T0 Function<X0 extends B00, ... Xm extends B0m>(P00, ... P0k, Named0)`,
         `T1 Function<X0 extends B10, ... Xm extends B1m>(P10, ... P1k, Named1)` =
   `R0 Function<X0 extends B20, ..., Xm extends B2m>(P20, ..., P2k, Named2)` if:
     - each `B0i` and `B1i` are equal types (syntactically)
     - `R0` is **DOWN**(`T0`, `T1`)
     - `B2i` is `B0i`
     - `P2i` is **UP**(`P0i`, `P1i`)
     - `Named2` contains `R2i xi` for each `xi` in both `Named0` and `Named1`
        - where `R0i xi` is in `Named0`
        - where `R1i xi` is in `Named1`
        - and `R2i` is **UP**(`R0i`, `R1i`)
        - and `R2i xi` is required if `xi` is required in both `Named0` and `Named1`
     - `Named2` contains `R0i xi` for each `xi` in  `Named0` and not `Named1`
       - where `xi` is optional in `Named2`
     - `Named2` contains `R1i xi` for each `xi` in  `Named1` and not `Named0`
       - where `xi` is optional in `Named2`

- **DOWN**(`T Function<...>(...)`, `S Function<...>(...)`) = `Never` otherwise


- **DOWN**(`T1`, `T2`) = `T1` if `T1` <: `T2`
- **DOWN**(`T1`, `T2`) = `T2` if `T2` <: `T1`

- **DOWN**(`FutureOr<T1>`, `FutureOr<T2>`) = `FutureOr<S>`
  - where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`FutureOr<T1>`, `Future<T2>`) = `Future<S>`
  - where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`Future<T1>`, `FutureOr<T2>`) = `Future<S>`
  - where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`FutureOr<T1>`, `T2`) = `S`
  - where `S` is **DOWN**(`T1`, `T2`)
- **DOWN**(`T1`, `FutureOr<T2>`) = `S`
  - where `S` is **DOWN**(`T1`, `T2`)

- **DOWN**(`T1`, `T2`) = `Never` otherwise


## Issues and Interesting examples

### Type variable bounds

The definition of upper bound for type variables does not guarantee termination.
Counterexample:

```dart
void foo<T extends List<S>, S extends List<T>>() {
  T x;
  S y;
  var a = (x == y) ? x : y;
}
```

It should be changed to close the bound with respect to all of the type
variables declared in the same scope, using the greatest closure definition.

### Generic functions

The CFE currently implements upper bounds for generic functions incorrectly. Example:

```dart
typedef G0 = T Function<T>(T x);
typedef G1 = T Function<T>(T x);
void main() {
  G0 x;
  G1 y;
  // Analyzer: T Function<T>(T)
  // CFE: bottom -> Object
  var a = (x == y) ? x : y;
}
```

Both the CFE and the analyzer currently implement lower bounds for generic
functions incorrectly.  Example:

```dart
typedef G0 = T Function<T>(T x);
typedef G1 = T Function<T>(T x);
void main() {
  void Function(G0) x;
  void Function(G1) y;
  int z;
  // Analyzer: void Function(Never Function(Object))
  // CFE:      void Function(bottom-type Function(Object))
  var a = (x == y) ? x : y;
}
```

## Asymmetry

The current algorithm is asymmetric.  There is an equivalence class of top
types, and we correctly choose a canonical representative for bare top types
using the **MORETOP** predicate.  However, when two different top types are
embedded in two mutual subtypes, we don't correctly choose a canonical
representative.

```dart
import 'dart:async';

void main () {
  List<FutureOr<Object>> x;
  List<dynamic> y;
  String s;
  // List<dynamic>
  var a = (x == y) ? x : y;
  // List<FutureOr<Object>>
  var b = (x == y) ? y : x;
```

The best solution for this is probably to normalize the types.  This is fairly
straightforward: we just normalize `FutureOr<T>` to the normal form of `T` when
`T` is a top type.  We can then inductively apply this across the rest of the
types.  Then, whenever we have mutual subtypes, we just return the normal form.
This would be breaking, albeit hopefully only in a minor way.

An alternative would be to try to define an ordering on mutual subtypes.  This
can probably be done, but is a bit ugly.  For example, consider `Map<dynamic,
FutureOr<dynamic>>` vs `Map<FutureOr<dynamic>, dynamic>`.  The obvious way to
proceed is to define the total order by defining a traversal order on types, and
then defining the ordering lexicographically.  That is, saying that `T` is
greater than `S` if the first pair of top types encountered in the traversal
that are not identical are `T0` and `S0` respectively, and **MORETOP**(`T0`,
`S0`).

A similar treatment would need to be done for the bottom types as well, since
there are two equivalences there. 
  - `X extends T` is equivalent to `Null` if `T` is equivalent to `Null`.
  - `FutureOr<Null>` is equivalent `Future<Null>`.

A possible variant of the previous approach would be to define a finer grained
variant of the subtyping relation which is a total order on mutual subtypes.
That is, if `<::` is the extended relation, we would want that `T <:: S` implies
that `T <: S`, but also that `T <:: S` and `S <:: T` implies that `S` and `T`
are syntactically (rather than just semantically) equal.
