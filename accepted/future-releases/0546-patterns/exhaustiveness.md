# Exhaustiveness Checking

Author: Bob Nystrom

Status: In progress

Version 2.0 (see [CHANGELOG](#CHANGELOG) at end)

## Summary

This document proposes a static analysis algorithm for exhaustiveness checking
of [switch statements and expressions][switch] as part of the proposed support
for [pattern matching][patterns]. It also tries to provide an intuition for how
the algorithm works.

[switch]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/0546-patterns/feature-specification.md#switch-statement
[patterns]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/0546-patterns/feature-specification.md

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
    also already be matched by one of the preceding two cases. This is not a
    concern for soundness or correctness, but is dead code that an
    implementation may want to warn on.

Dart already supports exhaustiveness and reachability warnings in switch
statements on `bool` and enum types. This document extends that to handle
destructuring patterns and [algebraic datatype-style][adt] code.

[adt]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/0546-patterns/feature-specification.md#algebraic-datatypes

The approach is based on the paper ["Warnings for pattern matching"][maranget]
(PDF) by Luc Maranget, modified to handle subtyping, named field destructuring,
and arbitrarily deep sealed class hierarchies. It was then elaborated much
further by Johnni Winther. It also takes inspiration from ["A Generic Algorithm
for Checking Exhaustivity of Pattern Matching"][space paper] by [Fengyun Liu][].

[maranget]: http://moscova.inria.fr/~maranget/papers/warn/warn.pdf
[space paper]: https://infoscience.epfl.ch/record/225497?ln=en
[Fengyun Liu]: https://fengy.me/

There is a [prototype implementation][prototype] of the algorithm with detailed
comments and tests.

[prototype]: https://github.com/dart-lang/language/tree/master/accepted/future-releases/0546-patterns/exhaustiveness_prototype

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

Instead, we [extend the language to let a user explicitly "seal"][sealed] a
supertype with a specified closed set of subtypes. No code outside of the
library where the sealed type is declared is allowed to define a new subtype of
the sealed supertype (using `extends`, `implements`, `with`, or `on`). The
supertype is also implicitly made abstract.

[sealed]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/sealed-types/feature-specification.md

Here is an example:

```dart
enum Suit { club, diamond, heart, spade }

sealed class Card {
  final Suit suit;

  Card(this.suit);
}

class Pip extends Card {
  final int pips;

  Pip(this.pips, super.suit);
}

sealed class Face extends Card {
  Face(super.suit);
}

class Jack extends Face {
  final bool oneEyed;

  Jack(super.suit, {this.oneEyed = false});
}

class Queen extends Face {
  Queen(super.suit);
}

class King extends Face {
  King(super.suit);
}
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
    extension or implementation. In the example here, anyone can extend or
    implement, say, `Pip` or `Queen`. This doesn't cause any problems. And in
    fact, we use this to turn `Face` into a sealed supertype of its own set of
    subtypes.

*   The subtypes do not have to be disjoint. Another library that wanted to
    depose the royalty could define a `Democracy` class that implements `Jack`,
    `Queen`, and `King` and takes over their functionality. This doesn't cause
    any problems for exhaustiveness even though it means that a single instance
    of `Democracy` would match more than one of the sealed subtypes of `Card`
    and `Face`.

*   The subtypes can have other supertypes in addition to the sealed one. We
    could have a `Monarch` interface that `Queen` and `King` implement.

All that matters is that any object that is an instance of the supertype must
also be an instance of one of the known set of subtypes. That gives us the
critical invariant that if we have matched against all instances of those
subtypes, then we have exhaustively covered all instances of the supertype.

## Spaces

Determining whether a switch is exhaustive requires reasoning about some notion
of a "set of values". A series of cases is exhaustive if the set of all possible
values entering the switch is covered by the sets of values matched by the case
patterns.

Thus the algorithm needs a way to model a (potentially infinite) set of values.
In a statically typed language, the first obvious answer is a static type. A
type does represent a set of values. But a plain static type isn't precise
enough for things like the set of values matched by the pattern `DateTime(day:
1)` which matches not just all values of some type, but only ones whose fields
have certain values.

A pattern is the natural way to describe a set of values of some type filtered
by some arbitrary set of predicates on their propertiesl, and we will use
somethig similar here. However, the patterns proposal defines a rich set of
patterns to make the feature user friendly and expressive. It would require
unnecessary complexity in the exhaustiveness algorithm to handle every single
kind of pattern.

Instead, following Liu's paper, we use a data structure called a *space*. Spaces
are essentially a simpler unified abstration over patterns and static types.

A single space has a *type*, a *restriction*, and zero or more *properties*. All
of these are used to determine which values match the space and which don't. The
type filters values by type. The restriction is used for more precise matching
constraints like constants and list lengths. Properties destructure from the
matched value and use further subspaces to constrain the result.

Zero or more spaces are collected into a *space union*. A space union matches
all of the values that any of its constituent spaces match. The *empty space
union* with no spaces matches no values. Multiple space unions can be unioned
together yielding a union containing all of their respective spaces.

Informally, where a space union is expected, a single space means a union
containing just that space. If a space isn't specified to have any properties,
it implicitly has none.

## Types and restrictions

Every space has a static type that defines the type of values it can match. In
addition, a space may have a restriction that further filters out values.

There are a couple of kinds of restrictions:

*   An *open restriction*, the default, matches all values.

*   A *constant restriction* matches only values that are identical to a given
    constant value. It's used for enum values, `true`, and `false`.

*   An *arity restriction* tracks the arity of which lists and maps the space
    for a list or map pattern may match. It has a `length`, which the specifies
    the minimum number of elements the collection must have. It also has a
    `hasRest` flag. If `true`, then the collection may have more than *length*
    elements and still match. If `false`, then the collection must have exactly
    *length* elements to match.

    *If exhaustiveness checking supported integer ranges more generally, then
    arity restrictions could be modeled in terms of that.*

## Properties

A space may contain one or more properties. Each property has a *key* used to
destructure a piece of data from the matched object and then matches the result
against a corresponding *subspace* (actually a space union). This is similar to
how subpatterns in object, list, and other patterns extract data and match
against it.

We call them "properties" here because they are more general than just
named getter accessors. There are a few kinds of keys:

*   A *getter key* accesses a named member on the object. This may invoke a
    getter, tear off a method, invoke an extension member, or tear off an
    extension.

*   A *field key* accesses a record field. This is essentially the same as a
    getter key since record objects also expose getters for their fields.

*   An *element key* accesses a list element with the given constant integer
    index or a map value with the given constant key by calling the `[]` on the
    matched object.

*   A *rest key* accesses a range of rest elements on a list. It has two
    constants: the number of `head` elements that precede the rest, and the
    number of `tail` elements after it. It destructures by calling
    `sublist(head, length - tail)` on the matched list.

*   A *tail key* accesses a list element with the given constant integer index
    `i` from the *end* of the list by calling `list[length - i]` on the matched
    list.

Every key has a corresponding static type that can be looked up given the
type of the space it is being accessed on:

*   For a getter or field key, the type is the type of the corresponding member
    or record field.

*   For an element or tail key, the type is the return type of the corresponding
    `[]` operator declared on the space's type.

*   For a rest key, the type is the same as the type of the space. That will
    always be `List<T>` for some `T`.

## Lifting types and patterns to space unions

The exhaustiveness algorithm works on spaces and space unions, but it is invoked
given the static type of the matched value and the patterns for each switch
case. The first step is "lifting" that type and those patterns into the space
representation.

*   **Static type:** The space union representing a static type `T` is a single
    space with type `T`, open restriction, and no properties.

Lifting a pattern to a space union happens in the context of a *matched value
type* which is determined during type checking and is known for each pattern.
The lifted space union for a pattern with matched value type `M` is:

*   **Logical-or pattern:** A union of the lifted spaces of the two branches.

*   **Logical-and pattern:** The intersection (defined below) of the lifted
    space unions of the two branches.

*   **Relational pattern:** The empty space union. *Relational patterns don't
    reliably match any values, so don't help with exhaustiveness.*

*   **Cast pattern:** *A cast pattern matches if the value is of the casted type
    and the inner pattern matches it. But a cast pattern also "handles" a value
    when the cast _fails_. From the perspective of exhaustiveness checking, what
    matters it that execution can't flow out of a switch without matching at
    least one case. But if a pattern _throws_ a runtime exception, then
    execution also doesn't flow out of it. So we treat throwing as essentially
    another kind of matching for exhaustiveness.*

    *In practice, this normally isn't very helpful. Consider:*

    ```dart
    test(Object obj) => switch (obj) {
      int(isEven: true) as int => 1,
      int _ => 2
    };
    ```

    *Here, the first case will throw on any value that isn't an `int` and the
    second case will match on any value that is, so it is exhaustive. But the
    exhaustiveness algorithm doesn't model "all objects that are not `int`", so
    it can't tell that this is exhaustive.*

    *But with sealed types, exhaustiveness can sometimes represent the set of
    remaining types. Given:*

    ```dart
    sealed class A {
      final int field;
    }
    class B extends A {}
    class C extends A {}
    class D extends A {}

    test(A a) => switch (a) {
      C(field: 0) as C => 0,
      C _ => 1
    };
    ```

    *After the first case, we know that if `a` is a `B` or `D` then we will have
    thrown an exception. But if `a` is a `C`, it may not have matched if the
    field isn't `0`. So the space for the first case is a union of `B|C(field:
    0)|D'.*

    *Then the second case covers the rest of `C` and this is exhaustive.*

    Formally, the space union `spaces` for a cast pattern with cast type `C` is
    a union of:

    1.  The lifted space union of the cast's subpattern in context `C`.

    2.  For each space `E` in the *expanded spaces* (see below) of `M`:

        1.  If `E` is not a *subset* (see below) of `C` and `C` is not a subset
            of `M`, then the lifted space union of `E`.

*   **Null-check pattern:**

    1.  Let `S` be the expanded spaces of the lifted space union of the
        subpattern.

    2.  Remove any unions in `S` that have type `Null`. *A null-check pattern
        specifically does not match `null`, so even if the subpattern would
        handle it, it will never see it.*

    3.  The result is `S`.

    *A null-check pattern also modifies the matched value type of the subpattern
    during type inference. This means that the subpattern usually has a
    non-nullable type already, so step 2 above rarely comes into play. For
    example:*

    ```dart
    test(Object? obj) => switch (obj) {
      case _?:
      case null:
    };
    ```

    *Here, the inferred type of the inner `_` pattern is `Object` and thus its
    lifted space is also `Object`. But if the inner pattern happens to be
    nullable, then step 2 can be involved:*

    ```dart
    test(Object? obj) => switch (obj) {
      case Object? _?:
    };
    ```

    *Here, the subspace expands to `Object|Null` and the space for the
    surrounding null-check pattern yields just `Object`.*

*   **Null-assert pattern:** A union of the lifted space union of the subpattern
    and a space with type `Null`.

    *As with cast patterns, a null-assert pattern "matches" `null` by throwing
    an exception, which is sufficient for exhaustiveness.*

*   **Constant pattern:**

    1.  If the constant has primitive equality, then a space whose type is the
        type of the constant and with a constant restriction for the given
        constant value.

    2.  Else the empty space union.

    *If the constant has a user-defined `==` method, then we can't rely on its
    behavior for exhaustiveness checking. Fortunately, the constants that most
    often come into play for exhaustiveness are enum values, booleans, and
    `null`, and those all have primitive equality.*

*   **Variable pattern** or **identifier pattern:** The lifted space union of
    the static type of the corresponding variable.

*   **Parenthesized pattern:** The lifted space union of the subpattern.

*   **List pattern:**

    1.  Let `h` be the elements in the list pattern before the rest element, or
        all elements if there is no rest element.

    2.  Let `t` be the elements in the list pattern after the rest element, or
        an empty list of patterns if there is no rest element.

    3.  The result is a space whose type is the type of the pattern and with an
        arity restriction whose length is `h + t` and whose `hasRest` is `true`
        if there is a rest element. The space's properties are:

    4.  For each element in `h`:

        1.  A property with element key `n` where `n` is the element index and
            whose subspace is the lifted space union of the corresponding
            element subpattern.

    5.  If there is a rest element, a property with a rest key `h.length` and
        `t.length` and whose subspace is the lifted space union of the rest
        element's subpattern. If the rest element has no subpattern, the
        subspace is a space whose type is the static type of the list pattern.

    6.  For each element in `t`:

        1.  A property with tail key `n` where `n` is the 1-based index of the
            element from the end of the list pattern, and whose subspace is the
            lifted space union of the corresponding element subpattern.

    *For example, the list pattern:*

    ```
    <String>['a', 'b', ...['c'], 'd', 'e', 'f']
    ```

    *Is lifted to:*

    ```
    List<String>(
      length: 5,
      hasRest: true,
      properties: {
        key(0): 'a',
        key(1): 'b',
        rest(2, 3): List<String>(key(0): 'c'),
        tail(3): 'd',
        tail(2): 'e',
        tail(1): 'f',
      }
    )
    ```

*   **Map pattern:**

    1.  A space whose type is the type of the pattern and with an arity
        restriction whose length is the number of non-rest elements and whose
        `hasRest` is `true` if there is a rest element. The space's properties
        are:

    2.  For each non-rest entry in the pattern:

        1.  A property with element key `k` where `k` is the entry's key
            constant whose subspace is the lifted space union of the
            corresponding value subpattern.

*   **Record pattern** or **object pattern:**

    1.  A space whose type is the type of the pattern. Its properties are:

    2.  For each field in the pattern:

        3.  A property whose key is the corresponding field or getter and
            whose value is the lifted space union of the corresponding
            subpattern.

### Space intersection

Space intersection on a pair of spaces and/or space unions produces a space or
union that contains only values contained by both of its operands.

Intersection is approximate and pessimistic: There may be values that are
matched by both operands that are not matched by the resulting intersection.
Since intersection is only invoked when lifting patterns to spaces (and not
value types), it is sound, though it may lead to the compiler not recognizing
that a switch is actually exhaustive when it is or not recognizing a case as
unreachable when it can't be reached.

Space intersection is defined as:

1.  If either is the empty space union, then the empty space union.

2.  Else, if either side is a union, then a space union of the intersection of
    each operand of the union with the other space.

    *In other words, distribute the intersection into the branches. So `(A|B) ^
    C` (where `|` is "union" and `^` is "intersection") results in `(A^C)|(B^C)`
    and then calculate the resulting intersections.*

3.  Else (both sides are single unions):

    1.  If neither side's type is a subtype of the other, then the result is the
        empty space union.

    2.  Else let `T` be the subtype.

    3.  If neither side's restriction is a *subset* (see below) of the other,
        then the result is the empty space union.

    4.  Else let `R` be the restriction that is a subset of the other.

    5.  Calculate the intersection of the sets of properties `P`. The
        intersection is a set of properties containing:

        1.  For any property whose key is present in one operand and not the
            other, a property with that key and the value from that operand.

        2.  Otherwise (the property key is present in both), a property with
            that key and whose value is the intersection of the corresponding
            spaces of the two property values.

        *In other words, keep all properties of both branches, and intersect the
        spaces of any that overlap.*

    6.  The result is a space with type `T`, restriction `R`, and properties
        `P`.

### Restriction subsetting

Similar to how a pair of type may have a subtype relation between them, one
restriction may be a *subset* of another. If one restriction is a subset of
another, then every value matched by the former will also be matched by the
latter.

Whether a restriction `a` is a subset of restriction `b` is defined as:

1.  If `b` is an open restriction, then `true`. *Everything is a subset of the
    open restriction.*

2.  Else if `a` is an open restriction, then `false`. *If we get here, `b`
    isn't open, so `a` is a superset.*

3.  Else if both are constant restrictions and the constants are identical then
    `true`.

4.  Else if both are arity restrictions:

    1.  If `b.hasRest` then `true` if `a.size >= b.size`. *Since `b` has no
        upper limit, as long as its minimum length isn't shorter than `a`'s, it
        will accept any length that `a` does.

    2.  Else if `a.hasRest` then `false`. *Since `a` has no upper limit and `b`
        does, there are lengths that `a` accepts that `b` does not.*

    3.  Else the result of `a.length == b.length`. *If we get here, neither has
        a rest element, so both only match a single length. To be a non-empty
        subset, `a` must match the exact same length as `b`.

5.  Else `false`. *We get here for non-equal constants, or when one has a
    constant restriction and the other an arity restriction.*

### Space subsetting

We extend restriction subsetting to include the type of the spaces. Whether a
space `a` is a subset of space `b` is defined as:

1.  If the type of `a` is not a subtype of `b` then `false`.

2.  Else `true` if the restriction of `a` is a subset of the restriction of `b`
    and `false` otherwise.

## Calculating exhaustiveness

We can now lift the matched value type and the switch case patterns into spaces
and space unions where our algorithm can operate on them. To determine
exhaustiveness and reachability from those, we need only one fundamental
operation, *is-exhaustive*.

It takes a space union `value` representing the set of possible values and a set
of space unions `cases` representing a set of patterns that will match those
values. It returns `true` if every possible value contained by `value` is
matched by at least one space in `cases`.

Given that operation, we can answer the two exhaustiveness questions like so:

### Is a switch exhaustive?

To tell if the set of cases in a switch statement or expression are exhaustive
over the matched value type:

1.  Lift the matched value type to a space union `value`.

2.  Discard any cases that have guards. *Since static analysis can't tell when a
    guard might evaluate to `false`, any case with a guard doesn't reliably
    match values and so can't help prove exhaustiveness.*

3.  Lift the remaining case patterns to a set of space unions `cases`.

4.  The switch is exhaustive if is-exhaustive with `value` and `cases` is `true`
    and `false` otherwise.

### Are any switch cases unreachable?

1.  For each case (including cases with guards) except the first:

    1.  Collect all of the of the patterns from the cases preceding `case`
        (except ones with guards), and lift them to space unions as `preceding`.

    2.  Lift the pattern for the current case to `case`.

    3.  This case's pattern is reachable if is-exhaustive with `case` and
        `preceding` returns `false`, and is unreachable otherwise.

*The clever part here is that our space representation works equally well for
types and patterns, so we can use the same algorithm to check if a switch's
value type is covered and to see if a case's pattern is reachable by treating
the latter pattern like a sort of "value". The algorithm doesn't care if the
`value` space union came from a type or a pattern. It just treats it like a set
of values.*

### The is-exhaustive operation

The core operation determines if a set of case space unions covers all possible
values allowed by a given value space union.

Internally, is-exhaustive doesn't take a single space union for the matched
values and a list of space unions for the cases. Instead, it takes a *worklist*
of space unions for the matched values, and a list of worklists of space unions
for the cases. These worklists are how the algorithm incrementally traverses
through the nested properties of the value and case spaces in parallel. When
first invoked externally, the arguments are implicitly wrapped in single-element
worklists.

We define is-exhaustive, given a `value` worklist of space unions and a `cases`
list of worklists of space unions like so:

1.  If `value` is empty then return `true` if `cases` is not empty and `false`
    otherwise.

    *This is the base case. If we get here, we've fully applied all of the
    constraints specified by the value space to winnow down the cases that
    might match it. If there are still any cases left, it means at least one
    of those will definitely match.*

2.  Else, look at all of the element and tail keys that appear in any property
    in any of the spaces in the first unions of the `cases` worklists:

    1.  Let `headMax` be the `1` + the highest index of any element key found.
        *This is the maximum number of leading elements destructured by any list
        pattern corresponding a case that could match it.*

    2.  Let `tailMax` be the highest index of any tail key found.

    *In order to expand list patterns for more precise exhaustiveness checking,
    we need to know the longest arity list pattern that can be matched against
    the current value space we're looking at. See the rules for expanding a
    list space below for more detail.*

3.  For each case worklist in `cases`:

    1.  Dequeue the first space union from the worklist.

    2.  Take every space in the union and *expand* it (see below) into a list of
        expanded spaces for each union branch. Pass in `headMax` and `tailMax`.

    3.  For each `space` in that list:

        1.  *Filter* by `space` (see below), passing in a copy of the `value`
            (which has had its first element dequeued) and a deep copy of
            `cases`.

            *We copy here since the specification describes updating the
            worklist in terms of mutation but sibling recursive calls shouldn't
            affect each other. Consider the specification-ese to be a
            pass-by-value language.*

        2.  If the result is `false`, then we've found an unmatched value, so
            stop and return `false`.

            *The algorithm stops at the first failure for performance.*

4.  Return `true`.

    *If we get here, then we recursed through the entire tree of possible values
    and all of them found a matching case, so the cases are exhaustive.*

### Expanding a space

Consider:

```dart
test(Card card) => switch (card) {
  Pip _ => 'pip',
  Face _ => 'face'
};
```

It's hard to see how we might easily tell that this switch is exhaustive. After
the algorithm has looked at the first `Pip _` case, what does it know about the
set of values that have been covered? More to the point, how does it know what's
*left*? If we supported set operations on spaces, we could say that the
remaining values are the `Card` space minus the `Pip` space. But we don't want
to have to define that.

However, we can observe that because `Card` is sealed, we know that any instance
of `Card` will be an instance of one of its direct sealed subtypes. That means
that if this pair of switch statements is exhaustive, then the above switch must
be too:

```dart
test(Pip pip) => switch (pip) {
  Pip _ => 'pip',
  Face _ => 'face'
};

test(Face face) => switch (face) {
  Pip _ => 'pip',
  Face _ => 'face'
};
```

Note that each switch is only matching one of the sealed subtypes now. It's now
trivial to see that the first switch is exhaustive because every matched value
will be an instance of `Pip` and the first case covers every single instance of
`Pip`. (The second case is unreachable and pointless, but harmless.) Likewise,
the second switch is clearly exhaustive because every value is a `Face` and the
second case matches all instances of `Face`.

In the algorithm, when it looks at a space, it first *expands* it. If the type
of a space is a sealed type, enum type, or `bool` (which is basically an enum
type), then it replaces the space with a set of more precise spaces that cover
the original space. Then it processes those each independently. If the cases are
all exhaustive over every one of the expanded spaces, then they are exhaustive
over the original unexpanded space too.

To expand a space `s` with type `T`, we create a new set of spaces that share
the same properties as `s` but with possibly different types and restrictions.
The resulting spaces are:

*   **The declaration `D` of `T` is a `sealed` type:**

    1.  For each declaration `C` in the library of `D` that has `D` in an
        `implements`, `extends`, or `with` clause:

        1.  If every type parameter in `C` forwards to a corresponding type
            parameter in `D`, then `C` is a *trivial substitution* for `D`.
            Let `S` be `C` instantiated with the type arguments of `T`.

            *For example:*

            ```dart
            sealed class A<T1, T2> {}
            class B<R1, R2> extends A<R1, R2> {}
            ```

        2.  Else (not a trivial substitution) let `S` be an overapproximation
            (see below) of `C`.

            **TODO:** Is the overapproximation part here correct?

        3.  If `S` exists and is a subtype of the overapproximation of `T`:

            1.  A space with type `S`.

            *Type `S` might not be a subtype if it constrains its supertype in
            a way that is incompatible with the specific instantiation of the
            sealed super type that we're matching against. For example:*

            ```dart
            sealed class A<T> {}
            class B<T> extends A<T> {}
            class C extends A<int> {}
            ```

            *Here, if we are matching on `A<String>`, then `B<String>` is a
            subtype, but `C` is not and won't be included. That means that this
            is exhaustive:*

            ```dart
            test(A<String> a) => switch (a) {
              B _ => 'B'
            };
            ```

    *Note that in the common case where the sealed type hierarchy is not
    generic, all of this simplifies to just being a list of spaces, one for each
    type that is a direct subtype of the sealed type.*

*   **`T` is an enum type:**

    1.  For each element in the enum:

        1.  If the element's type is a subtype of the overapproximation of the
            enum declaration:

            1.  A space with the type of the element and a constant restriction
                with the element value.

    *We have to check the type because with a generic enum, some elements might
    not be subtypes of the matched type. Consider:*

    ```dart
    enum E<T> {
      a<int>(),
      b<String>(),
      c<double>(),
    }

    method(E<num> e) {
      switch (e) {
        case E.a:
        case E.c:
          print('ok');
      }
    }
    ```

    *This switch is exhaustive because it's not possible for `E.b` to reach it.*

    *We use overapproximation because the enum may refer to type parameters in
    the surrounding code:*

    ```dart
    method<T extends num>(E<T> e) {
      switch (e) {
        case E.a:
        case E.c:
          print('ok');
      }
    }
    ```

    *This is also exhaustive. When `method()` is instantiated with `int`, then
    the second case will never match. Conversely, the first case will never
    match in a call to `method<double>()`. But exhaustiveness must be sound
    across all instantiations, so it uses overapproximation.*

*   **`T` is nullable type `S?`:** A space of type `S` and a space of type
    `Null`.

*   **`T` is `FutureOr<F>` for some `F`**: A space of type `Future<F>` and a
    space of type `F`.

*   **`T` is `bool`:** Two spaces of type `bool` with constant restrictions
    `true` and `false`.

*   **`T` is `List<E>` for some `E` and has an arity restriction:**

    *The "has an arity restriction" is to ensure the space was lifted from a
    list pattern, and not just a list constant. List constants do not help with
    exhaustiveness because reified type arguments mean that a list constant may
    fail to match a list that contains the same elements.*

    1.  Let `n` be `headMax + tailMax`. *The challenge with list patterns is
        that we could expand them to an unbounded number of spaces: empty list,
        list with one element, list with two elements, etc. Here, `n` represents
        the highest individual arity we need to expand to because there is no
        pattern that will match a list with a specific number of elements larger
        than that.*

    2.  For `i` from `0` to `n`, half-inclusive:

        1.  A space with type `T` and an arity restriction with length `i` and
            `hasRest` `false`.

    3.  And a space with type `T` and an arity restriction with length `n` and
        `hasRest` `true`.

    *For example, given:*

    ```dart
    switch (list) {
      case [_, ..., _, _]:
      case [_, _, _, ..., _]:
    }
    ```

    *The expansion of the value list is:*

    ```
    List(length: 0, hasRest: false)
    List(length: 1, hasRest: false)
    List(length: 2, hasRest: false)
    List(length: 3, hasRest: false)
    List(length: 4, hasRest: false)
    List(length: 5, hasRest: true)
    ```

*   Otherwise, `s` does not expand and the result is just `s`.

The expansion procedure is applied recursively to each resulting space described
here until no more expansions take place.

*For example, the expansion of `FutureOr<bool?>` is:*

```
Future<bool?>
true
false
null
```

### Overapproximation

The *overapproximation* of a declaration `D` is a type `T` with all type
variables replaced with their *defaults*:

1.  If the type variable is in a contravariant position, then the default is
    `Never`.

2.  Otherwise, the default is the bound if there is one.

3.  Otherwise, the default is `Object?`.

The overapproximation of a declaration reliably contains all values that any
possible instantiation of its type parameters could contain. This lets us
calculate exhaustiveness soundly even in the context of parameter types whose
concrete instantiations aren't known.

### Filtering by a space

We're given a single `valueSpace`, a `value` worklist for further value
constraints to explore, and a set of `cases` worklists that may match `space`.
Next, we discard any cases that won't be helpful for exhaustiveness given what
we know now. If it's *possible* for any `value` in value to *not* match the
first space in a given worklist in cases, then that case can't guarantee
exhaustiveness, so we remove it.

1.  Let `remaining` be an empty list of worklists.

2.  Let `caseFirstSpaces` be an empty list of spaces.

3.  For each `worklist` in `cases`:

    1.  Dequeue the first case union in `worklist` to `caseUnion`.

    2.  For each `case` space in `caseUnion`:

        1.  If `valueSpace` is a subset of `case`, then:

            1.  Add `case` to `caseFirstSpaces`.

            2.  Add `worklist` to `remaining`.

            *If every value in `valueSpace` is also in `case`, then this case
            may still help with exhaustiveness, so keep it.*

    *At this point, we have discarded any case that may not match because of the
    first space in its worklist. But those spaces may have properties which
    could also lead the case to not match, so we need to unpack and handle those
    too.*

4.  Let `keys` be the set of all keys in all of the properties of the spaces in
    `caseFirstSpaces` and in `valueSpace`.

    *We need to ensure that the value space we're currently looking at
    corresponds to the case spaces at the beginning of each case worklist. We're
    about to unpack the case spaces in the worklist and replace them with their
    properties. To keep all of the worklists aligned, we collect all of the keys
    that any of the spaces use. When we unpack a space's properties, we insert
    placeholder spaces for any space that the unpacked space doesn't have a
    property for.*

5.  Prepend `value` with the *unpacked properties* (see below) of `valueSpace`
    given `keys`. *We unpack the first value space so we can recurse into its
    properties. We've already dequeued `valueSpace` from `value`, so we don't
    need to do that here.*

6.  Iterate over `caseFirstSpaces` and `remaining` in parallel as `space` and
    `case`:

    1.  Prepend the unpacked properties of `space` to `case` given `keys`.

7.  Return the result of is-exhaustive on `value` and `remaining`.

    *Now that we've removed any cases that might not match based on the current
    space we're looking at, we can proceed forward along the worklists.*

### Unpacking properties

A key challenge with exhaustiveness checking is that patterns are arbitrarily
deeply nested trees. At the same time, we need to consider a set of cases in
parallel to see if they cover a value. And those cases may have patterns with
different sets of properties and different amounts of nested subpatterns.

To handle that, the algorithm does an incremental depth-first traversal of the
value and case spaces in parallel. After applying any filtering from a space's
type and restriction, we can discard the space itself, but we need to recurse
into its properties too.

We do that here. Unpacking a space's properties prepends them to the worklist so
that the depth-first traversal will explore into them. We use `keys` and pad the
worklist with match-all spaces in order to keep all of the worklists aligned.

To unpack a `space` given a set of `keys`:

1.  Let `result` be an empty list of space unions.

2.  For each key in `keys`:

    1.  If `space` has a property with this key, then append that property's
        subspace union to `result`.

    2.  Else, append a `space` to `result` whose type is the static type of the
        key declared on the type of `space`.

        *If a pattern doesn't have a subpattern for some field or getter, then
        it matches all values that the field or getter could return, which is
        equivalent to it matching it with its type.*

3.  Return `result`.

## Conclusion

The basic summary is:

1.  We lift static types and patterns to a unified concept called a *space* (and
    a union of those).

2.  We define a core operation that determines if a set of spaces covers all
    values allowed by another space.

3.  Using that, we define exhaustiveness and reachability as an invocation of
    that operation with the right lifted types and patterns.

## Changelog

### 2.0

-   Rewrite based on new algorithm and existing implementation.

### 1.1

-   Specify that constants are treated as subtypes based on identity. This way,
    we can get reachability errors on duplicate constant cases.

-   Specify how null-check, null-assert, cast, and declaration matcher patterns
    are lifted.

-   Handle nullable and `FutureOr` types in expand type.
