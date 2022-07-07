# Patterns Feature Specification

Author: Bob Nystrom

Status: In progress

Version 2.0 (see [CHANGELOG](#CHANGELOG) at end)

Note: This proposal is broken into a couple of separate documents. See also
[records][] and [exhaustiveness][].

[records]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/records-feature-specification.md

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
*   [Type patterns](https://github.com/dart-lang/language/issues/170) (9 👍)
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

### Extracting runtime type arguments

Dart reifies instances of generic types and keeps their type arguments at
runtime, but there is no good way for a user to extract that runtime type
argument. For example, let's say you want to write a function that takes a
`List` of some element type and converts it to a `Set` of the same type. (In
practice, you would use `Iterable.toSet()`, but imagine that didn't exist.) You
might write:

```dart
Set<T> listToSet<T>(List<T> items) {
  return <T>{...items};
}
```

This mostly works:

```dart
main() {
  var ints = <int>[1, 2, 3];
  var intSet = listToSet(ints);
  print(intSet.runtimeType); // Prints "Set<int>".
}
```

But that function returns a `Set` whose type argument is the *static* type of
the given `List`, not its *runtime* type:

```dart
main() {
  // Upcast:
  List<Object> ints = <int>[1, 2, 3];
  var intSet = listToSet(ints);
  print(intSet.runtimeType); // Prints "Set<Object>".
}
```

Here, even though the actual `List` object passed to `listToSet()` is still a
`List<int>`, the returned `Set` is reified with `Object` because the
`listToSet()` sees only the static type of the argument.

We can use patterns to let you extract the *runtime* type arguments of an
instance of a generic type, like so:

```dart
Set<T> listToSet<T>(List<T> items) {
  List<final E> _ = items;
  return <E>{...items};
}
```

Here, the `final E` in the local variable's type annotation is a *type pattern*
that matches and destructures the runtime type argument from `items`.

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
| [Or][orPattern] | `subpattern1 \| subpattern2` |
| [And][andPattern] | `subpattern1 & subpattern2` |
| [Relational][relationalPattern] | `== expression`<br>`< expression` |
| [Null-check][nullCheckPattern] | `subpattern?` |
| [Null-assert][nullAssertPattern] | `subpattern!` |
| [Literal][literalPattern] | `123`, `null`, `'string'` |
| [Constant][constantPattern] | `math.pi`, `SomeClass.constant` |
| [Variable][variablePattern] | `foo`, `String str`, `_`, `int _` |
| [Cast][castPattern] | `foo as String` |
| [Grouping][groupingPattern] | `(subpattern)` |
| [List][listPattern] | `[subpattern1, subpattern2]` |
| [Map][mapPattern] | `{"key": subpattern}` |
| [Record][recordPattern] | `(subpattern1, subpattern2)`<br>`(x: subpattern1, y: subpattern2)` |
| [Extractor][extractorPattern] | `SomeClass(x: subpattern1, y: subpattern2)` |
| [Type][typePattern] | `List<final T>` |

[orPattern]: #or-pattern
[andPattern]: #and-pattern
[relationalPattern]: #relational-pattern
[nullCheckPattern]: #null-check-pattern
[nullAssertPattern]: #null-assert-pattern
[literalPattern]: #literal-pattern
[constantPattern]: #constant-pattern
[variablePattern]: #variable-pattern
[castPattern]: #cast-pattern
[groupingPattern]: #grouping-pattern
[listPattern]: #list-pattern
[mapPattern]: #map-pattern
[recordPattern]: #record-pattern
[extractorPattern]: #extractor-pattern
[typePattern]: #type-pattern

Here is the overall grammar for the different kinds of patterns:

```
pattern               ::= orPattern
patterns              ::= pattern ( ',' pattern )* ','?

orPattern             ::= andPattern ( '|' orPattern )?
andPattern            ::= relationalPattern ( '&' andPattern )?
relationalPattern     ::= ( equalityOperator | relationalOperator) relationalExpression
                        | unaryPattern

unaryPattern          ::= nullCheckPattern
                        | nullAssertPattern
                        | primaryPattern

primaryPattern        ::= literalPattern
                        | constantPattern
                        | variablePattern
                        | castPattern
                        | groupingPattern
                        | listPattern
                        | mapPattern
                        | recordPattern
                        | extractorPattern
```

As you can see, or patterns (`|`) have the lowest precedence, then and patterns
(`&`), then the postfix unary null-check (`?`) and null-assert (`!`) patterns,
followed by the remaining highest precedence primary patterns.

The individual patterns are:

### Or pattern

```
orPattern ::= andPattern ( '|' orPattern )?
```

A pair of patterns separated by `|` matches if either of the branches match.
This can be used in a switch expression or statement to have multiple cases
share a body:

```dart
var isPrimary = switch (color) {
  case Color.red | Color.yellow | Color.blue => true;
  default => false;
};
```

Even in switch statements, which allow multiple empty cases to share a single
body, an or pattern can be useful when you want multiple patterns to share a
guard:

```dart
switch (shape) {
  case Square(size) | Circle(size) when size > 0:
    print('Non-empty symmetric shape');
  case Square() | Circle():
    print('Empty symmetric shape');
  default:
    print('Asymmetric shape');
}
```

An or pattern does not have to appear at the top level of a pattern. It can be
nested inside a destructuring pattern:

```dart
// Matches a two-element list whose first element is 'a' or an int:
if (var ['a' | int _, c] = list) ...
```

An or pattern may match even if one of its branches does not. That means that
any variables in the non-matching branch would not be initialized. To avoid
problems stemming from that, the following restrictions apply:

*   It is a compile-time error if one branch contains a variable pattern whose
    name or type does not exactly match a corresponding variable pattern in the
    other branch. These variable patterns can appear as subpatterns anywhere in
    each branch, but in total both branches must contain the same variables with
    the same types. This way, variables used inside the body covered by the
    pattern will always be initialized to a known type.

*   If the left branch matches, the right branch is not evaluated. This
    determines *which* value the variable gets if both branches would have
    matched. In that case, it will always be the value from the left branch.

### And pattern

```
andPattern ::= relationalPattern ( '&' andPattern )?
```

A pair of patterns separated by `&` matches only if *both* subpatterns match.
Unlike or patterns, each branch may define different variables, since the
and pattern only matches if both branches do.

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

The `==` operator is sometimes useful for matching named constants when the
constant doesn't have a qualified name:

```dart
void test(int value) {
  const magic = 123;
  switch (value) {
    case == magic: print('Got the magic number');
    default: print('Not the magic number');
  }
}
```

The comparison operators are useful for matching on numeric ranges, especially
when combined with `&`:

```dart
String asciiCharType(int char) {
  const space = 32;
  const zero = 48;
  const nine = 57;

  return switch (char) {
    case < space => 'control';
    case == space => 'space';
    case > space & < zero => 'punctuation';
    case >= zero <= nine => 'digit';
    // Etc...
  }
}
```

### Null-check pattern

```
nullCheckPattern ::= unaryPattern '?'
```

A null-check pattern matches if the value is not null, and then matches the
inner pattern against that same value. Because of how type inference flows
through patterns, this also provides a terse way to bind a variable whose type
is the non-nullable base type of the nullable value being matched:

```dart
String? maybeString = ...
if (var s? = maybeString) {
  // s has type non-nullable String here.
}
```

Using `?` to match a value that is *not* null seems counterintuitive. In truth,
there is no ideal syntax for this. The way I think about `?` is that it
describes the test it performs. Where a list pattern tests whether the value is
a list, a `?` tests whether the value is null. However, unlike other patterns,
it matches when the value is *not* null, because matching on null isn't
useful&mdash;you could always just use a `null` literal pattern for that.

Swift [uses the same syntax for a similar feature][swift null check].

[swift null check]: https://docs.swift.org/swift-book/ReferenceManual/Patterns.html#ID520

### Null-assert pattern

```
nullAssertPattern ::= unaryPattern '!'
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
if (var ['user', name!] = row) {
  // name is a non-nullable string here.
}
```

### Literal pattern

```
literalPattern ::= booleanLiteral | nullLiteral | numericLiteral | stringLiteral

```

A literal pattern determines if the value is equivalent to the given literal
value. There are no list and map *literal* patterns since there are actual list
and map patterns.

**Breaking change**: Using patterns in switch cases means that a list or map
literal in a switch case is now interpreted as a list or map pattern which
destructures its elements at runtime. Before, it was simply treated as identity
comparison.

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

### Constant pattern

```
constantPattern ::= qualifiedName
```

Like literal patterns, a named constant pattern determines if the matched value
is equal to the constant's value.

Only qualified names can be used as constant patterns. That includes prefixed
constants like `some_library.aConstant`, static constants on classes like
`SomeClass.aConstant`, and prefixed static constants like
`some_library.SomeClass.aConstant`. It does *not* allow references to named
constants that are simple identifiers. Those are ambiguous with variable
patterns and the language resolves the ambiguity by treating it as a variable
pattern:

```dart
void test() {
  const localConstant = 1;
  switch (2) {
    case localConstant: print('matched!');
    default: print('unmatched');
  }
}
```

This prints "matched!" because `localConstant` in the case is interpreted as a
*variable* pattern that matches any value and binds the value to a new variable
with that name.

**Breaking change:** This is a breaking change for simple identifiers that
appear in existing switch cases. Fortunately, it turns out that most switch
cases are not simple named constants. I analyzed a large corpus of Pub packages
and Flutter apps (13M+ lines in 61,346 files):

```
    -- Case (81469 total) --
  43469 ( 53.356%): literal                   ===================
  34960 ( 42.912%): prefixed.identifier       ===============
   2855 (  3.504%): identifier                ==
    171 (  0.210%): prefixed.property.access  =
      7 (  0.009%): SymbolLiteralImpl         =
      4 (  0.005%): MethodInvocationImpl      = (const ctor calls)
      3 (  0.004%): FunctionReferenceImpl     = (type literals)
```

Named constants are common in switch cases, but most of them are *qualified*
identifiers like `SomeEnum.value` or `prefix.aConstant`. Switches using a simple
identifier are only 3.5% of the cases. Most come from just a couple of packages
and most of those are from using the charcode package. Changing those to use an
import prefix would eliminate most of that already small 3.5%.

In rare cases where you do need a pattern to refer to a named constant with a
simple identifier name, you can use an explicit `==` pattern:

```dart
void test() {
  const localConstant = 1;
  switch (2) {
    case == localConstant: print('matched!');
    default: print('unmatched');
  }
}
```

This prints "unmatched".

**TODO: We should add a lint that warns if a variable pattern shadows an
in-scope constant since it's likely a mistaken attempt to match the constant.**

### Variable pattern

```
variablePattern ::= type? identifier
```

A variable pattern binds the matched value to a new variable. These usually
occur as subpatterns of a destructuring pattern in order to capture a
destructured value.

```dart
var (a, b) = (1, 2);
```

Here, `a` and `b` are variable patterns and end up bound to `1` and `2`,
respectively.

The pattern may also have a type annotation in order to only match values of the
specified type. If the type annotation is omitted, the variable's type is
inferred and the pattern matches all values.

```dart
if ((int x, String s) = record) {
  print('First field is int $x and second is String $s.');
}
```

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
if ((int _, String _) = record) {
  print('First field is int and second is String.');
}
```

### Cast pattern

```
castPattern ::= identifier 'as' type
```

A cast pattern is similar to a variable pattern in that it binds a new variable
to the matched value with a given type. But where a variable pattern is
*refuted* if the value doesn't have that type, a cast pattern *throws*. Like the
null-assert pattern, this lets you forcibly assert the expected type of some
destructured value. This isn't useful as the outermost pattern in a declaration
since you can always move the `as` to the initializer expression:

```dart
num n = 1;
var i as int = n; // Instead of this...
var i = n as int; // ...do this.
```

But when destructuring, there is no place in the initializer to insert the cast.
This pattern lets you insert the cast as values are being pulled out by the
pattern:

```dart
(num, Object) record = (1, "s");
var (i as int, s as String) = record;
```

### Grouping pattern

```
groupingPattern ::= '(' pattern ')'
```

Like parenthesized expressions, parentheses in a pattern let you control pattern
precedence and insert a lower precedence pattern where a higher precedence one
is expected.

### List pattern

```
listPattern ::= typeArguments? '[' patterns ']'
```

A list pattern matches an object that implements `List` and extracts elements by
position from it.

It is a compile-time error if `typeArguments` is present and has more than one
type argument.

**TODO: Allow a `...` element in order to match suffixes or ignore extra
elements. Allow capturing the rest in a variable.**

### Map pattern

```
mapPattern        ::= typeArguments? '{' mapPatternEntries '}'
mapPatternEntries ::= mapPatternEntry ( ',' mapPatternEntry )* ','?
mapPatternEntry   ::= expression ':' pattern
```

A map pattern matches values that implement `Map` and accesses values by key
from it.

It is a compile-time error if:

*   `typeArguments` is present and there are more or less than two type
    arguments.

*   Any of the entry key expressions are not constant expressions.

*   Any pair of key expressions evaluate to equivalent values.

### Record pattern

```
recordPattern         ::= '(' patternFields ')'
patternFields         ::= patternField ( ',' patternField )* ','?
patternField          ::= ( identifier? ':' )? pattern
```

A record pattern matches a record object destructures
its fields. If the value isn't a record with the same shape as the pattern, then
the match fails. Otherwise, the field subpatterns are matched against the
corresponding fields in the record.

Field subpatterns can be in one of three forms:

*   A bare `pattern` destructures the corresponding positional field from the
    record and matches it against `pattern`.

*   A `identifier: pattern` destructures the named field with the name
    `identifier` and matches it against `pattern`.

*   A `: pattern` is a named field with the name omitted. When destructuring
    named fields, it's very common to want to bind the resulting value to a
    variable with the same name. As a convenience, the identifier can be omitted
    on a named field. In that case, the name is inferred from `pattern`. The
    subpattern must be a variable pattern or cast pattern, which may be wrapped
    in any number of null-check or null-assert patterns.

    The field name is then inferred from the name in the variable or cast
    pattern. These pairs of patterns are each equivalent:

    ```dart
    // Variable:
    (untyped: untyped, typed: int typed)
    (:untyped, :int typed)

    // Null-check and null assert:
    (checked: checked?, asserted: asserted!)
    (:checked?, :asserted!)

    // Cast:
    (field: field as int)
    (:field as int)
    ```

**TODO: Allow a `...` element in order to ignore some positional fields while
capturing the suffix.**

### Extractor pattern

```
extractorPattern ::= extractorName typeArguments? '(' patternFields? ')'
extractorName    ::= typeIdentifier | qualifiedName
```

An extractor matches values of a given named type and then extracts values from
it by calling getters on the value. Extractor patterns let users destructure
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
    case Rect(width: w, height: h): print('Rect $w x $h');
    default: print(obj);
  }
}
```

You can also use an extractor to both match an enum value and destructure
fields from it:

```dart
enum Severity  {
  error(1, "Error"),
  warning(2, "Warning");

  Severity(this.level, this.prefix);

  final int level;
  final String prefix;
}

log(Severity severity, String message) {
  switch (severity) {
    case Severity.error(prefix: p):
      print('!! $p !! $message'.toUppercase());
    case Severity.warning(prefix: p):
      print('$p: $message');
  }
}
```

The `extractorName` must refer to a named type or an enum value. (If you want to
use an extractor with a function type, you can use a typedef.)

It is a compile-time error if:

*   `extractorName` does not refer to a type or enum value.

*   A type argument list is present and does not match the arity of the type of
    `extractorName` or `extractorName` is an enum value.

*   A `patternField` is of the form `pattern`. Positional fields aren't allowed.

As with record patterns, the getter name can be omitted in which case it is
inferred from the variable or cast pattern in the field subpattern, which may be
wrapped in null-check or null-assert patterns. The previous example could be
written like:

```dart
log(Severity severity, String message) {
  switch (severity) {
    case Severity.error(:prefix):
      print('!! $prefix !! $message'.toUppercase());
    case Severity.warning(:prefix):
      print('$prefix: $message');
  }
}
```

### Type pattern

Type patterns allow extracting the runtime type arguments from objects. Extend
the `type` grammar like so:

```
type ::= functionType '?'?
  | typeNotFunction
  | typePattern // New.

typePattern ::= 'final' identifier
```

Type patterns can only be used in certain contexts. It would be pretty confusing
to allow:

```dart
print(<final E>[]);
```

It is a compile-time error if a `typePattern` appears anywhere except inside
the `typeArguments` in:

*   A `listPattern`.
*   A `mapPattern`.
*   A `extractorPattern`.
*   The type annotation in a `localVariableDeclaration`.

**TODO: Specify this restriction more precisely.**

**TODO: Should we expand this to allow type patterns in for-loop variables,
fields, or top-level variables?**

The type pattern may be nested inside the allowed type argument list or record
type. For example:

```dart
var List<final E> = ...
var Map<String, List<final V>> = ...
var (final A, b: final B) = ...
```

**TODO: Do we want to support function types? If so, how do we handle
first-class generic function types?**

## Pattern uses

Patterns are woven into the larger language in a few ways:

### Pattern variable declaration

Most places in the language where a variable can be declared are extended to
allow a pattern, like:

```dart
var (a, [b, c]) = ("str", [1, 2]);
```

Dart's existing C-style variable declaration syntax makes it harder to
incorporate patterns. Variables can be declared just by writing their type, and
a single declaration might declare multiple variables. Fully incorporating
patterns into that could lead to confusing syntax like:

```dart
(int, String) (n, s) = (1, "str");
final (a, b) = (1, 2), c = 3, (d, e);
```

To avoid this weirdness, patterns only occur in variable declarations that begin
with a `var` or `final` keyword. Also, a variable declaration using a pattern
can only have a single declaration "section". No comma-separated multiple
declarations like:

```dart
var [a] = [1], (b, c) = (2, 3);
```

Also, declarations with patterns must have an initializer. This is not a
limitation since the point of using a pattern in a variable declaration is to
match it against the initializer's value.

Add this new rule:

```
patternDeclaration ::= ( 'final' | 'var' ) pattern '=' expression
```

It is a compile-time error if the outermost pattern in a `patternDeclaration`
is not one of:

*   [`listPattern`][listPattern]
*   [`mapPattern`][mapPattern]
*   [`recordPattern`][recordPattern]
*   [`extractorPattern`][extractorPattern]
*   [`nullCheckPattern`][nullCheckPattern]

This allows useful code like:

```dart
var [a, b] = [1, 2];                 // List.
var {1: a} = {1: 2};                 // Map.
var (a, b, x: x) = (1, 2, x: 3);     // Record.
var Point(x: x, y: y) = Point(1, 2); // Extractor.
var string? = nullableString;        // Null-check.
```

But excludes other kinds of patterns to prohibit weird code like:

```dart
var String str = 'redundant';     // Variable.
var str as String = 'weird';      // Cast.
var definitely! = maybe;          // Null-assert.
var (pointless) = 'parentheses';  // Grouping.
```

**TODO: Should we support destructuring in `const` declarations?**

This new rule is incorporated into the existing rules for declaring variables
like so:

```
topLevelDeclaration ::=
  | // Existing productions...
  | 'late'? patternDeclaration ';' // New.

localVariableDeclaration ::=
  | initializedVariableDeclaration ';' // Existing.
  | 'late'? patternDeclaration ';' // New.

forLoopParts ::=
  | // Existing productions...
  | patternDeclaration 'in' expression // New.

// Static and instance fields:
declaration ::=
  | // Existing productions...
  | 'static' 'late'? patternDeclaration // New.
  | 'covariant'? 'late'? patternDeclaration // New.
```

### Switch statement

We extend switch statements to allow patterns in cases:

```
switchStatement ::= 'switch' '(' expression ')' '{' switchCase* defaultCase? '}'
switchCase      ::= label* caseHead ':' statements
caseHead        ::= 'case' pattern ( 'when' expression )?
```

Allowing patterns in cases significantly increases the expressiveness of what
properties a case can verify, including executing arbitrary user-defined code.
This implies that the order that cases are checked is now potentially
user-visible and an implementation must execute the *first* case that matches.

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
  case (a, b):
    print('Other order');
}

// This prints "Other order":
switch (pair) {
  case (a, b) when a > b:
    print('First element greater');
  case (a, b):
    print('Other order');
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
primary               ::= // Existing productions...
                        | switchExpression

switchExpression      ::= 'switch' '(' expression ')' '{'
                          switchExpressionCase* defaultExpressionCase? '}'
switchExpressionCase  ::= caseHead '=>' expression ';'
defaultExpressionCase ::= 'default' '=>' expression ';'
```

Slotting into `primary` means it can be used anywhere any expression can appear,
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

#### Expression statement ambiguity

Thanks to expression statements, a switch expression could appear in the same
position as a switch statement. This isn't technically ambiguous, but requires
unbounded lookahead to tell if a switch in statement position is a statement or
expression.

```dart
main() {
  switch (some(extremely, long, expression, here)) {
    case Some(Quite(var long, var pattern)) => expression();
  };

  switch (some(extremely, long, expression, here)) {
    case Some(Quite(var long, var pattern)) : statement();
  }
}
```

To avoid that, we disallow a switch expression from appearing at the beginning
of an expression statement. This is similar to existing restrictions on map
literals appearing in expression statements. In the rare case where a user
really wants one there, they can parenthesize it.

**TODO: If we change switch expressions [to use `:` instead of `=>`][2126] then
there will be an actual ambiguity. In that case, reword the above section.**

[2126]: https://github.com/dart-lang/language/issues/2126

### Pattern-if statement

Often you want to conditionally match and destructure some data, but you only
want to test a value against a single pattern. You can use a `switch` statement
for that, but it's pretty verbose:

```dart
switch (json) {
  case [int x, int y]:
    return Point(x, y);
}
```

We can make simple uses like this a little cleaner by allowing a pattern
variable declaration in place of an if condition:

```dart
if (var [int x, int y] = json) return Point(x, y);
```

It may have an else branch as well:

```dart
if (var [int x, int y] = json) {
  print('Was coordinate array $x,$y');
} else {
  throw FormatException('Invalid JSON.');
}
```

We replace the existing `ifStatement` rule with:

```
ifStatement ::= 'if' '(' ifCondition ')' statement ('else' statement)?

ifCondition ::= expression // Existing if statement condition.
              | patternDeclaration
              | type identifier '=' expression
```

When the `ifCondition` is an `expression`, it behaves as it does today. If the
condition is a `patternDeclaration`, then the expression is evaluated and
matched against the pattern. If it matches, then branch is executed with any
variables the pattern defines in scope. Otherwise, the else branch is executed
if there is one. The third form of `ifCondition` allows simple typed variable
declarations inside the condition:

```dart
num n = ...
if (int i = n) print('$n is an integer $i');
```

This behaves like a typed variable pattern. *We don't allow a typed variable
pattern to appear in `patternDeclaration` to avoid a redundant `var int x`
syntax.*

Unlike `switch`, the pattern-if statement doesn't allow a guard clause. Guards
are important in switch cases because, unlike nesting an if statement *inside*
the switch case, a failed guard will continue to try later cases in the switch.
That is less important here since the only other case is the else branch.

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

Here, we infer `List<int>` for the list pattern based on the type of the element
subpattern. Or downwards:

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

2.  **Calculate the static type of the matched value.** A pattern always occurs
    in the context of some matched value. For pattern variable declarations,
    this is the initializer. For switches and if-case statements, it's the value
    being matched.

    Using the pattern's type schema as a context type, infer missing types on
    the value expression. This is the existing type inference rules on
    expressions. It yields a complete static type for the matched value.

3.  **Calculate the static type of the pattern.** Using that value type, recurse
    through the pattern again downwards to the leaf subpatterns filling in any
    holes in the type schema. When that completes, we now have a full static
    type for the pattern and all of its subpatterns.

The full process only comes into play for pattern variable declarations. For
switch case, and if-case statements, there is no downwards inference from
pattern to value and the first step is skipped. Instead, the type of the matched
value is inferred with no downwards context type and we jump straight to
inferring the types of the case patterns from that context type. *The intent of
a refutable pattern is to query the type of the matched value, so it would be
strange if that query affected the value expression.*

When calculating the context type schema or static type of a pattern, any
occurrence of `typePattern` in a type is treated as `Object?`.

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

To support this, every pattern has a context type schema. This is a type
*schema* because there may be holes in the type:

```dart
var (a, int b) = ... // Schema is `(?, int)`.
```

The context type schema for a pattern `p` is:

*   **Or**: The least upper bound of the context type schemas of the branches.

*   **And**: The greatest lower bound of the context type schemas of the branches.

*   **Null-check** or **null-assert**: A context type schema `E?` where `E` is
    the context type schema of the inner pattern. *For example:*

    ```dart
    var [[int x]!] = [[]]; // Infers List<List<int>?> for the list literal.
    ```

*   **Literal** or **constant**: The context type schema is the static type of
    the pattern's constant value expression.

*   **Variable**:

    *   If the pattern is in a refutable context, the context type schema is
        `Object?`. *We ignore the type annotation in a refutable context because
        the type is being used to test the value's type and shouldn't also
        influence it. This is consistent `is` expressions where we don't use the
        type annotation as a context type when inferring its operand.*

    *   Else if `p` has no type annotation, the context type schema is `?`.
        *This lets us potentially infer the variable's type from the matched
        value.*

    *   Else the context type schema is the annotated type. *When a typed
        variable pattern is used in a destructuring variable declaration, we
        do push the type over to the value for inference, as in:*

        ```dart
        var (items: List<int> x) = (items: []);
        //                                 ^- Infers List<int>.
        ```

*   **Relational** or **cast**: The context type schema is `Object?`.

*   **Grouping**: The context type schema of the inner subpattern.

*   **List**: A context type schema `List<E>` where:

    *   If `p` has a type argument, then `E` is the type argument.

    *   Else `E` is the greatest lower bound of the type schemas of all element
        subpatterns. *We use the greatest lower bound to ensure that the outer
        collection type has a precise enough type to ensure that any typed field
        subpatterns do not need to downcast:*

        ```dart
        var [int a, num b] = [1, 2];
        ```

        *Here, the GLB of `int` and `num` is `int`, which ensures that neither
        `int a` nor `num b` need to downcast their respective fields.*


*   **Map**: A type schema `Map<K, V>` where:

    *   If `p` has type arguments then `K`, and `V` are those type arguments.

    *   Else `K` is the least upper bound of the types of all key expressions
        and `V` is the greatest lower bound of the context type schemas of all
        value subpatterns.

*   **Record**: A record type schema with positional and named fields
    corresponding to the type schemas of the corresponding field subpatterns.

*   **Extractor**:

    *   If the pattern is in a refutable context, the type schema is `Object?`.
        *As with variable patterns, we ignore the extractor's annotated type in
        a refutable because the pattern is used to match that type.*

    *   Else the type the extractor name resolves to. *This lets inference
        fill in type arguments in the value based on the extractor's type
        arguments, as in:*

        ```
        var Foo<num>(x) = Foo();
        //                   ^-- Infer Foo<num>.
        ```

        *The extractor name can't refer to an enum value in this case, since
        an enum value extractor pattern can't appear in an irrefutable context.*

#### Pattern static type

Once the value a pattern is matched against has a static type (which means
downwards inference on it using the pattern's context type schema is complete),
we can calculate the static type of the pattern.

The value's static type is used to do upwards type inference on the pattern for
patterns in variable declarations and switches. Also, a pattern's static type
may be used for "downwards" ("inwards"?) inference of a pattern's subpatterns
in the same way that a collection literal's type argument is used for inference
on the collection's elements.

Some examples and the corresponding pattern static types:

```dart
var <int>[a, b] = <num>[1, 2];  // List<int> (and compile error).
var [a, b] = <num>[1, 2];       // List<num>, a is num, b is num.
var [int a, b] = <num>[1, 2];   // List<int>.
```

Putting this together, it means the process of completely inferring the types of
a construct using patterns works like:

1. Calculate the context type schema of the pattern.
2. Use that in downwards inference to calculate the type of the matched value.
3. Use that to calculate the static type of the pattern.

The static type of a pattern `p` being matched against a value of type `M` is:

*   **Or**:

    1.  Calculate the static types of each branch using `M` as the matched
        value type.

    2.  The static type of `p` is the least upper bound of those branch types.

*   **And**:

    1.  Calculate the static types of each branch using `M` as the matched
        value type.

    2.  The static type of `p` is the greatest lower bound of those branch
        types.

*   **Relational**:

    1.  It the operator is a comparison (`<`, `<=`, `>`, or `>=`), then it is a
        compile-time error if `M` does not define that operator, or if the type
        of the constant in the relational pattern is not a subtype of the
        operator's parameter type. *The `==` and `!=` operators are valid for
        all pairs of types.*

    2.  The static type of `p` is `Object?`.

*   **Null-check** or **null-assert**:

    1.  If `M` is `N?` for some type `N` then calculate the static type `q` of
        the inner pattern using `N` as the matched value type. Otherwise,
        calculate `q` using `M` as the matched value type. *A null-check or
        null-assert pattern removes the nullability of the type it matches
        against.*

        ```dart
        var [x!] = <int?>[]; // x is int.
        ```

    2.  The static type of `p` is `q?`. *The intent of `!` and `?` is only to
        remove nullability and not cast from an arbitrary type, so they accept a
        value of its nullable base type, and not simply `Object?`.*

*   **Literal** or **constant**: The static type of `p` is the static type of
    the pattern's value expression.

*   **Variable**:

    1.  If the variable has a type annotation, the type of `p` is that type.

    2.  Else the type of `p` is `M`. *This means that an untyped variable
        pattern can have its type indirectly inferred from the type of a
        superpattern:*

        ```dart
        var <(num, Object)>[(a, b)] = [(1, true)]; // a is num, b is Object.
        ```

        *The pattern's context type schema is `List<(num, Object>)`. Downwards
        inference uses that to infer `List<(num, Object>)` for the initializer.
        That inferred type is then destructured and used to infer `num` for `a`
        and `Object` for `b`.*

*   **Cast**: The static type of `p` is `Object?`. *Casts exist to check types
    at runtime, so statically accept all types.*

*   **Grouping**: The static type of the inner subpattern using `M` as the
    matched value type.

*   **List**:

    1.  Calculate the value's element type `E`:

        1.  If `M` implements `List<T>` for some `T` then `E` is `T`.

        2.  Else if `M` is `dynamic` then `E` is `dynamic`.

        3.  Else `E` is `Object?`.

    2.  Calculate the static types of each element subpattern using `E` as the
        matched value type. *Note that we calculate a single element type and
        use it for all subpatterns. In:*

        ```dart
        var [a, b] = [1, 2.3];
        ```

        *both `a` and `b` use `num` as their matched value type.*

    3.  The static type of `p` is `List<S>` where:

        1.  If `p` has a type argument, `S` is that type. *If the list pattern
            has an explicit type argument, that wins.*

        2.  Else if the greatest lower bound of the types of the element
            subpatterns is not `?`, then `S` is that type. *Otherwise, if we
            can infer a type bottom-up from the from the subpatterns, use that.*

        3.  Else `S` is `E`. *Otherwise, infer the type from the matched value.*

*   **Map**:

    1.  Calculate the value's entry key type `K` and value type `V`:

        1.  If `M` implements `Map<K, V>` for some `K` and `V` then use those.

        2.  Else if `M` is `dynamic` then `K` and `V` are `dynamic`.

        3.  Else `K` and `V` are `Object?`.

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

*   **Record**:

    1.  Calculate the type of each of `f`'s positional field subpatterns
        using the corresponding positional field type on `M` as the matched
        value type. It is a compile-time error if there are positional
        fields, `M` is not `dynamic`, and `M` is not a record with the same
        number of positional fields.

    2.  Calculate the type of each of `f`'s named field subpatterns using
        the type of the corresponding named field on `M` as the matched
        value type. If `M` is `dynamic`, then use `dynamic` as the matched
        value type. It is a compile-time error if `M` is not `dynamic` and
        is not a record type with a named field with the same name as this
        subpattern's name.

    3.  The static type of `p` is a record type whose fields are the fields of
        `p` with the types of the corresponding subpatterns of `p`.

*   **Extractor**:

    1.  Resolve the extractor name to either a type `X` or an enum value of type
        `X`. It is a compile-time error if the name does not refer to a type or
        enum value.

        **TODO: Can we infer type arguments for `X` from `M`?**

    1.  Calculate the type of each of `f`'s field subpatterns using the type of
        the getter on `X` with the same name as the field as the matched value
        type. It is a compile-time error if `X` does not have a getter whose
        name matches the subpattern's field name.

    2.  The static type of `p` is `Object?`. *Extractors exist to check types at
        runtime, so statically accept all types.*

It is a compile-time error if the type of an expression in a guard clause is not
`bool` or `dynamic`.

## Refutable and irrefutable patterns

Patterns appear inside a number of other constructs in the language. This
proposal extends Dart to allow patterns in:

* Top-level and local variable declarations.
* Static and instance field declarations.
* For loop variable declarations.
* Switch statement cases.
* A new switch expression form's cases.
* A new pattern-if statement.

When a pattern appears in a switch case, any variables bound by the pattern are
only in scope in that case's body. If the pattern fails to match, the case body
is skipped. This ensures that the variables can't be used when the pattern
failed to match and they have no defined value. Likewise, the variables bound by
a pattern-if statement's pattern are only in scope in the then branch. That
branch is skipped if the pattern fails to match.

The other places patterns can appear are various kinds of variable declarations,
like:

```dart
main() {
  var (a, b) = (1, 2);
  print(a + b);
}
```

Variable declarations have no natural control flow attached to them, so what
happens if the pattern fails to match? What happens when `a` is printed in the
example above?

To avoid that, we restrict which patterns can be used in variable declarations.
Only *irrefutable* patterns that never fail to match are allowed in contexts
where match failure can't be handled. For example, this is an error:

```dart
main() {
  var (== 2, == 3) = (1, 2);
}
```

We define an *irrefutable context* as the pattern in a `topLevelDeclaration`,
`localVariableDeclaration`, `forLoopParts`, or `declaration` or its subpatterns.
A *refutable context* is the pattern in a `caseHead` or `ifCondition` or its
subpatterns.

Refutability is not just a property of the pattern itself. It also depends on
the static type of the value being matched. Consider:

```dart
irrefutable((int, int) obj) {
  var (a, b) = obj;
}

refutable(Object obj) {
  var (a, b) = obj;
}
```

In the first function, the `(a, b)` pattern will always successfully destructure
the record because `obj` is known to be a record type of the right shape. But in
the second function, `obj` may fail to match because the value may not be a
record. *This implies that we can't determine whether a pattern in a variable
declaration is incorrectly refutable until after type checking.*

A pattern `p` matching a value of type `v` is refutable if:

*   **Or**, **and**, **grouping**, **null-assert**, or **cast**: Never refutable
    (though may contain refutable subpatterns).

*   **Relational**, **literal**, or **constant**: Always refutable.

*   **Null-check**, **variable**, **list**, **map**, or **record**: The static
    type of `p` is not a supertype of `v`. *If `p` is a variable pattern with no
    type annotation, the type is inferred from `v`, so it is never refutable.*

*   **Extractor**: The static type of `p` is not a supertype of `v` or the
    extractor name refers to an enum value.

It is a compile-time error if a refutable pattern appears in an irrefutable
context, either as the outermost pattern or a subpattern. *This means that the
explicit predicate patterns like constants and literals can never appear in
pattern variable declarations. The patterns that do type tests directly or
implicitly can appear in variable declarations only if the tested type is a
supertype of the value type. In other words, any pattern that needs to
"downcast" to match is refutable.*

### Variables and scope

Patterns often exist to introduce new bindings. Type patterns introduce type
variables and other patterns introduce normal variables. A "wildcard" identifier
named `_` in a pattern never introduces a binding.

The variables a patterns binds depend on what kind of pattern it is:

*   **Or**: Does not introduce variables but may contain subpatterns that do.
    If it a compile-time error if the two subpatterns do not introduce the same
    variables with the same names and types.

*   **And**, **null-check**, **null-assert**, **grouping**, **list**,
    **map**, **record**, or **extractor**: These do not introduce variables
    themselves but may contain type patterns and subpatterns that do.

*   **Relational**, **literal**, or **constant**: These do not introduce any
    variables.

*   **Variable** or **cast**: May contain type argument patterns. Introduces a
    variable whose name is the pattern's identifier. The variable is final if
    the surrounding pattern variable declaration has a `final` modifier. The
    variable is late if it is inside a pattern variable declaration marked
    `late`.

*   **Type pattern**: Type patterns new *type* variables whose name is the type
    pattern's identifier. Type variables are always final.

All variables declared in an instance field pattern variable declaration are
covariant if the pattern variable declaration is marked `covariant`. Variables
declared in a field pattern declaration define getters on the surrounding class
and setters if the field pattern declaration is not `final`.

The scope where a pattern's variables are declared depends on the construct
that contains the pattern:

*   **Top-level pattern variable declaration**: The top-level library scope.
*   **Local pattern variable declaration**: The rest of the block following
    the declaration.
*   **For loop pattern variable declaration**: The body of the loop and the
    condition and increment clauses in a C-style for loop.
*   **Static field pattern variable declaration**: The static scope of the
    enclosing class.
*   **Instance field pattern variable declaration**: The instance scope of the
    enclosing class.
*   **Switch statement case**: The guard clause and the statements of the
    subsequent non-empty case body.
*   **Switch expression case**: The guard clause and the case expression.
*   **Pattern-if statement**: The then statement.

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
subpatterns declare a variable with the same name, unless the name is `_`.*

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

Exhaustiveness checking over arbitrarily deeply nested record and extractor
patterns can be complex, so the proposal for that is in a [separate
document][exhaustiveness].

[exhaustiveness]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/exhaustiveness.md

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

#### Pattern-if statement

1.  Evaluate the `expression` producing `v`.

2.  Match the `pattern` against `v`.

3.  If the match succeeds, evaluate the then `statement`. Otherwise, if there
    is an `else` clause, evaluate the else `statement`.

### Matching (refuting and destructuring)

At runtime, a pattern is matched against a value. This determines whether or not
the match *fails* and the pattern *refutes* the value. If the match succeeds,
the pattern may also *destructure* data from the object or *bind* variables.

Refutable patterns usually occur in a context where match refutation causes
execution to skip over the body of code where any variables bound by the pattern
are in scope. If a pattern match failure occurs in irrefutable context, a
runtime exception is thrown. *This can happen when matching against a value of
type `dynamic`.*

To match a pattern `p` against a value `v`:

*   **Or**:

    1.  Match the left subpattern against `v`. If it matches, the or match
        succeeds.

    2.  Otherwise, match the right subpattern against `v` and succeed if it
        matches.

*   **And**:

    1.  Match the left subpattern against `v`. If the match fails, the and match
        fails.

    2.  Otherwise, match the right subpattern against `v` and succeed if it
        matches.

*   **Relational**:

    1.  Call the corresponding operator from `p` on `v` passing the constant
        value from `p` as the argument.

    2.  If the method returns `true`, the match succeeds, otherwise it fails.

*   **Null-check**:

    1.  If `v` is null then the match fails.

    2.  Otherwise, match the inner pattern against `v`.

*   **Null-assert**:

    1.  If `v` is null then throw a runtime exception. *Note that we throw even
        if this appears in a refutable context. The intent of this pattern is to
        assert that a value *must* not be null.*

    2.  Otherwise, match the inner pattern against `v`.

*   **Literal** or **constant**: The pattern matches if `o == v` evaluates to
    `true` where `o` is the pattern's value.

    **TODO: Should this be `v == o`?**

*   **Variable**:

    1.  If `v` is not a subtype of `p` then the match fails.

    2.  Otherwise, bind the variable's identifier to `v` and the match succeeds.

*   **Cast**:

    1.  If `v` is not a subtype of `p` then throw a runtime exception. *Note
        that we throw even if this appears in a refutable context. The intent
        of this pattern is to assert that a value *must* have some type.*

    2.  Otherwise, bind the variable's identifier to `v` and the match succeeds.

*   **Grouping**: Match the subpattern against `v` and succeed if it matches.

*   **List**:

    1.  If `v` does not implement `List<T>` for some `T`, then the match fails.

    2.  If the length of the list determined by calling `length` is not equal to
        the number of subpatterns, then the match fails.

    3.  Otherwise, for each element subpattern, in source order:

        1.  Extract the element value `e` by calling `[]` on `v` with an
            appropriate integer index.

        2.  Match `e` against the element subpattern.

    4.  The match succeeds if all subpatterns match.

*   **Map**:

    1.  If the value's type does not implement `Map<K,V>` for some `K` and `V`,
        then the match fails.

    2.  Otherwise, for each entry in `p`:

        1.  Evaluate the key `expression` to `k` and call `containsKey()` on the
            value. If this returns `false`, the map does not match.

        3.  Otherwise, evaluate `v[k]` and match the resulting value against
            this entry's value subpattern. If it does not match, the map does
            not match.

    3.  The match succeeds if all entry subpatterns match.

    *Note that, unlike with lists, a matched map may have additional entries
    that are not checked by the pattern.*

*   **Record**:

    1.  If `v` is not a record with the same type as `p`, then the match fails.

    2.  For each field `f` in `p`, in source order:

        1.  Access the corresponding field in record `v` as `r`.

        2.  Match the subpattern of `f` against `r`. If the match fails, the
            record match fails.

    3.  The match succeeds if all field subpatterns match.

*   **Extractor**:

    1.  If `v` is not a subtype of `p` then the match fails.

    2.  If the extractor pattern refers to an enum value and `v` is not that
        value, then the match fails.

    3.  Otherwise, for each field `f` in `p`:

        1.  Call the getter with the same name as `f` on `v` to a result `r`.

        2.  Match the subpattern of `f` against `r`. If the match fails, the
            extractor match fails.

    3.  The match succeeds if all field subpatterns match.

*   **Type pattern**: Always matches. Binds the corresponding type argument of
    the runtime type of `v` to the pattern's type variable.

**TODO: Update to specify that the result of operations can be cached across
cases. See: https://github.com/dart-lang/language/issues/2107**

### Late and static variables in pattern declaration

If a pattern variable declaration is marked `late` or a static variable
declaration has a pattern, then all variables declared by the pattern are late.
Evaluation of the initializer expression is deferred until any variable in the
pattern is accessed. When that occurs, the initializer is evaluated and all
pattern destructuring occurs and all uninitialized variables become initialized.

*If you read *any* of the variables, they *all* get initialized:*

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

If a variable has already been explicitly initialized before the initializer
ran and any destructuring occurred, then it keeps its previously initialized
value:

```dart
main() {
  late var (a, b) = (1, 2);
  a = 3;
  print(b);
  print(a);
}
```

*This prints "2" then "3".*

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

*   **Extractors.** I don't want patterns to feel like we're duct taping a
    functional feature onto an object-oriented language. To integrate it more
    gracefully means destructuring user-defined types too, so adding:

    *   Extractor patterns

*   **Refutable patterns.** The next big step is patterns that don't just
    destructure but *match*. The bare minimum refutable patterns and features
    are:

    *   Patterns in switch statement cases
    *   Switch case guards
    *   Exhaustiveness checking
    *   Literal patterns
    *   Constant patterns
    *   Relational patterns (at least `==`)

    The only critical relational pattern is `==` because once we allow patterns
    in switch cases, we lose the ability to have a bare identifier constant in
    a switch case.

*   **Type patterns.** The other type-based patterns aren't critical but do
    make patterns more convenient and useful:

    *   Null-check patterns
    *   Null-assert patterns
    *   Cast patterns

*   **Control flow.** Switch statements are heavyweight. If we want to make
    refutable patterns more useful, we eventually want:

    *   Switch expressions
    *   Pattern-if statements

*   **Logic patterns.** If we're going to add `==` patterns, we may as well
    support other Boolean infix operators. And if we're going to support the
    comparison operators, then `&` is useful for numeric ranges. It's weird to
    have `&` without `|` so we may as well do that too (and it's useful for
    switch expressions). Once we have infix patterns precedence comes into play,
    so we need parentheses to control it:

    *   Relational patterns (other than `==`)
    *   Or patterns
    *   And patterns
    *   Grouping patterns

*   **Type patterns.** This is a mostly orthogonal feature, though a useful one
    that would let us get rid of the hacky "dart_internal" package.

    *   Type patterns.

## Changelog

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
