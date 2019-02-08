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

Let *leaf elements* be all of the `expressionElement` and `mapEntry` elements in
*e*, including elements of `ifElement` or `forElement` elements, transitively.

It is a compile-time error if any *leaf elements* of a `listLiteral` are
`mapEntry` elements. *(We could avoid this prose by duplicating the above rules
for lists and removing `mapEntry`, but this is simpler.)*

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

Let *e* be a `setOrMapLiteral`.

1.  If *e* has `typeArguments` then:

    *   If there is exactly one type argument `T`, then it is syntactically
        known to be a set literal with static type `Set<T>`.

    *   If there are exactly two type arguments `K` and `V`, then it is
        syntactically known to be a map literal with static type `Map<K, V>`.

    *   Otherwise (three or more type arguments) it is a compile-time error.

1.  Else, if *e* has a context `C`, and the base type of `C` is `Cbase` (that
    is, `Cbase` is `C` with all wrapping `FutureOr`s removed), and `Cbase` is
    not `?`, and `S` is the greatest closure of `Cbase` then:

    *   If `S` is a subtype of `Iterable<Object>` and `S` is not a subtype of
        `Map<Object, Object>`, then *e* is syntactically known to be a set
        literal.

    *   If `S` is a subtype of `Map<Object, Object>` and `S` is not a subtype of
        `Iterable<Object>` then *e* is syntactically known to be a map literal.

1.  If *e* is not syntactically known to be a map or set literal yet and *leaf
    elements* is not empty, then:

    *   It is a compile-time error if *e* is syntactically known to be a map
        literal and *leaf elements* contains any `expressionElement` elements.

    *   It is a compile-time error if *e* is syntactically known to be a set
        literal and *leaf elements* contains any `mapEntry` elements.

    *   If *leaf elements* has at least one `expressionElement` and no
        `mapEntry` elements, it is syntactically known to be a set literal, with
        unknown static type.

    *   If *leaf elements* has at least one `mapEntry` and no
        `expressionElement` elements, it is syntactically known to be a map
        literal with unknown static type.

    *   If *leaf elements* has at least one `mapEntry` and at least one
        `expressionElement`, it is a compile-time error.

    *In other words, at least one key-value pair anywhere in the collection
    forces it to be a map, and a bare expression forces it to be a set. Having
    both is an error.*

If *e* has no `typeArguments` and no context type, and no `elements`, then *e*
is treated as a map literal with unknown static type. *In other words, an empty
`{}` is a map unless we have a context that indicates otherwise.*

If we don't have a compile-time error, then there are now three states we could
be in:

*   *e* is syntactically known to be a set literal.

*   *e* is syntactically known to be a map literal.

