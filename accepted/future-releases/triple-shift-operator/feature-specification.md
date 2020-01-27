# The `>>>` Operator

**Author**: [lrn@google.com](mailto:lrn@google.com)

**Version**: 1.0 (2018-11-30)

## Feature Specification

See [Issue #120](http://github.com/dart-lang/language/issues/120).

The `>>>` operator is reintroduced as a user-implementable operator.
It works exactly as all other user-implementable operators.
It has the same precedence as the `>>` and `<<` operators.

That also means that `>>>=` assignment must work 
and `#>>>` and `const Symbol(">>>")` must be valid symbols.
The `>>>` operator should work in all the same places that `>>` currently does.

The `int` class implements `>>>` as a logical right-shift operation,
defined as:
```dart
/// Shifts the bits of this integer down by [count] bits, fills with zeros.
///
/// Performs a *logical shift* down of the bits representing this number,
/// which shifts *out* the low [count] bits, shifts the remaining (if any)
/// bits *down* to the least significant bit positions,
/// and shifts *in* zeros as the most significant bits.
/// This differs from [operator >>] which shifts in copies of the most
/// significant bit as the new most significant bits.
///
/// The [count] must be non-negative. If [count] is greater than or equal to
/// the number of bits in the representation of the integer, the result is
/// always zero (all bits shifted out).
/// If [count] is greater than zero, the result is always positive.
///
/// For a *non-negative* integers `n` and `k`,
/// `n >>> k` is equivalent to truncating division of `n` by 2<sup>k</sup>,
/// or `n ~/ (1 << k)`.
int operator >>>(int count);
```

The JavaScript implementation of `int`'s `>>>` operator must be decided 
and implemented by the JavaScript platforms. It likely works like `>>`
except that it doesn't "sign-extend" the most significant bit.

## Background

When Dart chose arbitrary size integers as its `int` type, it also removed
the `>>>` operator, not just from `int`, but from the language.

Now that Dart has chosen to use signed 64-bit integers as its `int` type,
there is again need for a logical right shift operator on `int`,
and so we reintroduce the `>>>` operator in the language.

This was decided before Dart 2 was released, and `>>>` was put into the
current language specification document, but it was not implemented by
the language tools for Dart 2.0 due to other priorities.
