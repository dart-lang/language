# Dart Static Extension Methods Design

lrn@google.com<br>Version: 1.1<br>Status: Design Proposal

This is a design document for *static extension methods* for Dart. This document describes the most basic variant of the feature, then lists a few possible variants or extensions.

See [Problem Description](https://github.com/dart-lang/language/issues/40) and [Feature Request](https://github.com/dart-lang/language/issues/41) for background.

The design of this feature is kept deliberately simple, while still attempting to make extension methods act similarly to instance methods in most cases.

## What Are Static Extension Methods

Dart classes have virtual methods. An invocation like `thing.doStuff()` will invoke the virtual `doStuff` method on the object denoted by `thing`. The only way to add methods to a class is to modify the class. If you are not the author of the class, you have to use static helper functions instead of methods, so `doMyStuff(thing)` instead of `thing.doMyStuff()`. That's acceptable for a single function, but in a larger chain of operations, it becomes overly cumbersome. Example:

```dart
doMyOtherStuff(doMyStuff(something.doStuff()).doOtherStuff())
```

That code is much less readable than:

```dart
something.doStuff().doMyStuff().doOtherStuff().doMyOtherStuff()
```

The code is also much less discoverable. An IDE can suggest `doMyStuff()` after `something.doStuff().`, but will be unlikely to suggest putting `doMyOtherStuff(…)` around the expression.

For these discoverability and readability reasons, static extension methods will allow you to add "extension methods", which are really just static functions, to existing types, and allow you to discover and call those methods as if they were actual methods, using `.`-notation. It will not add any new abilities to the language which are not already available, they just require a more cumbersome and less discoverable syntax to reach.

The extension methods are *static*, which means that we use the static type of an expression to figure out which method to call, and that also means that static extension methods are not virtual methods.

The methods we allow you to add this way are normal methods, operators, getter and setters. As such, the feature should really be called "Static Extension Members". For historical reasons, we will stick with the "Static Extension Methods" name.

## Declaring Static Extension Methods

### Syntax

A static extension of a type is declared using syntax like:

```dart
extension MyFancyList<T> on List<T> {
  int get doubleLength => this.length * 2;
  List<T> operator-() => this.reversed.toList();
  List<List<T>> split(int at) => 
      <List<T>>[this.sublist(0, at), this.sublist(at)];
  List<T> mapToList<R>(R Function(T) convert) => this.map(convert).toList();
}
```

More precisely, an extension declaration is a top-level declaration with a grammar similar to:

```ebnf
<extension> ::= 
  `extension' <identifier>? <typeParameters>? `on' <type> `{'
     memberDeclaration*
  `}'