*   *e* is not syntactically known to be a set or map literal, has an empty
    *leaf elements*, but has at least one `element`. This implies that the body
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
(it becomes a runtime error to spread a value into the wrong kind of literal).

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
{...x}       // Static error, because it is ambiguous.
{...x, ...l} // Statically a set, runtime error when spreading x.
{...x, ...m} // Statically a map, no runtime error.
{...l, ...m} // Static error, because it must be both a set and a map.
```

In `setOrMapLiteral`, the inferred type of an `element` is a set element type
`T`, a pair of a key type `K` and a value type `V`, or both. It is computed
relative to a context type `P`.

We say that an element *can be a set* if it has a set element type. Likewise, an
element *can be a map* if it has a key and value type. We say that an element
*must be a set* if it can be a set and has and no key type or value type. We say
that an element *must be a map* if can be a map but has no set element type.

To infer the type of `element`:

*   If `element` is an `expressionElement` with expression `e1`:

    *   If `P` is `?` then the inferred set element type of `element` is the
        inferred type of the expression `e1` in context `?`.

    *   If `P` is `Iterable<Ps>` then the inferred set element type of `element`
        is the inferred type of the expression `e1` in context `Ps`.

*   If `element` is a `mapEntry` `ek: ev`:

    *   If `P` is `?` then the inferred key type of `element` is the inferred
        type of `ek` in context `?` and the inferred value type of `element` is
        the inferred type of `ev` in context `?`.

    *   If `P` is `Map<Pk, Pv>` then the inferred key type of `element` is the
        inferred type of `ek` in context `Pk` and the inferred value type of
        `element` is the inferred type of `ev` in context `Pv`.

*   If `element` is a `spreadElement` with expression `e1`:

    *   If `P` is `?` then let `S` be the inferred type of `e1` in context `?`:

        *   If `S` is a non-`Null` subtype of `Iterable<Object>`, then the
            inferred set element type of `element` is `T` where `T` is the type
            such that `Iterable<T>` is a superinterface of `S` (the result of
            constraint matching for `X` using the constraint `S <:
            Iterable<X>`).

        *   If `S` is a non-`Null` subtype of `Map<Object, Object>`, then the
            inferred key type of `element` is `K` and the inferred value type of
            `element` is `V`, where `K` and `V` are the types such that `Map<K,
            V>` is a superinterface of `S` (the result of constraint matching
            for `X` and `Y` using the constraint `S <: Map<X, Y>`).

            *Note that both this and the previous case can match on the same
            element if `S` is a subtype of both `Iterable<Object>` and
            `Map<Object, Object>`. In that case, we rely on other elements to
            disambiguate.*

        *   If `S` is `dynamic`, then the inferred set element type of `element`
            is `dynamic`, the inferred key type of `element` is `dynamic`, and
            the inferred value type of `element` is `dynamic`. *(We produce both
            a set element type here, and a key/value pair here and rely on other
            elements to disambiguate.)*

        *   If `S` is `Null` and the spread operator is `...?` then the element
            has set element type `Null`, map key type `Null` and map value type
            `Null`.

        *   If none of these cases match, it is an error.

    *   If `P` is `Set<Ps>` then let `S` be the inferred type of `e1` in context
        `Set<Ps>`:

        *   If `S` is a non-`Null` subtype of `Iterable<Object>`, then the
            inferred set element type of `element` is `T` where `T` is the type
            such that `Iterable<T>` is a superinterface of `S` (the result of
            constraint matching for `X` using the constraint `Iterable<X> <:
            S`).

        *   If `S` is `dynamic`, then the inferred set element type of `element`
            is `dynamic`.

        *   If `S` is `Null` and the spread operator is `...?`, then the set
            element type is `Null`.

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

*   If `element` is an `ifElement` with one `element`, `p1`, and no "else"
    element:

    The condition is inferred with a context type of `bool`.

    *   If the inferred set element type of `p1` is `S` then the inferred set
        element type of `element` is `S`.

    *   If the inferred key type of `p1` is `K` and the inferred value type of
        `p1` is `V` then the inferred key and value types of `element` are `K`
        and `V`.

    *Note that both of the above cases can simultaneously apply because of
    `dynamic` spreads.*

*   If `element` is an `ifElement` with two `element`s, `e1` and `e2`:

    The condition is inferred with a context type of `bool`.

    It is a compile error if `e1` must be a set and `e2` must be a map or vice
    versa. *In other words, you can't spread a map on one branch and a set on
    the other. Since `dynamic` provides both set and map key/value types, a
    `dynamic` in either branch does not run into this case.*

    *   If the inferred set element type of `e1` is `S1` and the inferred set
        element type of `e2` is `S2` then the inferred set element type of
        `element` is the upper bound of `S1` and `S2`.

    *   If the inferred key type of `e1` is `K1` and the inferred key type of
        `e1` is `V1` and the inferred key type of `e2` is `K2` and the inferred
        key type of `e2` is `V2` then the inferred key type of `element` is the
        upper bound of `K1` and `K2` and the inferred value type is the upper
        bound of `V1` and `V2`.

    *Note that both of the above cases can simultaneously apply because of
    `dynamic` spreads.*

*   If `element` is a `forElement` with `element` `e1` then:

    Inference for the iterated expression and the controlling variable is done
    as for the corresponding `for` or `await for` statement.

    *   If the inferred set element type of `e1` is `S` then the inferred set
        element type of `element` is `S`.

    *   If the inferred key type of `e1` is `K` and the inferred key type of
        `e1` is `V` then the inferred key and value types of `element` are `K`
        and `V`.

    *In other words, inference flows upwards from the body element. Note that
    both of the above cases can validly apply because of `dynamic` spreads.*

Finally, we define inference on a `setOrMapLiteral` *collection* as follows:

*   If *collection* is syntactically known to be a set literal, then the
    downwards context for inference of the elements of *collection* is `Set<P>`
    where `P` may be `?` if downwards inference does not constrain the type of
    *collection*.

    *   If `P` is `?` then the static type of *collection* is `Set<T>` where `T`
        is the upper bound of the inferred set element types of the elements.

    *   Otherwise, the static type of *collection* is `Set<T>` where `T` is
        determined by downwards inference.

    *Note that the element inference will never produce a key/value type here
    given that downwards context.*

*   If *collection* is syntactically known to be a map literal and downwards
    inference has statically known type `Map<K, V>` then the downwards context
    for the elements of *collection* is `Map<K, V>`.

*   If *collection* is syntactically known to be a map literal then the
    downwards context for the elements of *collection* is `Map<Pk, Pv>` where
    `Pk` and `Pv` are determined by downwards inference, and may be `?` if the
    downwards context does not constrain one or both.

    *   If `Pk` is `?` then the static key type of *collection* is `K` where `K`
        is the upper bound of the inferred key types of the elements.

    *   Otherwise the static key type of *collection* is `K` where `K` is
        determined by downwards inference.

    And:

    *   If `Pv` is `?` then the static value type of *collection* is `V` where
        `V` is the upper bound of the inferred value types of the elements.

    *   Otherwise the static value type of *collection* is `V` where `V` is
        determined by downwards inference.

    *Note that the element inference will never produce a set element type here
    given this downwards context.*

*   Otherwise, *collection* is not syntactically known to be a set or map
    literal, then the downwards context for the elements of *collection* is `?`,
    and the disambiguation is done as follows:

    *   If all elements can be a set, and at least one element must be a set,
        then *collection* is a set literal with static type `Set<T>` where `T`
        is the upper bound of the set element types of the elements.

    *   If all elements can be a map, and at least one element must be a map,
        then *e* is a map literal with static type `Map<K, V>` where `K` is the
        upper bound of the key types of the elements and `V` is the upper bound
        of the value types.

    *   If all elements can be both maps and sets, then the literal is ambiguous
        and it is a compile-time error. *This occurs when all the *leaf
        elements* are dynamic spreads.*

    *   Otherwise, it is a compile-time error. This can occur when at least one
        element must be a set, and one element which must be a map. Or when no
        element can be a set or map, because all elements are null-aware spreads
        of `Null`.

#### Lists

Inference for list literals mostly follows that of set literals without the
complexity around disambiguation with maps and using `List` or `Iterable` in a
few places instead of `Set`.

Inside a `listLiteral`, the inferred type of an `element` is a list element type
`T`. It is computed relative to an element context type `P`:

*   If `element` is an `expressionElement` with expression `e1`:

    *   The inferred list element type of `element` is the inferred type of the
        expression `e1` in context `P`.

*   If `element` is a `spreadElement` with expression `e1`:

    *   If `P` is `?` then let `S` be the inferred type of `e1` in context `?`:

        *   If `S` is a subtype of `Iterable<Object>`, then the inferred list
            element type of `element` is `T` where `T` is the type such that
            `Iterable<T>` is a superinterface of `S` (the result of constraint
            matching for `X` using the constraint `S <: Iterable<X>`).

        *   If `S` is `dynamic`, then the inferred list element type of
            `element` is `dynamic`.

        *   If `S` is `Null` and the spread operator is `...?`, then the list
            element type is `Null`.

        *   Otherwise it is an error (because it is a spread of a non-spreadable
            type like Object).

    *   Else, let `S` be the inferred type of `e1` in context `Iterable<P>`:

        *   If `S` is a non-`Null` subtype of `Iterable<Object>`, then the
            inferred list element type of `element` is `T` where `T` is the type
            such that `Iterable<T>` is a superinterface of `S` (the result of
            constraint matching for `X` using the constraint `Iterable<X> <:
            S`).

        *   If `S` is `dynamic`, then the inferred list element type of
            `element` is `dynamic`.

        *   Otherwise it is an error.

*   If `element` is an `ifElement` with one `element`, `p1`, and no "else"
    element:

    The condition is inferred with a context type of `bool`.

    The inferred list element type of `element` is the inferred list element
    type of `p1` with element context type `P`.

*   If `element` is a `ifElement` with two `element`s, `p1` and `p2`:

    The condition is inferred with a context type of `bool`.

    The inferred list element type of `element` is the upper bound of `S1` and
    `S2` where `S1` is the inferred list element type of `p1` and `S2` is the
    inferred list element type of `p2`, both with element context type `P`.

*   If `element` is a `forElement` with `element` `p1` then:

    Inference for the iterated expression and the controlling variable is done
    as for the corresponding `for` or `await for` statement.

    The inferred list element type of `element` is the inferred list element
    type of `p1` with element context type `P`.

*Note: `element` cannot be a `mapEntry` those are not allowed inside list
literals.*

Finally, we define inference on a `listLiteral` *collection* as follows:

*   The downwards element context for inference of the elements of *collection*
    is `P` where `P` is `T` if downwards inference constraints the type of
    collection to `Iterable<T>` for some `T`. Otherwise, `P` is `?`.

    *   If `P` is `?` then the static type of *collection* is `List<T>` where
        `T` is the upper bound of the inferred list element types of the
        elements.

    *   Otherwise, the static type of *collection* is `List<T>` where `T` is
        determined by downwards inference.

### Compile-time errors

After type inference and disambiguation, the collection is checked for other
compile-time errors. It is a compile-time error if:

*   The collection is a list and the type of any of the *leaf elements* may not
    be assigned to the list's element type.

    ```dart
    <int>[if (true) "not int"] // Error.
    ```

*   The collection is a map and the key type of any of the *leaf elements* may
    not be assigned to the map's key type.

    ```dart
    <int, int>{if (true) "not int": 1} // Error.
    ```

*   The collection is a map and the value type of any of the *leaf elements* may
    not be assigned to the map's value type.

    ```dart
    <int, int>{if (true) 1: "not int"} // Error.
    ```

*   A spread element in a list or set literal has a static type that is `Null`,
    or that is not `dynamic` and not a subtype of `Iterable<Object>`.

*   A spread element in a list or set has a static type that implements
    `Iterable<T>` for some `T` and `T` is not assignable to the element type of
    the list.

*   A spread element in a map literal has a static type that is `Null`, or that
    is not `dynamic` and not a subtype of `Map<Object, Object>`.

*   If a map spread element's static type implements `Map<K, V>` for some `K`
    and `V` and `K` is not assignable to the key type of the map or `V` is not
    assignable to the value type of the map.

*   The variable in a `for` element (either `for-in` or C-style) is declared
    outside of the element to be `final`.

    ```dart
    final i = 0;
    [for (i in [1]) i] // Error.
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

