# Dart 2.0 Static and Runtime Subtyping

leafp@google.com

**Status**: This document is now background material.
For normative text, please consult the language specification.

This is intended to define the core of the Dart 2.0 static and runtime subtyping
relation.


## Types

The syntactic set of types used in this draft are a slight simplification of
full Dart types.

The meta-variables `X`, `Y`, and `Z` range over type variables.

The meta-variables `T`, `S`, `U`, and `V` range over types.

The meta-variable `C` ranges over classes.

The meta-variable `B` ranges over types used as bounds for type variables.

As a general rule, indices up to `k` are used for type parameters and type
arguments, `n` for required value parameters, and `m` for all value parameters.

The set of types under consideration are as follows:

- Type variables `X`
- Promoted type variables `X & T` *Note: static only*
- `Object`
- `dynamic`
- `void`
- `Null`
- `Never`
- `Function`
- `Future<T>`
- `FutureOr<T>`
- `T?`
- `T*`
- Interface types `C`, `C<T0, ..., Tk>`
- Function types
  - `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])`
  - `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})`

We leave the set of interface types unspecified, but assume a class hierarchy
which provides a mapping from interfaces types `T` to the set of direct
super-interfaces of `T` induced by the superclass declaration, implemented
interfaces, and mixins of the class of `T`.  Among other well-formedness
constraints, the edges induced by this mapping must form a directed acyclic
graph rooted at `Object`.

The types `dynamic` and `void` are both referred to as *top* types, and
are considered equivalent as types (including when they appear as sub-components
of other types).  They exist as distinct names only to support distinct errors
and warnings (or absence thereof).

The type `Object` is the super type of all concrete types except `Null`.

The type `X & T` represents the result of a type promotion operation on a
variable.  In certain circumstances (defined elsewhere) a variable `x` of type
`X` that is tested against the type `T` (e.g. `x is T`) will have its type
replaced with the more specific type `X & T`, indicating that while it is known
to have type `X`, it is also known to have the more specific type `T`.  Promoted
type variables only occur statically (never at runtime).

The type `Null` represents the type of the `null` constant.

The type `Never` represents the uninhabited bottom type.

The type `T?` represents the nullable version of the type `T`, interpreted
semantically as the union type `T | Null`.

The type `T*` represents a legacy type which may be interpreted as nullable or
non-nullable as appropriate.

Given the current promotion semantics the following properties are also true:
   - If `X` has bound `B` then for any type `X & T`, `T <: B` will be true.
   - Promoted type variable types will only appear as top level types: that is,
     they can never appear as sub-components of other types, in bounds, or as
     part of other promoted type variables.


## Notation

We use `S[T0/Y0, ..., Tk/Yk]` for the result of performing a simultaneous
capture-avoiding substitution of types `T0, ..., Tk` for the type variables
`Y0, ..., Yk` in the type `S`.


## Type equality

We say that a type `T0` is equal to another type `T1` (written `T0 === T1`) if
`T0 <: T1` and `T1 <: T0`.

## Algorithmic subtyping

By convention the following rules are intended to be applied in top down order,
with exactly one rule syntactically applying.  That is, rules are written in the
form:

```
Syntactic criteria.
  - Additional condition 1
  - Additional or alternative condition 2
```

and it is the case that if a subtyping query matches the syntactic criteria for
a rule (but not the syntactic criteria for any rule preceeding it), then the
subtyping query holds iff the listed additional conditions hold.  Specifically,
once a rule has matched syntactically, the answer to the subtyping query is
entirely given by that rule: it is never necessary to try subsequent rules.

This makes the rules algorithmic, because they correspond in an obvious manner
to an algorithm with an acceptable time complexity, and it makes them syntax
directed because the overall structure of the algorithm corresponds to specific
syntactic shapes. We will use the word _algorithmic_ to refer to this property.

The runtime subtyping rules can be derived by eliminating all clauses dealing
with promoted type variables.


### Rules

**Note the convention described in the section above**

We say that a type `T0` is a subtype of a type `T1` (written `T0 <: T1`) when:

- **Reflexivity**: if `T0` and `T1` are the same type then `T0 <: T1`
  - *Note that this check is necessary as the base case for primitive types, and
    type variables but not for composite types.  In particular, algorithmically
    a structural equality check is admissible, but not required
    here. Pragmatically, non-constant time identity checks here are
    counter-productive*

- **Right Top**: if `T1` is a top type (i.e. `dynamic`, or `void`, or `Object?`)
  then `T0 <: T1`

- **Left Top**: if `T0` is `dynamic` or `void`
  then `T0 <: T1` if `Object? <: T1`

