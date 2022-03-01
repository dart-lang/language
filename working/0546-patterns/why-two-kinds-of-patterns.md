# Why Two Kinds of Patterns

One of the major design choices [this proposal][proposal] makes is to split
irrefutable and refutable patterns into two separate kinds which it calls
"matchers" and "binders". This makes the grammar and complexity of the feature
larger and means that some pattern syntax means different things in different
contexts.

[proposal]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md

That choice is close to [how pattern matching works in Swift][swift patterns],
but is different from pattern matching in Rust, Scala, ML, and most other
languages. This document explains the motivation behind that choice in
comparison to other possible approaches.

[swift patterns]: https://docs.swift.org/swift-book/ReferenceManual/Patterns.html

The core issue is around how to interpret bare identifiers inside a pattern,
but before we get to that, I want to set some context.

## Refutable and irrefutable patterns and contexts

Languages that feature pattern matching typically embed patterns in several
different surrounding language features. The main one is some kind of multi-way
branching "switch" or "match" form. That's where the "matching" part comes from
in the name. For example, here's a `match` expression in Rust:

```
match value {
  [1, y] => println!("first is one, second is {}", y),
  [x, 1] => println!("second is one, first is {}", x),
  _ => println!("something else"),
}
```

Here, `[1, y]` and `[x, 1]` are each list patterns containing a pair of
subpatterns for each element. If `value` evaluates to a two-element list whose
first element is 1 then the first pattern *matches* (and binds `y` to the value
of the second element). When a pattern doesn't match the value, we say it was
"refuted". When a pattern doesn't match, control flow skips over the region of
code where any variables in the pattern are in scope. That way, it's impossible
to access a variable bound by a pattern unless the pattern successfully matched.

But languages with patterns also usually allow patterns in local variable
declarations to destructure values. Again, here's some Rust:

```rust
let [x, y] = [1, 2];
```

Here, the `[x, y]` pattern is matched against the list `[1, 2]`. It extracts the
two elements and binds `x` to 1 and `y` to 2. In this case, the code is fine
since the value being matched is a two-element list and variable patterns always
match.

### Refutable patterns in irrefutable contexts

But what if you used a pattern that *could* be refuted? What happens if you try
to write:

```rust
let [x, 2] = [1, 3];
```

Here, the `2` on the left is a refutable literal pattern that only matches if
the value being matched is equal to the literal. That match would fail here.
Then what?

In Rust, code like this is a compile error:

```
error[E0005]: refutable pattern in local binding: `[_, i32::MIN..=1_i32]` and `[_, 3_i32..=i32::MAX]` not covered
 --> src/main.rs:2:9
  |
2 |     let [x, 2] = [1, 2];
  |         ^^^^^^ patterns `[_, i32::MIN..=1_i32]` and `[_, 3_i32..=i32::MAX]` not covered
  |
  = note: `let` bindings require an "irrefutable pattern", like a `struct` or an `enum` with only one variant
  = note: for more information, visit https://doc.rust-lang.org/book/ch18-02-refutability.html
  = note: the matched value is of type `[i32; 2]`
help: you might want to use `if let` to ignore the variant that isn't matched
  |
2 |     if let [x, 2] = [1, 2] { /* */ }
  |
```

Rust doesn't let you use any refutable pattern in a non-refutable context like a
variable declaration. So even Rust only has a single kind of pattern syntax that
is used everywhere, in some contexts only a subset is allowed. Here's Scala:

```scala
var (x, 3) = (1, 2)
```

Unlike Rust, Scala will happily let you write and compile this code. You can
use refutable patterns in variable declarations. When you run the program, if
the match fails, it throws an exception:

```
scala.MatchError: (1,2) (of class scala.Tuple2$mcII$sp)
  at Playground$.delayedEndpoint$Playground$1(main.scala:26)
  at Playground$delayedInit$body.apply(main.scala:2)
  at scala.Function0.apply$mcV$sp(Function0.scala:39)
  at scala.Function0.apply$mcV$sp$(Function0.scala:39)
...
```

