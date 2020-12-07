# Patterns

**NOTE: This document is still *very* rough. Note the many many TODOs. Putting
it out here now to start getting language team feedback on direction.**

**TODO: Show examples of common interesting use cases.**

If you want to get straight to the proposal, feel free to skip the next big
section. If you want to understand *why* the proposal makes the choices it does,
read on.

## Design Challenges

One cannot simply amputate the pattern matching syntax and semantics from a
functional language like SML and graft it directly onto an object-oriented
language like Dart. SML's type system is based on algebraic datatypes and has no
notion of subtyping.

The impedance mismatch between existing functional-style pattern syntax and
Dart causes (at least) two challenges:

### Challenge 1: Bare identifiers

Consider this hypothetical Dart program:

```dart
const a = 123;

main() {
  match ([345]) {
    case [a] => print(a);
    case _ => print("no match");
  }
}
```

Here's a match statement which contains a couple of cases. Each case contains a
pattern that the value is matched against. Look at `a` inside the `[a]` pattern.
It could mean either:

1.  **Look up the value of the constant `a`.** In that case, the whole pattern
    means, "Successfully match the value if it is a list containing the integer
    123."

2.  **Bind a new variable named `a`.** In that case, the whole pattern means,
    "Match the value if it is a list. If so, destructure it by pulling out the
    first element and binding it to a new variable `a`."

In the first interpretation, the program prints "no match". In the second, it
prints "123". Obviously, we have to pick. The hard part is that both behaviors
are eminently useful.

If we want a pattern matching construct like `match` here to completely replace
the venerable and much-maligned switch statement, then it needs to do all the
things switch can do. One of those is comparing values to other values stored
in named constants. So we want to support the first behavior.

But another key goal of pattern matching is destructuring. Users want a more
concise notation to pull data out of lists and other objects. So we want the
second too.

### Challenge 2: Subtype patterns

When subtyping gets involved, we need to think about cases where the static type
of a pattern&mdash;the type of all values it could possibly match&mdash;is a
subtype of the value's type. In vague terms, when a pattern needs to "downcast"
the value before it can do any further work and what it means if that downcast
fails.

For example, say you have a value of static type `num`, and the pattern can only
accept values of type `int`. There are three expectations a user might have
about how that behaves:

1.  **Compile-time error.** If we use patterns for variable declarations, it's
    likely that we want that to be an error:

    ```dart
    List<num> nums = [1.2];
    var [int i] = nums;
    ```

    Here, the `[int i]` is a list pattern that destructures an element,
    containing an `int i` pattern that requires the value to be an integer and
    binds it to a new variable `i`.

    If the list element is not an int then this must fail or the code is
    unsound. We are removing implicit downcasts from Dart specifically because
    *many* users over the years have told us they want to catch failures like
    this at compile time. So option one is that it is a compile-time error to
    have a pattern that requires a type that isn't a supertype of the value's
    type. We don't allow "implicit downcasts" in patterns.

2.  **Don't match the value.** Let's say you are using pattern matching to
    process the JSON response from some kind of RPC which returns a list.
    The different kinds of responses return lists containing different kinds of
    elements. You might use pattern matching like:

    ```dart
    handleJson(List<Object> json) {
      match (json) {
        case [int x, int y] => print("got point $x, $y");
        case [String s] => print("got name $s");
      }
    }
    ```

    Here the patterns like `int x` work like type *tests*. If the value *is*
    the right type, then it is downcast and the match succeeds. Otherwise, the
    match simply fails and we proceed to the next case.

3.  **Throw a CastError.** In other words, treat the pattern as *asserting* that
    the value must have type. It's a bug in the user's program if the value
    doesn't actually have that type. Like an `as` expression, but in the context
    of a pattern.

    For example, say you have a list and you know the first element should be a
    string and the second should be an int. Today, you would write:

    ```dart
    List<Object> data = ...;
    String name = data[0] as String;
    int age = data[1] as int;
    ```

    It would be great to use destructuring here, but that means you need a way
    to cast each element as you destructure it. Something like:

    ```dart
    List<Object> data = ...;
    var [String name, int age] = data;
    ```

    Here you are deliberately choosing to cast the values because you know
    something about their types that the type system doesn't.