- **Left Bottom**: if `T0` is `Never` then `T0 <: T1`

- **Right Object**: if `T1` is `Object` then:
    - if `T0` is an unpromoted type variable with bound `B` then `T0 <: T1` iff
      `B <: Object`
    - if `T0` is a promoted type variable `X & S` then `T0 <: T1` iff `S <:
      Object`
    - if `T0` is `FutureOr<S>` for some `S`, then `T0 <: T1` iff `S <: Object`.
    - if `T0` is `S*` for any `S`, then `T0 <: T1` iff `S <: T1`
    - if `T0` is `Null`, `dynamic`, `void`, or `S?` for any `S`, then the
      subtyping does not hold (per above, the result of the subtyping query is
      false).
    - Otherwise `T0 <: T1` is true.

- **Left Null**: if `T0` is `Null` then:
  - if `T1` is a type variable (promoted or not) the query is false
  - If `T1` is `FutureOr<S>` for some `S`, then the query is true iff `Null <:
    S`.
  - If `T1` is `Null`, `S?` or `S*` for some `S`, then the query is true.
  - Otherwise, the query is false

- **Left Legacy** if `T0` is `S0*` then:
  - `T0 <: T1` iff `S0 <: T1`.

- **Right Legacy** `T1` is `S1*` then:
  - `T0 <: T1` iff `T0 <: S1?`.

- **Left FutureOr**: if `T0` is `FutureOr<S0>` then:
  - `T0 <: T1` iff  `Future<S0> <: T1` and `S0 <: T1`

- **Left Nullable**: if `T0` is `S0?` then:
  - `T0 <: T1` iff  `S0 <: T1` and `Null <: T1`

- **Type Variable Reflexivity 1**: if `T0` is a type variable `X0` or a
promoted type variables `X0 & S0` and `T1` is `X0` then:
  - `T0 <: T1`
  - *Note that this rule is admissible, and can be safely elided if desired*

- **Type Variable Reflexivity 2**: if `T0` is a type variable `X0` or a
promoted type variables `X0 & S0` and `T1` is `X0 & S1` then:
  - `T0 <: T1` iff `T0 <: S1`.
  - *Note that this rule is admissible, and can be safely elided if desired*

- **Right Promoted Variable**: if `T1` is a promoted type variable `X1 & S1` then:
  - `T0 <: T1` iff  `T0 <: X1` and `T0 <: S1`

- **Right FutureOr**: if `T1` is `FutureOr<S1>` then:
  - `T0 <: T1` iff any of the following hold:
    - either `T0 <: Future<S1>`
    - or `T0 <: S1`
    - or `T0` is `X0` and `X0` has bound `S0` and `S0 <: T1`
    - or `T0` is `X0 & S0` and `S0 <: T1`

- **Right Nullable**: if `T1` is `S1?` then:
  - `T0 <: T1` iff any of the following hold:
    - either `T0 <: S1`
    - or `T0 <: Null`
    - or `T0` is `X0` and `X0` has bound `S0` and `S0 <: T1`
    - or `T0` is `X0 & S0` and `S0 <: T1`

- **Left Promoted Variable**: `T0` is a promoted type variable `X0 & S0`
  - and `S0 <: T1`

- **Left Type Variable Bound**: `T0` is a type variable `X0` with bound `B0`
  - and `B0 <: T1`

- **Function Type/Function**: `T0` is a function type and `T1` is `Function`

- **Interface Compositionality**: `T0` is an interface type `C0<S0, ..., Sk>`
  and `T1` is `C0<U0, ..., Uk>`
  - and each `Si <: Ui`

- **Super-Interface**: `T0` is an interface type with super-interfaces `S0,...Sn`
  - and `Si <: T1` for some `i`

- **Positional Function Types**: `T0` is
  `U0 Function<X0 extends B00, ..., Xk extends B0k>(V0 x0, ..., Vn xn, [Vn+1 xn+1, ..., Vm xm])`
  - and `T1` is
    `U1 Function<Y0 extends B10, ..., Yk extends B1k>(S0 y0, ..., Sp yp, [Sp+1 yp+1, ..., Sq yq])`
  - and `p >= n`
  - and `m >= q`
  - and `Si[Z0/Y0, ..., Zk/Yk] <: Vi[Z0/X0, ..., Zk/Xk]` for `i` in `0...q`
  - and `U0[Z0/X0, ..., Zk/Xk] <: U1[Z0/Y0, ..., Zk/Yk]`
  - and `B0i[Z0/X0, ..., Zk/Xk] === B1i[Z0/Y0, ..., Zk/Yk]` for `i` in `0...k`
  - where the `Zi` are fresh type variables with bounds `B0i[Z0/X0, ..., Zk/Xk]`