```

Such a declaration introduces its *name* (the identifier) into the surrounding scope. The name does not denote a type, but it can be used to denote the extension itself in various places. The name can be hidden or shown in `import` or `export` declarations.

The *type* can be any valid Dart type, including a single type variable. It can refer to the type parameters of the extension.

The member declarations can be any non-abstract static or instance member declaration except for instance variables and constructors. Instance member declaration parameters must not be marked `covariant`. Abstract members are not allowed since the extension declaration does not introduce an interface, and constructors are not allowed because the extension declaration doesn't introduce any type that can be constructed. Instance variables are not allowed because there won't be any memory allocation per instance that the extension applies to. We could implement instance variables using an `Expando`, but it would necessarily be nullable, so it would still not be an actual instance variable.

An extension declaration with a non-private name is included in the library's export scope, and a privately named extension is not. It is a compile-time error to export two declarations, including extensions, with the same name, whether they come from declarations in the library itself or from export declarations (with the usual exception when all but one declaration come from platform libraries). Extension *members* with private names are simply inaccessible in other libraries.

We may want to make `extension` a built-in identifier. Is not necessary for disambiguation, but it may make parsing easier.

### Omitting Names For Private Extensions

If an extension declaration is only used locally in a library, there might be no need to worry about naming conflicts or overrides. In that case, then name identifier can be omitted (hence the `<identifier>?` in the grammar above).

Example:

```dart
extension<T> on List<T> {
  void quadruple() { ... }
}
```

This is equivalent to giving the extension a fresh private name.

We may need to make `on` a built-in identifier, and not allow those as names of extensions, then there should not be any parsing issue. Even without that, the grammar should be unambiguous because `extension on on on { … }` and `extension on on { … }` are distinguishable, and the final type cannot be empty. It may be *harder* to parse, though.

This is a simple feature, but with very low impact. It only allows you to omit a single private name for an extension that is only used in a single library.

### Scope

Dart's static extension methods are *scoped*. They only apply to code where the extension itself is *in scope*. Being in scope means that the extension is declared or imported into a scope which is a parent scope of the current lexical scope.

You can *avoid* making the extension in-scope for a library by either not importing any library exporting the extension, importing such a library and hiding the extension using `hide` or `show`, or importing such a library only with a prefix.

An extension *is* in scope if the name is *shadowed* by another declaration (a class or local variable with the same name shadowing a top-level or imported declaration, a top-level declaration shadowing an imported extension, or a non-platform import shadowing a platform import).

An extension *is* in scope if is imported, and the extension name conflicts with one or more other imported declarations.

The usual rules applies to referencing the extension by name, which can be useful in some situations; the extension's *name* is only accessible if it is not shadowed and not conflicting with another imported declaration.

If an extension conflicts with, or is shadowed by, another declaration, and you need to access it by name anyway, it can be imported with a prefix and the name referenced through that prefix.

Example:

```dart
import "all.dart";  // exposes extensions `Foo`, `Bar` and `Baz`.
import "bar.dart";  // exposes another extension named `Bar`.
import "bar.dart" as b;  // Also import with prefix.
class Foo {}
main() {
  Foo();  // refers to class declaration.
  Baz("ok").baz();  // Explicit reference to `Baz` extension.
  Bar("ok").bar();  // *Compile-time error*, `Bar` name has conflict.
  b.Bar("ok").bar();  // Valid explicit reference to `Bar` from bar.dart.
}
```

*Rationale*: We want users to have control over which extensions are available. They control this through the imports and declarations used to include declarations into the import scope or declaration scope of the library. The typical ways to control the import scope is using `show` /`hide` in the imports or importing into a prefix scope. These features work exactly the same for extensions. On the other hand, we do not want extension writers to have to worry too much about name clashes for their extension names since most extension members are not accessed through that name anyway. In particular we do not want them to name-mangle their extensions in order to avoid hypothetical conflicts. So, all imported extensions are considered in scope, and choosing between the individual extensions is handled as described in the next section. You only run into problems with the extension name if you try to use the name itself. That way you can import two extensions with the same name and use the members without issue (as long as they don't conflict in an unresolvable way), even if you can only refer to *at most* one of them by name.

You still cannot *export* two extensions with the same name.

### Extension Member Resolution

The declaration introduces an extension. The extension's `on` type defines which types are being extended.

For any member access, `x.foo`, `x.bar()`, `x.baz = 42`, `x(42)`, `x[0] = 1` or `x + y`, including null-aware and cascade accesses which effectively desugar to one of those direct accesses, and including implicit member accesses on `this`, the language first checks whether the static type of `x` has a member with the same base name as the operation. That is, if it has a corresponding instance member, respectively, a `foo` method or getter or a `foo=` setter. a `bar` member or `bar=` setter, a `baz` member or `baz=` setter, a `call` method, a `[]=` operator or a `+` operator. If so, then the operation is unaffected by extensions. *This check does not care whether the invocation is otherwise correct, based on number or type of the arguments, it only checks whether there is a member at all.*

(The type `dynamic` is considered as having all members, a member access on the type `void` is always a compile-time error, and `Never`, introduced with NNBD, will behave as one of those two, so none of these can ever be affected by static extension methods. The type `Function` and all function types are considered as having a `call` member on top of any members inherited from `Object`. Methods declared on `Object` are available on all types and can therefore never be affected by extensions).

If there is no such member, the operation is currently a compile-time error. In that case, all extensions in scope are checked for whether they apply. *That is, extension members only apply to code that would currently be a compile-time error*. An extension applies to a member access if the static type of the receiver is a subtype of the `on` type of the extension *and* the extension has an instance member with the same base name as the operation. 

For generic extensions, standard type inference is used to infer the type arguments before comparing to the `on` type. As an example, take the following extension:

```dart
extension MyList<T extends Comparable<T>> on List<T> {
  void quickSort() { ... }
}
```

and a member access like:

```dart
List<Duration> times = ...;
times.quickSort();
```

Here we perform type inference equivalent to what we would do for:

```dart
class MyList<T extends Comparable<T>> {
  MyList(List<T> argument);
  void quickSort() { ... }
}
...
List<Duration> times = ...;
... MyList(times).quickSort() ... // Infer type argument of MyList here.
```

or for:

```dart
void Function() MyList$quickSort<T extends Comparable<T>>(List<T> $this) => 
    () { ... }
