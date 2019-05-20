# Dart Static Extension Methods Design

lrn@google.com<br>Version: 1.0<br>Status: Design Proposal

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

The code is also much less discoverable. An IDE can suggest `doMyStuff()` after `something.doStuff().`, but will be unlikely to suggest putting `doMyOherStuff(…)` around the expression.

For these discoverability and readability reasons, static extension methods will allow you to add "extension methods", which are really just static functions, to existing types, and allow you to discover and call those methods as if they were actual methods, using `.`-notation. It will not add any new abilities to the language which are not already available, they just require a more cumbersome and less discoverable syntax to reach.

The extension methods are *static*, which means that we use the static type of an expression to figure out which method to call, and that also means that static extension methods are not virtual methods.

The methods we allow you to add this way are normal methods, operators, getter and setters.

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
  `extension' <identifier> <typeParameters>? `on' <type> `?'? `{'
     memberDeclaration*
  `}'
```

Such a declaration introduces its *name* (the identifier) into the surrounding scope. The name does not denote a type, but it can be used to denote the extension itself in various places. The name can be hidden or shown in `import` or `export` declarations.

The *type* can be any valid Dart type, including a single type variable. It can refer to the type parameters of the extension. It can be followed by `?` which means that it allows `null` values. When Dart gets non-nullable types by default (NNBD), this `?` syntax is removed and subsumed by nullable types like `int?` being allowed in the `<type>` position.

The member declarations can be any static or instance member declaration except for instance variables and constructors.

### Scope

Dart's static extension methods are *scoped*. They only apply to code that the extension itself is accessible to. Being accessible means that using the extension's name must denote the extension. The extension is not in scope if another declaration with the same name shadows the extension, if the extension's library is not imported, if the library is imported and the extension is hidden, or the library is only imported with a prefix. In other words, if the extension had been a class, it is only in scope if using the name would denote the class&mdash; which will allow you to call static methods on the class, which is exactly what we are going to do.

### Extension Member Resolution

The declaration introduces an extension. The extension's `on` type defines which types are being extended.

For any member access, `x.foo`, `x.bar()`, `x.baz = 42`, `x(42)` or `x + y`, the language first checks whether the static type of `x` has a member with the same base name as the operation. That is, if it has a corresponding instance member, respectively, a `foo` method or getter or a `foo=` setter. a `bar` member or `bar=` setter, a `baz` member or `baz=` setter, a `call` method, or a `+` method. If so, then the operation is unaffected by extensions. *This check does not care whether the invocation is otherwise correct, based on number or type of the arguments, it only checks if there is a member at all.*

(The types `dynamic` and `Never` are considered as having all members, the type `void` is always a compile-time error when used in a receiver position, so none of these can ever be affected by static extension methods).

If there is no such member, the operation is currently a compile-time error. In that case, all extensions in scope are checked for whether they apply. An extension applies to a member access if the static type of the receiver is a subtype of the `on` type of the extension *and* the extension has an instance member with the same base name as the operation. 

For generic extensions, standard type inference is used to infer the type arguments. As an example, take the following extension:

```dart
extension MyList<T extends Comparable<T>> on List<T> {
  void quickSort() { ... }
}
```

and a member access like:

```dart
Uint8List bytes = ...;
bytes.quickSort();
```

Here we perform type inference equivalent to what we would do for:

```dart
class MyList<T extends Comparable<T>> {
  MyList(List<T> argument);
  void quickSort() { ... }
}
...
Uint8List bytes = ...;
... MyList(bytes).quickSort() ... // Infer type argument of MyList here.
```

This is inference based on static types only. The inferred type argument becomes the value of `T` for the function invocation that follows.

If the inference fails, or if the synthetic constructor invocation would not be valid for any other reason, then the extension does not apply. If the extension does not have an instance member with the base name `quickSort`, it does not apply.

If exactly one extension applies to an otherwise failed member invocation, then that invocation becomes an invocation of the corresponding instance member of the extension, with `this` bound to the receiver object and type parameter bound to the inferred types.

If the member is itself generic and has no type parameters supplied, normal static type inference applies again.

It is *as if* the invocation `bytes.quickSort` was converted to `MyList<int>(bytes).quickSort()`. The difference is that there is never an actual `MyList` object, and the `this` object inside `quickSort` is just the `bytes` list itself (although the extension methods apply to that code too).

### Extension Conflict Resolution

If more than one extension applies to a specific member invocation, then if exactly one of them is more specific than all the others, that one is chosen. Otherwise it is a compile-time error.

An extension with `on` type clause *T*<sub>1</sub> is more specific than another extension with `on` type clause *T*<sub>2</sub> iff the instantiated type (the type after applying type inference from the receiver) of *T*<sub>1</sub> is a subtype of the instantiated type of *T*<sub>2</sub> and either:

- not vice versa, or
- the instantiate-to-bounds type of *T*<sub>1</sub> is a subtype of the instantiate-to-bounds type of *T*<sub>2</sub> and not vice versa.

This definition is designed to ensure that the extension chosen is the one that has the most precise type information available.

If an extension's `on` type has a trailing `?`, say `T?`, then we treat it just as we would for the corresponding nullable type with NNBD types, which are described in a separate design document. In short, it means treating the type `T?`, for subtyping purposes, as a union type of `T` with `Null` (a least supertype of `T` and `Null`).

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
extension BoxCom<T extends Comparable<T>> on Box<Iterable<T>> { T best() {...} }
extension BoxList<T> on Box<List<T>> { T best() {...} }
extension BoxSpec on Box<List<num>> { num best() {...} }
...
  List<int> x = ...;
  var v = x.best();
  List<num> y = ...;
  var w = y.best();
```

