# Dart Null Safe Numbers

Author: lrn@google.com<br>Version: 1.3

## Background

Most Dart number operations behave such that if all operand are integers, the result is an integer, and if any operand is a double, the result is a double.

That's not something the general Dart type system can capture, so Dart special-cases number operators in the type system specification so that, for example, `1 + 1` can has static type `int` even though `int.operator+` actually has the signature `num Function(num)`.

The special-cased typing works because the language enforces that the only subclasses of `num` is `int` and `double`, and those cannot have subclasses at all. Even though operators are otherwise virtual, the only two `+` operations that can possibly be in play for `numValue + something`  are the `int.operator+` and `double.operator+`  which have known behavior compatible with the special typing, and `intValue + something` is known to call the `int.operator+` method. (This is also the reason those operators can be used in constant expressions: Their behavior is known at compile-time.).

The current rules do not cover all integer operations, or any double operations, and this means that a few operations have the default type of `num` inherited from the `num` interface. That has so far not been a serious problem since Dart has had *implicit downcasts* which allows `num` to be assigned to both `int` and `double`. Some static checking my be lacking, but it still runs.

With Null Safety, we remove implicit downcasts from the language. This causes some existing, functioning code to become invalid, and currently the only workaround is adding an explicit cast.

This behavior also interacts with type inference because the inference doesn't take the special rules for numbers into account, leading to users being surprised when `double x = 1 + await Future(() => 2.5);` fails to recognize that the result is a `double`.

