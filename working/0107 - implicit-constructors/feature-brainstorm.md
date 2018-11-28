# Implicit Constructors

Author: kevmoo@google.com

Proposed solution to [type conversion problem (#107)](https://github.com/dart-lang/language/issues/107).
Discussion about this proposal should go in [Issue #108](https://github.com/dart-lang/language/issues/108).

## Motivation

Every place in `pkg:http` with a `url` parameter types it as `dynamic`.

```dart
Future<Response> get(url, {Map<String, String> headers}) => ...

void doWork() async {
  await get('http://example.com');
  await get(Uri.parse('http://example.com'));
  await get(42); // statically fine, but causes a runtime error
}
```

This is to support a common use case: devs often want to pass either `Uri`
*or* `String` to such methods. In the end, all `String` values are "upgraded"
to `Uri` before use. To support the desired flexibility, the user risks
runtime errors if something other than `String` or `Uri` are provided.

Flutter avoids this issue, by being explicit about types everywhere.

```dart
// Flutter
void giveMeABorder(BorderRadiusGeometry value) {}

void doWork() {
  giveMeABorder(const BorderRadius.all(
    Radius.circular(18),
  ));

  // User would like to write this, but...
  giveMeABorder(18); // static error
}
```

The existing request(s) for union types –
https://github.com/dart-lang/sdk/issues/4938 and
https://github.com/dart-lang/language/issues/83
– could be an option here, but it would require updating all parameters
and setters to specify the supported types.

An alternative: implicit constructors.

## Syntax

*This is all PM spit-balling at the moment...*

* Introduce a new keyword – `implicit` – that can be applied to a constructor or
  factory.

```dart
class Uri {
  // Note: parse is currently a static function on Uri, not a constructor.
  implicit Uri.parse(String uri) => ...
}

class BorderRadiusGeometry {
  implicit factory BorderRadiusGeometry.fromDouble(double radius) =>
    BorderRadius.all(Radius.circular(18));
}

class Widget {
  implicit factory Widget.fromString(String text) => Text(text);
}

// NOTE - for both Widget and BorderRadiusGeometry, you really want a
// `const implicit factory`. Supporting `const factory` seems like a necessary
// precursor.
```

* When evaluating an assignment to type `T`, if the provided value `P` is
  not of type `T`, then look for an implicit constructor/factory on `T` that
  supports an instance of `P`. If it exists, use it.

## Other implementations

* C# - https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/implicit
* Scala - https://docs.scala-lang.org/tour/implicit-conversions.html
  * Leaf has warned about Scala's support for cascading implicit conversions
    (e.g. int -> Duration -> Time). Dart should avoid this!