Here all three extensions apply to both invocations.

For `x.best()`, the most specific one is `BoxList`. Because `Box<List<int>>` is a proper subtype of both ` Box<iterable<int>>` and `Box<List<num>>`, we expect `BoxList` to be the best implementation. The return type causes `v` to have type `int`. If we had chosen `BoxSpec` instead, the return type could only be `num`, which is why we choose the most specific instantiated type as the winner. 

For `y.best()`, the most specific extension is `BoxSpec`. The instantiated `on` types that are compared are `Box<Iterable<num>>` for `BoxCom` and `Box<List<num>>` for the two other. Using the instantiate-to-bounds types as tie-breaker, we find that `Box<List<Object>>` is less precise than `Box<List<num>>`, so the code of `BoxSpec` has more precise information available for its method implementation. The type of `w` becomes `Box<List<num>>`.

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

This mode of invocation also allows invocation of extensions that are *not* in scope, perhaps as `prefix.MyExtension(object).extensionMember()` if imported with a prefix.

The syntax is not *convenient*&mdash;you have to put the "constructor" invocation up front, which removes the one advantage that extension methods have over normal static methods. It is not intended as the common use-case, but as an escape hatch out of conflicts.

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

### Semantics of Invocations

If an extension is found to be the one applying to a member invocation, then at run-time, the invocation will perform a method invocation of the corresponding instance member of the extension, with `this` bound to the receiver value and type parameters bound to the types found by static inference.

If the receiver is `null`, then that invocation is an immediate run-time error unless the `on` type of the extension has a trailing `?`.

With NNBD types, it is a run-time error if the receiver is `null` and the instantiated `on` type of the selected extension does not allow `null`. For sound non-nullable types, this can be excluded statically. If a receiver expression is nullable, then the matching `on` type must be nullable too. If a receiver expression is soundly non-nullable, then the value cannot be `null` at run-time. During migration, we will have unsound nullable types like `int*` which should be matched by `extension Wot on int {…}`, and in that case we will need a run-time check to avoid passing `null` to that extension.

### Semantics of Extension Members

When executing an extension instance member, we stated earlier that the member is invoked with the original receiver as `this` object. We still have to describe how that works, and what the lexical scope is for those members.

Inside an extension declaration, we give preference to that extension over any other extension. At any otherwise invalid invocation, if the current extension applies, then it is considered more specific than all other extensions that may apply. This applies to static methods too. 

Example:

```dart
extension MyUnaryNumber on List<Object> {
  bool get isEven => this.length.isEven;
  bool get isOdd => !this.isEven;
  static bool isListEven(List<Object> list) => list.isEven;
}
```

Here the `list.isEven` is  guaranteed to hit the `isEven` of the same extension (unless someone puts an `isEven` member on `List`), an extension has more specificity than any other extension inside itself.

About *`this`*: Inside an instance member of an extension, the static type of the `this` operator is the `on` type. However, for member invocations, we give preference to extension methods of the current extension, *even over members of the `on` type*. 

Here, the `this.isEven` is a member invocation on `this`, so it *first* tries to resolve `isEven` against the current extension. If it finds a member with the same base name on the extension, that member is invoked with the same `this` value. If not, then it is considered a normal member invocation on an object with static type `List<Object>,` and if `List<Object>` does not have the necessary member, then all applicable extensions are checked (which will definitely not match the current extension since we already checked that).

The behavior is *only* for the `this` operator. Doing something like `var self = this; self.isEven;` will not give preference over members of `List` (if `List` had an `isEven`, then `self.isEven` would invoke that, where `this.isEven` will invoke the extension method). It is as if `this` has a type representing the extension, even if no such type actually exists.

