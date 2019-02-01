# Unified Collections

The Dart team is concurrently working on three proposals that affect collection
literals:

* [Set Literals][]
* [Spread Collections][]
* [Control Flow Collections][]

[set literals]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/set-literals/feature-specification.md
[spread collections]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/spread-collections/feature-specification.md
[control flow collections]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/control-flow-collections/feature-specification.md

These features interact in several ways, some of which weren't obvious at first.
To make things easier on implementers and anyone else trying to understand the
entire set of changes, this specification unifies and subsumes all three of
those proposals.

**This document is now the source of truth for these language changes.** The
other three proposals are useful because they contain motivation and other
context, but the precise syntax and semantics may be out of date in those docs.
This is where you should be looking if you're an implementer.

## Grammar

Remove `setLiteral` and `mapLiteral` entirely. Then change the grammar to:

```
setOrMapLiteral   : 'const'? typeArguments? '{' elements? '}' ;
listLiteral       : const? typeArguments? '[' elements? ']' ;

elements          : element ( ',' element )* ','? ;

element           : expressionElement
                  | mapEntry
                  | spreadElement
                  | ifElement
                  | forElement
                  ;

expressionElement : expression ;
mapEntry          : expression ':' expression ;

spreadElement     : ( '...' | '...?' ) expression ;
ifElement         : 'if' '(' expression ')' element ( 'else' element )? ;
forElement        : 'await'? 'for' '(' forLoopParts ')' element ;
```

It is a compile-time error if a `listLiteral` contains any `mapEntry` elements,
directly or within any of its `ifElement`s or `forElement`s, transitively. *(We
could avoid this prose by duplicating the above rules for lists and removing
`mapEntry`, but this is simpler.)*

The existing rule that an expression statement cannot start with `{` now covers
both map and set literals.

## Static Semantics

### Disambiguating sets and maps

Because sets and maps both use curly braces as delimiters, you can create
collection literals that are not obviously either a set or a map, like:

```dart
var a = {};
var b = {...other};
```

When possible, we use syntax to disambiguate between a map and set. Failing
that, we rely on types and inference.

#### Syntactic and context-driven disambiguation

Let `e` be a `setOrMapLiteral`.

Let `leafElements` be all of the `expressionElement` and `mapEntry` elements in
`e`, including elements inside `ifElement` or `forElement` elements,
transitively.

1.  If `e` has `typeArguments` then:

    *   If there is exactly one type argument `T`, then it is syntactically
        known to be a set literal with static type `Set<T>`.

    *   If there are exactly two type arguments `K` and `V`, then it is
        syntactically known to be a map literal with static type `Map<K, V>`.

    *   Otherwise (three or more type arguments) it is a compile-time error.

2.  Else, if `e` has a context `C`, and the base type of `C` is `Cbase` (that
    is, `Cbase` is `C` with all wrapping `FutureOr`s removed), and `Cbase` is
    not `?`, and `S` is the greatest closure of `Cbase` then:

    *   If `S` is a subtype of `Iterable<Object>` and `S` is not a subtype of
        `Map<Object, Object>`, then `e` is syntactically known to be a set
        literal.

    *   If `S` is a subtype of `Map<Object, Object>` and `S` is not a subtype of
        `Iterable<Object>` then `e` is syntactically known to be a map literal.

4.  If `leafElements` is not empty, then:

    *   It is a compile-time error if `e` is syntactically known to be a map
        literal and `leafElements` contains any `expressionElement` elements.

    *   It is a compile-time error if `e` is syntactically known to be a set
        literal and `leafElements` contains any `mapEntry` elements.

    *   If it has at least one `expressionElement` and no `mapEntry` elements,
        it is syntactically known to be a set literal, with unknown static type.

    *   If it has at least one `mapEntry` and no `expressionElement` elements,
        it is syntactically known to be a map literal with unknown static type.

    *   If it has at least one `mapEntry` and at least one `expressionElement`,
        it is an error.

    *In other words, at least one key-value pair anywhere in the collection
    forces it to be a map, and a bare expression forces it to be a set. Having
    both is an error.*