The runtime semantics below are also used to determine the compile-time value of
a collection literal marked `const`, with a few restrictions:

*   A `listLiteral` is constant if it occurs in a constant context or if it is
    directly prefixed by `const`. If so, then its `elements` must all be
    constant elements.

*   A `setOrMapLiteral` is constant if it occurs in a constant context or if it
    is directly prefixed by `const`. If so, then its `elements` must all be
    constant elements.

*   An `expressionElement` is a constant element if its expression is a constant
    expression, and a potentially constant element if it's expression is a
    potentially constant expression.

*   A `mapEntry` is a constant element if both its key and value expression are
    constant expressions, and a potentially constant element if both are
    potentially constant expressions.

*   A `spreadElement` starting with `...` is a constant element if its
    expression is constant and it evaluates to a constant `List`, `Set` or `Map`
    instance originally created by a list, set or map literal. It is a
    potentially constant element if the expression is potentially constant
    expression.

*   A `spreadElement` starting with `...?` is a constant element if its
    expression is constant and it evaluates to `null` or a constant `List`,
    `Set` or `Map` instance originally created by a list, set or map literal. It
    is a potentially constant element if the expression is potentially constant
    expression.

*   An `ifElement` is constant if its condition is a constant expression
    evaluating to a Boolean value and either:

    *   If the condition evaluates to `true`, the "then" element is a constant
        expression, and any "else" element is a potentially constant element.

    *   If the condition evaluates to `false`, then the "then" element is a
        potentially constant element and any "else" element is a constant
        element.