That's the terrain we're exploring. Some patterns can or can't be refuted and
some surrounding contexts can or can't gracefully handle refutatation. A
language with patterns has to decide whether and how to unify refutable and
irrefutable patterns and what to do when a refutable pattern appears in an
irrefutable context.

## Identifiers in patterns

A key syntax design problem for bringing patterns to Dart is how to handle bare
identifiers. We want pattern matching to feel seamless with the rest of the
language. We can approach that by starting with the Dart language we have now
and think about how we might extend it to allow patterns inside some existing
constructs.

### Destructuring variable declarations

One place is destructuring local variable declarations. Variables look like
this now:

```dart
var n = 1 + 2;
```

You could imagine extending that to allow destructuring patterns like so:

```dart
var [x, y] = [1, 2];
```

Here, the `x` and `y` bare identifiers represent names of new variables being
bound, just like the bare identifier `n` does in the first example. This looks
pretty nice to me, and it's consistent with destructuring in JavaScript, Rust,
Swift, and others.

### Pattern matching in switches

The other main use for patterns is a multi-way branching construct. Dart already
has a multi-way branching switch statement:

```dart
const red   = 0xff0000;
const green = 0x00ff00;
const blue  = 0x0000ff;

switch (color) {
  case red:   print('red'); break;
  case green: print('green'); break;
  case blue:  print('blue'); break;
  default:    print('other'); break;
}
```

In Dart today, switch cases are constant expressions. Here, they are named
references to constant declarations. (We could have inlined those hex literals
instead, but using named constant is idiomatic to avoid [magic numbers][].)

[magic numbers]: https://en.wikipedia.org/wiki/Magic_number_(programming)

We could extend this to allow matching on more interesting structured values
like so:

```dart
const red   = 0xff0000;
const green = 0x00ff00;
const blue  = 0x0000ff;

switch ([color1, color2]) {
  case [red, green]:  print('yellow'); break;
  case [green, blue]: print('cyan'); break;
  case [blue, red]:   print('magenta'); break;
  default:            print('other'); break;
}
```

This seems like a natural extension of the existing syntax. Here, bare
identifiers in the list patterns like `red` in `[red, green]` are references to
named constants. Those subpatterns should match if the destructured list element
is equal to that constant value.

### Two meanings for the same syntax

This is the crux of the problem. We want to use patterns in both variable
declarations and switches (or something switch-like). In both of those
statements, it seems natural and consistent with the existing language to use
bare identifiers as patterns. But the natural semantics to assign to them in
each kind of statement disagree—variable bindings in one and constant matching
in the other.

## What other languages do

It's generally a good idea to avoid novelty in programming language design.
Other language designers are smart and it's good to stand on their shoulders.
Also, users often come to Dart from other languages and bring their expectations
with them. Consistency with popular languages is key to making Dart easy to
learn.

Whenever I'm working on a feature, I look at what other languages do. Here's a
few:

### Rust

If you run:

```rust
let [x, y] = [1, 2];
println!("{} {}", x, y);
```

It prints "1 2". So here, it treats bare identifiers as variable bindings. But,
if you run this:

```rust
const N: i32 = 10;

match 10 {
    N => println!("is ten"),
    _ => println!("not ten"),
}
```

Then it prints "is ten". Here, the `N` pattern works like an equality check
against the corresponding named constant.

Here's a fun one:

```rust
const N: i32 = 10;

match [8, 2] {
    [N, x] => println!("ten {} and {}", N, x),
    _ => println!("not ten"),
}
```

This one prints "not ten". The first identifier `N` is treated as a constant
pattern, but the second identifier `x` is a variable pattern.

The rule in Rust for handling identifiers in patterns is this: Try to resolve
the identifier. If it resolves to some in-scope constant, then the identifier is
a constant pattern. Otherwise, if the identifier doesn't resolve to anything,
then it's a variable binder.

In the previous example, if we comment out the constant and run it again:

```rust
// const N: i32 = 10;

match [8, 2] {
    [N, x] => println!("ten {} and {}", N, x),
    _ => println!("not ten"),
}
```

It still compiles. But now the `N` in the pattern has become a variable binding.
And, since variable patterns always match, now the first pattern matches and it
prints "ten 8 and 2". This all means that in order to understand what a pattern
means, you need to have some idea of the names of the constants that are in
scope.

### Haskell

It's a little hard to map a functional language like Haskell to Dart because
the way data is modeled is so different. Haskell leans heavily on algebraic
datatypes so where you might use an enum or constant values in Dart, you're
more likely to use type constructors in Haskell. For example:

```haskell
data Planet = Jupiter | Saturn | Uranus | Neptune
```

Here, the planet names work like constants. You can match on them by name like
so:

```haskell
moons :: Planet -> Int
moons planet = case planet of Jupiter -> 53
                              Saturn -> 82
                              Uranus -> 27
                              Neptune -> 14
```

Variable patterns look like `other` in:

```haskell
isIce :: Planet -> Bool
isIce planet = case planet of Jupiter -> false
                              Saturn -> false
                              other -> true
```

Haskell doesn't have any real way to match against other named constants, though
there are some extensions and workarounds ([1][haskell 1], [2][haskell 2]).

[haskell 1]: https://stackoverflow.com/questions/35429144/haskell-using-a-constant-in-pattern-matching
[haskell 2]: https://stackoverflow.com/questions/35417305/constants-in-haskell-and-pattern-matching

In order to distinguish type constructor patterns from variable patterns, the
language uses case. Unlike Rust, where case is just a convention, in Haskell
it's baked directly into the language. Type constructors *must* start with a
capital letter and variable *must* start with a lowercase one.

### Scala

Scala takes a lot of cues from the ML family of languages (of which Haskell is
one), so it also uses case to distinguish variable patterns from constant
patterns. Scala calls an identifier that starts with capital letter a "[stable
identifier][]". If an identifier in a pattern is stable, then it is treated as a
constant pattern. Otherwise, it's a variable:

[stable identifier]: https://scala-lang.org/files/archive/spec/2.13/08-pattern-matching.html#stable-identifier-patterns

```scala
val Two = 2 // Capitalized.
3 match {
  case Two => println("was two")
  case _ => println("some other value")
}

val two = 2 // Lowercase.
3 match {
  case two => println("was two")
  case _ => println("some other value")
}
```

Here, the first example prints "some other value" and the second one prints "was
two". Similar to Rust, the rule works since Java has a convention of using
`SCREAMING_CAPS` for constants and Scala's convention is `UpperPascalCase`.

### Swift

Swift [takes a different approach][swift patterns] from all of those languages.
And, if you're familiar with the patterns proposal for Dart, you can probably
guess it. Swift defines two separate kinds of patterns: those that always
succeed and those that might fail. Each has its own syntax and semantics.

The first kind, irrefutable patterns, correspond to what the Dart proposal calls
"binders" and are used in variable declarations:

```swift
let (a, b) = (1, 2)
print("\(a) and \(b)") // Prints "1 and 2".
```

In these patterns, an identifier like `a` and `b` is treated as a variable
declaration. In switch cases, where a pattern might fail to match, a different
(but somewhat similar) set of patterns comes into play:

```swift
let one = 1
let two = 2
switch (1, 2) {
case (one, two): print("was (1, 2)")
case _:          print("other value")
}
```

Here, tuple patterns like `(...)` work the same for destructuring. But an
identifier is treated as a constant, not a variable. This example prints "was
(1, 2)" since the first element of the matched tuple is equal to the constant
`one` and the second element is equal to the constant `two`.

Of course, you often want to both match values and bind variables inside a
switch case. To enable that, Swift supports explicit value binding patterns that
can be nested inside a matching pattern:

```swift
let one = 1
switch (1, 2) {
case (one, let x): print("was one and \(x)")
case _:            print("other value")
}
```