As you can see each behavior is useful for different problems.

### Resolving ambiguity

Both of these challenges share a core problem that we have multiple useful
behaviors all vying for the same piece of syntax. With the first challenge, it's
wanting to treat a bare identifier as either a variable binding or a reference
to a constant. With the second, it's whether a type-based pattern treats the
type as an annotation, explicit cast, or type test.

These challenges come up often, especially when evolving a language with a rich
syntax like Dart. There's only so much ASCII to go around. For example, consider
the humble: `{}`. In Dart 1.0, this could already mean two different things: an
empty map literal for a `Map<dynamic, dynamic>`, or an empty block. When we
added type inference in Dart 2.0, that same pair of characters could mean an
empty map of any of a variety of different types. Then in Dart 2.2, we added set
literals, so now it could potentially be an empty set.

There are several ways to solve these kinds of problems. The first simply avoids
the problem entirely and the others rely on using some surrounding contextual
information to determine which behavior the user gets. For `{}`, we use almost
all of them:

1.  **Come up with different syntax.** The easiest and safest solution is to
    define completely distinct syntax for each behavior. If you write,
    `<int>{}`, it can *only* be a *set* and only a set of *ints*. Likewise,
    `<int, String>{}` is always a `Map<int, String>`.

2.  **Use the grammatical context to decide.** Look at the syntax surrounding
    the construct and pick based on that. In otherwise, split the grammar such
    that inside some elements only one behavior is allowed. For example:

    ```dart
    main() {
      {};
    }
    ```

    Here, we know the `{}` must be a block (followed by a useless `;` empty
    statement) because the language does not allow map/set literals to appear at
    the beginning of an expression statement.

3.  **Use name resolution to decide.** Bare identifiers can be resolved in Dart
    just by tracking the lexical scopes. You don't need to know the static type
    of everything, but you do need to know all imported names and class members.
    Consider:

    ```dart
    import 'foo.dart';

    class Bar extends Foo {
      test() {
        // Hidden code here...

        method();
      }
    }
    ```

    That `method()` call could be any of:

    1.  A call to a top-level function imported from Foo.
    2.  A call to a local function if there is one hiding in that comment.
    3.  A call to `this.method()` if Bar inherits that from Foo.

    In order to decide, the language looks through the surrounding lexical
    scopes for a function `method()`. If it finds one, it says the code is a
    call to that. Otherwise, it treats it as `this.method()`.

4.  **Use the surrounding static type context to decide.** Part of type
    inference is "downwards" type inference where we use known static type of
    some enclosing code to decide what a piece of syntax means. For example:

    ```dart
    Set<int> ints = {};
    Map<String, int> counts = {};
    ```

    We know the first `{}` is a set and the second a map because of the static
    type of the variable declaration that those are initializers for.

How do we choose an approach for these pattern matching problems? The options
are roughly in order. When possible, the safest solution is to come up with
distinct syntax. That can be difficult if users already have a strong
expectation for a certain syntax based on existing language features or other
languages. Novel syntax carries a high unfamiliarity cost. For features like
pattern matching that are primarily syntax sugar, a distinct but ugly syntax can
nullify the value of the feature.

Barring that, the less context you use the better. There is a sliding scale for
how much surrounding code the user has to have loaded in their head before they
can understand the syntax. Grammatical context is lowest&mdash;they literally
just need to look at the enclosing text. Lexical scoping is next. They have
to look at surrounding block scopes and know what's imported. Static types are
the last&mdash;they have to essentially run the type inference engine in their
head.

In this proposal, we take approach 2: we use the grammatical context. I think
this makes the right trade-off between familiar syntax and relatively local
reasoning, at the expense of a slightly more complex somewhat redundant set of
patterns. This approach was [directly inspired by Swift][swift], so there's
evidence this is a good balance.

[swift]: https://docs.swift.org/swift-book/ReferenceManual/Patterns.html

## Two kinds of patterns

A pattern generally does one of three things:

1.  Perform some kind of test on an object to decide whether to execute some
    piece of code or not. In other words, if the object **matches** the pattern,
    then evaluate the "body" of some surrounding construct. If the object does
    not match the value, the we say the pattern was **refuted**.

2.  **Bind** a new variable to the value.

3.  Extract data from some object by **destructuring** it and applying
    subpatterns to the extracted data.

Functional languages lump those three together into a single grammar, "pattern",
and allow them to be freely mixed. Instead, for Dart, we have two separate
categories: **matchers** and **binders**. Matchers are all of the refutable
patterns that can fail to match a value. Binders are the other patterns that can
never fail and exist to bind new variables.

Destructuring patterns like list and map patterns that contain subpatterns
exist in both categories. There is a list binder and a list matcher. The only
difference is that the former contains binders as subpatterns and the latter
matchers. (This is where the redundancy comes in.)

Places in the language where patterns can be embedded use the category that
makes sense for that context. For example, if we allow patterns in variable
declarations, like:

```dart
var [i, j] = [1, 2];
```

Then the pattern appearing after `var` is a binder, because that's the intent of
a variable declaration. (In this example, it's a list binder containing two
variable binders.) On the other hand, in some kind of match statement, the
pattern is a matcher because the main purpose of the statement is control flow:

```dart
match (value) {
  case [1, 2] => print("matched");
}
```

(Here we have a list *matcher* containing two literal matchers.)

### Disambiguating

The two categories are useful because some patterns do not appear in both
categories. There is a pattern to determine if a value is equal to a given named
constant, but that is only a matcher. Likewise, the pattern to bind a new
variable is only a binder. In this way, a bare identifier is unambiguous: in a
context where a matcher pattern is expected, it is a constant matcher. In a
context where a binder is expected, it is a variable binder.

Likewise, as we'll see when we go through the specific pattern types below, the
behavior around downcasts and subtyping varies between the two categories. In
matchers, where match failure is a meaningful concept, we can have patterns that
treat downcasts as runtime type tests. In binders where the user expects an
operation to succeed, we can flag a potential cast failure as a compile error.

### Mixing categories

The real power of pattern matching comes when you combine matching and binding.
The classic example is matching over sum types in a functional language. Users
[would like to write code in the same style in Dart][sum type]. The way to model
a sum type in an object-oriented language is by using a class hierarchy:

[sum type]: https://github.com/dart-lang/language/issues/83

```dart
abstract class Geometry {}

class Point extends Geometry {
  final num x, y;
  Point(this.x, this.y);
}

class Circle extends Geometry {
  final num x, y, radius;
  Circle(this.x, this.y, this.radius);
}
```

Say you want to write a function that prints out a given Geometry object. The
function needs to see which specific Geometry type it has and extract the fields
as appropriate. In Dart today, you'd write something like:

```dart
printGeometry(Geometry geometry) {
  if (geometry is Point) {
    print("Point ${geometry.y}, ${geometry.y}");
  } else if (geometry is Circle) {
    print("Circle ${geometry.x}, ${geometry.y}, ${geometry.radius}")
  }
}
```

Here we rely on type promotion on `geometry` to let us access the fields after
checking the variable's type. With pattern matching we can combine that type
test and field access like so:

```dart
printGeometry(Geometry geometry) {
  match (geometry) {
    case Point(var x, var y) => print("Point $x, $y");
    case Circle(var x, var y, var radius) => print("Circle $x, $y, $radius");
  }
}
```

Here, the outer `Point(...)` pattern is a matcher that does a type test to see
if `geometry` is a Point. If it is not, it simply proceeds to the next case. If
`geometry` is a point, the `Point(...)` patterns destructures the value and
evaluates its two subpatterns. The `var x` and `var y` patterns are *bind
matchers* that hop over to the bind category to bind variables. A bind matcher
is a special kind of matcher that contains a binder as a subpattern. This lets
you compose binders and matchers together, much like expression statements let
you place an expression where a statement is needed.

Note that you can't cross categories in the other direction. In a binder, there
is no way to get to a matcher. That makes sense because in a context where
failure isn't meaningful and the user does not expect control flow, there should
be no way for a match to fail.

## Matchers