This behavior makes the extension act similarly to a class, which will hopefully make it easier for users to understand the resolution.

Like for a class or mixin member declaration, the names of the extension members, both static and instance, are in the *lexical* scope of the extension member. That is why `MySmart` above can invoke the static `smartHelper` without prefixing it by the extension name. In the same way, *instance* members are in the lexical scope. 

Example:

```dart
extension MyUnaryNumber on List<Object> {
  bool get isEven => this.length.isEven;
  bool get isOdd => !isEven;  // not `!this.isEven`
}
```

Here, the `isEven` name exists in the surrounding static scope, so just as for `class` members, it is considered equivalent to `this.isEven`. Because of how we treat `this`, it means that `isEven` and `this.isEven` means the same thing when the extension declares an `isEven` member, just as for a class or mixin declaration.

### Member Conflict Resolution

An extension can declare a member with the same (base-)name as the type it is declared on. This does not cause a compile-time conflict, even if the member does not have a compatible signature.

Example:

```dart
extension MyList<T> on List<T> {
  void add(T value, {int count = 1}) { ... }
  void add2(T value1, T value2) { ... }
}
```

You cannot *access* this member in a normal invocation, so it could be argued that you shouldn't be allowed to add it. We allow it because we do not want to make it a compile-time error for a type to add a method just because an extension is already adding a method with the same name. it will likely be a problem if any code *uses* the method, but only that code needs to change (perhaps using an override).

That also means that an extension can shadow members of the `on` type.  To implement `add2` above, we don't want to call `this.add`, instead we want to use the `add` of `List` directly. To do that, we allow `super` invocations to target the underlying `on` type directly, with *no* extensions applying.

```dart
void add2(T value1, T value2) {
  super..add(value1)..add(value2);
}
```

### Tearoffs

A static extension method can be torn off like any other instance method.

```dart
extension Foo on Bar {
  int baz<T>(T x) => x.toString().length;
}
...
  Bar b = ...;
  int Function(int) func = b.baz;
```

This assignment does a tear-off of the `baz` method. In this case it even does generic specialization, so it creates a function value of type `int Function(int)` which, when called with argument `x`, works just as `Foo(b).baz<int>(x)`, whether or not`Foo` is in scope at the point where the function is called. The torn off function closes over both the extension type and the receiver, and over any type arguments that it is implicitly instantiated with.

An explicitly overridden extension method, like `Foo<Bar>(b).baz` also works as a tear-off. 

There is still no way to tear off getters, setters or operators. If we ever introduce such a feature, it should work for extension methods too.

## Summary

