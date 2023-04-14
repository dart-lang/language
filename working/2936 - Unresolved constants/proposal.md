# Dart Unresolved Constant Values

Author: lrn@google.com <br>
Version: 1.0

See https://github.com/dart-lang/language/issues/2936 for context.

Dart constants, aka. “compile-time constants”, are not as atomic as they might seem. The constant `bool.fromEnvironment` constructor allows the constants in the program to depend on compilation context, and in some compilation strategies (for example modular pre-compilation which shares compile-artifacts between multiple program compilations), those constants are not necessarily available at the *beginning* of compilation.

Which means that everything which depends on such a *value* must be delayed. With patterns, that may include deciding whether a switch is exhaustive (if we don’t know the constant value being checked yet, we don’t know if we have checked for all possible values), and that may then affect type inference and promotion after the switch. But we definitely want to determine static types of expressions in the earliest stages of compilation, otherwise it can block far too much compilation and make the modular compilation less useful.

So, to avoid that kind of problems, we introduce *unresolved constant values*, which are constant values that cannot be used as such in situations where their *value* affects static analysis. Their static type is still known at compile-time, and their value is known *before runtime*, and the values are subject to the usual canonicalization and all other rules related to constants. They just carry an extra bit of information that makes them ineligible in some positions, and which allows type inference to always be able to progress without knowing the precise value.

## Definition

The value from evaluating a constant or potentially constant expression is an *unresolved constant value* iff any of:

* The expression is an invocation of any of the constructors:

  * `String.fromEnvironment`
  * `int.fromEnvironment`
  * `bool.fromEnvironment`
  * `bool.hasEnvironment`

* The expression is a list, set or map literal, and at least one element, key or value expression’s value is an unresolved constant expression.

* The expression is an object expression (a constructor invocation), and at least one of the created object’s instance variables is initialized by an expression whose value is an unresolved constant expression, in one of the following ways:

  * An instance variable has an initializing expression whose value is an unresolved constant expression.
  * An instance variable is initialized using an initializer list assignment whose assigned expression’s value is an unresolved constant value.
  * An instance variable is initialized using an initializing formal, and the current constructor invocation has a corresponding argument expression whose value is an unresolved constant value.
  * An instance variable is initialized using an initializing formal with a default value expression *c1*, the current constructor invocation does not have a corresponding argument expressions, and *c1*‘s value is an unresolved constant value.

* The expression is a non-short-circuiting binary operator expression <code>*c1* *op* *c2*</code> where the value of either or both of *c1* or *c2* is an unresolved constant value. The *op* can be any of: `+`, `-`, `*`, `/`, `~/`, `%`, `&`, `|`, `^`, `>>`, `>>>`, `<<`, `>`, `>=`, `<`, `<=`, `==`, and `!=`.

* The expression is a unary operator expression <code>~*c1*</code>, <code>-*c1*</code> or <code>~*c1*</code>, and the value of *c1* is an unresolved constant value.

* The expression is <code>*c1*.length</code> and the value of *c1* is an unresolved constant value.

* The expression is <code>*c1* ? *c2* : *c3*</code> and either

  * the value of *c1* is an unresolved constant value, 
  * the value of *c1* is `true` and the value of *c2* is an unresolved constant value,  or
  * the value of *c1* is `false` and the value of *c3* is an unresolved constant value.

* The expression is <code>*c1* ?? *c2*</code> and either

  * the value of *c1* is an unresolved constant value, or
  * the value of *c1* is `null` and the value of *c2* is an unresolved constant value.

* The expression is <code>*c1* && *c2*</code> and either

  * the value of *c1* is an unresolved constant value, or
  * the value of *c1* is `true` and the value of *c2* is an unresolved constant value.

* The expression is <code>*c1* || *c2*</code> and either

  * the value of *c1* is an unresolved constant value, or
  * the value of *c1* is `false` and the value of *c2* is an unresolved constant value.

* The expression is <code>identical(*c1*, *c2*)</code> and the value of either or both of *c1* or *c2* is an unresolved constant value.

* The expression is a string literal containing interpolations, and at least one of its interpolation expressions’ value is an unresolved constant value.

* The expression is parenthesized expression <code>(*c1*)</code> where the value of *c1* is an unresolved constant value.

* The expression is <code>*c1* as *T*</code>, <code>*c1* is *T*</code> or <code>*c1* is! *T*</code>, and the value of *c1* is an unresolved constant value.