...
  MyList$quickSort(times)();
```

This is inference based on static types only. The inferred type argument becomes the value of `T` for the function invocation that follows. Notice that the context type of the invocation does not affect whether the extension applies, and neither the context type nor the method invocation affects the type inference, but if the extension method itself is generic, the context type may affect the member invocation.

If the inference fails, or if the synthetic constructor invocation (`MyList(times)` in the above example) would not be statically valid for any other reason, then the extension does not apply. If an extension does not have an instance member with the base name `quickSort`, it does not apply.

If exactly one extension applies to an otherwise failed member invocation, then that invocation becomes an invocation of the corresponding instance member of the extension, with `this` bound to the receiver object and extension type parameters bound to the inferred types.

If the member is itself generic and has no type parameters supplied, normal static type inference applies again.

It is *as if* the invocation `times.quickSort` was converted to `MyList<Duration>(times).quickSort()`. The difference is that there is never an actual `MyList` object, and the `this` object inside `quickSort` is just the `times` list itself (although the extension methods apply to that code too).

### Generic Parameter Inference

If both the extension and the method is generic, then inference must infer the extension type parameters first, to figure out whether the extension applies, and only then start inferring method type parameters. As mentioned above, the inference is similar to other cases of chained inference. 

Example:

```dart
extension SuperList<T> on List<T> {
  R foldRight<R>(R base, R combine(T element, R accumulator)) {
    for (int i = this.length - 1; i >= 0; i--) {
      base = combine(this[i], base);
    }
    return base;
  }
}
...
  List<String> strings = ...;
  int count(String string, int length) => length + string.length;
  ...
  var length = strings.foldRight(0, count);
```

Here the inference occurs just as if the extension had been declared like:

```dart
class SuperList<T> {
  final List<T> $this;
  SuperList(this.$this);
  R foldRight<R>(R base, R Function(T, R) combine) { ... }
}
```

and it was invoked as `SuperList(strings).foldRight(0, count)`.

Or, alternatively, like the extension method had been declared like:

```dart
R Function<R>(R, R Function(T, R)) SuperList$foldRight<T>(List<T> $this) =>
    <R>(R base, R Function(T, R) combine) { ... };
```

and it was invoked as `SuperList$foldRight(strings)(0, count)`.

In either case, the invocation of the `foldRight` method does not contribute to the inference of `T` at all, but after `T` has been inferred.

The extension type parameter can also occur as a parameter type for the method.

Example:

```dart
extension TypedEquals<T> {
  bool equals(T value) => this == value;
}
```

Using such an extension as:

```dart
Object o = ...;
String s = ...;
print(s.equals(o));  // Compile-time type error.
```

will fail. While we could make it work by inferring `T` as `Object`, we don't. We infer `T` *only* based on the receiver type, and therefore `T` is `String`, and `o` is not a valid argument (at least not when we remove implicit downcasts).

### Extension Conflict Resolution

If more than one extension applies to a specific member invocation, then we resort to a heuristic to choose one of the extensions to apply. If exactly one of them is "more specific" than all the others, that one is chosen. Otherwise it is a compile-time error.

An extension with `on` type clause *T*<sub>1</sub> is more specific than another extension with `on` type clause *T*<sub>2</sub> iff 

1. The latter extension is declared in a platform library, and the former extension is not, or
2. they are both declared in platform libraries or both declared in non-platform libraries, and
3. the instantiated type (the type after applying type inference from the receiver) of *T*<sub>1</sub> is a subtype of the instantiated type of *T*<sub>2</sub> and either
4. not vice versa, or
5. the instantiate-to-bounds type of *T*<sub>1</sub> is a subtype of the instantiate-to-bounds type of *T*<sub>2</sub> and not vice versa.

This definition is designed to ensure that the extension chosen is the one that has the most precise type information available, while ensuring that a platform library provided extension never conflicts with a user provided extension. We avoid this because it allows adding extensions to platform libraries without breaking existing code when the platform is upgraded.

That is, the specificity of an extension wrt. an application depends of the type it is used at, and how specific the extension is itself (what its implementation can assume about the type). 

Example:

```dart
extension SmartIterable<T> on Iterable<T> {
  void doTheSmartThing(void Function(T) smart) {
    for (var e in this) smart(e);
  }
}
extension SmartList<T> on List<T> {
  void doTheSmartThing(void Function(T) smart) {
    for (int i = 0; i < length; i++) smart(this[i]);
  }
}
...
  List<int> x = ....;
  x.doTheSmartThing(print);
