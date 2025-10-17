# Dart Implied Parameter/Record Field Names

Author: lrn@google.com<br>
Version: 1.0

## Pitch
Writing the same name twice is annoying. That happens often when forwarding
named arguments:
```dart
  var subscription = stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
```

To avoid redundant repetition, Dart will allow you to omit the
argument name if it's the same name as the value.

```dart
  var subscription = stream.listen(
    onData,
    :onError,
    :onDone,
    :cancelOnError,
  );
```

Same applies to record literal fields, where we have nice syntax
for destructuring, but not for re-creating:
```dart
typedef Color = ({int red, int green, int blue, int alpha});
extension on Color {
  Color withAlpha(int alpha) {
    var (:red, :green, :blue, alpha: _) = this;
    return (red: red, green: green, blue: blue, alpha: alpha);
  }
}
```
will become
```dart
extension on Color {
  Color withAlpha(int alpha) {
    var (:red, :green, :blue, alpha: _) = this;
    return (:red, :green, :blue, :alpha);
  }
}
```

## Specification

The current grammar for a named argument is:
```ebnf
<namedArgument> ::= <label> <expression>
```
The [current grammar](../../accepted/3.0/records/feature-specification.md#record-expressions) for a record literal field:
```ebnf
recordField  ::= (identifier ':' )? expression
```
So basically the same.

The new grammar is:
```ebnf
<namedArgument> ::= <namedExpression>

<recordField> ::= <namedExpression> | <expression>

<namedExpression> ::= <identifier>? `:' <expression>
```

This grammar change does not introduce any new ambiguities.
A named record field and a named argument can *only* occur
immediately after a `(` or a `,`, as the entire content until
a following `,` or `)`.
Starting with a `:` at that point is not currently possible.
(Even if we allow metadata annotations inside argument lists or record literals,
it's unambiguous whether those annotations includes a following identifier or
not.)

As a non-grammatical restriction, it's a **compile-time error**
if a `<namedExpression>` omits the leading`<identifier>`, and the following
expressions is not a _single identifier expression_, as defined below.

In short, an expression is a _single identifier expression_
which has a specific single _identifier_ if and only if
it is one of the following:
*   An identifier, with that identifier.
*   `s!`, `s as T`, `(s)`, `s..cascadeSection`/`s?..cascadeSection`
    where `s` is a single identifier expression,
    and then it has the same identifier as `s`.

More formally, An expression `e` is a single identifier expression with a certain identifier if and only if it is defined as such by the following:

*   If `e` is a `<primary>` expression which is an `<identifier>`,
    it is a single identifier expression with that `<identifier>` as identifier.
*   `s!`: If `e` is  a `<primary> <selector>*` production where `<selector>*`
    is the single `<selector>` `` `!' ``, and `<primary>` is
    a single identifier expression, then `e` is a single identifier expression
    with the same identifier as the `<primary>`,
*   `s as T`: If `e` is a `<relationalExpression>` of the form
    `<bitwiseOrExpression> <typeCast>` and the `<bitwiseOrExpression>`
    is a single identifier expression,
    then `e` is a single identifier expression with the same identifier as
    the `<bitwiseOrExpression>`.
*   `(s)`: If `e` is a `<primary>` production of the form
    `` `(' <expression> `)' `` and the `<expression>`
    is a single-identifier expression,
    then `e` is a single identifier expression with the same identifier as
    the `<expression>`.
*   `s..cascade`:
    *   If `e` a `<cascade>` of the form ``<cascade> `..' <cascadeSection>``
        and the `<cascade>` is a single identifier expression,
        then `e` is a single identifier expression with the same identifier as
        the `<cascade>`.
    *   If `e` a `<cascade>` of the form
        ``<conditionalExpression> (`?..' | `..') <cascadeSection>``
        and the `<conditionalExpression>` is a single identifier expression,
        then `e` is a single identifier expression with the same identifier as
        the `<conditionalExpression>`.

The _name of a named expression_ is then:
* If the named expression has a leading identifier, then that identifier.
* Otherwise the following expression must be a single identifier expression
  with an identifier *I*, and then the name of the named expression is *I*.

