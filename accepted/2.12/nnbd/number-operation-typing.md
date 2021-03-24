# Dart Null Safe Numbers

Author: lrn@google.com<br>Version: 1.4

## Background

Most Dart number operations behave such that if all operand are integers, the result is an integer, and if any operand is a double, the result is a double.

That's not something the general Dart type system can capture, so Dart special-cases number operators in the type system specification so that, for example, `1 + 1` can has static type `int` even though `int.operator+` actually has the signature `num Function(num)`.

The special-cased typing works because the language enforces that the only subclasses of `num` is `int` and `double`, and those cannot have subclasses at all. Even though operators are otherwise virtual, the only two `+` operations that can possibly be in play for `numValue + something`  are the `int.operator+` and `double.operator+`  which have known behavior compatible with the special typing, and `intValue + something` is known to call the `int.operator+` method. (This is also the reason those operators can be used in constant expressions: Their behavior is known at compile-time.).

The original Dart 2.0 rules do not cover all integer operations, or any double operations, and this means that a few operations have the default type of `num` inherited from the `num` interface. That has so far not been a serious problem since Dart has had *implicit downcasts* which allows `num` to be assigned to both `int` and `double`. Some static checking my be lacking, but it still runs.

With Null Safety, we remove implicit downcasts from the language. This causes some existing, functioning code to become invalid, and currently the only workaround is adding an explicit cast.

This behavior also interacts with type inference because the inference doesn't take the special rules for numbers into account, leading to users being surprised when `double x = 1 + await Future(() => 2.5);` fails to recognize that the result is a `double`.