- **Named Function Types**: `T0` is
  `U0 Function<X0 extends B00, ..., Xk extends B0k>(V0 x0, ..., Vn xn, {r0n+1 Vn+1 xn+1, ..., r0m Vm xm})`
  where `r0j` is empty or `required` for `j` in `n+1...m`
  - and `T1` is
    `U1 Function<Y0 extends B10, ..., Yk extends B1k>(S0 y0, ..., Sn yn, {r1n+1 Sn+1 yn+1, ..., r1q Sq yq})`
    where `r1j` is empty or `required` for `j` in `n+1...q`
  - and `{yn+1, ... , yq}` subsetof `{xn+1, ... , xm}`
  - and `Si[Z0/Y0, ..., Zk/Yk] <: Vi[Z0/X0, ..., Zk/Xk]` for `i` in `0...n`
  - and `Si[Z0/Y0, ..., Zk/Yk] <: Tj[Z0/X0, ..., Zk/Xk]` for `i` in `n+1...q`, `yj = xi`
  - and for each `j` such that `r0j` is `required`, then there exists an
    `i` in `n+1...q` such that `xj = yi`, and `r1i` is `required`
  - and `U0[Z0/X0, ..., Zk/Xk] <: U1[Z0/Y0, ..., Zk/Yk]`
  - and `B0i[Z0/X0, ..., Zk/Xk] === B1i[Z0/Y0, ..., Zk/Yk]` for `i` in `0...k`
  - where the `Zi` are fresh type variables with bounds `B0i[Z0/X0, ..., Zk/Xk]`

*Note: the requirement that `Zi` are fresh is as usual strictly a requirement
that the choice of common variable names avoid capture.  It is valid to choose
the `Xi` or the `Yi` for `Zi` so long as capture is avoided*


## Derivation of algorithmic rules

This section sketches out the derivation of the algorithmic rules from the
interpretation of `FutureOr<T>` and `T?` as union types, and promoted type
bounds as intersection types, based on standard rules for such types that do not
satisfy the requirements for being algorithmic.

### Non-algorithmic rules

The non-algorithmic rules that we derive from first principles of union and
intersection types are as follows, where: `S0 | S1` stands in for either
`FutureOr<S>` (in which case `S0` is `Future<S>` and `S1` is S) or `S?` (in
which case `S0` is `S`, and `S1` is `Null`); and `S0 & S1` stands in for
`X & S` (in which case `S0` is `X` and `S1` is `S`).

Left union introduction:
 - `S0 | S1 <: T` if `S0 <: T` and `S1 <: T`

Right union introduction:
 - `S <: T0 | T1` if `S <: T0` or `S <: T1`

Left intersection introduction:
 - `S0 & S1 <: T` if `S0 <: T` or `S1 <: T`

Right intersection introduction:
 - `S <: T0 & T1` if `S <: T0` and `S <: T1`

Axiom for `Object`:

Right nullable `Object`:
 - `T <: Object?`

The declarative legacy subtyping rules are derived from the possible completions
of the legacy type to a non-legacy type.

Right legacy introduction:
  - `T* <: S` if `T <: S` or `T? <: S`

Left legacy introduction:
  - `T <: S*` if `T <: S` or `T <: S?`


The only remaining non-algorithmic rule is the variable bounds rule:

Variable bounds:
  - `X <: T` if `X extends B` and `B <: T`

All other rules are algorithmic.

### Preliminaries

**Lemma 1**: If there is any derivation of `S0 | S1 <: T` (that is, either
`FutureOr<S> <: T` or `S? <: T`), then there is a derivation ending in a use of
left union introduction.

Proof.  By induction on derivations.  Consider a derivation of `S0 | S1 <:
T`.

