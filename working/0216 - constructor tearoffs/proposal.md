# Dart Constructor Tear-offs

Author: lrn@google.com<br>Version: 2.4

Dart allows you to tear off (aka. closurize) methods instead of just calling them. It does not allow you to tear off *constructors*, even though they are just as callable as methods (and for factory methods, the distinction is mainly philosophical).

It's an annoying shortcoming. We want to allow constructors to be torn off, and users have requested it repeatedly ([#216](https://github.com/dart-lang/language/issues/216), [#1429](https://github.com/dart-lang/language/issues/1429)).

This is a proposal for constructor tear-offs which introduces new syntax for the unnamed constructor, for constructor tear-offs, and for explicit instantiation of generic functions tear-offs in general.

## Goal

The goal is that you can always tear off a constructor, then invoke the torn off function and get the same result as invoking the constructor directly. For a named constructor it means that

```dart
var v1 = C.name(args);
var v2 = (C.name)(args);

// and 

var v3 = C<typeArgs>.name(args);
var v4 = (C<typeArgs>.name)(args);
var v5 = (C.name)<typeArgs>(args);
```

should always give equivalent values for `v1` and `v2`, and for `v3`, `v4` and `v5`.

We also want a consistent and useful *identity* and *equality* of the torn off functions, with the tear-off expression being a constant expression where possible. It should match what we already do for static function tear-off where that makes sense. 

## Proposal

### Named constructor tear-off

We allow tearing off named constructors.

If *C* denotes a class declaration and *C.name* is the name of a constructor of that class, we allow you to tear off that constructors as:

* <code>*C*.*name*</code>, or
* <code>*C*\<*typeArgs*>.*name*</code>

just as you can currently invoke the constructor as <code>*C*.*name*(*args*)</code>, or <code>*C*\<*typeArgs*>.*name*(*args*)</code>.

_The former syntax, without type arguments, is currently allowed by the language grammar, but is rejected by the static semantics as not being a valid expression. The latter syntax is not currently grammatically an expression. Both can occur as part of a_ constructor invocation_, but cannot be expressions by themselves because they have no values. We introduce a static and dynamic expression semantic for such a *named constructor tear-off expression*._

A named constructor tear-off expression of one of the forms above evaluates to a function value which could be created by tearing off a *corresponding constructor function*, which would be a static function defined on the class denoted by *C*, with a fresh name here represented by adding `$tearoff`:

> <code>static *C* *name*$tearoff\<*typeParams*>(*params*) => *C*\<*typeArgs*>.*name*(*args*);</code>

If *C* is not generic, then <code>\<*typeParams*\></code> and <code>\<*typeArgs*\></code> are omitted. Otherwise <code>\<*typeParams*\></code> are exactly the same type parameters as those of the class declaration of *C* (including bounds), and <code>\<*typeArgs*></code> applies those type parameter variables directly as type arguments to *C*.

Similarly, <code>*params*</code> is *almost* exactly the same parameter list as the constructor *C*.*name*, with the one exception that *initializing formals* are represented by normal parameters with the same name and type. All remaining properties of the parameters are the same as for the corresponding constructor parameter, including any default values, and *args* is an argument list passing those parameters to `C.name` directly as they are received. 

For example, `Uri.http` evaluates to an expression which could have been created by tearing off a corresponding static function declaration:

```dart
static Uri http$tearoff(String authority, String unencodedPath, [Map<String, dynamic>? queryParameters]) => 
    Uri.http(authority, unencodedPath, queryParameters);
```

and a constructor of a generic class, like `List.filled`, would be:

```6dart
static List<E> filled$tearoff<E>(int count, E fill) => List<E>.filled(count, fill);
```

When tearing off a *constructor of a generic class* using <code>*C*.*name*</code>, the type arguments may be implicitly instantiated, just as for a normal generic method tear-off of the corresponding static function. The instantiation is based on the context-type at the tear-off position. If the context types allows a generic function, the tear-off is not instantiated and the result is a generic function.

When tearing off a constructor of a generic class using <code>*C*\<*typeArgs*>.*name*</code>, the torn off method is *always* instantiated to the provided type arguments (which must be valid type arguments for the class/corresponding function). It otherwise behaves as an implicitly instantiated function tear-off.

The constant-ness, identity and equality of the torn-off constructor functions behave exactly the same as if they were tear-offs of the corresponding static function. This means that a non-generic class constructor always tears off to the *same* function value, as does an uninstantiated tear off of a generic class constructor. An instantiated tear-off is constant and canonicalized if the instantiating types are constant, and not even equal if they are not.

The static type of the named constructor tear-off expression is the same as the static type of the corresponding constructor function tear-off.