Matchers determine if the value in question *matches* or meets some predicate.
This answer is used to select appropriate control flow in the surrounding
construct. For example, in some hypothetical match statement, if the pattern
does not match, then the case containing the pattern is skipped.

```
matcher ::=
  | wildcardMatcher
  | literalMatcher
  | constantMatcher
  | listMatcher
  | mapMatcher
  | typedMatcher
  | bindMatcher
  | typeTestMatcher
  | tupleMatcher
  | extractMatcher

matchers ::= matcher ( "," matcher )* ","?
```

**TODO: Do set matchers make sense?**

### Wildcard matcher

```
wildcardMatcher ::= "_"
```

A wildcard pattern always matches. This is useful in places where a subpattern
is required but you always want to succeed. It can function as a "default"
pattern for the last case in a pattern matching statement.

### Literal matcher

```
literalMatcher ::=
  | booleanLiteral
  | numericLiteral
  | stringLiteral
```

A literal pattern determines if the value is equivalent to the given literal
value. The pattern matches if the two values are equal, determined by passing
the value being matched to the `==` method on the pattern's literal value.

### Constant matcher

```
constantMatcher ::= identifier ( "." identifier ( "." identifier )? )?
```

Determines if the value is equivalent to the value of the given constant
expression. The expression is syntactically restricted to be either:

*   **A bare identifier.** In this case, the identifier must resolve to a
    constant declaration in scope.

*   **A prefixed or qualified identifier.** In other words, `a.b`. It must
    resolve to either a top level constant imported from a library with a
    prefix, a static constant, or an enum value.

*   **A prefixed qualified identifier.** Like `a.B.c`. It must resolve to a
    value on an enum type that was imported with a prefix, or a static
    declaration in a class, mixin, or extension imported with a prefix.

The const expression is evaluated and the matched value is passed to the
result's `==` operator to determine if it matches.

**TODO: Do we want to allow other kinds of constant expressions like `1 + 2`?
Switch statements allow arbitrary const expressions. We probably don't want to
allow const collection literals since those clash with the corresponding
collection patterns.**

### List matcher

```
listMatcher ::= "[" matchers "]"
```

Matches and destructures lists. If the value's type does not implement `List<T>`
for some T, then the match fails. If the length of the list determined by
calling `length` is not equal to the number of subpatterns, the match fails.

Otherwise, extracts a series of elements from the list using the index operator
and tests them against the corresponding subpatterns. The list matcher succeeds
if all of the subpatterns match.

**TODO: Allow a `...` element to skip over elements and match suffixes. Can you
capture the rest in a variable?**

**TODO: Should we loosen this to match against any Iterables by using
`elementAt()`?**

**TODO: Can the pattern have a type argument? If so, can that have a type
pattern?**

**TODO: Calling `length` and `[]` may have user-visible side effects, but it
would be nice if compilers could cache the result of a previous call when
processing a series of list patterns. Decide how to specify that.**

### Map matcher

```
mapMatcher ::= "{" mapMatcherEntries "}"

mapMatcherEntries ::= mapMatcherEntry ( "," mapMatcherEntry )* ","?
mapMatcherEntry ::= expression ":" matcher
```

Matches and destructures maps. If the value's type does not implement `Map<K,V>`
for some K and V, then the match fails. Otherwise, tests the entry patterns:

1.  For each `mapMatcherEntry`:

    1.  Evaluate `expression` and pass to `containsKey()` on the value.

    1.  If this returns `false`, the map does not match.

    1.  Otherwise, pass the expression's value to the value's index operator.
        Match the entry's matcher against the resulting value. If it does not
        match, the map does not match.

1.  If all entries match, the map matches.

Note that, unlike with lists, a matched map may have additional entries that
are not checked by the matcher.

If it is a compile-time error if any of the entry key expressions are not
constant expressions.

**TODO: Can the pattern have type arguments? If so, can they have type
patterns?**

### Typed matcher

```
typedMatcher ::= type identifier
```

Performs both a type test and a variable binding. Matches if the runtime type of
the value is a subtype of `type`. If so, binds a new variable named `identifier`
to the value with static type `type`. Unlike the corresponding binder pattern,
this *can* "downcast" in that it checks the type first.

