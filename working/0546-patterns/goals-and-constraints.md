# Goals and Constraints

We're investigating adding pattern matching to Dart. If you aren't familiar
with the concept, [this Stackoverflow page][so] might help. [This tracking
issue][546] also helps frame things.

[546]: https://github.com/dart-lang/language/issues/546

Before I get into details of the design, I wanted to walk through our specific
goals and constraints. It's not enough to just yank pattern matching out of,
say, Haskell, and cram it into Dart. We need to define what a *good* pattern
matching feature looks like *in the context of Dart.*

[so]: https://stackoverflow.com/questions/2502354/what-is-pattern-matching-in-functional-languages

*Note: In this doc, I'll use a made-up match statement and other hypothetical
forms that could contain patterns as a way to show examples. The important part
of the examples is the patterns themselves contained in those forms. This doc
does not concretely propose any of those specific features.*

## General Goals

Before I get to specific pattern matching features, here's some higher level
goals that I have in mind when I think about designing this feature. Most are
not hard requirements, but soft constraints we will make trade-offs between and
aim to maximize.

### Be unambiguous and syntactically simple

Of course, the grammar *must* be unambiguous. If the user writes a valid Dart
program, it needs to mean only one thing. Further, we'd like the rules that
determine what a given pattern means to be as simple as possible.

Ideally, they would be completely context free. If not, they should at least
avoid relying on static type analysis in order to be meaningfully parsed. It may
be acceptable to rely on variable resolution to determine what a piece of syntax
means, much in the way that we rely on resolution to know if `foo` in `foo.bar`
is an import prefix or a variable.

### Offer good static checking

Dart is generally moving in a direction that if we can detect a user error at
compile time, we should. The earlier a developer can find and fix a mistake, the
better. That implies good static checking, in a few different ways:

If we can determine at compile time that a given pattern will *always* fail to
match a value, we should probably report that as an error. For example:

```dart
String s = ...
match (s) {
  case 1 => print("???");
}
```

The compiler knows `s` is a String and the `1` pattern can never match any
possible strings, so this code isn't useful.

Patterns are also often used in places like variable declarations where users
don't expect a runtime failure to occur. In that case, if a pattern *might* fail
to match, it should probably be compile-time error:

```dart
num n = ...
let int i = n;
```

Here, `let` is some made-up syntax that takes a pattern (`int i`) and matches it
against the initializer. In this case, a num might not match a pattern that
requires the value to be an int (it could be a double). Instead of failing at
runtime with an exception, this should probably be a static error.

### Check for exhaustiveness

One aspect of static checking is *exhaustiveness* checking. At compile time,
many languages can tell you if the set of patterns you are matching a value
against fully covers all possible values that might occur. If not, it tells you
that your patterns are not exhaustive -- some errant value may sneak through and
match none of the cases.

This is similar to how a switch statement on an enum type today gives you a
warning if you don't cover all of the cases. Extending this to arbitrary
patterns is a useful, powerful feature, because it means that when users add new
cases to some enum or enum-like type, the compiler will tell them all of the
places in code that may need to be extended to handle that case.

### Follow familiar pattern syntax and semantics

Pattern matching exists in some form or another in a number of languages today:
Haskell, SML, Scala, Kotlin, Swift, etc. Many users come to Dart from other
languages. When Dart builds on what they already know, it reduces the amount
they have to learn to be productive.

So, when it makes sense, we should look and work the same as similar features in
other languages.

### Mirror the syntax used to construct values

Pattern matching, especially destructuring patterns, are basically the dual to
expressions. An expression like a list literal or constructor call takes a
series of subexpressions (the list elements or constructor arguments) and
bundles them together into a new composite object. A list or instance
destructuring pattern does the opposite. It takes a composite value and pulls
out the elements or fields.

A brilliant aspect of patterns in other languages is that the syntax reflects
this duality. A list *pattern* looks like a list *expression*. This helps users
infer what it does. Consider:

```dart
var list = [1, 2, 3];
var [a, b, c] = list;
print("$a $b $c");
```

Even if you've never heard of destructuring, there's a good chance you can guess
what's going on here just from the syntactic similarity.

### Follow existing variable syntax when possible

Most languages that have patterns use patterns for all variable declarations.
Dart already has its own variable declaration syntax which it inherited from C
by way of Java and JavaScript.

We almost certainly want *some* kind of variable declaration syntax that uses
patterns so that you can destructure objects in a single statement like the list
example above. It *may* be that we can subsume *all* variable declarations into
that syntax.

Either way, given that there are already millions of Dart variable declarations,
a new pattern syntax that also lets you bind variables, possibly with type
annotations, should hew to that if possible so that the two styles are similar.
It's less to learn, easier to move between the two forms, and less to visually
distract the reader.

Likewise, a function's parameter list can also be considered a kind of pattern
and explicitly is in some other languages with patterns. (We may want to
consider even supporting patterns in parameter lists.) In that case, it would be
good if the pattern syntax doesn't clash with the parameter syntax.

### Allow user extensibility