If the last rule applied is:
  - Top type rules (including nullable object) are trivial.

  - Object, Null, Never, Function and interface rules can't apply.

  - Left union introduction rule is immediate.

  - Right union introduction. Then `T` is of the form `T0 | T1` and either
    - we have a sub-derivation of `S0 | S1 <: T0`
      - by induction we therefore have a derivation ending in left union
       introduction, so by inversion we have:
         - a derivation of `S0 <: T0 `, and so by right union
           introduction we have `S0 <: T0 | T1`
         - a derivation of `S1 <: T0 `, and so by right union
           introduction we have `S1 <: T0 | T1`
      - by left union introduction, we have `S0 | S1 <: T0 | T1`
      - QED
    - we have a sub-derivation of `S0 | S1 <: T1`
      - by induction we therefore have a derivation ending in left union
       introduction, so by inversion we have:
         - a derivation of `S0 <: T1 `, and so by right union
           introduction we have `S0 <: T0 | T1`
         - a derivation of `S1 <: T1 `, and so by right union
           introduction we have `S1 <: T0 | T1`
      - by left union introduction, we have `S0 | S1 <: T0 | T1`
      - QED

  - Right intersection introduction.  Then `T` is of the form `T0 & T1`, and
     - we have sub-derivations `S0 | S1 <: T0` and `S0 | S1 <: T1`
     - By induction, we can get derivations of the above ending in left union
       introduction, so by inversion we have derivations of:
       - `S0 <: T0`, `S1 <: T0`, `S0 <: T1`, `S1 <: T1`
         - so we have derivations of `S0 <: T0`, `S0 <: T1`, so by right
           intersection introduction we have
           - `S0 <: T0 & T1`
         - so we have derivations of `S1 <: T0`, `S1 <: T1`, so by right
           intersection introduction we have
           - `S1 <: T0 & T1`
     - so by left union introduction, we have a derivation of `S0 | S1 <: T0 & T1`

  - Left legacy introduction cannot apply

  - Right legacy introduction.  Then `T` is of the form `T0*`, and
     - we have one of the following cases for the immediate sub-derivation:
       - if we have `S0 | S1 <: T`, then by induction, there is a derivation
         ending in a use of left union introduction, so by inversion we have:
         - a derivation of `S0 <: T`, so by right legacy introduction we have
           `S0 <: T*`
         - a derivation of `S1 <: T`, so by right legacy introduction we have
           `S1 <: T*`
         - so by left union introduction we have `S0 | S1 <: T*`
       - if we have `S0 | S1 <: T?`, then by induction, there is a derivation
         ending in a use of left union introduction, so by inversion we have:
         - a derivation of `S0 <: T?`, so by right legacy introduction we have
           `S0 <: T*`
         - a derivation of `S1 <: T?`, so by right legacy introduction we have
           `S1 <: T*`
         - so by left union introduction we have `S0 | S1 <: T*`

- QED

Note: The reverse is not true.  Counter-example:

Given arbitrary `B <: A`, suppose we wish to show that `(X extends FutureOr<B>)
<: FutureOr<A>`.  If we apply right union introduction first, we must show
either:
  - `X <: Future<A>`
  - only variable bounds rule applies, so we must show
    - `FutureOr<B> <: Future<A>`
    - Only left union introduction applies, so we must show both of:
      - `Future<B> <: Future<A>` (yes)
      - `B <: Future<A>` (no)
  - `X <: A`
  - only variable bounds rule applies, so we must show that
    - `FutureOr<B> <: A`
    - Only left union introduction applies, so we must show both of:
      - `Future<B> <: Future<A>` (no)
      - `B <: Future<A>` (yes)

On the other hand, the derivation via first applying the variable bounds rule is
trivial.

Note though that we can also not simply always apply the variable bounds rule
first.  Counter-example:

Given `X extends Object`, it is trivial to derive `X <: FutureOr<X>` via the
right union introduction rule.  But applying the variable bounds rule doesn't
work.

**Lemma 2**: If there is any derivation of `S <: T0 & T1`, then there is
derivation ending in a use of right intersection introduction.

Proof.  By induction on derivations.  Consider a derivation D of `S <: T0 & T1`.