```

Here both the extensions apply, but the `SmartList` extension is more specific than the `SmartIterable` extension because `List<dynamic>` &lt;: `Iterable<dynamic>`.

Example:

```dart
extension BestCom<T extends num> on Iterable<T> { T best() {...} }
extension BestList<T> on List<T> { T best() {...} }
extension BestSpec on List<num> { num best() {...} }
...
  List<int> x = ...;
  var v = x.best();
  List<num> y = ...;
  var w = y.best();
```

Here all three extensions apply to both invocations.

For `x.best()`, the most specific one is `BestList`. Because `List<int>` is a proper subtype of both ` iterable<int>` and `<List<num>`, we expect `BestList` to be the best implementation. The return type causes `v` to have type `int`. If we had chosen `BestSpec` instead, the return type could only be `num`, which is one of the reasons why we choose the most specific instantiated type as the winner. 

For `y.best()`, the most specific extension is `BestSpec`. The instantiated `on` types that are compared are `Iterable<num>` for `Best
Com` and `List<num>` for the two other. Using the instantiate-to-bounds types as tie-breaker, we find that `List<Object>` is less precise than `List<num>`, so the code of `BestSpec` has more precise information available for its method implementation. The type of `w` becomes `num`.

In practice, unintended extension method name conflicts are likely to be rare. Intended conflicts happen where the same author is providing more specialized versions of an extension for subtypes, and in that case, picking the extension which has the most precise types available to it is considered the best choice.

### Overriding Access

If two or more extensions apply to the same member access, or if a member of the receiver type takes precedence over an extension method, or if the extension is imported with a prefix, then it is possible to force an extension member invocation:

```dart
MyList(object).quickSort();
```

or if you don't want the type argument to the extension to be inferred:

```dart
MyList<String>(object).quickSort();
```

or if you imported the extension with a prefix to avoid name collision:

```dart
prefix.MyList<String>(object).quickSort();
```

The syntax looks like a constructor invocation, but it does not create a new object.

If `object.quickSort()` would invoke an extension method of `MyList`, then `MyList(object).quickSort()` will invoke the exact same method in the same way.

The syntax is not *convenient*&mdash;you have to put the "constructor" invocation up front, which removes the one advantage that extension methods have over normal static methods. It is not intended as the common use-case, but as an escape hatch out of unresolvable conflicts.

An expression of the form `MyList(object)` or `MyList<String>(object)` must *only* be used for extension member access. It is a compile-time error to use it in any other way, similarly to how it is a compile-time error to use a *prefix* for anything other than member access. This also means that you cannot use an override expression as the receiver of a cascade, because a cascade does evaluate its receiver to a value. Unlike a prefix, it doesn't have to be followed by a `.` because extensions can also declare operators, but it must be followed by a `.`, a declared operator, or an arguments part (in case the extension implements `call`).

Notice that an explicit override introduces a type context for the *object*. Example:

```dart
extension SymDiff<T> on Set<T> {
  Set<T> symmetricDifference(Set<T> other) =>
      this.difference(other).union(other.difference(this))
}
...
  SymDiff({}).symmetricDifference(someSet);
```

Here the inference used to infer type parameters will also affect the extension receiver "parameter", and make `{}` a set literal.

### Static Members and Member Resolution

Static member declarations in the extension declaration can be accessed the same way as static members of a class or mixin declaration: By prefixing with the extension's name.

Example:

```dart
extension MySmart on Object {
  smart() => smartHelper(this);  // valid
  static smartHelper(Object o) { ... }
}
...
  MySmart.smartHelper(someObject);  // valid
