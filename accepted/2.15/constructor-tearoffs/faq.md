# Dart Constructor Tearoffs Feature FAQ

Author: lrn@google.com<br>Version: 1.0

This is a short summary of the _Constructor Tearoffs_ feature. This document is not intended as a specification, look at the feature specification for that. Instead it hopes to be a brief *introduction* to the feature set that we intend to release, and to answer some of the questions that it is hard to find short answers for in the specification.

## What are the new features?

In short:

* Named constructor tear-off (`C.name` is a valid expression).
* Named unnamed constructor (`C.new` is a constructor name, refers to the same constructor as "unnamed" `C` constructor).
* Function value instantiation (you can instantiate function *values*, not just tear-offs).
* Explicit instantiation (`List<int>` and `Future.then<int>` are valid type- and function-expressions).

## Named constructor tear-off

If *C* refers to a class, and *C* has a constructor *C*.*name*, then <code>*C*.*name*</code> can now be an expression which evaluates to a function with the same function signature as the constructor, and which, when called, does the same thing as the constructor.

Example:

```dart
// Has type: DateTime Function(int, [int, int, int, int, int, int, int])
var makeUtcDate = DateTime.utc; 
```

**Q:** What if the class is generic?

**A:** Then the function is also generic, with the same type arguments as the class.

Example:

```dart
// Has type: List<T> Function<T>(int, T)
var makeList = List.filled;
// Has type: Map<K, V> Function<K, V>(Iterable<MapEntry<K, V>>)
var makeMap = Map.fromEntries;
```

**Q:** Can I tear it off at a specific type argument?

**A:** Yes. Just like the current function tear-offs, the context type can be used to specify a type argument. It's really like the constructor tear-off is tearing off a generic function.

Example:

```dart
List<String> Function(int, String) makeList = List.filled; // Works!
```

**Q:** Can I write the type on the class, `List<int>.filled`, just like when calling?

**A:** *Yes*!

Example:

```dart
// Has type: List<String> Function(int, String) makeList
var makeList = List<String>.filled; // Works!
```

**Q:** Can I tear off an unnamed constructor too, as `var makeLocalDate = DateTime;`?

**A:** No, not like that. The expression `DateTime` still evaluates to a `Type` object. You have to use the "named unnamed constructor" feature and write it as `var makeLocalDate = DateTime.new;`. More on that later.

**Q:** What about `var makeSet = HashSet<int>;`?

**A:** No. With the "explicit instantiation" feature, `HashSet<int>` is also a `Type` object. More on that later.

**Q:** Can I write `List.filled<String>` instead of `List<String>.filled`?