If last rule applied in D is:
  - Never and non-nullable Null rules are trivial.

  - Top types cannot apply.

  - Function and interface type rules can't apply.

  - Right intersection introduction then we're done.

  - Left intersection introduction. Then `S` is of the form `S0 & S1`, and either
    - we have a sub-derivation of `S0 <: T0 & T1`
      - by induction we therefore have a derivation ending in right intersection
       introduction, so by inversion we have:
         - a derivation of `S0 <: T0 `, and so by left intersection
           introduction we have `S0 & S1 <: T0`
         - a derivation of `S0 <: T1 `, and so by left intersection
           introduction we have `S0 & S1 <: T1`
      - by right intersection introduction, we have `S0 & S1 <: T0 & T1`
      - QED
    - we have a sub-derivation of `S1 <: T0 & T1`
      - by induction we therefore have a derivation ending in right intersection
       introduction, so by inversion we have:
         - a derivation of `S1 <: T0`, and so by left intersection
           introduction we have `S0 & S1 <: T0`
         - a derivation of `S1 <: T1`, and so by left intersection
           introduction we have `S0 & S1 <: T1`
     - by right intersection introduction, we have `S0 & S1 <: T0 & T1`
     - QED

  - Left union introduction.  Then `S` is of the form `S0 | S1`, and
     - we have sub-derivations `S0 <: T0 & T1` and `S1 <: T0 & T1`
     - By induction, we can get derivations of the above ending in right intersection
       introduction, so by inversion we have derivations of:
       - `S0 <: T0`, `S1 <: T0`, `S0 <: T1`, `S1 <: T1`
         - so we have derivations of `S0 <: T0`, `S1 <: T0`, so by left
           union introduction we have
           - `S0 | S1 <: T0`
         - so we have derivations of `S0 <: T1`, `S1 <: T1`, so by left
           union introduction we have
           - `S0 | S1 <: T1`
     - so by right intersection introduction, we have a derivation of `S0 | S1 <: T0 & T1`

  - Right union introduction can't apply.

  - Left legacy introduction.  Then `S` is of the form `S0*`, and either
    - we have a sub-derivation of `S0 <: T0 & T1`
      - by induction we therefore have a derivation ending in right intersection
       introduction, so by inversion we have:
         - a derivation of `S0 <: T0 `, and so by left intersection
           introduction we have `S0* <: T0`
         - a derivation of `S0 <: T1 `, and so by left intersection
           introduction we have `S0* <: T1`
      - by right intersection introduction, we have `S0* <: T0 & T1`
      - QED
    - we have a sub-derivation of `S0? <: T0 & T1`
      - by induction we therefore have a derivation ending in right intersection
       introduction, so by inversion we have:
         - a derivation of `S0? <: T0 `, and so by left intersection
           introduction we have `S0* <: T0`
         - a derivation of `S0? <: T1 `, and so by left intersection
           introduction we have `S0* <: T1`
      - by right intersection introduction, we have `S0* <: T0 & T1`
      - QED

  - Right legacy introduction can't apply.

  - Variable bounds rule.  Then `S` is of the form `X` where `X extends B` and
    we have a derivation of `B <: T0 & T1`.
    - By induction, we have derivation ending in right intersection
      introduction, so by inversion we have:
      - a derivation of `B <: T0`, and so by the variable bounds rule we have `X
        <: T0`.
      - a derivation of `B <: T1`, and so by the variable bounds rule we have `X
        <: T1`.
    - So by right intersection introduction, we have `X <: T0 & T1`.

- QED


**Observation 1**:
  - If `T <: S` is derivable, then `T <: S?` is derivable by right union
    introduction
  - If `T? <: S` is derivable, then `T <: S` is derivable since by lemma 1 there
    is a derivation ending in left union introduction, and hence there is a
    sub-derivation of `T <: S`.

This observation justifies the following simpler derived rules for the legacy
types:

Left legacy introduction (derived):
  - `T* <: S` if `T <: S`

Right legacy introduction (derived):
  - `T <: S*` if `T <: S?`


**Lemma 3**: If there is any derivation of `S* <: T`, then there is a derivation
ending in a use of left legacy introduction.

Proof.  By induction on derivations.  Consider a derivation of `S* <:
T`.

If the last rule applied is:
  - Top type rules are trivial.

  - Object is trivial

  - Null, Never, Function and interface rules can't apply.

  - Left union introduction rule doesn't apply.

  - Right union introduction. Then `T` is of the form `T0 | T1` and either
    - we have a sub-derivation of `S* <: T0`
      - by induction we therefore have a derivation ending in left legacy
       introduction
        - so by inversion we have a derivation of `S <: T0 `
        - so by right union introduction we have `S <: T0 | T1`
      - so by left legacy introduction, we have `S* <: T0 | T1`
      - QED
    - we have a sub-derivation of `S* <: T1`
      - by induction we therefore have a derivation ending in left legacy
       introduction
        - so by inversion we have a derivation of `S <: T1 `
        - so by right union introduction we have `S <: T0 | T1`
      - so by left legacy introduction, we have `S* <: T0 | T1`
      - QED

  - Left intersection introduction cannot apply.

  - Right intersection introduction.  Then `T` is of the form `T0 & T1`, and
     - we have sub-derivations `S* <: T0` and `S* <: T1`
     - By induction, we can get derivations of the above ending in left legacy
       introduction.
     - so by inversion we have derivations of `S <: T0` and  `S <: T1`
     - so by right intersection introduction we have a derivation of `S <: T0 &
       T1`
     - so by left legacy introduction we have a derivation of `S* <: T0 & T1`

  - Left legacy introduction is immediate.

  - Right legacy introduction.  Then `T` is of the form `T0*`, and
     - by inversion we have a derivation of `S* <: T0?`
     - by induction we have a derivation of this ending in left legacy
       introduction, and hence by inversion we have a derivation of `S <: T0?`
     - by right legacy introduction we have `S <: T0*`
     - by left legacy introduction we have `S* <: T0*`
  - QED

