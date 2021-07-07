# Dart Constructor Tear-offs

Author: lrn@google.com<br>Version: 2.10

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

Expressions of the form <code>*C*\<*typeArgs*>.*name*</code> are potentially compile-time constant expressions and are compile-time constants if the type arguments are constant types.

_The former syntax, without type arguments, is currently allowed by the language grammar, but is rejected by the static semantics as not being a valid expression. The latter syntax is not currently grammatically an expression. Both can occur as part of a_ constructor invocation, but cannot be expressions by themselves because they have no values. We introduce a static and dynamic expression semantic for such a *named constructor tear-off expression*.

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

The constant-ness, identity and equality of the torn-off constructor functions behave exactly the same as if they were tear-offs of the corresponding static function. This means that a non-generic class constructor always tears off to the *same* function value, as does an uninstantiated tear off of a generic class constructor. An instantiated tear-off is constant and canonicalized if the instantiating types are constant, and not even equal if the types are not constant.

The static type of the named constructor tear-off expression is the same as the static type of the corresponding constructor function tear-off.

This introduces an **ambiguity** in the grammar. If `List.filled` is a valid expression, then `List.filled(4, 4)` can both be a constructor invocation *and* a tear-off followed by a function invocation, and `List.filled<int>(4, 4)` can *only* be valid as a tear-off followed by a function invocation.
This is similar to the existing possible ambiguity for an instance method invocation like `o.m(arg)`, and we resolve it the same way, by always preferring the direct invocation over doing a tear-off and a function invocation. 

We do not allow `List.filled<int>(4, 4)` at all.  We could allow it, it's syntactically similar to a getter invocation like `o.getter<int>(4)`, which we do handle without issues, but allowing that syntax to be a constructor tear-off could interfere with a possible later introduction of *generic constructors*. We only do constructor tear-off when the constructor reference is *not* followed by a *typeArguments* or *arguments* production. If it is followed by those, then it's a constructor *invocation*, and it's currently an error if it includes type arguments. That is, an expression of the form `List.filled<int>(4, 4)` is *invalid*, it's not interpreted as a constructor tear-off followed by a function invocation, but always as a constructor invocation&mdash;and the `List.filled` constructor is not a generic construct (no constructor is, yet). You can write `(List.filled)<int>(4, 4)` to do the tear-off or `List<int>.filled(4, 4)` to do the invocation.

#### Tearing off constructors from type aliases

*With generalized type-aliases*, it's possible to declare a class-alias like `typedef IntList = List<int>;`. We allow calling constructors on such a type alias, so we will also allow tearing off such a constructor.

Example class aliases:

```dart
typedef IntList                   = List<int>; // Non-generic alias.
typedef NumList<T extends num>    = List<T>;   // Generic alias.
typedef MyList<T extends dynamic> = List<T>;   // Generic alias *and* "proper rename" of List.
```

When a type alias aliases a class, we can introduce a corresponding constructor function for the alias for each constructor of the class, declared next to the alias (a top-level declaration) and with a fresh name. If an alias has the form <code>typedef *A*\<*typeParams*> = *C*\<*typeArgs*>;</code>, and *C* declares a constructor <code>*C*.*name*(params) &hellip;</code>, then the *alias* has a corresponding constructor function

```dart
C<typeArgs> A$name$tearoff<typeParams>(params) => C<typeArgs>.name(args);
```

where *args* passes the parameters *params* directly to as arguments to *C.name* in the same order they are received. As usual, if *A* is not generic, the \<*typeParams*> are omitted, and if *C* is not generic, \<*typeArgs*> are going to be absent. This constructor function is *only* used for *generic* tear-offs of the constructor, and only if the alias is not a "proper rename", as defined below. In all other cases, a tear-off of a constructor through an alias will use the corresponding constructor function of the aliased class directly.

For the example aliases above, the constructor functions corresponding to `List.filled` would be:

```dart
List<int> IntList$filled$tearoff(int length, int value) => List<int>.filled(length, value);
List<T> NumList$filled$tearoff<T extends num>(int length, T value) => List<T>.filled(length, value);
List<T> MyList$filled$tearoff<T extends dynamic>(int length, T value) => List<T>.filled(length, value);
```

However, those constructor functions are not necessarily all *used*, because we prefer to use the constructor functions of the class where possible. This reduces the number of functions the compiler actually has to introduce.

For static typing and type inference, the tear-off of a constructor from an alias is always equivalent to tearing off the corresponding constructor function of the alias. The static type of the tear-off expression is the static type of that function tear-off. Inferred type arguments that would be applied to that function tear-off are then applied to the alias in order to decide the run-time semantics. Example:

```dart
List<int> Function(int, int) f = NumList.filled;
// equivalent for inference:   = NumList$filled$tearoff;
// Infers type argument <int>: = NumList$filled$tearoff<int>;
// equivalent to writing:      = NumList<int>.filled;
```

For the run-time semantics we may tear off *either* the corresponding constructor function of the alias *or*, preferably, the corresponding constructor function of the class when we know that it has a compatible type and behavior. The choices are as follows:

**Tearing off a constructor from a non-generic alias for a class is equivalent to tearing off the constructor from the aliased class (which is instantiated by the alias if the class is generic).**

A *non-generic* type alias is always expanded to its aliased type, then the tear-off happens at that type. Tearing off `IntList.filled` will act like tearing off `List<int>.filled`, which uses the corresponding constructor function of `List`. It's constant and canonicalized to the same function as `List<int>.filled`. _In other words, the alias is treated as an actual alias for the type it aliases._ The `IntList$filled$tearoff` constructor is never used for anything because the alias is non-generic.

Example:

```dart
var f = IntList.filled; // Equivalent to `List<int>.filled` or `List.filled$tearoff<int>`
```