*   An `ifElement` is potentially constant if its condition, "then" element, and
    "else" element (if any) are potentially constant expressions.

*   A `forElement` is never a constant element. A `for` element cannot be used
    in constant collection literals.

*   It is a compile-time error if any element in a constant set or key in a
    constant map does not have a primitive operator `==`.

*   It is a compile-time error if an element in a const set is equal to any
    other element according to its operator `==`.

*   It is a compile-time error if a key in a constant map is equal to any other
    key according to its operator `==`.

*   It is a compile-time error to have duplicate values in a set literal or
    duplicate keys in a map literal, according to behavior specified in the
    runtime semantics.

*   When evaluating a const collection literal, if another const collection has
    previously been evaluated that:

    *   is of the same kind (map, set, or list),
    *   has the same type arguments,
    *   and contains the same (identical) elements or key/value entries in the
        same order,

    then the current literal evaluates to the value of that previous literal.
    *In other words, constants are canonicalized.* Note that maps and sets are
    only canonicalized if they contain the same keys or elements *in the same
    order*.

## Dynamic Semantics

Spread, `if`, and `for` behave similarly across all collection types. To
simplify the spec, there is a single procedure used for all kinds of
collections. This recursive procedure builds up either a `result` sequence of
values or key-value pair map entries. Then a final step handles those
appropriately for the given collection type.

