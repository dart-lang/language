# Horizontal inference

Author: paulberry@google.com, Version: 1.2 (See [Changelog](#Changelog) at end)

Horizontal inference allows certain arguments of an invocation (specifically
function literals) to be type inferred in a context derived from the type of
other arguments.

This functionality will initially be guarded by the experimental flag
`inference-update-1`.

## Motivation

The key motivating example is the `Iterable.fold` method, which has the
following signature:

```dart
abstract class Iterable<E> {
  T fold<T>(T initialValue, T combine(T previousValue, E element)) { ... }
}
```

A typical usage of `fold` today looks like this:

```dart
Iterable<int> values = ...;
int largestValue = values.fold(0, (a, b) => a < b ? b : a);
```

Note the use of the explicit type `int` for `largestValue`.  We would like for
the user to be able to drop this explicit type, and instead write:

```dart
Iterable<int> values = ...;
var largestValue = values.fold(0, (a, b) => a < b ? b : a);
```

Today this doesn't work, because without the leading `int`, the downwards
inference phase of type inference has no information with which to choose a
preliminary type for the type parameter `T`, so the type context used for
inference of the function literal `(a, b) => a < b ? b : a` is `_ Function(_,
int)`.  Hence, `a` gets assigned a static type of `Object?`, and this leads to a
compile error at `a < b`.

With horizontal inference, type inference first visits the `0`, and uses its
static type to assign a preliminary type of `int` to the type parameter `T`.
Then, when it proceeds to perform type inference on the function literal, the
type context is `int Function(int, int)`.  This results in `a` being assigned a
static type of `int`, which is what the user intends.

## Terminology

In this document we make use of the following terms:

- An "invocation" is any of the following syntactic constructs, as defined in
  the [language specification][].  Note that all of these syntactic constructs
  end in a list of arguments (_\<arguments\>_):

  - A constructor _\<redirection\>_.

  - An _\<initializerListEntry\>_ of the form **super** _\<arguments\>_ or
    **super** `.` _\<identifier\>_ _\<arguments\>_.

  - A _\<metadatum\>_ of the form _\<constructorDesignation\>_ _\<arguments\>_.

  - A _\<newExpression\>_, _\<constObjectExpression\>_, or
    _\<constructorInvocation\>_.

  - A _\<primary\>_ of the form **super** _\<argumentPart\>_.

  - An _\<expression\>_ followed by a _\<selector\>_ of the form
    _\<argumentPart\>_.

- The "target" of an invocation is the syntactic construct immediately to the
  left of the invocation's _\<arguments\>_.

- A "constructor invocation" is an invocation whose target refers to a
  constructor.  This corresponds to the syntactic forms _\<redirection\>_,
  _\<initializerListEntry\>_, _\<metadatum\>_, _\<newExpression\>_,
  _\<constObjectExpression\>_, and _\<constructorInvocation\>_.

- A "non-constructor invocation" is any other invocation.  For non-constructor
  invocations, the target always takes the syntactic form of an expression,
  though it may not actually have expression semantics (e.g. in the case where
  the target refers to a top level function or static method).

- The "target function type" of an invocation is the type of the invocation's
  target, if it is a function type.  For constructor invocations, this is the
  function type of the corresponding constructor.  For non-constructor
  invocations, the target function type is determined as part of type inference,
  as specified below.

- A "dynamic invocation" is a non-constructor invocation that has no target
  function type.

- "Type inference" is a phase of compilation in which a static type is assigned
  to each expression in a Dart program.  It is defined in the [Top-level and
  local type inference][inference] document.

- The "type inference algorithm" is a recursive process of visiting all the
  statements and expressions in the program in a well-defined order, with the
  nesting structure of the recursion reflecting the nesting structure of
  statements and expressions in the program's syntax tree.  The precise order in
  which statements and expressions are visited is defined in the [flow
  analysis][] document.  Note that this document is unfinished; one particular
  piece of information missing from it is the precise order in which arguments
  to an invocation are visited.  This proposal supplies that information.

- To "perform inference" on a given expression or statement means to execute the
  portion of the type inference algorithm that visits that expression or
  statement.

- A "type schema" (defined [here][type schemas]) is a generalization of the
  normal Dart type syntax, extended with a type known as "the unknown type"
  (denoted `_`), which allows representation of incomplete type information.

- An expression's "type context" is a type schema representing information
  captured by the type inference algorithm from the context surrounding it.  In
  most circumstances, it represents the set of static types that the expression
  could have without provoking a static error.  _(There are a few exceptions;
  for example the context of the RHS of an assignment to a promoted variable is
  the set of types that the expression could have without causing the variable
  to be demoted)._ The type context of an expression, together with other
  information defined in [flow analysis][], constitutes the **input** to the
  corresponding type inference step.

- An "implicit type argument" is a type argument to a generic invocation whose
  precise value is not directly specified in code, but is instead determined
  automatically by the compiler during type inference.

- A "type constraint" (defined [here][type constraints]) is a limitation on the
  possible values that may be assigned to an implicit type argument.

- "Subtype constraint generation" (defined [here][subtype constraint
  generation]) is an operation on two type schemas that produces a set of type
  constraints by attempting to make one type schema a subtype of another.  The
  rules for subtype constraint generation all take the form "`P` is a subtype
  match for `Q` with respect to the type variables `L` under constraints `C`".
  In this document, we invoke subtype constraint generation through the phrase
  "try to match `P` as a subtype of `Q`" (implicitly the set of type variables
  `L` is the set of generic type parameters of the target function type).

- The "constraint solution for a type variable" (defined [here][constraint
  solution for a type variable]) is a preliminary assignment of a type schema to
  a type variable based on a set of constraints.  It may contain occurrences of
  the unknown type.

- The "constraint solution for a set of type variables" (defined
  [here][constraint solution for a set of type variables]) is a mapping from
  type variables to type schemas, formed from a set of constraints and a partial
  solution.  Typically, each type variable is mapped to the result of solving
  the constraints that apply to it (according to the bullet above), plus an
  additional constraint based on the bound of the type variable.  The partial
  solution is used to break loops when the bound of one type variable refers to
  others, and to effectively "freeze" the solution of each variable at the time
  it becomes fully known (that is, it does not contain `_`).

- The "grounded constraint solution for a type variable" (defined
  [here][grounded constraint solution for a type variable]) is a final
  assignment of a type to a type variable based on a set of constraints.  It is
  a type, not a type schema, so it may not contain occurrences of the unknown
  type.

- The "grounded constraint solution for a set of type variables" (defined
  [here][grounded constraint solution for a set of type variables]) is a final
  mapping from type variables to types, formed from a set of constraints and a
  partial solution.  It parallels the corresponding definition for the
  non-grounded constraint solution.

- A "function literal expression" is a syntactic construct that consists of a
  _\<functionExpression\>_, possibly enclosed in parentheses, and possibly
  associated with an argument name.  Precisely, a syntactic construct is a
  direct function literal iff it takes one of the following syntactic forms:

  - A _\<functionExpression\>_.

  - A _\<namedArgument\>_, where the _\<expression\>_ part is a direct function
    literal.

  - `(` _\<expression\>_ `)`, where the _\<expression\>_ part is a direct
    function literal.

[language specification]: https://dart.dev/guides/language/spec
[inference]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md
[flow analysis]: https://github.com/dart-lang/language/blob/master/resources/type-system/flow-analysis.md#flow-analysis
[type schemas]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md#type-schemas
[type constraints]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md#type-constraints
[subtype constraint generation]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md#subtype-constraint-generation
[constraint solution for a type variable]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md#constraint-solution-for-a-type-variable
[constraint solution for a set of type variables]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md#constraint-solution-for-a-set-of-type-variables
[grounded constraint solution for a type variable]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md#grounded-constraint-solution-for-a-type-variable
[grounded constraint solution for a set of type variables]: https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md#grounded-constraint-solution-for-a-set-of-type-variables

## Type inference algorithm for invocations

_Since the full algorithm for type inference of invocation has not been
previously specified, this section specifies it in its entirety.  Afterwards
I'll make a note of the differences from language version 2.18._

Performing type inference on an invocation consists of the following steps:

1. If the invocation is a non-constructor invocation, perform type inference on
   its target, supplying a type context of `_`.  If the resulting type is a
   function type, this becomes the target function type.  Otherwise, the
   invocation is a dynamic invocation and has no target function type.  _Note
   that barring compilation errors, dynamic invocations can only occur if the
   target has a type of `dynamic` or `Function`._

2. Determine if generic inference is needed.  Generic inference is needed iff
   the following conditions are all met:

   - There is a target function type.

   - The target function type is generic.

   - The invocation does not explicitly specify type arguments using the
     _\<typeArguments\>_ syntax.

3. Initial constraints and downwards inference: if generic inference is needed,
   try to match the return type of the target function type as a subtype of the
   invocation's type context.  This produces an initial set of type constraints.
   Then, using those constraints, find the constraint solution for the target
   function type's type variables, using an initial partial solution that maps
   all type variables to the unknown type.  This produces a preliminary partial
   solution for the inferred types, which will be updated in later type
   inference steps.

4. Visit arguments: Partition the arguments into stages (see [argument
   partitioning](#Argument-partitioning) below), and then for each stage _k_, do
   the following:

   * Compute the type context for all invocation arguments in stage _k_.  If
     generic inference is needed, these contexts are obtained by substituting
     the preliminary mapping (from the most recent "downwards inference" or
     "horizontal inference" step) into the corresponding parameter type from the
     target function type.  Otherwise, if there is a target function type and
     there are explicit type arguments, they are obtained by substituting the
     explicit type arguments into the parameter type.  Otherwise, if there is a
     target function type and no explicit type arguments _(this case can only
     happen if the target function type is non-generic)_, the parameter type is
     used directly.  Finally, in the case where this is a dynamic invocation,
     each type context is `_`.

   * Perform type inference on all invocation arguments in stage _k_ that are
     not function literal expressions, in source order.  _Note that an invariant
     of the partitioning is that arguments that are not function literal
     expressions are always placed in stage zero._

   * Perform type inference on all arguments selected for stage _k_ that are
     function literal expressions, in source order.  _Note that we do not
     believe the order of performing type inference on function literal
     expressions to be user-visible, but we specify source order anyway, to
     reduce the risk of unpredictable behavior._

   * Constraint generation: if generic inference is needed, try to match the
     static type of each of the arguments selected for stage _k_ with the
     corresponding parameter type from the target function type.  This produces
     additional type constraints beyond those gathered in step 3.

   * Horizontal inference: if generic inference is needed, and this is not the
     last stage, use all the type constraints gathered so far to find the
     constraint solution for the target function's type variables, using the
     preliminary partial solution from the most recent previous execution of
     either this step or step 3.  This produces an updated partial solution for
     the inferred types.

5. Upwards inference: if generic inference is needed, use all the type
   constraints gathered so far to find the **grounded** constraint solution for
   the target function's type variables, using the preliminary partial solution
   from the most recent execution of step 4.  This produces the final solution
   for the inferred types.  Check that each inferred type is a subtype of the
   bound of its corresponding type parameter.

6. Type checking: Check that the static type of each argument is assignable to
   the type obtained by substituting the final mapping (from step 5) into the
   corresponding parameter type of the invocation target.

7. Compute static type: Finally, the static type of the invocation expression is
   computed as follows.  If generic inference was needed, the static type is
   obtained by substituting the final mapping (from step 5) into the return type
   of the target function type.  Otherwise, if there is a target function type
   and there are explicit type arguments, it is obtained by substituting the
   explicit type arguments into the parameter type.  Otherwise, if there is a
   target function type and no explicit type arguments _(this can only happen if
   the target function type is non-generic)_, the static type is the return type
   of the target function type.  Finally, in the case where this is a dynamic
   invocation, the static type is `dynamic`.

### Argument partitioning

In the algorithm above, the argument partitioning in step 4 works as follows.
First there is a _dependency analysis_ phase, in which type inference decides
which invocation arguments might benefit from being type inferred before other
arguments, and then a _stage selection_ phase, in which type inference
partitions the arguments into stages.

#### Dependency analysis

First, we form a dependency graph among the invocation arguments based on the
following rule: there is a dependency edge from argument _A_ to argument _B_ if
and only if the type of the invocation target is generic, and the following
relationship exists among _A_, _B_, and at least one of the invocation target’s
type parameters _T_:

1. _A_ is a function literal expression,

2. AND the parameter in the invocation target corresponding to _A_ is function
   typed,

3. AND _T_ is a free variable in the type of at least one of the parameters of
   that function type,

4. AND the corresponding parameter in _A_ does not have a type annotation,

5. AND EITHER:

   * The parameter in the invocation target corresponding to _B_ is function
     typed, and _T_ is a free variable in its return type

   * OR the parameter in the invocation target corresponding to _B_ is _not_
     function typed, and _T_ is a free variable in its type.

_The idea here is that we're trying to draw a dependency edge from A to B in
precisely those cirumstances in which there is likely to be a benefit to
performing a round of horizontal inference after type inferring B and before
type inferring A._

If the type of the invocation target is `dynamic` or the `Function` class, or
some non-generic function type, then the resulting graph has no edges.

_So, for example, if the invocation in question is this:_

```dart
f((t, u) { ... } /* A */, () { ... } /* B */, (v) { ... } /* C */, (u) { ... } /* D */)
```

_And the target of the invocation is declared like this:_

```dart
void f<T, U, V>(
    void Function(T, U) a,
    T b,
    U Function(V) c,
    V Function(U) d) => ...;
```

_then the resulting dependency graph looks like this:_

&emsp;B &lArr; A &rArr; C &hArr; D

_(That is, there are four edges, one from A to B, one from A to C, one from C to D, and one from D to C)._

#### Stage selection

After building the dependency graph, we condense it into its strongly connected
components (a.k.a. "dependency cycles").  The resulting condensation is
[guaranteed to be acyclic] (that is, considering the nodes of the condensed
graph, the arguments in each node depend transitively on each other, and
possibly on the arguments in other nodes, but no dependency cycle exists between
one node and another).

[guaranteed to be acyclic]: https://en.wikipedia.org/wiki/Strongly_connected_component#Definitions

_For the example above, C and D are condensed into a single node, so the graph
now looks like this:_

&emsp;{B} &lArr; {A} &rArr; {C, D}

Now, the nodes are grouped into stages as follows.  Stage zero consists of the
arguments from all nodes that have no outgoing edges.  Then, those nodes are
removed from the graph, along with all their incoming edges.  For each of the
following stages, we follow the same procedure: from the graph produced by stage
_k_, let stage _k+1_ be the set of arguments from all nodes that have no
outgoing edges, then delete those nodes and their incoming edges to produce a
newly reduced graph.  We repeat this until the graph is empty.

_In this example, that means that there will be two stages.  The first stage
will consist of arguments B, C, and D, and the second stage will consist of
argument A._

_The intuitive justification for this algorithm is that by condensing the
dependency graph into strongly connected components, we ensure that, in the
absence of dependency cycles, dependency arcs always go from earlier stages to
later stages; in other words we obtain each bit of information before it is
needed, if possible.  In the event that it's not possible due to a dependency
cycle, we group all arguments in the dependency cycle into the same stage, which
reproduces the previous behavior of the Dart language._

_(Note that the invariant mentioned earlier, that non-function literals are
always placed in the first stage, is guaranteed by the fact that dependency
analysis only draws an edge from A to B if A is a function literal.)_

## Additional information

_The remaining sections are intended to give context and additional information;
they are non-normative._

### Differences from language version 2.18

_The behavior of language version 2.18 may be recovered by modifying step 4
[Type inference algorithm for
invocations](#type-inference-algorithm-for-invocations) ("visit arguments") as
follows: perform type inference on all invocation arguments in source order,
regardless of whether they are function literal expressions, and do not do any
horizontal inference.  Today, since the feature is not yet enabled, the
implementations behave in this way when the experiment flag `inference-update-1`
is not enabled.  Once the experiment flag has been enabled by default, the
implementations will behave in this way when the Dart language version is less
than the version number in which that flag was turned on._

### Why is it safe to alter the visit order?

_Note that in most cases, flow analysis depends critically on the fact that type
inference visits subexpressions in the same order they are evaluated.  For
example, in the following code, the first argument to `f` requires a null check,
because `int?` does not support `operator +`._

```dart
void f(int i, int j) { ... }
void g(int? i) {
  f(i! + 1, i = 0);
}
```

_If type inference instead visited the `i = 0` argument first, the `!` would be
considered unnecessary (because `i = 0` promotes the type of `i` to non-nullable
`int`), so we would be permitted to write `f(i + 1, i = 0)`.  However, this
would fail at runtime, because arguments are evaluated in source order, so `i +
1` is evaluated before `i = 0`._

_In general, we risk these sorts of breakages any time we change the order in
which we perform type inference on invocation arguments.  However, there's an
exception for arguments that are function literals: they may be safely
re-ordered within the invocation, because the act of **evaluating** a function
literal doesn't actually have any runtime effect.  The runtime effect doesn't
happen until the function literal is **called**, and the earliest this can
possibly happen until after all the invocation arguments have been evaluated._

_This is why the invariant mentioned above (that non-function literals are always
placed in the first stage) is critically important&mdash;it guarantees that the
only arguments that will be type inferred out of order are function literals._

### Why do we defer all function literals?

_In step 4 of [Type inference algorithm for
invocations](#type-inference-algorithm-for-invocations), arguments that are not
function literal expressions are always visited before arguments that are
function literal expressions, even within a single stage.  The reason for this
is that it guarantees that regardless of the dependencies among the arguments,
type inference will always visit all non-(function literal) arguments before all
function literal arguments._

_This guarantee leads to a modest improvement in flow analysis: if a function
literal captures a write to a variable, causing the variable to be demoted, the
demotion won’t take effect until after all invocation arguments.  For example:_

```dart
void f(void Function() callback, int i) { ... }
void test(int? i) {
  if (i != null) { // `i` is promoted to `int` now
    f(() {
      i = null; // `i` is write captured, demoting it to `int?`
    }, i + 1 // but the demotion hasn’t occurred yet, so this is ok
    );
    // now, after the call to `f`, the demotion takes effect.
    print(i?.isEven); // `?.` is needed
  }
}
```

_This is sound for the same reason that altering the visit order of function
literals is safe: because the function literal can't actually be **called** until
after all the invocation arguments have been evaluated.  So when `i + 1` is
evaluated, `i` is guaranteed to still be non-null._

_To avoid inconsistent behavior between generic and non-generic invocations, we
defer type inference of function literals in all invocations, even if the
invocation target isn’t generic._

## Changelog

### 1.2

- Use `_` consistently to refer to the "unknown" type schema.

- Clarify what is meant by the term "type schema".

- Clarify the notions of "constraint solution for a set of type variables" and
  "grounded constraint solution for a set of type variables".  These are now
  defined in `resources/type-system/inference.md`, so we include links to their
  definitions.

### 1.1

- Add "terminology" section, with references to other docs, and improve
  nomenclature consistency elsewhere in the document.

- Do not attempt to specify both the new and old algorithms; instead just
  specify the new algorithm and note how the old algorithm differs in
  non-normative text.

- Clarify that the type inference stages constitute a _partition_ of the
  arguments.

- Ensure that all non-normative text is italicized.

- Minor additional clean-ups.

### 1.0

Initial version.