```

Like for a class or mixin declaration, static members simply treat the surrounding declaration as a namespace.

### Semantics of Invocations

If an extension is found to be the one applying to a member invocation, then at run-time, the invocation will perform a method invocation of the corresponding instance member of the extension, with `this` bound to the receiver value and type parameters bound to the types found by static inference.

Prior to NNBD, all extension members can be invoked on a `null` value. Since `null` is a subtype of the `on` type, this is consistent behavior.

Post-NNBD, a non-nullable `on` type would not match a nullable receiver type, so it is impossible to invoke an extension method that does not expect `null` on a `null` value.

During NNBD migration, where a non-nullable type or a legacy unsafely nullable type may contain `null` , it is a run-time error if a migrated extension with a non-nullable `on` type is called on `null`, just as all other cases where an unsafe `null` reaches a non-nullable context. This requires a run-time check which can be omitted when all non-NNBD code has been migrated.

### Semantics of Extension Members

When executing an extension instance member, we stated earlier that the member is invoked with the original receiver as `this` object. We still have to describe how that works, and what the lexical scope is for those members.

Inside an extension method body, `this` does not refer to an instance of a surrounding type. Instead it is bound to the original receiver, and the static type of `this` is the declared `on` type of the surrounding extension (which may contain unbound type variables).

Invocations on `this` use the same extension method resolution as any other code. Most likely  the current extension will be the only one in scope which applies. It definitely applies to its own declared `on` type.

Like for a class or mixin member declaration, the names of the extension members, both static and instance, are in the *lexical* scope of the extension member body. That is why `MySmart` above can invoke the static `smartHelper` without prefixing it by the extension name. In the same way, *instance* member declarations (the extension members) are in the lexical scope. 

If an unqualified identifier lexically resolves to an extension method of the surrounding extension, then that identifier is not equivalent to `this.id`, rather the invocation is equivalent to an explicit invocation of that extension method on `this` (which we already know has a compatible type for the extension): `Ext<T1,…,Tn>(this).id`, where `Ext` is the surrounding extension and `T1` through `Tn` are its type parameters, if any. The invocation works whether or not the names of the extension or parameters are actually accessible, it is not a syntactic rewrite.

Example:

```dart
extension MyUnaryNumber on List<Object> {
  bool get isEven => length.isEven;
  bool get isOdd => !isEven;
  static bool isListEven(List<Object> list) => list.isEven;
}
```

Here the `list.isEven` will find that `isEven` of `MyUnaryNumber` applies, and unless there are any other extensions in scope, it will call that. (Or unless someone adds an `isEven` member to `List`, but that's a breaking change, and then, if still necessary, this code can change the call to `MyUnaryNumber(list).isEven`.)

The unqualified `length` of `isEven` is not defined in the current lexical scope, so is equivalent to  `this.length`, which is valid since `List<Object>` has a `length` getter.

The unqualified `isEven` of `isOdd` resolves lexically to the `isEvent` getter above it, so it is equivalent to `MyUnaryNumber(this).isEven`,  even if there are other extensions in scope which define an `isEven` on `List<Object>`.

An unqualified identifier `id` which is not declared in the lexical scope at all, is considered equivalent to `this.id` as usual. It is subject to extension if `id` is not declared by the static type of `this`.

Even though you can access `this`, you cannot use `super` inside an extension method.

### Member Conflict Resolution

An extension can declare a member with the same (base-)name as a member of the type it is declared on. This does not cause a compile-time conflict, even if the member does not have a compatible signature.

Example:

```dart
extension MyList<T> on List<T> {
  void add(T value, {int count = 1}) { ... }
  void add2(T value1, T value2) { ... }
}
```

You cannot *access* this member in a normal invocation, so it could be argued that you shouldn't be allowed to add it. We allow it because we do not want to make it a compile-time error to add an instance member to an existing class just because an extension is already adding a method with the same name. It will likely be a problem if any code *uses* the method, but only that code needs to change (perhaps using an override to keep using the extension).

An unqualified identifier in the extension can refer to any extension member declaration, so inside an extension member body, `this.add` and `add` are not necessarily the same thing (if the `on` type has an `add` member, then `this.add` refers to that, while `add` refers to the extension method in the lexical scope). This may be confusing. In practice, extensions will rarely introduce members with the same name as their `on` type's members.

### Tearoffs

A static extension method can be torn off like an instance method.

```dart
extension Foo on Bar {
  int baz<T>(T x) => x.toString().length;
}
...
  Bar b = ...;
  int Function(int) func = b.baz;