Here, the `let x` subpattern binds a new variable `x` to the second element of
the matched tuple. This program prints "was two and 2".

## Evaluating an approach for Dart

So there's a few ways I've seen other languages handle refutable and irrefutable
patterns. We might also come up with something novel. Let's run through the
options I considered:

### Use identifier resolution to disambiguate

This is Rust's approach. If an identifier in a pattern resolves to a constant,
then treat it as a constant pattern. Otherwise, make it a variable declaration.

This means that, in principle, in order to tell what a pattern means, you need
to know what constants are in scope. For Rust, in practice [the naming
convention][rust style] makes this a non-issue. Constants are `SCREAMING_CAPS`
and variables are `snake_case`, so it's clear just from looking at the pattern
what's going on.

[rust style]: https://rust-lang.github.io/api-guidelines/naming.html

But Dart's style guide uses `lowerCamelCase` for both variables and constants. A
pattern like `Error(message)` in a pattern doesn't tell you if you're trying to
see if an object *matches* some specific known constant `message` or if you're
trying to *extract* the error message from the object and store it in a variable
named `message`.

It's even harder in Dart because idiomatic imports are unprefixed and
unrestricted. The last I checked, something like 90% of imports did not use a
prefix, `hide`, or `show` clause. So in order to tell if an identifier in a
pattern refers to a constant, you can't even reliably tell by looking at the
entire *file* because it could easily be imported. You'd have to rely on an IDE.

It's possible that upgrading to a new version of some library you're importing
removes a constant. When that happens, the pattern that used to *match* against
that constant value now silently turns into a variable pattern that will accept
*any* value. Instead of getting an error about referring to an unknown constant,
you get code that compiles and runs but behaves differently.

This feels highly brittle and context-sensitive to me and not a good fit for
Dart.

### Use identifier case to disambiguate

The Rust ecosystem relies on the naming convention to distinguish constants and
variables in patterns, but the language itself doesn't. Haskell and Scala
actually bake that convention into the language syntax. This makes it more
reliable than a convention.

Either way, the rules works in those languages because capitalized or all caps
identifiers make sense for constants or type constructors. But, again, Dart uses
`lowerCamelCase` for both variables and constants, so there's no syntactic
convention we can use to distinguish them.

(This convention was chosen *by design* because it makes it easier for a library
maintainer to change a variable into a constant without breaking existing uses
by needing to change the case of the identifier.)

It would be a massively breaking change to rename every constant in the Dart
ecosystem.

### Use a distinct syntax for constant patterns

So we have two kinds of patterns that both want to claim a bare identifier.
Instead of disambiguating by tweaking the identifier itself, we could simply
make the surrounding *pattern* syntax unique.

My first hobby programming language [used `== identifer` as the syntax for
patterns][magpie] that matched against a constant value. Then a simple
identifier would unambiguously be a variable declaration.

[magpie]: http://magpie-lang.org/patterns.html#equality-patterns

This is simple, non-breaking, and unambiguous. It also just looks really weird
to see `==` as a sort of prefix operator. Worse, it's inconsistent with what
every existing switch case in Dart that matches a named constant looks like
today.

We would have to either define some new kind of `match` statement separate
from switches to support the new pattern syntax, or break tons of existing code
and require users to migrate every `case foo:` to `case == foo:`. Neither of
those seem like a very appealing path, especially when the destination is an
ugly, unfamiliar syntax.

### Use a distinct syntax for variable patterns

A more promising approach is to treat bare identifiers as constant patterns.
That's consistent with how switch cases look. Then we give variable patterns a
distinct syntax, like `var identifier`:

```dart
const red = 0xff0000;
const green = 0x00ff00;
const blue = 0x0000ff;

switch ([color1, color2]) {
  case [red, var other]: print('reddish $other');
  //         ^^^^^^^^^
  case [green, blue]:    print('cyan');
  case [blue, red]:      print('magenta');
}
```