### To evaluate a collection `element`:

1.  If `element` is an expression element:

    1.  Evaluate the element's expression and append it to `result`.

1.  Else, `element` is a `mapEntry` `keyExpression: valueExpression`:

    1.  Evaluate `keyExpression` to a value `key`.

    1.  Evaluate `valueExpression` to a value `value`.

    1.  Append `key: value` to `result`.

1.  Else, if `element` is a spread element:

    1.  Evaluate the spread expression to a value `spread`.

    1.  If `entry` is null-aware and `spread` is null, do nothing.

    1.  Otherwise:

        1.  If the collection is a map, evaluate `spread.entries.iterator` to a
            value `iterator`. Otherwise, evaluate `spread.iterator` to
            `iterator`. *This will deliberately throw an exception if `spread`
            is `null` and `element` is not null-aware.*

        1.  Loop:

            1.  If `iterator.moveNext()` returns `false`, exit the loop.

            1.  Evaluate `iterator.current` and append it to `result`. *This
                will be a MapEntry in a map literal, or any object for a list or
                set literal.*

1.  Else, if `element` is an `ifElement`:

    1.  Evaluate the condition expression to a value `condition`.

    1.  If the Boolean conversion of `condition` is `true`:

        1.  Evaluate the "then" element using this procedure.

    1.  Else, if there is an "else" element of the `if`:

        1.  Evaluate the "else" element using this procedure.