If `e` has no `typeArguments` and no context type, and no `elements`, then `e`
is treated as a map literal with unknown static type. *In other words, an empty
`{}` is a map unless we have a context that indicates otherwise.*

There are now three states we could be in:

*   `e` is syntactically known to be a set literal.

*   `e` is syntactically known to be a map literal.

*   `e` is not syntactically known to be a set or map literal, has an empty
    `leafElements`, but has at least one `element`. This implies that the body
    of the collection contains only `spreadElement`s, and contains at least one.

    At this point all syntax- and context-driven resolution is done. The next
    step is to perform type inference, as defined below. The last step of type
    inference does the final resolution of the ambiguous third case above.

### Type inference (and inference-based disambiguation)

#### Maps and sets

Inference and set/map disambiguation are done concurrently. We perform inference
on the literal, and collect up either a set element type (indicating that the
literal may/must be a set), or a pair of a key type and a value type (indicating
that the literal may/must be a map), or both. We allow both, because spreads of
expressions of type `dynamic` do not disambiguate, and can be treated as either
(it becomes a runtime error to spread the wrong kind of thing into the wrong
kind of literal).

We require that at least one component unambiguously determine the literal form,
otherwise it is an error. So, given:

```dart
bool b = true;
dynamic x = <int, int>{};
Iterable l = [];
Map m = {};
```

Then:

```dart
{...x} // An error, because it is ambiguous.
{...x, ...l} // Statically resolved to a set, runtime error on the spread.
{...x, ...m} // Statically resolved to a map, no runtime error.
{...l, ...m} // Static error, because it must be both a set and a map.
```

The algorithm can be modified to catch this error eagerly by tracking four
result states for element inference:

*   `MapElement<K, V>` – The element constrains the literal to a map with key
    type `K` and element type `V`.

*   `SetElement<T>` – The element constrains the literal to a set with element
    type `T`.

*   `DynamicElement` – The element does not constrain the literal to a set or
    map, but constrains the element/key/value type to `dynamic`.

*   `ErrorElement` – The element is erroneous.

Alternatively, error checking for invalid spreads can be done separately.

In `setOrMapLiteral`, the inferred type of an `element` is a set element type
`T`, a pair of a key type `K` and a value type `V`, or both. It is computed
relative to a context type `P`:

*   If `element` is an `expressionElement` with expression `e1`:

    *   If `P` is `?` then the inferred set element type of `element` is the
        inferred type of the expression `e1` in context `?`.

    *   If `P` is `Set<Ps>` then the inferred set element type of `element` is
        the inferred type of the expression `e1` in context `Ps`.

        **TODO: what if `P` is `Iterable<R>`? Is this allowed?:**

        ```dart
        Iterable<int> = {123 as dynamic}; // Infers Set<int>?
        ```

*   If `element` is a `mapEntry` `ek: ev`:

    *   If `P` is `?` then the inferred key type of `element` is the inferred
        type of `ek` in context `?` and the inferred value type of `element` is
        the inferred type of `ev` in context `?`.

    *   If `P` is `Map<Pk, Pv>` then the inferred key type of `element` is the
        inferred type of `ek` in context `Pk` and the inferred value type of `element`
        is the inferred type of `ev` in context `Pv`.