**Tearing off a constructor from an instantiated generic alias for a class is equivalent to tearing off the constructor from the aliased class (which is instantiated by the instantiated alias if the class is generic, which it probably is since otherwise the alias doesn't use its type parameter).**

A *generic* type alias is not an alias for *one* type, but for a family of types. If the type alias is *instantiated* (implicitly or explicitly) before the tear-off, then the result is still the same as tearing the constructor off the aliased type directly, using the corresponding constructor function of the class, and it's constant and canonicalized if the instantiating type arguments are compile-time constant types.

Example:

```dart
var makeIntList = NumList<int>.filled; // Equivalent to `List<int>.filled` or `List.filled$tearoff<int>`
List<double> Function(int, double) makeDoubleList = NumList.filled; // Same as `List<double>.filled` after inference.
```

Here `NumList<int>` is a single type (`List<int>`), and the tear-off happens from that type.

Notice that whether an alias expansion is constant depends on the parameters, not the result. Example:

```dart
typedef Ignore2<T, S> = List<T>;
void foo<X>() {
  var c = Ignore2<int, X>.filled; // Aka List<int>.filled, but is *not constant*.
}
```

In this example, `Ignore2<int, X>.filled` is treated exactly like `List<Y>.filled` where `Y` happens to be bound to `int` when the expression is evaluated. There is no canonicalization. Such a situation, where a type alias has parameters it does not use, is expected to be extremely rare.

**If the generic alias is not a proper rename for the class it aliases, then tearing off a constructor from the uninstantiated alias is equivalent to tearing off the corresponding constructor function of the alias, which is a generic function. The result always a generic function, and is always a compile-time constant.**

If the generic alias is *not* instantiated before the constructor is torn off, then the tear-off abstracts over the type parameters *of the alias*, and tearing off a constructor works equivalently to tearing off the corresponding constructor function *of the alias* (where the generics match the type alias, not the underlying class). This is where we use the corresponding constructor function of the alias&mdash;except when the alias is a *proper rename*, as defined below. 

Example:

```dart
var makeNumList = NumList.filled;  // Equivalent to NumList$filled$tearoff
```

Since this is equivalent to the uninstantiated tear-off of a static/top-level function, it's always constant and canonicalized.

Example:

```dart
typedef ListList<T> = List<List<T>>;
// Corresponding factory function
List<List<T>> ListList$filled$tearoff<T>(int length, List<T> value) => List<List<T>>.filled(length, value);

var f = ListList.filled; // Equivalent to `= ListList$filled$tearoff;`
```

**If a generic alias is a proper rename for a class, then tearing off a constructor from the uninstantiated alias is equivalent to tearing off the corresponding constructor function of the *class*. This is always a generic function, and is always a compile-time constant.**

An alias is considered a *proper rename* of a class if the type alias aliases the class, its has the same number of type parameters as the class, the type parameters have the same bounds as the corresponding parameter of the class, and the type parameters are directly passed as type arguments to the class in the order they are declared. More formally:

A type alias of the form <code>typedef *A*\<*X*<sub>1</sub> extends *P*<sub>1</sub>, &hellip;,  *X*<sub>*n*</sub> extends *P*<sub>*n*</sub>\> = *C*<*x*<sub>1</sub>, &hellip;, *x*<sub>*n*</sub>\></code> is a *proper rename* of a class <code>class C \<*Y*<sub>1</sub> extends *Q*<sub>1</sub>, &hellip;,  *Y*<sub>*m*</sub> extends *Q*<sub>*m*</sub>\> &hellip;</code> iff:

* <code>*C*</code> denotes the class declaration of `C`,
* *n* = *m*.
* *P*<sub>*i*</sub>[*X*<sub>1</sub>&mapsto;*Y*<sub>1</sub>, &hellip; *X*<sub>*n*</sub>&mapsto;*Y*<sub>*n*</sub>] and *Q*<sub>*i*</sub> are mutual subtypes for all 1 &le; *i* &le; *n*.

That is, an alias is not a proper rename if it accepts different type parameters than the class it aliases, whether it be the bounds, the order, or even the number of type parameters.

Example:

```dart
class C<T1 extends num, T2 extends Object?> {}
typedef A1<X extends num, Y extends dynamic> = C<X, Y>; // Proper rename, bounds are mutual subtypes.
typedef A1<X extends num, Y extends num> = C<X, Y>;     // Not proper rename! Different bound.
typedef A1<X extends Object?, Y extends num> = C<Y, X>; // Not proper rename! Different order.
typedef A1<X extends num> = C<X, Object?>;              // Not proper rename! Different count.
```

If *A* is a proper rename for *C*, then a constructor tear-off <code>*A.name*</code> tears off the corresponding constructor function for <code>*C.name*</code> instead of the one for <code>*A.name*</code>. The static type is still the same as it would be for <code>*A.name*</code>, the only difference is the identity of the resulting function and the actual reified type parameter bounds, which are only guaranteed to be equivalent up to mutual subtyping, which may be visible if someone does `toString` on the runtime type of something containing those types. _The requirements of a proper rename ensures that the run-time behavior of the function will be nigh indistinguishable from the corresponding constructor function of the alias._

Example :

```dart
var f = MyList.filled; // Equivalent to `List.filled` or `List.filled$tearoff`

// Instantiated type aliases use the aliased type, constant and canonicalized when type are constant.
print(identical(MyList<int>.filled, NumList<int>.filled)); // true
print(identical(MyList<int>.filled, List<int>.filled)); // true
print(identical(NumList<int>.filled, List<int>.filled)); // true
  
// Non-instantiated type aliases have their own generic function.
print(identical(MyList.filled, MyList.filled)); // true
print(identical(NumList.filled, NumList.filled)); // true
print(identical(MyList.filled, NumList.filled)); // false
print(identical(MyList.filled, List.filled)); // true (proper rename!)
  
// Implicitly instantiated tear-off.
List<int> Function(int, int) myList = MyList.filled;
List<int> Function(int, int) numList = NumList.filled;
print(identical(myList, numList)); // true, same as `MyList<int>.filled` vs `NumList<int>.filled`.
```

The static type of a proper-rename alias constructor tear-off may differ from its runtime type, because the static type is taken from the alias, the runtime type is taken from the aliased class.

Example:

```dart
class C<T extends Object?> {
  C.name();
  List<T> createList() => <T>[];
}
typedef A<T extends dynamic> = C<T>; // Proper rename, different, but equivalent, bound.

void main() {
  // Static type : C<T> Function<T extends Object?>()
  // Runtime type: C<T> Function<T extends Object?>()
  var cf = C.name; 
  // Static type : C<T> Function<T extends dynamic>()
  // Runtime type: C<T> Function<T extends Object?>()
  var af = A.name;
  
  var co = (cf as dynamic)();
  var ao = (af as dynamic)(); // Dynamic instantiate to bounds uses actual bounds.
  print(co.runtimeType); // C<Object?>
  print(ao.runtimeType); // C<Object?>
}
```

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

You cannot have both a `C` and a `C.new` constructor declaration in the same class, they denote the same constructor, so we extend the section on class member conflicts to say:

> It is a compile-time error if $C$ declares a constructor named \code{$C$} and a constructor named \code{$C$.\NEW{}}.

(Alternatively we expand the notion of *basename* to cover constructors, make both constructors `C` and `C.new` have the same basename, and then simply say that it's a compile-time error if a class has two declarations with the same basename. That would automatically cover having two constructors with the same name).

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

We will introduce syntax allowing you to explicitly instantiate a function tear-off and a type literal for a generic class. The former for consistency with constructor tear-offs, the latter to introduce in-line types without needing a `typedef`, like we did for in-line function types originally. And we do both now because they share the same grammar productions.

Example:

```dart
T id<T>(T value) => value;
var idInt = id<int>; // Explicitly instantiated tear-off, saves on writing function types.
// and
Type intList = List<int>; // In-line instantiated type literal.
```

These grammar changes allows *type parameters* without following parenthesized arguments in places where we previously did not allow them. For example, this means that `<typeArguments>` becomes a *selector* by itself, not just followed by arguments.

It applies to instance methods as well as local, static and top-level function declarations. For instance methods, it applies to references of the form

`instanceMethod<int>` (with implicit `this`), `object.instanceMethod<int>` (including `this`) and `super.instanceMethod<int>`.

The static type of the explicitly instantiated tear-offs are the same as if the type parameter had been inferred, but no longer depends on the context type.

The static type of the instantiated type literal is `Type`. This also satisfies issue [#123](https://github.com/dart-lang/language/issues/123). 

We **do not allow** *dynamic* explicit instantiation. If an expression `e` has type `dynamic` (or `Never`), then `e.foo<int>` is a compile-time error for any name `foo`. (It'd be valid for a member of `Object` that was a generic function, but none of the `Object` members are generic functions). It's not possible to do implicit instantiation without knowing the member signature. _(Possible alternative: Allow it, and handle it all at run-time, including any errors from having the wrong number or types of arguments, or there not being an instantiable `foo` member. We won't do this for now.)_

We **do not allow** implicit instantiation of callable objects. Given <code>*e*\<*typeArgs*></code> where *e* has a static type which is a class with a generic `call` method, we do not implicitly convert this to <code>*e*.call\<*typeArgs*></code>, like we would for a call like <code>*e*\<*typeArgs*>(*args*)</code>. You cannot type-instantiate function *values*, only call them, and here we treat "callable objects" like function values. You *can* write <code>*e*.call\<*typeArgs*></code> and treat `call` as a normal generic instance method.

This new syntax also introduces **new ambiguities** in the grammar, similar to the one we introduced with generic functions. Examples include:

```dart
f(a<b,c>(d)); // Existing ambiguity, resolved to a generic method call.
f(x.a<b,c>[d]); // f((x.a<b, c>)[d]) or f((x.a < b), (c > [d]))
f(x.a<b,c>-d);  // f((x.a<b, c>)-d) or f((x.a < b), (c > -d]))
```

The `x.a<b,c>` can be an explicitly instantiated generic function tear-off or an explicitly instantiated type literal named using a prefix, which is new. While neither type objects nor functions declare `operator-` or `operator[]`, such could be added using extension methods.

We will disambiguate such situations *heuristically* based on the token following the `>`. In the existing ambiguity we treat `(` as a sign that it's a generic invocation. If the next character is one which *cannot* start a new expression (and thereby be the second operand of a `>` operator), the prior tokens is parsed as an explicit instantiation. If the token *can* start a new expression, then we make a choice depending on what we consider the most likely intention (that's specifically `-`  and `[` in the examples above).

The look-ahead tokens which force the prior tokens to be type arguments are:

> `(`  `)`  `]`  `}`  `:`  `;`  `,`  `.`  `?`  `==`  `!=` `..` `?.` `??` `?..` 
>
> `&` `|` `^` `+` `*`  `%`  `/`  `~/`

Any other token following the ambiguous `>` will make the prior tokens be parsed as comma separated `<` and `>` operator invocations.

_We could add `&&` and `||` to the list, but it won't matter since the result is going to be invalid in either case, because those operators do not work on `Type` or function values and cannot be defined using extension methods._

_This might set us up for problems if we ever decide to use any of the infix operators as prefix operators, like `-` is now, but it does allow defining those operators on `Type` or `Function` and using them. Not allowing the infix operators is an alternative_

**Identity and equality** is not affected by explicit instantiation, it works exactly like if the same types had been inferred.

#### Static invocations

A static member invocation still only works on an *uninstantiated* type literal. You can write `List.copyRange`, but not `List<int>.copyRange`.

Allowing `List<int>.copyRange` is confusing. The invocation will not have access to the type parameter anyway, so allowing it is not going to help anyone. The occurrence of `List` in `List.copyRange` refers to the class *declaration*, treated as a namespace, not the class itself.

This goes for type aliases too. We can declare `typedef MyList<T> = List<T>;` and `typedef IntList = List<int>;` and do `MyList.copyRange` or `IntList.copyRange` to access the static member of *the declaration* of the type being aliased. This is specially introduced semantics for aliases of class or mixin types, not something that falls out of first resolving the type alias to the class or mixin type. We do not allow `MyList<int>.copyRange` either, even though we allow `IntList.copyRange`. They are not the same when doing static member accesses.

#### Constructor/type object member ambiguity

Until now, writing `C.foo` means that `foo` must be a static member of `C`. If you write `C.toString()`, then it's interpreted as trying to call a static `toString` method on the class `C`, not the instance `toString` method of the `Type` object for the class `C`. You have to write `(C).toString()` if that is what you want.

Similarly, we always treat `C<T>.toString()` as an attempted constructor invocation, not an invocation of the instance `toString` method of the `Type` object corresponding to `C<T>` (which is now otherwise a valid expression). 

That is, disambiguation of the otherwise grammatically ambiguous "(instantiated class-reference or type-literal).name" always chooses the "constructor tear-off" interpretation over the "type-literal instance member" interpretation. If followed by an argument list, it's always treated as a constructor invocation, not the (now otherwise allowed) `Type` object instance method invocation. This is a generalization of what we already do for static members and for constructor invocations.

### No instantiated tearing off function `call` methods

We further formalize a restriction that the current implementation has.

Currently you can do instantiated tear-offs of *instance* methods. We restrict that to *interface* methods, which precisely excludes the `call` methods of function types. We do not allow instantiating function *values*, and therefore also cannot allow side-stepping that restriction by instantiation the `.call` "instance" method of such a value. 

That makes it a compile-time error to *explicitly* instantiate the `call` method of an expression with a function type or of type `Function`, and the tear-off of a `call`  method of a function type is not subject to implicit instantiation (so the tear-off is always generic, even if the context type requires it not to be, which is then guaranteed to introduce a type error).

### Grammar changes

The grammar changes necessary for these changes will be provided separately (likely as changes to the spec grammar).

## Summary

We allow `TypeName.name` and `TypeName<typeArgs>.name`, when not followed by a type argument list or function argument list, as expressions which creates tear-offs of the constructor `TypeName.name`.  The `TypeName` can refer to a class declaration or to a type alias declaration which aliases a class.

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
  factory C.d(T x) = D<T>.new;  // same as: `= D<T>;`
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
  void method() {
    var f1 = stat<int>;
    var f1TypeName = stat<int>.runtimeType.toString();
    var f2 = inst<int>;
    var f2TypeName = inst<int>.runtimeType.toString();
    var f3 = this.inst<int>;
    var f3TypeName = this.inst<int>.runtimeType.toString();
  }
}
mixin M on C {
  static T mstat<T>(T value) => value;
  T minst<T>(T value) => value;
  void mmethod() {
    var f1 = mstat<int>;
    var f1TypeName = mstat<int>.runtimeType.toString();
    var f2 = minst<int>;
    var f2TypeName = minst<int>.runtimeType.toString();
    var f3 = this.minst<int>;
    var f3TypeName = this.minst<int>.runtimeType.toString();
  }
}
extension Ext on C {
  static T estat<T>(T value) => value;
  T einst<T>(T value) => value;  
  void emethod() {
    var f1 = estat<int>; // works like (int $) => Ext.estat<int>($)
    var f1TypeName = estat<int>.runtimeType.toString();
    var f2 = einst<int>; // works like (int $) => Ext(this).einst<int>($)
    var f2TypeName = einst<int>.runtimeType.toString();
    var f3 = this.einst<int>; // works like (int $) => Ext(this).einst<int>($)
    var f3TypeName = this.einst<int>.runtimeType.toString();
  }
}
class D extends C with M {
  void method() {
    var f4 = super.inst<int>; // works like (int $) => super.inst<int>($)
    var f4TypeName = super.inst<int>.runtimeType.toString();
  }
}
void main() {
  // Type literals.
  var t1 = List<int>; // Type object for `List<int>`.
  var t2 = ListList<int>; // Type object for `List<List<int>>`.
  
  // Instantiated function tear-offs.
  T local<T>(T value) => value;
  
  const f1 = top<int>; // int Function(int), works like (int $) => top<int>($);
  const f2 = C.stat<int>; // int Function(int), works like (int $) => C.stat<int>($);
  var f3 = local<int>; // int Function(int), works like (int $) => local<int>($);
  var d = D();
  var f4 = d.inst<int>; // int Function(int), works like (int $) => c.inst<int>($);
  var f5 = d.minst<int>; // int Function(int), works like (int $) => c.minst<int>($);
  var f6 = d.einst<int>; // int Function(int), works like (int $) => Ext(c).einst<int>($);
  
  var typeName = List<int>.toString();
  var functionTypeName = local<int>.runtimeType.toString();
}
```

Finally, we formalize the current behavior disallowing instantiated tear-off of `call` methods of function-typed values.

```dart
T func<T>(T value) => value;
var funcValue = func;
int Function(int) f = funcValue.call; // Disallowed!
```

We can detect these statically, so we can special case them in the compiler.

That makes a type instantiation expression of the form <code>*e*\<*typeArgs*></code> only allowed if *e* denotes a generic type declaration (class, mixin, type alias, then the result is an instantiated type literal), if *e* denotes a generic function declaration (top-level, static or local), or if *e* denotes a generic instance method of a known interface type (not the `call` method of a function type), and in the last two cases the result is a non-generic function value.

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
* 2.5: Elaborate on instance member tear-offs.
* 2.6: Elaborate on constructor name clashes and alias tear-off identity.
* 2.7: State that we do not allow implicit `.call` member instantiations on callable objects.
* 2.8: State that unused type arguments of a type alias still affect whether they are constant.
* 2.9: Make it explicit that you cannot access static members through instantiated type literals.
* 2.10: Make it explicit that `C<T>.toString` is a constructor reference, not an instance member on a `Type` object.