1.  Else, if `element` is a synchronous `forElement` for a `for-in` loop:

    1.  Evaluate the iterator expression to a value `sequence`.

    1.  Evaluate `sequence.iterator` to a value `iterator`.

    1.  Loop:

        1.  If the Boolean conversion of `iterator.moveNext()` does not return
            `true`, exit the loop.

        1.  If the `for-in` element declares a variable, create a new namespace
            and a fresh `variable` for it. Otherwise, use the existing
            `variable` it refers to.

        1.  Bind `variable` to the result of evaluating `iterator.current`.

        1.  Evaluate the body element using this procedure in the scope of
            `variable`.

1.  Else, if `element` is an asynchronous `await for-in` element:

    1.  Evaluate the stream expression to a value `stream`. It is a dynamic
        error if `stream` is not an instance of a class that implements
        `Stream`.

    1. Listen on `stream` and take the following actions on events:

       *    On a data event with value `value`:

            1.  If the `for-in` element declares a variable, create a new
                namespace and a fresh `variable` for it. Otherwise, use the
                existing `variable` it refers to.

            1.  Bind `variable` to `value`.

            1.  Evaluate the body element using this procedure.

            1.  If evaluation of the body throws an error `error` and stack
                trace `stack`, then:

                1.  Stop listening on the stream by calling the `cancel()`
                    method of the c  orresponding stream subscription, which
                    returns a future `f`.

                1.  Wait for `f` to complete. If `f` completes with an error
                    `error2` and stack trace `stack2`, then complete
                    `streamDone` with error `error2` and stack trace `stack2`.
                    Otherwise complete `streamDone` with error `error` and stack
                    trace `stack`.

            1.  Else, evaluation of the body element completes successfully.

                1.  Resume the stream subscription if it has been paused.

        *   On an error event with error `error` and stack trace `stack`:

            1.  Stop listening on the stream by calling the `cancel()` method of
                the corresponding stream subscription, which returns a future
                `f`.

            1.  Wait for `f` to complete. If `f` completes with an error
                `error2` and stack trace `stack2`, then complete `streamDone`
                with error `error2` and stack trace `stack2`. Otherwise complete
                `streamDone` with error `error` and stack trace `stack`.

        *   On a done event, complete `streamDone` with the value `null`.

    1.  Evaluation of the `for-in` element completes when `streamDone`
        completes. If `streamDone` completes with an error `error` and stack
        trace `stack`, then evaluation of the element throws `error` with stack
        trace `stack`, otherwise the evaluation completes successfully.

1.  Else, `element` is a C-style `for` element:

    1.  Evaluate the initializer clause of the element, if there is one.

    1.  Loop:

        1.  If the initializer clause declares a variable, create a new
            namespace and bind that variable in that namespace.

        1.  Evaluate the condition expression to a value `condition`. If there
            is no condition expression, use `true`.

        1.  If the Boolean conversion of `condition` is not `true`, exit the
            loop.

        1.  Evaluate the body element using this procedure in the namespace of
            the variable declared by the initializer clause if there is one.

        1.  If there is an increment clause, execute it.

The procedure theoretically supports a mixture of expressions and map entries,
but the static semantics prohibit an actual literal containing that. Once the
`result` series of values or entries is produced from the tree of elements:

### Lists

1.  The result of the literal expression is a fresh instance of a class that
    implements `List<E>` containing the values in `result`, in order. If the
    literal is constant, the list is immutable, otherwise it is not.

### Sets

1.  Create a fresh instance `set` of a class that implements `Set<E>`.

1.  For each `value` in `result`:

    1.  If `set` contains any value `existing` that is equal to `value`
        according to `existing`'s `==` operator, do nothing.

    1.  Otherwise, add `value` to `set`.

1.  The result of the literal expression is `set`. If the literal is constant,
    make the set immutable.

### Maps

1.  Allocate a fresh instance `map` of a class that implements `LinkedHashMap<K,
    V>`.

1.  For each `entry` in `result`:

    1.  If `map` contains any key `key` that is equal to the key of `entry`
        according to `key`'s `==` operator, do nothing.

    1.  Otherwise, insert `entry` into `map`.

1.  The result of the map literal expression is `map`. If the literal is
    constant, make the map immutable.
