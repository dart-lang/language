# Flow Analysis for Non-nullability

paulberry@google.com, leafp@google.com

This is roughly based on the proposal discussed in
https://docs.google.com/document/d/11Xs0b4bzH6DwDlcJMUcbx4BpvEKGz8MVuJWEfo_mirE/edit.

**Status**: Draft.

## CHANGELOG

2019.01.16
  - Modify `restrictV` to make a variable definitely assigned in a try block or
    a finally block definitely assigned after the block.
  - Clarify that initialization promotion does not apply to formal parameters.

## Summary

This defines the local analysis (within function and method bodies) that
underlies type promotion, definite assignment analysis, and reachability
analysis.

## Motivation

The Dart language spec requires type promotion analysis to determine when a
local variable is known to have a more specific type than its declared type.  We
believe additional enhancement is necessary to support NNBD (“non-nullability by
default”) including but not limited to
the
[Enhanced Type Promotion]( https://github.com/dart-lang/language/blob/master/working/enhanced-type-promotion/feature-specification.md) proposal
(see [tracking issue](https://github.com/dart-lang/language/issues/81)).

For example, we should be able to handle these situations:

```dart
int stringLength1(String? stringOrNull) {
  return stringOrNull.length; // error stringOrNull may be null
}

int stringLength2(String? stringOrNull) {
  if (stringOrNull != null) return stringOrNull.length; // ok
  return 0;
}
```

The language spec also requires a small amount of reachability analysis,
to ensure control flow does not reach the end of a switch case.
To support NNBD a more complete form of reachability analysis is necessary to detect
when control flow “falls through” to the end of a function body and an implicit `return null;`,
which would be an error in a function with a non-nullable return type.
This would include but not be limited to the existing
[Define 'statically known to not complete normally'](https://github.com/dart-lang/language/issues/139)
proposal.

For example, we should correctly detect this error situation:

```dart
int stringLength3(String? stringOrNull) {
  if (stringOrNull != null) return stringOrNull.length;
} // error implied null return value

int stringLength4(String? stringOrNull) {
  if (stringOrNull != null) {
    return stringOrNull.length;
  } else {
    return 0;
  }
} // ok!
```

Finally, to support NNBD, we believe definite assignment analysis should be
added to the spec, so that a user is not required to initialize non-nullable
local variables if it can be proven that they will be assigned a non-null value
before being read.


## Terminology and Notation

We use the generic term *node* to denote an expression, statement, top level
function, method, constructor, or field.  We assume that all nodes are labelled
uniquely in some unspecified fashion such that mappings can be maintained from
nodes to the results of flow analysis.

The flow analysis assumes that the set of variables which are assigned in any
given node has been pre-computed, and can be queried by a predicate **Assigned**
such that for a node `N` and a variable `v`, **Assigned**(`N`, `v`) is true iff
`N` syntactically contains an assignment to `v` (regardless of reachability of
that assignment).

### Basic data structures


- Maps
  - We use the notation `{x: VM1, y: VM2}` to denote a map associating the
    key `x` with the value `VM1`, and the key `y` with the value `VM2`.
  - We use the notation `VI[x -> VM]` to denote the map which maps every key
    in `VI` to its corresponding value in `VI` except `x`, which is mapped to
    `VM` in the new map (regardless of any value associated with it in `VI`).

- Lists
  - We use the notation `[a, b]` to denote a list containing elements `a` and
    `b`.
  - We use the notation `a::l` where `l` is a list to denote a list beginning
    with `a` and followed by all of the elements of `l`.

- Stacks
  - We use the notation `push(s, x)` to mean pushing `x` onto the top of the
    stack `s`.
  - We use the notation `pop(s)` to mean the stack that results from removing
    the top element of `s`.  If `s` is empty, the result is undefined.
  - We use the notation `top(s)` to mean the top element of the stack `s`.  If
    `s` is empty, the result is undefined.
  - Informally, we also use `a::t` to describe a stack `s` such that `top(s)` is
    `a` and `pop(s)` is `t`.

### Models

A *variable model*, denoted `VariableModel(declaredType, promotedTypes,
tested, assigned, unassigned, writeCaptured)`, represents what is statically
known to the flow analysis about the state of a variable at a given point in the
source code.

- `declaredType` is the type assigned to the variable at its declaration site
  (either explicitly or by type inference).

- `promotedTypes` is an ordered set of types that the variable has been promoted
  to, with the final entry in the ordered set being the current promoted type of
  the variable.  Note that each entry in the ordered set must be a subtype of
  all previous entries, and of the declared type.

- `tested` is a set of types which are considered "of interest" for the purposes
  of promotion, generally because the variable in question has been tested
  against the type on some path in some way.

- `assigned` is a boolean value indicating whether the variable is known to
  have been definitely assigned at the given point in the source code.

- `unassigned` is a boolean value indicating whether the variable is known not
  to have been definitely assigned at the given point in the source code.  (Note
  that a variable may not be both definitely assigned and definitely
  unassigned).

- `writeCaptured` is a boolean value indicating whether a closure might exist at
  the given point in the source code, which could potentially write to the
  variable.

A *flow model*, denoted `FlowModel(reachable, variableInfo)`, represents what
is statically known to flow analysis about the state of the program at a given
point in the source code.

  - `reachable` is a stack of boolean values modeling the reachability of the
  given point in the source code.  The `i`th element of the stack (counting from
  the top of the stack) encodes whether the `i-1`th enclosing control flow split
  is reachable from the `ith` enclosing control flow split (or when `i` is 0,
  whether the current program point is reachable from the enclosing control flow
  split).  So if the bottom element of `reachable` is `false`, then the current
  program point is definitively known by flow analysis to be unreachable from
  the first enclosing control flow split.  If it is `true`, then the analysis
  cannot eliminate the possibility that the given point may be reached by some
  path.  Each other element of the stack models the same property, starting from
  some control flow split between the start of the program and the current node,
  and treating the entry to the program as the initial control flow split.  The
  true reachability of the current program point then is the conjunction of the
  elements of the `reachable` stack, since each element of the stack models the
  reachability of one control flow split from its enclosing control flow split.

  - `variableInfo` is a mapping from variables in scope at the given point to
  their associated *variable model*s.

The following functions associate flow models to nodes:

- `before(N)`, where `N` is a statement or expression, represents the *flow
  model* just prior to execution of `N`.

- `after(N)`, where `N` is a statement or expression, represents the *flow
  model* just after execution of `N`, assuming that `N` completes normally
  (i.e. does not throw an exception or perform a jump such as `return`, `break`,
  or `continue`).

- `true(E)`, where `E` is an expression, represents the *flow model* just after
  execution of `E`, assuming that `E` completes normally and evaluates to `true`.

- `false(E)`, where `E` is an expression, represents the *flow model* just after
  execution of `E`, assuming that `E` completes normally and evaluates to `false`.

- `null(E)`, where `E` is an expression, represents the *flow model* just after
  execution of `E`, assuming that `E` completes normally and evaluates to `null`.

- `notNull(E)`, where `E` is an expression, represents the *flow model* just
  after execution of `E`, assuming that `E` completes normally and does not
  evaluate to `null`.

- `break(S)`, where `S` is a `do`, `for`, `switch`, or `while` statement,
  represents the join of the flow models reaching each `break` statement
  targetting `S`.

- `continue(S)`, where `S` is a `do`, `for`, `switch`, or `while` statement,
  represents the join of the flow models reaching each `continue` statement
  targetting `S`.

- `assignedIn(S)`, where `S` is a `do`, `for`, `switch`, or `while` statement,
  represents the set of variables assigned to in `S`.

Note that `true`, `false`, `null`, and `notNull` are defined for all expressions
regardless of their static types.

We also make use of the following auxiliary functions:

- `joinV(VM1, VM2)`, where `VM1` and `VM2` are variable models, represents the
  union of two variable models, defined as follows:
  - If `VM1 = VariableModel(d1, p1, s1, a1, u1, c1)` and
  - If `VM2 = VariableModel(d2, p2, s2, a2, u2, c2)` then
  - `VM3 = VariableModel(d3, p3, s3, a3, u3, c3)` where
   - `d3 = d1 = d2`
     - Note that all models must agree on the declared type of a variable
   - `p3 = p1 ^ p2`
     - `p1` and `p2` are totally ordered subsets of a global partial order.
  Their intersection is a subset of each, and as such is also totally ordered.
   - `s3 = s1 U s2`
     - The set of test sites is the union of the test sites on either path
   - `a3 = a1 && a2`
     - A variable is definitely assigned in the join of two models iff it is
       definitely assigned in both.
   - `u3 = u1 && u2`
     - A variable is definitely unassigned in the join of two models iff it is
       definitely unassigned in both.
   - `c3 = c1 || c2`
     - A variable is captured in the join of two models iff it is captured in
       either.

- `split(M)`, where `M = FlowModel(r, VM)` is a flow model which models program
  nodes inside of a control flow split, and is defined as `FlowModel(r2, VM)`
  where `r2` is `r` with `true` pushed as the top element of the stack.

- `drop(M)`, where `M = FlowModel(r, VM)` is defined as `FlowModel(r1, VM)`
  where where `r` is of the form `n0::r1`.  This is the flow model which drops
  the reachability information encoded in the top entry in the stack.

- `unsplit(M)`, where `M = FlowModel(r, VM)` is defined as `M1 = FlowModel(r1,
  VM)` where `r` is of the form `n0::n1::s` and `r1 = (n0&&n1)::s`. The model
  `M1` is a flow model which collapses the top two elements of the reachability
  model from `M` into a single boolean which conservatively summarizes the
  reachability information present in `M`.

- `merge(M1, M2)`, where `M1` and `M2` are flow models is the inverse of `split`
  and represents the result of joining two flow models at the merge of two
  control flow paths.  If `M1 = FlowModel(r1, VI1)` and `M2 = FlowModel(r2,
  VI2)` where `pop(r1) = pop(r2) = r0` then:
  - if `top(r1)` is true and `top(r2)` is false, then `M3` is `FlowModel(pop(r1), VI1)`.
  - if `top(r1)` is false and `top(r2)` is true, then `M3` is `FlowModel(pop(r2), VI2)`.
  - otherwise `M3` is `join(unsplit(M1), unsplit(M2))`

- `join(M1, M2)`, where `M1` and `M2` are flow models, represents the union of
  two flow models and is defined as follows:

  - We define `join(M1, M2)` to be `M3 = FlowModel(r3, VI3)` where:
    - `M1 = FlowModel(r1, VI1)`
    - `M2 = FlowModel(r2, VI2))` 
    - `pop(r1) = pop(r2) = r0` for some `r0` 
    - `r3` is `push(r0, top(r1) || top(r2))`
    - `VI3` is the map which maps each variable `v` in the domain of `VI1` and
      `VI2` to `joinV(VI1(v), VI2(v))`.  Note that any variable which is in
      domain of only one of the two is dropped, since it is no longer in scope.

  The `merge`, `join` and `joinV` combinators are commutative and associative by
  construction.

  For brevity, we will sometimes extend `join` and `merge` to more than two
  arguments in the obvious way.  For example, `join(M1, M2, M3)` represents
  `join(join(M1, M2), M3)`, and `join(S)`, where S is a set of models, denotes
  the result of folding all models in S together using `join`.

- `restrictV(VMB, VMF, b)`, where `VMB` and `VMF` are variable models and `b` is
  a boolean indicating wether the variable is written in the finally block,
  represents the composition of two variable models through a try/finally and is
  defined as follows:
  - If `VMB = VariableModel(d1, p1, s1, a1, u1, c1)` and
  - If `VMF = VariableModel(d2, p2, s2, a2, u2, c2)` then
  - `VM3 = VariableModel(d3, p3, s3, a3, u3, c3)` where
   - `d3 = d1 = d2`
     - Note that all models must agree on the declared type of a variable
   - if `b` is true then `p3 = p2`
   - if `b` is false then if the last entry in `p1` is a subtype of the last
     entry of `p2`, then `p3 = p1` else `p3 = p2`.  If the variable is not
     written to in the finally block, then it is valid to use any promotions
     from the try block in any subsequent code (since if any subsequent code is
     executed, the try block must have completed normally).  We only choose to
     do so if the last entry is more precise.  (TODO: is this the right thing to
     do here?).
   - `s3 = s2`
     - The set of types of interest is the set of types of interest in the
       finally block.
   - `a3 = a2 || a1`
     - A variable is definitely assigned after the finally block if it is
       definitely assigned by the try block or by the finally block (note that
       code after the finally block will only be executed if the try block
       completes normally).
   - `u3 = u2`
     - A variable is definitely unassigned if it is definitely unassigned in the
       model of the finally block (note that the finally block is analyzed using
       the join of the model from before the try block and after the try block,
       and so the absence of any assignments that may have occurred in the try
       block is already modelled here).
   - `c3 = c2`
     - A variable is captured if it is captured in the model of the finally
       block (note that the finally block is analyzed using the join of the
       model from before the try block and after the try block, and so any
       captures from the try block are already modelled here).

- `restrict(MB, MF, N)`, where `MB` and `MF` are flow models and `N` is a set of
  variables assigned in the finally clause, models the flow of information
  through a try/finally statement, and is defined as follows:

  - We define `restrict(MB, MF, N)` to be `M3 = FlowModel(r3, VI3)` where:
    - `MB = FlowModel(rb, VIB)`
    - `MF = FlowModel(rf, VIF))`
    - `pop(rb) = pop(rf) = r0` for some `r0`
    - `r3` is `push(r0, top(rb) && top(rf))`
    - `b` is true if `v` is in `N` and otherwise false
    - `VI3` is the map which maps each variable `v` in the domain of `VIB` and
      `VIF` to `restrictV(VIB(v), VIF(v), b)`.

- `unreachable(M)` represents the model corresponding to a program location
  which is unreachable, but is otherwise modeled by flow model `M = FlowModel(r,
  VI)`, and is defined as `FlowModel(push(pop(r), false), VI)`

- `demoteVariables(M, S)` represents the flow model derived from `M` in which
  all variables in `S` have been demoted to their declared types.  It is defined
  as `FlowModel(r, VI1)` where `M` is `FlowModel(r, VI0)` and `VI1` is the map
  such that:
    - `VI0` maps `v` to `VM0 = VariableModel(d0, p0, s0, a0, u0, c0)`
    - If `S` contains `v` then `VI1` maps `v` to `VariableModel(d0, [], s0, a0, u0, c0)`
    - Otherwise `VI1` maps `v` to `VM0`


### Promotion

Promotion policy is defined by the following operations on flow models.

We say that the **current type** of a variable `x` in variable model `VM` is `S` where:
  - `VM = VariableModel(declared, promoted, tested, assigned, unassigned, captured)`
  - `promoted = S::l` or (`promoted = []` and `declared = S`)

Policy:
  - We say that at type `T` is a type of interest for a variable `x` in a set of
    tested types `tested` if `tested` contains a type `S` such that `T` is `S`,
    or `T` is **NonNull(`S`)**.

  - We say that a variable `x` is promotable via type test with type `T` given
    variable model `VM` if
    - `VM = VariableModel(declared, promoted, tested, assigned, unassigned, captured)`
    - and `captured` is false
    - and `S` is the current type of `x` in `VM`
    - and not `S <: T`
    - and `T <: S` or (`S` is `X extends R` and `T <: R`) or (`S` is `X & R` and
      `T <: R`)

  - We say that a variable `x` is promotable via initialization given variable
    model `VM` if `x` is a local variable (not a formal parameter) and:
    - `VM = VariableModel(declared, promoted, tested, assigned, unassigned, captured)`
    - and `captured` is false
    - and `promoted` is empty
    - and `x` is declared with no explicit type and no initializer
    - and `assigned` is false and `unassigned` is true

  - We say that a variable `x` is promotable via assignment of an expression of
    type `T` given variable model `VM` if
    - `VM = VariableModel(declared, promoted, tested, assigned, unassigned, captured)`
    - and `captured` is false
    - and `S` is the current type of `x` in `VM`
    - and `T <: S` and not `S <: T`
    - and `T` is a type of interest for `x` in `tested`

  - We say that a variable `x` is demotable via assignment of an expression of
    type `T` given variable model `VM` if
    - `VM = VariableModel(declared, promoted, tested, assigned, unassigned, captured)`
    - and `captured` is false
    - and declared::promoted contains a type `S` such that `T` is `S` or `T` is
      **NonNull(`S`)**.

Definitions:

- `assign(x, E, M)` where `x` is a local variable, `E` is an expression of
  inferred type `T`, and `M = FlowModel(r, VI)` is the flow model for `E` is
  defined to be `FlowModel(r, VI[x -> VM])` where:
    - `VI(x) = VariableModel(declared, promoted, tested, assigned, unassigned, captured)`
    - if `captured` is true then:
      - `VM = VariableModel(declared, promoted, tested, true, false, captured)`.
    - otherwise if `x` is promotable via initialization given `VM` then
      - `VM = VariableModel(declared, [T], tested, true, false, captured)`.
    - otherwise if `x` is promotable via assignment of `E` given `VM`
      - `VM = VariableModel(declared, T::promoted, tested, true, false, captured)`.
    - otherwise if `x` is demotable via assignment of `E` given `VM`
      - `VM = VariableModel(declared, demoted, tested, true, false, captured)`.
      - where `previous` is the suffix of `promoted` starting with the first type
        `S` such that `T <: S`, and:
        - if `S`is nullable and if `T <: Q` where `Q` is **NonNull(`S`)** then
          `demoted` is `Q::previous`
        - otherwise `demoted` is `previous`

- `promote(E, T, M)` where `E` is an expression, `T` is a type which it may be
  promoted to, and `M = FlowModel(r, VI)` is the flow model in which to promote,
  is defined as follows:
  - If `E` is not a promotion target, then `M`
  - If `E` is a promotion target `x`, then
    - Let `VM = VariableModel(declared, promoted, tested, assigned, unassigned,
      captured)` be the variable model for `x` in `VI`
    - If `x` is not promotable via type test to `T` given `VM`, then return `M`
    - Else
      - Let `S` be the current type of `x` in `VM`
      - If `T <: S` then let `T1` = `T`
      - Else if `S` is `X extends R` then let `T1` = `X & T`
      - Else If `S` is `X & R` then let `T1` = `X & T`
      - Else `x` is not promotable (shouldn't happen since we checked above)
      - Let `VM2 = VariableModel(declared, T1::promoted, T1::tested, assigned,
      unassigned, captured)`
      - Return `FlowModel(r, VI[x -> VM2])`
- `promoteToNonNull(E, M)` where `E` is an expression and `M` is a flow model is
  defined to be `promote(E, T, M)` where `T0` is the type of `E`, and `T` is
  **NonNull(`T0`)**.
- `factor(T, S)` where `T` and `S` are types defines the "remainder" of `T` when
  `S` has been removed from consideration by an instance check.  It is defined
  as follows:
  - If `T <: S` then `Never`
  - Else if `T` is `R?` and `Null <: S` then `factor(R, S)`
  - Else if `T` is `R?` then `factor(R, S)?`
  - Else if `T` is `R*` and `Null <: S` then `factor(R, S)`
  - Else if `T` is `R*` then `factor(R, S)*`
  - Else if `T` is `FutureOr<R>` and `Future<R> <: S` then `factor(R, S)`
  - Else if `T` is `FutureOr<R>` and `R <: S` then `factor(Future<R>, S)`
  - Else `T`

Questions:
 - The interaction between assignment based **promotion** and downwards inference is
   probably managable.  I think doing downwards inference using the current
   type, and then promoting the variable afterwards is fine for all reasonable
   cases.
 - The interaction between assignment based **demotion** and downwards inference is
   a bit trickier.  In so far as it is manageable, I think it would need to be
   done as follows, given `x = E` where `x` has current type `S`.
     - Infer `E` in context `S`
     - if the inferred type of `E` is `T` and `S <: T` and the demotion policy
     applies, then instead of treating this as `x = (E as S)` (or an error),
     then instead treat `x` as promoted to `S` in the scope of the assigment.

   - if a variable is tested before it is initialized, we must choose whether to
    honor the type test or the assignment.  Above I've chosen to prefer type
    test based promotion.  Examples:
    ```
      test1() {
        var x;
        if (x is num) {
           x = 3; // not an initializing promotion, since it's already promoted
        }
      }
      test2() {
        var x;
        if (x is String) {
           x = 3; // not an initializing promotion, nor an assignment promotion
        }
      }
     ```

## Flow analysis

The flow model pass is initiated by visiting the top level function, method,
constructor, or field declaration to be analyzed.

### Expressions

Analysis of an expression `N` assumes that `before(N)` has been computed, and
uses it to derive `after(N)`, `null(N)`, `notNull(N)`, `true(N)`, and
`false(N)`.

If `N` is an expression, and the following rules specify the values to be
assigned to `true(N)` and `false(N)`, but do not specify values for `null(N)`,
`notNull(N)`, or `after(N)`, then they are by default assigned as follows:
  - `null(N) = unreachable(after(N))`.
  - `notNull(N) = join(true(N), false(N))`.
  - `after(N) = notNull(N)`.

If `N` is an expression, and the following rules specify the values to be
assigned to `null(N)` and `notNull(N)`, but do not specify values for `true(N)`,
`false(N)`, or `after(N)`, then they are by default assigned as follows:
  - `true(N) = notNull(N)`.
  - `false(N) = notNull(N)`.
  - `after(N) = join(null(N), notNull(N))`.

If `N` is an expression, and the following rules specify the value to be
assigned to `after(N)`, but do not specify values for `true(N)`, `false(N)`,
`null(N)`, or `notNull(N)`, then they are all assigned the same value as
`after(N)`.


- **Variable or getter**: If `N` is an expression of the form `x` 
  where the type of `x` is `T` then:
  - If `T <: Never` then:
    - Let `null(N) = unreachable(before(N))`.
    - Let `notNull(N) = unreachable(before(N))`.
  - Otherwise if `T <: Null` then:
    - Let `null(N) = before(N)`.
    - Let `notNull(N) = unreachable(before(N))`.
  - Otherwise if `T` is non-nullable then:
    - Let `null(N) = before(N)`.
    - Let `notNull(N) = unreachable(before(N))`.
  - Otherwise:
    - Let `null(N) = promote(x, Null, before(N))`
    - Let `notNull(N) = promoteToNonNull(x, before(N))`

- **True literal**: If `N` is the literal `true`, then:
  - Let `true(N) = before(N)`.
  - Let `false(N) = unreachable(before(N))`.

- **False literal**: If `N` is the literal `false`, then:
  - Let `true(N) = unreachable(before(N))`.
  - Let `false(N) = before(N)`.

- **null literal**: If `N` is the literal `null`, then:
  - Let `null(N) = before(N)`.
  - Let `notNull(N) = unreachable(before(N))`.

- **other literal**: If `N` is some other literal than the above, then:
  - Let `null(N) = unreachable(before(N))`.
  - Let `notNull(N) = before(N)`.

- **throw**: If `N` is a throw expression of the form `throw E1`, then:
  - Let `before(E1) = before(N)`.
  - Let `after(N) = unreachable(after(E1))`

- **Local-variable assignment**: If `N` is an expression of the form `x = E1`
  where `x` is a local variable, then:
  - Let `before(E1) = before(N)`.
  - Let `after(N) = assign(x, E1, after(E1))`.
  - Let `true(N) = assign(x, E1, true(E1))`.
  - Let `false(N) = assign(x, E1, false(E1))`.
  - Let `null(N) = assign(x, E1, null(E1))`.
  - Let `notNull(N) = assign(x, E1, notNull(E1))`.

TODO(leafp): Per
discussion
[here](https://github.com/dart-lang/language/pull/763/files#r364003138), this is
wrong.  This needs reconsideration.
- **operator==** If `N` is an expression of the form `E1 == E2` then:
  - Let `before(E1) = before(N)`
  - Let `before(E2) = after(E1)`
  - Let `true(N) = join(join(null(E1), null(E2)),
                        join(notNull(E1), notNull(E2)))`
  - Let `false(N) = join(join(null(E1), notNull(E2)),
                         join(notNull(E1), null(E2)),
                         join(notNull(E1), notNull(E2)))`

- **instance check** If `N` is an expression of the form `E1 is S` where the
  static type of `E1` is `T` then:
  - Let `before(E1) = before(N)`
  - Let `true(N) = promote(E1, S, after(E1))`
  - Let `false(N) = promote(E1, factor(T, S), after(E1))`

- **type cast** If `N` is an expression of the form `E1 as S` where the
  static type of `E1` is `T` then:
  - Let `before(E1) = before(N)`
  - Let `after(N) = promote(E1, S, after(E1))`

- **Local variable conditional assignment**: If `N` is an expression of the form
  `x ??= E1` where `x` is a local variable, then:
  - Let `before(E1) = split(promote(x, Null, before(N)))`.
  - Let `M1 = assign(x, E1, after(E1))`
  - Let `M2 = split(promoteToNonNull(x, before(N)))`
  - Let `after(N) = merge(M1, M2)`

TODO: This isn't really right, `E1` isn't really an expression here.

- **Non local-variable conditional assignment**: If `N` is an expression of the form
  `E1 ??= E2` where `E1` is not a local variable, then:
  - Let `before(E1) = before(N)`
  - Let `before(E2) = split(null(E1))`.
  - Let `after(N) = merge(after(E2), split(notNull(E1)))`

- **Conditional expression**: If `N` is a conditional expression of the form `E1
  ? E2 : E3`, then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = split(true(E1))`.
  - Let `before(E3) = split(false(E1))`.
  - Let `after(N) = merge(after(E2), after(E3))`.
  - Let `true(N) = merge(true(E2), true(E3))`.
  - Let `false(N) = merge(false(E2), false(E3))`.
  - Let `null(N) = merge(null(E2), null(E3))`.
  - Let `notNull(N) = merge(notNull(E2), notNull(E3))`.

- **If-null**: If `N` is an if-null expression of the form `E1 ?? E2`, then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = split(null(E1))`.
  - Let `null(N) = unsplit(null(E2))`.
  - Let `notNull(N) = merge(split(notNull(E1)), notNull(E2))`.

- **Shortcut and**: If `N` is a shortcut "and" expression of the form `E1 && E2`,
  then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = split(true(E1))`.
  - Let `true(N) = unsplit(true(E2))`.
  - Let `false(N) = merge(split(false(E1)), false(E2))`.

- **Shortcut or**: If `N` is a shortcut "or" expression of the form `E1 || E2`,
  then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = split(false(E1))`.
  - Let `false(N) = unsplit(false(E2))`.
  - Let `true(N) = merge(split(true(E1)), true(E2))`.

- **Binary operator**: All binary operators other than `==`, `&&`, `||`, and
  `??`are handled as calls to the appropriate `operator` method.

- **Null check operator**: If `N` is an expression of the form `E!`, then:
  - Let `before(E) = before(N)`
  - Let `null(N) = unreachable(null(E))`
  - Let `nonNull(N) = nonNull(E)`

- **Method invocation**: If `N` is an expression of the form `E1.m1(E2)`, then:
  - Let `before(E1) = before(N)`
  - Let `before(E2) = after(E2)`
  - Let `T` be the static return type of the invocation
  - If `T <: Never` then:
    - Let `null(N) = unreachable(before(N))`.
    - Let `notNull(N) = unreachable(before(N))`.
  - Otherwise if `T <: Null` then:
    - Let `null(N) = before(N)`.
    - Let `notNull(N) = unreachable(before(N))`.
  - Otherwise if `T` is non-nullable then:
    - Let `null(N) = before(N)`.
    - Let `notNull(N) = unreachable(before(N))`.
  - Otherwise:
    - Let `null(N) = promote(x, Null, before(N))`
    - Let `notNull(N) = promoteToNonNull(x, before(N))`


TODO: Add missing expressions, handle cascades and left-hand sides accurately

### Statements

- **Expression statement**: If `N` is an expression statement of the form `E` then:
  - Let `before(E) = before(N)`.
  - Let `after(N) = after(E)`.

- **Break statement**: If `N` is a statement of the form `break [L];`, then:

  - Let `S` be the statement targeted by the `break`.  If `L` is not present,
    this is the innermost `do`, `for`, `switch`, or `while` statement.
    Otherwise it is the `do`, `for`, `switch`, or `while` statement with a label
    matching `L`.

  - Update `break(S) = join(break(S), before(N))`.

  - Let `after(N) = unreachable(before(N))`.

- **Continue statement**: If `N` is a statement of the form `continue [L];` then:

  - Let `S` be the statement targeted by the `continue`.  If `L` is not present,
    this is the innermost `do`, `for`, or `while` statement.  Otherwise it is
    the `do`, `for`, or `while` statement with a label matching `L`, or the
    `switch` statement containing a switch case with a label matching `L`.

  - Update `continue(S) = join(continue(S), before(N))`.

  - Let `after(N) = unreachable(before(N))`.

- **Return statement**: If `N` is a statement of the form `return E1;` then:
  - Let `before(E) = before(N)`.
  - Let `after(N) = unreachable(after(E))`;

- **Conditional statement**: If `N` is a conditional statement of the form `if
  (E) S1 else S2` then:
  - Let `before(E) = before(N)`.
  - Let `before(S1) = split(true(E))`.
  - Let `before(S2) = split(false(E))`.
  - Let `after(N) = merge(after(S1), after(S2))`.

- **while statement**: If `N` is a while statement of the form `while
  (E) S` then:
  - Let `before(E) = demoteVariables(before(N), assignedIn(N))`.
  - Let `before(S) = split(true(E))`.
  - Let `after(N) = join(false(E), unsplit(break(S))`

- **do while statement**: If `N` is a do while statement of the form `do S while
  (E)` then:
  - Let `before(S) = demoteVariables(before(N), assignedIn(N))`.
  - Let `before(E) = join(after(S), continue(N))`
  - Let `after(N) = join(false(E), break(S))`

- **switch statement**: If `N` is a switch statement of the form `switch (E)
  {alternatives}` then:
  - Let `before(E) = before(N)`.
  - For each `C` in `alternatives` with statement body `S`:
    - If `C` is labelled let `before(S) = demoteVariables(after(E),
      assignedIn(N)` otherwise let `before(S) = after(E)`.
  - If the cases are exhaustive, then let `after(N) = break(N)` otherwise let
    `after(N) = join(after(E), break(N))`.

- **try catch**: If `N` is a try/catch statement of the form `try B
alternatives` then:
  - Let `before(B) = before(N)`
  - Foreach catch block `on Ti Si` in `alternatives`:
    - Let `before(Si) = demoteVariables(before(N), assignedIn(B))`
  - Let `after(N) = join(after(B), after(C0), ..., after(Ck))`

- **try finally**: If `N` is a try/finally statement of the form `try B1 finally B2` then:
  - Let `before(B1) = split(before(N))`
  - Let `before(B2) = split(join(drop(after(B1)), demoteVariables(before(N), assignedIn(B1))))`
  - Let `after(N) = restrict(after(B1), after(B2), assignedIn(B2))`


## Interesting examples

```dart
void test() {
  int? a = null;
  if (false && a != null) {
    a.and(3);
  }
}
```

```dart
Object x;
if (false && x is int) {
  x.isEven
}
```