One way to make languages more powerful and flexible is by mapping the
language's syntax to a protocol whose behavior users can define. This way a
single language feature can do many different things just by users implementing
that protocol in different ways.

The canonical example is for-in loops. A for-in loop is a built-in statement
form in Dart. But its semantics are defined in terms of invoking methods on the
Iterable object being looped over. By implementing Iterable in interesting ways,
you can use for-in loops to walk custom data structures, generate infinite
numeric sequences, or whatever else you want.

I think it's a good goal for at least some patterns to be extensible in the same
way. That means some patterns would be syntactic sugar for some kind of "match
and destructure" operation. For example, Scala does this using
[`unapply()`][unapply].

[unapply]: https://docs.scala-lang.org/tour/extractor-objects.html

## Kinds of Patterns

That's how I look at the feature in general. Now, more specifically, what kind
of functionality do we want pattern matching to support? What kind of patterns
do we want?

### Bind variables

A fundamental aspect of pattern matching is binding new variables to
subcomponents of a matched object, so we'll need variable patterns that
introduce a new binding. We'll likely also want a "wildcard" pattern that
accepts all values but doesn't introduce a variable.

### Match against literal values

Many users aren't a fan of the existing switch statement. The required `break;`
statements are needlessly verbose, and it might be good to have a form that can
be used as an expression and not just a statement. That means a new pattern
matching construct should be able to do what switches can do.

An obvious simple feature is matching against literal values: numbers, strings,
Booleans, etc. All other languages support this. So you should be able to use
things like `3` and `"a string"` as patterns. They match when the value is
equivalent to the literal:

```dart
var value = 2;
match (value) {
  case 1 => print("one");
  case 2 => print("two");
  case 3 => print("three");
}
// Prints "two".
```

### Match against constants

Literals are fine but good programming practice is that literals should be
stored in named constants instead of being used directly as magic numbers. Most
current switch statements do not switch on literals. They usually switch on
named constants or enum values. We certainly want to support enums:

```dart
enum Color { red, green, blue }

showColor(Color c) {
  match (c) {
    case Color.red => print("red");
    case Color.green => print("green");
    case Color.blue => print("blue");
  }
}
```

We probably also want to support named constants:

```dart
const one = 1;
const two = 2;
const three = 3;

var value = 2;
match (value) {
  case one => print("one");
  case two => print("two");
  case three => print("three");
}
// Prints "two".
```

This introduces significant complexity. We'll also want variable binding
patterns, which are also naturally represented as an identifier. If we allow
constant patterns to also be simple bare identifiers, it means we need to do
lexical scope resolution to determine if a pattern is a constant pattern or a
variable pattern.

We'll presumably want to support dotted identifiers for enum cases. I imagine
users will expect that to also work for named constants imported from libraries
with a prefix.

That raises the question of whether we want to support arbitrary constant
expressions. That has some appeal, but means that much of the expression grammar
would overlap the pattern grammar, which leads to ambiguity and pain. Consider,
for example, `[1, 2]`. Is that a constant pattern containing a constant list
literal, or a list destructuring pattern containing two literal patterns?

### Destructure collections

A key goal and a feature offered by other languages is patterns that can match
and pull elements out of collections. Dart already has lists, maps, and sets.
Patterns to let you destructure those are an obvious feature.

We also want to add [tuples][] and those almost require destructuring because it's
difficult to otherwise access the elements in a type safe way, since tuples are
heterogeneously typed.

[tuples]: https://github.com/dart-lang/language/issues/68

As in other languages, the syntax for these should mirror the corresponding
collection literal expression form:

```dart
Object obj = ...
match (obj) {
  case [a, b] => print("list with elements $a and $b");
  case {a, b} => print("set with elements $a and $b");
  case (a, b) => print("tuple with elements $a and $b");
}
```

Maps are a little trickier. Do they match specific entries, in which case the
key is a value, or do they destructure any entry, in which case the key is a
pattern?

### Destructure instances of classes

Another common use of pattern matching is for working with [sum types][]. In
typed functional languages, sum types are the typical way to define values that
can be one of a few different cases, with potentially nested data for each case.
Pattern matching is then how you implement behavior that varies based on which
case you have.

[sum types]: https://en.wikipedia.org/wiki/Tagged_union

In an object-oriented language, those cases are modeled using subclasses. Thus,
to use pattern matching to select behavior based on a sum type case, we need
patterns that match a specific subclass and extract fields from it.

For example, something like this:

```dart
abstract class Shape {}
class Rect extends Shape {
  final num left, top, right, bottom;
  Rect(this.left, this.top, this.right, this.bottom);
}
class Circle extends Shape {
  final num x, y, radius;
  Circle(this.x, this.y, this.radius);
}

printShape(Shape shape) {
  match (shape) {
    case Rect(left, top, right, bottom) =>
        print("Rect $left, $top, $right, $bottom");
    case Circle(x, y, radius) =>
        print("Circle $x, $y, $radius");
  }
}
```

Here, the `Rect(...)` and `Circle(...)` are matching on shapes of the
appropriate subclass and then, when they match, somehow pulling out fields. This
would let us enable the sum type functional programming style many users want by
expressing it in terms to the object-oriented model Dart already has.