- Extensions are declared using the syntax:

  ```ebnf
  <extension> ::= `extension' <identifier><typeParameters>? `on' <type> `?'?
     `{'
       <memberDeclaration>*
     `}'
  ```

  where `extension` becomes a built-in identifier, `<type>` must not be a type variable, and `<memberDeclaration>` does not allow instance fields or constructors. It does allow static members.

- The extension declaration introduces a name (`<identifier>`) into the surrounding scope. 

  - The name can be shown or hidden in imports/export. It can be shadowed by other declarations as any other top-level declaration.
  - The name can be used as suffix for invoking static members (used as a namespace, same as class/mixin declarations).

- A member invocation (getter/setter/method/operator) which targets a member that is not on the static type of the receiver (no member with same base-name is available) is subject to extension application.  It would otherwise be a compile-time error.

- An extension applies to such a member invocation if 

  - the extension name is visible in the lexical scope,
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

- One extension is more specific than another if the instantiated `on` type of the former is a proper subtype of the instantiated `on` type of the latter, or if the two instantiated types are equivalent and the instantiate-to-bounds `on` type of the former is a proper subtype of the one on the latter.  An `on` type `T?`, with a trailing `?` works like a NNBD nullable type.

- If there is no single most-specific extension which applies to a member invocation, then it is a compile-time error. (This includes the case with no applicable extensions, which is just the current behavior).

- Otherwise, the single most-specific extension's member is invoked with the extension's type parameters bound to the types found by inference, and with `this ` bound to the receiver.

- An extension method can be invoked explicitly using the syntax `ExtensionName(object).method(args)`. Type arguments can be applied to the extension explicitly as well, `MyList<Object>(listOfString).quickSort()`. Such an invocation overrides all extension resolution. It is a compile-time error if `ExtensionName` would not apply to the `object.method(args)` invocation if it was in scope.  

- The override can also be used for extensions imported with a prefix (which are not otherwise in scope): `prefix.ExtensionName(object).method(args)`.

- An invocation of an extension method throws if the receiver is `null` unless the `on` type has a trailing `?`. With NNBD types, the invocation throws if the receiver is `null` and the instantiated `on` type of the selected extension does not accept `null`. (In most cases, this case can be excluded statically, but not for unsafely nullable types like `int*`).

- Otherwise an invocation of an extension method runs the instance method with `this` bound to the receiver and with type variables bound to the types found by type inference (or written explicitly for an override invocation).

- Inside an extension member, the current extension is considered more specific than any other extension, so if it applies to an invocation, then it doesn't matter which other extensions also apply.

- Inside an *instance* extension member,:

  - invocations on `this` check the current extension's members *before* the `on` type members.
  - in every other way the static type of `this ` is the `on` type.
  - A `super` invocations is an invocation on `this` allowing only members of the `on` type. No extension methods apply, from the current extension or any other.

## Variants

The design above can be extended in the following ways.

### Multiple `on` Types

The `on <type>` clause only allows a single type. The similar clause on `mixin` declarations allow multiple types, as long as they can all agree on a single combined interface. 

We could allow multiple types in the `extension` `on` clause as well. It would have the following consequences:

- An extension only applies if the receiver type is a subtype of all `on` types.
- An extension is more specific than another if for every `on` type in the latter, there is an `on` type in the former which is a proper subtype of that type, or the two are equivalent, and the former is a proper subtype of the latter when instantiated to bounds.
- The trailing `?` makes the most sense if it is applied only once (it's the extension which accepts and understands `null` as a receiver), but for forwards compatibility, we will need to put it on every `on` type individually. All `on` types must be nullable in order to accept a nullable receiver.
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

### Omitting Names For Local Extensions

If an extension declaration is only used locally in a library, there is no need to worry about naming conflicts or overrides. In that case, then name identifier can be omitted.

Example:

```dart
extension<T> on List<T> {
  void quadruple() { ... }
}
```

This is equivalent to giving the extension a fresh private name.

The grammar then becomes:

```ebnf
<extension> ::= 
  `extension' <identifier>? <typeParameters>? `on' <type> `?'? `{'
     memberDeclaration*
  `}'
```

This is a simple feature, but with very low impact. It only allows you to omit a single private name for an extension that is only used in a single library. Unless there is a documented demand for this feature, it doesn't seem worth the effort.

### Explicitly Specify Related Declarations

The above resolution strategy uses an implicit "more specific" relation between applicable extensions to select one of them (when possible). This may cause surprises when two unrelated extensions happen to both apply.

Alternatively, we can allow extensions to declare that they are *related*, and only allow conflicts between related extensions, which are presumably aware of each other.

The syntax would be:

```dart
extension Foo<T> on Iterable<T> { twizzle() {...} }
extension Bar<T> extends Foo on List<T> { twizzle() { ... } } 
```

If both of these extensions apply, then pick the one that extends the other. If there are more related extensions which apply, then pick one which transitively extends all the others.

If there isn't exactly one among applicable extensions which extends all the rest, the conflict is a compile-time error.

This approach allows related extensions to declare functionality on a number of types, without accidentally allowing a conflict with an unrelated extension.

### Explicitly Specify Related Declarations 2

Alternative syntax: Allow extensions with the same *name* to be related:

```dart
extension Foo<T> on Iterable<T> { twizzle() { ... } }
extension Foo<T> on List<T> { twizzle() { ... } }
```

Whenever an extension is declared with the same name as another extension in scope, it is considered as being *related*, which is an equivalence relation. The declaration extends the extension rather than conflicting with it. 

Only extension resolution conflicts between related extensions are allowed and resolved, any other conflict between applicable extensions is a compile-time error. We then still need to use an ordering relation on the `on` type to figure out which one is more specific in a particular case, and it can fail if there isn't one most specific applicable extension.

An explicit override like `Foo(something).twizzle()` would still have to pick the most specific applicable extension. There is no way to hide one part of an extension "cluster", and no way to override with a specific extension declaration since they all have the same name. If the extensions do not have the same number of type parameters, an explicit instantiated override like `Foo<int>(something)` won't apply to all of them, which may be confusing.

Maybe even allow combined declarations when the extensions do have the same type parameters:

```dart
extension Foo<T> 
  on Iterable<T> { twizzle() { ... } }
  on List<T> { twizzle() { ... } }
```

This shows that it really is a single thing being declared, even if we allow multiple declarations with the same name. (We can also choose not to allow multiple declarations, and require all related extensions to be declared in a single declaration with multiple `on` clauses like above).
