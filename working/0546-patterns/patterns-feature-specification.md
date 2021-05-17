# Patterns Feature Specification

Author: Bob Nystrom
Status: Draft

## Summary

This proposal (along with its smaller sister [records proposal][]) covers a
family of closely-related features that address a number of some of the most
highly-voted user requests. It directly addresses:

[records proposal]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/records-feature-specification.md

*   [Multiple return values](https://github.com/dart-lang/language/issues/68) (281 👍, 6th highest)
*   [Algebraic datatypes](https://github.com/dart-lang/language/issues/349) (249 👍, 7th highest)
*   [Patterns and related features](https://github.com/dart-lang/language/issues/546) (241 👍, 8th highest)
*   [Destructuring](https://github.com/dart-lang/language/issues/207) (201 👍, 9th highest)
*   [Sum types and pattern matching](https://github.com/dart-lang/language/issues/83) (98 👍, 13th highest)
*   [Extensible pattern matching](https://github.com/dart-lang/language/issues/1047) (49 👍, 19th highest)
*   [JDK 12-like switch statement](https://github.com/dart-lang/language/issues/27) (44 👍, 22nd highest)
*   [Switch expression](https://github.com/dart-lang/language/issues/307) (6 👍)
*   [Type patterns](https://github.com/dart-lang/language/issues/170) (4 👍)
*   [Type decomposition](https://github.com/dart-lang/language/issues/169)

(For comparison, the current #1 issue, [Data classes](https://github.com/dart-lang/language/issues/314) has 489 👍.)

In particular, this proposal covers several coding styles and idioms users
would like to express:

### Multiple returns

Functions take not a single parameter but an entire parameter *list* because
you often want to pass multiple values in. Parameter lists give you a flexible,
ad hoc way of aggregating multiple values going into a function, but there is
no equally easy way to aggregate multiple values coming *out*. You're left with
having to create a class, which is verbose and couples any users of the API to
that specific class declaration. Or you pack the values into a List or Map and
end up losing type safety.

Records are sort of like "first class argument lists" and give you a natural
way to return multiple values:

```dart
(double, double) geoCode(String city) {
  var lat = // Calculate...
  var long = // Calculate...

  return (lat, long); // Wrap in record and return.
}
```

### Destructuring

Once you have a few values lumped into a record, you need a way to get them
back out. Record patterns in variable declarations let you *destructure* a
record value by accessing fields and binding the resulting values to new
variables:

```dart
var (lat, long) = geoCode('Aarhus');
print('Location lat:$lat, long:$long');
```

List and map patterns let you likewise destructure those respective collection
types (or any other class that implements `List` or `Map`):

```dart
var list = [1, 2, 3];
var [a, b, c] = list;
print(a + b + c); // 6.

var map = {'first': 1, 'second': 2};
var {'first': a, 'second': b} = map;
print(a + b); // 3.
```

### Algebraic datatypes

You often have a family of related types and an operation that needs specific
behavior for each type. In an object-oriented language, the natural way to model
that is by implementing each operation as an instance method on its respective
type:

```dart
abstract class Shape {
  double calculateArea();
}

class Square implements Shape {
  final double length;
  Square(this.length);

  double calculateArea() => length * length;
}

class Circle implements Shape {
  final double radius;
  Circle(this.radius);

  double calculateArea() => math.pi * radius * radius;
}
```

Here, the `calculateArea()` operation is supported by all shapes by implementing
the method in each class. This works well for operations that feel closely tied
to the class, but it splits the behavior for the entire operation across many
classes and requires you to be able to add new instance methods to those
classes.

Some behavior is more naturally modeled with the operations for all types kept
together in a single function. Today, you can accomplish that using manual type
tests:

```dart
double calculateArea(Shape shape) {
  if (shape is Square) {
    return shape.length + shape.length;
  } else if (shape is Circle) {
    return math.pi * shape.radius * shape.radius;
  } else {
    throw ArgumentError("Unexpected shape.");
  }
}
```

This works, but is verbose and cumbersome. Functional languages like SML
naturally group operations together like this and use pattern matching over
algebraic datatypes to write these functions. Class hierarchies can already
essentially model an algebraic datatype. This proposal provides the pattern
matching constructs to make working with that style enjoyable:

```dart
double calculateArea(Shape shape) =>
  switch (shape) {
    case Square(length: l) => l * l;
    case Circle(radius: r) => math.pi * r * r;
  };
```

As you can see, it also adds an expression form for `switch`.

## Patterns

The core of this proposal is a new category of language construct called a
*pattern*. "Expression" and "statement" are both syntactic categories in the
grammar. Patterns form a third category. Like expressions and statements,
patterns are often composed of other subpatterns.

The basic idea with a pattern is that it:

*   Can be tested against some value to determine if the pattern *matches*. If
    not, the pattern *refutes* the value. Some kinds of patterns, called
    "irrefutable patterns" always match.

*   If (and only if) a pattern does match, the pattern may bind new variables in
    some scope.

Patterns appear inside a number of other constructs in the language. This
proposal extends Dart to allow patterns in:

* Top-level and local variable declarations.
* Static and instance field declarations.
* For loop variable declarations.
* Switch statement cases.
* A new switch expression form's cases.

### Binding and matching patterns

Languages with patterns have to deal with a tricky ambiguity. What does a bare
identifier inside a pattern mean? In some cases, you would like it declare a
variable with that name:

```dart
var (a, b) = (1, 2);
```

Here, `a` and `b` declare new variables. In other cases, you would like
identifiers to be references to constants so that you can refer to a constant
value in the pattern:

```dart
const a = 1;
const b = 2;

switch ([1, 2]) {
  case [a, b]: print("Got 1 and 2");
}
```

Here, `a` and `b` are references to constants and the pattern checks to see if
the value being switched on is equivalent to a list containing those two
elements.

This proposal follows Swift and addresses the ambiguity by dividing patterns
into two general categories *binding patterns* or *binders* and *matching
patterns* or *matchers*. (Binding patterns don't always necessarily bind a
variable, but "binder" is easier to say than "irrefutable pattern".) Binders
appear in irrefutable contexts like variable declarations where the intent is to
destructure and bind variables. Matchers appear in contexts like switch cases
where the intent is also to see if the value matches the pattern or not and
where control flow can occur when the pattern doesn't match.

## Syntax

Going top-down through the grammar, we start with the constructs where patterns
are allowed and then get to the patterns themselves.

### Pattern variable declaration

Most places in the language where a variable can be declared are extended to
allow a pattern, like:

```dart
var (a, [b, c]) = ("str", [1, 2]);
```

Dart's existing C-style variable declaration syntax where the name of a type
itself indicates a variable declaration without any leading keyword makes it
harder to incorporate patterns. We don't want to allow confusing syntax like:

```dart
(int, String) (n, s) = (1, "str");
final (a, b) = (1, 2), c = 3, (d, e);
```

To avoid that, patterns only occur in variable declarations that have a `var`
or `final` keyword. Also, a variable declaration using a pattern can only have
a single declaration "section". No comma-separated multiple declarations like:

```dart
var a = 1, b = 2;
```

Also, declarations with patterns must have an initializer. This is not
restriction since the reason to use patterns in variable declarations is to
destructure values.

Add these new rules:

```
patternDeclaration ::=
  | patternDeclarator declarationBinder '=' expression

patternDeclarator ::= 'late'? ( 'final' | 'var' )
```

**TODO: Should we support destructuring in `const` declarations?**

And incorporate the new rules into these existing rules:

```
topLevelDeclaration ::=
  | // existing productions...
  | patternDeclaration ';' // new

localVariableDeclaration ::=
  | initializedVariableDeclaration ';' // existing
  | patternDeclaration ';' // new

forLoopParts ::=
  | // existing productions...
  | ( 'final' | 'var' ) declarationBinder 'in' expression // new

// Static and instance fields.
declaration ::=
  | // existing productions...
  | 'static' patternDeclaration // new
  | 'covariant'? patternDeclaration // new
```

### Switch statement

We extend switch statements to allow patterns in cases:

```
switchStatement ::= 'switch' '(' expression ')' '{' switchCase* defaultCase? '}'
switchCase      ::= label* caseHead ':' statements
caseHead        ::= 'case' matcher caseGuard?
caseGuard       ::= 'if' '(' expression ')'
```

Allowing patterns in cases significantly increases the expressiveness of what
properties a case can verify, including executing arbitrary user-defined code.
This implies that the order that cases are checked is now potentially
user-visible and an implementation must execute the *first* case that matches.

#### Guard clauses

We also allow an optional *guard clause* to appear after a case. This enables
a switch case to evaluate a secondary arbitrary predicate:

```dart
switch (obj) {
  case [var a, var b] if (a > b):
    print("First element greater");
}
```

#### Implicit break

A long-running annoyance with switch statements is the mandatory `break`
statements at the end of each case body. Dart does not allow fallthrough, so
these `break` statements have no real effect. They exist so that Dart code does
not *appear* to be doing fallthrough to users coming from languages like C that
do allow it. That is a high syntactic tax for limited benefit.

I inspected the 25,014 switch cases in the most recent 1,000 packages on pub
(10,599,303 LOC). 26.40% of the statements in them are `break`. 28.960% of the
cases contain only a *single* statement followed by a `break`. This means
`break` is a fairly large fraction of the statements in all switches for
marginal benefit.

Therefore, this proposal removes the requirement that each non-empty case body
definitely exit. Instead, a non-empty case body implicitly jumps to the end of
the switch after completion. From the spec, remove:

> If *s* is a non-empty block statement, let *s* instead be the last statement
of the block statement. It is a compile-time error if *s* is not a `break`,
`continue`, `rethrow` or `return` statement or an expression statement where the
expression is a `throw` expression.

Empty cases continue to fallthrough to the next case as before:

*This prints "1 or 2":*

```dart
switch (1) {
  case 1:
  case 2:
    print("1 or 2");
}
```

### Switch expression

When you want an `if` statement in an expression context, you can use a
conditional expression (`?:`). There is no expression form for multi-way
branching, so we define a new switch expression. It takes code like this:

```dart
Color shiftHue(Color color) {
  switch (color) {
    case Color.red:
      return Color.orange;
    case Color.orange:
      return Color.yellow;
    case Color.yellow:
      return Color.green;
    case Color.green:
      return Color.blue;
    case Color.blue:
      return Color.purple;
    case Color.purple:
      return Color.red;
  }
}
```

And turns it into:

```dart
Color shiftHue(Color color) {
  return switch (color) {
    case Color.red => Color.orange;
    case Color.orange => Color.yellow;
    case Color.yellow => Color.green;
    case Color.green => Color.blue;
    case Color.blue => Color.purple;
    case Color.purple => Color.red;
  };
}
```

The grammar is:

```
primary ::= thisExpression
  | // existing productions...
  | switchExpression

switchExpression      ::= 'switch' '(' expression ')' '{'
                          switchExpressionCase* defaultExpressionCase? '}'
switchExpressionCase  ::= caseHead '=>' expression ';'
defaultExpressionCase ::= 'default' '=>' expression ';'
```

**TODO: This does not allow multiple cases to share an expression like empty
cases in a switch statement can share a set of statements. Should we support
that?**

Slotting into `primary` means it can be used anywhere any expression can appear
even as operands to unary and binary operators. Many of these uses are ugly, but
not any more problematic than using a collection literal in the same context
since a `switch` expression is always delimited by a `switch` and `}`.

Making it high precedence allows useful patterns like:

```dart
await switch (n) {
  case 1 => aFuture;
  case 2 => anotherFuture;
};

var x = switch (n) {
  case 1 => obj;
  case 2 => another;
}.someMethod();
```

Over half of the switch cases in a large corpus of packages contain either a
single return statement or an assignment followed by a break so there is some
evidence this will be useful.

**TODO: Something like an if statement that matches a single pattern and binds
its variables in the then branch.**

**TODO: Something like a Swift guard-let that matches a single pattern and binds
in the rest of the block or exits if the pattern does not match.**

### Irrefutable patterns ("binders")

Binders are the subset of patterns whose aim is to define new variables in some
scope. A binder can never be refuted. To avoid ambiguity with existing variable
declaration syntax, the outermost pattern where a binding pattern is allowed is
somewhat restricted:

```
declarationBinder ::=
| listBinder
| mapBinder
| recordBinder
```

This means that the outer pattern is always some sort of destructuring pattern
that contains subpatterns. Once nested inside a surrounding binder pattern, you
have access to all of the binders:

```
binder
| declarationBinder
| variableBinder
| castBinder

binders ::= binder ( ',' binder )* ','?
```

#### Type argument binder

Certain places in a pattern where a type argument is expected also allow you to
declare a type parameter variable to destructure and capture a type argument
from the runtime type of the matched object:

```
typeOrBinder ::= typeWithBinder | typePattern

typeWithBinder ::=
    'void'
  | 'Function' '?'?
  | typeName typeArgumentsOrBinders? '?'?
  | recordTypeWithBinder

typeOrBinders ::= typeOrBinder (',' typeOrBinder)*

typeArgumentsOrBinders ::= '<' typeOrBinders '>'

typePattern ::= 'final' identifier

// This the same as `recordType` and its related rules, but with `type`
// replaced with `typeOrBinder`.
recordTypeWithBinder   ::= '(' recordTypeFieldsWithBinder ','? ')'
                         | '(' ( recordTypeFieldsWithBinder ',' )?
                               recordTypeNamedFieldsWithBinder ')'
                         | recordTypeNamedFieldsWithBinder

recordTypeFieldsWithBinder ::= typeOrBinder ( ',' typeOrBinder )*

recordTypeNamedFieldsWithBinder  ::= '{' recordTypeNamedFieldWithBinder
                           ( ',' recordTypeNamedFieldWithBinder )* ','? '}'
recordTypeNamedFieldWithBinder   ::= typeOrBinder identifier
```

**TODO: Can type patterns have bounds?**

The `typeOrBinder` rule is similar to the existing `type` grammar rule, but also
allows `final` followed by an identifier to declare a type variable. It allows
this at the top level of the rule and anywhere a type argument may appear inside
a nested type. For example:

```dart
switch (object) {
  case List<final E>: ...
  case Map<String, final V>: ...
  case Set<List<(final A, b: final B)>>: ...
}
```

**TODO: Do we want to support function types? If so, how do we handle
first-class generic function types?**

#### List binder

Destructures elements from lists.

```
listBinder ::= ('<' typeOrBinder '>' )? '[' binders ']'
```

**TODO: Allow a `...` element in order to match suffixes or ignore extra
elements. Allow capturing the rest in a variable.**

#### Map binder

Destructures values from maps.

```
mapBinder ::= mapTypeArguments? '{' mapBinderEntries '}'

mapTypeArguments ::= '<' typeOrBinder ',' typeOrBinder '>'

mapBinderEntries ::= mapBinderEntry ( ',' mapBinderEntry )* ','?
mapBinderEntry ::= expression ':' binder
```

If it is a compile-time error if any of the entry key expressions are not
constant expressions. It is a compile-time error if any of the entry key
expressions evaluate to equivalent values.

#### Record binder

Record patterns destructure fields from records.

```
recordBinder ::= '(' recordFieldBinders ')'

recordFieldBinders ::= recordFieldBinder ( ',' recordFieldBinder )* ','?
recordFieldBinder ::= ( identifier ':' )? binder
```

**TODO: Allow a `...` element in order to ignore some positional fields while
capturing the suffix.**

#### Variable binder

A variable binding pattern matches the value and binds it to a new variable.
These often occur as subpatterns of a destructuring pattern in order to capture
a destructured value.

```
variableBinder ::= typeWithBinder? identifier
```

#### Cast binder

A cast pattern explicitly casts the matched value to the expected type.

```
castBinder ::= identifier "as" type
```

This is not a type *test* that causes a match failure. This pattern can be used
in irrefutable contexts to assert the expected type of some destructured value.
You rarely need this pattern as the outermost pattern in a declaration because
you can always move the `as` to the initializer expression:

```dart
num n = 1;
var i as int = n; // Instead of this...
var i = n as int; // ...do this.
```

But with destructuring, there is no place in the initializer to insert the cast,
so it's useful to do so inside the pattern:

```dart
(num, Object) record = (1, "s");
var (i as int, s as String) = record;
```

### Refutable patterns ("matchers")

Refutable patterns determine if the value in question matches or meets some
predicate. This answer is used to select appropriate control flow in the
surrounding construct. Matchers can only appear in a context where control flow
can naturally handle the pattern failing to match.

```
matcher ::=
  | literalMatcher
  | constantMatcher
  | wildcardMatcher
  | listMatcher
  | mapMatcher
  | recordMatcher
  | variableMatcher
  | declarationMatcher
  | extractMatcher
```

#### Literal matcher

A literal pattern determines if the value is equivalent to the given literal
value.

```
literalMatcher ::=
  | booleanLiteral
  | numericLiteral
  | stringLiteral
```

Note that list and map literals are not in here. Instead there are list and map
*patterns*. This is technically a breaking change. It means that a list or map
literal in a switch case is now interpreted as a list or map pattern which
destructures its elements at runtime. Before, it was simply treated as value
equality.

```dart
const a = 1;
const b = 2;
var obj = [1, 2]; // Not const.

switch (obj) {
  case [a, b]: print("match"); break;
  default: print("no match");
}
```

In Dart today, this prints "no match". With this proposal, it changes to
"match". However, looking at the 22,943 switch cases in 1,000 pub packages
(10,599,303 lines in 34,917 files), I found zero case expressions that were
collection literals.

#### Constant matcher

Like literals, references to constants determine if the matched value is equal
to the constant's value.

```
constantMatcher ::= qualified ( "." identifier )?
```

The expression is syntactically restricted to be either:

*   **A bare identifier.** In this case, the identifier must resolve to a
    constant declaration in scope.

*   **A prefixed or qualified identifier.** In other words, `a.b`. It must
    resolve to either a top level constant imported from a library with a
    prefix, a static constant in a class, or an enum case.

*   **A prefixed qualified identifier.** Like `a.B.c`. It must resolve to an
    enum case on an enum type that was imported with a prefix.

To avoid ambiguity with wildcard matchers, the identifier cannot be `_`.

**TODO: Do we want to allow other kinds of constant expressions like `1 + 2`?**

#### Wildcard matcher

A wildcard pattern always matches.

```
wildcardMatcher ::= "_"
```

This is useful in places where a subpattern is required but you always want to
succeed. It can function as a "default" pattern for the last case in a pattern
matching statement.

#### List matcher

Matches lists and destructures their elements.

```
listMatcher ::= ('<' typeOrBinder '>' )? '[' matchers ']'
```

**TODO: Allow a `...` element in order to match suffixes or ignore extra
elements. Allow capturing the rest in a variable.**

#### Map matcher

Matches maps and destructures their entries.

```
mapMatcher ::= mapTypeArguments? '{' mapMatcherEntries '}'

mapMatcherEntries ::= mapMatcherEntry ( ',' mapMatcherEntry )* ','?
mapMatcherEntry ::= expression ':' matcher
```

If it is a compile-time error if any of the entry key expressions are not
constant expressions. It is a compile-time error if any of the entry key
expressions evaluate to equivalent values.

#### Record matcher

Destructures fields from records and objects.

```
recordMatcher ::= '(' recordFieldMatchers ')'

recordFieldMatchers ::= recordFieldMatcher ( ',' recordFieldMatcher )* ','?
recordFieldMatcher ::= ( identifier ':' )? matcher
```

**TODO: Add a `...` syntax to allow ignoring positional fields?**

#### Variable matcher

A variable matcher lets a matching pattern also perform variable binding.

```
variableMatcher ::= ( 'final' | 'var' | 'final'? typeWithBinder ) identifier
```

By using variable matchers as subpatterns of a larger matched pattern, a single
composite pattern can validate some condition and then bind one or more
variables only when that condition holds.

#### Declaration matcher

A declaration matchers enables embedding an entire declaration binding pattern
inside a matcher.

```
declarationMatcher ::= ( "var" | "final" ) declarationBinder
```

This is essentially a convenience over using multiple variable matchers. It
spares you from having to write `var` or `final` before every destructured
variable:

```dart
switch (obj) {
  // Instead of:
  case [var a, var b, var c]: ...

  // Can use:
  case var [a, b, c]: ...
}
```

#### Extractor matcher

An extractor combines a type test and record destructuring. It matches if the
object has the named type. If so, it then uses the following record pattern to
destructure fields on the value as that type. This pattern is particularly
useful for writing code in an algebraic datatype style.

```
extractMatcher ::= typeName typeArgumentsOrBinders? "(" matchers ")"
```

It requires the type to be a named type. If you want to use an extractor with a
function type, you can use a typedef.

It is a compile-time error if `typeName` does not refer to a type. It is a
compile-time error if a type argument list is present and does not match the
arity of the type of `typeName`.

**TODO: Some kind of terse null-check pattern that matches a non-null value?**

## Static semantics

A pattern always appears in the context of some value expression that it is
being matched against. In a switch statement or expression, the value expression
is the value being switched on. In a variable declaration, the value is the
initializer:

```dart
var (a, b) = (1, 2);
```

Here, the `(a, b)` pattern is being matched against the expression `(1, 2)`.
When a pattern contains subpatterns, those subpatterns are matched against
values destructured from the value the outer pattern is matched against. Here,
`a` is matched against `1` and `b` is matched against `2`.

When calculating the context type schema or static type of a pattern, any
occurrence of `typePattern` in a type is treated as `Object?`.

### Pattern context type schema

In a non-pattern variable declaration, the variable's type annotation is used
for downwards inference of the initializer:

```dart
List<int> list = []; // Infer <int>[].
```

Patterns extend this behavior:

```dart
var (List<int> list, <num>[a]) = ([], [1]); // Infer (<int>[], <num>[]).
```

To support this, every pattern has a context type schema. This is a type schema
because there may be holes in the type:

```dart
var (a, int b) = ... // Schema is `(?, int)`.
```

#### Named fields in type schemas

Named record fields add complexity to type inference:

```dart
class C<T> {
  T get a => ...
}
var (a: int i) = C();
```

Here, we would ideally infer `C<int>()` for the initializer based on the
type of named field `a` in the destructuring record pattern on the left.
However, there isn't an obvious nominal type we can use for the type schema
that declares `a` without looking at the initializer, which we aren't ready to
infer yet.

We model this by extending the notion of a type schema to also include a
potentially empty set of named getters and their expected type schemas. So,
here, the type schema of the pattern is `Object` augmented with a getter `a` of
type schema `int`. When inferring a type from a given schema, any getters in the
schema become additional constraints placed on the inferred type's corresponding
getters.

The context type schema for a pattern `p` is:

*   **List binder and matcher:** A type schema `List<E>` where:
    *   If `p` has a type argument, then `E` is the type argument.
    *   Else `E` is the greatest lower bound of the type schemas of all element
        subpatterns.

*   **Map binder and matcher:** A type schema `Map<K, V>` where:
    *   If `p` has type arguments then `K`, and `V` are those type arguments.
    *   Else `K` is the least upper bound of the types of all key expressions
        and `V` is the greatest lower bound of the context type schemas of all
        value subpatterns.

*   **Record binder and matcher:**
    *   If the pattern has any positional fields, then the base type schema is
        `Destructure_n_<F...>` where `_n_` is the number of fields and `F...` is
        the context type schema of all of the positional fields.
    *   Else the base type schema is `Object?`.
    *   The base type schema is extended with getters for each named field
        subpattern in `p` where each getter's type schema is the type schema of
        the corresponding subpattern.

*   **Variable binder:**
    *   If `p` has a type annotation, the context type schema is that type.
    *   Else it is `?`.

*   **Variable matcher:**
    *   If `p` has a type annotation, the context type schema is `Object?`.
        *It is not the annotated type because a variable matching pattern can
        be used to downcast from any other type.*
    *   Else it is `?`.

*   **Cast binder**, **wildcard matcher**, and **extractor matcher:** The
    context type schema is `Object?`.

    **todo: should type arguments on an extractor create a type arg constraint?**

*   **Literal matcher** and **constant matcher:** The context type schema is the
    static type of the pattern's value expression.

*   **Declaration matcher:** The context type schema is the same as the context
    type schema of the inner binder.

*We use the greatest lower bound for list elements and map values to ensure that
the outer collection type has a precise enough type to ensure that any typed
field subpatterns do not need to downcast:*

```dart
var [int a, num b] = [1, 2];
```

*Here, the GLB of `int` and `num` is `int`, which ensures that neither `int a`
nor `num b` need to downcast their respective fields.*

### Pattern static type

Once the value a pattern is matched against has a static type (which means
downwards inference on it using the pattern's context type schema is complete),
we can calculate the static type of the pattern.

The value's static type is used to do upwards type inference on the pattern for
patterns in variable declarations and switches. Also, a pattern's static type
may be used for "downwards" ("inwards"?) inference of a pattern's subpatterns
in the same way that a collection literal's type argument is used for inference
on the collection's elements.

For example:

```dart
var <int>[a, b] = <num>[1, 2]; // List<int> (and compile error)
var [a, b] = <num>[1, 2]; // List<num>, a is num, b is num
var [int a, b] = <num>[1, 2]; // List<int>
```

Putting this together, it means the process of completely inferring the types of
a construct using patterns works like:

1. Calculate the context type schema of the pattern.
2. Use that in downwards inference to calculate the type of the value.
3. Use that to calculate the static type of a pattern.

The static type of a pattern `p` being matched against a value of type `M` is:

*   **List binder and matcher:**
    1.  Calculate the value's element type `E`:
        1.  If `M` implements `List<T>` for some `T` then `E` is `T`.
        2.  Else if `M` is `dynamic` then `E` is `dynamic`.
        3.  Else compile-time error. *It is an error to destructure a non-list
            value with a list pattern.*
    2.  Calculate the static types of each element subpattern using `E` as the
        matched value type. *Note that we calculate a single element type and
        use it for all subpatterns. In:*

        ```dart
        var [a, b] = [1, bool];
        ```

        *both `a` and `b` use `Object` as their matched value type.*

    3.  The static type of `p` is `List<S>` where:
        1.  If `p` has a type argument, `S` is that type. *If the list pattern
            has an explicit type argument, that wins.*
        2.  Else if the greatest lower bound of the types of the element
            subpatterns is not `?`, then `S` is that type. *Otherwise, if we
            can infer a type bottom-up from the from the subpatterns, use that.*
        3.  Else `S` is `E`. *Otherwise, infer the type from the matched value.*
    4.  It is a compile-time error if any element subpattern's type is not a
        supertype of `S`. *This ensures an element does not need to downcast
        an element from the matched value. For example:*

        ```dart
        var <num>[int i] = 1.2; // Compile-time error.
        ```

*   **Map binder and matcher:**
    1.  Calculate the value's entry key type `K` and value type `V`:
        1.  If `M` implements `Map<K, V>` for some `K` and `V` then use those.
        2.  Else if `M` is `dynamic` then `K` and `V` are `dynamic`.
        3.  Else compile-time error. *It is an error to destructure a non-map
            value with a map pattern.*
    2.  Calculate the static types of each value subpattern using `V` as the
        matched value type. *Like lists, we calculate a single value type and
        use it for all value subpatterns:*

        ```dart
        var {1: a, 2: b} = {1: "str", 2: bool};
        ```

        *Here, both `a` and `b` use `Object` as the matched value type.*
    3.  The static type of `p` is `Map<L, W>` where:
        1.  If `p` has type arguments, `L` and `W` are those type arguments.
            *If the map pattern is explicitly typed, that wins.*
        2.  Else `L` is the least upper bound of the types of all key
            expressions. If the greatest lower bound of all value subpattern
            types is not `?` then `W` is that type. Otherwise `W` is `V`.
    4.  It is a compile-time error if any value subpattern's type is not a
        supertype of `W`. *This ensures a value subpattern does not need to
        downcast an entry from the matched value. For example:*

        ```dart
        var <int, Object>{1: String s} = {1: false}; // Compile-time error.
        ```
*   **Record binder and matcher:**
    1.  If `p` has any position fields, then the static type of `p` is
        `Destructure_n_<args...>` where `_n_` is the number of positional
        fields and `args...` is a type argument list built from the static
        types of the positional field subpatterns, in order.
    2.  Else the static type of `p` is `Object?`. *You can destructure named
        fields on an object of any type by calling its getters.*
    3.  If `M` is not `dynamic`:
        *   It is a compile-time error if `p` has a field with name `n` and `M`
            does not define a getter named `n`.
        *   It is a compile-time error if `p` has a field named `n` and the type
            of getter `n` in `M` is not a subtype of the subpattern `n`'s type.

*   **Variable binder:**
    1.  If the variable has a type annotation, the type of `p` is that type.
    2.  Else the type of `p` is `M`. *This indirectly means that an untyped
        variable pattern can have its type inferred from the type of a
        superpattern:

        ```dart
        var <(num, Object)>[(a, b)] = [(1, true)]; // a is num, b is Object.
        ```

        *The pattern's context type schema is `List<(num, Object>)`. Downwards
        inference uses that to infer `List<(num, Object>)` for the initializer.
        That inferred type is then destructured and used to infer `num` for `a`
        and `Object` for `b`.*

*   **Cast binder**, **wildcard matcher**, and **extractor matcher:** The
    static type of `p` is `Object?`. *Wildcards accept all types. Casts and
    extractors exist to check types at runtime, so statically accept all types.*

*   **Literal matcher** and **constant matcher:** The static type of `p` is the
    static type of the pattern's value expression.

*   **Declaration matcher:** The static type of `p` is the static type of the
    inner binder.

It is a compile-time error if `M` is not a subtype of `p`.

### Variables and scope

Patterns often exist to introduce new bindings. Type patterns introduce type
variables and other patterns introduce normal variables. The variables a
patterns binds depend on what kind of pattern it is:

*   **Type pattern:** Type argument patterns (i.e. `typePattern` in the grammar)
    that appear anywhere in some other pattern introduce new *type* variables
    whose name is the type pattern's identifier. Type variables are always
    final.

*   **List binder**, **list matcher**, **map binder**, **map matcher**, **record
    binder**, **record matcher:** These do not introduce variables themselves
    but may contain type patterns and subpatterns that do.

*   **Literal matcher**, **constant matcher**, **wildcard matcher:** These do
    not introduce any variables.

*   **Variable binder:** May contain type argument patterns. Introduces a
    variable whose name is the pattern's identifier unless the identifier is
    `_`. *We always treat `_` as non-binding in patterns.*

    The variable is final if the surrounding pattern variable declaration or
    declaration matcher has a `final` modifier. The variable is late if it is
    inside a pattern variable declaration marked `late`.

*   **Variable matcher:** May contain type argument patterns. Introduces a
    variable whose name is the pattern's identifier. The variable is final if
    the pattern has a `final` modifier, otherwise it is assignable *(annotated
    with `var` or just a type annotation)*. The variable is never late.

*   **Cast binder:** Introduces a variable whose name is the pattern's
    identifier. The variable is final if the surrounding pattern variable
    declaration or declaration matcher has a `final` modifier. The variable is
    late if it is inside a pattern variable declaration marked `late`.

*   **Declaration matcher:** The `final` or `var` keyword establishes whether
    the binders nested inside this create final or assignable variables and
    then introduces those variables.

*   **Extractor matcher:** May contain type argument patterns and introduces
    all of the variables of its subpatterns.

All variables (except for type variables) declared in an instance field pattern
variable declaration are covariant if the pattern variable declaration is marked
`covariant`. Variables declared in an field pattern declaration define getters
on the surrounding class and setters if the field pattern declaration is not
`final`.

The scope where a pattern's variables are declared depends on the construct
that contains the pattern:

*   **Top-level pattern variable declaration:** The top-level library scope.
*   **Local pattern variable declaration:** The rest of the block following
    the declaration.
*   **For loop pattern variable declaration:** The body of the loop and the
    condition and increment clauses in a C-style for loop.
*   **Static field pattern variable declaration:** The static scope of the
    enclosing class.
*   **Instance field pattern variable declaration:** The instance scope of the
    enclosing class.
*   **Switch statement case:** The guard clause and the statements of the
    subsequent non-empty case body.
*   **Switch expression case:** The guard clause and the case expression.

Multiple switch case patterns may share the same variable scope if their case
bodies are empty:

```dart
switch (obj) {
  case [int a, int b]:
  case {"a": int a, "b": int b}:
    print(a + b); // OK.

  case [int a]:
  case (String a): // Error.
    break;
}
```

This would normally be a name collision, but we make an exception to allow this.
However, it is a compile-time error if all switch case patterns that share a
body do not all define the exact same variables with the exact same types.

*Aside from this special case, note that since all variables declared by a
pattern and its subpattern go into the same scope, it is an error if two
subpatterns declare a variable with the same name.*

### Type promotion

**TODO: Specify how pattern matching may show that existing variables have some
type.**

### Exhaustiveness and reachability

A switch is *exhaustive* if all possible values of the matched value's type
will definitely match at least one case, or there is a default case. Dart
currently shows a warning if a switch statement on an enum type does not have
cases for all enum values (or a default).

This is helpful for code maintainance: when you add a new value to an enum
type, the language shows you every switch statement that may need a new case
to handle it.

This checking is even more important with this proposal. Exhaustiveness checking
is a key part of maintaining code written in an algebraic datatype style. It's
the functional equivalent of the error reported when a concrete class fails to
implement an abstract method.

Exhaustiveness checking is *critical* for switch *expressions:*

```dart
int i = switch ("str") {
  case "a" => 1;
  case "oops" => 2;
};
```

An expression must reliably evaluate to *some* value, unlike statements where
you can simply do nothing if no case matches. We could throw a runtime error if
no case matches, but that's generally not useful for users.

Exhaustiveness checking is more complex in the presence of pattern matching and
destructuring:

```dart
bool xor(bool a, bool b) =>
    switch ((a, b)) {
      case (true, true) => false;
      case (true, false) => true;
      case (false, true) => true;
      case (false, false) => false;
    };
```

This is exhaustive, but it's not obvious how this would be determined. A
related problem is unreachable patterns:

```dart
switch (obj) {
  case num n: print("number");
  case int i: print("integer");
}
```

Here, the second case will never match because any value that could match it
will be caught by the first case. It's not necessary to detect unreachable
patterns for correctness, but it helps users if we can since the case is dead
code.

A trivial way to ensure all switches are exhaustive is to require a default
case or case containing only a wildcard pattern (with no guard).

**TODO: See if we can detect exhaustive and unreachable cases more precisely.
See: http://moscova.inria.fr/~maranget/papers/warn/index.html**

## Runtime semantics

### Execution

Most of the runtime behavior is defined in the "matching" section below, but
the constructs where patterns appear have their own (hopefully obvious)
behavior.

#### Pattern variable declaration

1.  Evaluate the initializer expression producing a value `v`.

2.  Match `v` against the declaration's pattern.

#### Switch statement

1.  Evaluate the switch value producing `v`.

2.  For each case:

    1.  Match the case's pattern against `v`. If the match fails then continue
        to the next case (or default clause or exit the switch if there are no
        other cases).

    2.  If there is a guard clause, evaluate it. If it does not evaluate to
        a Boolean, throw a runtime exception. If it evaluates to `false`,
        continue to the next case (or default or exit).

    3.  Execute the nearest non-empty case body at or following this case.
        *You're allowed to have multiple empty cases where all preceding
        ones share the same body with the last case.*

    4.  Exit the switch statement. *An explicit `break` is no longer
        required.*

3.  If no case pattern matched and there is a default clause, execute the
    statements after it.

#### Switch expression

1.  Evaluate the switch value producing `v`.

2.  For each case:

    1.  Match the case's pattern against `v`. If the match fails then continue
        to the next case (or default clause if there are no other cases).

    2.  If there is a guard clause, evaluate it. If it does not evaluate to
        a Boolean, throw a runtime exception. If it evaluates to `false`,
        continue to the next case (or default clause).

    3.  Evaluate the expression after the case and yield that as the result of
        the entire switch expression.

3.  If no case pattern matched and there is a default clause, execute the
    expression after it and yield that as the result of the entire switch
    expression.

### Matching (refuting and destructuring)

At runtime, a pattern is matched against a value. This determines whether or not
the match *fails* and the pattern *refutes* the value. If the match succeeds,
the pattern may also *destructure* data from the object or *bind* variables.

Most refutable patterns (matchers) are syntactically restricted to only appear
in a context where refutation is meaningful and control flow can occur. If the
pattern refutes the value, then no code where any variables defined by the
pattern are in scope will be executed. Specifically, if a pattern in a switch
case is refuted, execution proceeds to the next case.

If a pattern match failure occurs in pattern variable declaration, a runtime
exception is thrown. *(This can happen, for example, when matching against a
variable of type `dynamic`.)*

To match a pattern `p` against a value `v`:

*   **Type pattern:** Always matches. Binds the corresponding type argument of
    the runtime type of `v` to the pattern's type variable.

*   **List binder** and **list matcher:**

    1.  If `v` does not implement `List<T>` for some `T`, then the match fails.
        *This may happen at runtime if `v` has static type `dynamic`.*

    2.  If the length of the list determined by calling `length` is not equal to
        the number of subpatterns, then the match fails.

    3.  Otherwise, extracts a series of elements from `v` using `[]` and matches
        them against the corresponding subpatterns. The match succeeds if all
        subpatterns match.

*   **Map binder** and **map matcher:**

    1.  If the value's type does not implement `Map<K,V>` for some `K` and `V`,
        then the match fails. Otherwise, tests the entry patterns:

    2.  For each `mapBinderEntry` or `mapMatcherEntry`:

        1.  Evaluate key `expression` to `key` and call `containsKey()` on
            the value. If this returns `false`, the map does not match.

        3.  Otherwise, evaluate `v[key]` and match the resulting value against
            this entry's value subpattern. If it does not match, the map does
            not match.

    3.  If all entries match, the map matches.

    *Note that, unlike with lists, a matched map may have additional entries
    that are not checked by the pattern.*

*   **Record matcher** and **record binder:**

    1.  If the pattern has positional fields:

        1.  If `v` does not implement the appropriate `Destructure_n_<...>`
            interface instantiaged with type arguments based on the positional
            fields' static types, then the match fails.

        2.  For each field `f` in `p`:

            1.  Call the corresponding getter on `v` to get result `r`. If `f`
                is a positional field, then the getter is named `field_n_` where
                `_n_` is the zero-based index of the positional field, ignoring
                other named fields. If `f` is named, then the getter has the
                same name as `f`.

                *If `v` has type `dynamic`, this getter call may throw a
                NoSuchMethodError, which we allow to propagate instead of
                treating that as a match failure.*

            2.  Match the subpattern of `f` against `r`. If the match fails,
                the record match fails.

        3.  If all field subpatterns match, the record pattern matches.

*   **Variable binder**, and **variable matcher:**

    1.  If `v` is not a subtype of `p` then the match fails. *This is a
        deliberate failure when using a typed variable pattern in a switch in
        order to test a value's type. In a binder, this can only occur on a
        failed downcast from `dynamic` and becomes a runtime exception.*

    2.  Otherwise, bind the variable's identifier to `v` and the match succeeds.

*   **Cast binder:**

    1.  If `v` is not a subtype of `p` then throw a runtime exception. *Note
        that we throw even if this appears in a refutable context. The intent
        of this pattern is to assert that a value *must* have some type.*

    2.  Otherwise, bind the variable's identifier to `v`. The match always
        succeeds (if it didn't throw).

*   **Literal matcher**, **constant matcher:** The pattern matches if `o == v`
    evaluates to `true` where `o` is the pattern's value.

    **TODO: Should this be `v == o`?**

*   **Wildcard matcher:** Always succeeds.

*   **Declaration matcher:** Match `v` against the binder subpattern. Always
    succeeds.

*   **Extractor matcher:**

    1.  If `v` is not a subtype of the extractor pattern's type, then the
        match fails.

    2.  Otherwise, match `v` against the subpatterns of `p` as if it were a
        record pattern.

**TODO: Define order of evaluation and specify how much freedom compilers have
to reorder or skip tests. What happens if the various desugared operations have
side effects?**

### Late and static variables in pattern declaration

If a pattern variable declaration is marked `late` or a static variable
declaration has a pattern, then all variables declared by the pattern are late.
Evaluation of the initializer expression is deferred until any variable in the
pattern is accessed. When that occurs, the initializer is evaluated and all
pattern destructuring occurs and all variables become initialized.

*If you touch *any* of the variables, they *all* get initialized:*

```dart
int say(int n) {
  print(n);
  return n;
}

main() {
  late var (a, b) = (say(1), say(2));
  a;
  print("here");
  b;
}
```

*This prints "1", "2", "here".*