This introduces an **ambiguity** in the grammar. If `List.filled` is a valid expression, then `List.filled(4, 4)` can both be a constructor invocation *and* a tear-off followed by a function invocation. We only allow the constructor invocation when it's not followed by a *typeArguments* or *arguments* production (or, possibly, when it's not followed by a `<` or `(` character). _We don't want to allow `List.filled<int>` to be interpreted as `(List.filled)<int>`. Just write the `List<int>.filled` to begin with!_

#### Tearing off constructors from type aliases

*With generalized type-aliases*, it's possible to declare a class-alias like `typedef IntList = List<int>;`. We allow calling constructors on such a type alias, so we will also allow tearing off such a constructor. 

In general, a *non-generic* type alias is just expanded to its aliased type, then the tear-off happens on that type. Tearing off `IntList.filled` will act like tearing off `List<int>.filled`, it automatically instantiates the class type parameter to the specified type. It's constant and canonicalized to the same function as `List<int>.filled`. _In other words, the alias is treated as an actual alias for the type it aliases._

This differs for a *generic* type alias. If the type alias is *instantiated* (implicitly or explicitly), then the result is still the same as tearing off the aliased type directly, and it's constant and canonicalized if the type arguments are constant.

If the type alias is *not* instantiated, then it's a function from types to types, not an alias for a single type, and tearing off a constructor works equivalently to tearing off a corresponding generic function where the generics match the *type alias*, not the underlying class. The result is a compile-time constant.

Example:

```dart
typedef ListList<T> = List<List<T>>;
// Corresponding factory function
List<List<T>> ListList$filled$tearoff<T>(int length, List<T> value) => List<List<T>>.filled(length, value);
```

Example:

```dart
typedef MyList<T> = List<T>;
typedef MyList2<T extends num> = List<T>;
void main() {
  // Instantiated type aliases use the aliased type.
  print(identical(MyList<int>.filled, MyList2<int>.filled)); // true
  print(identical(MyList<int>.filled, List<int>.filled)); // true
  print(identical(MyList2<int>.filled, List<int>.filled)); // true
  // Non-instantiated type aliases have their own generic function.
  print(identical(MyList.filled, MyList.filled)); // true
  print(identical(MyList2.filled, MyList2.filled)); // true
  print(identical(MyList.filled, MyList2.filled)); // false
  print(identical(MyList.filled, List.filled)); // false (!)
}
```

We do not try to distinguish the cases where the type arguments are passed directly to the original class in the same order vs. those where they are modified along the way.

### Unnamed constructor tear-off

If *C* denotes a class, an expression of *C* by itself already has a meaning, it evaluates to a `Type` object representing the class, so it cannot also denote the unnamed constructor.

Because of that, we introduce a *new* syntax that can be used to denote the unnamed constructor: <code>*C*.new</code>. It can be used in every place where a named constructor can be referenced, but will instead denote the unnamed constructor, *and* it can be used to tear off the unnamed constructor without interfering with using the class name to denote the `Type` object.

```dart
class C {
  final int x;
  const C.new(this.x); // declaration.
}
class D extend C {
  D(int x) : super.new(x * 2); // super constructor reference.
}
void main() {
  D.new(1); // normal invocation.
  const C.new(1); // const invocation.
  new C.new(1); // explicit new invocation.
  var f = C.new; // tear-off.
  f(1);
}
```

Apart from the tear-off, this code will mean exactly the same thing as the same code without the `.new`. The tear-off cannot be performed without the `.new` because that expression already means something else.

*With regard to tear-offs, <code>C.new</code> works exactly as if it had been a named constructor, with a corresponding constructor function named <code>C.new$tearoff</code>.*

We probably want to support `[C.new]` as a constructor link in DartDoc as well. In `dart:mirrors`, the name of the constructor is still just `C`, not `C.new` (that's not a valid symbol, and we don't want to break existing reflection using code).

The grammar will be changed to allow ``<identifier> |`new'`` anywhere we currently denote a named constructor name, and we make it a primary expression to tear-off an unnamed constructor as `classRef.new`.

### Explicitly instantiated classes and function tear-offs

The above allows you to explicitly instantiate a constructor tear-off as `List<int>.filled`. We do not have a similar ability to explicitly instantiate function tear-offs. Currently you have to provide a context type and rely on implicit instantiation if you want to tear off an instantiated version of a generic function. 

We can also use type aliases to define instantiated interface types, but we cannot do the same thing in-line.

Example:

```dart
T id<T>(T value) => value;
int Function(int) idInt = id; // Implicitly instantiated tear-off.

