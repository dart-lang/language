# Set Literals Proposal
Author: lrn@google.com
Status: Superseded by [design document](https://github.com/dart-lang/language/blob/master/accepted/2.2/set-literals/feature-specification.md) and language specification.

Proposed solution for [Set Literals Problem](http://github.com/dart-lang/language/issues/36).
Discussion about his proposal should go in [Issue 37](http://github.com/dart-lang/language/issues/37)

## Background

Dart has `List` and `Map` literals, but no `Set` literal.
The obvious syntactic choice would be to use curly-braces, like in mathematical set notation, and it is almost without problems. 
The only case needing special handling is that the empty set literal with no type argument (`{}`) 
which is indistinguishable from an empty map literal with no type arguments, and we don't want to break existing uses of that. 
As disambiguation, we will allow the interpretation of that literal to depend on the expected type of the expression.

## Proposal
Change the grammar from:
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
    mapLiteral | 
    setLiteral |
    setOrMapLiteral |
    listLiteral

mapLiteral: 
    'const'?  ('<' type ',' type '>')?  '{' mapLiteralEntry (',' mapLiteralEntry)* ','? '}' |
    'const'?  ('<' type ',' type '>') '{' '}'
setLiteral: 
    'const'?  ('<' type '>')? '{' expression (',' expression)* ','? '}' |
    'const'?  ('<' type '>') '{' '}'
setOrMapLiteral: 
    'const'?  '{' '}' 
```    
This grammar is still syntactically unambiguous 
(and the rule that an expression statement cannot start with a `{` now covers both map and set literals).

The ambiguity is in the *meaning* of `{}` or `const {}`, which will be decided during type inference.

If a literal has an explicit type parameter, there is no ambiguity: one parameter for sets, two for maps. 
If it contains any elements or entries, there is no ambiguity: 
sets elements are single expressions, map entries are colon-separated expressions. 

The proposed grammar no longer allows a `Map` literal with a *typeArguments* with fewer or more than two types. 
That is not allowed by Dart anyway, so enshrining it in the grammar is not a restriction in practice.
It is currently a prose-specified compile-time error for a map literal to have fewer or more than two type arguments, 
and this is really just a left-over from Dart 1 where it was only a warning, 
and to make the specification easier to write by resuing the *typeArguments* production.

As an alternative grammar, we could keep using *typeArguments* 
and let the actual number of arguments be used to decide whether `<...>{}` is a `Set` or `Map` literal, 
or just an error if there are more than two type arguments.
If it makes the specification easier to write, we will just do so, the end result (the allowed programs) won't change.
The grammar would then be:

```
mapLiteral: 
    'const'?  typeArguments?  '{' mapLiteralEntry (',' mapLiteralEntry)* ','? '}'
setLiteral: 
    'const'?  typeArguments? '{' expression (',' expression)* ','? '}'
setOrMapLiteral: 
    'const'? typeArguments? '{' '}' 
```
and it's a compile-time error if a *setLiteral* has more than one type argument,
or if a *mapLiteral* has a number of type arguments other than two.

### Meaning of empty map/set literal.

If the static context type of a literal `{}` or `const {}` (a *setOrMapLiteral*) expression allows a `Set` type 
(`Set<Null>` is assignable to the context type), but does not allow a `Map` type 
(`Map<Null, Null>` is not assignable to the context type), then the literal is interpreted as a set literal.
In all other cases, including where there is no context type, the literal is interpreted as a map literal.

If we use *typeArguments*, then a *setOrMapLiteral* is a set literal if it has one type argument, 
a map literal if it has two type arguments, a compile-time error if it has more than two type arguments,
and treated as above if it has no type arguments.

### Type inference for non-empty sets.

Currently we infer type arguments of a map or list literal if they are omitted.
We do that by using the context type, or if that does not say anything about the type arguments 
(for example if the context type is `Object`), then the type argument is inferred from the entries of the map
or the elements of the list.

The type arguments of set literals are inferred in exactly the same way as for list literals.

### Exact types of literals

Currently, the Dart 2 type inference inferes an "exact type" for map literals,
either `Map<K, V>` for const literals or `LinkedHashMap<K, V>` for non-constant literals.
The inferred exact type makes it a compile-time error to require a down-cast,
since that down-cast is known to fail at runtime.
Likewise, it should infer exact types `Set<E>` for constant set literals
and `LinkedHashSet<E>` for non-constant set literals.

### Run-time Semantics.
The run-time value of a non-const set literal is a `LinkedHashSet` with the same elements and iteration order
as the set you would get by creating a new `LinkedHashSet` and adding the elements one by one.
That is `<int>{1, 3, 2}` evaluates to a set with the same values and iteration order as 
`LinkedHashSet<int>()..add(1)..add(3)..add(2)`.

### Const Set Literals
The grammar allows const set literals. 
These have similar constraints to compile-time constant list and map literals:

* The type argument must be a compile-time constant type.
* The element expressions must be constant expressions.
* The element values must satisfy the same constraints as constant map keys. 
  They must either be on the short list of system types that we know how to handle at compile-time,
  or be instances of classes that haven't overridden `operator==` from the `Object` class.
  
The constraint on the set elements allows us to recognize equality at compile-time without needing to run user-code 
(equality is either identity or something we are in control of).

The inference of whether the empty literal is a set or a map is unaffected by being const, 
the type parameter inference works the same way as for constant lists 
(including inferring `const<Null>{}` in some cases where the context type contains a type variable).

The run-time value for a constant `Set` literal is an unmodifiable `Set` with an equality that is compatible with 
the compile-time constant equality of the objects, and which iterates the elements in source order. 

## Migration

There is no change to existing valid programs. No programs need to be migrated.

If an API wants to change to accept a `Set`, that API needs to migrate its users.

## Implementation

Implementation can follow the same design as for map literals, 
with a private implementation class for constant sets. 
Each back-end will need to implement this independently.

Alternatively, or as a transition, the front-end can desugar non-constant set literals into expressions like 
`LinkedHashSet<type>..add(e1)..add(e2)`, 
and constant set literals into wrapped constant maps, so `const <type>{e1, e2, e3}` becomes:
```dart
const _$e1 = e1;
const _$e2 = e2;
const _$e3 = e3;
...
const _ImmutableSetWrapper<type>(<type, type>{_$e1: _$e1, _$e2: _$e2, _$e3: _$e3}) 
The _ImmutableSetWrapper would just be:
class _ImmutableSetWrapper<E> extends SetBase<E> {
  final Map<E, E> _map;
  const _ImmutableSetWrapper(this._map);
  bool contains(Object element) => _map.containsKey(element);
  int get length => _map.length;
  E lookup(Object object) => _map[object];
  Iterator<E> get iterator => _map.keys.iterator;
  Set<E> toSet() => _map.keys.toSet();
  bool add(E element) { _unmodifiable(); }
  bool remove(Object value) { _unmodifiable(); }
  void clear() { _unmodifiable(); }
  void bool addAll(E element) { _unmodifiable(); }
  void bool removeAll(Iterable<Object> elements) { _unmodifiable(); }
  void bool retainAll(Iterable<Object> elements) { _unmodifiable(); }
  void removeWhere(bool test(E element)) { _unmodifiable(); }
  void retainWhere(bool test(E element)) { _unmodifiable(); }
  static void _unmodifiable() { 
      throw new UnsupportedError("Constants sets are immutable"); 
  }
}
```
Such a transformation would allow backends to delay their (hopefully better optimized) implementation
of constant sets and would make set literals a front-end only feature. 
If at all possible, back-ends should have an optimized implementation of constant sets from the start,
anything else will negatively affect the adoption of the new feature.

## Concerns
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
and as a conditional operator including the `:`. (That is, we don't need to see the `:` to know how to parse the `?`).

However, adding `Set` literals specified this way will preclude any *future* syntax 
that allows an expression to start with `.` or `?` (or at least require extra disambiguation complexity at that point).
This includes some ideas for arrow-less function shorthands, e.g., `.foo(2)` as shorthand for `(x)=>x.foo(2)`,
or shorthand syntax for accessing enum instances like `Color c = test ? .red : .blue;`. 
Likewise it precludes adding new null-aware operators that can also be seen as two expressions separated by `?`, 
like a null-aware index operator `x?[4]` since `{x?[4]:5}` would then be ambigDo we have to?uous.

These concerns are speculative. 
We are unlikely to add such syntax since it would be hard to distinguish from existing uses of `?`
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

If we add this restriction, we need do so from the start, it will be a breaking change to add it later.

## Future Feature Compatibility
### Collection Spreads
"Collection spreads" is one potential future language feature, which is already being discussed, 
and which overlaps with set literals.
Collection spreads allow you to write `[1, ...iterableExpression, 3]` as a list literal, and it will evaluate `iterableExpression`, then iterate it and insert every element of the iterable in the resulting list. 
Similarly you can write `{1: 1, ...mapExpression, 3: 42}` to expand the entries of a map into another map literal.

We should also accept spreads in set literals. In most cases that is unproblematic, 
but it does introduce more ambiguous cases than the empty no-type-parameter literal `{}`.
An expression of the form `{... someExpression}` is gramatically valid as both a set literal and a map literal.
(The grammar will obviously need to be changed to allow this, and in that case, literals with only spreds
will all go in the `setOrMapLiteral` category).

To disambiguate such an expression, there are several options. 
This document proposes the following disambiguation rule for the case where there is no useful context type,
no type parameters, no non-spread element/entry in the literal, and it's not empty (so there is at least one spread):

* Find the static type of each spread expression. (Since the context type of the literal itself does not require 
  either a set or a map, and excact types prevents it from requiring any sub-type that is both, the context type
  of the literal provides no context type for the spread expressions).
* If all these static types are assignable to `Iterable<Object>` 
  and not all of them are assignable to `Map<Object, Object>`, then the literal is a set literal.
* If all these static types are assignable to `Map<Object, Object>` 
  and not all of them are assignable to `Iterable<Object>`, then the literal is a map literal.
* Otherwise it's a compile-time error.

In this case, any unresolvable ambigity is detected early and the programmer is notified.
For examples like `{...e1, ...e2}` where both `e1` and `e2` has type `dynamic`, 
we could guess that it should be a map, but we could just as easily be wrong, 
and the user would only find out when the code fails at run-time. 
It's better to fail early, so the user can safely assume that if the code compiles at all, 
it most likely does what they expect.

When we have decided whether it's a set or a map literal, 
we perform normal upwards type inference to deduce the type argument(s) to `Set` or `Map`,
based on the static types of the spread expressions.


The empty literal case still has to default to a map literal for backwards compatibility. 

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


## Examples
```dart
var v1                 = {};                // Empty Map<dynamic, dynamic>
var v2                 = <int, int>{};      // Empty Map<int, int>
var v3                 = <int>{};           // Empty Set<int>
var v4                 = {1: 1};            // Map<int, int>
var v5                 = {1};               // Set<int>

Iterable<int> v6       = {};                // Set<int>
Map<int, int> v7       = {};                // Map<int, int>
Object v8              = {};                // Map<dynamic, dynamic>
Iterable<num> v9       = {1};               // Set<num>
Iterable<num> v10      = <int>{};           // Set<int>
LinkedHashSet<int> v11 = {};                // Set<int>

const v12              = {};                // const Map<dynamic, dynamic>
const v13              = {1};               // const Set<int>
const Set v14          = {}                 // const Set<dynamic>

// Compile-time error, overrides `==`.
// const v15           = {Duration(seconds: 1)};
```

### With Spreads
```dart
var v16                = {...[1]};          // Set<int>
var v17                = {...{1}};          // Set<int>
var v18                = {...{1: 1}};       // Map<int, int>
var v19                = {...{}};           // Map<dynamic, dynamic>
dynamic d = null; // or any value.
var v20                = {...{1}, ...d}     // Set<dynamic>
var v21                = {...{1: 1}, ...d}  // Map<dynamic, dynamic>
// var v22             = {...d};            // Compile-time error, ambiguous
// var v23             = {...{1}, ...{1: 1}};  // Compile-time error, incompatible
```
