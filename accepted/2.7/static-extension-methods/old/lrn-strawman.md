# Dart Scoped Static Extension Methods

[lrn@google.com](mailto:lrn@google.com)

## Background

An "static extension method" is a static function that can be called on an object as if it was a member of the class. It is not actually a member of the class, it is still just a static function that gets access to the receiving object and the arguments, with a more convenient syntax and improved discoverability.

An extension method is "scoped" if code must opt in to the extension method being available, typically by ensuring that the declaration of the extension method is in the static scope of the code using it.

This document defines _scoped static extension methods_ as a language feature for Dart 2.

Being scoped is a big advantage in making software modular - two different extension libraries may add similarly named methods to a class, but if they are not used in the same scope, they won't cause conflict. It means that each library is in charge of avoiding conflicts for its own code, and it won't be foiled by an unrelated library extending a class that it also uses. 

Unscoped (global) class extension is more fragile, and it doesn't play well with modular compilation.

Being static means that the extension method isn't virtual, and it doesn't interact with other non-extension methods. This ensures that the scope extension method doesn't leak out of the scope anyway, that adding an extension methods doesn't affect code that doesn't want to be affected. And again, it makes modular compilation much simpler since a static function is restricted in what it can do.

Being static also means being statically resolved, based only on the static type of the receiver expression. Figuring out which extension methods apply to which invocation is determined entirely from (type-)information available at compile-time.

### Other Languages

Other languages have static scoped extension methods. One of the most well-known examples is C#, which has static scoped extension methods. See [this survey document](lrn-static-extension-survey.md) for other languages.

## Dart Extension Methods

Adding static extension methods to Dart requires two things:

- Declaration: Declaring a static function as an extension method.
- Resolution: Which invocations actually target which static extension method.

### Declaration

In C#, all methods are inside a class, so static extension methods are just static methods where the first argument has an extra `this` in the signature:

```C#
public static class IntExtensions
{
    public static bool IsEven(this int i)
    {
       return ((i % 2) == 0);
    }
}
```

(which can further be inside a namespace).

It's a completely normal static function except for the `this` before `int i`, and can still be called as a static function.

We could do something similar in Dart: Any top-level or static function declaration can add `this` to its first argument and become an extension method. It would be in scope if the top-level function is, or if the class containing the static function is.

We could require that extension methods are only top-level declarations, but that would require us to pollute the top-level namespace.

```dart
bool isOdd(this int x) => x & 1 != 0;
class SomeClassThatsReallyANamespace {
  static bool isEven(this int x) => x & 1 == 0;
}
```

This syntax emphasizes that the function is just a static function, and you can still call it as a static function. However, this does not work for getters, setters and operators, and we would like to be able to declare static extension getters, setters and operators as well. 

We can extend the syntax for getters, setters and operators to take an extra first argument:

```dart
int get count(this List<Object> l) => l.length;
int set count(this List<Object> l, int value) { l.length = value; } 
List<T> operator *(this List<T> l, int scalar) => scalar == 1 ? l : l + l * (scalar - 1);
```

This gives us new syntactic forms that only apply to extension methods. It doesn't make those setters and operators directly usable anyway, like it does for functions

Instead we can introduce extension methods that are _not_ available as static methods, with a syntax the differs more from normal static function syntax, but which is closer to the normal function/getter/setter/operator syntaxes. Potential examples:

```dart
// type.name
bool get int.isEven => this & 0 == 0
int int.pow(int times) => times <= 1 ? this : this * this.pow(times - 1);
// type::name
bool get int::isEven => this & 0 == 0
int int::pow(int times) => times <= 1 ? this : this * this.pow(times - 1);
// grouped
extends int { // or some other recognizable token sequence containing `int`.
  bool get isEven => this & 0 == 0
  int pow(int times) => times <= 1 ? this : this * this.pow(times - 1);
}
```

No matter which syntax is chosen, the static extension function introduced by it will_ only_ exist as an extension method, there is no way to invoke it as a plain static function. The advantage is that it doesn't take up room in the namespace where it's declared because it isn't available there anyway..

We also allow the body to be written using `this` with the advantage that normal unqualified invocations can default to being `this` calls:

```dart
String String::twice() => toString() * 2;  // Implicit `this.toString() * 2`.
```

Extension methods can be declared on _any type_, not just on class types, so it must be possible to declare methods on, say, `void Function()`. Since 

```dart
void void Function(int).apply(int x) => this(x);
```

is hard to parse and