*   If `element` is a `spreadElement` with expression `e1`:

    *   If `P` is `?` then let `S` be the inferred type of `e1` in context `?`:

        *   If `S` is a subtype of `Iterable<Object>` and not a subtype of
            `Map<Object, Object>`, then the inferred set element type of
            `element` is `T` where `T` is the type such that `Iterable<T>` is a
            superinterface of `S` (the result of constraint matching for `X`
            using the constraint `S <: Iterable<X>`).

        *   If `S` is a subtype of `Map<Object, Object>` and not a subtype of
            `Iterable<Object>`, then the inferred key type of `element` is `K`
            and the inferred value type of `element` is `V`, where `K` and `V`
            are the types such that `Map<K, V>` is a superinterface of `S` (the
            result of constraint matching for `X` and `Y` using the constraint
            `S <: Map<X, Y>`).

        *   If `S` is `dynamic`, then the inferred set element type of `element`
            is `dynamic`, the inferred key type of `element` is `dynamic`, and
            the inferred value type of `element` is `dynamic`. *(We produce both
            a set element type here, and a key/value pair here and rely on other
            elements to disambiguate.)*

        *   Otherwise it is an error (either because we cannot disambiguate,
            such as with something that implements both Map and Iterable, or
            because it is a spread of a non-spreadable type).

    *   If `P` is `Set<Ps>` then let `S` be the inferred type of `e1` in context
        `Iterable<Ps>`:

        *   If `S` is a non-`Null` subtype of `Iterable<Object>`, then the
            inferred set element type of `element` is `T` where `T` is the type
            such that `Iterable<T>` is a superinterface of `S` (the result of
            constraint matching for `X` using the constraint `Iterable<X> <:
            S`).

        *   If `S` is `dynamic`, then the inferred set element type of `element`
            is `dynamic`.

        *   Otherwise it is an error.

    *   If `P` is `Map<Pk, Pv>` then let `S` be the inferred type of `e1` in
        context `P`:

        *   If `S` is a non-`Null` subtype of `Map<Object, Object>`, then the
            inferred key type of `element` is `K` and the inferred value type of
            `element` is `V`, where `K` and `V` are the types such that `Map<K,
            V>` is a superinterface of `S` (the result of constraint matching
            for `X` and `Y` using the constraint `Map<X, Y> <: S`).

        *   If `S` is `dynamic`, then the inferred key type of `element` is
            `dynamic`, and the inferred value type of `element` is `dynamic`.

        *   Otherwise it is an error.

*   If `element` is a `ifElement` with one `element`, `p1`, and no `else`:

    The condition is inferred with a context type of `bool`.

    *   If the inferred set element type of `p1` is `S` then the inferred set
        element type of `element` is `S`.

    *   If the inferred key type of `p1` is `K` and the inferred value type of
        `p1` is `V` then the inferred key and value types of `element` are `K`
        and `V`.

    *Note that both of the above cases can simultaneously apply because of
    `dynamic` spreads.*

*   If `element` is an `ifElement` with two `element`s, `p1` and `p2`:

    The condition is inferred with a context type of `bool`.

    It is a compile error if `p1` has an inferred set element type and `p2` does
    not, or if `p2` has an inferred set element type and `p1` does not. *In
    other words, you can't spread a map on one branch and a set on the other.
    Since `dynamic` provides both set and map key/value types, a `dynamic` in
    either branch does not run into this case.*

    *   If the inferred set element type of `p1` is `S1` and the inferred set
        element type of `p2` is `S2` then the inferred set element type of
        `element` is the upper bound of `S1` and `S2`.

    *   If the inferred key type of `p1` is `K1` and the inferred key type of
        `p1` is `V1` and the inferred key type of `p2` is `K2` and the inferred
        key type of `p2` is `V2` then the inferred key type of `element` is the
        upper bound of `K1` and `K2` and the inferred value type is the upper
        bound of `V1` and `V2`.

    *Note that both of the above cases can simultaneously apply because of
    `dynamic` spreads.*

*   If `element` is a `forElement` with `element` `p1` then:

    Inference for the iterated expression and the controlling variable is done
    as for the corresponding `for` or `await for` statement.

    *   If the inferred set element type of `p1` is `S` then the inferred set
        element type of `element` is `S`.

    *   If the inferred key type of `p1` is `K` and the inferred key type of
        `p1` is `V` then the inferred key and value types of `element` are `K`
        and `V`.

    *In other words, inference flows upwards from the body element. Note that
    both of the above cases can validly apply because of `dynamic` spreads.*

