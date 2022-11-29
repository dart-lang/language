# Dart Nominal Union Types

Author: lrn@google.com<br>Version: 0.5

Dart has two structural union type constructs, `FutureOr` and `_?`.
Adding union types to the language is a long-standing request. However, general union types, likely with accompanying intersection types (the two are hard to separate because of contravariance), is a very complicated feature to add to a type system. The subtyping rules get more complicated. The least-upper-bound computation gets trivialized (and not in a good way) when any two types has their union as the least upper bound.

This is a proposal for *limited* union types. The limit is that the union type is made *nominal*, it is a new type which is only a subtype of `Object` or `Object?`, it’s not assignable to any other type, including other union types, unless explicitly made a subtype of another union type.

## Proposal

### Syntax (strawman)

A union type declaration has a form like:

```dart
typedef F<T> = A | B | C<T>;
```

(We just add `('|' type)*` to the end of the new `typedef` syntax.)

When used with multiple types, it introduces a new nominal type (which is why the use of `typedef` may be a bad idea, but let’s keep it as a strawman).

### Semantics

#### Static

##### New type, subtyping

A declaration `typedef F<X1 extend B1, Xn extends Bn> = T1 | .. | Tn;` introduces a new nominal type `F`.

The type `F` is, trivially, a supertype of `Never` and a subtype of `Object?`, and a super/sub-type of itself (subtying is reflexive).

It’s a subtype of `Object` if all the elements types are subtypes of `Object`. _(We say that the union types itself is nullable or non-nullable in those cases.)_

If `F` is nullable, then `F?` is equivalent to `F` (mutual subtypes), otherwise `F?` is a proper supertype of `F`.

The type is a supertype of each of its union element types (`Foo` is a supertype of `A` and `B` here.).

If the union type is generic, different instantiations can be subtypes of each other. The type parameters vary by their occurrences, like for a type alias. For example `typedef Foo<T> = T Function(int) | int Function(T);` is invariant in `T` because `T` occurs both covariantly and contravariantly in the union element types. _(This might need us to introduce variance first.)_. For `typedef G<X> = List<X> | Set<X>;`, `G<int>` is a subtype of `G<num>`, because `X` occurs only covariantly, so `G` varies covariantly with `X`. _A direct use of the type variable, like `typedef U<S, T> = S | T;` counts as covariant._

Union types are not *structural*, so `typedef F1 = A | B;` and `typedef F2 = A | B;` introduces two *different and unrelated* supertypes of `A` and `B`.

The union type has *no members* other than those shared by `Object` and `Null`.

##### No cycles

A union type should not be an element of itself. Further, checking whether a value is a valid member of the union type should also not recursively require checking the same value against the same union type again.

It’s a compile time error if it’s possible to reach the declaration of a union type from itself by a sequence of the following steps, starting with the type’s own declaration (instantiated with fresh type variables if the declaration is generic):

* Given a type expression *T*.
  * If *T* is one of the fresh type variables introduced above, stop.
  * If *T* is a function type, a record type or any of the types `void`, `dynamic` or `Never`, stop.
  * Otherwise *T* is of the form `B<typeArgumentsOpt>`.
  * If `B` denotes a class or mixin declaration, stop.
  * If `B` denotes a type alias declaration, instantiate the declaration with provided type arguments, if available, otherwise to bounds, and use the alias’ type as a new type `S`.
  * If `B` denotes a union type declaration, instantiate the declaration with provided type arguments, if available, otherwise to bounds, then choose any one of the union element types of the declaration as a new type `S`.
  * If `B` denotes an inline class declaration, instantiate the declaration with provided type arguments, if available, otherwise to bounds, then use the representation type of that inline class as a new type `S`.
* Then repeat with `T` being  `S` .

If a union type is reachable from itself using such steps, then doing `is UnionType` will always transitively end up doing `is UnionType` on the same value again. We want to avoid that.

This detects and prohibits cyclic definitions, after expanding type aliases. It disallows `typedef Foo = Foo | Bar;`, `typedef F1 = F2 | int; typdef F2 = F1 | int` and `typedef U<S, T> = S | T; typedef Foo = U<Foo, int> | int;`. Implementations are free to detect the same cycles in a more efficient way. 

