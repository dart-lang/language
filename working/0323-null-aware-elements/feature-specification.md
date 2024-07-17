# Null-aware elements

Author: Bob Nystrom

Status: In-progress

Version 0.2 (see [CHANGELOG](#CHANGELOG) at end)

Experiment flag: null-aware-elements

## Introduction

In Dart 2.3, we added [several new syntax features][unified] for use inside
collection literals. You can use `...` to spread the contents of one collection
into another, and `if` and `for` to perform branching and looping control flow
while generating elements.

[unified]: https://github.com/dart-lang/language/blob/main/accepted/2.3/unified-collections/feature-specification.md

We even added a `...?` null-aware spread operator so that you can include the
contents of another collection when the other collection is potentially `null`.
Shortly after shipping, [Andrew Lorenzen pointed out][323] that we missed the
simpler case: What if you have a *single value* that you only want to include
in the resulting collection if it's not `null`?

[323]: https://github.com/dart-lang/language/issues/323

You can use an `if` element, like so:

```dart
[
  if (nullableValue != null) nullableValue
];
```

That works as long as the value is in some local variable or parameter that can
be promoted to a non-nullable type by an if check. Otherwise, you're forced to
also use a null-assertion (`!`):

```dart
[
  if (nullable.value != null) nullable.value!
];
```

That's brittle, and both of these are quite verbose. In Dart 3.0, we added
pattern matching and a new `if-case` element. Combining that with a null-check
pattern and a variable pattern lets you do:

```dart
[
  if (nullable.value case var value?) value
];
```

That avoids the null-assertion but is still verbose.

Really, you just want a simple way to say "Evaluate this expression and if the
result isn't `null`, include it in the collection." This is not a hugely
impactful feature, but it does feel like a *missing* one. It seems strange to
have null-aware spreads, but not null-aware single values.

This proposal remedies that by adding *null-aware elements*. Using Lorenzen's
suggested syntax, inside a collection literal, a `?` followed by an expression
includes the value if it's not `null` and discards the `null` otherwise:

```dart
void printThree(String? a, String? b, String? c) {
  print([?a, ?b, ?c].join(' '));
}

main() {
  printThree('first', null, 'last');
}
```

Under this proposal, the above program prints "first last".

### Null-aware map entries

Lorenzen's proposed syntax is very natural in list and set literals. But what
about null-aware *map entries?* Where would the `?` go? Is it even worth
supporting null-aware elements in maps?

I analyzed a large corpus of open source Dart code (17,941,439 lines in 90,019
files). I looked for the kind of code users write today that could be replaced
with uses of this feature. Specifically, I checked for these simple syntactic
patterns inside list, set, and map literals:

```
// Potential null-aware expression in list or set:
if (<some expr> != null) <some expr>
if (<some expr> != null) <some expr>!

// Potential null-aware key in map:
if (<some expr> != null) <some expr>: <other code>
if (<some expr> != null) <some expr>!: <other code>

// Potential null-aware value in map:
if (<some expr> != null) <other code>: <some expr>
if (<some expr> != null) <other code>: <some expr>!
```

It turns out that *most* of the potential uses of this feature occur inside map
literals:

```
-- Surrounding collection (1812 total) --
   1566 ( 86.424%): Map   ===============================================
    241 ( 13.300%): List  ========
      5 (  0.276%): Set   =
```

There definitely are uses inside lists (and a tiny number in sets), but maps
are where the real value is. Maps have two potential places where `null` could
occur, the key and value. Which ones tend to be checked for `null`?

```
-- Element kind (1812 total) --
   1564 ( 86.313%): Map value   ==========================================
    246 ( 13.576%): Expression  =======
      2 (  0.110%): Map key     =
```

It's almost always that if the map *value* is `null`, then the entire map entry
is omitted. We could support *only* null-aware map values without much loss of
usefulness.

I also tried to get a feel for how useful this feature is overall. Comparing
`if` elements inside collection literals that do match this pattern versus those
that don't:

```
-- If element (89956 total) --
  88151 ( 97.993%): Could not be null-aware element  ===========================
   1805 (  2.007%): Could be null-aware element      =
```

So, it looks like this wouldn't be as widely used as `if` inside collection
literals is. That's not entirely surprising since `if` is a more powerful
general-purpose feature.

It's also certainly the case that my simple analysis didn't catch many other
workarounds that users are using to deal with `null`. (I did look for uses of
`if-case`, `.whereNotNull()`, and `.nonNulls` that seemed like could become
null-aware elements but only found a handful.)

This suggests that if we're to support this feature at all, we should support
it for map entries too. The syntax options, assuming we want to stick with a
prefix `?` are to put it before the whole entry, or just before the value part:

```dart
// Before this proposal:
Map<String, dynamic> toJson() => {
  if (referenceId != null) "reference_id": referenceId,
  "type": type.name,
  "reusability": reusability.name,
  "country": country,
  if (customerId != null) "customer_id": customerId,
  if (customer != null) "customer": customer?.toJson(),
  "ewallet": ewallet.toJson(),
  if (description != null) "description": description,
  if (metadata != null) "metadata": metadata?.toJson(),
};

// Null-aware with `?` before entire entry:
Map<String, dynamic> toJson() => {
  ?"reference_id": referenceId,
  "type": type.name,
  "reusability": reusability.name,
  "country": country,
  ?"customer_id": customerId,
  ?"customer": customer?.toJson(),
  "ewallet": ewallet.toJson(),
  ?"description": description,
  ?"metadata": metadata?.toJson(),
};

// Null-aware with `?` before value expression:
Map<String, dynamic> toJson() => {
  "reference_id": ?referenceId,
  "type": type.name,
  "reusability": reusability.name,
  "country": country,
  "customer_id": ?customerId,
  "customer": ?customer?.toJson(),
  "ewallet": ewallet.toJson(),
  "description": ?description,
  "metadata": ?metadata?.toJson(),
};
```

Putting the `?` before the entry map entries makes it easier to see that some
control flow is happening when quickly scanning down the left side of a series
of map entries.

But to my eyes, it makes it look like the `?` applies to the map key, which is a
reasonable thing for a user to infer, and possibly even a *useful* thing. So I
propose that we allow both null-aware map keys and null-aware map values. Then
you put the `?` before the value, after the `:`, if you want to omit the entry
when the value is `null`.

### Examples

Here are a few real-world examples before and after this proposal:

```dart
// Before:
Stack(
  fit: StackFit.expand,
  children: [
    const AbsorbPointer(),
    if (widget.child != null) widget.child!,
  ],
)

// After:
Stack(
  fit: StackFit.expand,
  children: [
    const AbsorbPointer(),
    ?widget?.child,
  ],
)

// Before:
final tag = Tag()
  ..tags = {
    if (Song.title != null) 'title': Song.title,
    if (Song.artist != null) 'artist': Song.artist,
    if (Song.album != null) 'album': Song.album,
    if (Song.year != null) 'year': Song.year.toString(),
    if (comments != null)
      'comment': comms!
          .asMap()
          .map((key, value) => MapEntry<String, Comment>(value.key, value)),
    if (Song.numberInAlbum != null) 'track': Song.numberInAlbum.toString(),
    if (Song.genre != null) 'genre': Song.genre,
    if (Song.albumArt != null) 'picture': {pic.key: pic},
  }
  ..type = 'ID3'
  ..version = '2.4';

// After:
final tag = Tag()
  ..tags = {
    'title': ?Song.title,
    'artist': ?Song.artist,
    'album': ?Song.album,
    'year': ?Song.year?.toString(),
    if (comments != null)
      'comment': comms!
          .asMap()
          .map((key, value) => MapEntry<String, Comment>(value.key, value)),
    'track': Song.numberInAlbum?.toString(),
    'genre': Song.genre,
    if (Song.albumArt != null) 'picture': {pic.key: pic},
  }
  ..type = 'ID3'
  ..version = '2.4';

// Before:
final List<Widget> children = <Widget>[
  // ...
  // Draw all the components on top of the empty bar box.
  if (componentsTransition.bottomBackChevron != null) componentsTransition.bottomBackChevron!,
  if (componentsTransition.bottomBackLabel != null) componentsTransition.bottomBackLabel!,
  if (componentsTransition.bottomLeading != null) componentsTransition.bottomLeading!,
  if (componentsTransition.bottomMiddle != null) componentsTransition.bottomMiddle!,
  if (componentsTransition.bottomLargeTitle != null) componentsTransition.bottomLargeTitle!,
  if (componentsTransition.bottomTrailing != null) componentsTransition.bottomTrailing!,
];

// After:
final List<Widget> children = <Widget>[
  // ...
  // Draw all the components on top of the empty bar box.
  ?componentsTransition.bottomBackChevron,
  ?componentsTransition.bottomBackLabel,
  ?componentsTransition.bottomLeading,
  ?componentsTransition.bottomMiddle,
  ?componentsTransition.bottomLargeTitle,
  ?componentsTransition.bottomTrailing,
];
```

Note how the null-aware elements also let uses remove uses of null-assertion
operators in some places.

Also note how the leading `?` null-aware element syntax is often combined with a
`?.` null-aware method call inside the value expression. This is a useful pair
of features to combine: the `?.` lets you short-circuit an entire method chain
when the target is `null`, and then the resulting `null` is consumed by the
surrounding null-aware element and the entire entry is discarded.

But this does mean that you often see two `?` in close succession but meaning
two different things: null-aware element and null-aware method call. The
promixity but slightly different behavior is potentially confusing.

More formally, here is the proposal:

## Syntax

We add two new rules in the grammar and add two new clauses to `element`:

```
element ::=
  | nullAwareExpressionElement
  | nullAwareMapElement
  | // Existing productions...

nullAwareExpressionElement ::= '?' expression

nullAwareMapElement ::=
  | '?' expression ':' '?'? expression // Null-aware key or both.
  |     expression ':' '?' expression  // Null-aware value.
```

*Note that the productions after `?` in these new rules are `expression` and not
`element`. As with spread elements, null-aware elements can't nest and contain
other elements. These new elements immediately exit the element grammar and
bottom out in an expression. There's no `????foo` or `?if (c) nullableThing else
otherNullableThing`.*

*The `?` character is already overloaded in Dart for nullable types, conditional
expressions, null-aware operators, and null-check patterns. However, I don't
believe there is any ambiguity in this new syntax. The preceding token will
usually be `,`, `[`, `{`, or `:`, none of which can appear before `?` in any
form that uses that character. The `?` may also appear after `)` after the
header of an `if` or `for` element, or after `else`, but those are also not
ambiguous.*

## Static semantics

Here and below, we say a `nullAwareMapElement` "has a null-aware key" if the
`nullAwareMapElement` begins with `?` and "has a null-aware value" if there is a
`?` after the `:`.

### Leaf elements

The existing specification uses *leaf elements* as part of disambiguating map
and set literals. We extend the rules by saying the leaf elements of `element`
are:

*   Else, if element is an `nullAwareExpressionElement` or `nullAwareMapEntry`,
    then the *leaf element* is `element` itself.

*In other words, just like their non-null-aware forms, null-aware expressions
and map entries are leaf elements.*

When disambiguating map and set literals, we replace the existing "If *leaf
elements* is not empty" step with:

1.  Else, if *leaf elements* is not empty, then:

    *   If *leaf elements* has at least one `expressionElement` or
        `nullAwareExpressionElement` and no `mapEntry` or `nullAwareMapEntry`
        elements, then *e* is a set literal with unknown static type. The static
        type will be filled in by type inference, defined below.

    *   If *leaf elements* has at least one `mapEntry` or `nullAwareMapEntry`
        and no `expressionElement` or `nullAwareExpressionElement` elements,
        then *e* is a map literal with unknown static type. The static type will
        be filled in by type inference, defined below.

    *   If leaf elements has at least one `mapEntry` or `nullAwareMapEntry` and
        at least one `expressionElement` or `nullAwareExpressionElement`, report
        a compile-time error.

*In other words, for map/set disambiguation, null-aware elements behave exactly
like their non-null-aware siblings.*

### Type inference

Null-aware elements add some slight complexity to type inference of collection
literals in order to handle wrapping and unwrapping the nullability as types
flow in and out of the element.

#### Map or set element type inference

When type inference is flowing through a brace-delimited collection literal, it
is applied to each element. The [existing type inference behavior][type
inference] is mostly unchanged by this proposal. We add two new clauses to
handle null-aware elements:

[type inference]: https://github.com/dart-lang/language/blob/main/accepted/2.3/unified-collections/feature-specification.md#type-inference

To infer the type of `element` in context `P`:

*   If `element` is a `nullAwareExpressionElement` with expression `e1`:

    *   If `P` is `_` (the unknown context):

        *   Let `U` be the inferred type of the expression `e1` in context `_`.

    *   Else, `P` is `Set<Ps>`:

        *   Let `U` be the inferred type of the expression `e1` in context
            `Ps?`. *The expression has a nullable context type because it may
            safely evaluate to `null` even when the surrounding set doesn't
            allow that because the `?` will discard a `null` entry.*

    *   The inferred set element type is **NonNull**(`U`). *The value added to
        the set will never be `null`.*

*   If `element` is a `nullAwareMapElement` with entry `ek: ev`:

    *   If `P` is `_` then the inferred key and value types of `element` are:

        *   Let `Uk` be the inferred type of `ek` in context `_`.

        *   If `element` has a null-aware key then the inferred key element type
            is **NonNull**(`Uk`). *The entry added to the map will never have a
            `null` key.*

        *   Else the inferred key element type is `Uk`. *The whole element is
            null-aware, but the key part is not, so it is inferred as normal.*

        *   Let `Uv` be the inferred type of `ev` in context `_`.

        *   If `element` has a null-aware value then the inferred value element
            type is **NonNull**(`Uv`). *The entry added to the map will never
            have a `null` value.*

        *   Else the inferred value element type is `Uv`. *The whole element is
            null-aware, but the value part is not, so it is inferred as normal.*

    *   If `P` is `Map<Pk, Pv>` then the inferred key and value types of
        `element` are:

        *   If `element` has a null-aware key then:

            *   Let `Uk` be the inferred type of `ek` in context `Pk?`. *The key
                expression has a nullable context type because it may safely
                evaluate to `null` even when the surrounding map doesn't allow
                that because the `?` will discard a `null` entry.*

            *   The inferred key element type is **NonNull**(`Uk`). *The entry
                added to the map will never have a `null` key.*

        *   Else the inferred key element type is the inferred type of `ek` in
            context `Pk`. *The whole element is null-aware, but the key part is
            not, so it is inferred as normal.*

        *   If `element` has a null-aware value then:

            *   Let `Uv` be the inferred type of `ev` in context `Pv?`. *The
                value expression has a nullable context type because it may
                safely evaluate to `null` even when the surrounding map doesn't
                allow that because the `?` will discard a `null` entry.*

            *   The inferred value element type is **NonNull**(`Uv`). *The entry
                added to the map will never have a `null` value.*

        *   Else the inferred value element type is the inferred type of `ev` in
            context `Pv`. *The whole element is null-aware, but the value part
            is not, so it is inferred as normal.*

*In other words, if there is a downwards inference context type, we add
nullability when the context type flows into a null-aware element's inner
expression or map entry parts. Conversely, when doing upwards inference, we
strip off the nullabilty of the inner expression as it flows out of the
null-aware part because `null` won't propagate out.*

#### List element type inference

Likewise, with list literals, we add a clause to handle a null-aware expression.

To infer the type of `element` in context `P`:

*   If `element` is a `nullAwareExpressionElement` with expression `e1`:

    *   If `P` is `_`:

        *   Let `U` be the inferred type of the expression `e1` in context `_`.

    *   Else, `P` is `List<Ps>`:

        *   Let `U` be the inferred type of the expression `e1` in context
            `Ps?`. *The expression has a nullable context type because it may
            safely evaluate to `null` even when the surrounding set doesn't
            allow that because the `?` will discard a `null` entry.*

    *   The inferred list element type is **NonNull**(`U`). *The value added to
        the list will never be `null`.*

### Constants

A `nullAwareExpressionElement` or `nullAwareMapElement` is constant if its inner
expression or map entry is constant.

## Runtime semantics

The runtime semantics of collection literals [are
defined][unified-dynamic-element] in terms of recursively building up a *result*
sequence of values (list or set) or map entries (map). For each kind of
`element`, there is specification for how that element adds to the result. We
add two new cases to that procedure:

[unified-dynamic-element]: https://github.com/dart-lang/language/blob/main/accepted/2.3/unified-collections/feature-specification.md#to-evaluate-a-collection-element

*   If `element` is a `nullAwareExpressionElement` with expression `e`:

    *   Evaluate `e` to `v`.

    *   If `v` is not `null` then append it to *result*. *Else the `null` is
        discarded.*

*   Else, if `element` is a `nullAwareMapElement` with entry `k: v`:

    *   Evaluate `k` to a value `kv`.

    *   If `element` has a null-aware key and `kv` is `null`, then stop. Else
        continue...

    *   Evaluate `v` to a value `vv`.

    *   If `element` has a null-aware value and `vv` is `null`, then stop. Else
        continue...

    *   Append an entry `kv: vv` to *result*.

*Note that either or both parts of a null-aware map entry may be null-aware. We
always evaluate the key before the value and short-circuit if a null-aware key
is `null`. When the value is null-aware but the key is not (the most common case
by far), the key expression will always be evaluated.*

## Tooling

The best language features are designed holistically with the entire user
experience in mind, including tooling and diagnostics. This section is *not
normative*, but is merely suggestions and ideas for the implementation teams.
They may wish to implement all, some, or none of this, and will likely have
further ideas for additional warnings, lints, and quick fixes.

### Unnecessary null-aware elements

As we do for other null-aware expressions like `?.` and `...?`, compilers and
IDEs should probably warn if the inner expressions in null-aware elements are
not potentially nullable since in that case, the `?` has no meaningful effect.

A quick fix to address the warning by removing the `?` would be nice.

### Quick fixes to use null-aware elements

In the absence of null-aware elements, I have seen a few patterns that users
use instead:

```dart
// An if element to check for null:
[
  if (foo != null) foo,

  if (unpromotable.expression != null) unpromotable.expression!,
];

// An if-case element with a null-check pattern:
[
  if (foo case var notNullFoo?) notNullFoo,
];

// Insert the nulls and then filter:
[
  nullableFoo,
].whereNotNull();

[
  nullableFoo,
].nonNulls;
```

If any of these patterns can be reliably detected through static analysis, then
quick fixes could be added to automatically convert these to use null-aware
elements instead.

## Changelog

### 0.2

-   Use separate grammar rules for null-aware elements instead of allowing
    optional `?` inside `expressionElement` and `mapEntryElement`. This only
    affects the wording of the specification but not the behavior of the
    feature.

### 0.1

-   Initial draft.