The name of a `<namedArgument>` or a named `<recordField>` is the name of
its `<namedExpression>`.


Where the language specification refers to a named argument's name,
it now uses this definition of the name of a `<namedArgument>`.

Where the Record specification for a record literal refers to a field name,
it now uses to this definition.

## Semantics

There are no changes to static or runtime semantics, other than extending the
notion of "name of a named argument" and "name of a field" to the name of the
single identifier expression following an unnamed `:`.

After that, there is no distinction between `(name: name,)` and `(: name,)`,
both syntaxes introduce a named argument or record field with name `name`
and expression `name`, and the semantics is only defined in terms of those
properties.


## Examples

From `sdk/lib/_http/http_impl.dart` (among many others):
```dart
  return _incoming.listen(
    onData,
    :onError,
    :onDone,
    :cancelOnError,
  );
```

From `pkg/_fe_analyzer_shared/lib/src/type_inference/type_analyzer.dart`:
```dart
    return new SwitchStatementTypeAnalysisResult(
      :hasDefault,
      :isExhaustive,
      :lastCaseTerminates,
      :requiresExhaustivenessValidation,
      :scrutineeType,
      :switchCaseCompletesNormallyErrors,
      :nonBooleanGuardErrors,
      :guardTypes,
    );
```

From `pkg/dds/lib/src/dap/isolate_manager.dart`:
```dart
  final uniqueBreakpointId = (:isolateId, :breakpointId);
```

## Migration

None.

## Implementation

Experiment flag name could be `implicit-names`.

## Tooling

Analysis server can suggest removing a redundant name before a `:`.

There should *probably* be a lint to report when an argument name is redundant.
Because if there isn't, someone will almost immediately ask for one.
Whether one likes omitting the name or not is a matter of taste, so it should
be an optional lint, not just a warning. It should be easy to have a fix.

A _rename operation_ may need to recognize if it changes a parameter
name or an identifier used as argument, and insert an argument name
if now necessary. That is:
*   If a name changes, then if any occurrences of that name is in
    single identifier position of an implicitly named argument,
    the old name must be inserted as explicit argument name.
*   If a named parameter name changes, then any invocation of the function
    which uses an implicitly named argument must have the new name
    inserted as explicit argument name.

A rename can also introduce new possibilities for removing argument names.
(It may be better to not do that automatically, and rely on the user fixing
the positions afterwards. Or only do it automatically if the lint is enabled.)

## Discussion

The definition of "single identifier expression" is the place this feature
can be tweaked.

It's currently restricted to expressions where the value of the expression
is always the value of evaluating a single identifier.
That identifier is always the *next* identifier, and the next non-`(` token.

The identifier expression can be wrapped in casts `!` or `as T`, in parentheses,
or can be pre-used/modified using cascade invocations, but none of those
operations change the value from evaluating the identifier, only, potentially,
whether it evaluates to a value at all.

### Cascades

The cascade sections are the most syntactically intrusive. They can contain
any other expression, including other identifiers.
However, the places where cascades are used are often in argument position.

Examples of uses that could be made shorter (from `package:csslib`):
```dart
  stylesheet = parseCss(input, errors: errors..clear());
```
which would become:
```dart
  stylesheet = parseCss(input, :errors..clear());
```

An example from Flutter:
```dart
 TextSpan(text: offScreenText, recognizer: recognizer..onTap = () {})
```
which would become:
```dart
 TextSpan(text: offScreenText, :recognizer..onTap = () {})
```

It is the use that has the biggest risk of being confusing to read,
but you can always write the identifier if you prefer it.

### Assignments

An expression of the form `id1 = id2` is an expression which has the same
value as a single identifier, `id2`.
(We don't know what assigning to `id1` means, or if it can even be read,
but the value of the expression is the value of evaluating `id2`.)

It's not included because that identifier is not the next identifier
of the expression, and because it can easily be confusing which identifier
defines the name. (And more so for more steps, like `:foo = bar = baz`.)


### Future additions.

It's possible to extend the "single identifier expression" definition
to more expressions in the future without breaking any code existing
at that point.

## Revision history

* 1.0: Initial version

