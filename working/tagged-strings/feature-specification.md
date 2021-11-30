# Tagged Strings

Authors: Bob Nystrom

Status: **Draft**

Summary: Use Dart's string literal syntax to create values of user-defined types
by allowing an identifier before a string to identify a "tag processor" that
controls how the string literal and its interpolated expressions are evaluted.

See also: [#1479][], [#1987][]

[#1479]: https://github.com/dart-lang/language/issues/1479
[#1987]: https://github.com/dart-lang/language/issues/1987

## Motivation

JavaScript has a feature called [tagged template literals][]. This proposal
essentially brings that to Dart. Why is something like this useful? Here's one
detailed example:

[tagged template literals]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Template_literals#tagged_templates

### Code literals for macros

The language team is currently investing adding [macros] to Dart. These macros
are written in Dart and produce Dart code. This means we need some sort of API
for constructing objects that represent pieces of Dart syntax. The best API for
creating Dart syntax *is* Dart syntax. The obvious approach is to have users
place that syntax in string literals and parse it:

[macros]: https://github.com/dart-lang/language/blob/master/working/macros/feature-specification.md

```dart
var code = Code.parse('var n = 123;');
```

But macros may need to produce code objects for different parts of the Dart
grammar&mdash;expressions, statements, declarations, etc. Dart's grammar uses
the same syntax in different contexts to mean different things. For example:

```dart
var code = Code.parse('{}');
```

Does this create syntax for an empty map literal or an empty block statement?
Without knowing where in the grammar the `{}` is intended to appear, there's
no way to unambiguously parse it. The code creation API needs a way for users
to specify what kind of grammar they are creating. We could expose multiple
API entrypoints:

```dart
var map = Expression.parse('{}');
var block = Statement.parse('{}');
```

This works, but is verbose. We could get clever with extension getters:

```dart
var map = '{}'.expression;
var block = '{}'.statement;
```

This is shorter, but not exactly idiomatic.

There is a bigger problem. Macros often compose code out of other pieces of
syntax. For example:

```dart
var add = Expression.parse('2 + 3');
var multiply = Expression.parse('4 * $add');
```

Here, we are composing a binary multiplication out of `4` and another expression
object. The intent is that `2 + 3` should become the right operand to the `*`.
But the `4 * $add` string interpolation simply calls `toString()` on the operand
and stuffs the result directly in, yielding `4 * 2 + 3`.

We want macro authors to be able to easily compose syntax without having to
worry about operator precedence, commas as separators, semicolons as
terminators, etc. In other words, we want Dart string interpolation syntax to be
user-programmable in the way that `for-in` loop syntax is.

## Tagged strings

A **tagged string** is a string literal prefixed with an identifier, like:

```dart
var add = expr '2 + 3';
var subtract = expr '7 - 5';
var multiply = expr '4 * $add / $subtract';
```

Here, the `expr` before each string marks that string as a tagged string. A
tagged string is syntactic sugar for a call to a user-defined **tag processor**
function that has control over how the string literal's string parts and
interpolated expressions are evaluated and composed together.

The above code is essentially seen by the compiler as:

```dart
var add = exprStringLiteral(['2 + 3'], []);
var subtract = exprStringLiteral(['7 - 5'], []);
var multiply = exprStringLiteral(['4 * ', ' / '], [add, subtract]);
```

The literal text parts are pulled out into one list. The interpolated
expressions are put into a second list. Then these are passed to a function
whose name is based on the tag identifier.

Since the intent of this feature is brevity, we expect users to choose short tag
names like `expr` here, `html`, `css`, etc. Since those names are likely to
collide with other variables, the language implicitly appends `StringLiteral` to
the tag name to determine the name of the tag processor. This lets users use
short tag names without having to worry about name collisions.

In the above example, those tagged strings could end up calling tag processor
that looks something like:

```dart
Code exprStringLiteral(
    List<String> strings,
    List<Object> values) {
  var buffer = StringBuffer();
  for (var i = 0; i < values.length; i++) {
    buffer.write(strings[i]);
    var value = values[i];
    if (value is Expression) {
      buffer.write('(' + value.toSource() + ')');
    } else {
      buffer.write(value);
    }
  }

  buffer.write(strings.last);
  return Expression.parse(buffer.toString());
}
```

Note that this toy implementation implicitly wraps values that are
subexpressions in parentheses to avoid precedence errors. The interpolated
expressions passed to a tag processor do not need to evaluate to strings. It's
up to the processor to define which kinds of values are allowed.

Note also that the tag handler does not have to *return* a string either. Here
it returns `Code`. While tag strings are based on Dart string literal syntax,
they can produce an object of any type the user wants.

### Other uses

The driving motivation for adding the feature now is so that we can make it
more pleasant to author macros, but this is a general purpose Dart language
feature that any Dart user can use. Some ideas:

*   An `html` API could be used to compose HTML out of pieces of strings while
    ensuring that the resulting string is correctly [sanitized][].

*   An `sql` API could ensure that interpolated expressions are correctly quoted
    and escaped to avoid [SQL injection][].

*   The [`BigInt`][bigint] class could expose a tag processor so that large
    integers can be created like:

    ```dart
    int '12345678901234567890'
    ```

    instead of:

    ```dart
    BigInt.parse('12345678901234567890')
    ```

*   A logging framework could avoid evaluating the interpolated expressions
    entirely when logging is currently disabled in order to improve performance.
    When logging is enabled, it can catch exceptions thrown by the interpolated
    expressions to ensure that logging itself cannot crash the program.

*   If tagged strings become used for embedded sub-languages like `html`, `css`,
    etc. Then Dart IDEs could potentially syntax highlight the contents of those
    strings according to their tagged language.

[sanitized]: https://en.wikipedia.org/wiki/HTML_sanitization
[sql injection]: https://xkcd.com/327/
[bigint]: https://api.dart.dev/stable/2.14.4/dart-core/BigInt-class.html

## Grammar

The grammar requires a little adjusting because of raw and adjacent strings:

```
stringLiteral ::=
    taggedStringLiteral
  | ( multilineString
    | singleLineString
    | RAW_SINGLE_LINE_STRING
    | RAW_MULTI_LINE_STRING )+

taggedStringLiteral ::= identifier ( multilineString | singleLineString )+

singleLineString ::= // remove raw
    SINGLE_LINE_STRING_SQ_BEGIN_END
  | SINGLE_LINE_STRING_SQ_BEGIN_MID expression
       (SINGLE_LINE_STRING_SQ_MID_MID expression)*
       SINGLE_LINE_STRING_SQ_MID_END
  | SINGLE_LINE_STRING_DQ_BEGIN_END
  | SINGLE_LINE_STRING_DQ_BEGIN_MID expression
       (SINGLE_LINE_STRING_DQ_MID_MID expression)*
       SINGLE_LINE_STRING_DQ_MID_END

multilineString ::= // remove raw
    MULTI_LINE_STRING_SQ_BEGIN_END
  | MULTI_LINE_STRING_SQ_BEGIN_MID expression
       (MULTI_LINE_STRING_SQ_MID_MID expression)*
       MULTI_LINE_STRING_SQ_MID_END
  | MULTI_LINE_STRING_DQ_BEGIN_END
  | MULTI_LINE_STRING_DQ_BEGIN_MID expression
       (MULTI_LINE_STRING_DQ_MID_MID expression)*
       MULTI_LINE_STRING_DQ_MID_END
```

Basically, a string literal can be a tagged string or an untagged string. A
tagged string is an identifier followed by a series of non-raw untagged adjacent
strings. An untagged string is a series of adjacent strings which may include
raw strings.

If the identifier before a string literal is `r`, it is considered a raw string,
not a string tagged with `r`.

## Static semantics

A tagged string is an identifier followed by a series of adjacent string
literals which may contain interpolated expressions. This is treated as
syntactic sugar for a function call with two list arguments.

The tag identifier is suffixed with `StringLiteral` to determine the tag
processor name.

### Static typing

It is a compile-time error if:

*   The tag processor name does not resolve to a function that can be called
    with two positional arguments and no named arguments.
*   `List<String>` cannot be assigned to the first parameter's type.
*   `List<T>` cannot be assigned to the first parameter's type for some `T`.
    This inferred `T` is called the *interpolated expression type*.
*   Any interpolated expression in the string literal cannot be assigned to the
    interpolated expression type.

The latter two rules mean that a tag processor can restrict the types of
expressions that are allowed in interpolation by specifying an element type on
the second parameter to the function. For example:

```dart
Expression exprStringLiteral(
    List<String> strings,
    List<Expression> values) {
  var buffer = StringBuffer();
  for (var i = 0; i < values.length; i++) {
    buffer.write(strings[i]);
    buffer.write('(' + values[i].toSource() + ')');
  }

  buffer.write(strings.last);
  return Expression.parse(buffer.toString());
}

main() {
  var identifier = expr "foo";
  var add = expr "$identifier + $identifier"; // OK.

  var notExpr = 123;
  var subtract = expr "$identifier - $notExpr"; // <-- Error.
}
```

The marked line has a compile error because `notExpr` has type `int`, which
cannot be assigned to the expected interpolated expression type `Code.`

The type of a tagged string literal expression is the return type of the
corresponding tagged string literal function.

### Desugaring

Adjacent strings are implicitly concatenated into a single string as in current
Dart.

The string is split into string parts and interpolation expressions. All of the
string literal parts from the `SINGLE_LINE_*` and `MULTI_LINE_*` rules are
collected in order and put in an object that implements `List<String>`.

Every `expression` from those rules is collected in order into an object that
implements `List<T>` where `T` is the interpolated expression type.

The structure of the grammar is such that the list of string parts will always
be one element longer than the list of expressions. If there are no expressions,
there will be one string part. If an interpolated expression begins the string,
there will be a zero-length initial string part. Likewise, if an interpolated
expression ends the string, there will be a zero-length string part at the end
of the parts list. Some examples:

```dart
// string          parts            expressions
tag ''          // ''               (none)
tag 'str'       // 'str'            (none)
tag '$e'        // '', ''           e
tag '@$e'       // '@', ''          e
tag '$e!'       // '', '!'          e
tag '@$e!'      // '@', '!'         e
tag '$e$f'      // '', '', ''       e, f
tag '@$e#$f!'   // '@', '#', '!'    e, f
```

The tagged string literal is replaced with a call to the tag processor function.
The list of string parts and expressions (which may be empty) are passed to that
function as positional arguments.

## Runtime semantics

This feature is purely syntactic sugar, so there are no runtime semantics
beyond the behavior of the Dart code that the tagged string desugars to.