**TODO: Allow `final`?**

**TODO: Allow type pattern.**

### Bind matcher

```
bindMatcher ::= ( "var" | "final" ) binder
```

A bind matcher lets a matching pattern also perform variable binding. By using
bind matchers as subpatterns of a larger matched pattern, a single composite
pattern can validate some condition and then bind one or more variables only
when that condition holds.

The `var` or `final` keyword indicates that a bind matcher is desired, followed
by the binder pattern.

A bind matcher always succeeds. Upon matching, it evaluates its binder using the
matched value. If the bind matcher uses `var`, any variables created by the
inner binders are assignable, otherwise they are final.

### Type test matcher

```
typeTestMatcher ::= "is" type
```

A type test matcher can be used to match against the value's runtime type. The
matcher succeeds if the value's runtime type is a subtype of `type`.

**TODO: Define how this interacts with promotion.**

**TODO: It's not clear if we want both this and typed matcher. We could allow a
name after this to make the type check explicit as in `is int i`. Then a
typedMatcher would disallow downcasting like the corresponding binder does. Or
we could eliminate this and require users to do `int _` if they just want to
test the type of the value and not bind.**

## Binders

Binders are the subset of patterns whose aim is to define new variables in some
scope. A binder can never be refuted.

```
binder ::=
  | wildcardBinder
  | variableBinder
  | typedBinder
  | castBinder
  | listBinder
  | mapBinder
  | tupleBinder
  | extractBinder

binders ::= binder ( "," binder )* ","?
```

### Wildcard binder

```
wildcardBinder ::= "_"
```

Does nothing. Placeholder in contexts where a subpattern is expected but you
don't want to bind anything.

### Variable binder

```
variableBinder ::= identifier
```

Binds a new variable named `identifier` to the value. The surrounding context
determines whether the variable is final or not, and its inferred type.

### Typed binder

```
typedBinder ::= type identifier
```

Binds a new variable named `identifier` to the value with static type `type`.
It is a compile-time error if `type` is not a supertype of the value's type.
(In other words, this can upcast but not downcast the value.)

### Cast binder

```
castBinder ::= identifier "as" type
```

Attempts to cast the value to `type`. If the value is not a subtype of `type`,
throws a CastError (which is *not* considered a match failure if used in a
context where matchers are allowed). Otherwise, creates a new variable with name
`identifier` of type `type` and binds it to the value.

**TODO: Allow this as a matcher too?**

### List binder

```
listBinder ::= "[" binders "]"
```

Destructures lists. It is a compile-time error if the value's type does not
implement `List<T>` for some T. Throws a runtime error if the length of the list
determined by calling `length` is not equal to the number of subpatterns.

Otherwise, extracts a series of elements from the list using the index operator
and applies them to the corresponding subpatterns.

**TODO: Allow a `...` element to skip elements and match suffixes or ignore extra
elements.**

**TODO: Can the rest element be captured in a variable? What does it desugar
to?**

**TODO: Should we loosen this to match against any Iterables by using
`elementAt()`?**

**TODO: Can the pattern have a type argument? If so, can that have a type
pattern?**

### Map binder

```
mapBinder ::= "{" mapBinderEntries "}"

mapBinderEntries ::= mapBinderEntry ( "," mapBinderEntry )* ","?
mapBinderEntry ::= expression ":" binder
```

Destructures maps. It is a compile-timer error if the value's type does not
implement `Map<K,V>` for some K and V. Otherwise:

1.  For each `mapMatcherEntry`:

    1.  Evaluate `expression` and pass to `containsKey()` on the value.

    1.  If this returns `false`, throw a runtime error.

    1.  Otherwise, pass the expression's value to the value's index operator.
        Apply the entry's binder to the resulting value.

Note that, unlike with lists, a matched map may have additional entries that
are not bound by the binder.

If it is a compile-time error if any of the entry key expressions are not
constant expressions.

**TODO: Can the pattern have type arguments? If so, can they have type
patterns?**

## Tuples and extractors