Finally, we define inference on a `setOrMapLiteral` `collection` as follows:

*   If `collection` is a set literal, then the downwards context for inference
    of the elements of `collection` is `Set<P>` where `P` may be `?` if
    downwards inference does not constrain the type of `collection`.

    *   If `P` is `?` then the static type of `collection` is `Set<T>` where `T`
        is the upper bound of the inferred set element types of the elements.

    *   Otherwise, the static type of `collection` is `Set<T>` where `T` is
        determined by downwards inference.

    *Note that the element inference will never produce a key/value type here
    given that downwards context.*

*   If `collection` is a map literal and downwards inference has statically
    known type `Map<K, V>` then the downwards context for the elements of
    `collection` is `Map<K, V>`.

*   If `collection` is a map literal then the downwards context for the elements
    of `collection` is `Map<Pk, Pv>` where `Pk` and `Pv` are determined by
    downwards inference, and may be `?` if the downwards context does not
    constrain one or both.

    *   If `Pk` is `?` then the static key type of `collection` is `K` where `K`
        is the upper bound of the inferred key types of the elements.

    *   Otherwise the static key type of `collection` is `K` where `K` is
        determined by downwards inference.

    And:

    *   If `Pv` is `?` then the static value type of `collection` is `V` where
        `V` is the upper bound of the inferred value types of the elements.

    *   Otherwise the static value type of `collection` is `V` where `V` is
        determined by downwards inference.

    *Note that the element inference will never produce a set element type here
    given this downwards context.*

*   If `collection` is not syntactically known to be a set or map literal, then
    the downwards context for the elements of `collection` is `?`, and the disambiguation
    is done as follows:

    *   If all elements `ei` have a set element type `Ti`, and at least one
        element does not have a key/value type pair, then `collection` is a set
        literal with static type `Set<T>` where `T` is the upper bound of `Ti`.
        *In other words, if every element can be a set and at least one must, it
        is a set.*

    *   If all elements `ei` have key element type `Ki`, and value element type
        `Vi` , and at least one element does not have a set element type, then
        `e` is a map literal with static type `Map<K, V>` where `K` is the upper
        bound of `Ki` and `V` is the upper bound of `Vi`. *In other words, if
        every element can be a map and at least one must, it is a map.*

    *   If all elements have both a set element type and a key/value type pair,
        then the literal is ambiguous and it is a compile-time error. *This
        occurs when all the leaf elements are dynamic spreads.*

    *   Otherwise, there is at least one element which has only a set element
        type, and one element which has only a key/value type, then it is a
        compile-time error since the literal is constrained to be both a map and
        a set.

#### Lists

Inference for list literals mostly follows that of set literals without the
complexity around disambiguation with maps and using `List` or `Iterable` in a
few places instead of `Set`.

Inside a `listLiteral`, the inferred type of an `element` is a list element type
`T`. It is computed relative to a context type `P`:

*   If `element` is an `expressionElement` with expression `e1`:

    *   If `P` is `?` then the inferred list element type of `element` is the
        inferred type of the expression `e1` in context `?`.

    *   If `P` is `Iterable<Ps>` then the inferred list element type of
        `element` is the inferred type of the expression `e1` in context `Ps`.

*   If `element` is a `spreadElement` with expression `e1`:

    *   If `P` is `?` then let `S` be the inferred type of `e1` in context `?`:

        *   If `S` is a subtype of `Iterable<Object>`, then the inferred list
            element type of `element` is `T` where `T` is the type such that
            `Iterable<T>` is a superinterface of `S` (the result of constraint
            matching for `X` using the constraint `S <: Iterable<X>`).

        *   If `S` is `dynamic`, then the inferred list element type of
            `element` is `dynamic`.

        *   Otherwise it is an error (because it is a spread of a non-spreadable
            type like Object).

    *   If `P` is `Iterable<Ps>` then let `S` be the inferred type of `e1` in
        context `Iterable<Ps>`:

        *   If `S` is a non-`Null` subtype of `Iterable<Object>`, then the
            inferred list element type of `element` is `T` where `T` is the type
            such that `Iterable<T>` is a superinterface of `S` (the result of
            constraint matching for `X` using the constraint `Iterable<X> <:
            S`).

        *   If `S` is `dynamic`, then the inferred list element type of
            `element` is `dynamic`.

        *   Otherwise it is an error.