### Match on types

Destructuring against instances implicitly also requires that the value be an
instance of that destructured class, so there is some level of type testing
going on. But it's also useful to just test a value against a type without doing
any destructuring. For example, code like this is fairly common:

```dart
printJson(Object json) {
  if (json is String) {
    print(json);
  } else if (json is num) {
    print(json);
  } else if (json is List<Object>) {
    print("[");
    json.forEach(printJson);
    print("]");
  }
}
```

Here, we rely on type promotion inside the then branches to promote `json` to
the tested type. That works, but gets verbose. It would be good to be able to
use a more concise pattern matching structure for code like this.

### Extract runtime type arguments

It doesn't happen often, but you occasionally want to write code that takes the
type argument of one object and propagates it to another. For example, say you
want to convert a list to a set of the same type. Often you can accomplish what
you need just using generic methods:

```dart
Set<T> listToSet<T>(List<T> list) {
  var set = Set<T>();
  for (var element in list) set.add(element);
}
```

The list's type is propagated *statically* through the program and the result is
a list of the "same" type. But here, "same" means the same *static* type:

```dart
main() {
  List<Object> list = <int>[1, 2, 3]; // Upcast.
  var set = listToSet(list);
  print(set.runtimeType);
}
```

If you run this, it prints `Set<Object>`, not `Set<int>`. Because of the upcast,
the static type system has "lost track" of the precise runtime type of the list.
The set you get back doesn't have the same type argument as the actual list
*object* passed in at runtime.

Fortunately, this is rarely a problem in practice. But sometimes, especially in
frameworks that do things like generic serialization, you actually need to be
able to create an object of some generic type whose type argument is the same as
the *runtime* type argument of some other object.

We identified this need during the transition to Dart 2.0, but didn't have time
to design a good solution. Instead, we added a hacky library so gross I won't
mention it here in order to migrate the few packages like observable that need
it. Since then, we have wanted a better solution.

Patterns give us a natural place for that solution. A [*type pattern*][type
pattern] could match an object of a generic class and bind a new *type* variable
to the object's runtime type argument(s). Then the body of that match case can
use that type variable in things like generic constructor calls.

[type pattern]: https://github.com/dart-lang/language/issues/170

### Guard clauses

This isn't *quite* tied to patterns, but most languages with a pattern matching
construct also support *guard clauses*. These are arbitrary predicate
expressions you place after the pattern. A pattern only matches if that
expression evaluates to true.

In C#, these are [`when` clauses][csharp when]. In Haskell, [they appear after
a `|`][haskell guard].

[csharp when]: https://docs.microsoft.com/en-us/dotnet/csharp/pattern-matching#when-clauses-in-case-expressions

[haskell guard]: http://learnyouahaskell.com/syntax-in-functions

## Uses for Patterns

Once you have patterns, they need to be embedded in some other language
constructs that developers can actually use. I've mentioned a few, but I'll run
quickly through places we should or could consider:

*   **A pattern matching statement.** Like a switch statement but where each
    case clause is a pattern instead of a simple constant expression.

*   **A pattern matching *expression*.** Statements are fine for imperative
    code, but people using patterns often like to write in a functional,
    expression-oriented style. In that case, it might be good to have a pattern
    matching construct that can be embedded in an expression.

    Match expressions rely on good exhaustiveness checking. A statement can
    simply do nothing if no case matches. An expression must evaluate to *some*
    value (or throw an exception, which is rarely helpful). That means ensuring
    that at least one case matches and telling the user at compile time if that
    may not happen.

*   **A declaration statement.** If you have some object that you know has a
    certain structure and you just want to destructure it and pull out some data
    bound to new variables, it's very handy to have a variable declaration
    statement form that takes a single pattern and matches it against the
    initializer.

    Most languages with pattern matching use this for all variable declarations.

*   **For-in loop variable clauses.** A for-in loop is another place where a
    variable can be declared. We could extend that to support arbitrary patterns.
    This might be particularly useful for iterating over the entries in a map:

    ```dart
    for (var (key, value) in someMap) {
      ...
    }
    ```

*   **A pattern-based if.** This is basically a lightweight, single case pattern
    match statement. You have one pattern and a "then branch" you execute if the
    pattern matches and an optional else branch if it doesn't.

    For example, [C# allows a type pattern][csharp] inside the condition of an
    if statement and Swift has [`if case`][swift].

    [csharp]: https://docs.microsoft.com/en-us/dotnet/csharp/pattern-matching
    [swift]: http://fuckingifcaseletsyntax.com/

*   **Exception catch clauses.** Semantically, a catch clause says "if the
    exception is this type, then execute this block with a new variable of that
    type". That's basically a pattern. We could extend catch clauses to allow
    arbitrary patterns in there.

*   **Parameter lists.** We could allow deeper nested patterns inside function
    parameter lists. This would let you define a function that, say, accepts a
    list and immediately destructures its elements all from the parameter
    signature.

There may be others, but those are the obvious applications.
