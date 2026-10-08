# Closure Promotion Soundness Feature Specification

Author: Paul Berry

Status: Draft

Experiment flag: TODO(paulberry): experiment name

## CHANGELOG

2026.10.04
  - Initial version.

## Summary

This proposal fixes two related soundness problems in the way flow analysis
handles promotion of local variables inside closures:

- [language#4779][]: promotion inside a closure is unsound today, if the
  enclosing function can be resumed while the closure is executing, and then
  assigns to the variable.
- [language#4778][]: if Dart adds shared-memory multithreading, the enclosing
  function might execute concurrently with the closure, so promotion inside a
  closure would be unsound whenever the enclosing function might assign to the
  variable after the closure is created.

Both are fixed by the same mechanism: on entry to a closure, flow analysis
*write captures* more variables, which prevents them from being promoted inside
the closure. This proposal describes two variants, which differ only in which
variables are write captured:

- The *full variant* fixes both issues. It write captures every non-final
  variable that might be assigned after the closure is created.
- The *narrow variant* fixes only [language#4779][]. It write captures only
  those variables that might be assigned after the enclosing function resumes
  from a suspension point that follows the creation of the closure.

Both variants assume the changes in [closure creation order][] (which addresses
[language#1536][]). That proposal greatly reduces the number of promotions that
are lost.

[language#1536]: https://github.com/dart-lang/language/issues/1536
[language#4778]: https://github.com/dart-lang/language/issues/4778
[language#4779]: https://github.com/dart-lang/language/issues/4779
[closure creation order]: ../closure-creation-order/feature-specification.md

## Background

### Terminology

A *closure* is a function expression, a local function declaration, or the
initializer of a `late` local variable. _A `late` initializer is treated as a
closure because it executes lazily, at the time of the first read of the
variable._

A variable is *write captured* if it is assigned inside some closure in which
it is not declared. A write captured variable cannot be promoted, because the
closure that assigns it might be invoked at any time. Flow analysis also write
captures variables in other circumstances, as described below.

The rules for closures and suspensions are described in [flow-analysis.md][],
in the section "Closures and suspensions". With the changes in [closure creation
order][], they are as follows:

- On entry to a closure `C`, flow analysis discards the promotions of every
  variable that is assigned after `C` is created, and every variable that is
  assigned inside a closure in which it isn't declared. The latter variables
  are also write captured.
- After `C`, in the enclosing function, the variables that are assigned inside
  `C` are write captured.
- When `C` suspends (at an `await` expression, or a `yield` or `yield*`
  statement), flow analysis discards the promotions of every variable that `C`
  reads and that is assigned after `C` is created.

A variable that is assigned only by enclosing functions is not write captured
inside `C`. So after its promotion is discarded on entry to `C`, it can be
promoted again inside `C`, by a null check or type test. This is sound only if,
while `C` is executing, enclosing functions can only execute at points where
`C` itself suspends. But this assumption doesn't always hold: an enclosing
function can also execute in the middle of `C`, at a point where `C` doesn't
suspend, either because `C` resumes it (see below) or, under shared-memory
multithreading, because it runs concurrently with `C`.

[flow-analysis.md]: ../../resources/type-system/flow-analysis.md

### Resumption while the closure executes ([language#4779][])

A `sync*` function is resumed by calling `moveNext` on its iterator. If a
closure has access to the iterator, it can resume the enclosing function, which
can then assign to a variable that the closure has promoted:

```dart
Iterator<int>? it;
void Function()? c;

Iterable<int> g() sync* {
  int? i = 0;
  c = () {
    if (i != null) {
      it!.moveNext(); // Resumes `g`, which sets `i` to `null`.
      print(i + 1); // Accepted today, but `i` is `null`.
    }
  };
  yield 1;
  i = null;
  yield 2;
}

void main() {
  it = g().iterator;
  it!.moveNext();
  c!();
}
```

Similarly, an `async` function can be resumed synchronously from an `await`, by
completing a sync completer:

```dart
import 'dart:async';

void Function()? c;
var f = Completer<void>.sync();

void g() async {
  int? i = 0;
  c = () {
    if (i != null) {
      if (!f.isCompleted) f.complete(null); // Resumes `g`.
      print(i + 1); // Accepted today, but `i` is `null`.
    }
  };
  await f.future;
  i = null;
}

void main() async {
  g();
  c!();
}
```

_This example is due to Lasse Nielsen._

### Concurrent execution ([language#4778][])

If Dart adds shared-memory multithreading, a closure might be invoked on a
different thread, while the enclosing function continues to execute:

```dart
void f() {
  int? i = 42;
  void closure() {
    if (i != null) {
      doSomeWork();
      print(i + 1); // Accepted today, but `i` might be `null`.
    }
  }

  runOnAnotherThread(closure);
  i = null;
}
```

Here, `f` sets `i` to `null` after the closure is created. If this happens
after the closure checks `i != null`, but before it computes `i + 1`, then the
closure sees `null`. There are no suspension points at all in this example.

## Proposal

### Finals

Let `Final` be the set of variables that are declared `final` (including those
declared `late final`). These variables are exempt from the new write capturing
rules below, because they can't change after they have been successfully read:

- A non-`late` `final` variable can only be read inside a closure if it is
  definitely assigned at the point where the closure appears, and it can't be
  assigned again.
- A `late final` variable is assigned at most once, so once a read of it has
  succeeded, its value can't change.

The exemption applies only to the write capturing added by this proposal (the
`writtenAfter(C) − Final` term below). It doesn't affect the write capturing
that flow analysis already does for a variable that is assigned inside a
closure in which it isn't declared. Such a variable is write captured in the
enclosing function after that closure, and on entry to every closure (because
it's in `writeCapturedAnywhere`), even if it's in `Final`. _It would be sound to
exempt such variables too, but this proposal doesn't; see [Exempting finals
from the existing write
capturing](#exempting-finals-from-the-existing-write-capturing)._

### Full variant (fixes [language#4778][] and [language#4779][])

On entry to a closure `C`, flow analysis write captures every variable in
`writtenAfter(C) − Final`, in addition to the variables that are write captured
today. That is, the flow model on entry to `C` is:

```
conservativeJoin(M, writtenAfter(C) ∪ writeCapturedAnywhere,
    writeCapturedAnywhere ∪ (writtenAfter(C) − Final))
```

where `M` is the flow model in the enclosing function at the point where `C`
appears (with the variables assigned in `C` write captured), and
`writtenAfter(C)` is the set of variables declared outside of `C` that are
assigned after the creation point of `C`, as defined in [closure promotion
order][].

In other words, a non-final variable can be promoted inside a closure only if
it is never assigned after the closure is created. This is sound regardless of
how the enclosing function executes relative to the closure, because any
assignment that could execute while the closure is executing must be after the
closure's creation point.

Under shared-memory multithreading, this relies on the implementation
guaranteeing that assignments that execute before a closure is created are
visible to the closure, even if the closure executes on another thread. See
the "Multithreading" section of [closure creation order][].

### Narrow variant (fixes [language#4779][] only)

The narrow variant write captures only those variables in `writtenAfter(C) −
Final` that might be assigned after the enclosing function resumes from a
suspension that follows the creation of `C`. That is, the flow model on entry
to `C` is:

```
conservativeJoin(M, writtenAfter(C) ∪ writeCapturedAnywhere,
    writeCapturedAnywhere ∪ resumableWrittenAfter(C))
```

where:

- A *suspension point* is the end of an `await` expression, or the end of a
  `yield` or `yield*` statement. An `await for` loop `L` (either a statement
  or a collection element) is treated as having one suspension point at the
  beginning of each iteration (before the implicit write to the loop variable,
  if any, and contained by `L`), and another immediately after `L`. _An
  `await for` loop suspends before each iteration, and before the loop exits.
  A suspension point follows the operand of the `await` or `yield`, so
  closures created and writes performed by the operand precede it._
- `resumableAfter(C, v)` is true if and only if there is a suspension point `s`
  such that:
  - `s` is in the body of `F`, where `F` is the function whose body or formal
    parameter list declares `v`, and `s` is not inside any closure nested
    within `F`;
  - `s` is after the creation point of `C` with respect to `v`; and
  - some write to `v` is after `s`, in the sense defined in
    [closure creation order][].

  A suspension point `s` is *after* a program point `P` with respect to a
  variable `v` if either of the following holds:

  - `s` follows `P` in the analysis order, unless there is an exclusive group
    `G` with an arm `A` such that `P` is inside `A`, and `s` is inside `G` but
    not inside `A`.
  - There is a loop that contains both `P` and `s`, but does not contain the
    declaration of `v`.

  _This mirrors the definition of a write being after a program point in
  [closure creation order][], and uses the same analysis order (including the
  treatment of deferred function literal arguments) and exclusive groups._
- `resumableWrittenAfter(C)` is the set of variables `v` in
  `writtenAfter(C) − Final` for which `resumableAfter(C, v)` is true.

The hazard requires the sequence "`C` is created; `F` suspends; `F` is resumed
while `C` is executing; `F` assigns to `v`". `resumableAfter(C, v)` holds
whenever that sequence is possible.

Only `F`'s own suspension points need to be considered. If `v` is assigned
inside any closure nested within `F`, then `v` is in `writeCapturedAnywhere`,
so it is write captured anyway. So all the remaining assignments to `v` are in
`F`'s own body, and they can only execute while `C` is executing if `F` is
resumed.

Note that a synchronous function, or an `async` function with no `await`
expressions or `await for` loops, has no suspension points, so the narrow
variant write captures nothing extra in such functions.

### Relationship between the variants

The set of variables write captured by the full variant is a superset of the
set write captured by the narrow variant. So the full variant fixes
[language#4779][] too. If shared-memory multithreading doesn't ship, the narrow
variant alone is enough to fix the existing soundness bug.

### What write capture affects

Write capturing a variable `v` inside `C` prevents all forms of promotion of
`v` inside `C`, so it affects:

- Promotion of `v` itself, for example by `v != null` or `v is T`.
- Promotion of private fields rooted at `v`, for example `v._f != null`.
- Promotion of `v` when it's used as the scrutinee of a pattern, for example
  `if (v case int())` or `switch (v) { case int(): ... }`. _Variables bound by
  the pattern can still be promoted._
- Promotion inside `late` initializers, which are closures.

## Examples

In each of these examples, `register` stores its argument somewhere so that it
can be invoked later, and `doStuff` is a function whose behavior is unknown.

### Write after the closure, no suspension

```dart
void f(int? i) {
  register(() {
    if (i != null) doStuff(i + 1); // (1)
  });
  i = null;
}
```

- **Full variant:** error at (1), because `i` is assigned after the closure is
  created, so it's write captured.
- **Narrow variant:** OK, because `f` has no suspension points. Without
  shared-memory multithreading, `f` can't execute while the closure is
  executing.

### Write after a suspension

```dart
Future<void> f(int? i, Future<void> ready) async {
  register(() {
    if (i != null) doStuff(i + 1); // (1)
  });
  await ready;
  i = null;
}
```

- **Both variants:** error at (1). `f` might be resumed while the closure is
  executing (for example, if `ready` is the future of a sync completer that
  `doStuff` completes), and then assign `null` to `i`.

### Write before a suspension

```dart
Future<void> f(int? i, Future<void> ready) async {
  register(() {
    if (i != null) doStuff(i + 1); // (1)
  });
  i = null;
  await ready;
}
```

- **Full variant:** error at (1).
- **Narrow variant:** OK, because the only assignment to `i` after the closure
  is created precedes the only suspension point. _If this code were inside a
  loop that didn't contain the declaration of `i`, the assignment would be
  after the suspension point, by the loop rule, so `i` would be write
  captured._

### Write before the closure

```dart
Future<void> f(int? i, Future<void> ready) async {
  i ??= 0;
  register(() => doStuff(i + 1)); // OK
  await ready;
}
```

- **Both variants:** OK. `i` is never assigned after the closure is created, so
  it's neither demoted nor write captured.

### `late final` variables

```dart
void f() {
  late final int? i;
  register(() {
    if (i != null) doStuff(i + 1); // OK
  });
  i = compute();
}
```

- **Both variants:** OK. Because `i` is assigned after the closure is created,
  it is in `writtenAfter(C)`. As a result, it isn't considered definitely
  unassigned inside the closure, and reading it there isn't an error.
  Additionally, `i` is in `Final`, which means it isn't write captured, and the
  null check can promote it. Once the closure has read `i` successfully, `i`
  can't change.

### Private fields, patterns, and cascades

```dart
class Box {
  final int? _value;
  Box(this._value);
}

void f(Box b, Box other) {
  register(() {
    if (b._value != null) doStuff(b._value + 1); // (1)
    if (b case Box(_value: var v?)) doStuff(v + 1); // (2)
    b.._value!.abs().._value.abs(); // (3)
  });
  b = other;
}
```

- **Full variant:** error at (1), because `b` is write captured, so `b._value`
  can't be promoted. (2) and (3) are OK. In (2), `v` is a fresh variable bound
  by the pattern. In (3), the cascade target is evaluated only once, so the
  promotion of `_value` by `!` in the first cascade section still applies in
  the second, even though `b` is write captured.
- **Narrow variant:** OK, because `f` has no suspension points.

## Soundness

### Full variant

Inside a closure `C`, a promotion of a variable `v` declared outside of `C`
can be invalidated only by an assignment to `v` that executes after the
promotion is established, while `C` is executing. Such an assignment is
either inside some closure, in which case `v` is in `writeCapturedAnywhere`,
or in the enclosing function, after `C` was created, in which case `v` is in
`writtenAfter(C)`. Either way, `v` is write captured, unless `v` is in `Final`,
in which case it can't be assigned after a successful read. Promotions that
are in effect on entry to `C` are covered by the soundness argument in
[closure creation order][].

### Narrow variant

Without shared-memory multithreading, the enclosing function `F` that declares
`v` can only execute while `C` is executing if either `C` suspends (in which
case the promotions are discarded, as described in [flow-analysis.md][]), or
`F` is resumed from one of its own suspension points. In the latter case, `F`
must have suspended after `C` was created, so any assignment to `v` that
executes after `F` is resumed is after a suspension point that is after the
creation point of `C`, so `resumableAfter(C, v)` is true, and `v` is write
captured (unless it is in `Final`).

_This assumes the SDK discards promotions when a closure suspends at an `await
for` loop (see [sdk#64466][])._

[sdk#64466]: https://github.com/dart-lang/sdk/issues/64466

## Impact

These changes cause new errors in code that relies on promotions that are
unsound (or would be unsound under shared-memory multithreading). So they are
language versioned: they apply only to libraries that have the feature enabled.

The following table shows the number of places in Google's internal codebase
where an existing promotion inside a closure would be lost, and a fix (such as
`!` or a cast) would be needed:

| Rule | Sites |
|---|---:|
| Full variant, without [closure creation order][] | 386 (269 variables, 224 files) |
| Full variant, with [closure creation order][] | 34 |
| Option A (see below), without [closure creation order][] | 205 |
| Option B (see below), without [closure creation order][] | 108 |
| Narrow variant, with [closure creation order][] | 7 |

All 7 sites affected by the narrow variant were checked by hand, and all are
real hazards: the closure is created, then the enclosing function awaits, then
the enclosing function assigns to the variable. All 7 are in `async`
functions. The 34 sites affected by the full variant include these 7.

## Migration

An analyzer lint, `closure_promotion_of_outer_mutated_variable` (in progress;
see [CL 556903][lint-cl]), reports each promotion inside a closure that would
be lost under the full variant, and a quick fix inserts a `!` or a cast. In the
corpus above, the lint and quick fix found and fixed all 386 sites.

[lint-cl]: https://dart-review.googlesource.com/c/sdk/+/556903

## Alternatives considered

### Option A: based on the kind of function

Write capture every non-final variable that is read inside a closure and
assigned somewhere other than its declaration, if the function declaring the
variable is `sync*`, `async`, or `async*`. This is simpler than the narrow
variant, but loses many more promotions: without [closure creation order][], it
affects 205 sites, versus 108 for option B.

### Option B: writes after a suspension

Like option A, but only if at least one of the assignments can execute after a
suspension point. The narrow variant refines this by requiring that the
suspension point be after the creation of the closure, and by using the
definition of "after" from [closure creation order][].

### Treat everything after a suspension as a closure

[It was suggested][suspend-as-closure] that code following a suspension point
be treated as if it were a separate closure. This fixes [language#4779][], but
also prevents promotions that are, and always have been, sound, like:

```dart
x = await fetch();
if (x != null) {
  use(x);
}
```

[suspend-as-closure]: https://github.com/dart-lang/language/issues/4779#issuecomment-5876471415

### Write type refinement

A variable need not be write captured if every assignment to it after the
closure is created assigns a value whose type is a subtype of the type the
variable is promoted to inside the closure. For example, if every such
assignment assigns a non-nullable value, a null check inside the closure would
remain valid. In the corpus above, this would rescue 3 of the 6 variables
involved in the narrow variant's 7 sites. This is probably not worth the extra
complexity.

## Future work

### A "why not promoted" reason

Today, when a variable can't be promoted because it is write captured, flow
analysis doesn't report any "why not promoted" reason, so the user gets no
explanation. This will be more confusing for the variables write captured by
this proposal, since they aren't assigned in any closure. A new "why not
promoted" reason could be added, with a message such as "`x` is assigned
outside this closure, after the closure is created", and a link to
documentation explaining why such promotions are unsound.

### Exempting finals from the existing write capturing

The argument in [Finals](#finals) also shows that it would be sound to stop
write capturing variables in `Final` that are assigned inside a closure in
which they aren't declared, as flow analysis does today. In practice, this
only affects `late final` variables declared without an initializer, because
it's a compile-time error to assign to a non-`late` `final` variable inside a
closure in which it isn't declared, and it's a compile-time error to assign to
a `late final` variable that has an initializer. Once a promotion of such a
variable has been established, either by a successful read or by a successful
assignment, the variable has been assigned, and any further assignment throws,
so the promotion remains valid everywhere.

This proposal doesn't make that change, for three reasons:

- It would allow more promotions rather than fewer, so it isn't needed to fix
  [language#4778][] or [language#4779][].
- It's unlikely to matter much in practice, because it only affects `late
  final` variables that are assigned inside a closure and promoted somewhere,
  which is an unusual combination.
- Its effects wouldn't be limited to closures: it would also change
  `writeCapturedIn`, which is used by the rules for loops, `switch`
  statements, and `try` statements. So it would need to be evaluated
  separately.

It could be made later, as a separate, language-versioned change.