*   If `element` is an `ifElement` with one `element`, `p1`, and no `else`:

    The condition is inferred with a context type of `bool`.

    The inferred list element type of `element` is the inferred list element
    type of `p1`.

*   If `element` is a `ifElement` with two `element`s, `p1` and `p2`:

    The condition is inferred with a context type of `bool`.

    The inferred list element type of `element` is the upper bound of `S1` and
    `S2` where `S1` is the inferred list element type of `p1` and `S2` is the
    inferred list element type of `p2`.

*   If `element` is a `forElement` with `element` `p1` then:

    Inference for the iterated expression and the controlling variable is done
    as for the corresponding `for` or `await for` statement.

    The inferred list element type of `element` is the inferred list element
    type of `p1`.

*Note: `element` cannot be a `mapEntry` since the syntax prohibits that.*

Finally, we define inference on a `listLiteral` `collection` as follows:

*   The downwards context for inference of the elements of `collection` is
    `Iterable<P>` where `P` may be `?` if downwards inference does not constrain
    the type of `collection`.

    *   If `P` is `?` then the static type of `collection` is `List<T>` where
        `T` is the upper bound of the inferred list element types of the
        elements.

    *   Otherwise, the static type of `collection` is `List<T>` where `T` is
        determined by downwards inference.

### Compile-time errors

After type inference and disambiguation, the collection is checked for other
compile-time errors. It is a compile-time error if:

*   The collection is a list and the type of any of the `leafElements` may not
    be assigned to the list's element type.

    ```dart
    <int>[if (true) "not int"] // Error.
    ```

*   The collection is a map and the key type of any of the `leafElements` may
    not be assigned to the map's key type.

    ```dart
    <int, int>{if (true) "not int": 1} // Error.
    ```

*   The collection is a map and the value type of any of the `leafElements` may
    not be assigned to the map's value type.

    ```dart
    <int, int>{if (true) 1: "not int"} // Error.
    ```

*   A spread element in a list or set literal has a static type that is not
    `dynamic` or a subtype of `Iterable<Object>`.

*   A spread element in a list or set has a static type that implements
    `Iterable<T>` for some `T` and `T` is not assignable to the element type of
    the list.

*   A spread element in a map literal has a static type that is not `dynamic` or
    a subtype of `Map<Object, Object>`.

*   If a map spread element's static type implements `Map<K, V>` for some `K`
    and `V` and `K` is not assignable to the key type of the map or `V` is not
    assignable to the value type of the map.

*   The type of the condition expression in an `if` element may not be assigned
    to `bool`.

    ```dart
    [if ("not bool") 1] // Error.
    ```

*   The type of the iterator expression in a synchronous `for-in` element may
    not be assigned to `Iterable<T>` for some type `T`. Otherwise, the *iterable
    type* of the iterator is `T`.

    ```dart
    [for (var i in "not iterable") i] // Error.
    ```

*   The iterable type of the iterator in a synchronous `for-in` element may not
    be assigned to the `for-in` variable's type.

    ```dart
    [for (int i in ["not", "int"]) i] // Error.
    ```

*   The type of the stream expression in an asynchronous `await for-in`
    element may not be assigned to `Stream<T>` for some type `T`. Otherwise,
    the *stream type* of the stream is `T`.

    ```dart
    [await for (var i in "not stream") i] // Error.
    ```

*   The stream type of the iterator in an asynchronous `await for-in` element
    may not be assigned to the `for-in` variable's type.

    ```dart
    [await for (int i in Stream.fromIterable(["not", "int"])) i] // Error.
    ```