**Lemma 4**: If there is any derivation of `S <: T*`, then there is
derivation ending in a use of right legacy introduction.

Proof.  By induction on derivations.  Consider a derivation D of `S <: T*`.

If last rule applied in D is:
  - Never rule is trivial.

  - Top, Function and interface type rules can't apply.

  - Left intersection introduction. Then `S` is of the form `S0 & S1`, and either
    - we have a sub-derivation of `S0 <: T*`
      - by induction we therefore have a derivation ending in right legacy
        introduction, so by inversion we have a derivation of `S0 <: T?`
      - so by left intersection introduction we have `S0 & S1 <: T?`
      - so we have `S0 & S1 <: T*` by right legacy introduction.
    - we have a sub-derivation of `S1 <: T*`
      - by induction we therefore have a derivation ending in right legacy
        introduction, so by inversion we have a derivation of `S1 <: T?`
      - so by left intersection introduction we have `S0 & S1 <: T?`
      - so we have `S0 & S1 <: T*` by right legacy introduction.

  - Right intersection introduction doesn't apply

  - Left union introduction.  Then `S` is of the form `S0 | S1`, and
     - we have sub-derivations `S0 <: T*` and `S1 <: T*`
     - By induction, we can get derivations of the above ending in right legacy
       introduction, so by inversion we have derivations of `S0 <: T?`, `S1 <:
       T?`
     - so by left union introduction we have `S0 | S1 <: T?`
     - so by right legacy introduction we have `S0 | S1 <: T*`

  - Right union introduction can't apply.

  - Left legacy introduction.  Then `S` is of the form `S0*`, and we have a
    sub-derivation of `S0 <: T*`
      - by induction we therefore have a derivation ending in right legacy
       introduction
      - so by inversion we have a derivation of `S0 <: T0?`
      - so by left legacy introduction we have `S0* <: T0?`
      - so by right legacy introduction, we have `S0* <: T0*`
      - QED

  - Right legacy introduction is immediate.

  - Variable bounds rule.  Then `S` is of the form `X` where `X extends B` and
    we have a derivation of `B <: T*`.
    - By induction, we have a derivation ending in right legacy
      introduction, so by inversion we have a derivation of `B <: T?`
    - so by the variables bounds rule, we have `X <: T?`
    - so by right legacy introduction we have `X <: T*`
- QED


**Note**: It is easy to see that `A <: B` implies `FutureOr<A> <: FutureOr<B>`,
but the converse does not hold.  Counter-example (due to @fishythefish):

Consider a class `A` which implements `Future<Future<A>>` (such a class is
definable in Dart).  Let `B` be `Future<A>`.  Note that `A <: B` is not
derivable, since to show this requires that `Future<Future<A>> <: Future<A>`
(super-interface), which requires that `Future<A> <: A`, which does not hold.

But we *can* show that `FutureOr<A> <: FutureOr<B>` as follows:
  - It suffices to show that `A <: FutureOr<B>` and `Future<A> <: FutureOr<B>`
    - To show that `A <: FutureOr<B>`, it suffices to show that `A <:
      Future<B>`, which holds by the super-interface rule plus identity.
    - To show that `Future<A> <: FutureOr<B>` it suffices to show that
      `Future<A> <: B` which holds by identity.

**Lemma 10**: Transitivity of subtyping without the legacy type rules is
admissible.  Given derivations of `A <: B` and `B <: C` which does not use any
of the legacy rules, then there is a derivation of `A <: C` which also does not
use any of the legacy rules.

Proof sketch: The proof should go through by induction on sizes of derivations,
cases on pairs of rules used.  For any pair of rules used, we can construct a
new derivation of the desired result using only smaller derivations.


**Observation 2**: Given `X` with bound `S`, we have the property that for all
instances of `X & T`, `T <: S` will be true, and hence `S <: M => T <: M`.

**Observation 3**: The following are not derivable for any `T`:
  - `T?` <: `Object`, since by lemma 1 we must have `Null <: Object`
  - `Null <: X` for any unpromoted type variable `X`
    - there are no typing rules which apply
  - `Null <: X & T` for any promoted type variable `X`
    - the only rule that applies is left intersection introduction, which in
      turn requires that `Null <: X`.

