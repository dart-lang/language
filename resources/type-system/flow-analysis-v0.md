# Flow Analysis for Non-nullability

paulberry@google.com, leafp@google.com

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

### Models

A *type test site* is a location in the program where a variable's type is
tested, either via an `is` expression or a cast.

A *variable model*, denoted `VariableModel(declaredType, promotedTypes,
testSites, assigned, unassigned, writeCaptured)`, represents what is statically
known to the flow analysis about the state of a variable at a given point in the
source code.

- `declaredType` is the type assigned to the variable at its declaration site
  (either explicitly or by type inference).

- `promotedTypes` is an ordered set of types that the variable has been promoted
  to, with the final entry in the ordered set being the current promoted type of
  the variable.  Note that each entry in the ordered set must be a subtype of
  all previous entries, and of the declared type.

- `testSites` is an ordered list of *type test site*s representing the set of
  type tests that are known to have been performed on the variable in all code
  paths leading to the given point in the source code.

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
  given point in the source code.  The ith element of the stack (counting from
  the top of the stack) indicates whether the given program point is reachable
  from the ith enclosing control flow split in the program.  If the bottom
  element of `reachable` is `false`, then the given point is definitively known
  by flow analysis to be unreachable from the start of the method under
  analysis.  If it is `true`, then the analysis cannot eliminate the possibility
  that the given point may be reached by some path.  Each other element of the
  stack models the same property, starting from some control flow split between
  the start of the program and the current node.

  - `variableInfo` is a mapping from variables in scope at the given point to
  their associated *variable model*s.

  - We will use the notation `{x: VM1, y: VM2}` to denote a map associating the key
    `x` with the value `VM1`, and the key `y` with the value `VM2`.

  - We will use the notation `VI[x -> VM]` to denote the map which maps every
    key in `VI` to its corresponding value in `VI` except `x`, which is mapped
    to `VM` in the new map (regardless of any value associated with it in `VI`).

  - We will use the notation `[a, b]` to denote a list containing elements `a`
    and `b`.

  - We will use the notation `a::l` where `l` is a list to denote a list
    beginning with `a` and followed by all of the elements of `l`.

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
  represents TODO.

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

- `drop(M)`, where `M = FlowModel(r, VM)` is a flow model which models program
  nodes after a control flow split which are only reachable by one path through
  the split, and is defined as `FlowModel(r1, VM)` where `r0 = pop(r)` and `r1 =
  push(pop(r0), top(r0) && top(r1))`.  Equivalently, `drop(M)` may be thought of
  as `join(M, M)`.

- `join(M1, M2)`, where `M1` and `M2` are flow models, represents the union of
  two flow models and is defined as follows:

  We define `join(M1, M2)` where `M1 = FlowModel(r1, VI1)` and `M2 =
  FlowModel(r2, VI2))` and `pop(r1) = pop(r2) = r0` for some `r0` to be `M3` where:
    - if `top(r1)` is true and `top(r2)` is false, then `M3` is `FlowModel(r0, VI1)`.
    - if `r1` is false and `r2` is true, then `M3` is `FlowModel(pop(r2), VI2)`.
    - otherwise `M3 = FlowModel(r3, VI3)` where:
      - `r3` is `push(pop(r0), top(r0) && top(r1) && top(r2))`
      - `VI3` maps each variable `v` in the domain of `VI1` and `VI2` to
      `joinV(VI1(v), VI2(v))`.  Note that any variable which is in domain of
      only one of the two is dropped, since it is no longer in scope.

  Both join and joinV are commutative and associative by construction.

  For brevity, we will sometimes extend `join` to more than two arguments in the
  obvious way.  For example, `join(M1, M2, M3)` represents `join(join(M1, M2),
  M3)`, and `join(S)`, where S is a set of models, denotes the result of folding
  all models in S together using `join`.

- `exit(M)` represents the model corresponding to a program location which is
  unreachable, but is otherwise modeled by flow model `M = FlowModel(r, VI)`,
  and is defined as `FlowModel(push(pop(r), false), VI)`

### Promotion

Promotion policy is defined by the following operations on flow models.

Policy:
  - We say that at type `T` is a type of interest for a variable `x` in a list
    of test sites `sites` if `sites` contains `x is T` or `x as T`.

  - We say that a variable `x` is promotable via initialization given variable
    model `VM` if:
    - `VM = VariableModel(declared, promoted, sites, assigned, unassigned, captured)`
    - and `captured` is false
    - and `promoted` is empty
    - and `x` is declared with no explicit type and no initializer
    - and `assigned` is false and `unassigned` is true

  - We say that a variable `x` is promotable via assignment of an expression of
    type `T` given variable model `VM` if
    - `VM = VariableModel(declared, promoted, sites, assigned, unassigned, captured)`
    - and `captured` is false
    - and `promoted = S::l` or (`promoted = []` and `declared = S`)
    - and `T <: S` and not `S <: T`
    - and `T` is a type of interest for `x` in `sites`

  - We say that a variable `x` is demotable via assignment of an expression of
    type `T` given variable model `VM` if
    - `VM = VariableModel(declared, promoted, sites, assigned, unassigned, captured)`
    - and `captured` is false
    - and promoted contains `T`

