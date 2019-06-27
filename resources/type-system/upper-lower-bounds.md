# Dart 2.0 Upper and Lower bounds

leafp@google.com

This documents the currently implemented upper and lower bound computation.

## Types

The syntactic set of types used in this draft are a slight simplification of
full Dart types, as described in the subtyping
document
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md)

## Helper predicates

The **TOP** predicate is true for any type which is in the equivalence class of
top types.

- **TOP**(`Object`) is true
- **TOP**(`dynamic`) is true
- **TOP**(`void`) is true
- **TOP**(`FutureOr<T>`) is **TOP**(T)
- **TOP**(T) is false otherwise

The **BOTTOM** predicate is true for either of the two bottom types.

- **BOTTOM**(`Null`) is true
- **BOTTOM**(`bottom`) is true
- **BOTTOM**(`T`) is false otherwise

The **MORETOP** predicate defines a total order on the equivalence class of top
types.

- **MORETOP**(`void`, `T`) = true
- **MORETOP**(`T`, `void`) = false
- **MORETOP**(`dynamic`, `T`) = true
- **MORETOP**(`T`, `dynamic`) = false
- **MORETOP**(`Object`, `T`) = true
- **MORETOP**(`T`, `Object`) = false
- **MORETOP**(`FutureOr<T>`, `FutureOr<S>`) = **MORETOP**(T, S)

## Upper bounds

We define the upper bound of two types T1 and T2 to be **UP**(T1,T2) as follows.


- **UP**(`T`, `T`) = `T`
- **UP**(`T1`, `T2`) = `T1` if:
  - **TOP**(`T1`) and **TOP**(`T2`)
  - and  **MORETOP**(`T1`, `T2`)
- **UP**(`T1`, `T2`) = `T2` if:
  - **TOP**(`T1`) and **TOP**(`T2`)
  - and  not **MORETOP**(`T1`, `T2`)
- **UP**(`T1`, `T2`) = `T1` if **TOP**(`T1`)
- **UP**(`T1`, `T2`) = `T1` if **BOTTOM**(`T2`)
- **UP**(`T1`, `T2`) = `T2` if **TOP**(`T2`)
- **UP**(`T1`, `T2`) = `T2` if **BOTTOM**(`T1`)

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
- **UP**(`T Function<...>(...)`, `T2`) = `Object`
- **UP**(`Function`, `T Function<...>(...)`) = `Function`
- **UP**(`T1`, `T Function<...>(...)`) = `Object`

