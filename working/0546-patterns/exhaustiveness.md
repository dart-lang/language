# Exhaustiveness Checking

Author: Bob Nystrom

Status: In progress

Version 1.1 (see [CHANGELOG](#CHANGELOG) at end)

## Summary

This document proposes a static analysis algorithm for exhaustiveness checking
of [switch statements and expressions][switch] as part of the proposed support
for [pattern matching][patterns]. It also tries to provide an intuition for how
the algorithm works.

[switch]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md#switch-statement
[patterns]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md

Exhaustiveness checking is about answering two questions:

*   **Exhaustiveness: Do the cases in this switch cover all possible values of
    the matched type?** In other words, is it possible for some value of the
    matched type to fail to match every case pattern?

    In a language with subtyping like Dart, the answer depends on not just the
    set of cases but also the static type of the matched value:

    ```dart
    switch (b) {
      case true: print('yes');
      case false: print('no');
    }
    ```

    This set of cases is exhaustive if `b` has type `bool`, but if it has type
    `bool?` then it needs a case to match `null`. If `b` has type `Object`, then
    it needs a default or wildcard case to match any non-`bool` types.

    Note that this implies that *exhaustiveness checking happens after type
    inference and type checking*, or at least at a point where the types of
    the matched value and patterns are all known.

*   **Reachability: Is any case unreachable because every value it matches will
    already be matched by some previous case?** For example:

    ```dart
    switch (b) {
      case true: print('yes');
      case false: print('no');
      case bool b: print('unreachable');
    }
    ```

    Here, the third case can never be matched because any value it matches would
    also already be matched by one of the preceding two cases.

Dart already supports exhaustiveness and reachability warnings in switch
statements on `bool` and enum types. This document extends that to handle
destructuring patterns and [algebraic datatype-style][adt] code.

[adt]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md#algebraic-datatypes

The approach is based very closely on the excellent paper ["A Generic Algorithm
for Checking Exhaustivity of Pattern Matching"][paper] by [Fengyun Liu][],
modified to handle named field destructuring and arbitrarily deep sealed class
hierarchies.

[paper]: https://infoscience.epfl.ch/record/225497?ln=en
[Fengyun Liu]: https://fengy.me/

There is a [prototype implementation][prototype] of the algorithm with detailed
comments and tests.

[prototype]: https://github.com/dart-lang/language/tree/master/working/0546-patterns/exhaustiveness_prototype

### Why check for exhaustiveness?

With switch expressions, it seems that we need exhaustiveness for soundness:

```dart
String describeBools(bool b1, bool b2) =>
    switch ((b1, b2)) {
      case (true, true) => 'both true';
      case (false, false) => 'both false';
      case (true, false) => 'one of each';
    };
```

This switch fails to handle `(false, true)`, which means it has no string to
return. Returning `null` would violate null safety. However, if all we cared
about was soundness, we could simply throw an exception at runtime if no case
matches.

The *language* doesn't need exhaustiveness checks. But users strongly prefer
them. A key goal of Dart is to detect programmer errors at compile time when
possible. This makes them faster to detect and fix.

In other words, exhaustiveness checking is a *software engineering feature*: it
helps users write good code. This is particularly true when programming using an
algebraic datatype style. In that kind of code, exhaustiveness checks over the
different case types is how users ensure that an operation is fully implemented.
A non-exhaustive switch error is the functional equivalent to the error in
object-oriented code when a concrete class fails to implement an abstract
method.

## Sealed types

In an object-oriented language like Dart (and Scala and Kotlin), the natural way
to model algebraic datatypes is using subtyping. The main type of the algebraic
datatype becomes a supertype, and the type constructors are each subtypes of
that supertype. For example, if we wanted to model the infamous [Three
Amigos][]:

[three amigos]: https://en.wikipedia.org/wiki/Three_Amigos

```dart
// amigos.dart
abstract class Amigo {}
class Lucky extends Amigo {}
class Dusty extends Amigo {}
class Ned extends Amigo {}

String lastName(Amigo amigo) =>
    switch (amigo) {
      case Lucky _ => 'Day';
      case Dusty _ => 'Bottoms';
      case Ned _   => 'Nederlander';
    }
```

We want this switch to be considered exhaustive. In order for that to be true,
we need to ensure:

1.  `Lucky`, `Dusty`, and `Ned` are the *only* subtypes of `Amigo`.
2.  There are no direct instances of `Amigo` itself. In other words, it's
    abstract.

If both of those are true, then any instance of type `Amigo` will reliably also
be an instance of `Lucky`, `Dusty`, or `Ned` and thus those cases are indeed
exhaustive.

### Global analysis

The second constraint is easy to guarantee using `abstract`. For the first
constraint, Dart could scan every library, find every subtype of `Amigo` in the
entire program and use that as the set of subtypes for exhaustiveness checking.

However, that breaks an important but unstated assumption users have. Say you
create this library:

```dart
// amigo_stats.dart
import 'amigos.dart';

int height(Amigo amigo) =>
    switch (amigo) {
      case Lucky _ => 72;
      case Dusty _ => 76;
      case Ned _   => 67;
    }
```

This code is fine and the switch is exhaustive.

Now in my application, I use your package. I also define my own subclass of
`Amigo`:

```dart
import 'amigo_stats.dart';

class Jefe extends Amigo {}
```

My new subtype of `Amigo` causes the switch in your library to no longer be
exhaustive. Some application that you are totally unaware of causes a compile
error to appear in your code. There is nothing you can to do prevent or fix
this.

In order to avoid situations like this, Dart and most other languages have an
implicit rule that *the compile errors in a file should be determined solely by
the files that file depends on, directly or indirectly.*

If we looked for the whole program to find subtypes for exhaustiveness checking,
we would break that principle.

### Sealing supertypes

Instead, we extend the language to let a user explicitly "seal" a supertype with
a specified closed set of subtypes. No other code is allowed to define a new
subtype of the sealed supertype (using `extends`, `implements`, or `with`). The
supertype is also implicitly made abstract.

This document does *not* propose a specific syntax for sealing, but we'll use
this hypothetical syntax for now to show an example:

```dart
enum Suit { club, diamond, heart, spade }

sealed class Card {
  final Suit suit;
}

class Pip extends Card {
  final int pips;
}

sealed class Face extends Card {}

class Jack extends Face {
  final bool oneEyed;
}

class Queen extends Face {}
class King extends Face {}
```

The above class declarations create the following class hierarchy:

```
 (Card)
   /\
  /  \
Pip (Face)
    /  |  \
   /   |   \
Jack Queen King
```

A parenthesized class name means "sealed". It's important to understand what
sealing does *not* mean:

*   The *subtypes* of a sealed type do not have to be "final" or closed to
    extension or implementation. In the example here, anyone can extend,
    implement or even mixin, say, `Pip` or `Queen`. This doesn't cause any
    problems. And in fact, we use this to turn `Face` into a sealed supertype
    of its own set of subtypes.

*   The subtypes do not have to be disjoint. We could define a `Royalty` class
    that implements `Jack`, `Queen`, and `King`.

*   The subtypes can have other supertypes in addition to the sealed one. We
    could have a `Monarch` interface that `Queen` and `King` implement.

All that matters is that any object that is an instance of the supertype must
also be an instance of one of the known set of subtypes. That gives us the
critical invariant that if we have matched against all instances of those
subtypes, then we have exhaustively covered all instances of the supertype.

## Types, patterns, and spaces

The two questions exhaustiveness answers are defined based on some notion of a
"set of values". A series of cases is exhaustive if the set
of all possible values entering the switch is covered by the sets of values
matched by the case patterns.

Thus the algorithm needs a way to model a (potentially infinite) set of values.
Let's consider a few options:

### Static types

In a statically typed language, the first obvious answer is a static type. A
type does represent a set of values. The type `bool` represents the set `true`
and `false`. The type `DateTime` represents the set of all instances of the
`DateTime` class or any of its subtypes.

Unfortunately, a static type isn't precise enough:

```dart
Object obj = ...
switch (obj) {
  case DateTime(day: 1): ...
  case DateTime(day: 2): ...
}
```

What static type could represent the set of values matched by the first case?
It's not just `DateTime` because that would imply that the second case is
unreachable, which isn't true. Static types aren't precise enough to represent
instances of a type *with certain destructured properties*.

### Patterns

A type with some properties sounds a lot like a pattern. Patterns are a much
more precise way to describe a set of values&mdash;that precision is essentially
why they exist. If we want to represent "the set of all instances of `DateTime`
whose `day` field is `1`" then `DateTime(day: 1)` means just that.

That's close to how this algorithm models patterns, but there are two minor
problems:

1.  Patterns aren't quite expressive enough. In the above switch statement, what
    pattern describes the set of values matched by *both* of those cases? We
    can't easily express that using the proposed patterns because there's no
    union pattern to represent "`1` or `2`".

2.  On the other hand, patterns are too complex. Because the proposal is
    intended to be richly expressive, it defines a large number of different
    kinds of patterns each with its own semantics. Handling every one of those
    (and every pairwise combination of them) would add a lot of complexity to
    the algorithm.

### Spaces

Instead, following Liu's paper, we use a data structure called a *space*. Spaces
are like patterns, but there are only a couple of kinds:

*   An **empty space** contains no values. We'll write it as just "empty".

*   An **object space** is similar to an [object pattern][]. It has a static
    type and a set of "named" fields. "Name" is in quotes because it's usually a
    simple string name but we can generalize slightly to allow names like `[2]`
    or `[someConstant]` in order to model list and map element access as named
    fields. For our purposes, the name just needs to be some fixed "key" that is
    computable at compile time and can be compared for equality to other keys.
    The value for each field is a space, and spaces can nest arbitrarily deeply.

    An object space contains all values of the object's type (or any subtype)
    whose field values are contained by the corresponding field spaces.

    If an object space has no fields, then it simply contains all values of some
    type. When the type is "top" (some presumed top type), it is similar to a
    record pattern in that it contains all values whose fields match. If the
    object space has type "top" and no fields, it contains all values.

    In this document, if an object space has no fields, we write it just as a
    type name like `Card`. If its type is "top", we omit the type and write it
    like `(pips: 3)`.

[object pattern]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md#object-pattern

*   A **union space** is a series of two or more spaces. It contains all values
    that are contained by any of its arms. Whenever a union space is created, we
    simplify it:

    *   Discard any empty spaces since they contribute nothing.
    *   If any two spaces are equivalent, keep only one. Equivalence here is
        defined structurally or syntactically in the obvious way.

    This isn't necessary for correctness, but is important for performance to
    avoid exponential blow-up. In theory, discarding duplicates is `O(n^2)`. In
    practice, it should be easy to define a hash code and use a hash set for the
    arms.

    In the document, we write unions as the arms separated by `|` like:

    ```
    Pip(pips: 5)|Queen|King
    ```

### Types in spaces

Object spaces have a static type and the algorithm needs to work with those. For
our purposes, the only thing we need to be able to ask about a type is:

*   Is it a subtype of some other type? And, conversely, is one type a supertype
    of another? Note that "subtype" and "supertype" aren't "strict". A type is
    its own subtype and supertype.
*   Is it sealed?
*   If so, what are its direct subtypes?
*   Is it the same as some another type?

## Lifting types and patterns to spaces

An algorithm that works on spaces isn't very useful unless we can plug it in to
the rest of the system. We need to be able to take Dart constructs and lift them
into spaces:

*   **Static type:** An object space with that type and no fields.

*   **Record pattern:** An object space with type "top". Then lift the record
    fields to spaces on the object space. Since object spaces only have named
    fields, lift positional fields to implicit names like `field0`, `field1`,
    etc.

*   **List pattern:** An object space whose type is the corresponding list type.
    Element subpatterns lift to fields on the object with names like `[0]`,
    `[1]`, etc.

*   **Map pattern:** Similar to lists, an object space whose type is the
    corresponding map type. Element subpatterns are lifted to object fields
    whose "names" are based on the map key constant, like `[someConstant]`.

*   **Wildcard pattern:** An object space of type "top" with no fields.

*   **Variable pattern:** An object space whose type is the variable's type
    (which might be inferred).

*   **Literal or constant matcher:** These are handled specially depending on
    the constant's type:

    *   We treat `bool` like a sealed supertype with subtypes `true` and
        `false`. The Boolean constants `true` and `false` are lifted to object
        patterns of those subtypes.

    *   Likewise, we treat enum types as if the enum type was a sealed supertype
        and each value was a singleton instance of a unique subtype for that
        value. Then an enum constant is lifted to an object pattern of the
        appropriate subtype.

        In the previous card example, we treat `Suit` as a sealed supertype with
        subtypes `club`, `diamond`, `heart` and `spade`.

        (We are *not* proposing adding Java-style enum value subtypes to the
        Dart language. This is just a way to model enums for exhaustiveness
        checking.)

    *   We lift other constants to an object pattern whose type is a synthesized
        subtype of the constant's type based on the constant's identity. Each
        unique value of the constant's type is a singleton instance of its own
        type, and the constant's type behaves like an *unsealed* supertype. Two
        constants have the same synthesized subtype if they are identical
        values.

        This means you don't get exhaustiveness checking for constants, but do
        get reachability checking:

        ```dart
        String s = ...
        switch (s) {
          case 'a string': ...
          case 'a string': ...
        }
        ```

        Here, there is an unreachable error on the second case since it matches
        the same string constant. Also the switch has a non-exhaustive error
        since it doesn't match the entire `String` type.

*   **Null-check matcher:** An object space whose type is the underlying
    non-nullable type of the pattern. It contains a single field, `this` that
    returns the same value it is called on. That field's space is the lifted
    subpattern of the null-check pattern. For example:

    ```dart
    Card? card;
    switch (card) {
      case Jack(oneEyed: true)?: ...
    }
    ```

    The case pattern is lifted to:

    ```
    Card(this: Jack(oneEyed: true))
    ```

*   **Object pattern:** An object space whose type is the object pattern's type
    and whose fields are the lifted fields of the object pattern. Positional
    fields in the object pattern get implicit names like `field0`, `field1`,
    etc.

*   **Declaration matcher:** The lifted space of the inner subpattern.

*   **Null-assert or cast binder:** An object space of type `top`. These binder
    patterns don't often appear in the matcher patterns used in switches where
    exhaustiveness checking applies, but can occur nested inside a [declaration
    matcher][] pattern.

    [declaration matcher]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md#declaration-matcher

**TODO: Once generics are supported, describe how type patterns are lifted to
spaces here.**

## The algorithm

We can now lift the value type being switched on to a space `value` and lift the
patterns of all of the cases to spaces. To determine exhaustiveness and
reachability from those, we need only one fundamental operation, subtraction.
`A - B = C` returns a new space `C` that contains all values of space `A` except
for the values of space `B`.

Given that, we can answer the two exhaustiveness questions like so:

### Exhaustiveness

1.  Discard any cases that have guards. Since static analysis can't tell when
    a guard might evaluate to false, any case with a guard doesn't reliably
    match values and so can't help prove exhaustiveness.

2.  Create a union space, `cases` of the remaining case spaces. That union
    contains all values that will be matched by any case.

3.  Calculate `remaining = value - cases`. If `remaining` is empty, then the
    cases cover all values and the switch is exhaustive. Otherwise it's not, and
    `remaining` can be used in error messages to describe the values that won't
    be matched.

### Unreachability

1.  For each case `case` except the first:

    1.  Create a union space `preceding` from all of the preceding cases (except ones with
        guards).

    2.  Calculate `remaining = case - preceding`. If `remaining` is empty, then
        every value matched by `case` is also matched by some preceding case
        and the case is unreachable. Otherwise, the case is reachable and
        `remaining` describes the values it might match.

Note that we can calculate reachability even for cases with guards. It's useful
to tell if a case with a guard is completely unreachable. It's just that we
ignore guards on *preceding* cases when determining if each case is reachable.

## Space subtraction

To calculate `C = A - B`:

*   If `A` is empty, then `C` is empty. Subtracting anything from nothing still
    leaves nothing.

*   If `B` is empty, then `C` is `A`. Subtracting nothing has no effect.

*   If `A` is a union, then subtract `B` from each of the arms and `C` is a
    union of the results. For example:

    ```
    X|Y|Z - B  becomes  X - B | Y - B | Z - B
    ```

    Subtracting values from a union is equivalent to subtracting those same
    values from every arm of the union.

*   If `B` is a union, then subtract every arm of the union from `A`. For
    example:

    ```
    A - X|Y|Z  becomes  A - X - Y - Z
    ```

    Subtracting a union is equivalent to removing all of the values from all of
    its arms.

*   Otherwise, `A` and `B` must both be object unions, handled in the next
    section.

## Object subtraction

Before we get into the algorithm, let's try to build an intuition about why it's
complex and how we might tackle that complexity. Object spaces are rich data
structures: they have a type and an open-ended set of fields which may nest
spaces arbitrarily deeply.

When subtracting two objects, they may have different types, or the same. They
may have fields that overlap, or a field name may appear in one and not the
other. All of those interact in interesting ways. For example:

```
Card(suit: heart|club) - Card(suit: club) = Card(suit: heart)
```

This is pretty simple. We recurse into the field and subtract the corresponding
spaces in the obvious way. Here's a similar example:

```
Jack(suit: heart|club) - Card(suit: club) = Jack(suit: heart)
```

The objects have different types now, but it still works out. Now consider:

```
Card(suit: heart|club) - Jack(suit: club)
```

It's not as obvious what the solution should be. It's not `Card(suit: heart)`
because the space should still contain clubs that aren't jacks. It's not
`Jack(suit: heart)` because it should still allow other ranks. It turns out the
answer is:

```
Pip(suit: heart|club)|Jack(suit: club)|Queen(suit: heart|club)|King(suit: heart|club)
```

### Representing holes

It might be surprising that subtracting one simple space from another simple
space yields much a more complex space. Since the resulting space is smaller,
shouldn't it be textually smaller?

Consider a simpler space: `(x: Suit, y: Suit)`. It's a pair of two suits, which
are enums. You can think of this space as a 2D grid with an axis for each field.
Each cell is a unique value in the space:

```
         x: club          diamond       heart         spade
y:    club  (x: ♣︎, y: ♣︎)  (x: ♦︎, y: ♣︎)  (x: ♥︎, y: ♣︎)  (x: ♠︎, y: ♣︎)

   diamond  (x: ♣︎, y: ♦︎)  (x: ♦︎, y: ♦︎)  (x: ♥︎, y: ♦︎)  (x: ♠︎, y: ♦︎)

     heart  (x: ♣︎, y: ♥︎)  (x: ♦︎, y: ♥︎)  (x: ♥︎, y: ♥︎)  (x: ♠︎, y: ♥︎)

     spade  (x: ♣︎, y: ♠︎)  (x: ♦︎, y: ♠︎)  (x: ♥︎, y: ♠︎)  (x: ♠︎, y: ♠︎)
```

To calculate `(x: Suit, y: Suit) - (x: club, y: spade)`, we need to poke a hole
in that table:

```
         x: club          diamond       heart         spade
y:    club  (x: ♣︎, y: ♣︎)  (x: ♦︎, y: ♣︎)  (x: ♥︎, y: ♣︎)  (x: ♠︎, y: ♣︎)

   diamond  (x: ♣︎, y: ♦︎)  (x: ♦︎, y: ♦︎)  (x: ♥︎, y: ♦︎)  (x: ♠︎, y: ♦︎)

     heart  (x: ♣︎, y: ♥︎)  (x: ♦︎, y: ♥︎)  (x: ♥︎, y: ♥︎)  (x: ♠︎, y: ♥︎)

     spade     <hole>     (x: ♦︎, y: ♠︎)  (x: ♥︎, y: ♠︎)  (x: ♠︎, y: ♠︎)
```

We don't have a kind of space that naturally represents a "negative" or hole.
Object spaces model a rectangular region of contiguous cells. They can easily
represent an entire table, row, column, or cell here. But they can't do a more
complex shape.

But we do have unions. We can represent an arbitrarily complex shape using a
union of simple object shapes that cover everything except the missing parts:

```
         x: club          diamond       heart         spade
           ┌────────────┐┌────────────────────────────────────────┐
y:    club │(x: ♣︎, y: ♣︎)││(x: ♦︎, y: ♣︎)  (x: ♥︎, y: ♣︎)  (x: ♠︎, y: ♣︎)│
           │            ││                                        │
   diamond │(x: ♣︎, y: ♦︎)││(x: ♦︎, y: ♦︎)  (x: ♥︎, y: ♦︎)  (x: ♠︎, y: ♦︎)│
           │            ││                                        │
     heart │(x: ♣︎, y: ♥︎)││(x: ♦︎, y: ♥︎)  (x: ♥︎, y: ♥︎)  (x: ♠︎, y: ♥︎)│
           └────────────┘│                                        │
     spade    <hole>     │(x: ♦︎, y: ♠︎)  (x: ♥︎, y: ♠︎)  (x: ♠︎, y: ♠︎)│
                         └────────────────────────────────────────┘
```

Here, the left box is `(x: club, y: heart|diamond|club)` and the right is `(x:
spade|heart|diamond, y: Suit)`. The result the algorithm produces is similar:

```
(x: Suit, y: heart|diamond|club)|(x: spade|heart|diamond, y: Suit)
```

(It uses `Suit` instead of `club` for `x` in the first arm because overlapping
arms are harmless.)

Note that there are multiple ways we could tile a set of objects around a hole.
There are multiple ways to represent a given space. We just need an algorithm
that produces *one*. The process of using a union of objects to represent
removed spaces harder to visualize with more fields because each fields adds a
dimension, but the process still works out.

When subtracting objects with fields, the algorithm's job is to figure out the
union of objects that tile the remaining space and do so efficiently to avoid a
combinatorial explosion of giant unions.

### Mismatched fields

Another problem unique to Dart's approach to pattern matching is that when
subtracting two object spaces, they may not have the same set of fields:

`Jack(suit: heart) - Face(oneEyed: bool)`

To handle this, when calculating `L - R`, we align the two sets of fields
according to these rules:

*   If a field in `R` is not in `L` then infer a field in `L` with an object
    whose type is the static type of the field in `L`'s type. In the above
    example, we would infer `oneEyed: bool` for the left space.

    Since an object only contains values of the matched type, we can assume
    that the field will be present and that every value of that field will be of
    the field's type. Therefore, a field space matching the field's static type
    is equivalent to not matching on the field at all.

*   If a field in `L` is not in `R` then infer a field in `R` with an object of
    type `top`.

    An object with no field allows all values of that field, so inferring "top"
    when subtracting is equivalent to not having the field. (We can't infer
    using the type of the corresponding field in `R`'s type because `R`'s type
    might be a supertype of `L` or even "top" and the field might not exist.)

Whenever we refer to a "corresponding field" below, if the space doesn't contain
it, then it is inferred using these rules.

### Expanding types

Even without fields, subtraction of object spaces can be interesting. Consider:

```
Face - Jack
```

If `Face` isn't a sealed class, there isn't much we can do. But since `Face` is
sealed, we know that `Face` is exactly equivalent to `Jack|Queen|King`. And the
result of that subtraction is obvious:

```
Jack|Queen|King - Jack = Queen|King
```

**Expanding a type** replaces a sealed supertype with its list of subtypes. We
only do this when the left type is sealed and the right type is a subtype.
Expanding is recursive:

```
Card - Jack
```

Here, we first expand `Card` to `Pip|Face`. One of the results is still a sealed
supertype of `R`'s type, so we expand again to:

```
Pip|Jack|Queen|King - Jack = Pip|Queen|King
```

We only expand a sealed supertype if doing so gets closer to a sealed subtype
on the right. If `Pip` was sealed in the above example, we wouldn't expand it.
This way, we minimize the size of the unions we're working with.

We can also expand *object spaces* and not just types, even when the space has
fields. In that case, we copy the fields and produce a union of the results. So:

```
Face(suit: heart) - Jack
```

Expands to:

```
Jack(suit: heart)|Queen(suit: heart)|King(suit: heart) - Jack
```

And now it's easier to see that `Jack` subtracts the first arm leaving:

```
Queen(suit: heart)|King(suit: heart)
```

If the left type is nullable and the right type is `Null` or non-nullable, then
expanding expands the nullable type to `Null` and the underlying type, as if the
nullable type was a sealed supertype of the underlying type and `Null`:

```
Face? - Face  expands to:  Face|Null - Face = Null
Jack? - Null  expands to:  Jack|Null - Null = Jack
```

Likewise, if the left type is `FutureOr<T>` for some type `T` and the right type
is a subtype of `Future` or `T`, then expanding expands the `FutureOr<T>` to
`Future<T>|T`.

```
FutureOr<int> - int     expands to:  Future<int>|int - int = Future<int>
FutureOr<int> - Future  expands to:  Future<int>|int - Future = int
```

### Subtraction

OK, that's enough preliminaries. Here's the algorithm. To subtract two object
spaces `L - R`:

1.  If `L`'s type is sealed and `R`'s type is in its sealed subtype hierarchy,
    then expand `L` to the union of subtypes and start the whole subtraction
    process over. (That will then distribute the `- R` into all of the resulting
    arms, process each subtype independently, and union the result.)

2.  Else, if `R`'s type is not a supertype of `L`'s type (even after expanding)
    then it can't meaningfully subtract anything. The result is just `L`. This
    comes into play when when matching on unsealed subtypes:

    ```dart
    class Animal {}
    class Mammal extends Animal {}

    test(Animal a) {
      switch (a) {
        case Mammal m: ...
      }
    }
    ```

    After we match `Mammal`, we're not any closer to being exhaustive since
    there could still be values of any unknown subtype of `Animal`, or even
    direct instances of `Animal` itself.

3.  Else, if `L` and `R` have any corresponding fields whose *space
    intersection* is empty, then the result is `L`. Space intersection, defined
    below, determines the set of values two spaces have in common. If the
    intersection of the field spaces for a pair of fields is empty, it means
    that any value in `L` has a field whose value can't possibly be matched by
    `R` Therefore, subtracting `R` won't remove any actual values from `L` and
    the result is just `L`.

    For example:

    ```
    Card(suit: heart) - Card(suit: club) = Card(suit: heart)
    ```

    Here, we're subtracting all clubs from a set of cards that are all hearts.
    This doesn't change anything.

4.  Else if `L` is a subspace of `R` then the result is empty. `L` is a
    subspace of `R` if every value in `L` is also in `R`. When that's true,
    subtracting `R` obviously removes every value from `L` leaving nothing.

    Subspace is simple to calculate. We already know that `L`'s type is a
    subtype of `R` from earlier checks. `L` is a subspace if subtracting each
    field in `R` from its corresponding field in `L` yields empty. For example:

    ```
    Jack(suit: heart, oneEyed: true) - Face(suit: Suit, oneEyed: bool)
    ```

    Here, `heart - Suit` is empty, as is `true - bool`, so `L` is a subspace.

5.  Else, subtract the field sets, below.

### Field set subtraction

We're finally at a point where have two objects `L` and `R` whose types allow
them to be subtracted in such a way that their fields come into play. We also
know there's no early out where the result is just `L` or empty.

1.  Subtract each field in `R` from its corresponding field in `L`. We define
    `fixed` to be the set of fields where that subtraction didn't change the
    field and `changed` to be the fields where it did. To calculate these sets,
    for each field in `L` or `R`:

    1.  Let `Lf` be the field in `L` and `Rf` be the field in `R` (either of
        which may be inferred if not present).

    2.  Calculate `D = Lf - Rf`.

    3.  If `D` is empty then `Lf` is already more a precise constraint on `L`'s
        values than `Rf` so `R` doesn't affect this field. Add `Lf` to `fixed`.

    4.  Else, add `D` to `changed`. (If `D` is "top", we can simply discard it.
        There's no need to keep a field that matches every value.)

2.  Now we know which fields are affected by the subtraction and which aren't.
    If `changed` is empty, then no fields come into play and the result is
    simply `L`.

3.  Otherwise, the result is a union of objects where each object includes one
    of the changed fields and leaves the others alone. This is how we tile over
    the holes created by subtracting `R`.

    1.  For each field in `changed`, create an object with the same type as `L`
        with all fields from `fixed`, this field from `changed` and all other
        field names in `changed` set to their original space in `L`.

    2.  The result is the union of those spaces.

    For example:

    ```
    (w: bool, x: bool, y: bool, z: bool) - (x: true, y: false, z: true)`
    ```

    `fixed` is `(w: bool)`. `changed` is `(x: false, y: true, z: false)`. The
    result is a union of:

    ```
    (x: false, y: bool, z: bool) // Set x to D.
    (x: bool, y: true, z: bool) // Set y to D.
    (x: bool, y: bool, z: false) // Set z to D.
    ```

## Space intersection

Intersection is (mercifully) simpler than subtraction. In fact, we don't even
need to calculate the actual intersection. We just need to know if it's empty
or not.

To calculate if the intersection `I` of spaces `L` and `R` is empty:

1.  If `L` or `R` is empty, then `I` is empty.

2.  If `L` or `R` is a union, then `I` is empty if the intersection of every
    arm of the union with the other operand is empty.

3.  Otherwise, we're intersecting two object spaces.

    1.  If neither object's type is a subtype of the other then `I` is empty.
        They are unrelated types with no (known) intersection.

    2.  Otherwise, go through the fields. If the intersection of any
        corresponding pair of fields is empty, then `I` is empty.

    3.  Otherwise, `I` is not empty. We found two objects where one is a
        subtype of the other and the fields (if any) have at least some overlap.

## Conclusion

The basic summary is:

1.  We take the language's notion of static types and patterns and lift them to
    a simpler but more expressive model of spaces.

2.  We define space subtraction and intersection.

3.  Using that, we can define exhaustiveness and reachability as a simple series
    of subtractions over the spaces for a switch's value type and case patterns.

The [prototype][] has a number of tests that try to cover all of the interesting
cases, though there are so many ways that object spaces can vary and compose
that it's hard to be sure everything is tested.

## Next steps

I haven't proven that the algorithm is correct. I also haven't proven any bounds
on its performance. A fairly large test covering every combination of four
fields seems to be snappy (and certainly was not with earlier versions of this
algorithm).

There are a couple of missing pieces that need to be done:

### Generics

The patterns proposal supports type arguments and even [type patterns][] on
objects:

[type patterns]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md#type-argument-binder

```dart
switch (obj) {
  case List<int> list: ...
  case Map<final K, final V> map: ...
}
```

Object spaces currently only support simple types and subtypes. We'll need to
extend that to handle generics, variance, and bounds. We might be able to model
type arguments sort of like additional fields.

### Constants

The algorithm here currently doesn't do anything smart for constants except for
Booleans and enums. It should probably treat identical constants of other types
as identical spaces so that redundant unreachable cases can be detected. That
should be a straightforward change.

We may also want to handle integers specially including supporting ranges. This
is particularly helpful for lists.

### List length

We lift list element accesses to named fields in object spaces. We can also
model the list length as a named field of type `int`. But without smarter
handling for integers that won't handle cases like:

```dart
switch (list) {
  case [var a, var b]: ...
  case [var a, var b]: ...
}
```

The algorithm currently won't detect that the second space is unreachable. We
will probably want to support `...` in list patterns to allow matching on lists
of unknown length where the length is at least above some minimum, as in:

```dart
switch (list) {
  case [var a, ..., var b]: ...
  case [var a, var b]: ...
}
```

In that case, to do smart exhaustiveness checks, we probably want the algorithm
to understand integer ranges. Most other languages do this, so it should be
tractable.

### Shared subtypes of sealed types

The expand type procedure assumes that any type is a direct subtype of at most
*one* sealed supertype. (It can have other supertypes but only one *sealed*
one.) It assumes that the language forbids a class hierarchy like:

```
   (A)
   / \
 (B) (C)
 / \ / \
D   E   F
```

Here, `A`, `B`, and `C` are sealed supertypes. The subtypes of `A` are `B` and
`C`. The subtypes of `B` are `D` and `E`. The subtypes of `C` are `E` and `F`.
So `E` is a direct subtype of both `B` and `C`.

If expanding supported class hierarchies like this correctly then given a switch
like this:

```dart
A a = ...
switch (a) {
  case B b: ...
  case F f: ...
}
```

It would be able to detect that the cases are indeed exhaustive.

It's probably reasonable to restrict the language in this way and leave expand
as it is. But if we want to loosen this restriction, it should be possible to
make expanding smart enough to handle this.

### Type promotion

Exhaustiveness checking is a flow-like analysis similar to type promotion in
Dart. This document does not directly connect them. I believe we can handle them
separately.

Type promotion can safely assume any switch is exhaustive and promote
accordingly. If that turns out to not be a case, a compile error will be
reported anyway, so promotion doesn't matter.


## Changelog

### 1.1

-   Specify that constants are treated as subtypes based on identity. This way,
    we can get reachability errors on duplicate constant cases.

-   Specify how null-check, null-assert, cast, and declaration matcher patterns
    are lifted.

-   Handle nullable and `FutureOr` types in expand type.
