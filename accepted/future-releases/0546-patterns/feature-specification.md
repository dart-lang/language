# Patterns Feature Specification

Author: Bob Nystrom

Status: Accepted

Version 2.16 (see [CHANGELOG](#CHANGELOG) at end)

Note: This proposal is broken into a couple of separate documents. See also
[records][] and [exhaustiveness][].

[records]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/records/records-feature-specification.md

## Summary

This proposal covers a family of closely-related features that address a number
of some of the most highly-voted user requests. It directly addresses:

*   [Multiple return values](https://github.com/dart-lang/language/issues/68) (495 👍, 4th highest)
*   [Algebraic datatypes](https://github.com/dart-lang/language/issues/349) (362 👍, 10th highest)
*   [Patterns and related features](https://github.com/dart-lang/language/issues/546) (379 👍, 9th highest)
*   [Destructuring](https://github.com/dart-lang/language/issues/207) (394 👍, 7th highest)
*   [Sum types and pattern matching](https://github.com/dart-lang/language/issues/83) (201 👍, 11th highest)
*   [Extensible pattern matching](https://github.com/dart-lang/language/issues/1047) (69 👍, 23rd highest)
*   [JDK 12-like switch statement](https://github.com/dart-lang/language/issues/27) (79 👍, 19th highest)
*   [Switch expression](https://github.com/dart-lang/language/issues/307) (28 👍)
*   [Type decomposition](https://github.com/dart-lang/language/issues/169)

(For comparison, the current #1 issue, [Data classes](https://github.com/dart-lang/language/issues/314) has 824 👍.)

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

You can also destructure and assign to existing variables:

```dart
var (a, b) = ('left', 'right');
(b, a) = (a, b); // Swap!
print('$a $b'); // Prints "right left".
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
    Square(length: var l) => l * l,
    Circle(radius: var r) => math.pi * r * r
  };
```

As you can see, it also adds an expression form for `switch` that doesn't
require `case`.

## Patterns

The core of this proposal is a new category of language construct called a
*pattern*. "Expression" and "statement" are both syntactic categories in the
grammar. Patterns form a third category. Like expressions and statements,
patterns are often composed of other subpatterns.

The basic ideas with patterns are:

*   Some can be tested against a value to determine if the pattern *matches* the
    value. If not, the pattern *refutes* the value. Other patterns, called
    *irrefutable* always match.

*   Some patterns, when they match, *destructure* the matched value by pulling
    data out of it. For example, a list pattern extracts elements from the list.
    A record pattern destructures fields from the record.

*   Variable patterns bind new variables to values that have been matched or
    destructured. The variables are in scope in a region of code that is only
    reachable when the pattern has matched.

This gives you a compact, composable notation that lets you determine if an
object has the form you expect, extract data from it, and then execute code only
when all of that is true.

Before introducing each pattern in detail, here is a summary with some examples:

| Kind | Examples |
| ---- |-------- |
| [Logical-or][logicalOrPattern] | `subpattern1 \| subpattern2` |
| [Logical-and][logicalAndPattern] | `subpattern1 & subpattern2` |
| [Relational][relationalPattern] | `== expression`<br>`< expression` |
| [Cast][castPattern] | `foo as String` |
| [Null-check][nullCheckPattern] | `subpattern?` |
| [Null-assert][nullAssertPattern] | `subpattern!` |
| [Constant][constantPattern] | `123`, `null`, `'string'`<br>`math.pi`, `SomeClass.constant`<br>`const Thing(1, 2)`, `const (1 + 2)` |
| [Variable][variablePattern] | `foo`, `var bar`, `String str`, `_`, `int _` |
| [Parenthesized][parenthesizedPattern] | `(subpattern)` |
| [List][listPattern] | `[subpattern1, subpattern2]` |
| [Map][mapPattern] | `{"key": subpattern1, someConst: subpattern2}` |
| [Record][recordPattern] | `(subpattern1, subpattern2)`<br>`(x: subpattern1, y: subpattern2)` |
| [Object][objectPattern] | `SomeClass(x: subpattern1, y: subpattern2)` |

[logicalOrPattern]: #logical-or-pattern
[logicalAndPattern]: #logical-and-pattern
[relationalPattern]: #relational-pattern
[castPattern]: #cast-pattern
[nullCheckPattern]: #null-check-pattern
[nullAssertPattern]: #null-assert-pattern
[constantPattern]: #constant-pattern
[variablePattern]: #variable-pattern
[parenthesizedPattern]: #parenthesized-pattern
[listPattern]: #list-pattern
[mapPattern]: #map-pattern
[recordPattern]: #record-pattern
[objectPattern]: #object-pattern

Here is the overall grammar for the different kinds of patterns:

```
pattern               ::= logicalOrPattern

logicalOrPattern      ::= ( logicalOrPattern '|' )? logicalAndPattern
logicalAndPattern     ::= ( logicalAndPattern '&' )? relationalPattern
relationalPattern     ::= ( equalityOperator | relationalOperator) relationalExpression
                        | unaryPattern

unaryPattern          ::= castPattern
                        | nullCheckPattern
                        | nullAssertPattern
                        | primaryPattern

primaryPattern        ::= constantPattern
                        | variablePattern
                        | parenthesizedPattern
                        | listPattern
                        | mapPattern
                        | recordPattern
                        | objectPattern
```

As you can see, logical-or patterns (`|`) have the lowest precedence; then
logical-and patterns (`&`), then the postfix *unary patterns* cast (`as`),
null-check (`?`), and null-assert (`!`) patterns; followed by the remaining
highest precedence primary patterns.

The individual patterns are:

### Logical-or pattern

```
logicalOrPattern ::= ( logicalOrPattern '|' )? logicalAndPattern
```

A pair of patterns separated by `|` matches if either of the branches match.
This can be used in a switch expression or statement to have multiple cases
share a body:

```dart
var isPrimary = switch (color) {
  Color.red | Color.yellow | Color.blue => true,
  _ => false
};
```

Even in switch statements, which allow multiple empty cases to share a single
body, a logical-or pattern can be useful when you want multiple patterns to
share a guard:

```dart
switch (shape) {
  case Square(size: var s) | Circle(size: var s) when s > 0:
    print('Non-empty symmetric shape');
  case Square() | Circle():
    print('Empty symmetric shape');
  default:
    print('Asymmetric shape');
}
```

A logical-or pattern does not have to appear at the top level of a pattern. It
can be nested inside a destructuring pattern:

```dart
switch (list) {
  // Matches a two-element list whose first element is 'a' or 'b':
  case ['a' | 'b', var c]):
}
```

A logical-or pattern may match even if one of its branches does not. That means
that any variables in the non-matching branch would not be initialized. To avoid
problems stemming from that, the following restrictions apply:

*   The two branches must define the same set of variables. This is specified
    more precisely under "Variables and scope".

*   If the left branch matches, the right branch is not evaluated. This
    determines *which* value the variable gets if both branches would have
    matched. In that case, it will always be the value from the left branch.

### Logical-and pattern

```
logicalAndPattern ::= ( logicalAndPattern '&' )? relationalPattern
```

A pair of patterns separated by `&` matches only if *both* subpatterns match.
Unlike logical-or patterns, the variables defined in each branch must *not*
overlap, since the logical-and pattern only matches if both branches do and
the variables in both branches will be bound.

If the left branch does not match, the right branch is not evaluated. *This only
matters because patterns may invoke user-defined methods with visible side
effects.*

### Relational pattern

```
relationalPattern ::= ( equalityOperator | relationalOperator) relationalExpression
```

A relational pattern lets you compare the matched value to a given constant
using any of the equality or relational operators: `==`, `!=`, `<`, `>`, `<=`,
and `>=`. The pattern matches when calling the appropriate operator on the
matched value with the constant as an argument returns `true`. It is a
compile-time error if `relationalExpression` is not a valid constant expression.

The comparison operators are useful for matching on numeric ranges, especially
when combined with `&`:

```dart
String asciiCharType(int char) {
  const space = 32;
  const zero = 48;
  const nine = 57;

  return switch (char) {
    < space => 'control',
    == space => 'space',
    > space & < zero => 'punctuation',
    >= zero & <= nine => 'digit'
    // Etc...
  }
}
```

### Cast pattern

```
castPattern ::= primaryPattern 'as' type
```

A cast pattern is similar to an object pattern in that it checks the matched
value against a given type. But where an object pattern is *refuted* if the
value doesn't have that type, a cast pattern *throws*. Like the null-assert
pattern, this lets you forcibly assert the expected type of some destructured
value.

This isn't useful as the outermost pattern in a declaration since you can always
move the `as` to the initializer expression, but when destructuring there is no
place in the initializer to insert the cast. This pattern lets you insert the
cast as values are being pulled out by the pattern:

```dart
(num, Object) record = (1, "s");
var (i as int, s as String) = record;
```

### Null-check pattern

```
nullCheckPattern ::= primaryPattern '?'
```

A null-check pattern matches if the value is not null, and then matches the
inner pattern against that same value. Because of how type inference flows
through patterns, this also provides a terse way to bind a variable whose type
is the non-nullable base type of the nullable value being matched:

```dart
String? maybeString = ...
switch (maybeString) {
  case var s?:
    // s has type non-nullable String here.
}
```

Using `?` to match a value that is *not* null seems counterintuitive. In truth,
I have not found an ideal syntax for this. The way I think about `?` is that it
describes the test it performs. Where a list pattern tests whether the value is
a list, a `?` tests whether the value is null. However, unlike other patterns,
it matches when the value is *not* null, because matching on null isn't
useful&mdash;you could always just use a `null` constant pattern for that.

Swift [uses the same syntax for a similar feature][swift null check].

[swift null check]: https://docs.swift.org/swift-book/ReferenceManual/Patterns.html#ID520

### Null-assert pattern

```
nullAssertPattern ::= primaryPattern '!'
```

A null-assert pattern is similar to a null-check pattern in that it permits
non-null values to flow through. But a null-assert *throws* if the matched
value is null. It lets you forcibly *assert* that you know a value shouldn't
be null, much like the corresponding `!` null-assert expression.

This lets you eliminate null in variable declarations where a refutable pattern
isn't allowed:

```dart
(int?, int?) position = ...

// We know if we get here that the coordinates should be present:
var (x!, y!) = position;
```

Or where you don't want null to be silently treated as a match failure, as in:

```dart
List<String?> row = ...

// If the first column is 'user', we expect to have a name after it.
switch (row) {
  case ['user', var name!]:
    // name is a non-nullable string here.
}
```

### Constant pattern

```
constantPattern ::= booleanLiteral
                  | nullLiteral
                  | numericLiteral
                  | stringLiteral
                  | identifier
                  | qualifiedName
                  | constObjectExpression
                  | 'const' typeArguments? '[' elements? ']'
                  | 'const' typeArguments? '{' elements? '}'
                  | 'const' '(' expression ')'
```

A constant pattern determines if the matched value is equal to the constant's
value. We don't allow all expressions here because many expression forms
syntactically overlap other kinds of patterns. We avoid ambiguity while
supporting terse forms of the most common constant expressions like so:

*   Simple "primitive" literals like Booleans and numbers are valid patterns
    since they aren't ambiguous.

*   Named constants are also allowed because they aren't ambiguous. That
    includes simple identifiers like `someConstant`, prefixed constants like
    `some_library.aConstant`, static constants on classes like
    `SomeClass.aConstant`, and prefixed static constants like
    `some_library.SomeClass.aConstant`. *Simple identifiers would be ambiguous
    with variable patterns that aren't marked with `var`, `final`, or a type,
    but unmarked variable patterns are only allowed in irrefutable contexts
    where constant patterns are prohibited.*

*   List literals are ambiguous with list patterns, so we only allow list
    literals explicitly marked `const`. Likewise with set and map literals
    versus map patterns.

*   Constructor calls are ambiguous with object patterns, so we require const
    constructor calls to be explicitly marked `const`.

*   Other constant expressions must be marked `const` and surrounded by
    parentheses. This avoids ambiguity with null-assert, logical-or, and
    logical-and patterns. It also makes future extensions to patterns and
    expressions less likely to collide.

Let the *value* of a constant pattern be the `expression` inside `'const' '('
expression ')'` or the entire pattern if the pattern has any other form. *This
awkward definition is because `const (1 + 2)` is not a valid expression but is a
valid constant pattern.*

It is a compile-time error if a constant pattern's value is not a valid constant
expression.

### Variable pattern

```
variablePattern ::= ( 'var' | 'final' | 'final'? type )? identifier
```

A variable pattern binds the matched value to a new variable. These usually
occur as subpatterns of a destructuring pattern in order to capture a
destructured value.

```dart
var (a, b) = (1, 2);
```

Here, `a` and `b` are variable patterns and end up bound to `1` and `2`,
respectively.

The pattern may have a type annotation in order to only match values of the
specified type. If the type annotation is omitted, the variable's type is
inferred and the pattern matches all values.

```dart
switch (record) {
  case (int x, String s):
    print('First field is int $x and second is String $s.');
}
```

*There are some restrictions on when `var` and `final` can and can't be used.
They are specified later in the "Pattern context" section.*

#### Wildcards

If the variable's name is `_`, it doesn't bind any variable. This "wildcard"
name is useful as a placeholder in places where you need a subpattern in order
to destructure later positional values:

```dart
var list = [1, 2, 3];
var [_, two, _] = list;
```

The `_` identifier can also be used with a type annotation when you want to test
a value's type but not bind the value to a name:

```dart
switch (record) {
  case (int _, String _):
    print('First field is int and second is String.');
}
```

### Parenthesized pattern

```
parenthesizedPattern ::= '(' pattern ')'
```

Like parenthesized expressions, parentheses in a pattern let you control pattern
precedence and insert a lower precedence pattern where a higher precedence one
is expected.

### List pattern

```
listPattern         ::= typeArguments? '[' listPatternElements? ']'
listPatternElements ::= listPatternElement ( ',' listPatternElement )* ','?
listPatternElement  ::= pattern | restPattern
restPattern         ::= '...' pattern?
```

A list pattern matches an object that implements `List` and extracts elements by
position from it.

It is a compile-time error if:

*   `typeArguments` is present and has more than one type argument.

*   There is more than one `restPattern` element in the list pattern. *It can
    appear anywhere in the list, but there can only be zero or one.*

#### Rest patterns

A list pattern may contain a *rest element* which allows matching lists of
arbitrary lengths. If a rest element is present and has a subpattern, all of the
elements not matched by other subpatterns are collected into a new list and that
list is matched against the rest subpattern.

```dart
var [a, b, ...rest, c, d] = [1, 2, 3, 4, 5, 6, 7];
print('$a $b $rest $c $d'); // Prints "1 2 [3, 4, 5] 6 7".
```

### Map pattern

```
mapPattern        ::= typeArguments? '{' mapPatternEntries? '}'
mapPatternEntries ::= mapPatternEntry ( ',' mapPatternEntry )* ','?
mapPatternEntry   ::= expression ':' pattern | '...'
```

A map pattern matches values that implement `Map` and accesses values by key
from it.

It is a compile-time error if:

*   `typeArguments` is present and there are more or fewer than two type
    arguments.

*   Any of the entry key expressions are not constant expressions.

*   If any two keys in the map both have primitive `==` methods, then it is a
    compile-time error if they are equal according to their `==` operator. *In
    cases where keys have types whose equality can be checked at compile time,
    we report errors if there are redundant keys. But we don't require the keys
    to have primitive equality for flexibility. In map patterns where the keys
    don't have primitive equality, it is possible to have redundant keys and the
    compiler won't detect it.*

*   There is more than one `...` element in the map pattern.

*   The `...` element is not the last element in the map pattern.

### Rest patterns

Like lists, map patterns can also have a rest pattern. However, there's no
well-defined notion of a map "minus" some set of matched entries. Thus, the
rest pattern doesn't allow a subpattern to capture the "remaining" entries.

Also, there is no ordering to entries in a map, so we only allow the `...` to
appear as the last element. Appearing anywhere else would send a confusing,
meaningless signal.

In practice, this means that the only purpose of `...` in a map pattern is to
allow matching a map that contains extra entries, while ignoring those entries.
By default, a map pattern only matches if the map's length is exactly the same
as the number of entry subpatterns. Adding a `...` element allows the map
pattern to match if the map's length is *at least* the number of (non-rest)
entry subpatterns (and all of those subpatterns match).

### Record pattern

```
recordPattern         ::= '(' patternFields? ')'
patternFields         ::= patternField ( ',' patternField )* ','?
patternField          ::= ( identifier? ':' )? pattern
```

A record pattern matches a record object and destructures its fields. If the
value isn't a record with the same shape as the pattern, then the match fails.
Otherwise, the field subpatterns are matched against the corresponding fields in
the record.

Field subpatterns can be in one of three forms:

*   A bare `pattern` destructures the corresponding positional field from the
    record and matches it against `pattern`.

*   An `identifier: pattern` destructures the named field with the name
    `identifier` and matches it against `pattern`.

*   A `: pattern` is a named field with the name omitted. When destructuring
    named fields, it's very common to want to bind the resulting value to a
    variable with the same name.

    As a convenience, the identifier can be omitted and inferred from `pattern`.
    The subpattern must be a variable pattern which may be wrapped in a unary
    pattern. The field name is then inferred from the name in the variable
    pattern. These pairs of patterns are each equivalent:

    ```dart
    // Variable:
    var (untyped: untyped, typed: int typed) = ...
    var (:untyped, :int typed) = ...

    switch (obj) {
      case (untyped: var untyped, typed: int typed): ...
      case (:var untyped, :int typed): ...
    }

    // Null-check and null-assert:
    switch (obj) {
      case (checked: var checked?, asserted: var asserted!): ...
      case (:var checked?, :var asserted!): ...
    }

    // Cast:
    var (field: field as int) = ...
    var (:field as int) = ...
    ```

A record pattern with a single unnamed field and no trailing comma is ambiguous
with a parenthesized pattern. In that case, it is treated as a parenthesized
pattern. To write a record pattern that matches a single unnamed field, add a
trailing comma, as you would with the corresponding record expression.

It is a compile-time error if any pair of named fields have the same name. This
applies to both explicit and inferred field names. *For example, this is an
error:*

```dart
var (:x, x: y) = (x: 1);
```

*Destructuring the same field multiple times is never necessary because you can
always just destructure it once with an `|` subpattern. If a user does it, it's
mostly like a copy/paste mistake and it's more helpful to draw their attention
to the error than silently accept it.*

### Object pattern

```
objectPattern ::= typeName typeArguments? '(' patternFields? ')'
```

An object pattern matches values of a given named type and then extracts values
from it by calling getters on the value. Object patterns let users destructure
data from arbitrary objects using the getters the object's class already
exposes.

This pattern is particularly useful for writing code in an algebraic datatype
style. For example:

```dart
class Rect {
  final double width, height;

  Rect(this.width, this.height);
}

display(Object obj) {
  switch (obj) {
    case Rect(width: var w, height: var h): print('Rect $w x $h');
    default: print(obj);
  }
}
```

As with record patterns, the getter name can be omitted and inferred from the
variable pattern in the field subpattern which may be wrapped in a unary
pattern. The previous example could be written like:

```dart
display(Object obj) {
  switch (obj) {
    case Rect(:var width, :var height): print('Rect $width x $height');
    default: print(obj);
  }
}
```

It is a compile-time error if:

*   `objectName` does not refer to a type.

*   A type argument list is present and does not match the arity of the type of
    `objectName`.

*   A `patternField` is of the form `pattern`. Positional fields aren't allowed.

*   Any two named fields have the same name. This applies to both explicit and
    inferred field names. *For example, this is an error:*

    ```dart
    var Point(:x, x: y) = Point(1, 2);
    ```

## Pattern uses

Patterns are woven into the larger language in a few ways:

### Pattern variable declaration

Places in the language where a local variable can be declared are extended to
allow a pattern, like:

```dart
var (a, [b, c]) = ("str", [1, 2]);
```

Dart's existing C-style variable declaration syntax makes it harder to
incorporate patterns. Variables can be declared just by writing their type, and
a single declaration might declare multiple variables. Fully incorporating
patterns into that could lead to confusing syntax like:

```dart
// Not allowed:
(int, String) (n, s) = (1, "str");
final (a, b) = (1, 2), c = 3, (d, e);
```

To avoid this weirdness, patterns only occur in variable declarations that begin
with a `var` or `final` keyword. Also, a variable declaration using a pattern
can only have a single declaration "section". No comma-separated multiple
declarations like:

```dart
// Not allowed:
var [a] = [1], (b, c) = (2, 3);
```

Declarations with patterns must have an initializer. This is not a limitation
since the point of using a pattern in a variable declaration is to match it
against the initializer's value.

Add this new rule:

```
patternVariableDeclaration  ::= ( 'final' | 'var' ) outerPattern '=' expression

outerPattern                ::= parenthesizedPattern
                              | listPattern
                              | mapPattern
                              | recordPattern
                              | objectPattern
```

The `outerPattern` rule defines a subset of the patterns that are allowed as the
outermost pattern in a declaration. Subsetting allows useful code like:

```dart
var ((a, b) & record) = (1, 2);           // Parentheses.
var [a, b] = [1, 2];                      // List.
var {1: a} = {1: 2};                      // Map.
var (a, b, x: x) = (1, 2, x: 3);          // Record.
var Point(x: x, y: y) = Point(1, 2);      // Object.
```

But excludes other kinds of patterns to prohibit weird code like:

```dart
// Not allowed:
var String str = 'redundant';     // Variable.
var str as String = 'weird';      // Cast.
var definitely! = maybe;          // Null-assert.
```

Allowing parentheses gives users an escape hatch if they really want to use an
unusual pattern there.

**TODO: Should we support destructuring in `const` declarations?**

The new rules are incorporated into the existing productions for declaring
variables like so:

```
localVariableDeclaration ::=
  | metadata initializedVariableDeclaration ';' // Existing.
  | metadata patternVariableDeclaration ';' // New.

forLoopParts ::=
  | // Existing productions...
  | metadata ( 'final' | 'var' ) outerPattern 'in' expression // New.
```

As with regular for-in loops, it is a compile-time error if the type of
`expression` in a pattern-for-in loop is not assignable to `Iterable<dynamic>`.

*We could potentially allow patterns in top-level variables and static fields
but lazy initialization makes that more complex. We could support patterns in
instance field declarations, but constructor initializer lists make that harder.
Parameter lists are a natural place to allow patterns, but the existing grammar
complexity of parameter lists&mdash;optional parameters, named parameters,
required parameters, default values, etc.&mdash;make that very hard. For the
initial proposal, we focus on patterns only in variables with local scope.*

### Pattern assignment

A pattern on the left side of an assignment expression is used to destructure
the assigned value. We extend `expression`:

```
expression        ::= patternAssignment
                    | // Existing productions...

patternAssignment ::= outerPattern '=' expression
```

*This syntax allows chaining pattern assignments and mixing them with other
assignments, but does not allow patterns to the left of a compound assignment
operator.*

In a pattern assignment, all variable patterns are interpreted as referring to
existing variables. You can't declare any new variables. *Disallowing new
variables allows pattern assignment expressions to appear anywhere expressions
are allowed while avoiding confusion about the scope of new variables.*

It is a compile-time error if:

*   An identifier in a variable pattern does not resolve to a non-final local
    variable. *We could allow assigning to other variables or setters, but it
    seems strange to allow assigning to `foo` when `foo` is an instance field on
    the surrounding class with an implicit `this.`, but not allowing to assign
    to `this.foo` explicitly. In the future, we may expand pattern assignment
    syntax to allow other selector expressions. For now, we restrict assignment
    to local variables, which are also the only kind of variables that can be
    declared by patterns.*

*   The matched value type for a variable or cast pattern is not assignable to
    the corresponding variable's type.

*   The same variable is assigned more than once. *In other words, a pattern
    assignment can't have multiple variable subpatterns with the same name. This
    prohibits code like:*

    ```dart
    var a = 1;
    (a & a) = 2;
    [a, a, a] = [1, 2, 3];
    ```

### Switch statement

We extend switch statements to allow patterns in cases:

```
switchStatement         ::= 'switch' '(' expression ')'
                            '{' switchStatementCase* switchStatementDefault? '}'
switchStatementCase     ::= label* 'case' guardedPattern ':' statements
guardedPattern          ::= pattern ( 'when' expression )?
switchStatementDefault  ::= label* 'default' ':' statements
```

Allowing patterns in cases significantly increases the expressiveness of what
properties a case can verify, including executing arbitrary user-defined code.
This implies that the order that cases are checked is now potentially
user-visible and an implementation must execute the *first* case that matches.

#### Breaking existing switches

Many constant expressions are subsumed by the new pattern syntax so most
existing switch cases have the same semantics under this proposal. However,
patterns are not a strict superset of constant expressions and some switches may
be broken.

To estimate how breaking these changes are, I analyzed 18,672,247 lines of code
in 102,015 files across 2,000 Pub packages, a large collection of open source
Flutter applications, and the Dart and Flutter repositories. I found a total of
94,249 switch cases.

The specific kinds of switches whose behavior changes are:

*   **List and map patterns.** A list or map constant literal in a switch case
    is now interpreted as a list or map *pattern* which destructures its
    elements at runtime. Before, it was simply treated as identity comparison.

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
    "match". I did not find any switch cases whose expression is a list or map
    literal.

*   **Wildcards.** A switch case containing the identifier `_` currently matches
    if the matched value is equal to the constant named `_`. With this proposal,
    it becomes a wildcard that always matches. I did not find any switch cases
    whose expression is `_`.

*   **Constant constructors.** A switch case can be a constant constructor call
    with implicit `const`, like:

    ```dart
    case SomeClass(1, 2):
    ```

    With this proposal, that is interpreted as an object pattern whose arguments
    are subpatterns. In cases where the matched value is also a constant, this
    will *likely* behave the same but may not. I found 8 switch cases of this
    form (0.008%).

*   **Other constant expressions.** Constant patterns allow simple literals and
    references to named constants to be used directly as patterns, which covers
    the majority of all existing switch cases. Also a constant constructor
    explicitly prefixed with `const` is a valid constant expression pattern. But
    some more complex expressions are valid constant expressions but not valid
    constant patterns. In the switch cases I analyzed, the exceptions are:

    ```
    case A + A:                                         // Infix "+".
    case A + 'b':                                       // Infix "+".
    case -ERR_LDS_ICAO_SIGNED_DATA_SIGNER_INFOS_EMPTY:  // Unary "-".
    case -sigkill:                                      // Unary "-".
    case List<RPChoice>:                                // Generic type literal.
    case 720 * 1280:                                    // Infix "*".
    case 1080 * 1920:                                   // Infix "*".
    case 1440 * 2560:                                   // Infix "*".
    case 2160 * 3840:                                   // Infix "*".
    ```

    These nine cases represent 0.009% of the cases found.

For any switch case that is broken by this proposal, you can revert back to the
original behavior by prefixing the case expression (now pattern) with `const`:

```dart
// List or map literal:
case const [a, b]:

// Const constructor call:
case const SomeClass(1, 2):

// Other constant expression:
case const A + A:
case const A + 'b':
case const -ERR_LDS_ICAO_SIGNED_DATA_SIGNER_INFOS_EMPTY:
case const -sigkill:
case const List<RPChoice>:
case const 720 * 1280:
case const 1080 * 1920:
case const 1440 * 2560:
case const 2160 * 3840:
```

We can determine syntactically whether an existing switch case's behavior will
be changed by this proposal, so this fix can be easily automated and applied
mechanically.

#### Guard clause

We also allow an optional *guard clause* to appear after a case. This enables a
switch case to evaluate an arbitrary predicate after matching. Guards are useful
because when the predicate evaluates to false, execution proceeds to the next
case instead of exiting the entire switch like it would if you nested an `if`
statement inside the switch case's body:

```dart
var pair = (1, 2);

// This prints nothing:
switch (pair) {
  case (a, b):
    if (a > b) print('First element greater');
    break;
  case (a, b):
    print('Other order');
    break;
}

// This prints "Other order":
switch (pair) {
  case (a, b) when a > b:
    print('First element greater');
    break;
  case (a, b):
    print('Other order');
    break;
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
`break` is a fairly large fraction of the statements in all switches even though
it does nothing.

Therefore, this proposal removes the requirement that each non-empty case body
definitely exit. Instead, a non-empty case body implicitly jumps to the end of
the switch after completion. From the spec, remove:

> If *s* is a non-empty block statement, let *s* instead be the last statement
> of the block statement. It is a compile-time error if *s* is not a `break`,
> `continue`, `rethrow` or `return` statement or an expression statement where
> the expression is a `throw` expression.

This is now valid code that prints "one":

```dart
switch (1) {
  case 1:
    print("one");
  case 2:
    print("two");
}
```

Empty cases continue to fallthrough to the next case as before. This prints "one
or two":

```dart
switch (1) {
  case 1:
  case 2:
    print("one or two");
}
```

To have an empty case that does *not* fallthrough, use `break;` for its body as
you would today.

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
    Color.red => Color.orange,
    Color.orange => Color.yellow,
    Color.yellow => Color.green,
    Color.green => Color.blue,
    Color.blue => Color.purple,
    Color.purple => Color.red
  };
}
```

The grammar is:

```
primary                 ::= // Existing productions...
                          | switchExpression

switchExpression        ::= 'switch' '(' expression ')' '{'
                            switchExpressionCase ( ',' switchExpressionCase )*
                            ','? '}'
switchExpressionCase    ::= guardedPattern '=>' expression
```

The body is a series of cases. Each case has a pattern, optional guard, and a
single expression body. As with other expression forms containing a list of
subelements (argument lists, collection literals), the cases are separated by
commas with an optional trailing comma. Since the body of each case is a single
expression with a known terminator, it's easy to tell when one case ends and the
next begins. That lets us do away with the `case` keyword.

To keep the syntax small and light, we also disallow a `default` clause.
Instead, you can use a shorter `_` wildcard pattern to catch any remaining
values.

Slotting into `primary` means it can be used anywhere any expression can appear,
even as operands to unary and binary operators. Many of these uses are ugly, but
not any more problematic than using a collection literal in the same context
since a `switch` expression is always delimited by a `switch` and `}`.

Making it high precedence allows useful patterns like:

```dart
await switch (n) {
  1 => aFuture,
  2 => anotherFuture,
  _ => otherwiseFuture
};

var x = switch (n) {
  1 => obj,
  2 => another,
  _ => otherwise
}.someMethod();
```

Over half of the switch cases in a large corpus of packages contain either a
single return statement or an assignment followed by a break so there is some
evidence this will be useful.

#### Expression statement ambiguity

Thanks to expression statements, a switch expression could appear in the same
position as a switch statement. This isn't technically ambiguous, but requires
unbounded lookahead to read past the value expression to the first `case` in
order to tell if a switch in statement position is a statement or expression.

```dart
main() {
  switch (some(extremely, long, expression, here)) {
    _ => expression()
  };

  switch (some(extremely, long, expression, here)) {
    case _: statement();
  }
}
```

To avoid that, we disallow a switch expression from appearing at the beginning
of an expression statement. This is similar to existing restrictions on map
literals appearing in expression statements. In the rare case where a user
really wants one there, they can parenthesize it.

### If-case statement and element

Often you want to conditionally match and destructure some data, but you only
want to test a value against a single pattern. A `switch` statement works but is
verbose:

```dart
switch (json) {
  case [int x, int y]:
    return Point(x, y);
}
```

We can make simple uses like this better by extending if statements to allow
`case` followed by a pattern:

```dart
if (json case [int x, int y]) return Point(x, y);
```

It may have an else branch as well:

```dart
if (json case [int x, int y]) {
  print('Was coordinate array $x,$y');
} else {
  throw FormatException('Invalid JSON.');
}
```

We replace the existing `ifStatement` rule with:

```
ifStatement ::= ifCondition statement ('else' statement)?
ifCondition :== 'if' '(' expression ( 'case' guardedPattern )? ')'
```

**TODO: Allow patterns in if elements too ([#2542][]).**

[#2542]: https://github.com/dart-lang/language/issues/2542

When the `condition` has no `guardedPattern`, it behaves as it does today. If
there is a `guardedPattern`, then the expression is evaluated and matched
against the subsequent pattern. If it matches, the then branch is executed with
any variables the pattern defines in scope. Otherwise, the else branch is
executed if there is one.

A guard is also allowed:

```
if (json case [int x, int y] when x == y) {
  print('Was on coordinate x-y intercept');
} else {
  throw FormatException('Invalid JSON.');
}
```

#### If-case element

Since Dart allows `if` elements inside collection literals, we also support
if-case elements. We replace the existing `ifElement` rule with:

```
ifElement ::= ifCondition element ('else' element)?
```

The semantics follow the statement form. If there is no `guardedPattern`, then
it behaves as before. When there is a `guardedPattern`, if the `expression`
matches the pattern (and the guard returns `true`) then we evaluate and yield
the then element into the surrounding collection. Otherwise, we evaluate and
yield the else element if there is one.

### Pattern context

Patterns appear inside a number of constructs in the language which we
categorize into three contexts:

*   **Declaration context.** The pattern in `localVariableDeclaration`,
    `forLoopParts`, or any of its subpatterns. Here, the innermost patterns are
    usually identifiers for the names of the new variables being bound.

*   **Assignment context.** The pattern in a `patternAssignment` or any of its
    subpatterns. The innermost subpatterns are again identifiers, but they refer
    to existing variables that are being assigned.

*   **Matching context.** The pattern in a `guardedPattern` or any of its
    subpatterns. The innermost subpatterns are often constant expressions that
    the value is compared against to see if the case matches. They may also be
    variable declarations to extract parts of the value for later processing
    when the case matches.

We refer to declaration and assignment contexts as *irrefutable contexts*.

While most patterns look and act the same regardless of where they appear in the
language, context places some restrictions on which kinds of patterns are
allowed and what their syntax is. The rules are:

*   It is a compile-time error if any of the following *refutable patterns*
    appear in an irrefutable context:

    *   Logical-or
    *   Relational
    *   Null-check
    *   Constant

    *All of these patterns are refutable and may fail to match. In a matching
    context like a switch case, if a pattern fails to match, execution skips
    over the case body to ensure that variables bound by the pattern can only
    be used when the pattern matches. Declaration and assignment contexts have
    no control flow, so they can only use patterns that will always match.*

    *Logical-or patterns are refutable because there is no point in using one
    with an irrefutable left operand. We could make null-check patterns
    irrefutable if `V` is assignable to its static type, but whenever that is
    true the pattern does nothing useful since its only behavior is a type
    test.*

    *The remaining patterns are allowed syntactically to appear in a refutable
    context. Patterns that do type tests like variables and lists produce a
    compile-time error when used in an irrefutable context if the static type of
    the matched value isn't assignable to their required type. This error is
    specified under type checking.*

*   It is a compile-time error if a variable pattern in a declaration context is
    marked with `var` or `final`. *A pattern declaration statement is already
    preceded by `var` or `final`, so allowing those on the variable patterns
    inside would lead to unnecessary or confusing code like:*

    ```dart
    // Disallowed:
    var [var x] = [1];
    final [var y] = [2];
    ```

    *To declare variables in a declaration context, use a simple identifer:*

    ```dart
    // OK:
    var [x] = [1];
    final [y] = [2];
    ```

*   It is a compile-time error if a variable pattern in an assignment context is
    marked with `var`, `final`, or a type annotation (or both `final` and a type
    annotation). *Patterns in assignments can only assign to existing variables,
    not declare new ones.*

    ```dart
    var a = 1;
    var b = 2;

    // Disallowed:
    (var a, int b) = (3, 4);

    // OK:
    (a, b) = (3, 4);
    ```

*   A simple identifier in a matching context is treated as a named constant
    pattern unless its name is `_`. *A bare identifier is ambiguous and could
    be either a named constant or a variable pattern without any `var`, `final`,
    or type annotation marker. We prefer the constant interpretation for
    backwards compatibility and to make variable declarations more explicit in
    cases. To declare variables in a matching context, use `var`, `final`, or a
    type before the name.*

    *There is no ambiguity with bare identifiers in irrefutable contexts since
    constant patterns are disallowed there.*

    ```dart
    const c = 1;
    switch (2) {
      case c: print('match $c');
      default: print('no match');
    }
    ```

    *This program prints "no match" and not "match 2".*

*   A simple identifier in a matching context named `_` is treated as a wildcard
    variable pattern. *A bare `_` is always treated as a wildcard regardless of
    context, even though other variables in matching contexts require a marker.*

    ```dart
    // OK:
    switch (triple) {
      case [_, var y, _]: print('The middle element is $y');
    }
    ```

    *You can also use `var _` or `final _` to write a wildcard in a matching
    context because it would require additional specification to explicitly
    forbid it, but doing so is discouraged.*

*In short, you can't use refutable patterns in places that don't do control
flow. Use simple identifiers (optionally with type annotations) to declare
variables in pattern declarations. Use simple identifiers to assign to variables
in pattern assignments. Use explicitly marked identifiers to declare variables
in `case` patterns. Use `_` anywhere for a wildcard.*

## Static semantics

### Type inference

Type inference in Dart allows type information in one part of the program to
flow over and fill in missing pieces in another part. Inference can flow
"upwards" from a subexpression to the surrounding expression:

```dart
[1]
```

Here, we infer `List<int>` for the type of the list literal based on type of its
element. Inference can flow "downwards" from an expression into its
subexpressions too:

```dart
<List<int>>[[]]
```

Here, the inner empty list literal `[]` gets type `List<int>` because the type
argument on the outer list literal is pushed into it.

Type information can flow through patterns in the same way. From subpatterns
upwards to the surrounding pattern:

```dart
var [int x] = ...
```

Here, we infer `List<int>` for the list pattern's context type schema based on
the type of the element subpattern. Or downwards:

```dart
var <int>[x] = ...
```

Here, we infer `int` for the inner `x` subpattern based on the type of the
surrounding list pattern.

In variable declarations, type information can also flow between the variable
and its initializer. "Upwards" from initializer to variable:

```dart
var x = 1;
```

Here we infer `int` for `x` based on the initializer expression's type. That
upwards flow extends to patterns:

```dart
var [x] = <int>[1];
```

Here, we infer `List<int>` for the list pattern (and thus `int` for the `x`
subpattern) based on type of the initializer expression `<int>[1]`.

Types can also flow "downwards" from variable to initializer:

```dart
List<int> x = [];
```

Here, the empty list is instantiated as `List<int>` because the type annotation
on `x` gets pushed over to the initializer. That extends to patterns:

```dart
var <num>[x] = [1];
```

Here, we infer the list literal in the initializer to have type `List<num>` (and
not `List<int>`) based on the type of list pattern. All of this type flow can be
combined:

```dart
var (a, b, <double>[c], [int d]) = ([1], <List<int>>[[]], [2], [3]);
```

To orchestrate this, type inference on patterns proceeds in three phases:

1.  **Calculate the pattern type schema.** Start at the top of the pattern and
    recurse downwards into subpatterns using the surrounding pattern as context.
    When we reach the leaves, work back upwards filling in missing pieces where
    possible. When this completes, we have a type schema for the pattern. It's
    a type *schema* and not a *type* because there may be holes where types
    aren't known yet.

    We only calculate a pattern type schema for pattern variable declarations
    and pattern assignments. In matching contexts (switch cases, if-case
    constructs), the pattern context type schema is not used, no downwards
    inference is performed from the pattern to the matched value expression, and
    no coercions or casts from `dynamic` are inserted in the matched value
    expression.

    *It would be hard to apply inference from cases in a switch to the value
    since there are multiple cases and it's not clear how to unify that. Even in
    if-case constructs, it's not clear that downwards inference is desirable,
    since the intent of the pattern is to ask a question about the matched
    object, and not necessarily to try to force a certain answer.*

2.  **Calculate the static type of the matched value.** A pattern always occurs
    in the context of some matched value. For pattern variable declarations,
    this is the initializer. For switches and if-case constructs, it's the value
    being matched.

    Using the pattern's type schema as a context type (if not in a matching
    context), infer missing types on the value expression. This is the existing
    type inference rules on expressions. It yields a complete static type for
    the matched value. This process may also insert implicit coercions and casts
    from `dynamic` in the matched value expression.

    *For example:*

    ```dart
    T id<T>(T t) => t;
    dynamic d = 'str';
    var (double n, int Function(int) f, String s) = (1, id, d);
    ```

    *This generates a type schema of `(double, int Function(int), String)` from
    the pattern. That type schema is applied to the initializer, which inserts
    coercions and casts to become:*

    ```dart
    var (double n, int Function(int) f, String s) = (1.0, id<int>, d as String);
    ```

3.  **Calculate the static type of the pattern.** Using that value type, recurse
    through the pattern again downwards to the leaf subpatterns filling in any
    holes in the type schema. This process may also insert implicit coercions
    and casts from `dynamic` when values flow into a pattern during matching.

    *For example:*

    ```dart
    T id<T>(T t) => t;
    (T Function<T>(T), dynamic) record = (t, 'str');
    var (int Function(int) f, String s) = record;
    ```

    *Since the right-hand is not a record literal, we can't use the pattern's
    context type schema to insert coercions when the record is being created.
    However, the matched value type `(T Function<T>(T), dynamic)` is allowed by
    the record pattern's required type `(Object?, Object?)`, the field matched
    value type `T Function<T>(T)` is allowed by the field required type `int
    Function(int)`, and the field matched value type `dynamic` is allowed by the
    field required type `String)`. So the declaration is valid. Coercions are
    inserted after destructuring each record field before passing them to the
    field subpatterns. At runtime, when the record is destructured during
    matching, the coercions are applied. This is specified below.*

#### Pattern context type schema

In a non-pattern variable declaration, the variable's type annotation is used
for downwards inference of the initializer:

```dart
List<int> list = []; // Infer <int>[].
```

Patterns extend this behavior:

```dart
var (List<int> list, <num>[a]) = ([], [1]); // Infer (<int>[], <num>[]).
```

To support this, every pattern has a context type schema which is used as the
downwards inference context on the matched value expression in pattern variable
declarations and pattern assignments. This is a type *schema* because there may
be holes in the type:

```dart
var (a, int b) = ... // Schema is `(?, int)`.
```

The context type schema for a pattern `p` is:

*   **Logical-and**: The greatest lower bound of the context type schemas of the
    branches.

*   **Null-assert**: A context type schema `E?` where `E` is the context type
    schema of the inner pattern. *For example:*

    ```dart
    var [[int x]!] = [[]]; // Infers List<List<int>?> for the list literal.
    ```

*   **Variable**:

    1.  In an assignment context, the context type schema is the static type of
        the variable that `p` resolves to.

    1.  Else if `p` has no type annotation, the context type schema is `?`.
        *This lets us potentially infer the variable's type from the matched
        value.*

    2.  Else the context type schema is the annotated type. *When a typed
        variable pattern is used in a destructuring variable declaration, we
        do push the type over to the value for inference, as in:*

        ```dart
        var (items: List<int> x) = (items: []);
        //                                 ^- Infers List<int>.
        ```

*   **Cast**: The context type schema is `?`.

*   **Parenthesized**: The context type schema of the inner subpattern.

*   **List**: A context type schema `List<E>` where:

    1.  If `p` has a type argument, then `E` is the type argument.

    2.  Else if `p` has no elements then `E` is `?`.

    3.  Else, infer the type schema from the subpatterns:

        1.  Let `es` be an empty list of type schemas.

        2.  For each subpattern `e` in `p`:

            1.  If `e` is a rest element pattern with a subpattern `s` and the
                context type schema of `s` is an `Iterable<T>` for some type
                schema `T`, then add `T` to `es`.

            2.  Else if `e` is not a rest element pattern, add the context
                type schema of `e` to `es`.

            *Else, `e` is a rest element without an iterable element type, so it
            doesn't contribute to inference.*

        3.  If `es` is empty, then `E` is `?`. *This can happen if the list
            pattern contains only a rest element which doesn't have a context
            type schema that is known to be an `Iterable<T>` for some `T`,
            like:*

            ```dart
            var [...] = [1, 2];
            var [...x] = [1, 2];
            ```

        4.  Else `E` is the greatest lower bound of the type schemas in `es`.
            *We use the greatest lower bound to ensure that the outer collection
            type has a precise enough type to ensure that any typed field
            subpatterns do not need to downcast:*

            ```dart
            var [int a, num b] = [1, 2];
            ```

            *Here, the GLB of `int` and `num` is `int`, which ensures that
            neither `int a` nor `num b` need to downcast their respective
            fields.*

*   **Map**: A type schema `Map<K, V>` where:

    1.  If `p` has type arguments then `K`, and `V` are those type arguments.

    2.  Else if `p` has no entries, then `K` and `V` are `?`.

    3.  Else `K` is the least upper bound of the types of all key expressions
        and `V` is the greatest lower bound of the context type schemas of all
        value subpatterns. *The rest pattern, if present, doesn't contribute to
        the context type schema.*

*   **Record**: A record type schema with positional and named fields
    corresponding to the type schemas of the corresponding field subpatterns.

*   **Object**: The type the object name resolves to. *This lets inference fill
    in type arguments in the value based on the object's type arguments, as in:*

    ```dart
    var Foo<num>() = Foo();
    //                  ^-- Infer Foo<num>.
    ```

The pattern type schema for logical-or, null-check, constant, and relational
patterns is not defined, because those patterns are only allowed in refutable
contexts, and the pattern type schema is only used in irrefutable contexts.

#### Type checking and pattern required type

Once the value a pattern is matched against has a static type (which means
downwards inference on it using the pattern's context type schema is complete),
we can type check the pattern.

Also variable, list, map, record, and object patterns only match a value of a
certain *required type*. These patterns are prohibited in an irrefutable context
if the matched value isn't assignable to that type. We define the required type
for those patterns here. Some examples and the corresponding required types:

```dart
var <int>[a, b] = <num>[1, 2];  // List<int> (and compile error).
var [a, b] = <num>[1, 2];       // List<num>, a is num, b is num.
var [int a, b] = <num>[1, 2];   // List<num>.
```

To type check a pattern `p` being matched against a value of type `M`:

*   **Logical-or** and **logical-and**: Type check each branch using `M` as the
    matched value type.

*   **Relational**:

    1.  Let `C` be the static type of the right operand constant expression.

    2.  If the operator is a comparison (`<`, `<=`, `>`, or `>=`), then it is a
        compile-time error if:

        *   `M` does not define that operator,
        *   `C` is not assignable to the operator's parameter type,
        *   or if the operator's return type is not assignable to `bool`.

    3.  Else the operator is `==` or `!=`. It is a compile-time error if `C` is
        not assignable to `T?` where `T` is `M`'s `==` method parameter type.
        *The language screens out `null` before calling the underlying `==`
        method, which is why `T?` is the allowed type. Since Object declares
        `==` to accept `Object` on the right, this compile-time error can only
        happen if a user-defined class has an override of `==` with a
        `covariant` parameter.*

*   **Cast**:

    1.  Resolve the type name to a type `X`. It is a compile-time error if
        the name does not refer to a type.

    2.  Type-check the subpattern using `X` as the matched value type.

*   **Null-check** or **null-assert**:

    1.  Let `N` be [**NonNull**][nonnull](`M`).

    2.  Type-check the subpattern using `N` as the matched value type.

    [nonnull]: https://github.com/dart-lang/language/blob/master/accepted/2.12/nnbd/feature-specification.md#null-promotion

*   **Constant**: Type check the pattern's value in context type `M`. *The
    context type comes into play for things like type argument inference,
    int-to-double, and implicit generic function instantiation.*

    *Note that the pattern's value must be a constant, but there is no longer a
    restriction that it must have a primitive operator `==`. Unlike switch cases
    in current Dart, you can have a constant with a user-defined operator `==`
    method. This lets you use constant patterns for user-defined types with
    custom value semantics.*

    *Note also that the restriction that constants must be a subtype of the
    matched value's static type is removed. This is a currently an error in
    Dart:*

    ```dart
    class A {}
    class B { const B(); }

    test(A a) {
      switch (A()) {
        case const B(): ...
      }
    }
    ```

    *There is no error under this proposal because it's possible for the
    constant to have a user-defined `==` method such that this could match.*

*   **Variable**:

    1.  In an assignment context, the required type of `p` is the (unpromoted)
        static type of the variable that `p` resolves to.

    2.  Else if the variable has a type annotation, the required type of `p` is
        that type, as is the static type of the variable introduced by `p`.

    3.  Else the required type of `p` is `M`, as is the static type of the
        variable introduced by `p`. *This means that an untyped variable pattern
        can have its type indirectly inferred from the type of a superpattern:*

        ```dart
        var <(num, Object)>[(a, b)] = [(1, true)]; // a is num, b is Object.
        ```

        *The pattern's context type schema is `List<(num, Object>)`. Downwards
        inference uses that to infer `List<(num, Object>)` for the initializer.
        That inferred type is then destructured and used to infer `num` for `a`
        and `Object` for `b`.*

*   **Parenthesized**: Type-check the inner subpattern using `M` as the matched
    value type.

*   **List**:

    1.  Calculate the value's element type `E`:

        1.  If `p` has a type argument `T`, then `E` is the type `T`.

        2.  Else if `M` implements `List<T>` for some `T` then `E` is `T`.

        3.  Else if `M` is `dynamic` then `E` is `dynamic`.

        4.  Else `E` is `Object?`.

    2.  Type-check each non-rest element subpattern using `E` as the matched
        value type. *Note that we calculate a single element type and use it for
        all subpatterns. In:*

        ```dart
        var [a, b] = [1, 2.3];
        ```

        *both `a` and `b` use `num` as their matched value type.*

    3.  If there is a rest element subpattern with a subpattern, type-check its
        subpattern using `List<E>` as the matched value type.

    4.  The required type of `p` is `List<E>`.

*   **Map**:

    1.  Calculate the value's entry key type `K` and value type `V`:

        1.  If `p` has type arguments `<K, V>` for some `K` and `V` then use
            those.

        2.  Else if `M` implements `Map<K, V>` for some `K` and `V` then use
            those.

        3.  Else if `M` is `dynamic` then `K` and `V` are `dynamic`.

        4.  Else `K` and `V` are `Object?`.
        
    2.  Type-check each value subpattern using `V` as the matched value type.
        *Like lists, we calculate a single value type and use it for all value
        subpatterns:*

        ```dart
        var {1: a, 2: b} = {1: "str", 2: bool};
        ```

        *Here, both `a` and `b` use `Object` as the matched value type.*

    3.  The required type of `p` is `Map<K, V>`.

* **Record**:

  1.  For each field `f` with subpattern `s` of `p`:

      1.  If `M` is a record type with the same shape as `p`, then let `F`
          be that field's type in `M`.

      2.  Else if `M` is `dynamic`, then let `F` be `dynamic`.

      3.  Else let `F` be `Object?`. *The field subpattern will only be
          matched at runtime if the value does turn out to be a record with
          the right shape where the field is present, so it's safe to just
          assume the field exists when type checking here.*

      4.  Type-check `s` using `F` as the matched value type.

  2.    The required type of `p` is a record type with the same shape as `p` and
        `Object?` for all fields. *If the matched value's type is `dynamic` or
        some record supertype like `Object`, then the record pattern should
        match any record with the right shape and then delegate to its field
        subpatterns to ensure that the fields match.*

*   **Object**:

    1.  Resolve the object name to a type `X`. It is a compile-time error if the
        name does not refer to a type. Apply downwards inference from `M` to
        infer type arguments for `X` if needed.

    2.  For each field subpattern of `p`, with name `n` and subpattern `f`:

        1.  Let `G` be the type of the getter on `X` with the name `n`.
          It is a **compile-time error** if `X` does not have a *getter* with name `n`.
          _If `X` is `dynamic` or `Never`, it is considered as having every getter with the same type._

        2.  Type check `f` with `G` as the matched value type, to find its
            required type.

    3.  The required type of `p` is `X`.

If `p` with required type `T` is in an irrefutable context:

    *   It is a compile-time error if `M` is not assignable to `T`.
        *Destructuring and variable patterns can only be used in declarations
        and assignments if we can statically tell that the destructuring and
        variable binding won't fail to match.*

    *   Else if `M` is not a subtype of `T` then an implicit coercion or cast is
        inserted before the pattern binds the value, tests the value's type,
        destructures the value, or invokes a function with the value as a target
        or argument.

        *Each pattern that requires a certain type can be thought of as an
        "assignment point" where an implicit coercion may happen when a value
        flows in during matching. Examples:*

        ```dart
        var record = (x: 1 as dynamic);
        var (x: String _) = record;
        ```

        *Here no coercion is performed on the record pattern since `(x:
        dynamic)` is a subtype of `(x: Object?)` (the record pattern's required
        type). But an implicit cast from `dynamic` is inserted when the
        destructured `x` field flows into the inner `String _` pattern since
        `dynamic` is not a subtype of `String`. In this example, the cast will
        fail and throw an exception.*

        ```dart
        T id<T>(T t) => t;
        var record = (x: id);
        var (x: int Function(int) _) = record;
        ```

        *Here, again no coercion is applied to the record flowing in to the
        record pattern, but a generic instantiation is inserted when the
        destructured field `x` field flows into the inner `int Function(int) _`
        pattern.*

        *We only insert coercions in irrefutable contexts:*

        ```dart
        dynamic d = 1;
        if (d case String s) print('then') else print('else');
        ```

        *This prints "else" instead of throwing an exception because we don't
        insert a _cast_ from `dynamic` to `String` and instead let the `String
        s` pattern _test_ the value's type, which then fails to match.*

It is a compile-time error if the type of an expression in a guard clause is not
assignable to `bool`.

### Pattern uses

It is a compile-time error if the expression in a guard clause in a switch case
or if-case construct is not assignable to `bool`.

The static type of a switch expression is the least upper bound of the static
types of all of the case expressions.

### Variables and scope

Patterns often exist to bind new variables. The language must ensure that the
variables bound by a pattern can only be used when the pattern has matched,
which means variables bound by refutable patterns must only be in scope in code
that can't be reached when the match fails.

Also, logical-or patterns and switch case fallthrough add some complexity.

#### Pattern variable sets

A *pattern variable set* specifies the set of variables declared by a pattern
and its subpatterns when not in an assignment context. Each variable in the set
has a unique name, a static type (the declared or inferred type, but not its
promoted type), and whether it is final or not. The pattern variable set for a
pattern is:

*   **Logical-or**: The pattern variable set of either branch. It is a
    compile-time error if the two branches do not have equal pattern variable
    sets. Two pattern variable sets are equal if they have the same set of names
    and each corresponding pair of variables have the same finality and their
    types are structurally equivalent after `NORM()`.

    *Since only one branch will match and we don't know which, for the pattern
    to have a stable set of variables with known types, the two branches must
    define the same variables. This way, uses of the variables later will have
    a known type and finality regardless of which branch matched.*

*   **Logical-and**, **cast**, **null-check**, **null-assert**,
    **parenthesized**, **list**, **map**, **record**, or **object**: The union
    of the pattern variable sets of all of the subpatterns.

    The union of a series of pattern variable sets is the union of their
    corresponding sets of variable names. Each variable in the resulting set is
    mapped to the corresponding variable's type and finality.

    It is a compile-time error if any two sets being unioned have a variable
    with the same name. *A pattern can't declare the same variable more than
    once.*

*   **Relational** or **constant**: The empty set.

*   **Variable**:

    1.  If the variable's identifier is `_` then the empty set.

    2.  Else a set containing a single variable whose name is the pattern's
        identifier and whose type is the pattern's required type (which may have
        been inferred). In a declaration context, the variable is final if the
        surrounding `patternVariableDeclaration` has a `final` modifier. In a
        matching context, the variable is final if the variable pattern is
        marked `final` and is not otherwise.

#### Scope

The variables defined by a pattern and its subpatterns (its pattern variable
set, defined above), are introduced into a scope based on where the pattern
appears:

*   **Pattern variable declaration**: The scope enclosing the variable
    declaration statement. *This will be either a function body scope or a block
    scope.*

    The *initializing expression* for every variable in the pattern is the
    pattern variable declaration's initializer. *This means all variables
    defined by a pattern are in scope beginning at the top of the surrounding
    block or function body, but it is a compile-time error to refer to them
    until after the pattern variable declaration's initializer:*

    ```dart
    const c = 1;

    f() {
      print(c);
      //    ^ Error: Refers to C declared below:

      var [c] = c;
      //        ^ Error: Not initialized yet.

      print(c);
      //    ^ OK.
    }
    ```

*   **Pattern-for statement**: Scoping follows the normal for and for-in
    statement scoping rules where the variable (now variables) are bound in a
    new scope for each loop iteration. All pattern variables are in the same
    scope. They are considered initialized after the for loop initializer
    expression.

*   **Pattern assignment**: An assignment only assigns to existing variables
    and does not bind any new ones.

*   **Switch statement**, **switch expression**, **if-case statement**,
    **if-case-element**: Each `guardedPattern` introduces a new *case scope*
    which is where the variables defined by that case's pattern are bound.

    There is no *initializing expression* for the variables in a case pattern,
    but they are considered initialized after the entire case pattern, before
    the guard expression if there is one. *However, all pattern variables are
    in scope in the entire pattern:*

    ```dart
    const c = 1;
    switch (1) {
      case [var c, == c]
        //            ^ Error: In scope but not initialized.
        //              (Also an error because `c` is not a constant.)
            when c == 2:
        //       ^ OK.
        print(c);
        //    ^ OK.
    }
    ```

    The guard expression is evaluated in its case's case scope.

    It is a compile-time error for a guard to contain an assignment to a
    variable defined in the case that owns that guard. *This helps avoid users
    running into confusing behavior where the body sees a different variable
    than the guard when cases share a body (see next section). We make this an
    error even when the body only has a single case to keep the rule simpler for
    users to understand. This is similar to the restriction that you can't
    assign to the variable introduced by an initializing formal inside the
    initializer list.*

    If the body of a switch statement or expression is reached through only a
    single case, then it is executed in a new scope whose enclosing scope is the
    case scope of that case. Otherwise, the body is executed in a new scope
    whose enclosing scope is the shared case scope, defined below.

    The then statement of an if-case statement is executed in a new scope whose
    enclosing scope is the case's case scope.

    The then element of an if-case element is evaluated in a new scope whose
    enclosing scope is the case's case scope.

#### Shared case scope

In a switch statement, multiple cases may share the same body. This introduces
complexity when those cases declare variables which may or may not overlap and
which may be used in the body or guards. For example:

```dart
switch (obj) {
  case [int a, int n] when n > 0:
  case {"a": int a}:
    print(a.abs()); // OK.
}
```

Here, both patterns declare a variable named `a` which is used in the body.
Somehow, in the body, `a` refers to *both* of those pattern variables.
Conversely, only the first case declares `n` which is used in that case's guard
but not the body.

We specify how this behaves by creating a new *shared case scope* that contains
all variables from all of the cases and then report errors from invalid uses of
them. The shared case scope `s` of a body used by a set of cases with pattern
variable sets `vs` (where default cases and labels have empty pattern variable
sets) is:

1.  Create a new empty scope `s` whose enclosing scope is the scope surrounding
    the switch statement or expression.

2.  For each name `n` appearing as a variable name in any of the pattern
    variable sets in `vs`:

    1.  If `n` is defined in every pattern variable set in `vs` and has the same
        type and finality, then introduce `n` into `s` with the same type and
        finality. This is a *shared variable* and is available for use in the
        body.

        If any of the corresponding variables in `vs` are promoted, calculate
        the promoted type of the variable in `s` based on all of the promoted
        types of `n` in the cases in the same way that promotions are merged at
        join points.

        *We declare a new variable because the enclosing scope of the body is
        not any of the case scopes. The fact that this is a new variable and not
        one of the variables declared by the cases is user-visible if a user
        captures a case variable in a closure in the guard:*

        ```dart
        Function captured;

        bool capture(Function closure) {
          captured = closure;
          return true;
        }

        switch (['before']) {
          case [String a] when capture(() => print(a)):
          case [_, String a]:
            a = 'after';
            captured();
        }
        ```

        *This prints "before", not "after". In practice, users will rarely
        notice this, the same way they rarely notice that an initializing formal
        introduces a variable in the initializer list distinct from the
        initialized field.*

        *Note that we only create a shared case scope with its own variables
        when there are multiple cases sharing a body. If there is only a single
        case, the body uses that case's scope as the enclosing scope directly.
        If you delete the second case in the above example, it prints "after".*

    2.  Else `n` is not consistently defined by all cases and thus isn't safe to
        use in the body. Introduce a new variable `n` into `s` with unspecified
        type and finality.

3.  Compile the body in `s`. It is a compile-time error if any identifier in the
    body resolves to a variable in `s` that isn't shared. *In other words, a
    variable declared by any of the case patterns shadows an outer variable, but
    only the shared ones can actually be used:*

    ```dart
    var c = 'outer';
    switch ('not int') {
      case int c:
      case _:
        print(c);
    }
    ```

    *This has a compile-time error instead of printing "outer" because `c` in
    the body resolves to a non-shared variable declared by one of the cases.*

*Note that it is not a compile-time error for there to _be_ non-shared defined
variables between cases. It's only an error to _use_ them in the body. This
enables patterns to define non-shared variables that are only used by their
respective guards:*

```dart
switch (obj) {
  case [var a, int n] when n > 1:
  case [var a, double n] when n > 1.0:
  case [var a, String s] when s.isNotEmpty:
    print(a);
}
```

*This example has no errors because the only variable used in the body, `a`, is
defined consistently by all cases.*

At runtime, we initialize all of the shared variables in the body of the case
with the values of the corresponding case variables from the matched case.

### Type promotion

**TODO: Specify how pattern matching may show that existing variables have some
type.**

### Exhaustiveness and reachability

A switch is *exhaustive* if all possible values of the matched value's static
type will definitely match at least one case, or there is a default case. Dart
currently shows a warning if a switch statement on an enum type does not have
cases for all enum values (or a default). This is helpful for code maintainance:
when you add a new value to an enum type, the language shows you every switch
statement that may need a new case to handle it.

This checking is even more important with this proposal. Exhaustiveness checking
is a key part of maintaining code written in an algebraic datatype style. It's
the functional equivalent of the error reported when a concrete class fails to
implement an abstract method.

Exhaustiveness checking over arbitrarily deeply nested record and object
patterns is complex, so the proposal to define how it works is in a [separate
document][exhaustiveness]. That tells us if the cases in a switch statement or
expression are exhaustive or not.

We don't want to require *all* switches to be exhaustive. The language currently
does not require switch statements on, say, strings to be exhaustive, and
requiring that would likely lead to many pointless empty default cases for
little value. We define an *exhaustive type* to be:

*   `bool`
*   `Null`
*   A enum type
*   A type whose declaration is marked sealed
*   `T?` where `T` is exhaustive
*   `FutureOr<T>` for some type `T` that is exhaustive
*   A record type whose fields are all exhaustive types

**TODO: Finalize the syntax for marking a class as a sealed family.**

All other types are not exhaustive. Then:

*   It is a compile-time error if the cases in a switch expression are not
    exhaustive. *Since an expression must yield a value, the only other option
    is to throw an error and most Dart users prefer to catch those kinds of
    mistakes at compile time.*

*   It is a compile-time error if the cases in a switch statement are not
    exhaustive and the static type of the matched value is an exhaustive type.

[exhaustiveness]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/0546-patterns/exhaustiveness.md

**Breaking change:** Currently, a non-exhaustive switch on an enum type is only
a warning. This promotes it to an error. Also, switches on `bool` do not have to
be exhaustive. In practice, many users already treat warnings as errors, and
switches on `bool` are rare and unidiomatic. This breaking change would only
apply to code that has opted into the language version where this ships.

## Runtime semantics

### Execution

Most of the runtime behavior is defined in the "matching" section below, but
the constructs where patterns appear have their own (hopefully obvious)
behavior.

#### Pattern variable declaration

1.  Evaluate the initializer expression producing a value `v`.

2.  Match `v` against the declaration's pattern.

#### Pattern assignment

1.  Evaluate the right-hand side expression to a value `v`.

2.  Match `v` against the pattern on the left. When matching a variable pattern
    against a value `o`, record that `o` will be the new value for the
    corresponding variable, but do not store the variable.

3.  Once all destructuring and matching is done, store all of the assigned
    variables with their corresponding values.

*In other words, it's as if every variable pattern in an assignment expression
is a new variable declaration with a hidden name. Then after the assignment
expression and matching completes, those temporary variables are all written to
the corresponding real variables. We defer the storage until matching has
completed so that users never see a partial assignment if matching happens to
fail in some way.*

#### Switch statement

1.  Evaluate the switch value producing `v`.

2.  For each case:

    1.  Match the case's pattern against `v`. If the match fails then continue
        to the next case (or default clause or exit the switch if there are no
        other cases).

    2.  If there is a guard clause, evaluate it. If it does not evaluate to a
        Boolean, throw a runtime error. *This can happen if the guard
        expression's type is `dynamic`.* If it evaluates to `false`, continue to
        the next case (or default or exit).

    3.  Find the nearest non-empty case body at or following this case. *You're
        allowed to have multiple empty cases where all preceding ones share the
        same body with the last case.*

    4.  If the enclosing scope for the body is a shared case scope, then
        initialize all shared variables the values of the corresponding
        variables from the case scope. *There will be no shared case scope and
        nothing to copy if the body is only used by a single case.*

    5.  Execute the body statement.

    6.  If execution of the body statement continues with a label, and that
        label is labeling a switch case of this switch, go to step 3 and
        continue from that label.

    7.  Otherwise the switch statement completes normally. *An explicit `break`
        is no longer required.*

3.  If no case pattern matched and there is a default clause, execute the
    statements after it.

4.  If no case matches and there is no default clause, throw a runtime
    error. *This can only occur when `null` or a legacy typed value flows
    into this switch statement from another library that hasn't migrated to
    [null safety][]. In fully migrated programs, exhaustiveness checking is
    sound and it isn't possible to reach this runtime error.*

[null safety]: https://dart.dev/null-safety

#### Switch expression

1.  Evaluate the switch value producing `v`.

2.  For each case:

    1.  Match the case's pattern against `v`. If the match fails then continue
        to the next case.

    2.  If there is a guard clause, evaluate it. If it does not evaluate to a
        Boolean, throw a runtime error. If it evaluates to `false`, continue to
        the next case.

    3.  Evaluate the expression after the case and yield that as the result of
        the entire switch expression.

3.  If no case matches, throw a runtime error. *This can only occur when `null`
    or a legacy typed value flows into this switch expression from another
    library that hasn't migrated to [null safety][]. In fully migrated programs,
    exhaustiveness checking is sound and it isn't possible to reach this runtime
    error.*

#### Pattern-for statement

A statement of the form:

```dart
for (<patternVariableDeclaration>; <condition>; <increment>) <statement>
```

Is executed similar to a traditional for loop except that multiple variables may
be declared by the pattern instead of just one. As with a normal for loop, those
variables are freshly bound to new values at each iteration so that if a
function closes over a variable, it captures the value at the current iteration
and is not affected by later iteration.

The increment clause is evaluated in a scope where all variables declared in the
pattern are freshly bound to new variables holding the current iteration's
values. If the increment clause assigns to any of the variables declared by the
pattern, those become the values bound to those variables in the next iteration.
For example:

```dart
var fns = <Function()>[];
for (var (a, b) = (0, 1); a <= 13; (a, b) = (b, a + b)) {
  fns.add(() {
    print(a);
  });
}

for (var fn in fns) {
  fn();
}
```

This prints `0`, `1`, `1`, `2`, `3`, `5`, `8`, `13`.

#### Pattern-for-in statement

A statement of the form:

```dart
for (<keyword> <pattern> in <expression>) <statement>
```

Where `<keyword>` is `var` or `final` is treated like so:

1.  Let `I` be the type of `<expression>`.

2.  Calculate the element type of `I`:

    1.  If `I` implements `Iterable<T>` for some `T` then `E` is `T`.

    2.  Else if `I` is `dynamic` then `E` is `dynamic`.

    3.  Else it is a compile-time error.

3.  Type check `<pattern>` with matched value type `E`.

4.  If there are no compile-time errors, then execution proceeds as the
    following code, where `id1` and `id2` are fresh identifiers:

    ```
    var id1 = <expression>;
    var id2 = id1.iterator;
    while (id2.moveNext()) {
      <keyword> <pattern> = id2.current;
      { <statement> }
    }
    ```

#### If-case statement

1.  Evaluate the `expression` producing `v`.

2.  Match the `pattern` in the `guardedPattern` against `v`.

3.  If the match succeeds:

    1.  If there is a guard clause:

        1.  Evaluate it. If it does not evaluate to a Boolean, throw a runtime
            error. *This can happen if the guard expression's type is
            `dynamic`.*

        1.  If the guard evaluates to `true`, execute the then `statement`.

        2.  Else, execute the else `statement` if there is one.

    2.  Else there is no guard clause. Execute the then `statement`.

4.  Else the match failed. Execute the else `statement` if there is one.

#### If-case element

1.  Evaluate the `expression` producing `v`.

2.  Match the `pattern` in the `guardedPattern` against `v`.

3.  If the match succeeds:

    1.  If there is a guard clause:

        1.  Evaluate it. If it does not evaluate to a Boolean, throw a runtime
            error. *This can happen if the guard expression's type is
            `dynamic`.*

        1.  If the guard evaluates to `true`, evaluate the then `element` and
            yield the result into the collection.

        2.  Else, evaluate the else `element` if there is one and yield the
            result into the collection.

    2.  Else there is no guard clause. Evaluate the then `element` and yield the
        result into the collection.

4.  Else the match failed. Evaluate the else `element` if there is one and yield
    the result into the collection.

### Matching (refuting and destructuring)

At runtime, a pattern is matched against a value. This determines whether or not
the match *fails* and the pattern *refutes* the value. If the match succeeds,
the pattern may also *destructure* data from the object or *bind* variables.

Refutable patterns usually occur in a context where match refutation causes
execution to skip over the body of code where any variables bound by the pattern
are in scope. If a pattern match failure occurs in irrefutable context, a
runtime error is thrown. *This can happen when matching against a value of type
`dynamic`, or when a list pattern in a variable declaration is matched against a
list of a different length.*

To match a pattern `p` against a value `v`:

*   **Logical-or**:

    1.  Match the left subpattern against `v`. If it matches, the logical-or
        match succeeds.

    2.  Otherwise, match the right subpattern against `v` and succeed if it
        matches.

*   **Logical-and**:

    1.  Match the left subpattern against `v`. If the match fails, the
        logical-and match fails.

    2.  Otherwise, match the right subpattern against `v` and succeed if it
        matches.

*   **Relational**:

    1.  Evaluate the right-hand constant expression to `c`.

    2.  If the operator is `==`:

        1.  Let `r` be the result of `v == c`.

        2.  The pattern matches if `r` is true and fails otherwise. *This takes
            into account the built-in semantics that `null` is only equal to
            `null`. The result will always be a Boolean since operator `==` on
            Object is declared to return `bool`.*

    2.  Else if the operator is `!=`:

        1.  Let `r` be the result of `v == c`.

        2.  If `r` is not a Boolean then throw a runtime error. *This can
            happen if operator `==` on `v`'s type returns `dynamic`.*

        3.  The pattern matches if `r` is false and fails otherwise. *This takes
            into account the built-in semantics that `null` is only equal to
            `null`.*

    3.  Else the operator is a comparison operator `op`:

        1.  Let `r` be the result of calling `op` on `v` with argument `c`.

        2.  If `r` is not a Boolean then throw a runtime error. *This can happen
            if the operator on `v`'s type returns `dynamic`.*

        3.  The pattern matches if `r` is true and fails otherwise.

*   **Cast**:

    1.  If the runtime type of `v` is not a subtype of the cast type of `p` then
        throw a runtime error. *Note that we throw even if this appears in a
        matching context. The intent of this pattern is to assert that a value
        *must* have some type.*

    2.  Otherwise, match the inner pattern against `v`.

*   **Null-check**:

    1.  If `v` is null then the match fails.

    2.  Otherwise, match the inner pattern against `v`.

*   **Null-assert**:

    1.  If `v` is null then throw a runtime error. *Note that we throw even if
        this appears in a matching context. The intent of this pattern is to
        assert that a value *must* not be null.*

    2.  Otherwise, match the inner pattern against `v`.

*   **Constant**:

    1.  Evaluate the pattern's value to `c`.

    2.  The pattern matches if `c == v` evaluates to `true`. *This is opposite
        the operand order that relational patterns use. This is deliberate to
        preserve compatibility with existing switch cases and continue to enable
        compilers to determine exactly which concrete `==` method is called in a
        constant pattern for optimization purposes.*

*   **Variable**:

    1.  Let `T` be the static type of the variable `p` declares or assigns to.

    2.  If the runtime type of `v` is not a subtype of `T` then the match fails.

    3.  Otherwise, store `v` in `p`'s variable and the match succeeds.

*   **Parenthesized**: Match the subpattern against `v` and succeed if it
    matches.

*   **List**:

    1.  If the runtime type of `v` is not a subtype of the required type of `p`
        then the match fails. *The list pattern's type will be `List<T>` for
        some `T` determined either by the pattern's explicit type argument or
        inferred from the matched value type.*

    2.  Let `l` be the length of the list determined by calling `length` on `v`.

    3.  Let `h` be the number of non-rest element subpatterns preceding the rest
        element if there is one, or the number of subpatterns if there is no
        rest element.

    4.  Let `t` be the number of non-rest element subpatterns following the rest
        element if there is one, or zero otherwise.

    3.  If `p` has no rest element and `l` is not equal to `h` then the match
        fails. If `p` has a rest element and `l` is less than `h + t` then the
        match fails. *These match failures become runtime exceptions if the list
        pattern is in an irrefutable context.*

    4.  Match the head elements. For `i` from `0` to `h - 1`, inclusive:

        1.  Extract the element value `e` by calling `[]` on `v` with index `i`.

        2.  Match the `i`th element subpattern against `e`.

    5.  If there is a rest element and it has a subpattern:

        1.  Let `r` be the result of calling `sublist()` on `v` with arguments
            `h`, and `l - t`.

        2.  Match the rest element subpattern against `r`.

        *If there is a rest element but it has no subpattern, the unneeded list
        elements are completely skipped and we don't even call `sublist()` to
        access them.*

    6.  Match the tail elements. If `t` is greater than zero, then for `i` from
        `0` to `t - 1`, inclusive:

        1.  Extract the element value `e` by calling `[]` on `v` with index
            `l - t + i`.

        2.  Match the subpattern `i` elements after the rest element against
            `e`.

    7.  The match succeeds if all subpatterns match.

*   **Map**:

    1.  If the runtime type of `v` is not a subtype of the required type of `p`
        then the match fails. *The map pattern's type will be `Map<K, V>` for
        some `K` and `V` determined either by the pattern's explicit type
        arguments or inferred from the matched value type.*

    2.  Let `l` be the length of the map determined by calling `length` on `v`.

    3.  If `p` has no rest element and `l` is not equal to the number of
        subpatterns then the match fails. If `p` has a rest element and `l` is
        less than the number of non-rest entry subpatterns, then the match
        fails. *These match failures become runtime exceptions if the map
        pattern is in an irrefutable context.*

    4.  Otherwise, for each (non-rest) entry in `p`, in source order:

        1.  Evaluate the key `expression` to `k` and call `containsKey()` on the
            value. If this returns `false`, the map does not match.

        2.  Otherwise, evaluate `v[k]` and match the resulting value against
            this entry's value subpattern. If it does not match, the map does
            not match.

    5.  The match succeeds if all entry subpatterns match.

*   **Record**:

    1.  If the runtime type of `v` is not a subtype of the required type of `p`,
        then the match fails.

    2.  For each field `f` in `p`, in source order:

        1.  Access the corresponding field in record `v` as `r`.

        2.  Match the subpattern of `f` against `r`. If the match fails, the
            record match fails.

    3.  The match succeeds if all field subpatterns match.

*   **Object**:

    1.  If the runtime type of `v` is not a subtype of the required type of `p`
        then the match fails.

    2.  Otherwise, for each field `f` in `p`, in source order:

        1.  Call the getter with the same name as `f` on `v`, and let the result
            be `r`. The getter may be an in-scope extension member.

        2.  Match the subpattern of `f` against `r`. If the match fails, the
            object match fails.

    3.  The match succeeds if all field subpatterns match.

### Side effects and exhaustiveness

You might expect this to be soundly exhaustive:

```dart
var n = switch (something) {
  case Bitbox(b: true): 1;
  case Bitbox(b: false): 2;
}
```

However, Bitbox could be defined like:

```dart
class Bitbox {
  bool get b => Random().nextBool();
}
```

Pattern matching in other languages is often restricted to values that are known
by the compiler to be fully immutable, but we want to allow users to use pattern
matching in Dart for the kinds of objects they already use, including mutable
lists and maps and instances of user-defined classes whose getters can't be
proven to be pure and side-effect free. At the same time, we also want to ensure
that exhaustiveness checking is correct and sound.

To balance those, pattern matching operates on an *immutable snapshot of the
properties of the matched value that are seen by the patterns*. The way this
works is that whenever a member is invoked on the matched value or an object
returned by some previous destructuring, the result is cached. Whenever the same
member is invoked by a later pattern (either a subsequent subpattern, or a
pattern in a later case), we don't invoke the member again and instead use the
previously returned value. This way, all subpatterns and cases see the exact
same portions of the object and from the perspective of the surrounding switch
statement or other construct, the object appears to be immutable.

For example, consider:

```dart
main() {
  var list = [1, 2];
  switch (list) {
    case [1, _] & [_, < 4]: print('first');
    case [int(isEven: true), var a]: print('second $a');
  }
}
```

As written, there appear to be multiple redundant method calls on `list` and the
elements extracted from it. But the actual execution semantics are roughly like:

```dart
main() {
  var list = [1, 2];

  late final $match = list;
  late final $match_length = $match.length;
  late final $match_length_eq2 = $match_length == 2;
  late final $match_0 = $match[0];
  late final $match_1 = $match[1];
  late final $match_0_eq1 = $match_0 == 1;
  late final $match_1_lt4 = $match_1 < 4;
  late final $match_0_isEven = $match_1.isEven;
  late final $match_0_isEven_eqtrue = $match_0_isEven == true;

  if ($match_length_eq2 &&
      $match_0_eq1 &&
      $match_length_eq2 &&
      $match_1_lt4) {
    print('first');
  } else if ($match_length_eq2 &&
      $match_0_isEven_eqtrue) {
    var a = $match_1;
    print('second $a');
  }
}
```

Note that every method call is encapsulated in a `late` variable ensuring that
it only gets invoked once even when used by multiple patterns.

It works like this:

1.  At compile time, after type checking has completed, we associate an
    *invocation key* with every member call or record field access potentially
    made by each pattern.

2.  At runtime, whenever the runtime semantics say to call a member or access a
    record field, if a previous call or access with that same invocation key has
    already been evaluated, we reuse the result.

3.  Otherwise, we invoke the member or field access now and associate the result
    with that invocation key for future calls.

Let an *invocation key* comprise:

*   A possibly absent parent invocation key.
*   A possibly absent extension and list of type arguments. If the invocation
    represents an extension member call, this tracks the extension declaration
    the call was resolved to, and the type arguments for it.
*   A member name.
*   A possibly empty list of argument constant values.

Two invocation keys are equivalent if and only if all of these are true:

*   They both have parent invocation keys and the keys are equivalent or
    neither of them have parent invocation keys.
*   The extension types refer to the same type or are both absent.
*   The member names are the same.
*   The argument lists have the same length and all corresponding pairs of
    argument constant values are identical.

*In other words, they're equal if all of their fields are equal in the obvious
ways.*

The notation `parent : (name, args)` creates an invocation key with parent
`parent`, no extension, member name `name`, and argument list `args`. The
notation `parent : extension(name, args)` creates an invocation key with parent
`parent`, extension `extension` (with its type arguments), member name `name`,
and argument list `args`.

Given a set of patterns `s` matching a value expression `v`, we bind an
invocation key to each member invocation and record field access in `s` like so:

1.  Let `i` be an invocation key with no parent, no extension type, named
    `this`, with an empty argument list. *This is the root node of the
    invocation key tree and represents the matched value itself.*

2.  For each pattern `p` in `s` with parent invocation `i`, bind invocation keys
    to it and its subpatterns using the following procedure:

To bind invocation keys in a pattern `p` using parent invocation `i`:

*   **Logical-or** or **logical-and**:

    1.  Bind invocations in the left and right subpatterns using parent `i`.

*   **Relational**:

    1.  If the matched value type is `dynamic`, is `Never`, or declares the
        operator, then bind `i : (op, [arg])` to the operator method invocation
        where `op` is the name of the operator and `arg` is the right operand
        value.

    2.  Else perform extension method resolution and infer the extension's type
        arguments. Bind `i : extension(op, [arg])` to the operator method
        invocation where `extension` is the resolved extension and its type
        arguments, `op` is the name of the operator and `arg` is the right
        operand value.

*   **Cast**, **null-check**, **null-assert**, or **parenthesized**:

    1.  Bind invocations in the subpattern using parent `i`.

*   **Constant**:

    1.  Bind `i : ("constant==", [arg])` to the `==` method invocation where
        `arg` is the constant value. *The odd `constant==` name is because
        constant patterns call `constant == value` while relational `==`
        patterns call `value == constant`. Those can be different methods so we
        need to cache them separately.*

*   **Variable**:

    1.  Nothing to do.

*   **List**:

    1.  Bind `i : ("length", [])` to the `length` getter invocation.

    2.  For each element subpattern `s`:

        1.  If `s` is a rest element:

            1.  Let `e` be `i : ("sublist()", [h, t])` where `h` is the number
                of elements preceding `s` and `t` is the number of elements
                following it.

                *Note that the actual end argument passed to `sublist()` is
                `length - t`, but we just use `t` for the invocation key here
                since the length of the list isn't a syntactically known
                property. Since the list and its length are cached too, using
                `t` is sufficient to distinguish calls to `sublist()` that are
                different, like `[...] & [..., a]` while caching calls that are
                the same as in `[..., a] & [..., b]`.*

            2.  Bind `e` to the `sublist()` invocation for `s`.

        2.  Else if `s` precedes a rest element (or there is no rest element):

            1.  Let `e` be `i : ("[]", [index])` where `index` is the zero-based
                index of this element subpattern.

            2.  Bind `e` to the `[]` invocation for `s`.

        3.  Else `s` is a non-rest element after the rest element:

            1.  Let `e` be `i : ("tail[]", [index])` where `index` is the
                zero-based index of this element subpattern.

                *Note the "tail" in the invocation key name. This is to
                distinguish elements after a rest element at some position from
                elements at the same position but not following a rest element,
                as in:*

                ```dart
                switch (list) {
                  case [var a, ..., var c]: ...
                  case [var a, _,   var d]: ...
                }
                ```

                *Here, `c` and `d` may have different values and `d` should not
                use the previously cached value of `c` even though they are both
                the third element of the same list. So we use an invocation key
                of "[]" for `c` and "tail[]" for `d`.*

            2.  Bind `e` to the `[]` invocation for `s`.

        3.  Bind invocations in the element subpattern using parent `e`.

*   **Map**:

    1.  Bind `i : ("length", [])` to the `length` getter invocation.

    2.  For each entry in `p`:

        1.  Bind `i : ("containsKey()", [key])` to the `containsKey()`
            invocation where `key` is entry's key constant value.

        2.  Let `e` be `i : ("[]", [key])` where `key` is entry's key constant
            value.

        3.  Bind `e` to the `[]` invocation for this entry.

        4.  Bind invocations in the entry value subpattern using parent `e`.

*   **Record**:

    1.  For each field `f` in `p`:

        1.  Let `f` be `i : (field, [])` where `field` is the corresponding
            getter name for the field.

        2.  Bind `e` to the field accessor for this field.

        3.  Bind invocations in the field subpattern using parent `e`.

*   **Object**:

    1.  For each field in `p`:

        1.  If the matched value type is `dynamic`, is `Never`, or declares a
            getter with the same name as the field, then let `f` be `i : (field,
            [])` where `field` is the name of the getter.

        2.  Else perform extension method resolution and infer the extension's
            type arguments. Let `f` be `i : extension(field, [])` where
            `extension` is the resolved extension and its type arguments and
            `field` is the name of the getter.

        3.  Bind `f` to the getter for this field.

        4.  Bind invocations in the field subpattern using parent `f`.

## Severability

This proposal, along with the records and exhaustiveness documents it depends
on, is a lot of new language work. There is new syntax to parse, new type
checking and inference features (including quite complex exhaustiveness
checking), a new kind of object that needs a runtime representation and runtime
type, and new imperative behavior.

It might be too much to fit into a single Dart release. However, it isn't
necessary to ship every corner of these proposals all at once. If needed for
scheduling reasons, we could stage it across several releases.

Here is one way it could be broken down into separate pieces:

*   **Records and destructuring.** Record expressions and record types are one
    of the most-desired aspects of this proposal. Currently, there is no
    expression syntax for accessing positional fields from a record. That means
    we need destructuring. So, at a minimum:

    *   Record expressions and types
    *   Pattern variable declarations
    *   Record patterns
    *   Variable patterns

    This would not include any refutable patterns, so doesn't need the changes
    to allow patterns in switches.

*   **Collection destructuring.** A minor extension of the above is to also
    allow destructuring the other built-in aggregate types:

    *   List patterns
    *   Map patterns

*   **Objects.** I don't want patterns to feel like we're duct taping a
    functional feature onto an object-oriented language. To integrate it more
    gracefully means destructuring user-defined types too, so adding:

    *   Object patterns

*   **Refutable patterns.** The next big step is patterns that don't just
    destructure but *match*. The bare minimum refutable patterns and features
    are:

    *   Patterns in switch statement cases
    *   Switch case guards
    *   Exhaustiveness checking
    *   Constant patterns
    *   Relational patterns (at least `==`)

    The only critical relational pattern is `==` because once we allow patterns
    in switch cases, we lose the ability to have a bare identifier constant in
    a switch case.

*   **Type testing patterns.** The other type-based patterns aren't critical but
    do make patterns more convenient and useful:

    *   Null-check patterns
    *   Null-assert patterns
    *   Cast patterns

*   **Control flow.** Switch statements are heavyweight. If we want to make
    refutable patterns more useful, we eventually want:

    *   Switch expressions
    *   Pattern-if statements

*   **Logical patterns.** If we're going to add `==` patterns, we may as well
    support other Boolean infix operators. And if we're going to support the
    comparison operators, then `&` is useful for numeric ranges. It's weird to
    have `&` without `|` so we may as well do that too (and it's useful for
    switch expressions). Once we have infix patterns precedence comes into play,
    so we need parentheses to control it:

    *   Relational patterns (other than `==`)
    *   Logical-or patterns
    *   Logical-and patterns
    *   Parenthesized patterns

## Changelog

### 2.16

-   Eliminate `case` and `default` from switch expressions and use `,` as the
    case separator (#2126).

-   Add if-case elements (#2542).

### 2.15

-   Error if named fields in record or object patterns collide (#2610).

### 2.14

-   Rename "extractor" patterns to "object" patterns (#2562). There are no
    semantic changes.

### 2.13

-   Refine variable and scoping rules in cases that share a body (#2553).

### 2.12

-   Add `...` rest patterns in list and map patterns (#2453).

-   Change context type schema to consistently use `?` in patterns where the
    type isn't known instead of `?` for unannotated variable patterns and
    `Object?` for other patterns.

### 2.11

-   Clarify implicit coercions and casts (#2488).

### 2.10

-   Tweak the rules for type checking List/Map patterns, so that explicit
    type arguments in the pattern are used as the type the elements are
    type checked against.

### 2.9

-   Clarify scoping rules and loosen restrictions on variables in cases with a
    shared body (#2473, #2485, #2533).

### 2.8

-   Upgrade non-exhaustive switch statements on enums from a warning to an
    error (#2474).

### 2.7

-   Clarify that relational and extractor patterns can call extension members
    (#2457).

-   Non-boolean results throw in relational patterns instead of failing the
    match (#2461).

-   Specify that map and extractor subpatterns are evaluated in source order
    (#2466).

-   Specify non-exhaustive switch errors and warnings (#2474).

-   Allow `final` before type annotated variable patterns (#2486).

-   Rename some grammars to align with Analyzer AST names (#2491).

-   Propagate `dynamic` into fields when type checking a record pattern against
    a matched value of type `dynamic`.

### 2.6

-   Change logical-or and logical-and patterns to be left-associative.

### 2.5

-   Move back to a syntax where variable declarations are explicit in cases but
    not in pattern declarations (but otherwise keep the unified grammar). Allow
    simple identifier constant patterns in cases.

-   Allow cast patterns to take a subpattern instead of just a variable name.

-   Only allow pattern assignments to assign to locals.

-   Don't allow unary patterns to nest.

-   Merge literal and constant patterns into a single kind of pattern and
    extend them to allow const constructor calls and `const` followed by a
    primary expression.

-   Replace pattern-if with if-case statements. Allow guard clauses.

-   Use the pattern context type schema for assignments but not if-case.

-   Disallow `nullCheckPattern` in `outerPattern`. Now that if-case no longer
    uses `outerPattern`, there's no point in allowing it.

### 2.4

-   Add destructuring assignment (#2438).

-   Specify the context type for empty list and map patterns (#2441).

-   Define a grammar rule for the outermost patterns in a declaration (#2446).

-   Rename "grouping" patterns to "parenthesized" patterns (#2447).

-   Specify behavior of patterns in for loops (#2448).

-   Make logical-or and null-check patterns always refutable.

### 2.3

-   Specify that switches throw a runtime error if values from legacy libraries
    flow in and break exhaustiveness checking (#2123).

-   Allow empty list, map, and record patterns (#2441).

-   Clarify ambiguity between grouping and record patterns.

### 2.2

-   Make map patterns check length like list patterns do (#2415).

-   Clarify that variables in cases are not final (#2416).

### 2.1

Minor tweaks:

-   Define the static type of switch expressions (#2380).

-   Clarify semantics of runtime type tests (#2385).

-   Allow relational operators whose return type is `dynamic`.

### 2.0

Major redesign of the syntax and minor redesign of the semantics.

-   Unify binder and matcher patterns into a single grammar. Refutable patterns
    are still prohibited outside of contexts where failure can be handled using
    control flow, but the grammar is unified and more patterns can be used in
    the other context. For example, null-assert patterns can be used in switch
    cases.

-   Always treat simple identifiers as variables in patterns, even in switch
    cases.

-   Change the `if (expr case pattern)` syntax to `if (var pattern = expr)`.

-   Change the guard syntax to `when expr`.

-   Record patterns match only record objects. Extractor patterns (which can
    now be used in variable declarations) are the only way to call getters on
    abitrary objects.

-   New patterns for relational operators, `|`, `&`, and `(...)`. Set up a
    precedence hierarchy for patterns.

-   Get rid of explicit wildcard patterns since they're redundant with untyped
    variable patterns named `_`.

-   Don't allow extractor patterns to match enum values. (It doesn't seem that
    well motivated and could be added later if useful.)

-   Remove support for `late` pattern variable declarations, patterns in
    top-level variables, and patterns in fields. The semantics get pretty weird
    and it's not clear that they're worth it.

-   Change the static typing rules significantly in a number of ways.

-   Remove type patterns. They aren't fully baked, are pretty complex, and don't
    seem critical right now. We can always add them as a later extension.

### 1.8

-   Remove declaration matcher from the proposal. It's only a syntactic sugar
    convenience and seems to cause enough confusion that it's not clear if it
    carries its weight. Removing it simplifies the feature some and we can
    always add it in a future version.

-   Remove the `Destructure_n_` interface. Positional record fields can only be
    used to destructure positional fields from actual record objects. (We may
    extend this later.)

-   Revise and clarify how types work in record and extractor patterns.

### 1.7

-   Fix object destructuring examples and clarify that extract matchers support
    the named field destructuring shorthand too ([#2193][]).

[#2193]: https://github.com/dart-lang/language/issues/2193

### 1.6

-   Change syntax of if-case statement ([#2181][]).

[#2181]: https://github.com/dart-lang/language/issues/2181

### 1.5

-   Introduce and clarify type inference.

-   The context type schema for a variable matcher is always `Object?`, since
    it's intent is to *match* a type and *cause* the expression to have some
    type.

### 1.4

-   Link to [exhaustiveness][] proposal.

### 1.3

-   Avoid unbounded lookahead with switch expression in an expression statement
    ([#2138][]).

-   Re-introduce rule that `_` is non-binding in all patterns, not just
    wildcards.

[#2138]: https://github.com/dart-lang/language/issues/2138

### 1.2

-   Add a shorthand for destructuring a named record field to a variable with
    the same name.

-   Add if-case statement.

-   Allow extractor patterns to match enum values.

-   Add null-assert binder `!` and null-check `?` matcher patterns.

### 1.1

-   Copy editing and clean up.

-   Add `nullLiteral` to literal patterns.

-   Add wildcard binder patterns. Remove exception that variable patterns named
    `_` don't bind.