**Observation 4**: The following are derivable for any `T`:
  - `Null <: T?`, since it suffices to show that `Null <: Null`
  - `Null <: T*`, since it suffices to show that `Null <: T?`



### Algorithmic rules

Consider `T0 <: T1`.

#### True top on the right

If `T1` is `dynamic` or `void` or `Object?` the query is true.

#### True bottom on the left

If `T0` is `Never` the query is true.

#### `Object` 

If `T1` is `Object`: 
  - if `T0` is an unpromoted type variable with bound `B`, the query is true iff
    `B <: Object` is true.
    - The only rule that can apply is the variable bounds rule.
  - if `T0` is a promoted type variable `X & S` with bound `B` then the query is
    true iff `S <: Object` is true
    - The only rule that applies is left intersection introduction
    - Hence we must show `X <: Object` or `S <: Object`. For the former, the
      only rule which applies is the variable bounds rule, so it suffices to
      show that `B <: Object` and `S <: Object`.  But by observation 2, we have
      that `S <: B`, so it suffices to show that `S <: Object`.
  - If `T0` is `FutureOr<S>` for some `S`, then the query is true iff `S <: Object`.
    - By lemma 1, it suffices to show that `Future<S> <: Object` and `S <:
      Object`, and the former holds immediately.
  - If `T0` is `Null`, `dynamic`, `void`, or `S?` for any `S`, the query is
    false.
    - By Observation 3 above
  - If `T0` is `S*` for any `S`, the query is true iff `S <: Object` by lemma 3.
  - Otherwise the query is true.
    - In this case, `T0` must be `Object`, a function type, or interface type. 

#### `Null` 

If `T0` is `Null` 
  - if `T1` is a type variable (promoted or not) the query is false
    - By observation 3
  - If `T1` is `FutureOr<S>` for some `S`, then the query is true iff `Null <: S`.
    - The only rule that applies is right union introduction which requires
      either `Null <: Future<S>` or `Null <: S`.  The former is never true so it
      suffices to check the latter.
  - If `T1` is `Null`, `S?` or `S*` for some `S`, then the query is true.
    - By Observaton 4 above
  - Otherwise, the query is false
    - In this case, `T1` is `Object`, a function type, or an interface type.

#### Legacy on the left

If `T0` is `S*` for some `S`, the query is true iff `S <: T1` is true
  - By lemma 3 above, and the derived version of the legacy left introduction
    rule

#### Legacy on the right

If `T1` is `S*` for some `S`, the query is true iff `T0 <: S?` is true
  - By lemma 4 above, and the derived version of the legacy right introduction
    rule.

#### Union on the left

By lemma 1, if `T0` is of the form `FutureOr<S0>` and there is any derivation of
`T0 <: T1`, then there is a derivation ending with a use of left union
introduction so we have the rule:

- `T0` is `FutureOr<S0>`
  - and `Future<S0> <: T1`
  - and `S0 <: T1`

By lemma 1, if `T0` is of the form `S0?` and there is any derivation of
`T0 <: T1`, then there is a derivation ending with a use of left union
introduction so we have the rule:

- `T0` is `S0?`
  - and `S0 <: T1`
  - and `Null <: T1`


#### Identical type variables

If `T0` and `T1` are both the same unpromoted type variable, then subtyping
holds by reflexivity.  If `T0` is a promoted type variable `X0 & S0`, and `T0`
is `X0` then it suffices to show that `X0 <: X0` or `S0 <: X0`, and the former
holds immediately.  This justifies the rule:

- `T0` is a type variable `X0` or a promoted type variables `X0 & S0` and `T1`
is `X0`.

If `T0` is `X0` or `X0 & S0` and `T1` is `X0 & S1`, then by lemma 1 it suffices
to show that `X0 & S0 <: X0` and `X0 & S0 <: S1`.  The first holds immediately
by reflexivity on the type variable, so it is sufficient to check `T0 <: S1`.

- `T0` is a type variable `X0` or a promoted type variables `X0 & S0` and `T1`
is `X0 & S1`
  - and `T0 <: S1`.

*Note that neither of these type variable rules are required to make the rules
algorithmic: they are merely useful special cases of the next rule.*


#### Intersection on the right

By lemma 2, if `T1` is of the form `X1 & S1` and there is any derivation of `T0
<: T1`, then there is a derivation ending with a use of right intersection
introduction, hence the rule:

- `T1` is a promoted type variable `X1 & S1`
  - and `T0 <: X1`
  - and `T0 <: S1`

#### Union on the right