Definitions:

- `assign(x, E, M)` where `x` is a local variable, `E` is an expression of
  inferred type `T`, and `M = FlowModel(r, VI)` is the flow model for `E` is
  defined to be `FlowModel(r, VI[x -> VM])` where:
    - `VI(x) = VariableModel(declared, promoted, sites, assigned, unassigned, captured)`
    - if `captured` is true then:
      - `VM = VariableModel(declared, promoted, sites, true, false, captured)`.
    - otherwise if `x` is promotable via initialization given `VM` then
      - `VM = VariableModel(declared, [T], sites, true, false, captured)`.
    - otherwise if `x` is promotable via assignment of `E` given `VM`
      - `VM = VariableModel(declared, T::promoted, sites, true, false, captured)`.
    - otherwise if `x` is demotable via assignment of `E` given `VM`
      - `VM = VariableModel(declared, demoted, sites, true, false, captured)`.
      - where `demoted` is the suffix of `promoted` starting with the first
        occurrence of `T`.

Questions:
 - The interaction between assignment based promotion and downwards inference is
   probably managable.  I think doing downwards inference using the current
   type, and then promoting the variable afterwards is fine for all reasonable
   cases.
 - The interaction between assignment based demotion and downwards inference is
   a bit trickier.  In so far as it is manageable, I think it would need to be
   done as follows, given `x = E` where `x` has current type `S`.
     - Infer `E` in context `S`
     - if the inferred type of `E` is `T` and `S <: T` and the demotion policy
     applies, then instead of treating this as `x = (E as S)` (or an error),
     then instead treat `x` as promoted to `S` in the scope of the assigment.

   - if a variable is tests before it is initialized, we must choose whether to
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
  - `null(N) = exit(after(N))`.
  - `notNull(N) = join(true(N), false(N))`.
  - `after(N) = notNull(N)`.

If `N` is an expression, and the above rules specify the value to be assigned to
`after(N)`, but do not specify values for `true(N)`, `false(N)`, `null(N)`, or
`notNull(N)`, then they are all assigned the same value as `after(N)`.


- **True literal**: If `N` is the literal `true`, then:
  - Let `true(N) = before(N)`.
  - Let `false(N) = exit(before(N))`.

- **False literal**: If `N` is the literal `false`, then:
  - Let `true(N) = exit(before(N))`.
  - Let `false(N) = before(N)`.

- **Shortcut and**: If `N` is a shortcut "and" expression of the form `E1 && E2`,
  then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = split(true(E1))`.
  - Let `true(N) = drop(true(E2))`.
  - Let `false(N) = join(split(false(E1)), false(E2))`.

- **Shortcut or**: If `N` is a shortcut "or" expression of the form `E1 || E2`,
  then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = split(false(E1))`.
  - Let `false(N) = drop(false(E2))`.
  - Let `true(N) = join(split(true(E1)), true(E2))`.

- **If-null**: If `N` is an if-null expression of the form `E1 ?? E2`, then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = split(null(E1))`.
  - Let `null(N) = drop(null(E2))`.
  - Let `notNull(N) = join(split(notNull(E1)), notNull(E2))`.

- **operator==** TODO

- **Binary operator**: All binary operators other than `&&`, `||`, and `??` are
  handled as calls to the appropriate `operator` method.

- **Conditional expression**: If `N` is a conditional expression of the form `E1
  ? E2 : E3`, then:
  - Let `before(E1) = before(N)`.
  - Let `before(E2) = split(true(E1))`.
  - Let `before(E3) = split(false(E1))`.
  - Let `after(N) = join(after(E2), after(E3))`.
  - Let `true(N) = join(true(E2), true(E3))`.
  - Let `false(N) = join(false(E2), false(E3))`.
  - Let `null(N) = join(null(E2), null(E3))`.
  - Let `notNull(N) = join(notNull(E2), notNull(E3))`.


- **Local variable assignment**: If `N` is an expression of the form `x = E1`
  where `x` is a local variable, then:
  - Let `before(E1) = before(N)`.
  - Let `after(N) = assign(x, E1, after(E1))`.
  - Let `true(N) = assign(x, E1, true(E1))`.
  - Let `false(N) = assign(x, E1, false(E1))`.
  - Let `null(N) = assign(x, E1, null(E1))`.
  - Let `notNull(N) = assign(x, E1, notNull(E1))`.



### Statements

- **Conditional statement**: If `N` is a conditional statement of the form `if
  (E) S1 else S2` then:
  - Let `before(E) = before(N)`.
  - Let `before(S1) = split(true(E))`.
  - Let `before(S2) = split(false(E))`.
  - Let `after(N) = join(after(S1), after(S2))`.
  - Let `true(N) = join(true(S1), true(S2))`.
  - Let `false(N) = join(false(S1), false(S2))`.
  - Let `null(N) = join(null(S1), null(S2))`.
  - Let `notNull(N) = join(notNull(S1), notNull(S2))`.