typedef IntList = List<int>;
Type intList = IntList;
```

We will introduce syntax allowing you to explicitly instantiate a function tear-off and a type literal for a generic class. The former for consistency with constructor tear-offs, the latter to introduce in-line types without needing a `typedef`, like we did for function types. And we do both now because they share the same grammar productions.

Example:

```dart
T id<T>(T value) => value;
var idInt = id<int>; // Explicitly instantiated tear-off, saves on writing function types.
// and
Type intList = List<int>; // In-line instantiated type literal.
```

These grammar changes allows *type parameters* without following parenthesized arguments in places where we previously did not allow them. For example, this means that `<typeArguments>` becomes a *selector* by itself, not just followed by arguments.

The static type of the explicitly instantiated tear-offs are the same as if the type parameter had been inferred, but no longer depends on the context type.

The static type of the instantiated type literal is `Type`. This also satisfies issue [#123](https://github.com/dart-lang/language/issues/123). 

We **do not allow** *dynamic* explicit instantiation. If an expression `e` has type `dynamic` (or `Never`), then `e.foo<int>` is a compile-time error for any name `foo`. (It'd be valid for a member of `Object` if it was a generic functions, but none of the are). It's not possible to do implicit instantiation without knowing the member signature. _(Alternative: Allow it, and handle it all at run-time, including any errors from having the wrong number or types of arguments, or there not being an instantiable `foo` member.)_

This introduces **new ambiguities** in the grammar, similar to the one we introduced with generic functions. Examples include:

```dart
f(a<b,c>(d)); // Existing ambiguity, resolved to a generic method call.
f(x.a<b,c>[d]); // f((x.a<b, c>)[d]) or f((x.a < b), (c > [d]))
f(x.a<b,c>-d);  // f((x.a<b, c>)-d) or f((x.a < b), (c > -d]))
```

The `x.a<b,c>` can be an explicitly instantiated generic constructor (or function) tear-off or an explicitly instantiated type literal named using a prefix, which is new. While neither type objects nor functions declare `operator-` or `operator[]`, such could be added using extension methods.

We will disambiguate such situations *heuristically* based on the token following the `>`. In the existing ambigurity we treat `(` as a sign that it's a generic invocation. If the next character is one which *cannot* start a new expression (and be the operand of a `>` operator), the prior tokens is parsed as an explicit instantiation. If the token *can* start a new expression, then we make a choice depending on what we consider the most likely intention (that's specifically `-`  and `[` in the examples above).

The look-ahead tokens which force the prior tokens to be type arguments are:

> `(`  `)`  `]`  `}`  `:`  `;`  `,`  `.`  `?`  `==`  `!=` `..` `?.` `??` `?..` 
>
> `&` `|` `^` `+` `*`  `%`  `/`  `~/`

Any other token following the ambiguous `>` will make the prior tokens be parsed as a comma separated `<` and `>` operator invocations.

_We could add `&&` and `||` to the list, but it won't matter since the result is going to be invalid in either case._

_This might set us up for problems if we ever decide to use any of the infix operators as prefix operators, like `-`, but it does allow defining those operators on `Type` or `Function` and using them. Not allowing the infix operators is an alternative_

**Identity and equality** is not affected by explicit instantiation, it works exactly like if the same types had been inferred.

### No instantiated tearing off function `call` methods

We further formalize a restriction that the current implementation has.

Currently you can do instantiated tear-offs of *instance* methods. We restrict that to *interface* methods, which precisely excludes the `call` methods of function types. We do not allow instantiating function *values*, and therefore also do not allow side-stepping that restriction by instantiation the `.call` "instance" method of such a value. 

That makes it a compile-time error to *explicitly* instantiate the `call` method of an expression with a function type or of type `Function`, and the tear-off of a `call`  method of a function type is not subject to implicit instantiation (so the tear-off is always generic, even if the context type requires it not to be).

### Grammar changes

The grammar changes necessary for these changes will be provided in a separate document.

## Summary

We allow `TypeName.name` and `TypeName<typeArgs>.name`, when not followed by a type argument list or function argument list, as expressions which creates tear-offs of the the constructor `TypeName.name`.  The `TypeName` can refer to a class declaration or to a type alias declaration which aliases a class.

```dart
typedef ListList<T> = List<List<T>>;
const filledList = List.filled;  // List<T> Function<T>(int, T)
const filledIntList = List<int>.filled;  // List<int> Function(int, int)
const filledListList = ListList.filled;  // List<List<T>> Function<T>(int, T)
const filledIntListList = ListList<int>.filled;  // List<List<int>> Function(int, int)
```

We allow `TypeName.new` and `TypeName<typeArgs>.new` everywhere we allow a reference to a named constructor. It instead refers to the unnamed constructor. We allow tear-offs of the unnamed constructor by using `.new` and then treating it as a named constructor tear-off. Examples:

```dart
class C<T> {
  final T x;
  const C.new(this.x); // Same as: `const C(this.x);`
  C.other(T x) : this.new(x); // Same as: `: this(x)`
  factory C.d(int x) = D<T>.new;  // same as: `= D<T>;`
}
class D<T> extends C<T> {
  const D(T x) : super.new(x); // Same as: `: super(x);`
}
void main() {
  const C.new(0); // Same as: `const C(0);`. (Inferred `T` = `int`.)
  const C<num>.new(0); // Same as: `const C<num>(0);`.
  new C.new(0); // Same as `new C(0);`.
  new C<num>.new(0); // Same as `new C<num>(0);`.
  C.new(0); // Same as `C(0);`.
  C<num>.new(0); // Same as `C<num>(0);`.
  var f1 = C.new; // New tear-off, not expressible without `.new`.
  var f2 = C<num>.new; // New tear-off, not expressible without `.new`.
}
```

We allow *explicit instantiation* of tear-offs and type literals, by allowing type arguments where we would otherwise do implicit instantiation of tear-offs, or after type literals. Examples:

```dart
typedef ListList<T> = List<List<T>>;
T top<T>(T value) => value;
class C {
  static T stat<T>(T value) => value;
  T inst<T>(T value) => value;
}
void main() {
  // Type literals.
  var t1 = List<int>; // Type object for `List<int>`.
  var t2 = ListList<int>; // Type object for `List<List<int>>`.
  // Tear-offs.
  T local<T>(T value) => value;
  
  const f1 = top<int>; // int Function(int), works like (int $) => top<int>($);
  const f2 = C.stat<int>; // int Function(int), works like (int $) => C.stat<int>($);
  var c = C();
  var f3 = C().inst<int>; // int Function(int), works like (int $) => c.inst<int>($);
  var f4 = local<int>; // int Function(int), works like (int $) => local<int>($);
  
  var typeName = List<int>.toString();
  var functionTypeName = local<int>.runtimeType.toString();
}
```

Finally, we formalize the current behavior disallowing instantiated tear-off of `call` methods of function-typed values.

```dart
T func<T>(T value) => value;
var funcValue = func;
int Function(int) f = funcValue.call; // Disallow!
```

We can detect these statically, and they always throw at run-time, so we can special case them.

### Consequences

This proposal is non-breaking and backwards compatible. Where we introduce new syntactic ambiguities, we retain the current interpretation.

It introduces new syntax for "unnamed" constructors, they are now "`new`-named" constructors, you can just omit the `new` in most cases except tear-offs. This avoids conflicting with type literals when trying to tear off an unnamed constructor.

We technically only need the `C.new` for tear-offs, and don't need to allow it in other places, but it would be (more) inconsistent to only allow the syntax in one place. Also, the same syntax may be useful for declaring and calling generic unnamed constructors in the future.

We make the tear-off of the constructor of a generic class be a generic function. *However*, we also want to introduce *generic constructors*, say `Map.fromIterable<T>(Iterable<T> elements, K key(T element), V value(T element))`, and tearing off that should also create a generic function. Making generic tear-offs work with the *class* type parameters could interfere with this later feature. The most obvious solution is to combine class and constructor type parameters when tearing off a constructor, so the tear-off function of `Map.fromIterable` could become `Map<K, V> fromIterable$tearoff<K, V, T>(…)`. The issue with that is that *making* the constructor generic would be a breaking change, it changes the number of type parameters of the tear-off `Map.fromIterable`, whereas making a previously non-generic function into a generic one is not breaking for existing invocations (they'll infer the type arguments).

Constructors with very large argument lists will create very large function closures. Example:

```dart
class C {
  final int? a, b, c, d, e, f, g, h, i, j, k, l, m;
  C({this.a, this.b, this.c, this.d, this.e, this.f, this.g, this.h, this.i, this.j, this.k, this.l, this.m});
  // Has constructor function:
  static C new$tearoff({
      int? a, int? b, int? c, int? d, int? e, int? f, int? g, int? h, int? i, int? j, int? k, int? l, int? m}) =>
    C(a: a, b: b, c: c, d: d, e: e, f: f, g: g, h: h, j: j, l: l, m: m);
}
...
 void Function() f = C.new; // closure of new$tearoff
```

In this case, most of the parameters are *unnecessary*, and a tear-off expression of `() => C()` would likely be sufficient. However, that would prevent canonicalization, and would be inconsistent with what we do for function tear-off. If the implementation is just a tear-off of an implicitly defined `new$tearoff`, which can be tree-shaken if the constructor is never torn off, then the overhead should be *fixed*. It will make it harder to tree-shake unused *parameters*, but no harder than for static functions, which are already torn off.

## Versions

* 2.0: Initial version in this iteration. Proposed `new C` as unnamed tear-off syntax.
* 2.1: Revision. Proposed `C.new` as unnamed tear-off syntax.
* 2.2: Revision. Propose generic tear-off functions.
* 2.3: Include `F<Type>` as an expression, specify tear-offs from type aliases.
* 2.4: Only allow tear-offs of declarations and instance methods, not arbitrary functions. Specify disambiguation strategy for parsing ambiguities.
