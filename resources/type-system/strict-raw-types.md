# Strict raw types static analysis option

This document specifies the "Strict raw types" mode enabled with a static
analysis option. As a static analysis option, we only intend to implement this
feature in the Dart Analyzer. Under this feature, a type with omitted type
argument(s) is defined as a "raw type." Dart fills in such type arguments with
their bounds, or `dynamic` if there are no bounds.

## Enabling strict raw types

 To enable strict raw types, set the `strict-raw-types` option to `true`, under
 the Analyzer's `language` section:

 ```yaml
analyzer:
  language:
    strict-raw-types: true
```

## Motivation

It is possible to write Dart code that passes all static type analysis and
compile-time checks that is guaranteed to result in runtime errors. Common
examples include runtime type errors, and no-such-method errors. Developers are
often surprised to see such errors at runtime, which look like they should be
caught at compile time.

The strict raw types mode aims to highlight such code during static analysis.
We can look at some common examples:

```dart
void main() {
  List a = [1, 2, 3];
}
```

Developers often think that inference fills in the type of `a` from the right
side of the assignment. It may look like `a` has the type `List<int>`. But Dart
fills in omitted type arguments, like `E` on `List`, with `dynamic` (or the
corresponding type parameter's bound); `List a;` is purely a shorthand for
`List<dynamic> a;`. Inference then flows from `a` onto the expression on the
right side of the assignment. This is more obvious in another example:

```dart
void main() {
  List a = [1, 2, 3]..forEach((e) => print(e.length));
  var b = [4, 5, 6]..forEach((e) => print(e.length));
}
```

The first statement does not result in any static analysis errors, since the
type of the list is inferred to be `List<dynamic>`. Instead, the code results
in a runtime no-such-method error, when the `length` getter is called on an
`int`.

The second statement, however, allows the type of the list to be inferred from
its elements, as `List<int>`, which results in a static analysis type error,
which notes that the getter `length` is not defined on `int`.

Raw types can also lead to unintended dynamic dispatch:

```dart
void main() {
  List a = [1, 2, 3];
  a.forEach((e) => print(e.isEven));
}
```

The developer likely does not realize that the parameter `e` of the callback is
`dynamic`, and that the call to `isEven` is a dynamic dispatch.

Reporting strict raw types encourages developers to fill in omitted type
arguments, hopefully with something other than `dynamic`. In cases where the
only good type is `dynamic`, then including it as an explicit type argument
avoids the raw type, and makes the dynamic behavior more explicit in the code.

## Conditions for a raw type Hint

Any raw type results in a raw type Hint, except under the following conditions:

* the raw type is on the right side of an `as` or an `is` expression
* the raw type is defined by a class, mixin, or typedef annotated with the
  `optionalTypeArgs` annotation from the meta package.

## Examples

This section is non-normative. It does not represent an exhaustive selection of
conditions for a raw type Hint.

```dart
import 'package:meta/meta.dart';

List l1 = [1, 2, 3];            // Hint
List<List> l2 = [1, 2, 3];      // Hint
final f1 = Future.value(7);     // OK

fn1(Map map) => print(map);     // Hint
Map fn2() => {};                // Hint

class C1 {
  List l3 = [1, 2, 3];          // Hint
  print([] is Set);             // OK

  m(Map map) => print(map);     // Hint
}

class C2<T> {}

class C3 extends C2 {}          // Hint
class C4 implements C2 {}       // Hint
class C5 with C2 {}             // Hint

typedef Callback<T> = void Function(T);

Callback = (int n) => print(n); // Hint

@optionalTypeArgs
class C6<T> {}

C6 a;                           // OK
List<C6> b;                     // OK
C6<List> c;                     // Hint

class C7 extends C6 {}          // OK
```
