# Unified Collections

The Dart team is concurrently working on three proposals that affect collection
literals:

* [Set Literals][]
* [Spread Collections][]
* [Control Flow Collections][]

[set literals]: https://github.com/dart-lang/language/blob/master/accepted/2.2/set-literals/feature-specification.md
[spread collections]: https://github.com/dart-lang/language/blob/master/accepted/2.3/spread-collections/feature-specification.md
[control flow collections]: https://github.com/dart-lang/language/blob/master/accepted/2.3/control-flow-collections/feature-specification.md

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
listLiteral       : 'const'? typeArguments? '[' elements? ']' ;

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

Let the *leaf elements* of *e* be the concatenation of all of the *leaf
elements* of each `element` directly in *e* where the *leaf elements* of an
`element` are:

*   If `element` is an `ifElement`, then the *leaf elements* are the
    concatenation of the *leaf elements* of the "then" and "else" elements of
    `element`.

*   Else, if `element` is a `forElement`, then the *leaf elements* are the *leaf
    elements* of the body element of `element`.

*   Else, if `element` is an `expressionElement` or `mapEntry`, then the *leaf
    element* is `element` itself.

*   Else, the element has no *leaf elements*. *A spread contains no leaf
    elements.*

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

Inference and set/map disambiguation are done concurrently. When possible, we
use syntax and the surrounding context type to disambiguate between a map and
set:

Let *e* be a `setOrMapLiteral`.

If *e* has a context `C`, and the base type of `C` is `Cbase` (that is, `Cbase`
is `C` with all wrapping `FutureOr`s removed), and `Cbase` is not `?`, then let
`S` be the greatest closure.

1.  If *e* has `typeArguments` then:

    *   If there is exactly one type argument `T`, then *e* is a set literal
        with static type `Set<T>`.

    *   If there are exactly two type arguments `K` and `V`, then *e* is a map
        literal with static type `Map<K, V>`.

    *   Otherwise (three or more type arguments), report a compile-time error.

1.  Else, if `S` is defined and is a subtype of `Iterable<Object>` and `S` is
    not a subtype of `Map<Object, Object>`, then *e* is a set literal.

1.  Else, if `S` is defined and is a subtype of `Map<Object, Object>` and `S` is
    not a subtype of `Iterable<Object>` then *e* is a map literal.

1.  Else, if *leaf elements* is not empty, then:

    *   If *leaf elements* has at least one `expressionElement` and no
        `mapEntry` elements, then *e* is a set literal with unknown static type.
        The static type will be filled in by type inference, defined below.

    *   If *leaf elements* has at least one `mapEntry` and no
        `expressionElement` elements, then *e* is a map literal with unknown
        static type. The static type will be filled in by type inference,
        defined below.

    *   If *leaf elements* has at least one `mapEntry` and at least one
        `expressionElement`, report a compile-time error.

    *In other words, at least one key-value pair anywhere in the collection
    forces it to be a map, and a bare expression forces it to be a set. Having
    both is an error.*

1.  Else, if *e* has no `typeArguments`, no useful context type, and no
    `elements`, then *e* is treated as a map literal with unknown static type.
    *In other words, an empty `{}` is a map unless we have a context that
    indicates otherwise.*

1.  Otherwise, *e* is still ambiguous. This can only happen when *e* is
    non-empty but contains no *leaf elements*. In other words, it contains only
    spreads or spreads wrapped in if and for elements. In this case, the
    disambiguation will happen during type inference, defined below.

If this process successfully disambiguates the literal, then we say that *e* is
"unambiguously a map" or "unambiguously a set", as appropriate.

### Type inference

#### Maps and sets

We perform inference on the literal, and collect up either a set element type
(indicating that the literal may/must be a set), or a pair of a key type and a
value type (indicating that the literal may/must be a map), or both. We allow
both, because spreads of expressions of type `dynamic` do not disambiguate, and
can be treated as either (it becomes a runtime error to spread a value into the
wrong kind of literal).

We require that at least one component unambiguously determine the literal form,
otherwise it is a compile-time error. So, given:

```dart
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

In a `setOrMapLiteral` *collection*, the inferred type of an `element` is a set
element type `T`, a pair of a key type `K` and a value type `V`, or both. It is
computed relative to a context type `P`:

*   If *collection* is unambiguously a set literal, then `P` is `Set<Pe>` where
    `Pe` is determined by downwards inference, and may be `?` if downwards
    inference does not constrain it.

*   If *collection* is unambiguously a map literal then `P` is `Map<Pk, Pv>`
    where `Pk` and `Pv` are determined by downwards inference, and may be `?` if
    the downwards context does not constrain one or both.

*   Otherwise, *collection* is ambiguous, and the downwards context for the
    elements of *collection* is `?`.

We say that an element *can be a set* if it has a set element type. Likewise, an
element *can be a map* if it has a key and value type. We say that an element
*must be a set* if it can be a set and has and no key type or value type. We say
that an element *must be a map* if can be a map and has no set element type.

To infer the type of `element`:

*   If `element` is an `expressionElement` with expression `e1`:

    *   If `P` is `?` then the inferred set element type of `element` is the
        inferred type of the expression `e1` in context `?`.

    *   If `P` is `Set<Ps>` then the inferred set element type of `element`
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
        `Iterable<Ps>`:

        *   If `S` is a non-`Null` subtype of `Iterable<Object>`, then the
            inferred set element type of `element` is `T` where `T` is the type
            such that `Iterable<T>` is a superinterface of `S` (the result of
            constraint matching for `X` using the constraint `S <:
            Iterable<X>`).

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
            for `X` and `Y` using the constraint `S <: Map<X, Y>`).

        *   If `S` is `dynamic`, then the inferred key type of `element` is
            `dynamic`, and the inferred value type of `element` is `dynamic`.

        *   If `S` is `Null` and the spread operator is `...?`, then the key and
            value element types are `Null`.

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
        `element` is the least upper bound of `S1` and `S2`.

    *   If the inferred key type of `e1` is `K1` and the inferred key type of
        `e1` is `V1` and the inferred key type of `e2` is `K2` and the inferred
        key type of `e2` is `V2` then the inferred key type of `element` is the
        least upper bound of `K1` and `K2` and the inferred value type is the
        least upper bound of `V1` and `V2`.

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

*   If *collection* is unambiguously a set literal:

    *   If `P` is `?` then the static type of *collection* is `Set<T>` where `T`
        is the least upper bound of the inferred set element types of the
        elements.

    *   Otherwise, the static type of *collection* is `P`.

    *Note that the element inference will never produce a key/value type here
    given that downwards context.*

*   Else, f *collection* is unambiguously a map literal where `P` is `Map<Pk,
    Pv>`:

    *   If `Pk` is `?` then the static key type of *collection* is `K` where `K`
        is the least upper bound of the inferred key types of the elements.

    *   Otherwise the static key type of *collection* is `K` where `K` is
        determined by downwards inference.

    And:

    *   If `Pv` is `?` then the static value type of *collection* is `V` where
        `V` is the least upper bound of the inferred value types of the
        elements.

    *   Otherwise the static value type of *collection* is `V` where `V` is
        determined by downwards inference.

    The static type of *collection* is `Map<K, V>`.

    *Note that the element inference will never produce a set element type here
    given this downwards context.*

*   Otherwise, *collection* is still ambiguous, the downwards context for the
    elements of *collection* is `?`, and the disambiguation is done using the
    immediate `elements` of *collection* as follows:

    *   If all elements can be a set, and at least one element must be a set,
        then *collection* is a set literal with static type `Set<T>` where `T`
        is the least upper bound of the set element types of the elements.

    *   If all elements can be a map, and at least one element must be a map,
        then *e* is a map literal with static type `Map<K, V>` where `K` is the
        least upper bound of the key types of the elements and `V` is the least
        upper bound of the value types.

    *   Otherwise, the literal cannot be disambiguated and it is a compile-time
        error. This can occur if the literal *must* be both a set and a map,
        as in:

        ```dart
        var iterable = [1, 2];
        var map = {1: 2};
        var ambiguous = {...iterable, ...map};
        ```

        Or, if there is nothing indicates that it is *either* a map or set:

        ```dart
        dynamic dyn;
        var ambiguous = {...dyn};
        ```

#### Lists

Inference for list literals mostly follows that of set literals without the
complexity around disambiguation with maps and using `List` or `Iterable` in a
few places instead of `Set`.

Inside a `listLiteral`, the inferred type of an `element` is a list element type
`T`. It is computed relative to a downwards element context type `P`, where `P`
is `T` if downwards inference constrains the type of `listLiteral` to
`Iterable<T>` for some `T`. Otherwise, `P` is `?`.

*   If `element` is an `expressionElement` with expression `e1`:

    *   The inferred list element type of `element` is the inferred type of the
        expression `e1` in context `P`.

*   If `element` is a `spreadElement` with expression `e1`:

    *   If `P` is `?` then let `S` be the inferred type of `e1` in context `?`:

        *   If `S` is a non-`Null` subtype of `Iterable<Object>`, then the
            inferred list element type of `element` is `T` where `T` is the type
            such that `Iterable<T>` is a superinterface of `S` (the result of
            constraint matching for `X` using the constraint `S <:
            Iterable<X>`).

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
            constraint matching for `X` using the constraint `S <:
            Iterable<X>`).

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

    The inferred list element type of `element` is the least upper bound of `S1`
    and `S2` where `S1` is the inferred list element type of `p1` and `S2` is
    the inferred list element type of `p2`, both with element context type `P`.

*   If `element` is a `forElement` with `element` `p1` then:

    Inference for the iterated expression and the controlling variable is done
    as for the corresponding `for` or `await for` statement.

    The inferred list element type of `element` is the inferred list element
    type of `p1` with element context type `P`.

*Note: `element` cannot be a `mapEntry` as those are not allowed inside list
literals.*

Finally, we define inference on a `listLiteral` *collection* as follows:

*   If `P` is `?` then the static type of *collection* is `List<T>` where
    `T` is the least upper bound of the inferred list element types of the
    elements.

*   Otherwise, the static type of *collection* is `List<T>` where `T` is
    determined by downwards inference.

### Type promotion

An `ifElement` interacts with type promotion in the same way that `if`
statements do. Given an `ifElement` with condition `condition`, then element
`thenElement` and optional else element `elseElement`:

*   If `condition` shows that a local variable *v* has type `T`, then the type
    of *v* is known to be `T` in `thenElement`, unless any of the following are
    true:

    *   *v* is potentially mutated in `thenElement`,
    *   *v* is potentially mutated within a function other than the one where
        *v* is declared, or
    *   *v* is accessed by a function defined in `thenElement` and
    *   *v* is potentially mutated anywhere in the scope of *v*.

*Note: The type promotion rules for `if` will likely get more sophisticated in a
future version of Dart because of non-nullable types. When that happens, `if`
elements should continue to match `if` statements.*

### Compile-time errors

After type inference and disambiguation, the collection is checked for other
compile-time errors. It is a compile-time error if:

*   The collection is a map literal and *leaf elements* contains any
    `expressionElement` elements.

    ```dart
    <String, int>{"not entry"} // Error.
    ```

*   The collection is a set literal and *leaf elements* contains any `mapEntry`
    elements.

    ```dart
    ["not": "expression"] // Error.
    <String>{"not": "expression"} // Error.
    ```

    *We prohibit map entries in list literals syntacitcally, earlier in the
    proposal.*

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

*   A non-null-aware spread element has static type `Null`.

*   A spread element in a list or set literal has a static type that is not
    `dynamic` and not a subtype of `Iterable<Object>`.

*   A spread element in a list or set has a static type that implements
    `Iterable<T>` for some `T` and `T` is not assignable to the element type of
    the list.

*   A spread element in a map literal has a static type that is not `dynamic`
    and not a subtype of `Map<Object, Object>`.

*   If a map spread element's static type implements `Map<K, V>` for some `K`
    and `V` and `K` is not assignable to the key type of the map or `V` is not
    assignable to the value type of the map.

*   The variable in a `for` element (either `for-in` or C-style) is declared
    outside of the element to be `final` or to not have a setter.

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

The runtime semantics below are used to determine the compile-time value of a
constant collection literal, which is defined as a `listLiteral` or
`setOrMapLiteral` that occurs in a constant context or directly preceded by
`const`.

Elements in a collection may be constant, potentially constant, or neither. All
`elements` directly inside in a constant collection must be constant elements.
They are defined as:

*   An `expressionElement` is a constant element if its expression is a constant
    expression, and a potentially constant element if it's expression is a
    potentially constant expression.

*   A `mapEntry` is a constant element if both its key and value expression are
    constant expressions, and a potentially constant element if both are
    potentially constant expressions.

*   A `spreadElement` starting with `...` is a constant element if its
    expression is constant and it evaluates to a constant `List`, `Set` or `Map`
    instance originally created by a list, set or map literal. It is a
    potentially constant element if the expression is a potentially constant
    expression.

*   A `spreadElement` starting with `...?` is a constant element if its
    expression is constant and it evaluates to `null` or a constant `List`,
    `Set` or `Map` instance originally created by a list, set or map literal. It
    is a potentially constant element if the expression is potentially constant
    expression.

*   An `ifElement` is a constant element if its condition is a constant
    expression evaluating to a value of type `bool` and either:

    *   The condition evaluates to `true`, the "then" element is a constant
        expression, and the "else" element (if it exists) is a potentially
        constant element.

    *   The condition evaluates to `false`, the "then" element is a potentially
        constant element, and the "else" element (if it exists) is a constant
        element.

*   An `ifElement` is potentially constant if its condition, "then" element, and
    "else" element (if any) are potentially constant expressions.

*   A `forElement` is never a constant or potentially constant element. A `for`
    element cannot be used in constant collection literals.

Also:

*   It is a compile-time error if any element in a constant set or key in a
    constant map does not have a primitive operator `==`.

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
collections. This recursive procedure builds up either a *result* sequence of
values or key-value pair map entries. Then a final step handles those
appropriately for the given collection type.

### To evaluate a collection `element`:

1.  If `element` is an expression element:

    1.  Evaluate the element's expression and append it to *result*.

1.  Else, `element` is a `mapEntry` `keyExpression: valueExpression`:

    1.  Evaluate `keyExpression` to a value *key*.

    1.  Evaluate `valueExpression` to a value *value*.

    1.  Append an entry *key*: *value* to *result*.

1.  Else, if `element` is a spread element:

    1.  Evaluate the spread expression to a value `spread`.

    1.  If `element` is not null-aware and `spread` is `null`, throw a dynamic
        exception.

    1.  Else, if `element` is null-aware and `spread` is `null`, do nothing.

    1.  Else, if the collection is a map:

        1.  If `spread` is not an instance of a class that implements `Map`,
            throw a dynamic exception.

        1.  Evaluate `spread.entries.iterator` to a value `iterator`.

        1.  Loop:

            1.  Evaluate `iterator.moveNext()` to a value `hasValue`.

            1.  If `hasValue` is `true`:

                1.  Evaluate `iterator.current` to a value `entry`.

                1.  Evaluate `entry.key` to a value *key*.

                1.  Evaluate `entry.value` to a value *value*.

                1.  If *key* is not a subtype of the map's key type, throw a
                    dynamic error.

                1.  If *value* is not a subtype of the map's value type, throw a
                    dynamic error.

                An implementation is free to execute the previous four
                operations in any order, except that obviously the key must be
                evaluated before its type is checked, and likewise for the
                value.

                1.  Append an entry *key*: *value* to *result*.

            1.  Else, if `hasValue` is `false`, exit the loop.

            1.  Else, throw a dynamic error.

    1.  Else, the collection is a list or set:

        1.  If `spread` is not an instance of a class that implements
            `Iterable`, throw a dynamic exception.

        1.  Evaluate `spread.iterator` to *iterator*.

        1.  Loop:

            1.  Evaluate `iterator.moveNext()` to a value `hasValue`.

            1.  If `hasValue` is `true`:

                1.  Evaluate `iterator.current` to a value *value*.

                1.  If *value* is not a subtype of the collection's element
                    type, throw a dynamic error.

                1.  Append *value* to *result*.

            1.  Else, if `hasValue` is `false`, exit the loop.

            1.  Else, throw a dynamic error.

    The `iterator` API may not be the most efficient way to traverse the items
    in a collection. In order to give implementations more room to optimize, we
    loosen the semantics:

    *   If `spread` is an object whose class implements List, Queue, or Set (all
        from `dart:core`), an implementation *may* choose to call `length` on
        the object. This may let it allocate space for the resulting collection
        more efficiently. Classes that implement these are expected to have an
        efficient, side-effect free implementation of `length`.

    *   If `spread` is an object whose class implements List from `dart:core`,
        an implementation may choose to call `[]` to access elements from the
        list. If it does so, it will only pass indexes `>= 0` and `<` the value
        returned by `length`.

    A Dart implementation may detect whether these options apply at compile time
    based on the static type of `spread` or at runtime based on the actual
    value.

1.  Else, if `element` is an `ifElement`:

    1.  Evaluate the condition expression to a value `condition`.

    1.  If `condition` is `true`:

        1.  Evaluate the "then" element using this procedure.

    1.  Else, if `condition` is `false`:

        1.  If there is an "else" element of the `if`:

            1.  Evaluate the "else" element using this procedure.

    1.  Else, throw a dynamic error.

1.  Else, if `element` is a synchronous `forElement` for a `for-in` loop:

    1.  Evaluate the iterator expression to a value `sequence`.

    1.  If `sequence` is not an instance of a class that implements `Iterable`,
        throw a dynamic exception.

    1.  Evaluate `sequence.iterator` to a value `iterator`.

    1.  Loop:

        1.  Evaluate `iterator.moveNext()` to a value `hasValue`.

        1.  If `hasValue` is `true`:

            1.  If the `for-in` element declares a variable, create a new
                namespace and a fresh `variable` for it. Otherwise, use the
                existing `variable` it refers to.

            1.  Bind `variable` to the result of evaluating `iterator.current`.

            1.  Evaluate the body element using this procedure in the scope of
                `variable`.

        1.  Else, if `hasValue` is `false`, exit the loop.

        1.  Else, throw a dynamic error.

1.  Else, if `element` is an asynchronous `await for-in` element:

    1.  Evaluate the stream expression to a value `stream`.

    1.  If `stream` is not an instance of a class that implements `Stream`,
        throw a dynamic error.

    1.  Pause the subscription of any surrounding `await for` loop in the
        current method.

    1.  Let `streamDone` be a value implementing `Future<Null>`.

    1.  Listen on `stream` and take the following actions on events:

        *   On a data event with value `value`:

            1.  If the `for-in` element declares a variable, create a new
                namespace and a fresh `variable` for it. Otherwise, use the
                existing `variable` it refers to.

            1.  Bind `variable` to `value`.

            1.  Evaluate the body element using this procedure.

            1.  If evaluation of the body throws an error `error` and stack
                trace `stack`, then:

                1.  Stop listening on the stream by calling the `cancel()`
                    method of the corresponding stream subscription, which
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

        1.  If `condition` is `true`:

            1.  Evaluate the body element using this procedure in the namespace
                of the variable declared by the initializer clause if there is
                one.

            1.  If there is an increment clause, execute it.

        1.  Else, if `condition` is `false`, exit the loop.

        1.  Else, throw a dynamic error.

The procedure theoretically supports a mixture of expressions and map entries,
but the static semantics prohibit an actual literal containing that.

Once the *result* series of values or entries is produced from the tree of
elements, the final object is produced from that based on what kind of literal
it is:

### List

1.  The result of the literal expression is a fresh instance of a class that
    implements `List<E>` where `E` is the element type of the literal. It
    contains the values in *result*, in order. If the literal is constant, the
    list is canonicalized and immutable, otherwise it is not.

### Set

1.  Create a fresh instance *set* of a class that implements `Set<E>` where `E`
    is the set element type of the literal.

1.  For each *value* in *result*:

    1.  If *set* contains a value *existing* that is equal to *value*
        according to *existing*'s `==` operator:

        1.  If the literal is constant, it is a compile-time error.

        1.  Else, do nothing. *Duplicates are discarded and the first one wins.*

    1.  Else, add *value* to *set*.

1.  The result of the literal expression is *set*. If the literal is constant,
    canonicalize it make the set immutable.

### Map

1.  Allocate a fresh instance *map* of a class that implements `LinkedHashMap<K,
    V>` where `K` is the key type of the literal and `V` is the value type.

1.  For each entry *key*: *value* in *result*:

    1.  If *map* contains an entry *existing* whose key *existingKey* is equal
        to *key* according to *existingKeys*'s `==` operator:

        1.  If the literal is constant, it is a compile-time error.

        1.  Else, replace the value in *existing* with *value*, while keeping
            its position in the sequence of entries and *existingKey* the same.

    1.  Else add entry *key*: *value* to *map*.

1.  The result of the map literal expression is *map*. If the literal is
    constant, canonicalize it and make the map immutable.