See [language#971][], [language#725][], [language#597][], [sdk#41559][], [sdk#39652][], [sdk#32645][], [sdk#28249][].

## Concrete issues

### Some methods are not special-cased

The special-case typing rules only apply to arithmetic *operators* (`+`, `-`, `*`, `%`). They do not apply to `int.remainder`, even though it is otherwise equivalent to `%`,and they do not apply to `num.clamp`. These are the two remaining members of `int` which has a return type of `num`.

This has caused issues before, but now those issues become compile-time errors because of the lack of [impliciit downcasts][sdk#39652].

### Rules do not work with type variables

An operation like `T add<T extends num>(T a, T b) => a + b;` becomes invalid with Null Safety because the type of `a + b` is num, not `T`, and the implicit down-cast from `num` to `T` is no longer valid.

### No special case for `num op double`

We recognize that `int + int` is an `int`  and that `int + double` is a `double`, but not that `num + double` is a `double`, even though it always is. That missing case has generally been saved by implicit downcast because the result is `num` and `num`  can be assigned to `double` (and because there are very few members on `double` that are not also members of `num`). It can happen accidentally, for example:

```dart
int n = …, m = …;
var x = n.remainder(m); // Type is `num` because `remainder` isn't special-cased.
var y = x * 2.5;  // Type of y is `num`, not `double`.
expectsDouble(y); // Used to be implicit downcast, now a compile-time error.
```

### Inference doesn't know special rules

Code like `int n = …; double y = n * 2;` is a compile-time error. The type context for `2` is `num`. The author expected `2` to be a double literal, and it's possible to recognize that *making* it a double literal would make the code correct. Not all instances of this problem are as obvious as this one, for example: `double y = n * await Future(() => 2.0);` will currently infer the future to be a `Future<num>` independently of the operation.

## Solution goal

This document specifies new rules that solves the problems mentioned above. The *goal* is to allow code that users will naturally write and expect to work, to actually work. The users expected mental model for arithmetic operations can be summarized 

> If all operands are integers, the result is and integer, and if any operand is a double, the result is a double.

Users understand that both `int` and `double` are sealed types and that all `num` objects are really either an `int` or a `double`. They also understand type promotion, so checking that something is a an `int`  should make it work like an `int`. This means that `T extends num`  should act like `num` and  `T & int` should act like `int`.

Such a user would expect the following code to work:

```dart
double lerp(num start, num end, double y) => start + (end - start) * y;
T add<T extends num>(T a, T b) => a + b;
```

because any attempt to plug in actual values will give sound results.

Users also understand that `clamp` will return either the receiver or one of the arguments. If those all have the same type, the result will have that type.

## Solution

### Extended Rules

We extend the special-casing rules of `+`, `-`, `*` and `%` to also cover calls of the `remainder` method, and to also work with type parameters which extend `num` , `int` or `double`. Finally, if the second operand is a `double` and the first is a `num`, the result is guaranteed to be a `double`.

That is:

> For an expression `e` of one of the forms `e1 + e2`, `e1 - e2`, `e1 * e2`, `e1 % e2` or `e1.remainder(e2)`, where the static type of `e1` is a non-`Never` type *T* where *T* <: `num` and the static type of `e2` is a non-`Never` type *S* where *S* <: `num`:
>
> * If S <: T then the static type of `e` is *T*. 
> * Otherwise If *T* <: *S* then the static type of `e` is *S*.
> * Otherwise if *T* <: `int` and *S* <: `int` then the static type of `e` is `int`.
> * Otherwise if *T* <: `double` or *S* <: *double* then the static type of *e* is `double`.
> * Otherwise the static type of *e* is `num`.

We also special-case the `clamp` method:

> For a normal invocation `e` of the form `e1.clamp(e2, e3)`, where the static types of `e1`, `e2` and `e3` are *T*<sub>1</sub>, *T*<sub>2</sub> and *T*<sub>3</sub> respectively, which are all non-`Never` subtypes of `num`:
>
> * If any of *T*<sub>1</sub>, *T*<sub>2</sub> or *T*<sub>3</sub> is a supertype of the other two, the first such is the static type of `e`.
> * Otherwise, if all of *T*<sub>1</sub>, *T*<sub>2</sub> and *T*<sub>3</sub> are subtypes of `int`, the static type of `e` is `int`.
> * Otherwise if all of *T*<sub>1</sub>, *T*<sub>2</sub> and *T*<sub>3</sub> are subtypes of `double`, the static type of `e` is `double`.
> * Otherwise the static type of `e` is `num`.

With these extensions, we cover all members on `int` which has a return type of `num`, and we ensure that a using operands with the *same* type gives a result of that type, even if that type is a type variable (like `X extends int`) or promoted type variable (like `X & int`).

There are no special rules for `/` and `~/` because their return type is not `num`, and the return value's type is independent of the argument types. A `/` operation always returns a `double` and a `~/` operation always returns an `int`.

### Improved context type

We extend type inference to take the special number rules into account.

> For  `e1 + e2`, `e1 - e2`, `e1 * e2`, `e1 % e2` or `e1.remainder(e2)` where `e1` has static type `int`, if the context type of the entire expression is `int`, then the context type of `e2` is `int`, and if the context type of the entire expression is `double`, then the context type of `e2` is `double`.

> If the context type of `e1.clamp(e2, e3)` is a non-`Never` subtype of `num`, *T*, and the static type of `e1` is a non-`Never` subtype of *T*, then the context types of `e2` and `e3` are both *T*.<br>

(This does emphasize the inherent non-symmetry of Dart operators: The first operand is a receiver which is always evaluated with no type context, and is then used to resolve the operator method against, and the second operand is an argument to that method. We need to fully resolve the first operand and the operator before we can even begin with the second operand.)

### Compound Operations

These extensions also carry over to the compound assignment operators and increment/decrement operators.

#### Compound Assignment Operators

An `lhs += e` expression is roughly equivalent to `lhs = lhs + e` except that subexpressions of `lhs` are only evaluated once. The static typing rules that apply to `lhs + e` also applies to `lhs += e`, and similarly for the other binary operators that are special cased.

That means that `int x = 0; x += 1;` works because `x += 2` is equivalent to `x =  x + 2`, and `x + 2` has type `int`.

### Increment/Decrement Operators

The prefix and suffix increment and decrement operators (`++x`, `x++`, `--x` and `x--`) are roughly equivalent to expressions containing `x + 1` or `x - 1`. The static typing rules that apply to `+` also apply to `--` and `++`, with the caveat that the `1` is not treated as a number literal that can potentially be a `double`, even if we apply a context type of `double` to the position. The `1` is *always* an integer literal.

## Summary

These changes to the special-casing type rules for numbers will ensure that commonly used operations behave nicely. 

The changes cover *all the listed issued*:

* [language#971][] is fixed by including `remainder`.
* [language#597][] is fixed by the improved context type inference and recognition of type.variables.
* [sdk#28249][] is fixed by including `clamp`.
* [sdk#32645][] is fixed by including `remainder`.
* [sdk#39652][] is fixed by including `clamp`.
* [sdk#41559][] is fixed by improved context type inference.

These changes will remove some common pitfalls introduced (or worsened) by removing implicit downcasts with Null Safety.

[language#597]: https://github.com/dart-lang/language/issues/597
[language#725]: https://github.com/dart-lang/language/issues/725
[language#971]: https://github.com/dart-lang/language/issues/971
[sdk#28249]: https://github.com/dart-lang/sdk/issues/28249
[sdk#32645]: https://github.com/dart-lang/sdk/issues/32645
[sdk#39652]: https://github.com/dart-lang/sdk/issues/39652
[sdk#41559]: https://github.com/dart-lang/sdk/issues/41559

