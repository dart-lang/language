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

To avoid redundant repetition, this feature will allow you to omit the
argument name if it's the same name as the expression providing the value.

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

Color colorWithAlpha(Color color, int newAlpha) {
  var (:red, :green, :blue, alpha: _) = color;
  return (red: red, green: green, blue: blue, alpha: newAlpha);
}
```
which this feature will allow to be written as:
```dart
Color colorWithAlpha(Color color, int alpha) {
  var (:red, :green, :blue, alpha: _) = color;
  return (:red, :green, :blue, :alpha);
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
expression is not a _single identifier expression_, as defined below.

An expression `e` is a _single identifier expression with identifier *I*_ if
and only if it is defined as such by one of the following rules,
where `s` is, inductively, a single identifier expression with identifier *I*:

*   If `e` is a `<primary>` expression which is an `<identifier>`,
    it is a single identifier expression with that `<identifier>` as identifier.
*   `s!`: If `e` is a `<primary> <selector>*` production where `<selector>*`
    is the single selector `` `!' ``, and `<primary>` is `s`,
    then `e` is a single identifier expression with identifier *I*.
*   `s as T`: If `e` is a `<relationalExpression>` of the form
    `<bitwiseOrExpression> <typeCast>` and the `<bitwiseOrExpression>` is `s`
    then `e` is a single identifier expression with identifier *I*.
*   `(s)`: If `e` is a `<primary>` production of the form
    `` `(' <expression> `)' `` and the `<expression>` is `s`, then `e` is a single identifier expression with the same identifier as
    the `<expression>`.

_In short, an identifier expression is a single identifier expression,
and you can then wrap it in null-assertions, parentheses, or casts,
and it will still be a single identifier expression with the same identifier. The value if `id` is the same as the value of
`(id! as List<num>)` &mdash; if it has a value._
_The resulting expression still evaluates to the value of the original
identifier, if it doesn't throw first._

The _name of a `<namedExpression>`_ is then:
* If the named expression has a leading identifier before the colon,
  then that identifier.
* Otherwise the following expression must be a single identifier expression
  with an identifier *I*, and then the name of the named expression is *I*.

The name of a `<namedArgument>` or a named `<recordField>` is the name of
its `<namedExpression>`.

Where the language specification refers to a named argument's name,
it now uses this definition of the name of a `<namedArgument>`.

Where the Record specification for a record literal refers to a field name,
it now uses this definition.

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
Also, that identifier is always the *only* identifier of the expression,
and can only be preceded by `(`s.

The identifier expression can be wrapped in casts `!` or `as T`
or in parentheses, but none of those operations change the value
of the expression away from the value of evaluating the identifier,
only, potentially, whether it evaluates to a value at all.

Those are properties chosen to make it easier to read and understand
a missing name, but nothing is technically necessary,
we could allow any expression where we can, somehow, derive a significant
identifier.
The limitation to the name being the next non-`(` token should hopefully make it
*very easy* to find the name.

Possible additions, initially or in the future, could include the following
expression forms.

### Cascades

A cascade expression like `e..selector` or `e?..selector` also satisfies
that the value of the expression is the value of the leading sub-expression.
It could be made a single identifier expression, and since cascades are
often used in argument position, that is exactly where we would *want*
to use the shorter syntax.

The rule for single identifier expressions would add another rule:

> *   `s..cascade`:
>    *   If `e` a `<cascade>` of the form ``<cascade> `..' <cascadeSection>``
>        and the `<cascade>` is `s`,
>        then `e` is a single identifier expression with identifier *I*.
>    *   If `e` a `<cascade>` of the form
>        ``<conditionalExpression> (`?..' | `..') <cascadeSection>``
>        and the `<conditionalExpression>` is `s`,
>        then `e` is a single identifier expression with identifier *I*.

The other cases do not contain any other identifier than the one that
provides the value of the expression. A cascade could have any expression
after the `..`, so it would be even more important for readability that
the reader knows to look at the very next identifier for the name.

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

Also, if we *ever* want to allow a prefixed identifier, making it possible
to abbreviate `foo(bar: source.bar)` to `foo(:source.bar)`, then it's confusing
that the very syntactically similar `(:a.b)`and  `(:a..b)` mean
`(b: a.b)` and `(a:..b)` respectively. Not surprising since the *value* of the
expression comes from something named `b` in one case and something names `a`
in the other, but does make it easier to lose track of which name goes where.
_(With `(:a.b)` meaning `(b: a.b)`, it's more like the *last* identifier is
the one that provides the name, and a cascade would break that, leaving the
reader with no easy rule for where to find the significant identifier.)_

Another example simplified from actual code:
```dart
  static Uri addQueryParameters(
      Uri uri,
      Map<String, String> queryParameters,
  ) => uri.replace(:queryParameters..addAll(uri.queryParameters));
```

And from a Flutter program using a null-aware cascade:
```dart
        child: TextField(
          :controller?..text = initialValue,
          maxLines: 5,
          :onChanged,
        ),
```

### Increments

Expressions of the form `++id`/`--id` or `id++`/`id--` also evaluate to
the value of `id`, either as it was when read for `id++`, or what it is
now for `++id`, and the `id` is the first identifier of the expression.

As such, they are within the design parameters that are otherwise used,
and could be allowed. _They'd only be valid directly on the identifier,
not after wrapping with `!`, `as T` or `(...)`._

Increments are also often used in argument position, so it would fit
in that way too.

I'd expect it to be less common that a *counter* has the same
name as the *value*. Passing the value of a mutable variable as
an argument means that the are less likely to have the *same meaning*,
even if they have the same value.

For now, it's not included. It can easily be added if an real need
is discovered.

### Assignments

An expression of the form `id1 = id2` is an expression which has the same
value as the identifier, `id2`.
(We don't know for sure what assigning to `id1` means,
or if it can even be read, but we know that the value of the expression
is the value of evaluating `id2`.)

Assignments are not included because that identifier is not the next identifier
of the expression, and because it can easily be confusing which identifier
defines the name. (And more so for more steps, like `:foo = bar = baz`.)

It would be *more consistent* to use the identifier `id1`.
If assignment behaves *as it looks like it should*, then `id1` is a name for
the value of the expression. It is also the first identifier, which makes
it easy to find, and it would also open the door to `id += 2` &mdash;
to generalize `id++` &mdash; or to `id ??= 42`, where the latter makes good
sense in a parameter position.

The most generally useful choice would be that `id = e` and `id op= e`
would count as `id`, since the value of the expression is the (new) value
of `id`, and `id` is the first identifier of the expression.

Probably likely to be confusing.
The expression occurs in parameter or record-field position,
which means that there is *another* implicit assignment going on.

_If we also want to allow `:a.b` to be short for `b:a.b`, then allowing
assignment puts the significant identifier in the middle: `:e1.id = e2`,
which can make it hard to find.

### Property access

As alluded to above, we could allow `(:e.b)` to mean `(b: e.b)`,
using the name of a final selector to represent the value it
evaluates to.

That is consistent with using plain identifiers that refer to instance getters
inside the declaring context.
It would allow referring to identifiers imported with a prefix
or accessing an identifier from outside of its scope just as briefly
as inside its scope.

It would mean that the operative identifier is no longer the *first*
identifier of the expression. Rather, it would be the last one,
which conflicts with allowing cascades or assignments, that both
add something after the identifier. A `(:a.b..c.d)` or `(:a.b=c.d)` would
have the missing name somewhere in the middle of the expression,
and not necessarily easy to find.

### Future additions.

Extending the "single identifier expression" to more syntaxes is non-breaking.
It turns something that would be a compile-time error into something else.

That means that we can always add more cases later.
The initially proposed expressions are only the simplest of cases,
where there is only one identifier in the expression at all,
so no choice of it being the first or last identifier has been made.
(And increments are omitted because they are similar to assignments,
and it feels like half a feature to only handle increments by themselves.)

## Revision history

* 1.0: Initial version

