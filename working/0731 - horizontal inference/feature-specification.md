# Horizontal inference

Author: paulberry@google.com, Version: 1.0 (See [Changelog](#Changelog) at end)

Horizontal inference allows certain arguments of an invocation (specifically
function literals) to be type inferred in a context derived from the type of
other arguments.

## Motivation

The key motivating example is the Iterable.fold method, which has the following
signature:

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
inference of the function literal `(a, b) => a < b ? b : a` is `? Function(?,
int)`.  Hence, `a` gets assigned a static type of `Object?`, and this leads to a
compile error at `a < b`.

With horizontal inference, type inference first visits the `0`, and uses its
static type to assign a preliminary type of `int` to the type parameter `T`.
Then, when it proceeds to perform type inference on the function literal, the
type context is `int Function(int, int)`.  This results in `a` being assigned a
static type of `int`, which is what the user intends.

## Type inference algorithm for invocations

The full algorithm for type inference of invocations is expanded as follows.
This algorithm is used for constructor invocations (including those in
annotations, super-constructor calls, and constructor redirects), method
invocations (including super calls), and invocations of function-typed
expressions.

1. Initial constraints: Create some constraints on type parameters by trying to
   match the return type of the invocation target as a subtype of the incoming
   type context.  (For a constructor invocation, the return type of the
   invocation target is considered the raw uninstantiated type of the class
   enclosing the constructor declaration.)

2. Downwards inference: partially solve the set of type constraints accumulated
   in step 1, to produce a preliminary mapping of type parameters to type
   schemas.
   
3. Visit arguments (legacy): If experiment flag `inference-update-1` is not
   enabled, recursively perform inference on all arguments to the invocation in
   source order.  Obtain the type contexts for the recursive inference by
   substituting the preliminary mapping (from step 2) into the corresponding
   parameter types of the invocation target.  For each argument that is
   recursively inferred, create additional constraints on type parameters using
   the resulting static type.  Then proceed to step 5.

4. Visit arguments (new): If experiment flag `inference-update-1` is enabled,
   topologically sort the arguments into stages (see [topological
   sort](#Topological-sort) below), and then for each stage, do the following:

   * Recursively infer all arguments selected for this stage that are not
     function literals (see [what constitutes a function
     literal?](#what-constitutes-a-function-literal), in source order.  (Note
     that an invariant of the topological sort is that non-function literals are
     always placed in the first stage).  The logic for obtaining type contexts
     and for creating additional constraints is the same as in step 3.

   * Recursively infer all arguments selected for this stage that are function
     literals, in source order.

   * Horizontal inference: if this is not the last stage, partially solve the
     set of type constraints accumulated so far, to produce an updated
     preliminary mapping of type parameters to type schemas.  Otherwise proceed
     to step 5.

5. Upwards inference: solve the set of type constraints accumulated so far, to
   produce a final mapping of type parameters to types.  Check that each type is
   a subtype of the bound of its corresponding type parameter.

6. Type checking: Check that the static type of each argument is assignable to
   the type obtained by substituting the final mapping (from step 5) into the
   corresponding parameter type of the invocation target.

7. Assign static type: Finally, obtain the static type of the invocation by
   substituting the final mapping (from step 5) into the return type of the
   invocation target.

(Note that step 4 is the only step that differs from the inference implemented
in Dart today, and it only takes effect if the experiment flag
`inference-update-1` is enabled, hence this feature is backward compatible.)

### Topological sort

In the algorithm above, the "topological sort" in step 4 works as follows.
First there is a _dependency analysis_ phase, in which type inference decides
which invocation arguments might benefit from being type inferred before other
arguments, and then a _stage selection_ phase, in which type inference groups
the arguments into stages.

#### Dependency analysis

First, we form a dependency graph among the invocation arguments based on the
following rule: there is a dependency edge from argument _A_ to argument _B_ if
and only if the type of the invocation target is generic, and the following
relationship exists among _A_, _B_, and at least one of the invocation target’s
type formals _T_:

1. _A_ is a function literal (see [what constitutes a function
   literal?](#what-constitutes-a-function-literal))

2. AND the parameter in the invocation target corresponding to _A_ is function
   typed,

3. AND _T_ is a free variable in at least one of the parameters of that function
   type,

4. AND the corresponding parameter in _A_ is implicitly typed,

5. AND EITHER:

   * The parameter in the invocation target corresponding to _B_ is function
     typed, and _T_ is a free variable in its return type

   * OR the parameter in the invocation target corresponding to _B_ is _not_
     function typed, and _T_ is a free variable in its type.

(The idea here is that we're trying to draw a dependency edge from _A_ to _B_ in
precisely those cirumstances in which there is likely to be a benefit to
performing a round of horizontal inference between type inferring _A_ and type
inferring _B_).

If the type of the invocation target is `dynamic` or the `Function` class, or
some non-generic function type, then the resulting graph has no edges.

So, for example, if the invocation in question is this:

```dart
f((t, u) { ... } /* A */, () { ... } /* B */, (v) { ... } /* C */, (u) { ... } /* D */)
```

And the target of the invocation is declared like this:

```dart
void f<T, U, V>(
    void Function(T, U) a,
    T b,
    U Function(V) c,
    V Function(U) d) => ...;
```

then the resulting dependency graph looks like this:

&emsp;B &lArr; A &rArr; C &hArr; D

(That is, there are four edges, one from A to B, one from A to C, one from C to D, and one from D to C).

#### Stage selection

After building the dependency graph, we condense it into its strongly connected
components (a.k.a. "dependency cycles").  The resulting condensation is
[guaranteed to be acyclic] (that is, the nodes in each strongly connected
component depend transitively on each other and possibly on the nodes in other
strongly connected components, but no cycle exists among multiple strongly
connected components).  For the example above, C and D are condensed into a
single strongly connected component, so the graph now looks like this:

[guaranteed to be acyclic]: https://en.wikipedia.org/wiki/Strongly_connected_component#Definitions

&emsp;(B) &lArr; (A) &rArr; (C &hArr; D)

Then, for each stage of inference, we find all the strongly connected components
with no graph edges pointing to them, and remove them from the graph.  We repeat
the process for successive stages, until no strongly connected components remain
in the graph.  The set of arguments we will recursively infer during each stage
is the union of the arguments in all the strongly connected components removed
from the graph during that stage.

In this example, that means that there will be two stages.  The first stage will
consist of argument A, and the second stage will consist of arguments B, C, and
D.

(Note that the invariant mentioned earlier, that non-function literals are
always placed in the first stage, is guaranteed by the fact that dependency
analysis only draws an edge from _A_ to _B_ if _A_ is a function literal.)

### What constitutes a function literal?

The determination of whether an argument is a function literal is made
syntactically.  An argument is a function literal if it is produced by one of
the following grammar productions (as described in the language specification):

* _\<functionExpression\>_

* _\<namedArgument\>_, where the _\<expression\>_ part is a function literal.

* `(` _\<expression\>_ `)`, where the _\<expression\>_ part is a function
  literal.

### Why is it safe to alter the visit order?

Note that in most cases, flow analysis depends critically on the fact that type
inference visits subexpressions in the same order they are evaluated.  For
example, in the following code, the first argument to `f` requires a null check,
because `int?` does not support `operator +`.

```dart
void f(int i, int j) { ... }
void g(int? i) {
  f(i! + 1, i = 0);
}
```

If type inference instead visited the `i = 0` argument first, the `!` would be
considered unnecessary (because `i = 0` promotes the type of `i` to non-nullable
`int`), so we would be permitted to write `f(i + 1, i = 0)`.  However, this
would fail at runtime, because arguments are evaluated in source order, so `i +
1` is evaluated before `i = 0`.

In general, we risk these sorts of breakages any time we change the order in
which we perform type inference on invocation arguments.  However, there's an
exception for arguments that are function literals: they may be safely
re-ordered within the invocation, because the act of _evaluating_ a function
literal doesn't actually have any runtime effect.  The runtime effect doesn't
happen until the function literal is _called_, and the earliest this can
possibly happen until after all the invocation arguments have been evaluated.

This is why the invariant mentioned above (that non-function literals are always
placed in the first stage) is critically important&mdash;it guarantees that the
only arguments that will be type inferred out of order are function literals.

### Why do we defer all function literals?

In step 4 of [Type inference algorithm for
invocations](#type-inference-algorithm-for-invocations), non-function literals
are always visited before function literals, even within a single stage.  The
reason for this is that it guarantees that regardless of the dependencies among
the arguments, type inference will always visit all non-function literal
arguments before all function literal arguments.

This guarantee leads to a modest improvement in flow analysis: if a function
literal captures a write to a variable, causing the variable to be demoted, the
demotion won’t take effect until after all invocation arguments.  For example:

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

This is sound for the same reason that altering the visit order of function
literals is safe: because the function literal can't actually be _called_ until
after all the invocation arguments have been evaluated.  So when `i + 1` is
evaluated, `i` is guaranteed to still be non-null.

To avoid inconsistent behavior between generic and non-generic invocations, we
defer type inference of function literals in all invocations, even if the
invocation target isn’t generic.



## Changelog

### 1.0

Initial version.
