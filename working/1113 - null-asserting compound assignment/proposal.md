# Dart Null-Asserting Composite Assignment

Author: lrn@google.com<br>Version: 0.1

## Background and Motivation

With the current Null Safety behavior, a nullable variable like `int? x;` cannot be incremented as easily
as a non-nullable variable, even when you know that it currently contains a non-null value.
We have `++x` and `x += 1` as easy composite operations on non-nullable types,
but for the nullable type, when you know it's not null, the only option is `x = x! + 1` 
because we need to insert the `!` in the middle of the expression that `++x` or `x += 1` expands to.

This document proposes a new syntax, `x! += 1`, `++x!` or `x!++`, 
which is a short-hand for an expanded version like the one above, 
but where the *read* of the value is guarded with a non-`null` asserting check.

### Composite operator specification 

Currently we have a multiplicity of rules for various assignable expressions/left-hand sides (LHSs):

```dart
id
e1.id
e1?.id
e1[e2]
e1?[e2]
super.id
super[e2]
ClassName.id  
```

(and we'd probably have `prefix.id` and `prefix.ClassName.id` if we didn't still pretend prefixes were objects) .

Then we have operations on those LHSs:

```dart
lhs = expr
lhs op= expr
lhs ??= expr
lhs ||= expr // Not yet.
lhs &&= expr // Not yet.
lhs++
++lhs
```

The specification has no abstraction over LHSs, so it contains one case 
per combination of operation and LHS shape (cf. [#228](https://github.com/dart-lang/language/issues/228)).

This proposal introduces (three) more operations, since the new behavior applies equally to all existing LHSs.

## Proposal

We introduce new operations on LHSs of the form:

```dart
lhs! op= expr
lhs!++
++lhs!
```

These forms are currently not valid expressions because if `lhs` is an assignable expression,
`lhs!` is not, and `op=` and `++` only applies to assignable expressions.

### Grammar

Grammatically we need to allow the new syntax. This is done by modifying the following grammar productions: 

```latex
<assignmentOperator> ::= `='
  \alt <compoundAssignmentOperator>
  
<unaryExpression> ::= …
  \alt <incrementOperator> <assignableExpression>

<postfixOperator> ::= <incrementOperator>  
```

to

```latex
<assignmentOperator> ::= `='
  \alt `!'? <compoundAssignmentOperator>
  
<unaryExpression> ::= …
  \alt <incrementOperator> <assignableExpression> `!'?

<postfixOperator> ::= `!'? <incrementOperator>  
```

This allows one optional `!` exactly where it affects a composite operation, and nowhere else.

This grammar is not ambiguous. The `++x!` looks like it could be a problem,
but because prefix-`++` only applies to an `<assignableExpression>`, a
ny existing valid expression starting with `++x!` would need to be followed 
by a selector making it into an assignable expression, like `++x!.foo`,
and because postfix selectors bind stronger than prefix operators,
there is no valid parse which accepts `++x!` as an unary expression
when followed by another selector like`.foo`.

### Semantics

For each LHS, the semantics of an expression of the form 
``lhs `!' op= expr`` is is specified in almost the same way
as `lhs op= expr` except that:

* After *reading* `lhs`, the operation throws if the value is `null` in the same way as `lhs!` would.
* The static analysis uses the **NON_NULL** type of the static type of `lhs` for the operator lookup.

For each LHS, an expression of the form ``lhs `!' incrementOp`` is specified
in almost the same ways as `lhs incrementOp`, except that:

* After *reading* `lhs`, the operation throws if the value is `null` in the same way as `lhs!`.
* The static analysis uses the **NON_NULL** type of the static type of `lhs` for the `+` operator lookup.

For each LHS, an expression of the form ``incrementOp lhs `!'`` is specified as behaving the same as `lhs! += 1 `.

### Example

The <code>*e*<sub>1</sub>.*v*! *op*= *e*<sub>2</sub></code> case would be specified as:

```latex
\LMHash{}%
\Case{\code{$e_1$.$v$! $op$= $e_2$}}
Consider a compound assignment $a$ of the form \code{$e_1$.$v$! $op$= $e_2$}.
Let $x$ be a fresh variable whose static type is the static type of $e_1$.
Except for errors inside $e_1$ and references to the name $x$,
exactly the same compile-time errors that would be caused by
\code{$x$.$v$ = $x$.$v$! $op$ $e_2$}
are also generated in the case of $a$.
The static type of $a$ is the static type of \code{$e_1$.$v$! $op$ $e_2$}.
```

That is, almost exactly the same as for
<code>*e*<sub>1</sub>.*v* *op*= *e*<sub>2</sub></code>,
just with a `!`s inserted on all reads of the LHS.

## Possible extensions

### Null checking compound operators

This proposal's `!` modifier handles the case where we *know* that the LHS is non-null.
We could also introduce a version which checks whether the LHS is `null`,
and does nothing if it is, similar to the distinction between `?.` and `!.`.

We already have `x ??= y` which does something if `x` is null.
This one would do something if `x` is non-`null` instead.
Let's go with one `?` as strawman marker syntax:

```dart
e.x ?+= 2
```

would add 2 to `e.x` if it's non-`null`, and do nothing (and evaluate to `null`) if `e.x` is `null`.

The `?` could be inserted in the same places that this proposal inserts `!`.
That could be an potential grammar ambiguity for prefix increments, say `--x?[1]`,
but for the same reasons as for `!`, it is only going to be parsable in one way.
Unlike `!` it can also conflict with the conditional expression syntax.
If the `?` matches a later `:`, we prefer to parse as a conditional expression,
like we already do for `{x?[y]:z}`.
