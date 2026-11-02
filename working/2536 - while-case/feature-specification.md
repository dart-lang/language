# While-Case Statements

Author: Sam Rawlins

Status: Proposed

Version: 1.0

Specification for issue
[#2536](https://github.com/dart-lang/language/issues/2536), extending `while`
statements with `case` pattern matching clauses.

## Motivation

Dart 3.0 introduced [pattern matching][] including the `if-case` statement
(`if (expression case guardedPattern) ...`), which matches and destructures a
single value against a refutable pattern.

[pattern matching]: https://github.com/dart-lang/language/blob/main/accepted/3.0/patterns/feature-specification.md

However, we omitted the corresponding loop construct, `while-case`. Loops that
repeatedly pull or traverse values until a pattern stops matching are common:

* Draining queues, iterators, tokenizers, or nullable producer functions:

  ```dart
  while (queue.removeFirstOrNull() case var item?) {
    process(item);
  }
  ```

* Walking linked or recursive data structures:

  ```dart
  while (node case Node(:var value, :var next)) {
    print(value);
    node = next;
  }
  ```

* Repeatedly matching structured state with an optional guard:

  ```dart
  while (lexer.peek() case Token(:var kind, :var lexeme)
      when kind != TokenKind.eof) {
    lexer.advance();
    emit(lexeme);
  }
  ```

Without `while-case`, users must write something more verbose, like an
unconditional `while (true)` loop containing a `break` in a similar `if-case`
statement:

```dart
while (true) {
  if (node case Node(:var value, :var next)) {
    print(value);
    node = next;
  } else {
    break;
  }
}
```

Or hoist a temporary variable into the enclosing scope and duplicate the
update expression before and inside the loop. Neither form expresses the loop's
termination condition directly in the `while` condition.

Other languages with `if`-pattern syntax (including Swift (`while case`), Rust
(`while let`)) provide the corresponding `while` form. Adding `while-case`
removes a point of surprise in Dart's pattern matching support.

### Non-goals

#### `do-while-case`

Extending `do statement while (expression);` with a `case` clause is
intentionally omitted. In a `do-while` loop, the body executes *before* the
condition is first evaluated. Any pattern variables declared in the `while`
condition could not be bound on the first iteration of the body, so they could
not be in scope (with initialized values) in the body at all.

Alternately, we could allow one of the following:

* Allow `do-while-case` with variable binding in the `case` clause, but those
  variables are not in scope in the `do-while` body. This perhaps is the least
  surprising alternative, but it is still exceptional; the variables are not
  bound in any context except the `when` component of the clause. This may
  prove useful enough to justify the feature.

* Allow `do-while-case`, but without any variable binding. The `do-while`
  condition can have a `case` clause _which does not bind any variables._ This
  also seems surprising and complicated.

* Allow `do-while-case`, and initialize pattern-bound variables to `null` on
  the first iteration; this seems awkward, surprising, and complicated.

#### case expression in C-style for loops

Extending `for (init; condition; updaters) body` is also intentionally omitted.
This would look like `for (init; e case p; updaters) body`.

## Syntax

We replace the existing `whileStatement` grammar rule with:

```bnf
whileStatement ::= whileCondition statement
whileCondition ::= 'while' '(' expression ( 'case' guardedPattern )? ')'
```

Where `guardedPattern` is defined as in the
[Patterns specification][pattern matching]:

```bnf
guardedPattern ::= pattern ( 'when' expression )?
```

When `whileCondition` has no `case guardedPattern`, the statement is a standard
Boolean `while` statement and its static and runtime semantics are unchanged.
Hereafter, a `whileStatement` that contains `case guardedPattern` is referred to
as a **while-case statement**.

## Static semantics

### Pattern context

Because `whileCondition` contains a `guardedPattern`, the `pattern` in a
while-case statement and all of its subpatterns occur in a **matching context**
(refutable context), just as in `if-case` and `switch` cases.

Any pattern form permitted in a matching context is allowed, subject to the
existing compile-time rules for matching contexts in the Patterns specification.

### Type inference and type checking

Given a while-case statement of the form `while (e case p) s` or
`while (e case p when g) s`:

1. **Scrutinee expression (`e`)**: Analyze `e` with unknown context type schema
   `_`.
   * As in `if-case` and `switch`, the pattern's context type schema is *not*
     used for downwards inference on `e`, and no implicit coercions or casts
     from `dynamic` are inserted on `e`.
   * Unlike a Boolean `while` statement, `e` is *not* required to have type
     `bool` (and may have any static type, matching existing `if-case`
     behavior).
   * Let `M` be the static type of `e`.

2.  **Pattern (`p`)**: Type check `p` and infer types for any unannotated
    pattern variables declared in `p` using `M` as the matched value type,
    following the existing matching-context type inference and checking rules
    in the Patterns specification (including variable consistency rules across
    logical-or branches).

3.  **Guard (`g`)**: If a `when g` clause is present, analyze `g` with context
    type schema `bool`. It is a **compile-time error** if the static type of `g`
    is not assignable to `bool`.

4.  **Body (`s`)**: Analyze `s` as a statement.

### Scoping and mutability

Scoping closely mirrors `if-case` combined with per-iteration loop bindings:

1. The scrutinee expression `e` is resolved in the scope enclosing the
   while-case statement. Variables declared by `p` are **not** in scope in `e`.

   *Even though subsequent iterations re-evaluate `e` after `s` has run, `e` is
   also evaluated before the first match occurs, so pattern variables from a
   prior iteration cannot be referenced in `e`.*

2. The `guardedPattern` introduces a new **case scope** whose enclosing scope
   is the scope surrounding the while-case statement. Every variable subpattern
   in `p` declares a variable in this case scope (with joint variable handling
   for logical-or patterns identical to `if-case`).

   * As in `if-case` and `switch`, variables defined in the pattern are in
     scope across the entire pattern, so it is a compile-time error for a
     relational or constant subpattern inside `p` to refer to a name bound
     anywhere in `p` before it is initialized (rather than resolving to an
     identically named declaration in an enclosing scope).

3. If a `when g` guard clause is present:
   * `g` is resolved in the case scope, after all variables declared by `p`
     have been initialized.
   * It is a **compile-time error** for `g` to contain an assignment to any
     variable declared in `p` (including inside function literals or local
     functions nested within `g`), identical to guards in `if-case` and
     `switch`.

4. The body `s` is resolved in a new local statement scope whose enclosing
   scope is the case scope.
   * Variables declared in `p` without `final` are mutable and may be assigned
     inside `s`.
   * Because `s` has its own inner scope enclosed by the case scope, a body like
     `{ var x = ...; }` or `var x = ...;` declares a local variable that
     shadows a pattern variable `x` rather than colliding with it in the same
     scope (identical to the then-branch of an `if-case` statement).

5. **Per-iteration bindings**: Each evaluation of the loop condition creates a
   fresh instance of the case scope and fresh bindings for the pattern
   variables declared in `p`:
   * A closure created in `g` and a closure created in `s` during the *same*
     iteration capture the *same* variable binding (so mutations to that
     variable in `s` are observed by the closure created in `g` on that
     iteration).
   * Closures created on *different* iterations capture *distinct* variable
     bindings.

### Flow analysis

Flow analysis treats `while (e case p when g) s` as a combination of standard
`while` loop entry/exit handling and `if-case` pattern/guard handling:

1. **Loop entry (`conditionBegin`)**: Before analyzing `e`, flow analysis
   performs the standard loop-entry split and conservative join over all
   variables assigned or write-captured anywhere within `e`, `p`, `g`, or `s`
   (demoting any outer promotions on those variables that could be invalidated
   by a subsequent iteration).

2. **Scrutinee and pattern matching**: `e` is analyzed, and `p` is analyzed
   against `e` as the scrutinee:
   * If `e` refers to a promotable variable or property, matching `p` may
     promote `e` in the matched flow state (used at entry to `g` and `s`) and
     may promote `e` via refutation in the unmatched flow state (for example,
     matching against the constant pattern `null` promotes a nullable local
     variable to its non-nullable type along the unmatched path).

3. **Guard (`g`)**: If `g` is present, it is analyzed starting from the
   pattern-matched flow state.
   * The flow state entering `s` is the `ifTrue` flow state of `g` (or the
     pattern-matched flow state if no guard is present).
   * The loop's condition-exit (`unmatched`) flow state is the join of the
     pattern-unmatched flow state and the `ifFalse` flow state of `g` (or
     simply the pattern-unmatched flow state if no guard is present).

4. **Body (`s`) and `continue` / `break`**: `s` is analyzed as a loop body
   whose break target is the while-case statement and whose continue target is
   the loop header:
   *   Reachable `break` statements targeting this while-case statement record
       their flow states into the loop's break list.
   *   Normal completion of `s` and reachable `continue` statements targeting
       this while-case statement loop back to the condition (their write effects
       were already accounted for conservatively in step 1).

5. **Loop exit (`end`)**: The flow state immediately following the while-case
   statement is the join of the condition-exit (`unmatched`) flow state from
   step 3 and all break flow states recorded in step 4.

   *Notable consequences of these rules:*

   * *Post-loop promotion by refutation*: In
     `while (x case null) { x = next(); }`, if `x` is a promotable local
     variable of type `T?` and the body contains no `break`, `x` is promoted to
     `T` after the loop (because the only way to exit the loop is for
     `x case null` to fail to match).
   * *Infinite loops and reachability*: If `p` is unconditionally matching (for
     example `while (next() case var x)` or `while (e case _)`), there is no
     guard (or the guard's `ifFalse` state is unreachable, such as
     `when true`), and there is no reachable `break` targeting the loop, then
     the flow state after the while-case statement is **unreachable**. Code
     following the loop receives a dead-code warning, and an enclosing function
     with a non-nullable return type is not required to have a `return` after
     the loop.

### Exhaustiveness and warnings

* Like `if-case`, a while-case statement is **not** required to be exhaustive,
  even when the matched value type is an always-exhaustive type (such as `bool`
  or a `sealed` class). *Indeed, a loop whose pattern might not match is the
  primary use case so that the loop terminates.*
* All existing static warnings for patterns and statements apply directly to
  while-case statements, including:
  * Warning when a null-check (`p?`) or null-assert (`p!`) pattern is matched
    against a non-nullable type, or against `Null`.
  * Warning when a cast pattern (`p as T`) or object/variable pattern check is
    unnecessary or can never match as applicable under standard pattern
    warnings.
  * Warning when the right operand of a logical-or pattern (`p1 || p2`) is
    unreachable because `p1` always matches.
  * Dead-code warning on `s` if the entry to `s` is unreachable (for example,
    `while (e case _ when false) { ... }`), and dead-code warning on statements
    following the while-case statement if its exit is unreachable.

## Runtime semantics

Executing a while-case statement `while (e case p) s` or
`while (e case p when g) s` proceeds as follows:

1. Evaluate `e` to a value `v`.

2. Create a fresh case scope for this iteration and match `p` against `v` in
   that scope. This includes the invocation cache, which is not to be shared
   across iterations of the loop.

3. If the match fails, execution of the while-case statement completes
   normally.

4. Otherwise, the match succeeded and bound any pattern variables declared in
   `p` within this iteration's case scope:

   1. If a guard clause `when g` is present:

      1. Evaluate `g` in this iteration's case scope to a value `b`. If `b` is
         not a `bool`, throw a runtime `TypeError`. *This can happen when the
         static type of `g` is `dynamic`.*

      2. If `b` is `false`, execution of the while-case statement completes
         normally.

5. Execute `s` in a fresh local scope enclosed by this iteration's case scope,
   with this while-case statement as the target for unlabeled `break` and
   `continue` statements (and for labeled `break`/`continue` statements whose
   label labels this while-case statement):

   * If `s` completes normally, or completes via a `continue` targeting this
     while-case statement, restart execution of the while-case statement from
     step 1.

   * If `s` completes via a `break` targeting this while-case statement,
     execution of the while-case statement completes normally.

   * Otherwise (`s` completes via `return`, throwing an exception, or a
     `break`/`continue` targeting an enclosing statement), execution of the
     while-case statement completes with that same abrupt completion.

### Desugaring equivalence

A while-case statement (optionally preceded by labels `L_1: ... L_k:`):

```dart
L_1: ... L_k:
while (e case p when g) s
```

(omitting `when g` if absent) has identical static reachability, per-iteration
variable capture semantics, and runtime behavior to:

```dart
L_break:
while (true) {
  if (e case p when g) {
    L_continue: {
      s'
    }
  } else {
    break L_break;
  }
}
```

where `L_break` and `L_continue` are fresh labels, and `s'` is obtained from `s`
by replacing every `break` targeting the original `while` statement (whether
unlabeled or referencing one of `L_1, ..., L_k`) with `break L_break;` and every
`continue` targeting the original `while` statement (whether unlabeled or
referencing one of `L_1, ..., L_k`) with `continue L_continue;`.

## Changelog

### 1.0

*   Initial specification for `while-case` statements.