```

This assignment does a tear-off of the `baz` method. In this case it even does generic specialization, so it creates a function value of type `int Function(int)` which, when called with argument `x`, works just as `Foo(b).baz<int>(x)`, whether or not`Foo` is in scope at the point where the function is called. The torn off function closes over both the extension method, the receiver, and any type arguments to the extension, and if the tear-off is an instantiating tear-off of a generic method, also over the type arguments that it is implicitly instantiated with. The tear-off effectively creates a curried function from the extension:

```dart
int Function(int) func = (int x) => Foo(b).baz<int>(x);
```

*Torn off extension methods are never equal unless they are identical*. Unlike instance methods, which are equal if it's the same method torn off from the same object (unless it's an instantiated tear-off of a generic function), torn off extension methods may close over the type variables of the extension as well. To avoid distinction between generic and non-generic extensions, no two torn off extension methods are equal, even if they are torn off from the same extension on the same object at the same static type.

Extension methods torn off *constant* receiver expressions are not constant expressions. They also create a new function object each time the tear-off expression is evaluated.

An explicitly overridden extension method access, like `Foo<Bar>(b).baz`, also works as a tear-off. 

There is still no way to tear off getters, setters or operators. If we ever introduce such a feature, it should work for extension methods too.

### The `call` Member

An instance method named `call` is implicitly callable on the object, and implicitly torn off when assigning the instance to a function type.

As the initial examples suggest, an extension method named `call` can also be called implicitly. The following should work:

```dart
extension Tricky on int {
 	Iterable<int> call(int to) => 
      Iterable<int>.generate(to - this + 1, (i) => i + this);
}
...
  for (var i in 1(10)) { 
    print(i);  // prints 1, 2, 3, 4, 5, 6, 7, 8, 9, 10.
  }