This check is entirely *structural*. It can be performed before type inference, since it relies only on resolving identifiers to declarations, and substituting type arguments into types. It ensures that we can always expand a union type to a finite collection of non-union types in a finite number of steps, such that `is UnionType` can be decided by doing `is X` on each of the types in that collection. _(That’s why we need to expand inline classes to their representation type, because `is InlineClass` is implemented as `is RepresentationType`.)_

It’s still possible to make a union type nested inside itself dynamically, as:

```dart
typedef U<S, T> = S | T;
void main() {
  U<U<int, bool>, String> x;
}
```

However, this is only iterative, not recursive, which ensures that we can always keep expanding union types until we end up with a set of non-union types that are subtypes of the union type.

##### Type inference

For most purposes, the new type is just a plain type, with specific subtype relations.

If the union type is nullable, then `Foo?` is equivalent to `Foo`, and **NORM** will reflect that and remove the `?`.

Promotion happens normally on type checks of subtypes.

An expression of the form `e as Foo` or `e is Foo` work as normal. It can promote from `Object?`, or any supertype, to `Foo`.

Likewise `Foo x = …; if (x is A) …` can promote from `Foo` to `A`. This is one way to extract a useful value from a union type. So is an `as` cast if you happen to know which subtype it is.

Pattern matching also works: `switch (someFoo) { case A a: … case B b: ….}` can destructure `Foo`. The switch is exhaustive if the type checks cover all the union subtypes (each subtype would be exhausted by the cases of the switch). _For switch exhaustiveness, a union type is like a `sealed class` with the explicitly listed subtypes._

A union type is never the result of a least-upper-bound computation unless at one of its operands is that union type (and it’s a supertype of all the other types). _Union types have no link *from* their subtypes to the union type, and a single type can be a member of any number of union types. We never try to guess a union-super-type of a type._

You cannot implement, extend or mix-in a union type. You *can* declare extension methods on it (it’s a type), and you *can* declare inline classes with a union type as representation type.

##### Summary

Given `typedef F<T> = A | B | C<T>;`, the type `F<T>` is a supertype of `A`, `B` , `C<T>`. That means:

* `List<F> list = <B>[B(), B()];` is valid. A `List<B>` is-a `List<F>`.

* And `F f = B();` is allowed.

* You can also *cast* to `F`, as `B() as F`. This checks whether the value is accepted by *any* of the union types (which can be a trivial check if the static type guarantees the result.)

* Similarly `e is F` checks whether the value of `e` is accepted by any of  `is A`, `is B`, `is C`, …

* You can include one union type in another:

  ```dart
  typedef JsonPrimitive = num | bool | String | Null;
  typedef Json = JsonPrimitive | List<Json> | Map<String, Json>;
  ```

  The subtyping is transitive in this case, `num` is a subtype if `Json`, and `JsonPrimitive` itself is also a subtype of `Json`.

* Union types can be indirectly recursive, as shown above. They can refer to themselves in type arguments, or function return/parameter types, but cannot be directly recursive. Something like `typedef Foo = Foo | Bar;` is *not* valid. _It should always be possible to expand each union element type to an actual non-union type, without cyclic dependencies.

* Generic union types can refer to type parameters, also as top-level types, like `typedef U<S, T> = S | T;`. 

#### Runtime

When a subtype check is needed, whether for `e is Foo`, `e as Foo`, `try { … } on Foo { … }`, `e is List<Foo>`, or any other runtime type check against a union type, the proposed subtype is checked against *every* element type of the union to see if it is a subtype, in the source order of the declaration (presumably, it should be impossible to tell which order, so a compiler can optimize when possible).

In every other way, the union type is just a normal type, with the subtype relationships defined above. The union type has no other purpose than allow multiple types being treated as one.

## Limitations and discussions

### Incompatible with existing `dynamic`-using types

This does not allow having a simple type alias for existing JSON values,

```dart
typedef Json = int | bool | String | Null| List<Json> | Map<String, Json>;
```

