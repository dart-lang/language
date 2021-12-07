# Strict casts static analysis option

This document specifies the "Strict casts" mode enabled with a static
analysis option, new in Dart 2.16. As a static analysis option, we only intend
to implement this feature in the Dart Analyzer. Under this feature, any
implicit cast is reported as an analyzer "Hint" (a warning).

Note that under the null safe type system, the only expressions which may be
implicitly cast are those with a static type of `dynamic`. These are exactly
the implicit casts reported in the "Strict casts" mode.

## Enabling strict casts

To enable strict casts, set the `strict-casts` option to `true`, under
the Analyzer's `language` section:

```yaml
analyzer:
  language:
    strict-casts: true
```

## Motivation

Static analysis can provide many benefits which require meaningful static
types. For example, when a value of one type is _not assignable_ to a variable
of another type, the error is reported by static analysis. However, when a
value has a static type of `dynamic`, no error is reported; such a value is
always assignable, because a cast is implicitly inserted at runtime, which may
fail. For example:

```dart
import 'dart:convert';
void main() {
  var decoded = jsonDecode(/* some JSON */);
  if (decoded['foo']) {
    print('Got foo.');
  }
}
```

The expression used in an if-statement's condition must have a static type of
`bool`. Without the Strict casts mode, an expression with a static type of
`dynamic` (such as the example's `decoded['foo']`) is allowed, due to the
implicit cast to `bool` which will occur at runtime. The Strict casts mode aims
to warn about such code during static analysis.

Note that another way to root out implicit casts from the `dynamic` type is to
ban all use of the `dynamic` type. However, there are many common APIs which
return `dynamic`-typed values, such as the `dart:convert` library's
JSON-decoding functions (referenced in the example above). The Strict casts
mode allows the use of such APIs, requiring only that such `dynamic`-typed
values are _explicitly_ cast before using them in a position where a value of
non-`dynamic` type is expected.

## Differences from "no implicit casts" mode

The Strict casts mode is very similar to another static analysis mode supported
by the Dart analyzer: "no implicit casts," now deprecated in favor of the
Strict casts mode. The Strict casts mode reports all of the same implicit casts
which the "no implicit casts" mode does, and it also reports three more cases,
detailed below.

### for-in loop iteration

A value with a static type of `dynamic` which is used as the iterator
expression in a for-in loop is reported. For example:

```dart
void foo(dynamic arg) {
  for (var value in arg) { /* ... */ }
}
```

### spread expression

A value with a static type of `dynamic` which is used as the expression in a
spread is reported. For example:

```dart
void foo(dynamic arg) {
  [...arg];
}
```

### yield-each expression

A value with a static type of `dynamic` which is used as the expression in a
yield-each expression is reported. For example:

```dart
Stream<int> foo(dynamic arg) async* {
  yield* arg;
}
```