*   `await for` is used when the function immediately enclosing the collection
    literal is not asynchronous.

    ```dart
    main() {
      [await for (_ in stream)]; // Error.
    }
    ```

*   `await` is used before a C-style `for` element. `await` can only be used
    with `for-in` loops.

    ```dart
    main() {
      [await for (;;)]; // Error.
    }
    ```

*   The type of the condition expression (the second clause) in a C-style `for`
    element may not be assigned to `bool`.

    ```dart
    [for (; "not bool";) 1] // Error.
    ```

## Constant Semantics

The runtime semantics below can also be used to determine the compile-time value
of a collection literal marked `const`, with a few modifications:

*   A `listLiteral` is constant if it occurs in a constant context or if it is
    directly prefixed by `const`. If so, then its `elements` must all be
    constant elements, or at least potentially constant elements.

*   A `setOrMapLiteral` is constant if it occurs in a constant context or if it
    is directly prefixed by `const`. If so, then its `elements` must all be
    constant elements, or at least potentially constant elements.

*   An `expressionElement` is a constant element if its expression is a constant
    expression, and a potentially constant element if it's expression is a
    potentially constant expression.

*   A `mapEntry` is a constant element if both its key and value expression are
    constant expressions, and a potentially constant element if both are
    potentially constant expressions.

*   A `spreadElement` is a constant element if its expression is constant and it
    evaluates to a constant `List`, `Set` or `Map` instance originally created
    by a list, set or map literal. It is a potentially constant element if the
    expression is potentially constant expression.

*   An `ifElement` is constant if its condition is a constant expression
    evaluating to a Boolean value and either:

    *   If the condition evaluates to `true`, the then element is a constant
        expression, and any else element is a potentially constant element.

    *   If the condition evaluates to `false`, then the then element is a
        potentially constant element and any else element is a constant element.

*   A `forElement` is never a constant element. `for` cannot be used in constant
    set or map literals.

*   It is a compile-time error to have duplicate values in a set literal or
    duplicate keys in a map literal, according to behavior specified in the
    runtime semantics.

*   When evaluating a const collection literal, if there is an existing const
    list, map, or set literal that contains the same series of values or entries
    in the same order, then that object is used instead of producing a new one.
    *In other words, constants are canonicalized.* Note that maps are only
    canonicalized if they contain the same keys *in the same order*.

### Constant equality safe

A value is constant equality safe iff:

*   It is an instance of a class that does not override `Object.operator==`, or

*   it is an instance of `int` or `String`, or

*   it is an instance of `Symbol` originally created by a symbol literal or a
    constant invocation of the `Symbol` constructor, or

*   it is an instance of `Type` originally created by evaluating a type literal
    expression (an identifier or qualified identifier denoting a class, mixin or
    type alias declaration, that is evaluated as an expression).

All constant equality safe values are also valid constant values.

## Dynamic Semantics

Spread, `if`, and `for` behave similarly across all collection types. To
simplify the spec, there is a single procedure used for all kinds of
collections. This recursive procedure builds up either a `result` sequence of
either values or key-value pair map entries. Then a final step handles those
appropropriately for the given collection type.

### To evaluate a collection `element`:

1.  If `element` is an expression element:

    1.  Evaluate the element's expression and append it to `result`.

1.  Else, `element` is a `mapEntry` `keyExpression: valueExpression`:

    1.  Evaluate `keyExpression` to a value `key`.

    1.  Evaluate `valueExpression` to a value `value`.

    1.  Append `key: value` to `result`.

1.  Else, if `element` is a spread element:

    1.  Evaluate the spread expression to a value `spread`.

    1.  If `entry` is null-aware and `spread` is null, continue to the next
        element in the literal.

    1.  If the collection is a map, evaluate `spread.entries.iterator` to a
        value `iterator`. Otherwise, evaluate `spread.iterator` to `iterator`.
        *This will deliberately throw an exception if `spread` is `null` and
        `element` is not null-aware.*

    1.  Loop:

        1.  If `iterator.moveNext()` returns `false`, exit the loop.

        1.  Evaluate `iterator.current` and append it to `result`. *This will be
            a MapEntry in a map literal, or any object for a list or set
            literal.*

