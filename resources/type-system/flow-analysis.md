# Flow Analysis for Non-nullability

paulberry@google.com, leafp@google.com

This is roughly based on the proposal discussed in
https://docs.google.com/document/d/11Xs0b4bzH6DwDlcJMUcbx4BpvEKGz8MVuJWEfo_mirE/edit.

**Status**: Draft.

## CHANGELOG

2020.06.29
  - Fix handling of variables that are write captured in loops, switch
    statements, and try-blocks (such variables should be conservatively assumed
    to be captured).

2020.06.02
  - Specify the interaction between downwards inference and promotion/demotion.

2020.01.16
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
  - We use the notation `[...l, a]` where `l` is a list to denote a list
    beginning with all the elements of `l` and followed by `a`.
  - A list of types `p` is called a _promotion chain_ iff, for all `i < j`,
    `p[j] <: p[i]`. _Note that since the subtyping relation is transitive, in
    order to establish that `p` is a promotion chain, it is sufficient to check
    the `p[j] <: p[i]` relation for each adjacent pair of types._
  - A promotion chain `p` is said to be _valid for declared type `T`_ iff every
    type in `p` is a subtype of `T`. _Note that since the subtyping relation is
    transitive, in order to establish that `p` is valid for declared type `T`,
    it is sufficient to check that the first type in `p` is a subtype of `T`._

- Stacks
  - We use the notation `push(s, x)` to mean pushing `x` onto the top of the
    stack `s`.
  - We use the notation `pop(s)` to mean the stack that results from removing
    the top element of `s`.  If `s` is empty, the result is undefined.
  - We use the notation `top(s)` to mean the top element of the stack `s`.  If
    `s` is empty, the result is undefined.
  - Informally, we also use `[...t, a]` to describe a stack `s` such that
    `top(s)` is `a` and `pop(s)` is `t`.

### Models

A *variable model*, denoted `VariableModel(declaredType, promotionChain,
tested, assigned, unassigned, writeCaptured)`, represents what is statically
known to the flow analysis about the state of a variable at a given point in the
source code.

- `declaredType` is the type assigned to the variable at its declaration site
  (either explicitly or by type inference).

- `promotionChain` is the variable's promotion chain. This is a list of types
  that the variable has been promoted to, with the final type in the list being
  the current promoted type of the variable. It must always be a valid promotion
  chain for declared type `declaredType`.

- `tested` is a set of types which are considered "of interest" for the purposes
  of promotion, generally because the variable in question has been tested
  against the type on some path in some way.

- `assigned` is a boolean value indicating whether the variable has definitely
  been assigned at the given point in the source code.  When `assigned` is
  true, we say that the variable is _definitely assigned_ at that point.

- `unassigned` is a boolean value indicating whether the variable has
  definitely not been assigned at the given point in the source code.  When
  `unassigned` is true, we say that the variable is _definitely unassigned_ at
  that point.  (Note that a variable cannot be both definitely assigned and
  definitely unassigned at any location).

- `writeCaptured` is a boolean value indicating whether a closure or an unevaluated
  late variable initializer might exist at the given point in the source code,
  which could potentially write to the variable.  Note that for purposes of
  write captures performed by a late variable initializer, we only consider
  variable writes performed within the initializer expression itself; a late
  variable initializer is not per se considered to write to the late variable
  itself.

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

- `assignedIn(S)`, where `S` is a `do`, `for`, `switch`, or `while` statement,
  or a `for` element in a collection, represents the set of variables assigned
  to in the recurrent part of `S`, not counting initializations of variables at
  their declaration sites.  The "recurrent" part of `S` is defined as:
  - If `S` is a `do` or `while` statement, the entire statement `S`.
  - If `S` is a `for` statement or a `for` element in a collection, whose
    `forLoopParts` take the form of a traditional for loop, all of `S` except
    the `forInitializerStatement`.
  - If `S` is a `for` statement or a `for` element in a collection, whose
    `forLoopParts` take the form of a for-in loop, the body of `S`.  A loop of
    the form `for (var x in ...) ...` is not considered to assign to `x`
    (because `var x in ...` is considered an initialization of `x` at its
    declaration site), but a loop of the form `for (x in ...) ...` (where `x` is
    declared elsewhere in the function) *is* considered to assign to `x`.
  - If `S` is a `switch` statement, all of `S` except the switch `expression`.

- `capturedIn(S)`, where `S` is a `do`, `for`, `switch`, or `while` statement,
  represents the set of variables assigned to in a local function or function
  expression in the recurrent part of `S`, where the "recurrent" part of `s` is
  defined as in `assignedIn`, above.

Note that `true` and `false` are defined for all expressions regardless of their
static types.

We also make use of the following auxiliary functions:

- `joinV(VM1, VM2)`, where `VM1` and `VM2` are variable models, represents the
  union of two variable models, defined as follows:
  - If `VM1 = VariableModel(d1, p1, s1, a1, u1, c1)` and
  - If `VM2 = VariableModel(d2, p2, s2, a2, u2, c2)` then
  - `VM3 = VariableModel(d3, p3, s3, a3, u3, c3)` where
   - `d3 = d1 = d2`
     - Note that all models must agree on the declared type of a variable
   - `p3` is a list formed by taking all the types that are in both `p1` and
     `p2`, and ordering them such that each type in the list is a subtype of all
     previous types.
     - _Note: it is not specified how to order elements of this list that are
       mutual subtypes of each other. This will soon be addressed by changing
       the behavior of flow analysis so that each type in the list is a proper
       subtype of the previous. (See
       https://github.com/dart-lang/language/issues/4368.)
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

- `unsplit(M)`, where `M = FlowModel(r, VM)` is defined as `M1 = FlowModel(r1,
  VM)` where `r` is of the form `[...s, n1, n0]` and `r1 = [...s, n0&&n1]`. The
  model `M1` is a flow model which collapses the top two elements of the
  reachability model from `M` into a single boolean which conservatively
  summarizes the reachability information present in `M`.

- `unsplitTo(r0, M)` is defined recursively as follows:
  - Let `M = FlowModel(r, VI)`.
  - If `r0` and `r` have the same length, then `unsplitTo(r, M) = M`.
  - Otherwise, `unsplitTo(r, M) = unsplitTo(r, unsplit(M))`.
  - _In other words, the effect of `unsplitTo(r, M)` is to perform `unsplit()`
    on `M` exactly the number of times necessary to cause the length of its
    `reachability` stack to match that of `r`._

- `join(M1, M2)`, where `M1` and `M2` are flow models, represents the union of
  two flow models and is defined as follows:

  - We define `join(M1, M2)` to be `M3 = FlowModel(r3, VI3)` where:
    - `M1 = FlowModel(r1, VI1)`
    - `M2 = FlowModel(r2, VI2)`
    - `pop(r1) = pop(r2) = r0` for some `r0`
    - `r3` is `push(r0, top(r1) || top(r2))`
    - `VI3` is the map which maps each variable `v` in the domain of `VI1` and
      `VI2` to `joinV(VI1(v), VI2(v))`.  Note that any variable which is in
      domain of only one of the two is dropped, since it is no longer in scope.

  _We expect the `join` and `joinV` combinators to be commutative and
  associative, but we don't rely on this for the soundness of the algorithm._

  For brevity, we will sometimes extend `join` to more than two arguments in the
  obvious way.  For example, `join(M1, M2, M3)` represents `join(join(M1, M2),
  M3)`, and `join(S)`, where S is a set of models, denotes the result of folding
  all models in S together using `join`.

  Simiarly, if L is a non-empty list of flow models, `join(...L)` represents the
  result of folding the list using `join`.

- `rebasePromotedTypes(basePromotions, newPromotions)`, where `basePromotions`
  and `newPromotions` are promotion chains, computes a promotion chain
  containing promotions from both `basePromotions` and `newPromotions`,
  discarding promotions if necessary to avoid violating the promotion chain
  requirement. It is defined as follows:
  - If `basePromotions` is empty, then `rebasePromotedTypes(basePromotions,
    newPromotions) = newPromotions`.
  - Otherwise:
    - Let `T2` be the last type in `basePromotions`.
    - Let `newPromotions'` be a promotion chain obtained by deleting any
      elements `T` from `newPromotions` that do not satisfy `T <: T2`.
    - Let `rebasePromotedTypes(basePromotions, newPromotions) =
      [...basePromotions, ...newPromotions']`.

  _The reason `rebasePromotedTypes` is asymmetric is that it is used in
  asymmetric situations. For example, when analyzing a `try`/`finally`
  statement, `basePromotions` contains the promotions from the end of the `try`
  block and `newPromotions` contains the promotions from the end of the
  `finally` block. Hence, to compute the promotion chain after the
  `try`/`finally` block, the promotions from `basePromotions` should be applied
  first, followed by any promotions from `newPromotions` that do not violate the
  promotion chain requirement._

- `attachFinally(afterTry, beforeFinally, afterFinally)`, where `afterTry`,
  `beforeFinally`, and `afterFinally` are flow models, represents the state of
  the program after a `try/finally` statement, where `afterTry` is the state
  after the `try` block, `beforeFinally` is the state before the `finally`
  block, and `afterFinally` is the state after the `finally` block. It is
  defined as `FlowModel(r4, VI4)`, where:
  - Let `afterTry = FlowModel(r1, VI1)`, `beforeFinally = FlowModel(r2, VI2)`,
    and `afterFinally = FlowModel(r3, VI3)`.
  - Let `r4` be defined as follows:
    - If `top(r3)` is `true`, then let `r4 = r1`. _If the `finally` block does
      not unconditionally exit, then the reachability behavior of the
      `try/finally` statement as a whole is the same as that of the `try`
      block._
    - Otherwise, let `r4 = unreachable(r1)`. _If the `finally` block
      unconditionally exits, then the `try/finally` statement as a whole
      unconditionally exits._
  - Let `VI4` be the map which maps each variable `v` in the domain of either
    `VI1` or `VI3` as follows:
    - If `v` is in the domain of `VI1` but not `VI3`, then `VI4(v) = VI1(v)`.
    - If `v` is in the domain of `VI3` but not `VI1`, then `VI4(v) = VI3(v)`.
    - If `v` is in the domain of both `VI1` and `VI3`, then `VI4(v) =
      attachFinallyV(VI1(v), VI2(v), VI3(v))`. _Note that if `v` is in the
      domain of both `VI1` and `VI3`, it must have been declared before the
      `try/finally` statement, therefore it must also be in the domain of
      `VI2`._

- `attachFinallyV(afterTry, beforeFinally, afterFinally)`, where `afterTry`,
  `beforeFinally`, and `afterFinally` are variable models, represents the state
  of a variable model after a `try/finally` statement, where `afterTry` is the
  state after the `try` block, `beforeFinally` is the state before the `finally`
  block, and `afterFinally` is the state after the `finally` block. It is
  defined as `VariableModel(d4, p4, s4, a4, u4, c4)`, where:
  - Let `afterTry = VariableModel(d1, p1, s1, a1, u1, c1)`.
  - Let `beforeFinally = VariableModel(d2, p2, s2, a2, u2, c2)`.
  - Let `afterFinally = VariableModel(d3, p3, s3, a3, u3, c3)`.
  - Let `d4 = d3`. _A variable's declared type cannot change. Therefore, `d1 =
    d2 = d3`, so it is safe to simply pick `d3`._
  - Let `p4` be determined as follows:
    - If the variable's value might have been changed by the `finally` block
      (_TODO(paulberry): specify precisely how this is determined_), then `p4 =
      p3`. _Promotions from the `try` block aren't necessarily valid, so only
      promotions from the `finally` block are kept._
    - Otherwise, `p4 = rebasePromotedTypes(p1, p3)`.
  - Let `t4 = t3`. _The `finally` block inherited all tests from the `try`
    block, so `t3` contains all relevant tested types._
  - Let `a4 = a1 || a3`. _The variable is definitely assigned if it was
    definitely assigned in either the `try` or the `finally` block._
  - Let `u4 = u3`. _The `finally` block inherited the "unassigned" state from
    the `try` block, so `u3` already accounts for assignments in both the `try`
    and `finally` blocks._
  - Let `c4 = c3`. _The `finally` block inherited the "writeCaptured" state from
    the `try` block, so `c3` is already accounts for write captures in both the
    `try` and `finally` blocks._

- `unreachable(M)` represents the model corresponding to a program location
  which is unreachable, but is otherwise modeled by flow model `M = FlowModel(r,
  VI)`, and is defined as `FlowModel(push(pop(r), false), VI)`

- `conservativeJoin(M, written, captured)` represents a conservative
  approximation of the flow model that could result from joining `M` with a
  model in which variables in `written` might have been written to and variables
  in `captured` might have been write-captured.  It is defined as
  `FlowModel(r, VI1)` where `M` is `FlowModel(r, VI0)` and `VI1` is the map
  such that:
    - `VI0` maps `v` to `VM0 = VariableModel(d0, p0, s0, a0, u0, c0)`
    - If `captured` contains `v` then `VI1` maps `v` to
      `VariableModel(d0, [], s0, a0, false, true)`
    - Otherwise if `written` contains `v` then `VI1` maps `v` to
      `VariableModel(d0, [], s0, a0, false, c0)`
    - Otherwise `VI1` maps `v` to `VM0`

- `inheritTestedV(VM1, VM2)`, where `VM1` and `VM2` are variable models,
  represents a modification of `VM1` to include any additional types of interest
  from `VM2`.  It is defined as follows:

  - We define `inheritTestedV(VM1, VM2)` to be `VM3 = VariableModel(d1, p1, s3,
    a1, u1, c1)` where:
    - `VM1 = VariableModel(d1, p1, s1, a1, u1, c1)`
    - `VM2 = VariableModel(d2, p2, s2, a2, u2, c2)`
    - `s3 = s1 U s2`
      - The set of test sites is the union of the test sites on either path

- `inheritTested(M1, M2)`, where `M1` and `M2` are flow models, represents a
  modification of `M1` to include any additional types of interest from `M2`.
  It is defined as follows:

  - We define `inheritTested(M1, M2)` to be `M3 = FlowModel(r1, VI3)` where:
    - `M1 = FlowModel(r1, VI1)`
    - `M2 = FlowModel(r2, VI2)`
    - `VI3` is the map which maps each variable `v` in the domain of both `VI1`
      and `VI2` to `inheritTestedV(VI1(v), VI2(v))`, and maps each variable in
      the domain of `VI1` but not `VI2` to `VI1(v)`.


### Promotion

Promotion policy is defined by the following operations on flow models.

We say that the **current type** of a variable `x` in variable model `VM` is `S` where:
  - `VM = VariableModel(declared, promotionChain, tested, assigned, unassigned, captured)`
  - `promotionChain = [...l, S]` or (`promotionChain = []` and `declared = S`)

Policy:
  - We say that at type `T` is a type of interest for a variable `x` in a set of
    tested types `tested` if `tested` contains a type `S` such that `T` is `S`,
    or `T` is **NonNull(`S`)**.

  - We say that a variable `x` is promotable via type test with type `T` given
    variable model `VM` if
    - `VM = VariableModel(declared, promotionChain, tested, assigned, unassigned, captured)`
    - and `captured` is false
    - and `S` is the current type of `x` in `VM`
    - and not `S <: T`
    - and `T <: S` or (`S` is `X extends R` and `T <: R`) or (`S` is `X & R` and
      `T <: R`)

Definitions:

- `demote(promotionChain, written)`, is a promotion chain obtained by deleting
  any elements from `promotionChain` that do not satisfy `written <: T`. _In
  effect, this removes any type promotions that are no longer valid after the
  assignment of a value of type `written`._
  - _Note that if `promotionChain` is valid for declared type `T`, it follows
    that `demote(promotionChain, written)` is also valid for declared type `T`._

- `toi_promote(declared, promotionChain, tested, written)`, where `declared` and
  `written` are types satisfying `written <: declared`, `promotionChain` is
  valid for declared type `declared`, and all types `T` in `promotionChain`
  satisfy `written <: T`, is the promotion chain `newPromotionChain`, defined as
  follows. _("toi" stands for "type of interest".)_
  - Let `provisionalType` be the last type in `promotionChain`, or `declared` if
    `promotionChain` is empty. _(This is the type of the variable after
    demotions, but before type of interest promotion.)_
    - _Since the last type in a promotion chain is a subtype of all the others,
      it follows that all types `T` in `promotionChain` satisfy `provisionalType
      <: T`._
  - If `written` and `provisionalType` are the same type, then
    `newPromotionChain` is `promotionChain`. _(No type of interest promotion is
    necessary in this case.)_
  - Otherwise _(when `written` is not `provisionalType`)_, let `p1` be a set
    containing the following types:
    - **NonNull**(`declared`), if it is not the same as `declared`.
    - For each type `T` in the `tested` list:
      - `T`
      - **NonNull**(`T`)

    _The types in `p1` are known as the types of interest._
  - Let `p2` be the set `p1 \ { provisionalType }` _(where `\` denotes set
    difference)_.
  - If the `written` type is in `p2` then `newPromotionChain` is
    `[...promotionChain, written]`. _Writing a value whose static type is a
    type of interest promotes to that type._
    - _By precondition, `written <: declared` and `written <: T` for all types
      in `promotionChain`. Therefore, `newPromotionChain` satisfies the
      definition of a promotion chain, and is valid for declared type
      `declared`._
  - Otherwise _(when `written` is not in `p2`)_:
    - Let `p3` be the set of all types `T` in `p2` such that `written <: T <:
      provisionalType`.
    - If `p3` contains exactly one type `T` that is a subtype of all the others,
      then `promoted` is `[...promotionChain, T]`. _Writing a value whose static
      type is a subtype of a type of interest promotes to that type of interest,
      provided there is a single "best" type of interest available to promote
      to._
      - _Since `T <: provisionalType <: declared`, and all types `U` in
        `promotionChain` satisfy `provisionalType <: U`, it follows that all
        types `U` in `promotionChain` satisfy `T <: U`. Therefore
        `newPromotionChain` satisfies the definition of a promotion chain, and
        is valid for declared type `declared`._
    - Otherwise, `newPromotionChain` is `promotionChain`. _If there is no single
      "best" type of interest to promote to, then no type of interest promotion
      is done._

- `assign(x, E, M)` where `x` is a local variable, `E` is an expression of
  inferred type `T` (which must be a subtype of `x`'s declared type), and `M =
  FlowModel(r, VI)` is the flow model for `E` is defined to be `FlowModel(r,
  VI[x -> VM])` where:
  - `VI(x) = VariableModel(declared, promoted, tested, assigned, unassigned,
    captured)`
  - If `captured` is true then:
    - `VM = VariableModel(declared, promotionChain, tested, true, false, captured)`.
  - Otherwise:
    - Let `written = T`.
    - Let `promotionChain' = demote(promotionChain, written)`.
    - Let `promotionChain'' = toi_promote(declared, promotionChain', tested,
      written)`.
      - _The preconditions for `toi_promote` are satisfied because:_
        - _`demote` deletes any elements from `promotionChain` that do not
          satisfy `written <: T`, therefore every element of `promotionChain'`
          satisfies `written <: T`._
        - _`written = T` and `T` is a subtype of `x`'s declared type, therefore
          `written <: declared`._
    - Then `VM = VariableModel(declared, promotionChain'', tested, true, false,
      captured)`.

- `stripParens(E1)`, where `E1` is an expression, is the result of stripping
  outer parentheses from the expression `E1`.  It is defined to be the
  expression `E3`, where:
  - If `E1` is a parenthesized expression of the form `(E2)`, then `E3` =
    `stripParens(E2)`.
  - Otherwise, `E3` = `E1`.

- `equivalentToNull(T)`, where `T` is a type, indicates whether `T` is
  equivalent to the `Null` type.  It is defined to be true if `T <: Null` and
  `Null <: T`; otherwise false.

- `promote(E, T, M)` where `E` is an expression, `T` is a type which it may be
  promoted to, and `M = FlowModel(r, VI)` is the flow model in which to promote,
  is defined to be `M3`, where:
  - If `stripParens(E)` is not a promotion target, then `M3` = `M`
  - If `stripParens(E)` is a promotion target `x`, then
    - Let `VM = VariableModel(declared, promoted, tested, assigned, unassigned,
      captured)` be the variable model for `x` in `VI`
    - If `x` is not promotable via type test to `T` given `VM`, then `M3` = `M`
    - Else
      - Let `S` be the current type of `x` in `VM`
      - If `T <: S` then let `T1` = `T`
      - Else if `S` is `X extends R` then let `T1` = `X & T`
      - Else If `S` is `X & R` then let `T1` = `X & T`
      - Else `x` is not promotable (shouldn't happen since we checked above)
      - Let `VM2 = VariableModel(declared, [...promoted, T1], [...tested, T],
        assigned, unassigned, captured)`
      - Let `M2 = FlowModel(r, VI[x -> VM2])`
      - If `T1 <: Never` then `M3` = `unreachable(M2)`, otherwise `M3` = `M2`
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

#### Interactions between downwards inference and promotion

Given an assignment (or composite assignment) `x = E` where `x` has current type
`S` (possibly the result of promotion), inference and promotion interact as
follows.
  - Inference for `E` is done as usual, using `S` as the downwards typing
    context.  All reference to `x` within `E` are treated as having type `S` as
    usual.
  - Let `T` be the resulting inferred type of `E`.
  - The assignment is treated as an assignment of an expression of type `T` to a
    variable of type `S`, with the usual promotion, demotion and errors applied.

## Flow analysis

The flow model pass is initiated by visiting the top level function, method,
constructor, or field declaration to be analyzed.

### Expressions

Analysis of an expression `N` assumes that `before(N)` has been computed, and
uses it to derive `after(N)`, `true(N)`, and `false(N)`.

If `N` is an expression, and the following rules specify the values to be
assigned to `true(N)` and `false(N)`, but do not specify the value for
`after(N)`, then it is by default assigned as follows:
  - `after(N) = join(true(N), false(N))`.

If `N` is an expression, and the following rules specify the value to be
assigned to `after(N)`, but do not specify values for `true(N)` and `false(N)`,
then they are all assigned the same value as `after(N)`.


- **Variable or getter**: If `N` is an expression of the form `x`
  where the type of `x` is `T` then:
  - If `T <: Never` then:
    - Let `after(N) = unreachable(before(N))`.
  - Otherwise:
    - Let `after(N) = before(N)`.

- **True literal**: If `N` is the literal `true`, then:
  - Let `true(N) = before(N)`.
  - Let `false(N) = unreachable(before(N))`.

- **False literal**: If `N` is the literal `false`, then:
  - Let `true(N) = unreachable(before(N))`.
  - Let `false(N) = before(N)`.

- TODO(paulberry): list, map, and set literals.

- **other literal**: If `N` is some other literal than the above, then:
  - Let `after(N) = before(N)`.

- **throw**: If `N` is a throw expression of the form `throw E1`, then:
  - Let `before(E1) = before(N)`.
  - Let `after(N) = unreachable(after(E1))`

- **Local-variable assignment**: If `N` is an expression of the form `x = E1`
  where `x` is a local variable, then:
  - Let `before(E1) = before(N)`.
  - Let `E1'` be the result of applying type coercion to `E1`, to coerce it to
    the declared type of `x`.
  - Let `after(N) = assign(x, E1', after(E1))`.
    - _Since type coercion to type `T` produces an expression whose static type
      is a subtype of `T`, the precondition of `assign` is satisfied, namely
      that the static type of `E1'` must be a subtype of `x`'s declared type._

- **operator==** If `N` is an expression of the form `E1 == E2`, where the
  static type of `E1` is `T1` and the static type of `E2` is `T2`, then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = after(E1)`.
  - If `equivalentToNull(T1)` and `equivalentToNull(T2)`, then:
    - Let `true(N) = after(E2)`.
    - Let `false(N) = unreachable(after(E2))`.
  - Otherwise, if `equivalentToNull(T1)` and `T2` is non-nullable, or
    `equivalentToNull(T2)` and `T1` is non-nullable, then:
    - Let `after(N) = after(E2)`.
    - *Note that now that Dart no longer supports unsound null safety mode, it
      would be sound (and probably preferable) to let `true(N) =
      unreachable(after(E2))` and `false(N) = after(E2)`. This improvement is
      being contemplated as part of
      https://github.com/dart-lang/language/issues/3100.*
  - Otherwise, if `stripParens(E1)` is a `null` literal, then:
    - Let `true(N) = after(E2)`.
    - Let `false(N) = promoteToNonNull(E2, after(E2))`.
  - Otherwise, if `stripParens(E2)` is a `null` literal, then:
    - Let `true(N) = after(E1)`.
    - Let `false(N) = promoteToNonNull(E1, after(E2))`.
  - Otherwise:
    - Let `after(N) = after(E2)`.

  Note that it is tempting to generalize the two `null` literal cases to apply
  to any expression whose type is `Null`, but this would be unsound in cases
  where `E2` assigns to `x`.  (Consider, for example, `(int? x) => x == (x =
  null) ? true : x.isEven`, which tries to call `null.isEven` in the event of a
  non-null input).

- **operator!=** If `N` is an expression of the form `E1 != E2`, it is treated
  as equivalent to the expression `!(E1 == E2)`.

- **instance check** If `N` is an expression of the form `E1 is S` where the
  static type of `E1` is `T` then:
  - Let `before(E1) = before(N)`
  - If `T` is a bottom type, then:
    - Let `true(N) = unreachable(after(E1))`.
    - Let `false(N) = after(E1)`.
  - Otherwise:
    - Let `true(N) = promote(E1, S, after(E1))`
    - Let `false(N) = promote(E1, factor(T, S), after(E1))`

- **negated instance check** If `N` is an expression of the form `E1 is! S`
  where the static type of `E1` is `T` then:
  - Let `before(E1) = before(N)`
  - If `T` is a bottom type, then:
    - Let `true(N) = after(E1)`.
    - Let `false(N) = unreachable(after(E1))`.
  - Otherwise:
    - Let `true(N) = promote(E1, factor(T, S), after(E1))`
    - Let `false(N) = promote(E1, S, after(E1))`

  _Note that flow analysis treats `E1 is! S` the same as the equivalent
  expression `!(E1 is S)`._

- **type cast** If `N` is an expression of the form `E1 as S` where the
  static type of `E1` is `T` then:
  - Let `before(E1) = before(N)`
  - Let `after(N) = promote(E1, S, after(E1))`

- **Conditional expression**: If `N` is a conditional expression of the form `E1
  ? E2 : E3`, then:
  - Let `before(E1) = split(before(N))`.
  - Let `before(E2) = true(E1)`.
  - Let `before(E3) = false(E1)`.
  - Let `after(N) = unsplit(join(after(E2), after(E3)))`.
  - Let `true(N) = unsplit(join(true(E2), true(E3)))`.
  - Let `false(N) = unsplit(join(false(E2), false(E3)))`.

- **If-null**: If `N` is an if-null expression of the form `E1 ?? E2`, where the
  type of `E1` is `T1`, then:
  - Let `before(E1) = before(N)`.
  - Let `M0 = split(after(E1))`.
  - Let `M1 = promoteToNonNull(E1, M0)`.
  - Let `M1'` be defined as follows:
    - If the static type of `E1` is a subtype of `Null` but not a subtype of
      `Object` _(meaning it's `Null` or an equivalent type)_, let `M1' =
      unreachable(M1)`.
    - Otherwise, let `M1' = M1`.
  - Let `before(E2)` be defined as follows:
    - If the static type of `L1` is a non-nullable type, let `before(E2) =
      unreachable(M0)`.
    - Otherwise, let `before(E2) = M0`.
  - Let `after(N) = unsplit(join(after(E2), M1'))`.

- **Shortcut and**: If `N` is a shortcut "and" expression of the form `E1 && E2`,
  then:
  - Let `before(E1) = split(before(N))`.
  - Let `before(E2) = true(E1)`.
  - Let `true(N) = unsplit(true(E2))`.
  - Let `false(N) = unsplit(join(false(E1), false(E2)))`.

- **Shortcut or**: If `N` is a shortcut "or" expression of the form `E1 || E2`,
  then:
  - Let `before(E1) = split(before(N))`.
  - Let `before(E2) = false(E1)`.
  - Let `false(N) = unsplit(false(E2))`.
  - Let `true(N) = unsplit(join(true(E1), true(E2)))`.

- **Binary operator**: All binary operators other than `==`, `&&`, `||`, and
  `??`are handled as calls to the appropriate `operator` method.

- **Null check operator**: If `N` is an expression of the form `E!`, then:
  - Let `before(E) = before(N)`.
  - Let `after(N) = promoteToNonNull(E, after(E))`.

- **Method invocation**: If `N` is an expression of the form `E1.m1(E2)`, then:
  - Let `before(E1) = before(N)`
  - Let `before(E2) = after(E1)`
  - Let `T` be the static return type of the invocation
  - If `T <: Never` then:
    - Let `after(N) = unreachable(after(E2))`.
  - Otherwise:
    - Let `after(N) = after(E2)`.

  TODO(paulberry): handle `E1.m1(E2, E3, ...)`.

TODO: Add missing expressions, handle cascades and left-hand sides accurately

### Statements

- **Expression statement**: If `N` is an expression statement of the form `E` then:
  - Let `before(E) = before(N)`.
  - Let `after(N) = after(E)`.

- **Break statement**: If `N` is a statement of the form `break [L];`, then:

  - Let `after(N) = unreachable(before(N))`.

- **Continue statement**: If `N` is a statement of the form `continue [L];` then:

  - Let `after(N) = unreachable(before(N))`.

- **Return statement with value**: If `N` is a statement of the form `return
  E1;` then:
  - Let `before(E) = before(N)`.
  - Let `after(N) = unreachable(after(E))`;

- **Return statement without value**: If `N` is a statement of the form
  `return;` then:
  - Let `after(N) = unreachable(before(N))`;

- **Conditional statement**: If `N` is a conditional statement of the form `if
  (E) S1 else S2` then:
  - Let `before(E) = split(before(N))`.
  - Let `before(S1) = true(E)`.
  - Let `before(S2) = false(E)`.
  - Let `after(N) = unsplit(join(after(S1), after(S2)))`.

- **while statement**: If `N` is a while statement of the form `while
  (E) S` then:
  - Let `before(E) = conservativeJoin(split(before(N)), assignedIn(N),
    capturedIn(N))`.
  - Let `before(S) = true(E)`.
  - Let `r` be the `reachability` stack of `before(E)`.
  - Let `breakModels` be a list whose first element is `false(E)`, and whose
    remaining elements are `unsplitTo(r, before(B))` for each `break` statement
    `B` that targets `N`.
  - Let `after(N) = inheritTested(unsplit(join(...breakModels)), after(S))`.

- **for statement**: If `N` is a for statement of the form `for (D; [C]; U) S`,
  then:
  - Let `before(D) = before(N)`.
  - Let `M0 = conservativeJoin(split(after(D)), assignedIn(N'),
    capturedIn(N'))`, where `N'` represents the portion of the for statement
    that excludes `D`.
  - Let `before(S)` be defined as follows:
    - If the condition `C` is present, then:
      - Let `before(C) = M0`.
      - Let `before(S) = true(C)`.
    - Otherwise, let `before(S) = M0`.
  - Let `r` be the `reachability` stack of `before(S)`.
  - Let `continueModels` be a list whose first element is `after(S)`, and whose
    remaining elements are `unsplitTo(r, before(C))` for each `continue`
    statement `C` that targets `N`.
  - Let `before(U) = join(...continueModels)`.
  - Let `M1` be defined as follows:
    - If the condition `C` is present, then let `M1 = false(C)`.
    - Otherwise, let `M1 = unreachable(M0)`.
  - Let `breakModels` be a list whose first element is `M1`, and whose remaining
    elements are `unsplitTo(r, before(B))` for each `break` statement `B` that
    targets `N`.
  - Let `after(N) = inheritTested(unsplit(join(...breakModels)), after(U))`.

- **do while statement**: If `N` is a do while statement of the form `do S while
  (E)` then:
  - Let `before(S) = conservativeJoin(split(before(N)), assignedIn(N),
    capturedIn(N))`.
  - Let `r` be the `reachability` stack of `before(S)`.
  - Let `continueModels` be a list whose first element is `after(S)`, and whose
    remaining elements are `unsplitTo(r, before(C))` for each `continue`
    statement `C` that targets `N`.
  - Let `before(E) = join(...continueModels)`.
  - Let `breakModels` be a list whose first element is `false(E)`, and whose
    remaining elements are `unsplitTo(r, before(B))` for each `break` statement
    `B` that targets `N`.
  - Let `after(N) = unsplit(join(...breakModels))`.

- **for each statement**: If `N` is a for statement of the form `for (T X in E)
  S`, `for (var X in E) S`, or `for (X in E) S`, then:
  - Let `before(E) = before(N)`
  - Let `before(S) = conservativeJoin(split(after(E)), assignedIn(N'),
    capturedIn(N'))`, where `N'` represents the portion of the for statement
    that excludes `E`.
  - Let `after(N) = join(after(S), before(S))`. _In principle, it seems like it
    ought to be necessary for the join to include code paths that come from
    `break` statements that target `N`. However, since `before(S)` is the result
    of a conservative join, no code path coming from a break statement that
    targets `N` can possibly affect the join. So, as an optimization, these code
    paths are ignored._

  TODO(paulberry): this glosses over how we handle the implicit assignment to X.
  See https://github.com/dart-lang/sdk/issues/42653.

- **switch statement**: If `N` is a switch statement of the form `switch (E)
  {alternatives}` (where each `alternative` is a `switchStatementDefault` or
  `switchStatementCase` construct), then:
  - Let `before(E) = before(N)`.
  - Let `unmatched = split(after(E))`. _Note: the name `unmatched` was chosen
    because a future update is planned that will add support for patterns; in
    this update, `unmatched` will model the program's state in the event that
    the value of `E` has failed to match all of the alternatives seen so far._
  - Let `r` be the `reachability` stack of `unmatched`.
  - Collect the `alternatives` into groups, where each alternative is in the
    same group as the following one iff its statement list is empty. _This
    grouping has the property that if any alternative matches, the set of
    statements that will be executed is the last set of statements in the
    group._
  - For each group `G` in `body`:
    - Let `S` be the set of statements in the last alternative of `G`.
    - Let `before(S)` be defined as follows:
      - If any of the alternatives in `G` contains a label, then `before(S) =
        split(conservativeJoin(unmatched, assignedIn(N), capturedIn(N)))`.
      - Otherwise, let `before(S) = split(unmatched)`.
  - Let `breakModels` be a list consisting of:
    - For each group `G` in `body`:
      - For each `break` statement `B` in `G` that targets `N`:
        - `unsplitTo(r, before(B))`.
      - If `after(S)` is locally reachable (where `S` be the set of statements
        in the last alternative of `G`):
        - `unsplit(after(S))`.
    - If `N` does not contain a `default:` clause, and the static type of `E` is
      not an always-exhaustive type:
      - `unmatched`
  - Let `after(N)` be defined as follows:
    - If `breakModels` is an empty list, let `after(N) = unreachable(after(E))`.
    - Otherwise, let `after(N) = unsplit(join(...breakModels))`

  TODO(paulberry): update this to account for patterns.

- **try catch**: If `N` is a try statement of the form `try B catches` then:
  - Let `before(B) = split(before(N))`.
  - For each catch block `on Ti Si` in `catches`:
    - Let `before(Si) = conservativeJoin(before(N), assignedIn(B),
      capturedIn(B))`.
  - Let `after(N) = unsplit(join(after(B), after(S0), ..., after(Sk)))`.

- **try finally**: If `N` is a try statement of the form `try B1 finally B2`
  then:
  - Let `before(B1) = before(N)`
  - Let `before(B2) = join(after(B1), conservativeJoin(before(N),
    assignedIn(B1), capturedIn(B1)))`.
  - Let `after(N) = attachFinally(after(B1), before(B2), after(B2))`.
    - _Note: as an optimization, the computation of `attachFinally` may be
      skipped in two circumstances:_
      - _If `before(B2)` and `after(B2)` are identical flow models (meaning
        nothing of consequence to flow analysis occured in `B2`), then `after(N)
        = after(B1)`._
      - _If `before(B1)`, `after(B1)`, and `before(B2)` are identical flow
        models (meaning nothing of consequence to flow analysis happened in
        `B1`), then `after(N) = after(B2)`._

- **try catch finally**: If `N` is a try statement of the form `try B1 catches
  finally B2`, then it is treated as equivalent to the statement `try { try B1
  catches } finally B2`.

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