That looks pretty nice in a switch case, I think. It also lets you easily mix
and match variable patterns and constant patterns together like the example
here. How does it look in a variable declaration?

```dart
var [var x, var y] = [1, 2];
```

OK... that's pretty strange. It seems redundant to have to say `var` twice.
The whole point of this statement is to bind variables, so it seems pretty
obvious that `x` and `y` are variables.

What would happen if you accidentally omitted `var` in this example?

```dart
var [x, y] = [1, 2];
```

Here, `x` and `y` are refutable constant patterns. But we're not in a constant
where refutation can be handled. How should this behave?

I don't think we want to take Scala's approach and allow this but have it throw
an exception at runtime. The clear trend in Dart since 2.0 is towards better
static checking and fewer runtime errors. Instead, like Rust, it should probably
be a compile error to use a refutable pattern in a variable declaration where
refutation can't be handled.

So the obvious syntax would simply be forbidden.

### Different refutable and irrefutable patterns

This gets us to Swift's approach. In languages like Rust where it's a compile
error to use a refutable pattern in an irrefutable context, you can think of it
as there being two separate kinds of patterns:

*   The ones you can use in match cases, which might be refuted.
*   The ones you can use in variable declarations, which are never refutable.

The latter patterns happen to be a strict subset of the former ones. There's
value in this design because there's less total language to learn. Once you know
all the patterns that can be used in a match case, you've also learned all the
patterns that can appear in variable declarations too. You do still have to
learn which *subset* of the refutable patterns are allowed in irrefutable
contexts.

Swift takes that observation one step further. If some refutable pattern syntax
can't be used in a variable declaration and causes a compile error if you try...
why not repurpose that syntax to mean something *useful?*

In particular, it means that we can have an identifier in an irrefutable
context implicitly mean "bind a variable" because that's consistent with simple
variable declarations.

At the beginning of this document, I suggested you could approach the design by
trying to take Dart's existing variable declarations and switch statements and
extending them to support patterns:

```dart
// This:
var x = 1 + 2;
// Leads to:
var [x, y] = [1, 2];

// And this:
switch (color) {
  case red: print('red'); break;
  case green: print('green'); break;
  case blue: print('blue'); break;
}

// Leads to:
switch ([color1, color2]) {
  case [red, green]:  print('yellow'); break;
  case [green, blue]: print('cyan'); break;
  case [blue, red]:   print('magenta'); break;
  default:            print('other'); break;
}
```

With an approach like Swift's, *both* of these can work at the same time.

Having the same syntax mean different things does mean users have to *know* what
context a pattern appears in. But even in a language like Rust with a single
pattern grammar, they have to know that already to know which patterns are
*allowed*.

Unlike Rust's approach of trying to resolving the identifer, the only context
the user has to be aware of is *purely local and syntactic*. They don't need to
know what names are in scope or anything types or inference. It's basically, "Is
there a `case` to my left? OK, it's a matcher. Is there a `var` or `final`? Must
be a binder."

This does mean that a bare identifier is sort of "syntactically overloaded" in
that it would mean something different in different contexts. But Dart overloads
other syntax like that and it mostly works out:

*   `if` is a statement in a block but an element in a collection literal.
*   `[1]` is a list literal in prefix position, but an index operator call in
    postfix position.
*   `{}` could be an empty block, empty map, or empty set depending on where
    it appears syntactically and even the surrounding type inference context.
*   `?` is used for nullable types, null-aware operators, and conditional
    expressions.

Taking Swift's approach does mean that the resulting grammar is more complex.
It's not a "minimal" design. But I believe that the additional complexity
carries its weight. Having different binder and matcher patterns lets us design
patterns that work well for their contexts and needs.

For example, we can define a `?` null-aware matcher pattern that fails a match
in a switch if the value is null and a separate `!` null-*assert* binder pattern
that *throws* if the value is null. We can have type *test* patterns in switch
cases and type *cast* patterns in variable declarations.

I think it leads to an expressive, useful set of patterns that cover the known
use cases well.