and casting existing JSON structures to it, because you can’t cast a `Map<String, dynamic>` to `Json`. It would require the JSON parser to generate a `Map<String, Json>` to start with. Then it *would* work.

### No members on the type

We could allow the union type to declare members. The union type is a new (static) type for an existing value, just like an inline class. We could allow declaring members on union type as well. We’d probably want a different syntax then, because

```dart
typedef Foo = A | B | C {
  int get kind => this is A ? 1 : this is B ? 2 : 3;
}
```

looks weird. Something like:

```dart
union Foo implements A | B | C {
  int get kind => this is A ? 1 : this is B ? 2 : 3; 
}
```

might look better. (Definitely work to do.)

### No intersection types

Because the union types have no members, other than those of `Object`, we don’t have to worry about how two semi-compatible members would combine.

In a design where we allow common supertypes of the union element types to also be supertypes of the union type itself, we would assume the API of those supertypes to be available on the union type.

Take:

```dart
class B<T> {
  T foo(T x) => x;  
}
class C extends B<int> {}
class D extends B<double> {}
typedef U = C | D;
void main() {
  U x = ...;
  ? r = x.foo(?);
}
```

What would the valid arguments to `U.foo` be, and what does it return?
(This is actually getting us into a situation where a value can possibly implement the generic `B` with two different type arguments, which we wouldn’t allow normally, but here we know that it’s at most one of them at a time.)
The usual solution would be making the return type of `U.foo` the union type of the individual return types, and the argument type the intersection types of the individual argument types, so `(int | double) foo((int & double) x)`. We cannot do that, either of them, because union types being nominal means we can’t synthesize `(int | double)` without a declaration for it. We also don’t want to.

So, having no members means we don’t need intersection types for the usual reasons.

Do we want them? Would `typedef FooBar = Foo & Bar;` defining a nominative supertype of all types that implement both `Foo` and `Bar` make sense? Probably not, because again it wouldn’t be able to have any members, and that’s really the most important part when it comes to intersection types.

### What about `FutureOr`?

The above specification was not written with `FutureOr` in mind. It would be *nice* if we could change the declaration of `FutureOr` to

```dart
typedef FutureOr<T> = Future<T> | T;
```

That would *mostly* work the same as today. It’s a supertype of `Future<T>` and `T`. It’s nullable if `T` is nullable. Where it differs is in `FutureOr<Future<Object>>`, which is currently equivalent to `Future<Object>` because `Future<Object>` is a supertype of both `Future<Object>` and `Future<Future<Object>>`, and we say that any supertype of both types of a union is a subtype of the union.

With the defined subtyping above for nominative union types, the only supertype of `FutureOr<T>` would be `Object?`, and `Object` if `T` is non-nullable.

It’s probably not a difference which is important in practice.

It’s possibly a *better* behavior than the current one. You should never need to assign a `FutureOr<Future<Object>>` directly to a `Future<Object>`, not without first checking if it’s a `Future<Future<Object>>`. (It won’t change that all the values of `FutureOr<Future<Object>>` satisfy `is Future<Object>`, but the union type doesn’t forget that it’s a union type.)

### What about nullable types?

Can we do the same to nullable types? Introduce:

```dart
typedef Nullable<T> = T | Null;
```

with `int?` being shorthand for `Nullable<int>`?

Both `T` and `Null` are subtypes of `Nullable<T>`. It’s covariant, so `Nullable<int>` is a subtype of `Nullable<num>`. 

Where it breaks down is that the types `Nullable<Null>` and `Nullable<Never>` are *not* equivalent to `Null`. They are new types.

Likewise `Nullable<dynamic>` is a new types, not `dynamic` again.

That’s probably a bigger problem than for `FutureOr`, because we really want to normalize away types like  `Null?`. We can still do that using `NORM`.

The alternative would be to introduce a rule, that if one of the union element types is a supertype of all the rest, then the union type is equivalent to that type (both super and subtype). I fear that might degenerate the type in some unpredictable places, and remove some of the advantage of introducing new nominative types. Then we might as well just go back to saying that a union type is a subtype of any type that all element types are subtypes of.

## Versions

* 0.5 - initial version 