**A:** No. We reserve type arguments at that location in case we later want to introduce [generic constructors](https://github.com/dart-lang/language/issues/647).

**Q:** I can call a constructor through a type alias, like `typedef MyMap<X> = Map<X, X>; … MyMap<int>.from(…) …`. Can I also tear off a constructor through an alias?

**A:** Yes! The goal is that if you can call a constructor, <code>*C*\<typeArgs>.*name*</code>, with arguments, you can tear off the constructor using the same syntax, and then call it later with the same arguments. That also applies to calls through type aliases. If the *alias* is generic, the tear-off will be a generic function (unless it's an instantiated tear-off) and will have the same type parameters as the *alias*. So, `MyMap.from` would have type `Map<X, X> Function<X>(Map<X, X>)`. 

**Q:** Is the tear-off of a `const` constructor a `const` value?

**A:** Yes, but really, all uninstantiated constructor tear-offs are constant values (just like all uninstantiated static/top-level method tear-offs). It doesn't matter whether the constructor is `const` or not. An *instantiated* tear-off (like `List<String> Function(int, String) makeList = List.filled;`) will be constant if the inferred type arguments are constant types, which they are if they contain no type variables (again, just as for static function tear-offs).

**Q:** Can I do a `const` invocation of a torn-off `const` constructor?

**A:** No. When you tear off a constructor, `const` or not, it results in a function value. At that point, all the language knows about it is its function type. You can only invoke constructors with `const` (or `new`), not arbitrary functions, and that value is not a constructor (it's a function which calls a constructor). To create a new constant value, you must specify the constant constructor directly in the `const` constructor invocation.

**Q:** Are tear-offs canonicalized? When are they equal?

**A:** Constant tear-offs are canonicalized. Non-constant tear-offs do try to be equal when they refer to the same constructor, and if type-instantiated, the same constructor with "the same" type arguments. There are complications when going through type aliases, so try to avoid that.

## Named unnamed constructor

A class name, like `DateTime`, evaluates to a `Type` object, which means we have no way to tear off the "unnamed constructor". To allow that, we allow you to refer to the unnamed constructor as `DateTime.new` *as well*.

Everywhere you can currently refer to an unnamed constructor, you will also be able write the same name followed by `.new`. It means exactly the same thing as the unnamed constructor. Everywhere you can use a named constructor, you can use `.new` to refer to the unnamed constructor as if it was named.

Example:

```dart
class C<T> {
  const C.new();
  C.named() : this.new();
  /// Calls [C.new].
  factory C.otherNamed() = C<T>.new;  
}
class D {
  D() : super.new();
}
void main() {
  var cs = [C<int>.new(), const C<int>.new(), new C<int>.new()];
  var tearoff = C.new; // New!
  var explicitlyTypedTearoff = C<int>.new; // New!
}
```

Everywhere except the tear-offs, you can remove the `.new`  and it means the same thing. The tearoff is the only place which *requires* the `.new`.

**Q:** Should I use `.new` or not. What does the style guide say?

**A:** The style guide says nothing yet. As with most language features, we are deliberately avoiding making any style recommendations early on so that we can see what kind of a style the community as a whole prefers, and see the consequences of people's stylistic choices. Once the feature has been in use for a while, we'll settle on some specific stylistic recommendations. _Just don't ever write `new Foo.new()`, please!_

**Q:** Why introduce this everywhere when it's only supposed to be used for tear-offs. Couldn't it just work for tear-offs?

**A:** For consistency *and* because it's expected to be useful for other things too, like generic constructors where we'll also need a way to add type arguments to both the class and the constructor. We'd rather introduce a full feature once than a partial feature now and then having to add another part to it later.

**Q:** Can I declare both `C` and `C.new` in the same class?

**A:** No. The *name* of the constructor is still `C`, the `C.new` is just another syntax for declaring a constructor named `C`, and you still can't declare two constructors with the same name.

**Q:** Will `dart:mirrors` be able to see the `.new` on a constructor declaration?

**A:** Most likely not. There are no plans to change the `dart:mirrors` library, and it's just different syntax for the same declaration. The constructor name is still going to be just the class name, and that's what `dart:mirrors` expose.

## Function value instantiation

Until now you could only instantiate *tear-offs* of function declarations or instance methods. You could write:

```dart
T id<T>(T value) => value;
int Function(int) intId = id; // implicitly instantiated with <int>.
```

but you couldn't instantiate function *values* with a type argument:

```dart
T Function<T>(T) id = <T>(T value) => value;
int Function(int) intId = id; // INVALID
```

There were reasons for this, mainly worries about implementations not being able to be efficient. The implementors have told us that it's not a problem, so we now remove that restriction and allow you to instantiate any function-typed expression. The `INVALID` above becomes valid and well-typed.

_This is not actually part of the constructor tear-off feature, it's considered a bug-fix because some (but not all) compilers already supported the feature, and it will be available in older language versions too. See language issue [#1812](https://github.com/dart-lang/language/pull/1812) for details. This feature-fix will still very likely ship at the same time as constructor tear-offs, and it's affecting the explicit instantiation feature, so we include it here._

This also applies to *callable objects* (objects that have an interface type with a `call` method), which we treat like function values in most places.

**Q:** Where does that even matter?

**A:** If you have a generic function *value*, it's usually something you've received as a parameter at some point (if you knew which value it was, you'd just refer directly to a function declaration). It's probably going to be fairly rare to then need to instantiate that function to a specific type, instead of keeping it generic until it's called. It can happen. It makes explicit instantiation easier to explain too!

Hypothetical example:

```dart
// Not a clue, mate. You tell me.
```

**Q:** Couldn't I just instantiate the `call` method using method instantiation anyway?

**A:** Yes and no. You could for callable objects, and we'd even add the `.call` implicitly for you (we do that for any callable object in a function-typed context, before checking whether the types actually work). It just didn't work for *real* function values. Dart2js never implemented instantiated tear-off of the `call` method of function values because that would be equivalent to instantiating the function value itself, which wasn't a supported feature (until now), so your code would just crash. We recognized this and initially planned to disallow doing a instantiated tear-off of a function's `call` method. Instead it turned out we can just support it consistently.

**Q:** Are function value instantiations canonicalized? Or equal?

**A:** Since function value instantiations are never constants, they won't be canonicalized. They may be equal if the underlying instantiated functions are equal and the type arguments are the same, but they are not required to. In general, do not rely on equality of instantiated function values.

## Explicit instantiation

So far, you've been able to *implicitly* instantiate tear-offs. You can instantiate a *class* both implicitly *and explicitly* when doing a constructor tear-off as `List<int>.filled`. We extend that to all the other places where we currently only allow implicit instantiation. That closes a hole in the language where some type arguments could *only* be introduced by inference, but couldn't be explicitly written if you weren't satisfied with the inference result.

Examples:

```dart
Type intListType = List<int>; // Explicit type literal instantiation.

T id<T>(T value) => value; // Our standard generic function example.
var idValue = id; // A function *value*.

var intId = id<int>; // Explicit instantiation, saves on writing the function type.
var intId2 = idValue<int>; // Still works!
var intId3 = (id)<int>; // Still works!

var makeList = (List.filled)<String>; // List<String> Function(int, String)
```

The last example shows the generality of the feature, because the `(List.filled)` tear-off is a generic function value, you can instantiate it. *Don't even write that*, always use `List<String>.filled` instead!

In short, we allow you to use `<typeArguments>` as a *selector*, like `.name` and `[expr]`, which you can chain after an expression. Previously we only allowed type arguments to occur before an argument list (`<typeArguments>(arguments)`) or after a class name in a constructor invocation (`ClassName<typeArguments>.name(arguments)`). Now we allow it after any expression, and with the same precedence as other selectors like argument lists, `.name` and `[expr]`.

Whenever such a type argument list is followed by an argument list, it exactly means the same as it used to. No change there.

**Q:** Doesn't that make the grammar, like, totally ambiguous?

**A:** Yes! *Thank you* for noticing! And that is a problem. With Dart 2.0 we introduced generic function invocations, and had to decide how to parse `f(a<b,c>(d))`. The argument(s) to `f` could be either two comparison operator expressions or a single generic function invocation. We decided on always choosing the latter when `b` and `c` can be parsed as types and the `>` is followed by a `(`. (We have to decide while we parse the program, long before we can even begin to figure out what `b` and `c` actually refer to, so the choice is entirely grammar based.) We now have even more similar ambiguous cases. For example `f(a<b,c>-d)` is ambiguous because `-` can both be a prefix operator after a greater-than operator, or an infix operator after an explicit type-instantiation. Our choice is to be very restrictive in when we parse `expr <` as starting a type argument. We only do so when the following tokens *can* be parsed as a type argument list, and the only if the *next token* after the final `>` of the type arguments is one of:

> `)`, `}`, `]`, `;`, `:`, `,`,`(`, `.`, `==`, or `!=`

If the next token is *any other token*, then the `<` is parsed as a less-than operator.

In practice, we believe the parser will just do the right thing without any effort on your part. In the unlikely event that it doesn't, you can force the interpretation you want by adding parentheses:

```dart
f((a < b), c > -d)
// or
f((a<b, c>) - d)
```

**Q:** Can I call a static method from `List` on `List<int>`.

**A:** No. You can write `List.copyRange` but not `List<int>.copyRange`. This is a grammar based restriction. Even if you have a type alias like `typedef Stupid<X> = int;`, where `Stupid<void>` just means `int`, you can't do `Stupid<void>.parseInt`. The only thing you can access through an instantiated type literal is constructors. (So `Stupid<void>.fromEnvironment` is valid, just please don't do it.)

**Q:** What if I want to call an extension method defined on `Type` on a `List<int>`?

**A:** Then you need parentheses, just like now. Writing `List<int>.filled` *only works for constructors*. If you write `.something` after an explicitly instantiated type literal, it tries to do a constructor lookup. If you write `.something` after a raw type literal, it tries to do a static member or constructor lookup (that's what you can do now). If you want to call instance or extension members on `Type`, whether an extension or just `.toString()`, you need to write `(List<int>).toString()`.

**Q:** If I can instantiate a generic function, and `List.filled` is a generic function tear-off, why is `List.filled<int>` invalid?

**A:** Because we say so. We could make it mean `(List.filled)<int>`, but we prefer to reserve the syntax for if/when we add proper generic constructors. And you *can* write the parentheses, just please don't. Prefer `List<int>.filled` if that's what you mean&mdash;and if it's not what you mean, you probably can't yet do what you mean.

**Q:** So where can I write an explicit type argument instantiation.

**A:** In short, after any expression which can actually use type arguments. The meaning depends on what generic thing is being instantiated.

- If the expression denotes a generic class, mixin, or type alias, it just supplies type parameters to the type, e.g., `Type t = List<int>;` If the type is then followed by a constructor name, then it's a constructor tear-off, e.g., `var f = List<int>.filled;`. Otherwise it's a `Type` literal.
- If the expression is a generic function, it instantiates it, e.g., `var f = [1.0].map<int>;`.
- If the expression is a callable object with a generic `call` method, it instantiates the `call` method, e.g., if `foo.call` is a generic method, then `var f = foo<int>;` is equivalent to `var f = foo.call<int>;`.

In all other cases, it's an error. You can only instantiate something which is generic.

**Q:** Can I do an explicit instantiation on a `dynamic` value?

**A:** No. We do allow you to *invoke* a `dynamic` value *v* as <code>*v*\<typeArgs>(args)</code>, but we do *not* allow <code>*v*\<typeArgs></code> as a dynamic instantiation. It's not one of the cases above because they all require or imply having a non-`dynamic` static type. (Same for expressions with static type `Function` or `Never`). In short, we need to know the static type of the type arguments before we will try to instantiate them.

**Q:** If `<typeArgs>` is a selector, can't I write `foo<int><int>`?

**A:** Nice try, but no. Since the token after the first `<int>` is `<`, and not one of the tokens listed above, the first `<` is parsed as a less-than operator, and then parsing will fail glamorously when it reaches the `>`. You could of course try doing `(foo<int>)<int>` but there's no way that would work in practice, because the result of `foo<int>` would no longer be generic.

**Q:** If `<typeArgs>` is a selector, can I use it in cascades?

**A:** Yes. It's unlikely to be *useful*, but it is *allowed*. You can instantiate an instance member and the result is a non-generic function. The only selector which can follow that instantiation, other than an argument list which would make it an invocation, not an instantiation, is `.someName`. Any other selector would make the `<` parse as a less than operator and break the cascade. You *can* do `.someName` on that function value &hellip; it's just that there aren't really any useful members on a function value except `call`, but then you can, and should, just call the method directly.

Example:

```dart
object..someFuture.then<int>.call((_) => 42); // Don't do this!
object..someFuture.then<int>.doWith((f) => f((_) => 42));
```

(The latter just requires an extension method to be valid, and it's still not particularly useful.)

**Q:** Are explicitly instantiated functions and types canonicalized? Are they equal?

**A:** Explicitly instantiated tear-offs work exactly like implicitly instantiated tear-offs, they just don't need to infer the types from the context first. For instantiated type literals, they will be constant and canonicalized if the type arguments are constant (contains no type variables), and otherwise equal if the same type is instantiated with "the same" type arguments.

## Versions

1.0: Initial version
