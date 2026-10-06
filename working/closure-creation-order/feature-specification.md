# Closure Creation Order Feature Specification

Author: Paul Berry

Status: Draft

Experiment flag: closure-creation-order

## CHANGELOG

2026.10.04
  - Initial version.

## Summary

This proposal allows a local variable to keep its type promotion inside a
closure, provided that the variable is never assigned after the closure is
created. For example:

```dart
int foo({int? arg}) {
  arg ??= 0;
  return (() => arg)(); // OK: `arg` has type `int` inside the closure.
}
```

Today, this code has a compile-time error, because `arg` is assigned somewhere
in `foo`, so flow analysis discards its promotion inside the closure. Under this
proposal, flow analysis notices that the only assignment to `arg` happens
before the closure is created, so the promotion is kept.

This addresses [language#1536][].

[language#1536]: https://github.com/dart-lang/language/issues/1536

## Background

### Today's rule

A *closure* is a function expression, a local function declaration, or the
initializer of a `late` local variable. _A `late` initializer is treated as a
closure because it executes lazily, at the time of the first read of the
variable, rather than at the point where it appears._

When flow analysis reaches a closure `C`, it analyzes the body of `C` right
away, in a state derived from the state before `C`. This is not the state in
which `C`'s body will actually execute, because `C` may be invoked later, after
other code has run. So flow analysis adjusts the state as follows:

- Every variable declared outside of `C` that is assigned anywhere in the
  enclosing top-level declaration has its promotions discarded, and is no
  longer considered definitely unassigned, because the assignment might have
  happened between the creation of `C` and its invocation.

- Every variable that is assigned inside a closure in which it isn't declared
  is *write captured*, which means it can't be promoted again inside `C`.
  _Such a variable might be changed at any time, by an invocation of the
  closure that assigns it._

- After `C`, in the enclosing function, every variable that is assigned inside
  `C` is write captured.

In addition, when a closure suspends (at an `await` expression, or a `yield` or
`yield*` statement), any variable that the closure reads, and that is assigned
anywhere in the enclosing top-level declaration, has its promotions discarded,
because the enclosing function might run while the closure is suspended.

These rules are documented in [flow-analysis.md][], in the section "Closures
and suspensions".

[flow-analysis.md]: ../../resources/type-system/flow-analysis.md

### The problem

The first bullet above is more conservative than it needs to be. If an
assignment executes before the closure is created, then that execution of the
assignment can't invalidate a promotion that was in effect when the closure
was created. (The same assignment might execute again later, for example in a
loop; the definition of "after", below, takes care of that.) For example:

```dart
void printLater(int? value, void Function(void Function()) schedule) {
  value ??= 0;
  schedule(() => print(value + 1)); // Error today, OK under this proposal.
}
```

Today, programmers work around this by adding `!` or a cast inside the
closure, or by copying the variable into a fresh `final` variable before
creating the closure. Both workarounds are noise, and the first one can hide
real bugs if the code is changed later.

## Proposal

This proposal changes "assigned anywhere" to "assigned *after* `C` is created"
in the rules above, both on entry to a closure and when a closure suspends. The
tricky part is defining "after". The rest of this section defines it precisely.

### Creation point

The *creation point* of a closure `C` is the end of `C`: the end of the
function expression, the end of the local function declaration, or the end of
the `late` variable's initializer expression. _We say that `C` is created when
execution reaches its creation point. So a local function declaration is
created at its declaration, and a `late` variable's initializer is created
when the declaration is reached._

Local functions that call themselves, or each other, need no special treatment
(setting aside [language#4779][], which is addressed by [closure promotion
soundness][]). Any assignment that executes as a result of invoking a closure
`D` is inside `D` (or inside some closure that `D` invokes). If the variable it
assigns to is declared outside that closure, then the variable is write
captured anyway; otherwise, each invocation of the closure has its own copy of
the variable.

### Analysis order

The *analysis order* is the order in which flow analysis visits code, with the
bodies of closures visited at the points where flow analysis visits the
closures. This is mostly the same as the textual order, with the following
points worth noting:

- In `x = E`, `x op= E`, and `x ??= E`, the assignment to `x` follows `E`. In
  `++x`, `--x`, `x++`, and `x--`, the assignment follows the read of `x`. So in
  `x += f(() => x)`, the assignment to `x` follows the closure's creation
  point.
- In a pattern assignment `P = E`, the assignments to the variables in `P`
  follow `E`. So in `(a, b) = g(() => a)`, the assignment to `a` follows the
  closure's creation point.
- In `for (X in E) S`, the implicit assignment to `X` follows `E` and precedes
  `S`.
- In `for (D; E; U) S`, `D` is followed by `E`, then `S`, then `U`. Because of
  the loop rule below, the order of code within a single loop never matters,
  only the fact that `D` precedes the rest of the loop.
- Since Dart 2.18 (see [horizontal inference][]), if an argument of an
  invocation is a function literal, flow analysis visits it (including
  everything nested inside it) after all the arguments of the invocation that
  are not function literals. Function literal arguments are visited in an
  order determined by horizontal inference. So in `f(() => x, x = null)`, the
  assignment `x = null` precedes the closure's creation point. _This is sound,
  because the closure can't be invoked until the invocation happens, which is
  after all the arguments have been evaluated. For the same reason, it's sound
  for closures nested inside the function literal: in
  `f(() => () => x, x = null)`, the assignment also precedes the creation point
  of the inner closure._ This applies only to
  function literals that are actually deferred in this way:
  - The library must have language version 2.18 or later.
  - The function literal may be enclosed in parentheses, and the argument may
    be positional or named. So in `f(a: (() => x), b: x = null)`, the
    assignment `x = null` precedes the closure's creation point.
  - The function literal must be an argument of the invocation itself, not
    nested inside some other argument. So in `f(g(() => x), x = null)`, the
    closure is deferred only until the end of `g`'s argument list, and the
    assignment `x = null` follows the closure's creation point.

In this document, `for (X in E) S` stands for every form of `for`-`in` loop
whose loop variable is an existing variable `X`: a `for` statement, an `await
for` statement, or a `for` element in a collection literal (in which case `S`
is an element rather than a statement). Similarly, `for (D; E; U) S` stands
for both the statement form and the collection element form.

[horizontal inference]: ../../accepted/2.18/horizontal-inference/feature-specification.md

### Loops

A *loop* is a `do`, `while`, or `for` statement (including `for`-`in` and
`await for`), a `for` element in a collection literal, or a `switch` statement
with at least one labeled case. _A `switch` statement with a labeled case is
considered a loop because `continue L` can jump backward to the labeled case._

A loop *contains* a program point if the program point is in the part of the
loop that can execute more than once. _For example, the initializer `D` of
`for (D; E; U) S` is not contained by the loop, but `E`, `U`, and `S` are. In
`for (X in E) S`, `E` is not contained by the loop, but the implicit
assignment to `X` and `S` are. In `switch (E) { case ... L: case ... }`, `E`
is not contained by the loop, but the cases are._

A loop is not considered to contain the declaration of a variable that is
declared in the loop's header. This includes the variables declared in `D` in
`for (D; E; U) S`, and the variables declared by `for (var X in E) S` and
`for (var P in E) S` (and the corresponding `final`, typed, `await for`, and
collection element forms).

_This is conservative. At run time, each iteration of such a loop has a fresh
copy of the variables declared in its header, so an assignment to one of them
in a later iteration can't affect a closure created in an earlier iteration.
But a more precise rule would be subtle. In `for (var v = ...; E; U) S`, the
copy of `v` for the next iteration is created before `U` is executed, so `U`
operates on the next iteration's copy. So a closure in `S` isn't affected by
assignments in `U`, but a closure in `U` is affected by assignments in the
next iteration's `E` and `S`._

TODO(paulberry): check with the language team whether to adopt the more
precise rule before this feature ships. (Adopting it later would require
another language-versioned change, because keeping more promotions can cause
new errors; see [Impact](#impact).)

### Exclusive groups

An *exclusive group* is a construct consisting of one or more *arms*, such
that once control enters an arm, no part of the group that follows the end of
that arm (in the analysis order) executes during the same execution of the
group.

_Arms are syntactic: a program point or an assignment is inside an arm if it
is located within the source text of that arm._

The exclusive groups are:

- An `if` statement or a collection `if` element (including the if-case
  forms). The then-branch and the else-branch (if present) are arms. The
  condition (or the pattern and guard) is not part of any arm.
- A conditional expression `E1 ? E2 : E3`. `E2` and `E3` are arms.
- A `switch` statement in which no case has a label, or a `switch` expression.
  The body of each case (or group of cases sharing a body), or the result
  expression of each case, is an arm. The patterns and guards are not part of
  any arm, because a guard can create a closure and then fail, so that later
  cases are considered.
- The `catch` clauses of a `try` statement. Each `catch` clause is an arm.
  The `try` block is not an arm, because a `catch` clause can execute after
  it. The `finally` block is not part of the group, because it can execute
  after a `catch` clause.

The `&&`, `||`, and `??` operators, and null-aware accesses, are not exclusive
groups, because their right-hand operands execute after their left-hand
operands.

### After

An assignment `w` to a variable `v` is *after* a program point `P` if either of
the following holds:

- `w` follows `P` in the analysis order, unless there is an exclusive group `G`
  with an arm `A` such that `P` is inside `A`, and `w` is inside `G` but not
  inside `A`.
- There is a loop that contains both `P` and `w`, but does not contain the
  declaration of `v`. _If the loop contained the declaration of `v`, each
  iteration would have a fresh copy of `v`, so assignments in later iterations
  couldn't affect the copy seen by a closure created in an earlier one._

The initialization of a variable at its declaration site is not considered an
assignment for this purpose. The implicit assignment in `for (v in E) S` is.

_The purpose of this definition is to identify the assignments that might
change a variable's value, as seen by a closure, after the closure has been
created. Assignments inside closures are handled separately: if `w` is inside
a closure in which `v` is not declared, then `v` is in `writeCapturedAnywhere`,
so this definition doesn't need to account for closures being invoked at
arbitrary times. For other assignments, if `w` is not after the creation point
of a closure `C`, then once `C` has been created, `w` can't execute on the copy
of `v` that `C` refers to (see [soundness](#soundness)). The converse doesn't
hold: the definition is conservative (see [early exits](#early-exits))._

`writtenAfter(C)` is the set of variables `v` declared outside of a closure
`C`, such that some assignment to `v` is after the creation point of `C`.

_A `switch` statement with a labeled case is not an exclusive group, because a
`continue` statement can transfer control from one case to another. But an
implementation may treat it as one, with no observable difference. To see why,
consider an assignment `w` to a variable `v`, and a program point `P`, such
that `w` follows `P` in the analysis order. Treating the `switch` statement as
an exclusive group could only change whether `w` is after `P` if `P` and `w`
are in different arms of the `switch` statement. If the `switch` statement
doesn't contain the declaration of `v`, then `w` is after `P` anyway, by the
loop rule. If it does, then, since each case has its own scope, `v` is declared
in the case containing `w`, so a closure whose creation point is `P` can't
refer to `v`._

_Similarly, the order in which horizontal inference visits the function
literal arguments of an invocation (see [analysis order](#analysis-order))
never makes an observable difference. To see why, consider an assignment `w`
to a variable `v` inside one function literal argument, and a closure `C`
inside a different function literal argument of the same invocation. If `v`
is declared inside the function literal containing `w`, then `C` can't refer
to `v`. Otherwise, since `w` is inside a closure, `v` is in
`writeCapturedAnywhere`. Either way, whether `w` is after the creation point
of `C` doesn't affect `writtenAfter(C) ∪ writeCapturedAnywhere`, and since `v`
is write captured on entry to `C`, it is never promoted inside `C`, so whether
`v` is in `readIn(C) ∩ writtenAfter(C)` doesn't matter either._

### The rules

Using the notation of [flow-analysis.md][]:

- On entry to a closure `C`, the flow model is `conservativeJoin(M,
  writtenAfter(C) ∪ writeCapturedAnywhere, writeCapturedAnywhere)`, where `M`
  is the flow model in the enclosing function at the point where `C` appears,
  with the variables assigned in `C` write captured. _Today,
  `assignedAnywhere` is used in place of `writtenAfter(C) ∪
  writeCapturedAnywhere`._
- When a closure `C` reaches an `await` expression, a `yield` statement, or a
  `yield*` statement, the flow model `M` is replaced by `conservativeJoin(M,
  readIn(C) ∩ writtenAfter(C), [])`. _Today, `assignedAnywhere` is used in
  place of `writtenAfter(C)`._

All other rules are unchanged.

_`conservativeJoin` also marks the variables in its second argument as not
definitely unassigned. So a variable that is definitely unassigned at the point
where `C` appears, and is not in `writtenAfter(C) ∪ writeCapturedAnywhere`,
remains definitely unassigned inside `C`. Today, it would only remain
definitely unassigned if it were never assigned at all. See [unassigned `late`
variables](#unassigned-late-variables)._

## Examples

### Assignment before the closure

The example from [language#1536][]:

```dart
int foo({int? arg}) {
  arg = 0;
  return (() => arg)(); // OK
}
```

The assignment `arg = 0` promotes `arg` to `int`. No assignment follows the
creation of the closure, so the promotion is kept inside the closure.

### Assignment after the closure

```dart
void f(int? x) {
  if (x == null) return;
  var g = () => x + 1; // Error: `x` might be null when `g` is called.
  x = null;
  g();
}
```

The assignment `x = null` follows the creation of the closure, so `x` is
demoted inside the closure. This is the same as today, and it's necessary for
soundness: `g()` is called after `x` is set to `null`.

### Loops

```dart
void f(List<int?> values, List<void Function()> callbacks) {
  int? x;
  for (var value in values) {
    x = value;
    if (x != null) {
      callbacks.add(() => print(x + 1)); // Error.
    }
  }
}
```

The assignment `x = value` precedes the closure in the analysis order, but
it's inside a loop that contains the closure and not the declaration of `x`.
So it's after the closure: in a later iteration, it may set `x` to `null`
before the closure from an earlier iteration is called. So `x` is demoted
inside the closure.

If the declaration of `x` is moved inside the loop, each iteration has its
own copy of `x`, so the promotion is kept:

```dart
void f(List<int?> values, List<void Function()> callbacks) {
  for (var value in values) {
    int? x;
    x = value;
    if (x != null) {
      callbacks.add(() => print(x + 1)); // OK
    }
  }
}
```

### Mutually exclusive branches

```dart
void Function()? callback;

void f(int? x, bool b) {
  if (x == null) return;
  if (b) {
    callback = () => print(x + 1); // OK
  } else {
    x = null;
  }
}
```

The assignment `x = null` follows the closure in the analysis order, but it's
in an arm of an `if` statement that is never executed if the closure is
created. So it's not after the closure, and the promotion is kept. This makes
the result the same as for the equivalent code with the branches inverted:

```dart
void f(int? x, bool b) {
  if (x == null) return;
  if (!b) {
    x = null;
  } else {
    callback = () => print(x + 1); // OK
  }
}
```

### Deferred function literal arguments

```dart
void open([Config? config]) => show(Spec(
      onInit: (widget) {
        if (config == null) return;
        widget.apply(config);
      },
      bindings: {Config: config ??= Config()},
    ));
```

The function literal passed to `onInit` is deferred, so flow analysis visits
it after the other arguments of `Spec(...)`. So `config ??= Config()` precedes
the closure's creation point in the analysis order, and `config` is promoted
to `Config` on entry to the closure. This is sound,
because the closure can't be invoked until `Spec(...)` is invoked, and by then,
all of its arguments (including `config ??= Config()`) have been evaluated.

Without this proposal, `config` is demoted on entry to the closure, and
promoted again by the null check. Under this proposal, the null check is
unnecessary, so it causes a warning, and the code can be cleaned up:

```dart
void open([Config? config]) => show(Spec(
      onInit: (widget) {
        widget.apply(config);
      },
      bindings: {Config: config ??= Config()},
    ));
```

_This example is relevant to the proposed fix for [language#4778][] (see
[closure promotion soundness][]): without this proposal, that fix would
prevent the null check from promoting `config`, so the code would need
`config!`. With this proposal, no `!` is needed._

[language#4778]: https://github.com/dart-lang/language/issues/4778
[closure promotion soundness]: ../closure-promotion-soundness/feature-specification.md

### `late` variables

```dart
void f(int? x) {
  x ??= 0;
  late int y = x + 1; // OK
  print(y);
}
```

The initializer of `y` is a closure, created when the declaration of `y` is
reached. The only assignment to `x` precedes it, so the promotion of `x` is
kept.

### Unassigned `late` variables

```dart
void f(bool b) {
  late int x;
  if (b) {
    () {
      print(x); // Error: `x` is definitely unassigned.
    };
  } else {
    x = 0;
  }
}
```

The only assignment to `x` is in an arm of an `if` statement that is never
executed if the closure is created, so it's not after the closure, and `x`
remains definitely unassigned inside the closure. Reading a definitely
unassigned `late` variable is an error. Without this proposal, there is no
error, because `x` is assigned somewhere in `f`, so it isn't considered
definitely unassigned inside the closure.

The new error is accurate: if the read of `x` executes, it always throws. There
is no error if `x` is also assigned after the `if` statement, or if the
closure and the assignment are both inside a loop that doesn't contain the
declaration of `x`, or if `x` is assigned inside any closure in which it isn't
declared.

### Early exits

```dart
void Function()? callback;

void f(int? x, bool b) {
  if (x == null) return;
  if (b) {
    callback = () => print(x + 1); // Error.
    return;
  }
  x = null;
}
```

Here, the assignment `x = null` can't actually execute after the closure is
created, because of the `return`. But it follows the closure in the analysis
order, and is not in an exclusive group with it, so it's considered to be after
the closure. Determining otherwise would require reachability information that
isn't available until after the body of the closure has been analyzed. This is
the same as today.

## Soundness

Consider a closure `C`, and an assignment `w` to a variable `v`, such that `w`
is not after the creation point of `C`, and `w` is not inside a closure in
which `v` is not declared. For `w` to execute on the copy of `v` that `C`
refers to after `C` has been created, control would have to reach `w` after
the creation point of `C` without leaving the scope that declares `v` (leaving
and re-entering that scope creates a fresh copy of `v`). That requires a loop
that contains both the creation point of `C` and `w`, but not the declaration
of `v`, and in that case `w` would be after the creation point of `C`, by the
loop rule.

So the promotions in effect at the creation point of `C` are still valid when
`C` begins executing, unless `v` has been assigned in the meantime, either by
the enclosing function (in which case `v` is in `writtenAfter(C)`) or by some
closure (in which case `v` is in `writeCapturedAnywhere`). Either way, the
promotion is discarded.

The same argument applies to suspensions: while `C` is suspended, the only
assignments to `v` that can execute in the enclosing function are those that
are after the creation point of `C`.

It also applies to definite unassignment: if `v` is definitely unassigned at
the creation point of `C`, and is in neither `writtenAfter(C)` nor
`writeCapturedAnywhere`, then no assignment to `v` can execute before `C` reads
it, so `v` is still unassigned when the read executes.

_This argument relies on the same assumption as today's rule: while a closure
is executing, the enclosing function can only execute at points where the
closure suspends. This assumption doesn't hold in all cases; see
[language#4779][] and [language#4778][]. These soundness issues already exist
today, and are addressed separately, in [closure promotion soundness][]._

[language#4779]: https://github.com/dart-lang/language/issues/4779

### Multithreading

If Dart adds shared-memory multithreading, a closure might be invoked on a
different thread from the one that created it. For this proposal to remain
sound, assignments that happen before a closure is created must be visible to
the closure when it's invoked on another thread. This is an implementation
requirement:

- In general, this is satisfied by a memory fence at closure allocation, which
  makes the writes that precede the allocation visible to any thread that
  obtains a reference to the closure.
- Flow analysis visits a deferred function literal argument after the other
  arguments of the invocation, but at run time, the closure may be allocated
  earlier, while the arguments are being evaluated. So the implementation must
  ensure that assignments in the argument list are visible to the closure,
  either by emitting an additional fence for invocations with deferred
  function literal arguments, or by allocating such closures after the other
  arguments have been evaluated. _Closures nested inside a deferred function
  literal need no special treatment, because they can't be allocated until the
  function literal is invoked, which can't happen until the invocation it's
  passed to has begun._

TODO(paulberry): confirm these requirements with the VM team.

## Impact

This change makes flow analysis keep more promotions, and keep more variables
definitely unassigned, inside closures. Most code that is accepted today is
still accepted, but it may cause new warnings, because code that was needed
before (such as a null check, `!`, or a cast) may become unnecessary. In rare
cases, it can cause new errors:

- It changes the static types of some expressions inside closures, which can
  affect type inference. For example, `var y = x; y = null;` inside a closure
  is an error if `x` is promoted to a non-nullable type.
- A read of a `late` variable inside a closure is an error if the variable is
  definitely unassigned there, as in [unassigned `late`
  variables](#unassigned-late-variables). This only happens when the read is
  guaranteed to throw if it executes.

So it's language versioned: it applies only to libraries that have the feature
enabled.

In Google's internal codebase,
TODO(paulberry): measurement `!` operators and casts become unnecessary, and
TODO(paulberry): measurement new errors are reported for reads of definitely
unassigned `late` variables.

## Alternatives considered

### Ignore exclusive groups

A simpler rule would consider every assignment that follows the creation point
in the analysis order to be after it. But then promotion would depend on the
order of the branches of an `if` statement, which would be surprising. For
example, the two forms of `f` in [mutually exclusive
branches](#mutually-exclusive-branches) would behave differently.

### Treat deferred function literals at their textual position

A simpler rule would use the textual order, rather than the order in which flow
analysis visits the code, so that assignments in the arguments that textually
follow a deferred function literal would be after it. But deferred function
literals are common in real-world code, because deferral is what allows the
types of a function literal's parameters to be inferred from other arguments.
And flow analysis already visits such a function literal in a state that
reflects the promotions made by the other arguments, so it would be
inconsistent to then discard those promotions, as in the [deferred function
literal arguments](#deferred-function-literal-arguments) example.

### Take early exits into account

A more precise rule would ignore assignments that can't be reached from the
creation point, as in the [early exits](#early-exits) example. Flow analysis
can't use its own reachability information for this, because the body of a
closure is analyzed at the point where the closure appears, before the code
that follows it. But a syntactic pre-pass, like the one that already determines
which variables are assigned and which are write captured, could recognize
simple cases, such as a block that ends in a `return` statement. This is left
as possible future work, to keep this proposal small.

### Leave definite unassignment unchanged

To avoid the new errors described in [unassigned `late`
variables](#unassigned-late-variables), flow analysis could continue to mark
every variable in `assignedAnywhere` as not definitely unassigned on entry to
a closure, while using `writtenAfter(C)` only for promotions. But that would
require `conservativeJoin` to take a separate set of variables for definite
unassignment, and the only code it would keep accepting is code that reads a
`late` variable in a closure where the read is guaranteed to throw.