```

This looks somewhat surprising, but not much more surprising that an extension `operator[]` would: `for (var i in 1[10])...`. We will expect users to use this power responsibly.

In detail: Any expression of the form `e1(args)` or `e1<types>(args)` where `e1` does not denote a method, and where the static type of `e1` is not a function type, an interface type declaring a `call` method, or `dynamic,` will currently be a compile-time error. If the static type of `e1` is an interface type declaring a `call` *getter*, then this stays a compile-time error. Otherwise we check for extensions applying to the static type of `e1` and declaring a `call` member. If one such most specific extension exists, and it declares a `call` extension method, then the expression is equivalent to `e1.call(args)` or `e1.call<typeS>(args)`. Otherwise it is still a compile-time error.

A second question is whether this would also work with implicit `call` method tear-off:

```dart
Iterable<int> Function(int) from2 = 2;
```

This code will find, during type inference, that `2` is not a function. It will then find that the interface type `int` does not have a `call` method, and inference will fail to make the program valid.  

We could allow an applicable `call` extension method to be coerced instead, as an implicit tear-off. We will not do so.

That is: We do *not* allow implicit tear-off of an extension `call` method in a function typed context.

This implicit conversion would come at a readability cost. A type like `int` is well known as being non-callable, and an implicit `.call` tear-off would have no visible syntax at the tear-off point to inform the reader what is going on. For implicit `call` invocations, the *arguments* are visible to a reader, but for implicit coercion to a function, there is no visible syntax at all.

## Migration and Breaking Changes

Introduction of static extension methods is a non-breaking change to the language. No existing correct programs will change behavior.

### Breaking Changes for Extension Methods

Introducing a new extension to an existing library has the same problems as adding any other top-level name: A potential naming conflict. It may also change the behavior of existing extension member invocations if it causes an extension resolution conflict, and it wins by being more specific than the currently used extension. Barring an extension member conflict, adding an extension will not change the behavior of any code that isn't already a compile-time error. The choice of making interface instance members take precedence over extension methods ensures this.

Adding an instance member to a class may now change behavior of code relying on extension methods. Adding instance members to interfaces is already breaking in case someone implements the interface. With extension methods, it may be breaking even for classes that are never implemented.

### Migration

The static extension methods feature will be released after the language versioning feature.

As such, enabling extensions methods will require upgrading the library's language level to the version where extension methods are released. Since the language change is non-breaking, libraries should be able to simply upgrade their SDK dependency to the newer version and all existing code should keep working.

A library which is at a language versions prior to the release of static extension methods will not be able to use extension members:

- It cannot declare an extension.
- it cannot refer to an imported extension.
- It cannot invoke an imported extension member.
- It *can* re-export an extension from another library.

A library which has not enabled static extension members cannot use the new syntax. It also cannot use the *override* syntax (`MyExt(o).member()`) even though it is grammatically valid as a function or constructor invocation. The extension is neither a class nor a function.

If such a library imports an extension declaration, say `MyExt`, then any reference to that imported name is a compile-time error, the same way as accessing a name-conflicting import. The imported declaration is still there, and can cause naming conflicts, but attempting to use it is disallowed.

Invocations which would otherwise check for extension members, do not. It is as if there are no extensions in scope, even if some were imported.

The library can export any other library, and will do so blindly without needing to understand the exported declarations. The exporting library can still cause a naming conflict if it exports something else with the same name as an exported extension.

*This is not the only possible option. It might be possible to enable use of extensions in libraries which cannot declare them. However, it would be only half a feature without the syntax for extension member override, and enabling that syntax would also be inconsistent. As such, the simplest and safest approach is to _disable_ extensions completely in legacy libraries. The cost of enabling extensions is trivial since it will merely be a matter of increasing the library SDK requirement. There is no migration needed for a non-breaking change.*

## Interaction With Potential Future Features

### Non-Null by Default

The interaction with NNBD was discussed above. It will be possible to declare extensions on nullable and non-nullable types, and on a nullable type, `this` may be bound to `null`.

### Sealed Classes

If we introduce sealed classes, we may want to consider whether to allow extensions on sealed classes, since adding members even to a sealed class could still be a breaking change.

One of the reasons for having sealed classes is that it ensures the author can add to the interface without breaking code. If adding a member changes the meaning of code which currently calls an extension member, that reason is eliminated. 

Since it's possible to add extensions on superclass (including `Object`), it would not be sufficient to disallow *declaring* extensions on a sealed class, you would have to disallow *invoking* an extension on a sealed class, at least without an explicit override (which would also prevent breaking if a similarly named instance member is added).

## Summary

- Extensions are declared using the syntax:

  ```ebnf
  <extension> ::= `extension' <identifier>? <typeParameters>? `on' <type> `?'?
     `{'
       <memberDeclaration>*
     `}'
  ```

  where `extension` becomes a built-in identifier and `<memberDeclaration>` does not allow instance variables, constructors or abstract members. It does allow static members.

- The extension declaration introduces a name (`<identifier>`) into the surrounding scope. 

  - The name can be shown or hidden in imports/export. It can be shadowed by other declarations as any other top-level declaration.
  - The name can be used as prefix for invoking static members (used as a namespace, same as class/mixin declarations).

- A member invocation (getter/setter/method/operator) which targets a member that is not on the static type of the receiver (no member with same base-name is available) is subject to extension application.  It would otherwise be a compile-time error.

- An extension applies to such a member invocation if 

  - the extension is declared or imported in the lexical scope,
  - the extension declares an instance member with the same base name, and 
  - the `on` type (after type inference) of the extension is a super-type of the static type of the receiver.

- Type inference for `extension Foo<T> on Bar<T> { baz<S>(params) => ...}` for an invocation `receiver.baz(args)` is performed as if the extension was a class:

  ```dart
  class Foo<T> {
    Bar<T> _receiver;
    Foo(Bar<T> this._receiver);
    void baz<S>(params) => ...;
  }
  ```

  that was invoked as `Foo(receiver).baz(args)`. The binding of `T` and `S` found here is the same binding used by the extension.  If the constructor invocation would be a compile-time error, the extension does not apply.

- One extension is more specific than another if the former is a non-platform extension and the latter is a platform extension, or if the instantiated `on` type of the former is a proper subtype of the instantiated `on` type of the latter, or if the two instantiated types are equivalent and the instantiate-to-bounds `on` type of the former is a proper subtype of the one on the latter. 

- If there is no single most-specific extension which applies to a member invocation, then it is a compile-time error. (This includes the case with no applicable extensions, which is just the current behavior).

- Otherwise, the single most-specific extension's member is invoked with the extension's type parameters bound to the types found by inference, and with `this ` bound to the receiver.

- An extension method can be invoked explicitly using the syntax `ExtensionName(object).method(args)`. Type arguments can be applied to the extension explicitly as well, `MyList<String>(listOfString).quickSort()`. Such an invocation overrides all extension resolution. It is a compile-time error if `ExtensionName` would not apply to the `object.method(args)` invocation if it was in scope. 

- The override can also be used for extensions imported with a prefix (which are not otherwise in scope): `prefix.ExtensionName(object).method(args)`.

- An invocation of an extension method succeeds even if the receiver is `null`. With NNBD types, the invocation throws if the receiver is `null` and the instantiated `on` type of the selected extension does not accept `null`. (In most cases, this case can be excluded statically, but not for unsafely nullable types like `int*`).

- Otherwise an invocation of an extension method runs the instance method with `this` bound to the receiver and with type variables bound to the types found by type inference (or written explicitly for an override invocation). The static type of `this` is the `on` type of the extension.

- Inside an instance extension member, extension members accessed by unqualified name are treated as extension override accesses on `this`. Otherwise invocations on `this` are treated as any other invocations on the same static type.

## Variants

The design above can be extended in the following ways.

### Multiple `on` Types

The `on <type>` clause only allows a single type. The similar clause on `mixin` declarations allow multiple types, as long as they can all agree on a single combined interface. 

We could allow multiple types in the `extension` `on` clause as well. It would have the following consequences:

- An extension only applies if the receiver type is a subtype of *all* `on` types.
- An extension is more specific than another if for every `on` type in the latter, there is an `on` type in the former which is a proper subtype of that type, or the two are equivalent, and the former is a proper subtype of the latter when instantiated to bounds.
- There is no clear type to assign to `this` inside an instance extension method. For a mixin that's not a problem because it introduces a type by itself, and the combined super-interface is only used for `super` invocations. For extension, a statement like `var self = this;` needs to be assigned a useful type.

The last item is the reason this feature is not something we will definitely do. We can start out without the feature and maybe add it later if it is necessary, but it's safer to start without it.

### Extending Static Members

The feature above only extends instance members. There is no way to add a new static member on an existing type, something that should logically be a *simpler* operation.

We could allow

```dart
extension MyInt on num {
  int get double => this * s;
  static int get random => 4;
}
```

to introduce both a `double` instance getter on `num` instances and a `random` getter on `num` itself, usable as `var n = num.random;`

However, while this is possible, not all `on` types are class or mixin types. It is not clear what it would mean to put static methods on `on` types of extension like:

- `extension X on Iterable<int>`
- `extension X<T extends Comparable<T>> on Iterable<T>`
- `extension X on int Function(int)`
- `extension X on FutureOr<int>`
- `extension X on int?`

For the first two, we could put the static members on the `Iterable` class, but since the extension does not apply to *all* iterables, it is not clear that this is correct.

For `int Function(int)` and `FutureOr<int>`, it's unclear how to call such a static method at all. We can denote`int Function(int)` with a type alias, but putting static members on type aliases is a new concept.  We could put the static method on `Function`, but that's not particularly discoverable, and why not require that they are put on `Functon` explicitly. For `FutureOr`, we could allow static members on `FutureOr` (which is a denotable type), but again it seems spurious. For `int?`, we could put the method on `int`, but why not  just require that it's on `int`.

The issue here is that the type patterns used by `on` are much more powerful than what is necessary to put static members on class types.

It would probably be more readable to introduce a proper static extension declaration:

```dart
static extension Foo on int {  // or: extension Foo on static int 
  int fromList(List l) => l.length;
}