```dart
void Function() Function(int).apply(int x) => this(x);
```

is directly ambiguous (because you can omit return types from function types), this gives the advantage to the grouping syntax where the target type is clearly delimited from the return type:

```dart
extends void Function(int) {
   void Function() apply(int x) => this(x);
}
```

#### Proposal

The syntax used will be something like:

```dart
extension FooMethods<T> on List<T> {
  normalInstanceDeclarations() { ... this.something() ... }
  static staticMethods
}
```

where

- We make `extension` a built-in identifier.
- The name of the extension introduces a namespace for static members (like an abstract class).
- The name of the extension can be used in import/export hide/show clauses.
- The `on` clause specifies a single type pattern which a static receiver type must match for the extension to apply.
- A static member declaration is just introduced into the namespace as normal.
- An instance member declaration defines an extension member. It treats `this` as having a type corresponding to the `on` clause type pattern, and unresolved identifiers are interpreted as `this.id` as usual. It cannot do `super` invocations.
- The type parameter is discussed below in the Generics section.
- The extension applies if the declaration is in scope.

You cannot create a type alias for an extension declaration since it is not a type (no `typedef Foo = ExtensionName`). The declaration name is only a *namespace*, not a type.

Grammar:

```
	<extensionDeclaration>: `extension` <identifier> <typeArguments>? `on` <type> `?`? `{`
		<memberDeclarationsNoConstructor> `}` ;
```

Example:

```dart
extension IntPow on int {
  int pow(int power) => math.pow(this, power);
}
```

### Resolution

An invocation like `42.pow(4)` should invoke the `pow` method declared above, if that declaration is in scope. It is in scope if the `IntPow` declaration is _accessible_ at the point of invocation (the name `IntPow` must resolve to the declared extension, which is declared or imported into the library scope without being hidden, so it is in the lexical scope, it is not not private to another library, and it is not shadowed by another declaration).

It will _not_ be available if the declaring library is imported with a prefix. Importing with a prefix is a way to avoid name-clashes, so it should not introduce anything into the main library scope.

Any _typed_ invocation `o.pow(42)` can have both an instance `pow` method declared on the type of `o` and an extension method on the type of `o`. If that happens, we need to pick one of them.

In C#, the instance method takes precedence. This was chosen so that adding extension methods to the language _and platform libraries_ would not break existing functioning code, it would only allow more calls that were previously not allowed. It allows a class to add its own implementation of an extension method, which gets called when the method is invoked on that class or a subclass. Adding a new member to an existing interface will still be a potentially breaking change since it might change the behavior of code that uses an extension method with the same name. 

In Dart, it is currently a (potentially) breaking change to add any member to an interface, and extension methods is one approach to allow users to extend an API without breaking code.

As such, the same rationale suggests that we should let the instance member take precedence over the extension members.

So, seeing `o.pow(42)`, the compiler will find the static type of `o`.

Then it will check whether the interface of `o` declares a `pow` method. If so, it is called normally.

If not, then the call would currently be an error. With extension methods, the compiler now checks if any extension is declared in the current scope with an `on` clause matching the type of `o` (the type of `o` must be a subtype of the type of the clause, or be matched by the type pattern if we extend the syntax to general patterns), and which introduces a `pow` member. If so, the call is changed into a call to that method with the value of `o` bound to `this`.

A static extension method on `num` will match an invocation on an `int`. Effectively, if an extension method _had_ been an instance method, and it would then have been invoked, then it can be invoked as an extension method.

If _more than one_ matching static extension method is in scope, we need to either pick a preferred one, if possible, or make it a compile-time error.

If one extension method is declared on a type that is more specific than any of the other extension methods' types, then that one is used. If not, it's a compile-time error.

Inside the bodies of the members an extension declaration, the extension declaration itself takes precedence over any other extension method. The "static scope"  wins.

#### Nullability

If extension methods are chosen based on static type, then nothing prevents the receiver from being `null` at run-time. However, that's probably not what most users expect, and it's annoying to have to start every extension method with `if (this == null) throw ...`.

So, to make things easier, the static function call _only_ happens if the run-time value is non-`null`. If the value is `null`, a run-time error is thrown (similarly to calling an instance method on `null`). The same error happens for tear-offs when the receiver is `null`, exactly like it would for an actual instance method.

We can allow extensions to work on `null` as well. If we get non-nullable types, the way to do that would be to define the extension on the nullable type. So, we can introduce that to the type patterns as well:

```dart
extension EzString on String? {
  bool get isThere => this != null && this.isNotEmpty;
}
...
String foo = ...;
if (foo.isThere) ...;
```

This example will run without throwing because the type pattern is nullable, and `this` is allowed to be `null` inside the body. (Which also means that the pattern is not just a plain type, we will need a new grammatic production for type patterns).

When Dart gets non-nullable types, the code will be prepared for that. At that point, you will not be allowed to call a non-nullable extension on a nullable static type.
(We need to consider whether you can define, say, a `[]` operator on `Map?` and have it override the one on `Map` when used on a nullable receiver type.)

Allowing nullable extensions is something we can add later, but we should figure out whether there are known use-case for it, and if so, we might as well include it from the beginning.

#### Showing/Hiding

Since scoped extensions are introduced by imports, it might be necessary to hide (or show) specific extension declarations. That would be complicated if the declaration did not have a _name_.

To make hiding possible, we have given `extension` blocks a name, which is one of the reasons for adding a name to the declaration syntax above.

```dart
extension Foo on void Function(int) { int bar() => 42; }
```

You can hide all members of an extension in an import by `hide Foo`. You cannot hide individual extension members. (We could allow that, as `hide Foo.bar`, but it's not expected to be important).

If the name is private, then the scoped extensions are _not visible_ in importing libraries. (Privately named extension methods cannot be named in another library, but you don't have to mention the extension name in order to use it, so we have to say explicitly that a privately named extension is not available to other libraries).

#### Tear-Offs

You can tear off a static extension method.

If `o.foo` matches an extension method, then evaluating it produces a function value remembering the value of `o` that can be called and have the same effect as calling `o.foo` with that static extension in scope.

This should "just work".

#### Edge cases

A function invocation like `o(args)` where `o` does not have a function type, is equivalent to `o.call(args)`. This applies to static extension methods as well, so an extension can make a type callable.

A receiver of type `dynamic` is treated as having all members available, so you can never call an extension method on a receiver typed `dynamic`. Same for the bottom type.

The `Function` type acts like `dynamic` with regard to the `call` method. A `call` extension method on `Function`, or on any function type, will never be matched.

You cannot call extension methods on receivers with type `void` because an expression like `o.foo` is a compile-time error if `o` has static type `void`.

You can declare extensions on `void` and `dynamic`, but it doesn't change the above. Since the types in an extension declaration are mostly used for sub-type tests, it makes little difference whether you declare the extension on `void`, `dynamic` or `Object`, except for the type of `this` inside the member bodies. Maybe we should disallow extensions on `void` and `dynamic` and defer the user to declaring them on `Object`, just to prevent the user from shooting themselves in the foot.

For the same reason, we should perhaps also disallow extensions on the bottom type, when that type becomes user expressible as part of non-null types.

Likewise you can put extension methods on `FutureOr<Object>`, and it's equivalent to putting them on `Object` since all types are subtypes of both.

If extension methods with the same name are put on multiple equivalent types, then resolution will fail to find a most specific one, but that's the same if the extensions were put on the same type. In general, we will probably recommend no putting extensions on any top type except `Object` (`Object?` with non-nullable types).

When finding a matching extension method, the arity is not relevant. The most specific extension type matcher which has a member of the right name is found, then it is invoked.

We define "more specific" on type patterns using the subtype relation on the maximal type allowed by the patterns.  If a pattern of `Iterable<int>` and pattern of `List<num>` both match a static type of `List<int>`, then there is no *most specific* pattern. Likewise if a pattern is `Iterble<T>` where `T extends int`, then the least specific type allowed by that pattern is still `Iterable<int>`. 

The least specific type allowed by a pattern is the type that the extension methods must be written against, so if a more specific extension with the same name exists, then we can assume that it is more specialized and should be used. We consider `Iterable<int>` as more specialized with regard to the element type, but `List<num>` as more specialized with regard to the collection type, but neither is clearly uniformly better than the other.

A conflict like this is not expected to be common. If two different extensions to define a method with the same name, and which can both be used for the invocation (otherwise one should just be hidden), and neither is more specific, then they are likely from the same author, and then there will probably also be an even more specialized version for the intersection. If all else fails, the user can cast the receiver to precisely match one of the extensions.

Since extension method invocations are static invocations, it is a compile-time error if the arguments do not match the function signature of the chosen extension method. There is no way to have a mismatched argument list at run-time, so it is impossible to invoke any `noSuchMethod` member. If it was, it would/should not invoke the receiver's `noSuchMethod`.

#### Proposal

The resolution rules for `o.foo(args)` where `o` as static type _T_ is:

- If _T_ has a `foo` member, then use that. 
  - A type is considered to have a member named _x_ if it has any method, setter or getter with the same base-name as _x_.
  - If _T_ is `dynamic` or the bottom type, it's assumed to have all members. 
  - If _T_ is `Function` or any function type, it's assumed to have a `call` member.
- Otherwise, if one accessible (in scope, not shadowed, not private to other library) extension matching _T_ declares a `foo` member, then use that.
  - An extension is considered to declare a member named _x_ if it declares any instance method, setter or getter with the same base-name as _x_.
  - An extension matches _T_ if _T_ matches the type pattern in the extension's `on` clause.
- If multiple accessible extensions matching _T_ declare a `foo` member, then
  - If one of those extensions is _more specific_ than the rest, use that
  - Otherwise it is a compile-time error.
- One extension is more specific than another iff the type in the `on` clause of the latter extension is a super-type of the type in the `on` clause of the former. If the pattern is generic, use the bound of the type variable as the variable type when comparing for specificity.

## Generics

We will want to allow extensions on `List<T>` to have access to the type `T`. Dart has reified generics and covariant generics, so there is functionality of instance methods that cannot be copied by static extension methods without access to the object's type variables.

We can still choose to only give the *static* extension member access to the type argument of the static type being matched, rather than the run-time type argument of the object, but it will be more limiting.

Example:

```dart
extension ListFancy<T> on List<T> {
  List<T> copyReversed() => List<T>(this.length)..setAll(0, this.reversed);
}
main() {
  List<num> list = <int>[1, 2, 3];
  var list2 = list.copyReversed();
}
```

In this case, the static type of `list.copyReversed` is definitely `List<num>`, but we have to decide what `T` is bound to during execution of the `copyReversed` method body.

The easy answer is to use the static type. We are doing static resolution of static functions, so we definitely have the static type available. We infer the type argument during inference, like any other type argument. It's safe, including type safe, but perhaps not _optimal_.

If instead we allow `T` to be the actual run-time type argument of `List` implemented by the `this` object, then it opens up a lot of opportunities. It provides a general way to access type arguments of run-time objects, which we want to add to the language as well.

We need some _restrictions_, though, in order to make that possible.

Example:

```dart
extension Foo<T> on Bar<T, T> { List<T> baz() => <T>[];  }
Bar<num, num> bar = Bar<int, double>();
main() { var list = bar.baz(); }
```

The static type of `list` will be `List<num>`, that much is certain. However, we can't bind `T` at run-time to _the_ run-time type argument of `Bar` because there are two values. We _do not_ want to compute the least-upper-bound of the two two run-time types. We also do not want to fail at run-time. That doesn't really leave us with any good solution except using the static type.

The problem with this example was ambiguity. We cannot extract _the_ run-time type argument when the type variable occurs more than once in the type constraint list. We _can_ if it occurs exactly once.

So, we can say that we let a type variable resolve to the run-time type argument if the type variable occurs only once, and otherwise it uses the static type. That's an annoying difference.

Or, we could restrict the type variable to always occur exactly once.

So, what would we be disallowing by restricting type variables to a single occurrence.

Some users might want to use multiple occurrences of a type variable to check that two types are the same. Example:

```dart
extension BiMap<T> on Map<T, T> { Map<T, T> get reversed ... }
```

The intention here is to match only something that is a `List<X>` and a `Map<int, X>` for exactly the same `X`, or a `Map<X, X>` for one `X`. It doesn't automatically work that way. Picking `Object` as the static value for `T` will allow something which is both a `List<int>` and a `Map<int, String>` to be matched, or a `Map<int, String>`. We would have to define this to mean a type pattern that only matches if the static type arguments to the classes are _exactly _the same. It won't guarantee that the type arguments are the same at run-time, so we are back at getting the static type in such a case.

That would be a completely new way of matching type parameters. It might be useful, but it's also complicated and likely error-prone.

A type parameter can have bounds:

```dart
extension NumList<T extends num> on List<T> {
   T sum() => this.reduce<T>((T a, T b) => a + b);
}
```

Such an extension only matches if the static type argument of the list is a subtype of the bound type.

The type variable may only occur once, so if it is used in another type variable bound, it cannot occur anywhere else.

Alternatively, we introduce a complete type pattern syntax with a way to capture a variable in the pattern, instead of writing the type on the extension name. 

Example:

```dart
extension NumList on List<var T extends num> {  // Alternative syntax.
   T sum() => this.reduce<T>((T a, T b) => a + b);  
}
```

Then it's not a problem to mention the variable more than once in the pattern because the binding occurrence is clearly marked:

```dart
extension BiMap on Map<var K, var V extends T> { Map<V, K> get reversed ... }
```

We should consider whether the syntax generalizes to [static extension types](https://github.com/dart-lang/language/issues/42). We would probably like the syntax of the two to be similar. Also, we should consider whether the type patterns applies in other places, like a `mixin` declaration's `on` clause, and `is` check or a `try` statement's `on` clause.

#### Function Types

The section above talks only about deconstructing interface types. We can match a `List<int>` and extract the `int`. Extension methods can be defined on _any_ type, so maybe it should also be possible to extract parts of structural types.

Example:

```dart
extension FunWrap<R, A> on R Function(A) {

  R Function(A) intercept(A before(A argument), R after(R result)) => 

      (argument) => after(this(before(argument)));

}
```

Here we put an extension method on unary functions, capturing the function's argument and return types. Again we could use the static type and be safe, but allowing access to the run-time type allows operations that are otherwise not possible, like preserving the type of the function here without knowing it statically.

This example also shows that `this` may not be an interface types inside an extension method.

It should not be treated like a normal `this` inside a class declaration, but more like the `super` of a mixin declaration - it's just an expression with a known type.

Being _able_ to deconstruct function types means that implementations must retain the types at run-time. The dart2js compiler has flags that disables type checks, and without those checks, it might not otherwise need to retain the types. With this feature, it might need to do so anyway.

Type parameter bounds are problematic when the type variable occurs contravariantly.

Example:

```dart
extension TooClever<T extends num> on void Function(T) { 
  List<T> argumentCollector() => <T>[];
}
void Function(int) fun = (Object o) {};
main() { var list = fun.argumentCollector(); }
```

Here the static type of `list` will be `List<int>`. It's unclear what happens at run-time when `T` should be bound to `Object`. Maybe it's just a type error, but it's one that happens very easily when a contravariant type variable is used, and even more when it has a bound (because the bound is not safe). 

We should just disallow (or strongly discourage) bounds on contravariantly occurring type variables, unless we introduce lower bounds (`T super num`). Since a type variable can only occur once, it's always either covariant or contravariant.

The code here will still need to fail because the type variable is _used_ covariantly. We can warn about that, but probably can't disallow it if we want to be able to deconstruct function type and use the type covariantly as well, like this example suggests.

We will need to insert run-time checks in all places where the contravariantly captured type variable is used covariantly (and in all places where a convariant type variable is used contravariantly) because the extension behavior is inherently covariant (we use static types to determine which extension to use, then pass the run-time object, which may be of a subtype, into the resulting code). 

#### Other Non-Interface Types

Function types are not the only structural, non-interface types in Dart. We also have `FutureOr` and we might get nullable vs. non-nullable types. Both of these are union types.

A match on `FutureOr<T>` should match if the static type of the receiver is `T` or `Future<T>`.

It should be able to capture the `T` type as a type variable.

A `FutureOr` type pattern is not compatible with any other pattern. We could choose to allow `FutureOr<Object>` because it's equivalent to `Object`, but it's easier to just disallow combining `FutureOr` with anything.

If we get nullable and non-nullable types, then a nullable type is a union type.

We may still be able to allow combinations of nullable and non-nullable interface types, but it only matches a nullable type if all the type-patterns are nullable, so we might as well require all the type patterns to be nullable or all of them to be non-nullable, and not allow combinations.

It _is_ (or can be) possible to use a type variable as a type pattern, providing a self-type for the matched object. 

Example:

```dart
extension Doubler<T extends num> on T {
  T get double => this * 2;
}
```

#### Specificity

We said above that if more than one extension declaration matches an invocation, then we pick the most specific one. A generic extension is considered as specific as its bounds. That is, for:

```dart
extension Foo on List<int> { ... }

extension Bar<T> on List<T> { ... }

extension Baz<T extends int> on List<T> { ... }
```

the most least specific extension is `Bar`, then `Foo` and `Baz` are equally specific. In practice, `Baz on List<int>` is treated exactly like `Baz<T extends int> on List<T>`, just without access to a captured run-time type.

### Alternative

Only allowing the type variables to occur once suggests that this variable is different from other type variables. And it is, this is really a _type pattern_ with captures.

We could introduce a new syntax for that, one that we expect to be able to use in other cases as well, but it might also increase the scope of this feature too much.

Example: Instead of 

```dart
extension Foo<T> on List<T> { ... }
```

we could write

```dart
extension Foo on List<Object T>{ ... }
```

or 

```dart
extension Foo on List<T extends Object>{ ... }
```

```dart
extension Foo on List<var T>{ ... }
```

in order to say that `T` captures the type that is matched at that point.

This also explains why the specificity of a type variable uses the bound, because the type variable in a type pattern really is equivalent to just matching the bound, plus a run-time capturing of the actual type.

We should consider this approach, and see if we can find a good, generalizable solution, but I'd not put it as part of an initial plan.

### Proposal

An extension declaration may have type parameters. The type variable must only occur once in the type patterns or in other type variable bound. There should not be any bounds on type variables which occur contravariantly.

An extension matches an object if the `on` clause types where type variables are replaced by their bounds in covariant positions and by `Null`/bottom in contravariant positions, all match the static type of the object expression. At that point, the type variables are bound to the _actual_ run-time type of the object at the position where the type variable occurs.

This binding can deconstruct run-time types to extract type arguments from interfaces, return or parameter types from function types, or base types from `FutureOr` types.

Alternatively, and probably better, use something like [type patterns](https://github.com/dart-lang/language/issues/170).

## Extension State/Fields

So far we have described extension _methods_, which include getters, setters and constructors.

It does not allow extension _fields_, so an extension cannot add state to an object.

That makes sense because a scoped extension should only affect the code that opts-in to the extension, and modifying the object layout to add more state is a global change.

One way to simulate added state is by using an `Expando` to store the values.

We can automatically convert an extension field to an expando access, but expandos have some restrictions:

- They do not work for basic types like `bool`, `int` and `String` (types where you can create new objects that are identical to previously existing objects).
- You cannot initialize an expando to something other than `null`.

It may still be useful, but I recommend that we omit this feature for now.

## Extension Static Methods

So far we have only allowed extending a type with (seemingly) instance methods.

We could also allow extending it with _static _members and factory constructors.

For example:

```dart
extension RevList<T> on List<T> {
  static List<T> reverse<T>(List<T> source) => source.reversed.toList();
}
```

This _could _introduce `reverse` as a method on the `List` class, so users could call `List.reverse(someList)`. Or add a factory constructor like 

```dart
extension ConcatList<T> on List<T> {
  factory List.concat(Iterable<Iterable<T>> elements) => elements.expand((i) => i);
}
```

so users can writer `List<int>.concat([[1, 2], [3, 4]]);`.

This is definitely possible, and has some interesting applications, but it is also not that big an advantage because you still have to call the function the same way as usual, just with a different type in front.

It has some issues too: Not all types are class types, and it doesn't make sense to attach static methods or constructors to structural types like function types or `FutureOr`-types, or constructors on any intersection type (what you get by listing more than one type in the `on` clause). That makes it a special-case feature that only applies to some extensions, those defined on a single class type, which makes the design much less compelling.

If we allow static members like this, then we can't use the extension declaration also as a scope for static methods that only occur there. We'd either have to say that the static methods in the extension declaration are not available through that, or make them available through both a matched type and the extension declaration itself. That feels inconsistent, and error-prone since someone might add a static helper function on the extension and not realize that it also becomes a static method on all matching types. It seems more consistent to pick either approach, and stick to it.

With capturing type patterns, it's possible to capture the "Self" type like:

```dart
extension Apply<S> on S {
  T apply<T>(T Function(S) action) => action(this);
}
```

That's a useful extension on `Object` that knows the type of the current object. (We probably should add the self-type to the language, to avoid people using extension methods _just_ for that).

If we then put a static method on that extension, would it also have access to `S`? It probably shouldn't.

All in all, I'm not sure it's worth it, but if we want to keep the door open, we should not allow an extension to contain static methods at all.

I suggest making static methods declared in an `extension` declaration be plain static methods in the namespace defined by the declaration, just as we do for classes and mixins. Then you can do:

```dart
extension MyList on List<Object> {
  bool equals(List<Object> other) => listEquals(this, other);
  static bool listEquals(List self, List other) {
    if (self.length != other.length) return false;
    for (int i = 0; i < self.length; i++) {
      if (self[i] != other[i]) return false;
    }
    return true;  
  }
}
```

and let other people reuse the static helper function as:

```dart
... MyList.listEquals(list1, list2) ...
```