My favorite language features add powerful, expressive syntax, but with hooks
that let users control what that syntax does. A simple example is for-in loops:

```dart
for (var n in foo()) print(n);
```

This loop could print the elements in a list or a set. It could iterate over
a numeric range or generate an infinite series of primes. Because the for-in
loop is implemented in terms of calling methods on Iterable, a user can
implement the Iterable interface to provide whatever sequence-like behavior
they want.

Tuples and extractors are like that for pattern matching. They let users write
patterns that pull arbitrary data out of objects by invoking getters declared by
the object's class. This is similar to [`unapply()`][unapply] in Scala and the
[`componentN()`][component] methods in Kotlin.

[unapply]: https://docs.scala-lang.org/tour/extractor-objects.html
[component]: https://kotlinlang.org/docs/reference/multi-declarations.html

### Tuple patterns

There are two kinds of these patterns. **Tuple patterns** appear as they do in
other languages, a parenthesized list of subpatterns, like:

```dart
var (a, b, c) = object;
```

Much like argument lists in Dart, named fields are also allowed:

```dart
var (x: a, y: b) = object;
```

Each field subpattern invokes a corresponding getter on the matched object and
then applies itself to the result. For named fields, the field name is the name
of the getter that is invoked (so `x` and `y` in the previous example).
Positional fields are implicitly named `field<n>` where `<n>` is the zero-based
index of the positional field. In other words, `(a, b: c, d)` matches `field0`
against `a`, field `b` against `c` and `field1` against `d`.

We expect to add tuples to the language. Tuples will expose a set of getters
that match these positional names, so the tuple `("a", "b")` exposes `field0`
whose value is `"a"` and `field1` whose value is `"b"`. Tuples may also support
named fields like `(x: 1, y: 2)` which can be matched by these patterns.

In addition, instances of classes can have their getters invoked by name. This
provides a nice notation for extracting multiple values out of instances of any
class without any explicit support needed in the class itself. If the instance's
class defines getters like `field0`, then it can also be matched using
positional fields. In other words, a class can "implement the tuple matching
protocol" by providing getters with those names. For example, if we add `field0`
and `field1` to MapEntry, returning the key and value, respectively, then users
can write:

```dart
for (var (key, value) in someMap.entries) {
  print("$key: $value");
}
```

It is also possible for a field subpattern to invoke an *extension* getter on
the class. This lets users retroactively add destructuring to classes they don't
control.

Note that a one-element field matcher is *not* the same as the underlying
subpattern. Parentheses are not just for grouping in that case. The pattern `a`
matches any object and binds it to `a`. The pattern `(a)` invokes `field0` on
the object and binds the result of *that* to `a`.

**TODO: If this is a concern, we could avoid this weird corner by making it a
syntax error for a field matcher to only have a single positional field. Should
we?**

### Extractor patterns

An **extractor pattern** is similar but has an identifier (possibly qualified)
before the parenthesized subpattern list. This name is used to lookup a
extractor function that is applied to the matched value. The result of that
function is then the object whose getters are accessed.

For example:

```dart
class Color {
  int r, g, b;

  static (int, int, int) hsv(Color color) {
    var h = calculateHue(color);
    var s = calculateSaturation(color);
    var v = calculateValue(color);
    return (h, s, v);
  }
}

printHsv(Color c) {
  var hsv(h, s, v) = c; // <--
  print("$h $s $v");
}
```

On the marked line, the `hsv(h, s, v)` pattern first passes the matched value to
`Color.hsv()`. That returns a tuple, which the pattern then destructures using
its `(h, s, v)` subpatterns. You can think of extractors as the mirror to
functions&mdash;where a function gives users a way to introduce a new named
expression that performs arbitrary computation, extractors introduce a new named
pattern.

If the declared return type of the extractor is non-nullable, then the extractor
can be used in both binder and matcher patterns. If it is nullable, then
returning null means that the passed in value fails to match the pattern. These
extractors can only be used in matchers.

**TODO: What about potentially nullable return types like `T extract<T>()`?**

Refutable extractors like this can be useful for implementing sum type style
class hierarchies. In the previous example:

```dart
printGeometry(Geometry geometry) {
  match (geometry) {
    case Point(var x, var y) => print("Point $y, $y");
    case Circle(var x, var y, var radius) => print("Circle $x, $y, $radius");
  }
}
```

Here, `Point()` is a extractor defined something like:

```dart
class Point extends Shape {
  static Point? extract(Shape shape) => shape is Point ? shape : null;
}
```

**TODO: Is it necessary to define explicit extractors for downcasts? Should we
consider allowing `is` before a extractor to do a cast check?**

### Resolving extractor functions

We resolve the identifier in a extractor pattern to a function like so:

1.  If the name is unqualified and there is a static method defined on the
    value's static type with that name, the extractor is that method. *This lets
    a class define its own "named extractors" that take precedence over the
    lexical scope as in the `hsv()` example. Making these instance or extension
    members on the class lets them have short names without risk of top level
    collision.*

3.  Otherwise, if the name resolves to a top level function, that function is
    the extractor. *This lets you define free-floating extractor functions.*

4.  Otherwise, if the name resolves to a class and the class defines a static
    method named `extract()`, the extractor is that method. *This lets you use
    the name of an unrelated class as if the class itself were an extractor.
    It's the extractor analogue of an unnamed constructor.*

    **TODO: Is `extract()` the name we want?**

5.  Otherwise, no extractor could be found and a compile-time error is reported.

**TODO: Is this too complex?**

It is a compile-time error if the resolved extractor function takes anything but
a single mandatory positional argument. It is a compile-time error if the
function's return type is `void`.

### Single-value extractors

If an extractor converts the matched value to something containing multiple
fields, it's natural to return a tuple which conveniently implements the proper
`field<n>` fields. But if the extractor produces only a single value, what does
it return? There are no one-element tuples. We could provide some wrapper class
like:

```dart
class Box<T> {
  final T field0;
}
```

That would enable extractor patterns like `foo(x)` to work by having `foo()`
return a `Box<T>` wrapping the value it wants to expose. But that's kind of
gross. A cleaner solution might be to add this to the core library:

```dart
extension Monuple<T> on T {
  T get field0 => this;
}
```

Then every object is implicitly also a single-element tuple.

### Tuple matcher

```
tupleMatcher ::= "(" matcherFields ")"

matcherFields ::= matcherField ( "," matcherField )* ","?
matcherField ::= ( identifier ":" )? matcher
```

Destructures fields from an object. It is a compile-time error if the static
type of the value being matched does not declare members whose names match all
of the matched fields.

At runtime, invokes the corresponding getters on the object and matches the
results against each corresponding subpattern. The tuple pattern matches if all
subpatterns match.

### Extract matcher

```
extractMatcher  ::= qualified "(" matcherFields ")"
qualified       ::= identifier ( "." identifier )?
```

Applies an extractor function resolved from `qualified`. It is a compile-time
error if the matched value's static type is not a subtype of the parameter type
of the extractor. It is a compile-time error if the return type of the extractor
does not define fields that match all of the extractor patterns' subpatterns.

Invokes the extractor, passing in the matched value. If the extractor returns
`null`, then the pattern does not match. Otherwise, destructures the result in
the same way a tuple matcher works and succeeds if all of those subpatterns do.

### Tuple binder

```
tupleBinder ::= "(" binderFields ")"

binderFields ::= binderField ( "," binderField )* ","?
binderField ::= ( identifier ":" )? binder
```

Destructures fields from an object. Identical to `tupleMatcher` except that the
subpatterns are `binder`s. The semantics are otherwise the same.

### Extract binder

```
extractBinder ::= qualified "(" binders ")"
```

Similar to the extract matcher except that it cannot be refuted. It is a
compile-time error if the return type of the extractor function is nullable.

## Type patterns

In some matcher and binder patterns, a type name can be written which may
include generic type arguments. We allow special **type patterns** inside these
to capture the reified type arguments from the matched object's runtime type.

**TODO: Incorporate https://github.com/dart-lang/language/issues/170. Update
other patterns here to allow type argument lists that may contain type
patterns.**

**TODO: Do we want a null-check pattern to remove the nullability of the matched
value?**