See [language#971][], [language#597][], [sdk#41559][], [sdk#39652][], [sdk#32645][], [sdk#28249][].

## Concrete issues

### Some methods are not special-cased

The special-case typing rules only apply to arithmetic *operators* (`+`, `-`, `*`, `%`). They do not apply to `int.remainder`, even though it is otherwise equivalent to `%`,and they do not apply to `num.clamp`. These are the two remaining members of `int` which have a return type of `num`.

This has caused issues before, but now those issues become compile-time errors because of the lack of [implicit downcasts][sdk#39652].

### Rules do not work with type variables

An operation like `T add<T extends num>(T a, T b) => a + b;` becomes invalid with Null Safety because the type of `a + b` is `num`, not `T`, and the implicit down-cast from `num` to `T` is no longer valid.

### No special case for `num op double`

We recognize that `int + int` is an `int`  and that `int + double` is a `double`, but not that `num + double` is a `double`, even though it always is. That missing case has generally been saved by implicit downcast because the result is `num` and `num`  can be assigned to `double` (and because there are very few members on `double` that are not also members of `num`). It can happen accidentally, for example:

```dart
int n = …, m = …;
var x = n.remainder(m); // Type is `num` because `remainder` isn't special-cased.
var y = x * 2.5;  // Type of y is `num`, not `double`.
expectsDouble(y); // Used to be implicit downcast, now a compile-time error.
```

### Inference doesn't know special rules

Code like `int n = …; double y = n * 2;` is a compile-time error. The type context for `2` is `num`. The author expected `2` to be a double literal, and it's possible to recognize that *making* it a double literal would make the code correct. Not all instances of this problem are as obvious as this one, for example: `double y = n * await Future(() => 2.0);` will infer the future to be a `Future<num>` independently of the operation.

## Solution goal

This document specifies new rules that solves the problems mentioned above. The *goal* is to allow code that users will naturally write and expect to work, to actually work. The users expected mental model for arithmetic operations can be summarized 

> If all operands are integers, the result is and integer, and if any operand is a double, the result is a double.

Users understand that both `int` and `double` are sealed types and that all `num` objects are really either an `int` or a `double`. They also understand type promotion, so checking that something is a an `int`  should make it work like an `int` where possible.

This means that a value of type `T extends num`  should act like `num` and  `T & int` should act like `int`.

Such a user would expect the following code to work:

```dart
double lerp(num start, num end, double y) => start + (end - start) * y;
```

because any attempt to plug in actual values will give sound results. 

They will expect `x += 1;` to work no matter which numeric type `x` has. We will not  try to make it work for type variables with bounds or promotions to numeric types.

Users also understand that `clamp` will return either the receiver or one of the arguments. If those all have the same numeric type, the result will have that type.

## Solution

### Extended Rules

We extend the special-casing rules of `+`, `-`, `*` and `%` to also cover calls of the `remainder` method, and to also work with type parameters which extend `num` , `int` or `double`. Finally, if the second operand is a `double` and the first is a `num`, the result is guaranteed to be a `double`.

Let `e` be an expression of one of the forms `e1 + e2`, `e1 - e2`, `e1 * e2`, `e1 % e2` or `e1.remainder(e2)`, where the static type of `e1` is a non-`Never` type *T* and *T* <: `num`, and where the static type of `e2` is *S* and *S* is assignable to `num`. Then:

* If *T* <: `double` then the static type of `e` is `double`. _This includes *S* being `dynamic` or `Never`._
* If *S* <: `double` and not *S* <:`Never`, then the static type of `e` is `double`.
* If *T* <: `int` ,  *S* <: `int` and not *S* <: `Never`, then the static type of `e` is `int`.
* Otherwise the static type of *e* is `num`.

We also special-case the `clamp` method.

Let `e` be a normal invocation of the form `e1.clamp(e2, e3)`, where the static types of `e1`, `e2` and `e3` are *T*<sub>1</sub>, *T*<sub>2</sub> and *T*<sub>3</sub> respectively, and where  *T*<sub>1</sub>, *T*<sub>2</sub>, and *T*<sub>3</sub> are all non-`Never` subtypes of `num`. Then:

* If *T*<sub>1</sub>, *T*<sub>2</sub> and *T*<sub>3</sub> are all subtypes of `int`, the static type of `e` is `int`.
* If *T*<sub>1</sub>, *T*<sub>2</sub> and *T*<sub>3</sub> are all subtypes of `double`, the static type of `e` is `double`.
* Otherwise the static type of `e` is `num`.

With these typing rules, we cover all the instance members of `int` which has a return type of `num`, and we ensure that a using operands with the *same* type gives a result of that type, even if that type is a type variable (like `X extends int`) or promoted type variable (like `X & int`).

There are no special rules for `/` and `~/` because their return type is not `num`, and the return value's type is independent of the argument types. A `/` operation always returns a `double` and a `~/` operation always returns an `int`.

The rules for the binary operators can be summarized (non-normatively) as:


|  *T* \\ *S*   | <: int | <: double | <: num | dynamic |
| :-----------: | ------ | --------- | ------ | ------- |
|  **<: int**   | int    | double    | num    | num     |
| **<: double** | double | double    | double | double  |
|  **<: num**   | num    | double    | num    | num     |

where `<: num` here represents a subtype of `num` which is *not* also a subtype of `int` or `double`.

### Improved context type

We extend type inference to take the special typing rules into account.

If `e` is an expression of the form  `e1 + e2`, `e1 - e2`, `e1 * e2`, `e1 % e2` or `e1.remainder(e2)`, where *C* is the context type of `e` and *T* is the static type of `e1`, and where *T* is a non-`Never` subtype of `num`, then:

* If `int` <: *C*, not `num` <: *C*, and *T* <: `int`, then the context type of `e2` is `int`. 
* If `double` <: *C*, not `num` <: *C*, and not *T* <: `double`, then the context type of `e2` is `double`.
* Otherwise, the context type of `e2` is `num`.

*(It is not necessarily a compile-time error if the static type of `e2` is not a subtype of _C_, but it is still a compile-time error if the static type of `e2` is not assignable to the actual parameter type,`num`.)*

If `e` is an expression of the form `e1.clamp(e2, e3)` where *C* is the context type of `e` and *T* is the static type of `e1` where *T* is a non-`Never` subtype of `num`, then:

* If `int` <: *C*, not `num` <: *C*, and *T* <: `int`, then the context type of `e2` and `e3` is `int`. 
* If `double` <: *C*, not `num` <: *C*, and *T* <: `double`, then the context type of `e2` and `e3` is `double`. 
* Otherwise the context type of `e2` an `e3` is `num`

*(It is not necessarily a compile-time error if the static type of `e2` or `e3` is not a subtype of the expression's context type, but it is still a compile-time error if the static type of `e2` or `e3` is not assignable to the actual parameter type,`num`.)*

These rules emphasize the inherent non-symmetry of Dart operators: The first operand is a receiver which is always evaluated with no type context, and is then used to resolve the operator method against, and the second operand is an argument to that method. We need to fully resolve the first operand and the operator before we can even begin with the second operand.

For the binary operators, the context type of the second operand, based on the first operand and the context type of the entire operation, can be summarized (non-normatively) as:

|  *C* \\ *T*   | <: int | <: double       | <: num          |
| :-----------: | ------ | --------------- | --------------- |
|  **<: int**   | int    | num<sup>*</sup> | num<sup>*</sup> |
| **<: double** | double | num             | double          |
|  **<: num**   | num    | num             | num             |

where `<: num` here represents a subtype of `num` which is *not* also a subtype of `int` or `double`.

The cases marked with <sup>\*</sup> are inherently invalid. There is no valid second operand which can make the operation satisfy the context type.

### Compound Operations

These extensions also carry over to the compound assignment operators and increment/decrement operators.

#### Compound Assignment Operators

An `lhs += e` expression is roughly equivalent to `lhs = lhs + e` except that subexpressions of `lhs` are only evaluated once. The static typing rules that apply to `lhs + e` also applies to `lhs += e`, and similarly for the other binary operators that are special cased.

The static type of `lhs += e` is the static type of `lhs + e`.

In general the static type of `x + integer` is the same as the static type of `x` when the type is a one of `int`, `double` or  `num`, exactly to allow compound assignment to work no matter which number type is on the left-hand side.

If the type of `x` is, say, `T extends int`, then `x += 1` will not work without a cast because the static type of `x + 1` is `int`, not `T`. The result must be cast to `T` as `x = (x + 1) as T;`. There is no simple workaround if the type of `x` is `T&int`.

*It's possible to have a setter with a less specific argument type than the type of the corresponding getter, like `set foo(num x); int get foo;`. That is not a problem for these rules, it merely means that for `foo += e`, equivalent to `foo = foo + e`, the context type might not be the same as the type of  reading `x`. The typing and context rules are compatible with this.*

### Increment/Decrement Operators

The prefix and suffix increment and decrement operators (`++x`, `x++`, `--x` and `x--`) are roughly equivalent to expressions containing `x + 1` or `x - 1`, and assignments of that back to `x` (the only difference is whether the result value is the value of `x` before or after the assignment). 

*If `e` is an assignable expression with a static type T which is one of `int`, `double` or`num`, then the static type of `e++`, `e--`, `++e` and `--e` is always T. This follows from the current semantics where the type of `e++` and `e--` is the static type of `e`, and `++e` and `--e` are equivalent to `e += 1` or `e -= 1`.*

## Summary

These changes to the special-casing type rules for numbers will ensure that commonly used operations behave nicely. 

The changes cover *all the listed issued*:

* [language#971][] is fixed by including `remainder`.
* [language#597][] is fixed by the improved context type inference.
* [sdk#28249][] is fixed by including `clamp`.
* [sdk#32645][] is fixed by including `remainder`.
* [sdk#39652][] is fixed by including `clamp`.
* [sdk#41559][] is fixed by improved context type inference.

These changes will remove some common pitfalls introduced (or worsened) by removing implicit downcasts with Null Safety.

[language#597]: https://github.com/dart-lang/language/issues/597
[language#971]: https://github.com/dart-lang/language/issues/971
[sdk#28249]: https://github.com/dart-lang/sdk/issues/28249
[sdk#32645]: https://github.com/dart-lang/sdk/issues/32645
[sdk#39652]: https://github.com/dart-lang/sdk/issues/39652
[sdk#41559]: https://github.com/dart-lang/sdk/issues/41559

## Revisions

1.0 – Initial draft version.

1.1 – Addressed initial comments.

1.2 – Initial published version.

1.3 – Simplified rules and fixed unsound edge cases.

1.4 – Only infer static types of `int`, `double`  or `num`, not type variables extending those.
