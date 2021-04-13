# Dart Constructor Tear-offs

Author: lrn@google.com<br>Version: 2.1

Dart allows you to tear off (aka. closurize) methods instead of just calling them. It does not allow you to tear off *constructors*, even though they are just as callable as methods (and for factory methods, the distinction is mainly philosophical).

It's an annoying shortcoming. We want to allow constructors to be torn off, and users have requested it repeatedly ([#216](https://github.com/dart-lang/language/issues/216), [#1429](https://github.com/dart-lang/language/issues/1429)).

This is a proposal for constructor tear-offs which introduces minimal new syntax, but enables all constructors to be torn off, and with some discussion on possible extensions to the syntax.

## Proposal

### Named constructor tear-off

We allow tearing off named constructors.

An expression *e* of the form <code>*C*.*name*</code> where *C* is an identifier or qualified identifier denoting a class, and *name* is the base name of a named constructor of the class *C*, is currently allowed by the grammar, but rejected by the static semantics. It can occur as part of a constructor invocation, but cannot be an expression by itself because it has no value. We introduce a static and dynamic expression semantic for such a *named constructor tear-off expression*.

A named constructor tear-off expression of the form <code>*C*.*name*</code> evaluates to a function value which could be created by tearing off a *corresponding constructor function*, which would be a static function defined on the class denoted by *C*

> static *C* *name*$tearoff(*params*) => *C*.*name*(*args*);

where *params* is a parameter list equivalent to the one for <code>*C*.*name*</code> (same optional/required parameters with the same names, types and default values, but where any initializing formals are replaced by normal parameters of the same type), and *args* is an argument list passing those parameters to `C.name` directly as they are received. For example, `Uri.http` evaluates to an expression which could have been created by a corresponding function literal expression:

```dart
static Uri http$tearoff(String authority, String unencodedPath, [Map<String, dynamic>? queryParameters]) => 
    Uri.http(authority, unencodedPath, queryParameters);
```

If the class denoted by *C* is generic, the corresponding constructor function is a generic function with the same type arguments (names and bounds) as the class. For example, the corresponding constructor function for `List.filled` would be:

```dart
static List<E> filled$tearoff<E>(int count, E fill) => List<E>.filled(count, fill);
```

When tearing off the constructor of a generic class, *the function tear-off is always instantiated* so the resulting function is not generic. This works the same way as instantiated tear-off of any other function, except that it is not an option to *not* instantiate when tearing off. If type inference has no constraints on the type arguments, they will be filled in by instantiate to bounds.

The static type of the named constructor tear-off expression is the same as the static type of the corresponding (instantiated) constructor function tear-off.

Also, similarly to function tear-offs, constructor tear-offs are potentially constant and canonicalized. Whenever the corresponding constructor function tear-off would be constant and canonicalized, the constructor tear-off itself is also constant and canonicalized.

### Unnamed constructor tear-off

If *C* denotes a class, an expression of *C* by itself already has a meaning, it evaluates to a `Type` object representing the class, so it cannot also denote the unnamed constructor.

Because of that, we introduce a *new* syntax that can be used to denote the unnamed constructor: <code>*C*.new</code>. It can be used (almost) everywhere the unnamed constructor can currently be referred to *and* it can be used to tear off the unnamed constructor.

```dart
class C {
  final int x;
  const C.new(this.x); // declaration
}
class D extend C {
  D(int x) : super.new(x * 2); // super constructor reference
}
void main() {
  D.new(1); // normal invocation
  const C.new(1); // const invocation
  var f = C.new; // tear-off
  f(1);
}
```

Apart from the tear-off, this code will mean exactly the same thing as the same code without the `.new`. The tear-off cannot be performed without the `.new` because that expression already means something else. 

The one thing we do *not* allow is `new C.new(1)`, in an explicit constructor invocation. That'd be too much of a good thing, and we are discouraging that use of `new`. We allow `const C.new(1)` because it means something else.

