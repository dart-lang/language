# Set Literals Design Document

**Author**: lrn@google.com

**Version**: 1.2

**Status**: Superceeded by language specification.

Solution for [Set Literals Problem](http://github.com/dart-lang/language/issues/36).
Based on feature proposal [Issue 37](http://github.com/dart-lang/language/issues/37)

**Note: Because this feature interacts heavily with [Spread Collections][] and
[Control Flow Collections][], which are all being implemented concurrently, we
have a [unified proposal][] that covers the behavior of all three. That proposal
is now the source of truth. This document is useful for motivation, but may be
otherwise out of date.**

[spread collections]: https://github.com/dart-lang/language/blob/master/accepted/2.3/spread-collections/feature-specification.md
[control flow collections]: https://github.com/dart-lang/language/tree/master/accepted/2.3/control-flow-collections/feature-specification.md
[unified proposal]: https://github.com/dart-lang/language/tree/master/accepted/2.3/unified-collections/feature-specification.md

## Overview

Dart has `List` and `Map` literals, but no `Set` literal.
This feature adds *set* literals using curly brace-delimiters, like in mathematical set notation.
The notation is mostly non-conflicting with existing syntax.
It uses the same braces as map literals, and is usable in the same syntactic positions,
but since map literals have colon-separated map entries rather than single value elements,
and map literals take two type arguments rather than one,
the only conflict arises for the `{}` expression, with no type arguments and not contents,
which can be either an empty map or an empty set.
We use the context type to distinguish even further cases, but for backwards compatibility,
we will default it being a map literal when there is no detectable reason it cannot be one.

## Syntax
We change the literal grammar from:
```
literal:
    nullLiteral |
    booleanLiteral |
    numericLiteral |
    stringLiteral |
    symbolLiteral |
    mapLiteral |
    listLiteral

mapLiteral:
    const? typeArguments? '{' (mapLiteralEntry (',' mapLiteralEntry)* ', '?)? '}'
```
to:
```
literal:
    nullLiteral |
    booleanLiteral |
    numericLiteral |
    stringLiteral |
    symbolLiteral |
    setOrMapLiteral |
    listLiteral

setOrMapLiteral:
    mapLiteral |
    setLiteral |
    emptySetOrMapLiteral ;
mapLiteral:
    'const'?  typeArguments? '{' mapLiteralEntry (',' mapLiteralEntry)* ','? '}' ;
setLiteral:
    'const'?  typeArguments? '{' expression (',' expression)* ','? '}' ;
emptySetOrMapLiteral:
    'const'?  typeArguments? '{' '}' ;
```
This grammar is still syntactically unambiguous
(and the rule that an expression statement cannot start with a `{` token now covers both map and set literals).

The ambiguity is in the *meaning* of `typeArguments {}` or `const typeArguments {}`,
which will be decided based on the number of type arguments,
and in the meaning of `{}` or `const {}`, which will be decided during type inference.

If a literal has an explicit type parameter, there is no ambiguity: one parameter for sets, two for maps.
If it contains any elements or entries, there is no ambiguity:
sets elements are single expressions, map entries are colon-separated expressions.

## semantics

It is a compile-time error if a `mapLiteral` has a `typeArguments` with a number of type arguments other than two.

It is a compile-time error if a `setLiteral` has a `typeArguments` with more than one type argument.

It is a compile-time error if an `emptySetOrMapLiteral` has a `typeArguments` with more than two type arguments.

Let *s* be a `setOrMapLiteral`. Then *s* is either a *set literal* or a *map literal*.

If *s* is a `mapLiteral` then it is a *map literal*.

If *s* is a `setLiteral` then it is a *set literal*.

If *s* is an `emptySetOrMapLiteral`, then if *s* has a `typeArguments` with one type argument, *s* is a *set literal*, and
if *s* has a `typeArguments` with two type arguments, *s* is a *map literal*.
(*Three or more type arguments is a compile time error, so the remaining possible case is having no type arguments*).

If *s* is an `emptySetOrMapLiteral` with no `typeArguments` and static context type *C*, then
if `Iterable<Object>` is a supertype of *basetype(C)* and `Map<Object, Object>` is not a super-type of *basetype(C)*,
then *s* is a *set literal*, otherwise *s* is a *map literal*.
The *basetype* function is defined as:
* *basetype(FutureOr&lt;S&gt;)* = *basetype(S)*
* *basetype(T)* = *T* if *T* is not *FutureOr&lt;X&gt;* for any *X*.

(*So if *C* is, for example, `Iterable<int>`, `Set<Object>`, `LinkedHashSet<int>` or `FutureOr<Iterable<int>>`,
then *s* is a set literal. If *C* is `Object` or `dynamic` or `Null` or `String`, then *s* is a map literal,
*and* potentially a compile-time error due to static typing*. If *C* implements both `Set<X>` *and* `Map<Y, Z>`, then the literal is a map literal, but it is also a guaranteed tun-time type error whther the literal is a set or a map because the actual object will not implement that type.

### Map literals

If *s* is a *map literal*, then its static and dynamic semantics are unchanged by this feature.

### Set literals

If *s* is a *set literal*, then it has the form `const? ('<' type '>')? '{' ... '}'` where `...` is zero or more
comma-separated element expressions (potentially with a trailing comma which is otherwise ignored).

If *s* has no `typeArgument`, then one is inferred in exactly the same way as for list literals.
(*Either infer it from the context type, or if there is no context type, or the context type does not constrain
the element type, then do upwards inference based on the static type of the element expressions, if any,
or otherwise fall back on `dynamic`*).

Let *T* be the explicit or inferred type argument to the type literal.
It's a compile-time error if the static type of any element expression is not assignable to *T*.

The static type of `s` is `Set<T>`.

#### Constant Set Literals

If *s* starts with `const` or it occurs in a constant context, then it is a *constant set literal*.
It is then a compile-time error if any element expression is not a compile-time constant expression,
or if *T* is not a compile-time constant type. It is a compile-time error if any of the *values* of the constant element expressions
override `Object.operator==` unless they are instances of `int` or `String`, objects implementing `Symbol` originally created by
a symbol literal or a constant invocation of the `Symbol` constructor, or objects implementing `Type` originally created by
a constant type literal expression.
It is a compile-time error if any two of the values are equal according to `==`.

Let *e<sub>1</sub>* … *e<sub>n</sub>* be the constant element expressions of *s* in source order,
and let *v*<sub>1</sub> … *v<sub>n</sub>* be their respective constant values.
Evaluation of *s* creates an unmodifiable object implementing `Set<T>` with *v*<sub>1</sub> … *v<sub>n</sub>* as elements.
When iterated, the set provides the values in the source order of the original expressions.

If a constant set literals is created which has the same type argument and contains the same values in the same order,
as the value of a previously evaluated constant set literal,
then the constant set literal expression instead evaluates to the previously created constant set.
That is, constant set literals are canonicalized.

#### Non-constant Set Literals

If *s* does not start with `const` and it does not occur in a constant context,
then it evaluates to a mutable set object as follows:

Let *e<sub>1</sub>* … *e<sub>n</sub>* be the constant element expressions of *s* in source order.
Evaluation of *s* proceeds as follows:
1. First evaluate *e*<sub>1</sub> … *e<sub>n</sub>*, in source order, to values *v*<sub>1</sub> … *v<sub>n</sub>*.
2. Create a new `LinkedHashSet<T>` instance, *o*.
3. For each *i* in 1 … *n* in numeric order, invoke the `add` method on *o* with *v<sub>i</sub>* as argument.
Then *s* evaluates to an object implementing `LinkedHashSet` which has the same elements as *o*, and in the same
iteration order. (*Iteration order is insertion order, where adding an element equal to one already in the set does
not change the set in any way*).

### Exact Types of Literals

Currently, the Dart 2 type inference infers an "exact type" for map literals
(as well as for other literals and for generative constructor invocations).
If the map literal has the static type `Map<K, V>`, then that type is inferred as exact.
The inferred exact type makes it a compile-time error to require a down-cast,
since that down-cast is known to fail at runtime.
Effectively, an exact type disables the implicit downcasts otherwise inserted by inference to allow
a supertype where a sub-type is expected.
This behavior is retained for map literals,
and for set literals with element type *T*, the static type of `Set<T>` is also considered exact.

## Concerns
### Migration

There is no change to existing valid programs. No programs need to be migrated.

If an API wants to change to accept a `Set`, that API needs to migrate its users.

### Syntax Compatibility
Above, we say that it is easy to distinguish between set elements and map entries
because map entries contains a colon.
However, expressions can contain a colon too, as part of a conditional expression,
and non-conditional expressions can contain question marks as part of null-aware operations.

That *could* make it ambiguous whether `{ … ? … : … }` is a one-element set or a one-entry map.
Luckily, the current grammar does not allow for an ambiguous parsing.
The token following a question mark dictates whether it's part of a null-aware operation
or the beginning of a new expression.

Question marks can occur in null-aware operations as:
```
x ?. y
x ?? y
x ??= y
```
Neither `.` nor `?` can be the first character of an expression,
which rules out the first `?` being an operator of a conditional expression. That is `{ … ? … : … }`
can be parsed unambiguously because the `?` cannot be seen as both an operator in an expression before the `:`
and as a conditional operator including the `:`. (We don't need to see the `:` to know how to parse the `?`).

However, adding `Set` literals specified this way will preclude any *future* syntax
that allows an expression to start with `.` or `?` (or at least require extra disambiguation complexity at that point).
This includes some ideas for arrow-less function shorthands, e.g., `.foo(2)` as shorthand for `(x)=>x.foo(2)`,
or shorthand syntax for accessing enum instances like `Color c = test ? .red : .blue;`.
Likewise it precludes adding new null-aware operators that can also be seen as two expressions separated by `?`,
like a null-aware index operator `x?[4]` since `{x?[4]:5}` would then be ambiguous.

These concerns are speculative.
We are unlikely to add such syntax since it would be hard to distinguish visually from existing uses of `?`
and will likely make parsing more expensive when you can't recognize whether a `?` starts a conditional expression
without finding the matching `:`, instead of just looking at the next token.
We can probably find other syntax for such operations, but using braces for sets is the most natural syntax available.

We could choose to disallow an element expression of a set literal from being a *conditionalExpression*
that is not an *ifNullExpression*.
Then the conditional expression containing a top-level `:` operator would have to be parenthesized.
That would probably be a usability pitfall, though,
since there is no *obvious* reason for the restriction to a normal user who just wants to write a set.
You can write `[b ? e1 : e2]`, but would not be allowed to write `{b ? e1 : e2}`.
Maybe the top-level `:` making this look like a map is enough reason for users to be able to remember that it's not allowed.

If we add this restriction at a later point, it will be a breaking change.

### Future Feature Compatibility
#### Collection Spreads
"Collection spreads" is one potential future language feature, which is already being discussed,
and which overlaps with set literals.
Collection spreads allow you to write `[1, ...iterableExpression, 3]` as a list literal, and it will evaluate `iterableExpression`, then iterate it and insert every element of the iterable in the resulting list.
Similarly you can write `{1: 1, ...mapExpression, 3: 42}` to expand the entries of a map into another map literal.

We should also accept spreads in set literals. In most cases that is unproblematic,
but it does introduce more ambiguous cases than the empty no-type-parameter literal `{}`.
An expression of the form `{... someExpression}` is grammatically valid as both a set literal and a map literal.
(The grammar will obviously need to be changed to allow this, and in that case, such literals will be
an extension of the `emptySetOrMapLiteral` category).

there are several ways to disambiguate such an expression where there is no useful context type,
no type parameters, no non-spread element/entry in the literal, and it's not empty (so there is at least one spread).
One likely candidate is:

* Find the static type of each spread expression. (Since the context type of the literal itself does not require
  either a set or a map, and exact types prevents it from requiring any sub-type that is both, the context type
  of the literal provides no context type for the spread expressions).
* If all these static types are assignable to `Set<Object>`
  and not all of them are assignable to `Map<Object, Object>`, then the literal is a set literal.
* If all these static types are assignable to `Map<Object, Object>`
  and not all of them are assignable to `Set<Object>`, then the literal is a map literal.
* Otherwise it's a compile-time error.

In this case, any unresolvable ambiguity is detected early and the programmer is notified.
For examples like `{...e1, ...e2}` where both `e1` and `e2` has type `dynamic`,
we could guess that it should be a map, but we could just as easily be wrong,
and the user would only find out when the code fails at run-time.
It's better to fail early, so the user can safely assume that if the code compiles at all,
it most likely does what they expect.

When we have decided whether it's a set or a map literal,
we perform normal upwards type inference to deduce the type argument(s) to `Set` or `Map`,
based on the static types of the spread expressions.

The *empty* literal case still has to default to a map literal for backwards compatibility.

Since we have no context type for the spread expressions, we can get into situations like:
```dart
var x = { ...{}};
```
Because the spread expression is an empty set-or-map literal with no hints, it will default to a map literal.
That forces the outer literal to be a map literal.
If you do:
```dart
var x = {...{1}, ...{}};
```
you will have a conflict because the static type of the individual spreads are found independently,
and with no hint, the latter spread expression is a map, where the former is a set.
Even if this could have been valid if we had guessed that it should be a set literal, we won't detect that.
That's not special to spread expressions, you can get the same effect from:
```dart
void foo<T>(T x, T y) {}
foo({1}, {});
```

In any case, this needs to be finalized if/when we introduce literal spreads.

## Summary
Set literals use `{` and `}` as delimiters, allows a single type argument, and has comma-separated expressions for elements.

This syntax is distinct from map literal syntax (two type arguments, colon-pairs as elements) except for the no-type-argument empty literal `{}`.
In that case, we make it a set if the context type allows a set, and it does not allow a map, otherwise we make it a map.

Type inference works just as for list literals,
and the literal has an "exact" type of `Set<E>`.

The meaning of a set `<E>{e1, ..., en}` is a set with the same elements and iteration order as `new Set<E>()..add(e1) ... ..add(en)`.

Const set literals are allowed. Elements need to satisfy the same requirements as constant map keys (not overriding `Object.==` unless it's an integer, string or `Symbol`).

Adding set literals like this will not change any existing compilable program,
since the new syntax is either not allowed by the existing grammar, or it is rejected by the static type system.

## Examples
```dart
/*
context                  expression            runtime type and const-ness
*/
var v1                 = {};                // LinkedHashMap<dynamic, dynamic>
var v2                 = <int, int>{};      // LinkedHashMap<int, int>
var v3                 = <int>{};           // LinkedHashSet<int>
var v4                 = {1: 1};            // LinkedHashMap<int, int>
var v5                 = {1};               // LinkedHashSet<int>

Iterable<int> v6       = {};                // LinkedHashSet<int>
Map<int, int> v7       = {};                // LinkedHashMap<int, int>
Object v8              = {};                // LinkedHashMap<dynamic, dynamic>
Iterable<num> v9       = {1};               // LinkedHashSet<num>
Iterable<num> v10      = <int>{};           // LinkedHashSet<int>
Set<int> v11           = {};                // LinkedHashSet<int>

const v12              = {};                // const Map<dynamic, dynamic>
const v13              = {1};               // const Set<int>
const Set v14          = {};                // const Set<dynamic>
Set v15                = const {4};         // const Set<dynamic>

// Compile-time error, overrides `==`.
// const _             = {Duration(seconds: 1)};
// const _             = {2.3};

var v16                = {1, 2, 3, 2, 1};   // LinkedHashSet<int>
var l16                = v16.toList();        // -> <int>[1, 2, 3]
// Compile-time error, contains equal elements
// const _             = {1, 2, 3, 2, 1};

FutureOr<Iterable<int>> v17 = {};           // LinkedHashSet<int>
var l18                = const {1, 2};      // const Set<int>

// Class overriding `==`.
class C {
  final int id;
  final String name;
  C(this.id, this.name);
  int get hashCode => id;
  bool operator==(Object other) => other is C && id == other.id;
  String toString() => "C($id, $name)";
}

// First equal object wins.
var v19                = {C(1, "a"), C(2, "a"), C(1, "b")};  // LinkedHashSet<C>
print(v19);  // {C(1, "a"), C(2, "a")}

const v20              = {1, 2, 3};        // const Set<int>
const v21              = {3, 2, 1};        // const Set<int>
print(identical(v20, v21));                // -> false

// Type can be computed from element types.
var v23                = {1, 2.5};         // LinkedHashSet<num>
var v24                = {1, false};       // LinkedHashSet<Object>
const v26              = {1, false};       // const Set<Object>
```

### With Spreads
```dart
var s1                 = {...[1]};          // Set<int>
var s2                 = {...{1}};          // Set<int>
var s3                 = {...{1: 1}};       // Map<int, int>
var s4                 = {...{}};           // Map<dynamic, dynamic>
dynamic d = null; // or any value.
var s5                 = {...{1}, ...?d};    // Set<dynamic>
var s6                 = {...{1: 1}, ...?d}; // Map<dynamic, dynamic>
// var s7              = {...?d};            // Compile-time error, ambiguous
// var s8              = {...{1}, ...{1: 1}};  // Compile-time error, incompatible
```

## Revisions
1.0: Initial version plus type fixes.

1.1: Changed type rules for selecting set literals over map literals.

1.2: Changed type rules again.
