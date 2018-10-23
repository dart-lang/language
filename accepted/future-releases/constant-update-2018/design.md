# Design Document for Constant Specification Update 2018.
Author: lrn@google.com (@lrhn)

## Motivation and Scope

The Dart 2 and 2.1 language updates introduced a stricter type system, 
the ability to have `assert`s in const constructors, 
and new operators on the `int` and `bool` classes 
(`>>>` on `int` and `|`, `&` and `^` on `bool`).

The stricter type system made some constant expressions hard to write, 
especially for users who disable implicit downcasts. 
For that reason, we want to introduce explicit `as` casts in constant expressions.

The asserts made it obvious that the existing constant expression specification
was overly strict. 
The `&&`, `||` and `?`/`:` operators were not specified to be short-circuiting,
instead they always evaluated all the sub-expressions, 
and introduced a compile-time error if any of them were wrong. 
It made tests like `(string != null && string.length < 4)` unusable. 
We want to fix that, to make boolean expressions more usable.

The new operators on basic system types should also work in constant
contexts, so we want to handle those as well.

On top of that, the Dart 1 specification of potentially constant expressions
had some inconsistencies where an expression was potentially constant only if
it would actually be constant if the constructor parameters were constants
of suitable *types*, but since the constant-ness of an expression depends on
the actual values, not just their type, that question couldn't be answered. 
We also want to clean that up and give a clean, statically checkable
definition of potentially constant expressions.

We do not want to change the behavior of existing constant
or potentially constant expressions.

## Design

The precise defintion of the changes [has landed](https://dart-review.googlesource.com/36220)
in the language specification. 
The following section summarizes the changes.

### Cast Operator
An expression of the form `e as T` is accepted as a potentially 
and compile-time constant experssion 
if `e` is potentially constant or compile-time constant, respectively, 
and `T` is a *compile-time constant type*. 
A compile-time constant type means any type that doesn't contain free
type variables, so the type expression always resolves to the exact
same type.

### Equality Operator
The `==` operator in constant expressions was defined such that `e1 != null` was only allowed
if `e1` had one of the "primitive" system types. Users had to rewrite their code to `!identical(e1, null)`.
This was changed so that the `==` expression is always allowed as long as one of the operands is `null`.

### New Operators
The operator `>>>` is now allowed in a potentially constant expression, 
and it is valid in constant expression if its left and right operands are `int` instances,
and the operation doesn't throw.
The `>>>` operator has not been added to the `int` class yet, so unless the left-hand
operand's static type is `dynamic`, the program will still be rejected. 
When the opeator is added, it should also work in a constant expression.

The `&`, `|` and `^` binary operators are now also allowed when the operands are of 
type `bool`.

### Short-Circuit Operators
The `&&` operator is now short-circuit in constant and potentially constant expressions.
It only attempts to evaluate the second operand if the first operand evaluates to `true`.
This makes `false && (null as String).length` a valid constant expression.
The second operand expression still needs to be a *potentially* constant expression,
which is a new use of potentially constant expressions outside of const constructor
initializer lists.

Likewise the `||` operator only evaluates its second operand if the first evaluates to
`false`, and the second operand must be a potentially constant expression.

The `??` operator only evaluates its second operand if the first evaluates to
`null`, and the second operand must be a potentially constant expression.

Finally, the conditional `?`/`:` operator only evaluates one of its branches, 
depending on whether the condition expression evaluates to `true` or `false`.
The other branch must also be a potenatially constant expression.

### Potentially Constant Expressions

Potentially constant expressions were previously defined in terms of 
"expressions that would be constant if constructor arguments are replaced with 
constants of types matching the context", but something was a constant
expression if it evaluated to a value without throwing. 

That was not a functional definition, 
so it has been changed to an entirely syntactic definition which allows 
some syntactic constructs where the sub-expressions are also potentially constant. 
There is no need to evaluate anything to determine if an expression is potentially constant,
and there is no *type* requirements on the expression.

The potentially constant expression must still satisfy all the same typing rules 
as any other expression, independently of whether it's used at compile time.

If a potentially constant expression is actually evaluated as part of a constant
evaluation, then further type rules apply to the actual objects that are involved.

*Notice*: That also means that there are obivous errors we do not catch.
For example:
```dart
class C {
  final x;
  const C(List<int> x) : x = x.length;
}
```
This class is accepted because `x.length` is a potentially constant expression
independently of typing. However, `x.length` is only a constant expression if
`x` is a `String`, so there is no possible valid constant invocation of this
constructor.
The constructor can still be invoked as a non-constant, though.

### Clarifications

The new specification clarifies that type variables cannot be used 
as compile-time constant types, 
and the type arguments to const constructor invocations and constant literals
must be compile-time constant types.

## Implementation Requirements

The implementation of these changes must happen behind an *experiments flag*.
Tools need to be passed the flag `--enable-experiment=constant-update-2018`
for the changes to be enabled.

The `--enable-experiment` option takes a comma separated list of names of experiments
to enable, and the option can be passed multiple times to a tool, 
enabling any experiment mentioned in any of the option arguments.

The list of avaialable flags at any time is defined by a 
`.dart` file (location and exact content TBD).

Individual tools may have incomplete implementations behind the flag.
When all tools have completely implemented the feature,
the flag will be removed and the feature enabled in the next stable release.

## Summary
The changes here should be entirely incremental, 
existing valid programs should not change behavior.

Some implementations may already have accepted some of the changes,
in particular `const [] == null` is already allowed in some implementations.
We do not *require* that to be put behind a flag again.