*With regard to tear-offs, <code>C.new</code> works exactly as if it had been a named constructor, with a corresponding constructor function named <code>C.new$tearoff</code>.*

We probably want to support `[C.new]` as a constructor link in DartDoc as well. In `dart:mirrors`, the name of the constructor is still just `C`, not `C.new` (that's not a valid symbol, and we don't want to break existing reflection using code).

### Consequences

This proposal is deliberately non-breaking and backwards compatible.

It introduces new syntax for "unnamed" constructors, they are now `new`-named constructors, you can just omit the `new` in most cases, except tear-offs. This avoids conflicting with type literals when trying to tear off an unnamed constructor.

We technically only need the `C.new` for tear-offs, and don't need to allow it in other places, but it would be (more) inconsistent to only allow the syntax in one place. Also, the same syntax may be useful for declaring and calling generic unnamed constructors in the future.

There is no easy way to abstract over the type parameters of the class. We could make `Set<T> Function<T>() makeSet = HashSet;` tear off as `<T>() => HashSet<T>()`, providing a generic function matching the generic class. *However*, we also want to introduce *generic constructors*, say `Map.fromIterable<T>(Iterable<T> elements, K key(T element), V value(T element))`, and tearing off that should create a generic function. Making generic tear-offs work with the *class* type parameters could interfere with this later feature. Not doing so is still a choice with consequence, we can't just allow it later if we change our minds. If `var makeFilled = List.filled;` is not generic now, it would be a breaking change to make it generic later. Adding `.new` syntax gives us a way to declare and invoke generic "unnamed" constructors, so it won't need to be `B<int><int>(…)`.

Constructors with very large argument lists will create very large function closures. Example:

```dart
class C {
  final int? a, b, c, d, e, f, g, h, i, j, k, l, m;
  C({this.a, this.b, this.c, this.d, this.e, this.f, this.g, this.h, this.i, this.j, this.k, this.l, this.m});
}
...
 void Function() f = C.new; 
 // equivalent to:
 //    = (int? a, int? b, int? c, int? d, int? e, int? f, int? g, int? h, int? i, int? j, int? k, int? l, int? m) =>
 //      C(a: a, b: b, c: c, d: d, e: e, f: f, g: g, h: h, j: j, l: l, m: m);
```

In this case, most of the parameters are *unnecessary*, and a tear-off expression of `() => C()` would likely be sufficient. However, that would prevent canonicalization, and would be inconsistent with what we do for function-tear-off. If the implementation is just a tear-off of an implicitly defined

```dart
static C new$tearOff(int? a, int? b, int? c, int? d, int? e, int? f, int? g, int? h, int? i, int? j, int? k, int? l, int? m) =>
    C(a: a, b: b, c: c, d: d, e: e, f: f, g: g, h: h, j: j, l: l, m: m);
```

which can be tree-shaken if the constructor is never torn off, then the overhead should be fixed.

## Possible Extensions

### Explicitly instantiated generics

We can only instantiate generic classes based on type inference. That means that `var makeIntList = List.filled;` won't work (it will have type `List<Object?> Function(int, Object?)`, you have to write out the entire type as  `List<int> Function(int args, int value) = List.filled;`.

If we instead allow you to write `var makeIntList = List<int>.filled;`, then you would not need the context type.

This would be further new syntax. It's not currently allowed by the grammar. It's fairly uncontroversial, but it blurs the lines between constructor invocations and selector chains, and we might need to rewrite the specification around those.

That is, we would allow the following expressions as well:

* `C<typeArgs>.new`
* `C<typeArgs>.name`

and in the semantics above, the type arguments to the corresponding constructor function uses the specified type arguments instead of inferring them.

## Versions

* 2.0: Initial version in this iteration. Proposed `new C` as unnamed tear-off syntax.
* 2.1: Revision. Proposed `C.new` as unnamed tear-off syntax.