1.  Else, if `element` is an `if` element:

    1.  Evaluate the condition expression to a value `condition`.

    1.  If the boolean conversion of `condition` is `true`:

        1.  Evaluate the "then" element using this procedure.

    1.  Else, if there is an "else" element of the `if`:

        1.  Evaluate the "else" element using this procedure.

1.  Else, if `element` is a synchronous `for-in` element:

    1.  Evaluate the iterator expression to a value `sequence`.

    1.  Evaluate `sequence.iterator` to a value `iterator`.

    1.  Loop:

        1.  If the boolean conversion of `iterator.moveNext()` does not return
            `true`, exit the loop.

        1.  If the `for-in` element declares a variable, create a new namespace
            and a fresh `variable` for it. Otherwise, use the existing
            `variable` it refers to.

        1.  Evaluate `iterator.current` and bind it to `variable`.

        1.  Evaluate the body element using this procedure in the scope of
            `variable`.

        1.  If the `for-in` element declares a variable, discard the namespace
            created for it.

1.  Else, if `element` is an asynchronous `await for-in` element:

    1.  Evaluate the stream expression to a value `stream`. It is a dynamic
        error if `stream` is not an instance of a class that implements
        `Stream`.

    1.  Create a new `Future`, `streamDone`.

    1.  Evaluate `await streamDone`.

    1.  Listen to `stream`. On each data event `event` the stream sends:

        1.  If the `for-in` element declares a variable, create a new namespace
            and a fresh `variable` for it. Otherwise, use the existing
            `variable` it refers to.

        1.  Bind `event` to `variable`.

        1.  Evaluate the body element using this procedure in the scope of
            `variable`. If this raises an exception, complete `streamDone` with
            it as an error.

        1.  If the `for-in` element declares a variable, discard the namespace
            created for it.

    1.  If `stream` raises an exception, complete `streamDone` with it as an
        error. Otherwise, when all events in the stream are processed, complete
        `streamDone` with `null`.

1.  Else, `element` is a C-style `for` element:

    1.  Evaluate the initializer clause of the element, if there is one.

    1.  Loop:

        1.  If the initializer clause declares a variable, create a new
            namespace and bind that variable in that namespace.

        1.  Evaluate the condition expression to a value `condition`. If there
            is no condition expression, use `true`.

        1.  If the boolean conversion of `condition` is not `true`, exit the
            loop.

        1.  Evaluate the body element using this procedure in the namespace of
            the variable declared by the initializer clause if there is one.

        1.  If there is an increment clause, execute it.

        1.  If the initializer clause declares a variable, discard the namespace
            created for it.

The procedure theoretically supports a mixture of expressions and map entries,
but the static semantics prohibit an actual literal containing that. Once the
`result` series of values or entries is produced from the tree of elements:

### Lists

1.  The result of the literal expression is a fresh instance of a class that
    implements `List<E>` containing the values in `result`, in order.

### Sets

1.  Create a fresh instance `set` of a class that implements `Set<E>`.

1.  For each `value` in `result`:

    1.  If `set` contains any value `existing` that is equal to `value`
        according to `existing`'s `==` operator, do nothing.

    1.  Otherwise, add `value` to `set`.

1.  The result of the literal expression is `set`.

### Maps

1.  Allocate a fresh instance `map` of a class that implements `LinkedHashMap<K,
    V>`.

1.  For each `entry` in `result`:

    1.  If `map` contains any key `key` that is equal to the key of `entry`
        according to `key`'s `==` operator, do nothing.

    1.  Otherwise, insert `entry` into `map`.

1.  The result of the map literal expression is `map`.
