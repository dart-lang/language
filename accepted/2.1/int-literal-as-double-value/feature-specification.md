# Integer literals where a double value is expected

**Author**: [lrn@google.com](mailto:lrn@google.com)

**Version**: 1.0 (2018-10-18)

**Status**: Specification complete

## Specification

This is the feature specification for allowing integer literals where a double value is expected. The content was ported from https://github.com/dart-lang/language/issues/4.

## Summary

Dart should allow an integer literal to denote a `double` value when it's used in a context which requires a `double` value.

To do this, the meaning of the literal will have to depend on the expected type, aka. "the context type". The context type is already known to the compiler since Dart 2 uses that type for inference. The expected type may be empty (no requirement), but that still means that the expected type isn't exactly `double.`

## Background

Currently a valid integer literal, or an integer literal prefixed with a minus sign, always evaluates to instances of `int`. The (potentially signed) integer literal is invalid if its numerical value cannot be represented by `int` (plus some edge cases for unsigned 64-bit integers).

If the context type does not allow `int` to be assigned to it, the program fails to compile. That includes the case where the context type is `double`, so programs like `double x = 0;` are compile-time errors because of the type-invalid assignment.

The current behavior is changed to:

> If `e` is an integer literal which is not the operand of a unary minus operator, then:
> * If the context type is `double`, it is a compile-time error if the numerical value of `e` is not precisely representable by a `double`. Otherwise the static type of `e` is double and the result of evaluating `e` is a `double` instance representing that value.
> * Otherwise (the current behavior of `e`, with a static type of `int`).

and 

> If `e` is `-n` and `n` is an integer literal, then
> * If the context type is `double`, it is a compile-time error if the numerical value of `n` is not precisley representable by a `double`. Otherwise the static type of `e` is double and the result of evaluating `e` is the result of calling the unary minus operator on a `double` instance representing the numerical value of `n`.
> * Otherwise (the current behavior of `-n`)

This applies to both decimal and hexadecimal integer literals. 
We recognize `-0` in a double context as evaluating to `-0.0`.

In all other contexts, the integer literal evaluates to an `int` instance like it currently does.

Making the unrepresentable integer numeral an error allows the user to keep a simple mental model: Integer literals are always exact, floating point literals may not be. This matches the integer behavior, where an invalid `int` value is a compile-time error.

This is a non-breaking change since the all programs that change behavior would have an integer literal in a double context, and therefore already be compile-time errors.

Examples
-----

The following declarations are either valid (named "valid") or compile-time errors (named "bad").

```dart
double valid = 0;  // 0.0
double valid = -0;  // -0.0
double valid = 0xFFFFFFFFFFFFF0000000000;  // Too big to be an int, valid as a double.
double bad = 0xFFFFFFFFFFFFFF;  // Valid int, invalid double, more than 53 significant bits.
double valid = 9007199254740991;  // 2^53-1.
double valid = 9007199254740992;  // 2^53. All integers up to here are representable.
double bad = 9007199254740993;  // 2^53+1, first non-representable integer.
double valid = 0xfffffffffffff800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;  // Max finite double, largest allowed literal.
double bad = 0xfffffffffffff8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;  // Too large (one more 0 than above, would be Infinity if double).
```

Potential issues
===
This change is mostly simple and non-breaking, but there are potential issues.

Static typing 
---
The change relies on static typing to decide the meaning of literals. We do that in a few other cases (instantiated tear-offs of generic methods), which can seem a bit magical, and means that the meaning of the expression depends on the type, and potentially on type inference. 

Confusion because it doesn't work everywhere
---
This feature allows the use of integer literals as double values in some places. However, it is very restrictive in where that happens, and it's only applied to literals. That might be confusing to users who will expect integers to be usable as doubles in other situations, and it means that some refactorings are no longer valid. If they move a literal out of the double context, it might change meaning. Or, in other words, refactoring should type any variable that it introduces when extracting an expression, but that should generally be the case in Dart 2, to preserve the inference context.

Examples where context isn't expecting double:
```dart
var doubleList = [3.14159, 2.71828, 1.61803, 0]; // Obviously meant 0.0!
const x = -0;  // Not -0.0, even though there is *no other reason* to write it.
var x1 = functionExpectingDouble(0);  // Works. 
// Let's refactor the constant into a named variable.
const zero = 0;
var x2 = functionExpectingDouble(zero);  // Fails now?
```

The `doubleList` needs to be written as either:
```dart
var doubleList = <double>[3.14159, 2.71828, 1.61803, 0];
// or 
List<double> doubleList = [3.14159, 2.71828, 1.61803, 0];
```
We can't easily change this, since the `num`-list is existing valid code and might be deliberate.
This may be a usability pitfall to users, and we may be introducing new stumbling points to replace the ones we are fixing.

Exact integers are hard to write
---
We only allow integer literals that can be represented exactly by a double.
However, doubles are not always thought of as representing a single number. In some cases they are treated as if they represent a range, and any number in that range is represented by the same double value.
That affects `double.toString`, so there are double value where the non fractional digits of their `toString` will not be a valid integer-literal-as-double. Since JavaScript does not add a final `.0` when printing integer valued doubles, taking a double value in JavaScript and pasting its string representation into Dart may not be a valid double-typed integer literal.

Example, in JavaScript console:
```javascript
> 123456 * 7891011121314
< 974192668992941200
```
Now enter that into Dart:
```dart
double x = 974192668992941200;  // Compile-time error
```
This is a compile-time error because the value, as written, is not exactly representable as a double. The actual value of the JavaScript double is 974192668992941184.0, but the double-to-string conversion picks a representation with more trailing zeros, one that is still closer to the correct value than to any other valid double value.

This will likely be annoying. 

We can, without issues, allow inexact literals, but it breaks the user expectation that an integer literal represents an exact number, and that any integer which is accepted on all platforms will meant the same thing everywhere. We already allow inexact values for double literals, but the trailing `.0` is a very clear hint to the reader that we are in double land.
I recommend starting out with the strict rejection of any integer literal in a double context with a value that cannot be represented exactly by a double. We can then remove that restriction if experience tells us that it is too cumbersome to work with, but we cannot introduce a restriction after launching without it.


Implementation
===
Implementation is likely front-end only. Back-ends should just see a double literal.
The parser needs to allow more integer literals, so that finding the meaning of the integer literal can be delayed until the context type is known (past type inference).

Tools that process source code might need to be aware that this new combination is allowed.

JavaScript compilation
---
When compiling to JavaScript, integer literals will need to accept all valid non-fractional finite double values anyway, because that's what the `int` type can contain. They don't currently, we restrict to 64-bit values early, but we plan to change that. When that happens, the integer literals in a double context and the integer literals in a non-double context will behave exactly the same when compiled to JavaScript. That means that the code path must exist anyway, even without this feature, so adding this feature is unlikely to require large computations.

Related work
===
[Go lang constants](https://golang.org/ref/spec#Constants).
The Go language numeric constants are "bignums" with at least 256 bits of precision, and all constant computations are performed at this large precision. They are only converted to the actual int and double types when the value is used in a dynamic computation. This differs from Dart where compile-time constant computations always use the same semantics as the run-time computations.