- **UP**(`T0 Function<X0 extends B00, ... Xm extends B0m>(P00, ... P0k)`,
         `T0 Function<X0 extends B10, ... Xm extends B1m>(P10, ... P1l)` = 
   `R0 Function<X0 extends B20, ..., Xm extends B2m>(P20, ..., P2q)` if:
     - each `B0i` and `B1i` are equal types (syntactically)
     - Both have the same number of required positional parameters
     - `q` is min(`k`, `l`)
     - `R0` is **UP**(`T0`, `T1`)
     - `B2i` is `B0i`
     - `P2i` is **DOWN**(`P0i`, `P1i`)
- **UP**(`T0 Function<X0 extends B00, ... Xm extends B0m>(P00, ... P0k, Named0)`,
         `T0 Function<X0 extends B10, ... Xm extends B1m>(P10, ... P1k, Named1)` = 
   `R0 Function<X0 extends B20, ..., Xm extends B2m>(P20, ..., P2k, Named2)` if:
     - each `B0i` and `B1i` are equal types (syntactically)
     - All positional parameters are required
     - `R0` is **UP**(`T0`, `T1`)
     - `B2i` is `B0i`
     - `P2i` is **DOWN**(`P0i`, `P1i`)
     - `Named2` contains exactly `R2i xi` for each `xi` in both `Named0` and `Named1` 
        - where `R0i xi` is in `Named0`
        - where `R1i xi` is in `Named1`
        - and `R2i` is **DOWN**(`R0i`, `R1i`)

- **UP**(`T Function<...>(...)`, `S Function<...>(...)`) = `Function` otherwise
- **UP**(`T1`, `T2`) = `T2` if `T1` <: `T2`
  - Note that both types must be interface types at this point
- **UP**(`T1`, `T2`) = `T1` if `T2` <: `T1`
  - Note that both types must be interface types at this point
- **UP**(`C<T0, ..., Tn>`, `C<S0, ..., Sn>`) = `C<R0,..., Rn>` where `Ri` is **UP**(`Ti`, `Si`)
- **UP**(`C0<T0, ..., Tn>`, `C1<S0, ..., Sk>`) = least upper bound of two interfaces
  as in Dart 1.

## Lower bounds

We define the lower bound of two types T1 and T2 to be **DOWN**(T1,T2) as follows.

- **DOWN**(`T`, `T`) = `T`
- **DOWN**(`T1`, `T2`) = `T1` if:
  - **TOP**(`T1`) and **TOP**(`T2`)
  - and  **MORETOP**(`T2`, `T1`)
- **DOWN**(`T1`, `T2`) = `T2` if:
  - **TOP**(`T1`) and **TOP**(`T2`)
  - and  not **MORETOP**(`T2`, `T1`)
- **DOWN**(`T1`, `T2`) = `T2` if **TOP**(`T1`)
- **DOWN**(`T1`, `T2`) = `T2` if **BOTTOM**(`T2`)
- **DOWN**(`T1`, `T2`) = `T1` if **TOP**(`T2`)
- **DOWN**(`T1`, `T2`) = `T1` if **BOTTOM**(`T1`)

- **DOWN**(`T0 Function<X0 extends B00, ... Xm extends B0m>(P00, ... P0k)`,
         `T0 Function<X0 extends B10, ... Xm extends B1m>(P10, ... P1l)` = 
   `R0 Function<X0 extends B20, ..., Xm extends B2m>(P20, ..., P2q)` if:
     - each `B0i` and `B1i` are equal types (syntactically)
     - `q` is max(`k`, `l`)
     - `R0` is **DOWN**(`T0`, `T1`)
     - `B2i` is `B0i`
     - `P2i` is **UP**(`P0i`, `P1i`) for `i` <= than min(`k`, `l`)
     - `P2i` is `P0i` for `k` < `i` <= `q`
     - `P2i` is `P1i` for `l` < `i` <= `q`
     - `P2i` is optional if `P0i` or `P1i` is optional
- **DOWN**(`T0 Function<X0 extends B00, ... Xm extends B0m>(P00, ... P0k, Named0)`,
         `T0 Function<X0 extends B10, ... Xm extends B1m>(P10, ... P1k, Named1)` = 
   `R0 Function<X0 extends B20, ..., Xm extends B2m>(P20, ..., P2k, Named2)` if:
     - each `B0i` and `B1i` are equal types (syntactically)
     - `R0` is **DOWN**(`T0`, `T1`)
     - `B2i` is `B0i`
     - `P2i` is **UP**(`P0i`, `P1i`)
     - `Named2` contains `R2i xi` for each `xi` in both `Named0` and `Named1`
        - where `R0i xi` is in `Named0`
        - where `R1i xi` is in `Named1`
        - and `R2i` is **UP**(`R0i`, `R1i`)
     - `Named2` contains `R0i xi` for each `xi` in  `Named0` and not `Named1`
     - `Named2` contains `R1i xi` for each `xi` in  `Named1` and not `Named0`

- **DOWN**(`T Function<...>(...)`, `S Function<...>(...)`) = `bottom` otherwise


- **DOWN**(`T1`, `T2`) = `T1` if `T1` <: `T2`
- **DOWN**(`T1`, `T2`) = `T2` if `T2` <: `T1`
- **DOWN**(`T1`, `T2`) = `bottom` otherwise


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
   {
    G0 x;
    G1 y;
    // Analyzer: T Function<T>(T)
    // CFE: bottom -> Object
    var a = (x == y) ? x : y;

    }
}
```

Both the CFE and the analyzer currently implement lower bounds for generic
functions incorrectly.  Example:

```dart
typedef G0 = T Function<T>(T x);
typedef G1 = T Function<T>(T x);
void main() {
  {
    void Function(G0) x;
    void Function(G1) y;
    int z;
    // Analyzer: void Function(Never Function(Object))
    // CFE:      void Function(bottom-type Function(Object))
    var a = (x == y) ? x : y;
  }
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


### FutureOr

We could choose to do better for `FutureOr<T>`.  The inference algorithm
currently special cases this for lower bounds, and it's a bit of an unpleasent
asymmetry that we deal with this in inference but not in the normal computation.
