# Patterns Feature Specification

Author: Bob Nystrom

Status: In progress

Version 1.2 (see [CHANGELOG](#CHANGELOG) at end)

## Summary

This proposal (along with its smaller sister [records proposal][]) covers a
family of closely-related features that address a number of some of the most
highly-voted user requests. It directly addresses:

[records proposal]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/records-feature-specification.md

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

This proposal [follows Swift][swift pattern] and addresses the ambiguity by
dividing patterns into two general categories *binding patterns* or *binders*
and *matching patterns* or *matchers*. (Binding patterns don't always
necessarily bind a variable, but "binder" is easier to say than "irrefutable
pattern".) Binders appear in irrefutable contexts like variable declarations
where the intent is to destructure and bind variables. Matchers appear in
contexts like switch cases where the intent is first to see if the value matches
the pattern or not and where control flow can occur when the pattern doesn't
match.

[swift pattern]: https://docs.swift.org/swift-book/ReferenceManual/Patterns.html

## Syntax

Going top-down through the grammar, we start with the constructs where patterns
are allowed and then get to the patterns themselves.

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
var a = 1, b = 2;
```

Also, declarations with patterns must have an initializer. This is not a
limitation since the point of using a pattern in a variable declaration is to
immediately destructure the initialized value.

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
  | // Existing productions...
  | patternDeclaration ';' // New.

localVariableDeclaration ::=
  | initializedVariableDeclaration ';' // Existing.
  | patternDeclaration ';' // New.

forLoopParts ::=
  | // Existing productions...
  | ( 'final' | 'var' ) declarationBinder 'in' expression // New.

// Static and instance fields:
declaration ::=
  | // Existing productions...
  | 'static' patternDeclaration // New.
  | 'covariant'? patternDeclaration // New.
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

This is useful because if the guard evaluates to false then execution proceeds
to the next case, instead of exiting the entire switch like it would if you
had nested an `if` statement inside the switch case.

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

*This is now valid code that prints "one":*

```dart
switch (1) {
  case 1:
    print("one");
  case 2:
    print("two");
}
```

Empty cases continue to fallthrough to the next case as before:

*This prints "one or two":*

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
primary ::= thisExpression
  | // Existing productions...
  | switchExpression

switchExpression      ::= 'switch' '(' expression ')' '{'
                          switchExpressionCase* defaultExpressionCase? '}'
switchExpressionCase  ::= caseHead '=>' expression ';'
defaultExpressionCase ::= 'default' '=>' expression ';'
```

**TODO: This does not allow multiple cases to share an expression like empty
cases in a switch statement can share a set of statements. Can we support
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

### If-case statement

Often you want to conditionally match and destructure some data, but you only
want to test a value against a single pattern. You can use a `switch` statement
for that, but it's pretty verbose:

```dart
switch (json) {
  case [int x, int y]:
    return Point(x, y);
}
```

We can make simple uses like this a little cleaner by introducing an if-like
form similar to [if-case in Swift][]:

[if-case in swift]: https://useyourloaf.com/blog/swift-if-case-let/

```dart
if (case [int x, int y] = json) return Point(x, y);
```

It may have an else branch as well:

```dart
if (case [int x, int y] = json) {
  print('Was coordinate array $x,$y');
} else {
  throw FormatException('Invalid JSON.');
}
```

The grammar is:

```
ifCaseStatement ::= 'if' '(' 'case' matcher '=' expression ')'
                         statement ('else' statement)?
```

The `expression` is evaluated and matched against `matcher`. If the pattern
matches, then the then branch is executed with any variables the pattern
defines in scope. Otherwise, the else branch is executed if there is one.

Unlike `switch`, this form doesn't allow a guard clause. Guards are important in
switch cases because, unlike nesting an if statement *inside* the switch case, a
failed guard will continue to try later cases in the switch. That is less
important here since the only other case is the else branch.

**TODO: Consider allowing guard clauses here. That probably necessitates
changing guard clauses to use a keyword other than `if` since `if` nested inside
an `if` condition looks pretty strange.**

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

**TODO: Allow extractBinder patterns here if we support irrefutable user-defined
extractors.**

This means that the outer pattern is always some sort of destructuring pattern
that contains subpatterns. Once nested inside a surrounding binder pattern, you
have access to all of the binders:

```
binder
| declarationBinder
| wildcardBinder
| variableBinder
| castBinder
| nullAssertBinder

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

A list binder extracts elements by position from objects that implement `List`.

```
listBinder ::= ('<' typeOrBinder '>' )? '[' binders ']'
```

**TODO: Allow a `...` element in order to match suffixes or ignore extra
elements. Allow capturing the rest in a variable.**

#### Map binder

A map binder access values by key from objects that implement `Map`.

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

A record pattern destructures fields from a record.

```
recordBinder        ::= '(' recordFieldBinders ')'

recordFieldBinders  ::= recordFieldBinder ( ',' recordFieldBinder )* ','?
recordFieldBinder   ::= ( identifier ':' )? binder
                      | identifier ':'
```

Each field is either a binder which destructures a positional field, or a binder
prefixed with an identifier and `:` which destructures a named field.

When destructuring named fields, it's common to want to bind the resulting value
to a variable with the same name. As a convenience, the binder can be omitted on
a named field. In that case, the field implicitly contains a variable binder
subpattern with the same name. These are equivalent:

```dart
var (first: first, second: second) = (first: 1, second: 2);
var (first:, second:) = (first: 1, second: 2);
```

**TODO: Allow a `...` element in order to ignore some positional fields while
capturing the suffix.**

#### Wildcard binder

A wildcard binder pattern does nothing.

```
wildcardBinder ::= "_"
```

It's useful in places where you need a subpattern in order to destructure later
positional values:

```
var list = [1, 2, 3];
var [_, two, _] = list;
```

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

This is not a type *test* that causes a match failure if the value isn't of the
tested type. This pattern can be used in irrefutable contexts to forcibly assert
the expected type of some destructured value. This isn't useful as the outermost
pattern in a declaration since you can always move the `as` to the initializer
expression:

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

#### Null-assert binder

```
nullAssertBinder ::= binder '!'
```

When the type being matched or destructured is nullable and you want to assert
that the value shouldn't be null, you can use a cast pattern, but that can be
verbose if the underlying type name is long:

```dart
(String, Map<String, List<DateTime>?>) data = ...
var (name, timeStamps as Map<String, List<DateTime>>) = data;
```

To make that easier, similar to the null-assert expression, a null-assert binder
pattern forcibly casts the matched value to its non-nullable type. If the value
is null, a runtime exception is thrown:

```dart
(String, Map<String, List<DateTime>?>) data = ...
var (name, timeStamps!) = data;
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
  | nullCheckMatcher
```

#### Literal matcher

A literal pattern determines if the value is equivalent to the given literal
value.

```
literalMatcher ::=
  | booleanLiteral
  | nullLiteral
  | numericLiteral
  | stringLiteral
```

Note that list and map literals are not in here. Instead there are list and map
*patterns*.

**Breaking change**: Using matcher patterns in switch cases means that a list or
map literal in a switch case is now interpreted as a list or map pattern which
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

**TODO: Consider giving this an optional type annotation to enable matching a
value of a specific type without binding it to a variable.**

This is useful in places where a subpattern is required but you always want it
to succeed. It can function as a "default" pattern for the last case in a
pattern matching statement.

#### List matcher

Matches objects of type `List` with the right length and destructures their
elements.

```
listMatcher ::= ('<' typeOrBinder '>' )? '[' matchers ']'
```

**TODO: Allow a `...` element in order to match suffixes or ignore extra
elements. Allow capturing the rest in a variable.**

#### Map matcher

Matches objects of type `Map` and destructures their entries.

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
recordFieldMatcher  ::= ( identifier ':' )? matcher
                      | identifier ':'
```

Each field is either a positional matcher which destructures a positional field,
or a matcher prefixed with an identifier and `:` which destructures a named
field.

As with record binders, a named field without a matcher is implicitly treated as
containing a variable matcher with the same name as the field. The variable is
always `final`. These cases are equivalent:

```dart
switch (obj) {
  case (first: final first, second: final second): ...
  case (first:, second:): ...
}
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

A variable pattern can also have a type annotation in order to only match values
of the specified type.

#### Declaration matcher

A declaration matcher enables embedding an entire declaration binding pattern
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
useful for writing code in an algebraic datatype style. For example:

```dart
class Rect {
  final double width, height;
  Rect(this.width, this.height);
}

display(Object obj) {
  switch (obj) {
    case Rect(var width, var height):
      print('Rect $width x $height');
    case _:
      print(obj);
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
    case Severity.error(_, prefix):
      print('!! $prefix !! $message'.toUppercase());
    case Severity.warning(_, prefix):
      print('$prefix: $message');
  }
}
```

The grammar is:

```
extractMatcher ::= extractName typeArgumentsOrBinders? "(" recordFieldMatchers ")"
extractName    ::= typeIdentifier | qualifiedName
```

It requires the type to be a named type. If you want to use an extractor with a
function type, you can use a typedef.

It is a compile-time error if `extractName` does not refer to a type or enum
value. It is a compile-time error if a type argument list is present and does
not match the arity of the type of `extractName`.

#### Null-check matcher

Similar to the null-assert binder, a null-check matcher provides a nicer syntax
for working with nullable values. Where a null-assert binder *throws* if the
matched value is null, a null-check matcher simply fails the match. To highlight
the difference, it uses a gentler `?` syntax, like the [similar feature in
Swift][swift null check]:

[swift null check]: https://docs.swift.org/swift-book/ReferenceManual/Patterns.html#ID520

```
nullCheckMatcher ::= matcher '?'
```

A null-check pattern matches if the value is not null, and then matches the
inner pattern against that same value. Because of how type inference flows
through patterns, this also provides a terse way to bind a variable whose type
is the non-nullable base type of the nullable value being matched:

```dart
String? maybeString = ...
if (case var s? = maybeString) {
  // s has type String here.
}
```

## Static semantics

A pattern always appears in the context of some value expression that it is
being matched against. In a switch statement or expression, the value expression
is the value being switched on. In an if-case statement, the value is the result
of the expression to the right of the `=`. In a variable declaration, the value
is the initializer:

```dart
var (a, b) = (1, 2);
```

Here, the `(a, b)` pattern is being matched against the expression `(1, 2)`.
When a pattern contains subpatterns, each subpattern is matched against a value
destructured from the value that the outer pattern is matched against. Here, `a`
is matched against `1` and `b` is matched against `2`.

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

To support this, every pattern has a context type schema. This is a type
*schema* because there may be holes in the type:

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

Here, the pattern is destructuring field `a` on the matched value. Since it
binds that to a variable of type `int`, ideally, that would fact would flow
through inference to the right and infer `C<int>()` for the initializer.
However, there isn't an obvious nominal type we can use for the type schema that
declares `a` without looking at the initializer, which we aren't ready to infer
yet.

We model this by extending the notion of a type schema to also include a
potentially empty set of named getters and their expected type schemas. So,
here, the type schema of the pattern is `Object` augmented with a getter `a` of
type schema `int`. When inferring a type from a given schema, any getters in the
schema become additional constraints placed on the inferred type's corresponding
getters.

**TODO: Type inference doesn't currently look at getter return types to infer
the type arguments of a generic class's constructor, so more work is needed
here if we want this to actually infer type arguments.**

The context type schema for a pattern `p` is:

*   **List binder or matcher**: A type schema `List<E>` where:
    *   If `p` has a type argument, then `E` is the type argument.
    *   Else `E` is the greatest lower bound of the type schemas of all element
        subpatterns.

*   **Map binder or matcher**: A type schema `Map<K, V>` where:
    *   If `p` has type arguments then `K`, and `V` are those type arguments.
    *   Else `K` is the least upper bound of the types of all key expressions
        and `V` is the greatest lower bound of the context type schemas of all
        value subpatterns.

*   **Record binder or matcher**:
    *   If the pattern has any positional fields, then the base type schema is
        `Destructure_n_<F...>` where `_n_` is the number of fields and `F...` is
        the context type schemas of all of the positional fields.
    *   Else the base type schema is `Object?`.
    *   The base type schema is extended with getters for each named field
        subpattern in `p` where each getter's type schema is the type schema of
        the corresponding subpattern. (If there is no subpattern because it's
        an implicit variable pattern like `(field:)`, the type schema is `?`.)

*   **Variable binder**:
    *   If `p` has a type annotation, the context type schema is that type.
    *   Else it is `?`.

*   **Variable matcher**:
    *   If `p` has a type annotation, the context type schema is `Object?`.
        *It is not the annotated type because a variable matching pattern can
        be used to downcast from any other type.*
    *   Else it is `?`.

*   **Cast binder**, **wildcard matcher**, or **extractor matcher**: The context
    type schema is `Object?`.

    **TODO: Should type arguments on an extractor create a type argument
    constraint?**

*   **Null-assert binder** or **null-check matcher**: A type schema `E?` where
    `E` is the type schema of the inner pattern. *For example:*

    ```dart
    var [[int x]!] = [[]]; // Infers List<List<int>?> for the list literal.
    ```

*   **Literal matcher** or **constant matcher**: The context type schema is the
    static type of the pattern's constant value expression.

*   **Declaration matcher**: The context type schema is the same as the context
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

*   **List binder or matcher**:

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

    4.  It is a compile-time error if the list pattern is a binder and any
        element subpattern's type is not a supertype of `S`. *This ensures an
        element binder subpattern does not need to downcast an element from the
        matched value. For example:*

        ```dart
        var <num>[int i] = [1.2]; // Compile-time error.
        ```

*   **Map binder or matcher**:

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

    4.  It is a compile-time error if the map pattern is a binder and any value
        subpattern's type is not a supertype of `W`. *This ensures a value
        binder subpattern does not need to downcast an entry from the matched
        value. For example:*

        ```dart
        var <int, Object>{1: String s} = {1: false}; // Compile-time error.
        ```

*   **Record binder or matcher**:

    1.  Calculate the static types of the field subpatterns:

        1.  It is a compile-time error if there are positional fields, `M` is
            not `dynamic`, and `M` does not implement `Destructure_n_` with as
            many type arguments as there are positional fields.

        1.  Calculate the type of each of `f`'s positional field subpatterns
            using the corresponding type argument in `M`'s implementation of
            `Destructure_n_` as the matched value type.

        1.  Calculate the type of `f`'s named field subpatterns using the
            return type of the getter on `M` with the same name as the field
            as the matched value type. If `M` is `dynamic`, then use `dynamic`
            as the matched value type. It is a compile-time error if `M` is
            not `dynamic` and does not have a getter whose name matches the
            subpattern's field name.

            (If the named field has no subpattern like `(field:)`, treat it as
            if it has a variable subpattern with the same name as the field and
            calculate the static type of that subpattern like a normal variable
            pattern.)

    1.  If `p` has any positional fields, then the static type of `p` is
        `Destructure_n_<args...>` where `_n_` is the number of positional
        fields and `args...` is a type argument list built from the static
        types of the positional field subpatterns, in order.

    2.  Else the static type of `p` is `Object?`. *You can destructure named
        fields on an object of any type by calling its getters. In other words,
        named fields are treated structurally and don't form part of the record
        pattern's overall static type.*

    3.  If `M` is not `dynamic`:
        *   It is a compile-time error if `p` has a field with name `n` and `M`
            does not define a getter named `n`.
        *   It is a compile-time error if `p` has a field named `n` and the type
            of getter `n` in `M` is not a subtype of the subpattern `n`'s type.

*   **Variable binder**:

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

*   **Cast binder**, **wildcard binder or matcher**, or **extractor matcher**:
    The static type of `p` is `Object?`. *Wildcards accept all types. Casts and
    extractors exist to check types at runtime, so statically accept all types.*

*   **Null-assert binder** or **null-check matcher**:

    1.  If `M` is `N?` for some type `N` then calculate the static type `q` of
        the inner pattern using `N` as the matched value type. Otherwise,
        calculate `q` using `M` as the matched value type. *A null-assert or
        null-check pattern removes the nullability of the type it matches
        against.*

        ```dart
        var [x!] = <int?>[]; // x is int.
        ```

    2.  The static type of `p` is `q?`. *The intent of `!` and `?` is only to
        remove nullability and not cast from an arbitrary type, so they accept a
        value of its nullable base type, and not simply `Object?`.*

*   **Literal matcher** or **constant matcher**: The static type of `p` is the
    static type of the pattern's value expression.

*   **Declaration matcher**: The static type of `p` is the static type of the
    inner binder.

It is a compile-time error if `M` is not a subtype of `p`.

It is a compile-time error if the type of an expression in a guard clause is not
`bool` or `dynamic`.

### Variables and scope

Patterns often exist to introduce new bindings. Type patterns introduce type
variables and other patterns introduce normal variables. The variables a
patterns binds depend on what kind of pattern it is:

*   **Type pattern**: Type argument patterns (i.e. `typePattern` in the grammar)
    that appear anywhere in some other pattern introduce new *type* variables
    whose name is the type pattern's identifier. Type variables are always
    final.

*   **List binder or matcher**, **map binder or matcher**, or **record binder or
    matcher**: These do not introduce variables themselves but may contain type
    patterns and subpatterns that do. A named record field with no subpattern
    implicitly defines a variable with the same name as the field. If the
    pattern is a matcher, the variable is `final`.

*   **Literal matcher**, **constant matcher**, or **wildcard binder or
    matcher**: These do not introduce any variables.

*   **Variable binder**: May contain type argument patterns. Introduces a
    variable whose name is the pattern's identifier. The variable is final if
    the surrounding pattern variable declaration or declaration matcher has a
    `final` modifier. The variable is late if it is inside a pattern variable
    declaration marked `late`.

*   **Variable matcher**: May contain type argument patterns. Introduces a
    variable whose name is the pattern's identifier. The variable is final if
    the pattern has a `final` modifier, otherwise it is assignable *(annotated
    with `var` or just a type annotation)*. The variable is never late.

*   **Cast binder**: Introduces a variable whose name is the pattern's
    identifier. The variable is final if the surrounding pattern variable
    declaration or declaration matcher has a `final` modifier. The variable is
    late if it is inside a pattern variable declaration marked `late`.

*   **Null-assert binder** or **null-check matcher**: Introduces all of the
    variables of its subpattern.

*   **Declaration matcher**: The `final` or `var` keyword establishes whether
    the binders nested inside this create final or assignable variables and
    then introduces those variables.

*   **Extractor matcher**: May contain type argument patterns and introduces
    all of the variables of its subpatterns.

All variables (except for type variables) declared in an instance field pattern
variable declaration are covariant if the pattern variable declaration is marked
`covariant`. Variables declared in a field pattern declaration define getters
on the surrounding class and setters if the field pattern declaration is not
`final`.

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
*   **If-case statement**: The then statement.

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

#### If-case statement

1.  Evaluate the `expression` producing `v`.

2.  Match the `matcher` pattern against `v`.

3.  If the match succeeds, evaluate the then `statement`. Otherwise, if there
    is an `else` clause, evaluate the else `statement`.

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

*   **Type pattern**: Always matches. Binds the corresponding type argument of
    the runtime type of `v` to the pattern's type variable.

*   **List binder or matcher**:

    1.  If `v` does not implement `List<T>` for some `T`, then the match fails.
        *This may happen at runtime if `v` has static type `dynamic`.*

    2.  If the length of the list determined by calling `length` is not equal to
        the number of subpatterns, then the match fails.

    3.  Otherwise, extracts a series of elements from `v` using `[]` and matches
        them against the corresponding subpatterns. The match succeeds if all
        subpatterns match.

*   **Map binder or matcher**:

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

*   **Record matcher or binder**:

    1.  If the pattern has positional fields:

        1.  If `v` does not implement the appropriate `Destructure_n_<...>`
            interface instantiated with type arguments based on the positional
            fields' static types, then the match fails.

    2.  For each positional and named field `f` in `p`:

        1.  Call the corresponding getter on `v` to get result `r`. If `f`
            is a positional field, then the getter is named `field_n_` where
            `_n_` is the zero-based index of the positional field, ignoring
            other named fields. If `f` is named, then the getter has the
            same name as `f`.

            *If `v` has type `dynamic`, this getter call may throw a
            NoSuchMethodError, which we allow to propagate instead of
            treating that as a match failure.*

        2.  Match the subpattern of `f` against `r`. If the match fails,
            the record match fails. (If `f` has no subpattern because it's an
            implicit field pattern like `(field:)`, treat it like a the
            subpattern is a variable pattern with the same name.)

    3.  If all field subpatterns match, the record pattern matches.

*   **Variable binder or matcher**:

    1.  If `v` is not a subtype of `p` then the match fails. *This is a
        deliberate failure when using a typed variable pattern in a switch in
        order to test a value's type. In a binder, this can only occur on a
        failed downcast from `dynamic` and becomes a runtime exception.*

    2.  Otherwise, bind the variable's identifier to `v` and the match succeeds.

*   **Cast binder**:

    1.  If `v` is not a subtype of `p` then throw a runtime exception. *Note
        that we throw even if this appears in a refutable context. The intent
        of this pattern is to assert that a value *must* have some type.*

    2.  Otherwise, bind the variable's identifier to `v`. The match always
        succeeds (if it didn't throw).

*   **Null-assert binder**:

    1.  If `v` is null then throw a runtime exception. *Note that we throw even
        if this appears in a refutable context. The intent of this pattern is to
        assert that a value *must* not be null.*

    2.  Otherwise, match the inner pattern against `v`.

*   **Literal matcher** or **constant matcher**: The pattern matches if `o == v`
    evaluates to `true` where `o` is the pattern's value.

    **TODO: Should this be `v == o`?**

*   **Wildcard binder or matcher**: Always succeeds.

*   **Declaration matcher**: Match `v` against the binder subpattern. Always
    succeeds.

*   **Extractor matcher**:

    1.  If `v` is not a subtype of the extractor pattern's type, then the
        match fails.

    2.  If the extractor pattern refers to an enum value and `v` is not that
        value, then the match fails.

    3.  Otherwise, match `v` against the subpatterns of `p` as if it were a
        record pattern.

*   **Null-check matcher**:

    1.  If `v` is null then the match fails.

    2.  Otherwise, match the inner pattern against `v`.

**TODO: Update to specify that the result of operations can be cached across
cases. See: https://github.com/dart-lang/language/issues/2107**

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

## Changelog

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