...
  print(int.fromList([1, 2])); // 2
```

where the `on` type must be something that can already have static methods. 

The disadvantage is that if you want to introduce related functionality that is both static and instance methods on a class, then you need to write two extensions with different names.

If we allow extension static declarations like these, we can also allow extension constructors.

### Aliasing

If we have two different extensions with the same name, they can't both be in scope, even if they don't apply to the same types. At least one of them must be delegated to a prefixed import scope, and if so, it doesn't *work* as an extension method any more.

To overcome this issue, we can use a *generalized typedef* to give a new name to an existing entity in a given scope. Example:

```dart
typedef MyCleverList<T> = prefix.MyList<T>;
```

If `prefix.MyList` is an extension, this would put that extension back in the current scope under a different name (use a private name to avoid exporting the extension again).

If we do this, we should be *consistent* with other type aliases, which means that the type parameter of the RHS must be explicit. Just writing

```drt
typedef MyCleverList = prefix.MyList; // bad!
```

would make `MyCleverList` an alias for `prefix.MyList<dynamic>`, which would still apply to `List<anything>`, but the type variable of `MyList` will always be `dynamic`. Similarly, we can put more bounds on the type variable:

```dart
typedef MyWidgetList<T extends Widget> = prefix.MyList<T>;
```

Here the extension will only apply if it matches `Widget` *and* would otherwise match `MyList` (but `T` needs to be a valid type argument to `MyList`, which means that it must satisfy all bounds of `MyList` as well, otherwise the typedef is rejected).

The use of `typedef` for something which is not a type may be too confusing. Another option is:

```dart
extension MyWidgetList<T extends Widget> = prefix.MyList<T>;
```

## Revisions

#### 1.0

- Initial version.

#### 1.1:

- Removed `?` after types. The behavior was subtly inconsistent with the eventual NNBD behavior of a nullable type. Instead all extensions can be invoked on `null` until we get NNBD.
- Sepcified that override syntax like `MyList(o)` can only be used for member access, not as an expression with a value.