Suppose `T1` is `FutureOr<S1>`. The rules above have eliminated the possibility
that `T0` is of the form `FutureOr<S0>`, `S0*`, or `S0?`.  The only rules that
could possibly apply then are right union introduction, left intersection
introduction, or the variable bounds rules.  Combining these yields the
following preliminary disjunctive rule:

- `T1` is `FutureOr<S1>` and
  - either `T0 <: Future<S1>`
  - or `T0 <: S1`
  - or `T0` is `X0` and `X0` has bound `S0` and `S0 <: T1`
  - or `T0` is `X0 & S0` and `X0 <: T1` and `S0 <: T1`

The last disjunctive clause can be further simplified to
  - or `T0` is `X0 & S0` and `S0 <: T1`

since the premise `X0 <: FutureOr<S1>` can only be derived either using the
variable bounds rule or right union introduction.  For the variable bounds rule,
the premise `B0 <: T1` is redundant with `S0 <: T1` by observation 2.  For right
union introduction, `X0 <: S1` is redundant with `T0 <: S1`, since if `X0 <: S1`
is derivable, then `T0 <: S1` is derivable by left intersection introduction;
and `X0 <: Future<S1>` is redundant with `T0 <: Future<S1>`, since if the former
is derivable, then the latter is also derivable by left intersection
introduction.  So we have the final rule:

- `T1` is `FutureOr<S1>` and
  - either `T0 <: Future<S1>`
  - or `T0 <: S1`
  - or `T0` is `X0` and `X0` has bound `S0` and `S0 <: T1`
  - or `T0` is `X0 & S0` and `S0 <: T1`


Suppose `T1` is `S1?`. The rules above have eliminated the possibility that `T0`
is of the form `FutureOr<S0>`, `S0*`, or `S0?`.  The only rules that could
possibly apply then are right union introduction, left intersection
introduction, or the variable bounds rules.  Combining these yields the
following preliminary disjunctive rule:

- `T1` is `S1?` and
  - either `T0 <: S1`
  - or `T0 <: Null`
  - or `T0` is `X0` and `X0` has bound `S0` and `S0 <: T1`
  - or `T0` is `X0 & S0` and `X0 <: T1` and `S0 <: T1`

The last disjunctive clause can be further simplified to
  - or `T0` is `X0 & S0` and `S0 <: T1`

since the premise `X0 <: S1?` can only be derived either using the variable
bounds rule or right union introduction.  For the variable bounds rule, the
premise `B0 <: T1` is redundant with `S0 <: T1` by observation 2.  For right
union introduction, `X0 <: S1` is redundant with `T0 <: S1`, since if `X0 <: S1`
is derivable, then `T0 <: S1` is derivable by left intersection introduction;
and `X0 <: Null` is redundant with `T0 <: Null`, since if the former
is derivable, then the latter is also derivable by left intersection
introduction.  So we have the final rule:

- `T1` is `S1?` and
  - either `T0 <: S1`
  - or `T0 <: Null`
  - or `T0` is `X0` and `X0` has bound `S0` and `S0 <: T1`
  - or `T0` is `X0 & S0` and `S0 <: T1`


#### Intersection on the left

At this point, we've eliminated the possibility that `T1` is `FutureOr<S1>`, the
possibility that `T1` is `S1?`, the possibility that `T1` is `S1*`, the
possibility that `T1` is `X1 & S1`, the possibility that `T1` is any variant of
`X0`, and the possibility that `T1` is any of the top types, or `Object`.  The
only remaining possibilities for `T1` are function types or non-top interfaces
types.

Suppose `T0` is `X0 & S0`. Given that we have eliminated all of the structural
types as possibilities for `T1`, the only remaining rule that applies is left
intersection introduction, and so it suffices to check that `X0 <: T1` and `S0
<: T1`.  But given the remaining possible forms for `T1`, the only rule that can
apply to `X0 <: T1` is the variable bounds rule, which by observation 2 is
redundant with the second premise, and so we have the rule:

`T0` is a promoted type variable `X0 & S0`
  - and `S0 <: T1`

#### Type variable on the left

Suppose `T0` is `X0`.  Given that we have eliminated all of the structural types
as possibilities for `T1`, the only rule that applies is the variable bounds
rule:

`T0` is a type variable `X0` with bound `B0`
  - and `B0 <: T1`

This eliminates all of the non-algorithmic rules: the remainder are strictly
syntax driven.

## Changelog

* July 12th, 2019: Replaced conjecture on FutureOr subtyping with counter-example.
* Jan 29th, 2019: Fixed legacy rules.
* Dec 19th, 2018: Added subtyping for nullable types and transitional legacy
  types.