* The expression is a (potentially constant) constructor parameter variable of a generative `const` constructor, and the _current `const` invocation_ of that constructor has a corresponding argument expression whose value is an unresolved constant value. 
  _The “current `const` invocation” of the constructor is the expression or clause which invokes the constructor, and it can be:_

  * _An object expression, and the argument expressions are in the argument list of that invocation._

  * _A redirect by a redirecting factory constructor, where the argument expressions of the redirection target are the same as those of the invocation of the redirecting constructor._

  * _A redirect by a redirecting generative constructor, where the argument expressions are in the argument list of the redirection clause, `: this(arguments);`._

  * _A super-constructor invocation from a subclass non-redirecting generative constructor, where the argument expressions are either:_

    * _the corresponding argument expression for `super`-parameters in the subclass constructor. Or,_
    * _argument expressions in the argument list of the super-constructor invocation of the initializer list of the sub-classs constructor._

    _Example: `const SubClass(super.foo, int bar) : super(bar: bar);`._

* The expression is a (potentially constant) constructor parameter variable of a generative `const` constructor with a default value expression *c1*, the current `const` invocation of that constructor did not provide a corresponding argument expression, and the value of *c1* is an unresolved constant value.

* The expression is a (possibly qualified) identifier denoting a constant variable declaration, and the value of the initializer expression of that declaration is an unresolved constant value.

## Restrictions

With this definition, we then say that pattern directly depending on an unresolved constant value will not contribute to exhaustiveness.

A pattern does *not contribute to exhaustiveness* iff it is:

* A const pattern where the constant is an unresolved constant value.
* A relational pattern (`< c`, `== c`, etc.) where the operand is an unresolved constant value.
* A map pattern where any key expression's value is an unresolved constant value.
* A composite pattern where at least one of the sub-patterns does not contribute to exhaustiveness.

Cases with such patterns do not exhaust any space in the exhaustiveness algorithm, just like cases with a guard `when` clause.

Further, a condition expression of the form <code>*e1* == *c2*</code> or <code>*e1* != *c2*</code> where the value of *c2* is an unresolved constant value does not cause type promotion, even if *c2* evaluates to `null`. _(If we want to make `const nothing = null;` and `if (maybeValue != nothing) { … }` promote, which it doesn’t do today. It might be viable if we can trust the constant.)_

## Consequences

This is basically a *taint* analysis, determining whether the value of any expression depends on one of the environment-constructors. It doesn’t change the *value* of any constant, it just tracks whether the value is tainted by the environment, and acts specially in *one particular case* &mdash; when such a value occurs in a switch pattern where exhaustiveness matters.

This is a lot of extra complexity in order to keep the `fromEnvironment` constructors constant, while not actually being *real* constants. We have effectively introduced two tiers of constants, compile-time constants and “link-time constants”, which are not available when parsing and type-inferencing the code, but are made available before running the code, when the actual values of the environment are provided.

Since a value being unresolved doesn’t affect the value, just how it can be used, canonicalization needs to have access to the values of link-time constants in order to properly canonicalize them, and objects containing them, with other constant objects that has the same canonicalized state. But we also do want to evaluate and canonicalize the non-tainted values early, so that we can do `identical` and switch-exhaustiveness computations eagerly on those. 

That requires us to have (at least) two complete constant evaluation steps, including canonicalization of the results, which are basically *partial evaluation* for the values that are available, with unevaluated subexpressions for the ones that cannot be resolved yet. If we’re lucky, we can use the same code for both/every step, the only difference is that after the final step, there are no unresolved subexpressions left.

We analyze each invocation of a constant constructor independently, remembering which values flows into which initializer field. Basically, every time we evaluate a constant to a (potentially partially evaluated) result, we remember whether it has unresolved sub-expressions, and pass that around with the value.

We only care about unresolved constant values in relation to type analysis. Usually that only needs the static type of an expression, so the only case where the value affects typing is in determining whether a switch is exhaustive.

The restriction on map pattern keys is there because exhaustiveness may depend on whether the same *value* is checked twice, or two different values are checked ones each. Effectively, the 

We do not add any restrictions on, say, constant map keys or set elements, even though the latter have restrictions on not being allowed to contain the same (identical) key/element twice. That’s because containing the same key/element twice is just a compile-time error which we can report later (at “link” time), but it doesn’t affect type inference. Same for allowing unresolved values as map pattern keys, because map patterns with keys do not affect exhaustiveness anyway.

Examples:

```dart
const truth = !bool.fromEnvironment("not-there"); // true, but unresolved.
const Null nothing = truth ? null : null;
enum Values { e1, e2; }
void main() {
  const myE2 = truth ? Values.e2 : Values.e1;
  switch (Values.e1) { // Error: Not exhaustive, `case myE2:` doesn't count.
      case Values.e1: print("Yep");
      case myE2: print("Nope");
      case Values.e2 when true: print("Still nope");
  }
  switch (true) { /// Error; Not exhaustive.
      case truth: print("Yep");
      case false: print("Nope");
  }
  String? maybeString = "A" as dynamic; // Cast to avoid promoting assignment.
  if (maybeString != nothing) {
    print(maybeString.length); // Error, maybeString is nullable.
  }
}
```
