# No Inferred Dynamic

Author: Paul Berry

Status: Draft

Version 1.4 (see [Changelog](#changelog) at end)

Experiment flag: no-inferred-dynamic

This feature removes the places where Dart's type inference produces the type
`dynamic` without being asked to. After this change:

*   When inference has to fill in a type argument and has no information to go
    on, it uses `Object?` instead of `dynamic`.
*   When a declaration has no type annotation and inference has no way to
    determine its type, it gets a default type instead of `dynamic`: `Object?`
    for a variable or parameter, and `void` for most return types.
*   The exception is a local variable declaration with no type annotation and
    no initializer, which is a compile-time error.

A developer who actually wants dynamic dispatch says so by writing `dynamic`.

## Motivation

### Two meanings of `dynamic`

In Dart today, `dynamic` means two very different things that share one
spelling:

1.  *"I, the author, want dynamic dispatch here."* This is deliberate, local,
    and visible in the source.
2.  *"The compiler couldn't work out a type."* This is accidental, often
    distant from the place where it causes harm, and invisible in the source.

The second meaning is the problem. It turns a failure of type inference into a
silent removal of static checking, at a place the reader has no reason to look
at.

This proposal removes the second meaning. Its core rule is:

> **Type inference never introduces `dynamic`. It only propagates a `dynamic`
> that some declaration has, whether written explicitly or produced by the rules
> of an older language version.**

Propagation is still fine. If `d` has type `dynamic`, then `d.foo` and `d[0]`
have type `dynamic`, and so does a local variable initialized from them. That
`dynamic` follows from the declaration of `d`, by way of the rules for dynamic
invocations. What changes is that inference no longer *invents* `dynamic` where
nothing in the program says so.

### Example: raw types silently defeat the type system

This program is accepted today:

```dart
class Box<T> {
  final T value;
  Box(this.value);
}

void printLength(Box box) {
  print(box.value.length); // (1)
}

void main() {
  printLength(Box('hello'));  // prints 5
  printLength(Box(42));       // throws NoSuchMethodError at runtime
}
```

`Box box` is a raw type, which instantiate to bound turns into `Box<dynamic>`,
so `box.value` (at (1)) has type `dynamic` and `box.value.length` isn't checked
at compile time. Nothing in the source says so.

Under this proposal, `Box` means `Box<Object?>`, and `box.value.length` is a
compile-time error. An author who really wants dynamic dispatch writes
`Box<dynamic>`; an author who wants static checking writes `Box<String>`.

### Example: a `dynamic` with nothing to blame

```dart
var x = null;   // x has type dynamic
x.anything;     // accepted
```

Nothing is missing from this declaration: it has an initializer. Inference's
obvious answer, `Null`, isn't a useful type for a variable, so it substitutes
`dynamic`, which turns off static checking. This proposal substitutes `Object?`
instead, which doesn't.

### Example: the implementations disagree

```dart
T callAndReturnFirst<T>(Iterable<T> Function() callback) => callback().first;

test(bool b, List<int> x, Set<String> y) {
  var r = callAndReturnFirst(() => b ? x : y);
  r.anything;   // analyzer: compile-time error.  CFE: accepted.
}
```

To infer `T`, Dart needs the type of the callback's body, `b ? x : y`. Its two
branches, `List<int>` and `Set<String>`, have no common supertype more specific
than `Object`. When that happens, Dart falls back to the type the context
expects for the body, which is `Iterable<T>`. But `T` is the very thing being
inferred, so at this point it's still unknown, and Dart has to fill the hole
with a top type. The specification and the analyzer fill it with `Object?`, so
`T` is `Object?` and `r.anything` is a compile-time error. The CFE, which
compiles the program for execution, fills it with `dynamic`, so `T` is
`dynamic` and the same line compiles and then throws at runtime.

A closely related case involving function literal return types is tracked as
[language#4466][]. There, neither implementation matches the specification:
both accept a program that the specification says should be rejected.

[language#4466]: https://github.com/dart-lang/language/issues/4466

So for some programs, whether `dynamic` is invented depends on which tool is
looking. This proposal settles all of these cases on `Object?`, as the type
inference specification already says for greatest closures.

### Precedent

Dart has already moved away from inventing `dynamic` several times. Most
recently, the [primary constructors][] feature gives a declaring parameter with
no type annotation and no default value the type `Object?`, and does the same
when the default value is `null`, explaining: *"Dart has traditionally assumed
the type `dynamic` in such situations. We have chosen the more strictly checked
type `Object?` instead, in order to avoid introducing run-time type checking
implicitly."* (This proposal extends that feature's rules to all parameters;
see [Parameters](#parameters).)

[primary constructors]: ../../accepted/3.13/primary-constructors/feature-specification.md

Before that, null safety removed several places where Dart invented `dynamic`:

| Case | Before null safety | With null safety |
|---|---|---|
| `catch (e)` | `dynamic` | `Object` |
| Parameter of `operator ==` | `dynamic` | `Object` |
| Bound of a type parameter with no declared bound | `dynamic` | `Object?` |
| Function literal parameter whose context type is a subtype of `Null` | `dynamic` | `Object?` |
| Recursive call to a local function with no declared return type | `dynamic` | inference failure (as specified; see [Recursive local functions](#recursive-local-functions)) |

The third and fourth rows are exactly the change this proposal makes
elsewhere. The fifth shows that the specification already treats a recursive
call as an inference failure rather than as a source of `dynamic`; this
proposal gives such a function a default return type instead. *(The change to
type parameter bounds didn't reach instantiate to bound, which still uses
`dynamic` for an omitted bound; see
[Instantiate to bound](#instantiate-to-bound).)*

## Overview

*This section is informal. The normative rules are in
[Static semantics](#static-semantics).*

The changes follow three rules:

*   **A type argument that inference would have to invent becomes `Object?`.**
    This covers raw types (`List` means `List<Object?>`), unconstrained type
    variables in generic inference (`var l = [];` gives `List<Object?>`), and
    greatest closures.
*   **A local variable declaration with no type and no initializer is a
    compile-time error.**
*   **Any other declaration whose type can't be determined gets a default
    type.**
    A parameter with no type and nothing to infer one from, or a top-level
    variable or field with no type and no initializer, gets type `Object?`. An
    omitted return type is `void` (or `Object?`, for a getter or an operator
    other than `[]=`), regardless of the body. This applies to top-level
    functions, methods, function types, and recursive local functions, but not
    to function literals and non-recursive local functions, whose return types
    are still inferred from their bodies.

Why these defaults? A parameter always has a value when its function runs. If
the body doesn't use it, its type doesn't matter, and `Object?` accepts any
argument. If the body does use it in a way that needs a more specific type,
the resulting errors lead the author to write one. Similarly, `void` is what
an author who omits a return type usually means, and since the default doesn't
depend on the body, a function's signature can still be understood without
reading its body. A getter or an operator exists to produce a value, though, so
`void` would make every use of it an error; in this circumstance, `Object?` is
used instead.

Why is a local variable declaration with no type and no initializer different?
Mainly because reporting the error at the declaration puts it where the fix
goes; see [Variables](#variables) for the full rationale and supporting data.

Some notes:

*   A variable whose initializer has type `Null` (as in `var x = null;`) gets
    type `Object?`. *Giving such a variable type `Null` would be practically
    useless.*
*   A generator function literal or local function with no `yield` gets element
    type `Never`, since it produces no elements.

| Construct | Today | With this feature |
|---|---|---|
| `List x;` (raw type) | `List<dynamic>` | `List<Object?>` |
| `class D<T extends Comparable<T>> {}` then `D d;` | `D<Comparable<dynamic>>` | `D<Comparable<Object?>>` |
| `var l = [];` | `List<dynamic>` | `List<Object?>` |
| `var m = {};` | `Map<dynamic, dynamic>` | `Map<Object?, Object?>` |
| `var x;` (local variable) | `dynamic` | error |
| `var x;` (top-level variable or field) | `dynamic` | `Object?` |
| `var x = null;` | `dynamic` | `Object?` |
| `void f(x) {}` | `x` is `dynamic` | `x` is `Object?` |
| `void f(_) {}` | `_` is `dynamic` | `_` is `Object?` |
| `void f([x = 0]) {}` | `x` is `dynamic` | `x` is `int` |
| `class C(var x);` (primary constructor) | `x` is `Object?` | `x` is `Object?` |
| `class C(x);` (primary constructor) | `x` is `dynamic` | `x` is `Object?` |
| `class C([var x = 0]);` (primary constructor) | `x` is `int` | `x` is `int` |
| `var g = (x) => x;` | `x` is `dynamic` | `x` is `Object?` |
| `f() {}` (top-level) | returns `dynamic` | returns `void` |
| `f() => 0;` (top-level) | returns `dynamic` | returns `void` |
| `f() { return 0; }` (top-level) | returns `dynamic` | error (returns `void`) |
| `get g => 0;` (top-level) | `dynamic` | `Object?` |
| `Function(int)` | `dynamic Function(int)` | `void Function(int)` |
| `fib(int n) => ... fib(n - 1) ...;` (local) | returns `dynamic` | error (returns `void`) |
| `var f = () sync* {};` | `Iterable<dynamic>` (analyzer) or `Iterable<Null>` (CFE) | `Iterable<Never>` |
| `Object f() sync* { ... }` | element type `dynamic` | element type `Object?` |

## Static semantics

The rules in this section apply to code in libraries where the feature is
enabled. See [Language versioning](#language-versioning) for how libraries with
and without the feature interact.

### Instantiate to bound

The instantiation to bound algorithm (in the language specification's section
"The Instantiation to Bound Algorithm") changes in two places:

*   When the bound of the *i*th type parameter is omitted, *S<sub>i</sub>* is
    `Object?` instead of `dynamic`. The same change applies to instantiation to
    bound of generic functions.
*   In the cycle-breaking step, occurrences of a type variable in a position
    that isn't contravariant are replaced by `Object?` instead of `dynamic`.
    Occurrences in contravariant positions are still replaced by `Never`, as
    specified by null safety. *This step applies even when every bound is
    written explicitly.*

*For example:*

```dart
class C<T> {}
class D<T extends Comparable<T>> {}
class E<T extends void Function(T)> {}

C c;  // C<Object?>             (was C<dynamic>)
D d;  // D<Comparable<Object?>> (was D<Comparable<dynamic>>)
E e;  // E<void Function(Never)> (unchanged)
```

*The type `D<Comparable<Object?>>` doesn't satisfy `D`'s declared bound, but
neither does today's `D<Comparable<dynamic>>`. Both are well-bounded because
they're super-bounded: the super-bounded check replaces covariant occurrences of
top types by `Never` before checking the bound, and `dynamic` and `Object?` are
both top types, so both types are checked as `D<Comparable<Never>>`. So every
type produced by cycle breaking that is well-bounded today remains well-bounded.
The two forms are also mutual subtypes, so they're assignable to each other and
compatible as override signatures.*

*A bound that is written as `Object` or `Object?` is unaffected:
`class F<T extends Object> {}` already instantiates to `F<Object>`, and
`class G<T extends Object?> {}` already instantiates to `G<Object?>`.*

### Type inference

#### Unconstrained type variables

When generic inference finishes with a type variable that has no constraints,
the variable is given the result of instantiate to bound, as today. Because of
the change above, that is now `Object?` rather than `dynamic` when the bound is
omitted.

*This covers type arguments of generic function invocations, generic
constructor invocations, and collection literals. In particular, an empty
collection literal with no useful context gets `Object?` type arguments:*

```dart
var l = [];  // List<Object?>
var s = {};  // Map<Object?, Object?>
```

*An empty `{}` with no context is disambiguated as a map literal (language
specification, "Set and Map Literal Disambiguation"), and its type arguments are
then inferred like those of any other map literal.*

*Other places that fill in missing type arguments using instantiate to bound
change in the same way, with no further rules needed:*

*   *Mixin applications: in `mixin M<T> {}` and `class C with M {}`, `M` means
    `M<Object?>` (was `M<dynamic>`), including for type parameters that mixin
    inference leaves unconstrained.*
*   *Object patterns: given `class Foo<T> { final T x; ... }`, in
    `case Foo(:var x):` where the matched value's type doesn't constrain
    `Foo`'s type argument, `Foo` means `Foo<Object?>` (was `Foo<dynamic>`). So
    the variable `x`, which takes the type of the getter `Foo<Object?>.x`, has
    type `Object?` (was `dynamic`).*
*   *Implicit instantiation of a generic function tear-off whose type arguments
    aren't constrained by the context.*

#### Greatest closure

The greatest closure of a type schema uses `Object?` as its top type, as already
specified. Implementations must use it everywhere a greatest closure is
computed, including:

*   computing the context for the returned expressions of a function literal
    from its imposed return type schema, and
*   the rule for conditional expressions, `??`, and `??=` that uses the greatest
    closure of the context type as the type of the expression when the static
    types of both operands are subtypes of it but their least upper bound is
    not.

*Today, the CFE uses `dynamic` in these places. This part of the feature is a
conformance fix: no specification text changes.*

#### Variables initialized with a `Null`-typed expression

When the type of a variable declared without a type annotation is inferred from
its initializing expression, and the inferred type of that expression is
`Null`, the variable's type is `Object?` instead of `dynamic`.

```dart
var x = null;  // Object?
```

*This applies to local variables, top-level variables, and static and instance
fields. An instance variable whose type is provided by override inference gets
that type instead, as it does today; override inference takes precedence over
the initializer. It matches the rule the primary constructors feature uses for a
declaring parameter whose default value is `null`. An initializer of type
`Never` (such as `throw 'x'`) gives the variable type `Never`, as it does
today. (The type inference specification says that `dynamic` is used whenever
the initializer's type is a subtype of `Null`, which would include `Never`, but
the implementations only do this for `Null`; see
[Specification cleanups](#specification-cleanups).)*

*For a local variable, this rule deliberately differs from the rule for a
variable with no initializer, which is an error (see [Variables](#variables),
and see also [Open questions](#open-questions)).*

#### Generator element types

*   If a function literal or local function is a generator, its return type is
    inferred from its body, and if its body contains no `yield` or `yield*`
    statements, then its inferred element type is `Never`, whether or not the
    end of the body is reachable. So its inferred return type is
    `Iterable<Never>` for `sync*` and `Stream<Never>` for `async*` (unless the
    context type wins, as it does today). *(In the terms of the type inference
    specification, the generator's "actual returned type" is `Never`.)*

    ```dart
    var f = () sync* {};   // Iterable<Never> Function()
    var g = () async* {};  // Stream<Never> Function()
    ```

    *A separate breaking change request, [sdk#63795][] (with specification
    change [language#4724][]), proposes the same change without language
    versioning. If that change is approved and implemented first, this rule
    and the corresponding items in [Compatibility](#compatibility),
    [Migration](#migration), [Tooling](#tooling), and
    [Specification cleanups](#specification-cleanups) won't be needed.
    Otherwise, this feature makes the change, with language versioning.*

*   When inferring the return type of a generator function literal or local
    function, a `yield* e;` statement where the static type of `e` is `Never`
    contributes `Never` to the element type. *(A `yield* e;` where `e` has type
    `dynamic` contributes `dynamic`, which is propagation and is unchanged.)*

    ```dart
    var h = () sync* { yield* (throw 'x'); };  // Iterable<Never> Function()
    ```

*   In the definition of the element type of a generator function (language
    specification, section "Functions"), when the union-free type derived from
    the declared return type is a supertype of `Object`, the element type is
    `Object?` instead of `dynamic`.

    ```dart
    Object f() sync* {
      yield 1;
    }

    void main() {
      print(f().runtimeType);
      // Today: _SyncStarIterable<dynamic>
      // With this feature: _SyncStarIterable<Object?>
      // (The exact class name varies by platform.)
      print(f() is Iterable<Object?>); // true either way
    }
    ```

*This change can't be observed at compile time, since every value can be
yielded with either element type and callers only see the declared return type.
It's only visible through `Type` objects, as above (see also
[Runtime semantics](#runtime-semantics)).*

### Declarations without a type

#### Variables

It's a compile-time error if a local variable declaration declares a variable
without a type annotation and without an initializing expression.

A top-level, static, or instance variable declaration that declares a variable
without a type annotation and without an initializing expression gives the
variable the type `Object?`, unless its type is provided by override
inference.

*A type annotation isn't the only way for a variable to get a declared type: an
instance variable can inherit its type from its superinterfaces through
override inference, as `Sub.i` does below.*

*These rules apply whether the variable is declared with `var`, `final`, or
`late` (or, for a non-local variable, `abstract` or `external`). (A variable
declared with no keyword at all must have a type annotation, and a `const`
variable must have an initializer, so neither can be affected.) They apply to
each variable separately: in `var x = 1, y;` (as a local variable
declaration), `y` has no initializing expression, so it's an error.*

```dart
void f() {
  var a;          // Error.
  final b;        // Error.
  late var c;     // Error.
  var d = 1, e;   // Error (for `e`).
}

var t;            // OK: type Object?.

class C {
  static var s;   // OK: type Object?.
  final f;        // OK: type Object?.
  C(this.f);
}

abstract class A {
  abstract var j; // OK: type Object?.
}

abstract class Base {
  int get i;
}

class Sub extends Base {
  var i;          // OK: type int, from override inference.
  Sub(this.i);
}
```

*Variables that get their types from an enclosing construct aren't variable
declarations in this sense, and are unaffected: a `for`-`in` loop variable is
initialized from the elements of the iterable; a `catch` clause's exception
variable gets the type in its `on` clause (or `Object`, if there's no `on`
clause), and its stack trace variable gets type `StackTrace`; and a pattern
variable gets its type from the matched value. (A pattern variable declaration
such as `var (x, y) = (1, 0);` always has an initializer.)*

*The rationale for making an untyped local variable declaration with no
initializer an error is that reporting the error at the declaration puts the
error where the fix goes. Data from open-source code suggests that giving such
a variable type `Object?` instead would usually just move the error to its
usage sites (for example, as an error about a member that doesn't exist on
`Object?`), far from the declaration. Among 275 such local variables,
collected from popular pub packages and open-source Flutter apps, 56 (20%)
would have compiled without errors with type `Object?`, and 7 more were unused
or in code that isn't meant to compile. Each of the remaining 212 (77%) would
have caused errors elsewhere, and in each case, the appropriate fix was to add
a type at the declaration: a specific type in 190 cases, `dynamic` in 20, and
a nullable type or `num` in 2.*

*Kotlin, Swift, and C# also reject a local variable declaration with no type
and no initializer, although they accept one with a type and no initializer
(checking that the variable is assigned before it's read).*

*Top-level variables and fields get `Object?` instead, as parameters do.
Whether they should be errors too is an open question (see
[Open questions](#open-questions)).*

#### Parameters

A formal parameter with no type annotation gets its type from the first of the
following that applies:

1.  Override inference.
2.  For an initializing formal (`this.x`) or a super parameter (`super.x`), the
    corresponding field or super constructor parameter.
3.  For a parameter of a function literal whose context type is a function type
    with a corresponding parameter, that corresponding parameter.
4.  **New:** if the parameter is optional and has a default value, the default
    value. Its type is the static type of the default value expression,
    inferred in the empty context, or `Object?` if that type is `Null`.
5.  **New:** otherwise, `Object?`.

*Items 4 and 5 are the rules the primary constructors feature already uses for
declaring parameters, extended to all parameters.*

*This applies to parameters of functions, methods, constructors, setters,
operators, and function literals, and to the parameters inside old-style
function-typed parameters and typedefs. For an old-style function-typed
parameter itself, such as `void f(callback())` or `void f(_())`, the optional
type written before the name is its return type, so a missing one is covered
by [Return types](#return-types) rather than by this rule.*

*Some consequences:*

*   *An untyped optional parameter with a default value gets its type from the
    default value, and one with no default value (and no type from anywhere
    else) gets type `Object?`. Declaring parameters of primary constructors are
    unchanged. A non-declaring parameter of a primary constructor follows the
    same rule as any other parameter.*

    ```dart
    void f([x = 0]) {}        // x is int (today: dynamic).
    void g({y = null}) {}     // y is Object? (today: dynamic).
    void h([z]) {}            // z is Object? (today: dynamic).
    class C(var x);           // x is Object?, as it is today.
    class D([var x = 0]);     // x is int, as it is today.
    class E(x);               // x is Object? (today: dynamic).
    extension type F(x);      // x is Object?, as it is today.
    ```

*   *A parameter of a function literal with no context, or whose context type
    isn't a function type (such as `Function` or `Object`), gets type `Object?`
    unless it has a default value:*

    ```dart
    var g = (x) => x;        // x is Object?, so g is Object? Function(Object?).
    var h = (int x) => x;    // x is int.
    var i = ([x = 0]) => x;  // x is int, from the default value.
    ```

*   *Likewise, an extra optional parameter of a function literal (beyond its
    context function type) gets type `Object?` unless it has a default value.*

    ```dart
    void f(void Function(int) callback) {}

    f((a, [b]) {});     // `b` is Object?: no corresponding context parameter.
    f((a, {b}) {});     // `b` is Object?: same reason.
    f((a, [b = 0]) {}); // `b` is int, from the default value.
    ```

*   *And a parameter that a method adds (beyond the parameters in the combined
    member signature of the members it overrides) gets type `Object?` unless it
    has a default value. (Today such a parameter gets type `dynamic`.)*

    ```dart
    abstract class A {
      void m(int x);
    }

    class B extends A {
      void m(x, [y]) {}      // `y` is Object?. (`x` is int.)
    }

    class C extends A {
      void m(x, [y = '']) {} // `y` is String. (`x` is int.)
    }
    ```

*   *The error handlers taken by `Future.catchError`, `Future.then`'s `onError`,
    and `Stream.listen`'s `onError` are declared with type `Function`, so their
    untyped parameters get type `Object?`. See [Compatibility](#compatibility).*

#### Return types

If any of the following has no declared return type and its return type isn't
provided by override inference, its return type is `void`:

*   a top-level function, a static method, or an instance method that isn't
    an operator,
*   an old-style function-typed formal parameter (`void f(callback())`),
*   a function type written with `Function` (`Function(int)`), or
*   an old-style typedef (`typedef F(int x);`).

*The body isn't consulted, so a function's signature never depends on its
body. A block body containing `return e;` is therefore an error (unless `e`
has type `void`, `dynamic`, or `Null`), and so is a generator, since a
generator can't have return type `void`. In both cases, the author needs to
write the return type. An `async` function gets return type `void` too, not
`Future<void>`.*

If a top-level, static, or instance getter, or an operator other than `[]=`,
has no declared return type and its return type isn't provided by override
inference, its return type is `Object?`.

*A getter or an operator exists to produce a value, so `void` would make every
use of it an error (including, for an operator such as `+`, a compound
assignment such as `a += b`). (`operator ==` gets return type `bool` from
`Object` by override inference.)*

*Setters and `operator []=` aren't affected: when their return type is omitted
it's already `void`. Function literals and non-recursive local functions aren't
affected: their return types are inferred from their bodies.*

```dart
f() {}                    // Returns void.
g() => 1;                 // Returns void.
h() { return 1; }         // Error: can't return a value from a void function.
i() async {}              // Returns void.
j() sync* {}              // Error: a generator can't return void.
get k => 1;               // k has type Object?.
void l(callback()) {}     // callback has type void Function().
typedef F(x);             // F is void Function(Object?).
typedef G = Function();   // G is void Function().

class C {
  operator [](int i) => i;   // Returns Object?.
  operator +(C other) => this; // Returns Object?.
}

void main() {
  local() => 1;           // Returns int, inferred from the body.
}
```

*`main` isn't special: `main() {}` and `main() async {}` both have return
type `void`.*

#### Recursive local functions

If a local function declaration has no declared return type and its body
refers to the function itself (by calling it or by tearing it off), its return
type is `void`.

```dart
void main() {
  // Error: `fib(n - 1)` has type void, so its value can't be used.
  fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);

  int fib2(int n) => n < 2 ? n : fib2(n - 1) + fib2(n - 2); // OK.

  visit(Node? node) {     // OK: returns void.
    if (node == null) return;
    visit(node.left);
    print(node.value);
    visit(node.right);
  }
}
```

*The type inference specification already says that, with null safety, a
recursive call whose result type is needed for inference is an inference
failure. Neither implementation does this today: both give the recursive call
type `dynamic`, and that `dynamic` becomes the function's inferred return type
whenever the call's result is returned. This rule replaces the inference with
a simple syntactic rule, and gives the same default as an omitted return type
elsewhere. A recursive local generator needs a declared return type, since a
generator can't have return type `void`. Likewise, a recursive `async` local
function gets return type `void`, not `Future<void>`, so if it awaits its own
recursive calls (as in `await visit(node.left);`), it needs a declared return
type such as `Future<void>`.*

#### Augmenting declarations

The rules in this section apply to introductory declarations. An augmenting
declaration that omits a type gets it from the declaration it augments, as
specified by the [augmentations][] feature, so it isn't affected. An
augmentation can't supply the introductory declaration's type, so an
introductory declaration whose type can't be determined gets the default type
described above even if it's augmented:

```dart
get x;                      // Type Object?: no declared type.
augment final x = 42;       // OK: x has type Object?.

f();                        // Returns void: no declared return type.
augment f() { return 42; }  // Error: f returns void.
```

*Augmentations are merged before type inference fills in the omitted types of
the introductory declaration, though (but see
[Open questions](#open-questions)). So when an augmentation supplies the
default value of an optional parameter whose introductory declaration has no
type and no default value, the parameter's type is inferred from that default
value, as described in [Parameters](#parameters):*

```dart
void f([x]);                // x has type int, from the augmentation.
augment void f([x = 0]) {}
```

[augmentations]: ../augmentations/feature-specification.md

### What doesn't change

*   **Explicit `dynamic`** keeps its meaning, and so does everything derived from
    it: member accesses, calls, and index operations on `dynamic` still have
    type `dynamic`.
*   **`for`-`in` over a `dynamic` iterable.** The language specification says
    that when the static type of the iterable is a top type, the loop treats it
    as `Iterable<dynamic>`. But it's a compile-time error unless that type is
    assignable to `Iterable<dynamic>`, so the only valid case is iterating a
    `dynamic` value. Giving the loop variable type `dynamic` then is a
    deliberate choice that follows from the iterable being `dynamic`, not an
    invented `dynamic` (the author has said "trust me", and the elements are
    trusted the same way). It's unchanged.

    ```dart
    for (var item in decoded['items']) {  // decoded is dynamic
      print(item['name']);                // item is dynamic, as today
    }
    ```

*   **Override inference failures.** When override inference can't combine the
    signatures of the overridden members, implementations give the missing types
    `dynamic` today, but always together with a compile-time error. That's error
    recovery, unchanged by this feature.
*   **Bottom types** produced by instantiate to bound in contravariant positions
    stay `Never`.
*   **Type parameter bounds for subtyping.** An omitted bound already means
    `Object?` for bounds checking and subtyping. Only instantiate to bound used
    `dynamic`, and that's what changes.

## Runtime semantics

This feature adds no new runtime behavior. But because some inferred types
change, some reified types change too:

```dart
List x = [];   // a List<Object?> at runtime (was List<dynamic>)
Object f() sync* { yield 1; }  // returns an Iterable<Object?> (was Iterable<dynamic>)
g() {}         // tears off as a void Function() (was dynamic Function())
```

Where a reified type changes only by replacing `dynamic` with another top type
(`Object?` or `void`), as in the examples above, `is` and `as` checks behave
the same either way, since the two types are mutual subtypes. The difference
can only be observed through `Type` objects, for example obtained using
`runtimeType`, and inspected using `==` or `toString()`.

Some changes make a reified type more specific, though, and those can also
change the outcome of `is` and `as` checks, and of dynamic invocations:

*   **Parameter types inferred from default values.** Given `void f([x = 0])`,
    `f` has runtime type `void Function([int])` (was
    `void Function([dynamic])`), so `f is void Function([String])` is now
    false, and a dynamic invocation `(f as dynamic)('a')` now throws.
*   **Generators with no `yield`.** Given `var f = () sync* {};`, `f()` is now
    an `Iterable<Never>` (the CFE gives `Iterable<Null>` today), so
    `f() is Iterable<int>` is now true.
*   **Function literals in a function type context with an omitted return
    type.** A function literal whose context return type is `void` gets
    inferred return type `void`. So now that `Function()` means
    `void Function()`, a function literal passed to it is inferred
    differently:

    ```dart
    void g(Function() callback) {
      print(callback is int Function());
    }

    void main() {
      g(() => 1);  // Today: prints true. With this feature: prints false.
    }
    ```

The runtime type of a torn-off method's parameters follows the method's
declaration. *Today the language specification says that a parameter with no
type annotation has runtime type `dynamic` in the torn-off function, which
doesn't account for override inference. The implementations already use the
inferred type, and the specification text should be updated (see
[Specification cleanups](#specification-cleanups)).*

## Language versioning

This feature is a breaking change, so it's language versioned. The rules above
apply to declarations and expressions in libraries whose language version has
the feature enabled. This section describes what happens when those libraries
interact with libraries that have earlier language versions.

**Each declaration has one type, determined by the language version of the
library that declares it.** Every reader sees that type, regardless of its own
language version. Likewise, the type of an expression is determined by the
rules of the library containing it.

```dart
// lib1.dart, language version without the feature
List x = [];

// lib2.dart, language version without the feature
import 'lib1.dart';
void f() {
  x[0].foo;   // OK: x is List<dynamic>.
}

// lib3.dart, language version with the feature
import 'lib1.dart';
void f() {
  x[0].foo;   // OK: x is List<dynamic>, its declared type.
}

// lib1b.dart, language version with the feature
List x = [];

// lib2b.dart, language version without the feature
import 'lib1b.dart';
void f() {
  x[0].foo;   // Error: x is List<Object?>.
}
```

*This is how earlier changes to inference have worked. For example, a library
on language version 2.17, before horizontal inference, sees the type of
`var f = [1, 2].fold(0, (a, b) => a + b);` declared in a newer library as `int`,
even though the same initializer inferred in the 2.17 library would be an
error.*

*Because the migration (see [Migration](#migration)) makes every affected type
explicit before the language version is bumped, opting a library into this
feature doesn't change any type its users see. Its users are only affected if
its author later changes a declaration's type, for example from `List<dynamic>`
to `List`, which is an ordinary API change.*

*A class on an older language version that overrides a member declared in a
library with the feature enabled gets that member's types through override
inference, as usual. For example, an untyped parameter in the override may get
type `Object?`.*

*Since each declaration has one type, which every library sees, mixing
libraries on different language versions raises no soundness questions.*

## Compatibility

Moving a library to a language version that has this feature can break code in
that library in these ways:

*   Code that relied on `dynamic` produced by instantiate to bound, by
    unconstrained inference, or by a greatest closure, now sees `Object?`, so
    member accesses and calls that were dynamically dispatched become
    compile-time errors.
*   Declarations with no type that can't be inferred change from `dynamic` to
    `Object?` (variables and parameters) or `void` (most return types), so code
    that relied on `dynamic` becomes a compile-time error. For example, the
    result of a function with no declared return type can't be used, a block
    body of such a function can't contain `return e;`, and an `async` function
    with no declared return type can't be awaited.
*   Local variable declarations with no type and no initializer become
    compile-time errors.
*   Untyped optional parameters with a default value change from `dynamic` to
    the default value's type, so code that relied on `dynamic` (for example,
    assigning a `String` to a parameter whose default is `0`) becomes a
    compile-time error.
*   Recursive local functions with no declared return type now return `void`,
    so code that uses the results of their recursive calls becomes a
    compile-time error.

Some specific cases are worth calling out:

*   **Extension members.** Extension members never apply to a receiver whose
    static type is `dynamic`, but an extension on `dynamic`, on `Object?`, or
    on a type variable (as in `extension<T> on T`) does apply to a receiver of
    type `Object?`. So when a receiver's type changes from `dynamic` to
    `Object?`, a member access that used to be dynamically dispatched may
    resolve to an extension member instead. If the object also has an instance
    member with the same name, this silently changes behavior, with no
    compile-time error:

    ```dart
    extension E on Object? {
      String foo() => 'extension';
    }

    class C {
      String foo() => 'instance';
    }

    void main() {
      List l = [C()];
      print(l[0].foo());
      // Today: 'instance' (l is List<dynamic>; dynamic dispatch)
      // With this feature: 'extension' (l is List<Object?>)
    }
    ```

    The migration (see [Migration](#migration)) preserves the old behavior,
    since it makes the `dynamic` explicit.

*   **Error handlers taking `Function`.** The parameter of `Future.catchError`,
    the `onError` parameter of `Future.then`, and the `onError` parameter of
    `Stream.listen`
    are declared with type `Function`, because a handler may take either one
    argument or two. So a handler like `future.catchError((e) { ... })` has no
    context for its parameter types, and its parameters get type `Object?`.
    That still works at runtime, since a function taking `Object?` accepts any
    error object, but the handler body becomes an error if it uses `e`
    dynamically (as in `e.message`) or uses a stack trace parameter `s` as a
    `StackTrace`. The parameters then need to be typed, as in
    `(FormatException e) { ... }` or `(Object e, StackTrace s) { ... }`. This
    pattern is common, so it's likely to be a significant source of errors
    from the parameter rule.
*   **`main`.** `main() {}` and `main() async {}` now have return type `void`.
    Code that uses the result of calling `main` breaks. In particular, test
    runners sometimes write `await other_test.main();`, which becomes an error
    if `other_test.main` is `async` with no declared return type, because the
    awaited expression has type `void`.
*   **Generators with no `yield`.** A generator function literal or local
    function with no `yield` now has element type `Never`, so code that relies
    on a different element type for its result can break. For example, given
    `var l = (() sync* {})().toList();`, `l.add(null)` compiles today (the
    analyzer infers `List<dynamic>` and the CFE `List<Null>`) but is a
    compile-time error with this feature. Such code should be rare. *(The change
    to generators declared to return a supertype of `Object` can't break code at
    compile time; see [Runtime semantics](#runtime-semantics).)*
*   **`Type` objects as map keys.** Although `dynamic` and `Object?` are mutual
    subtypes, the `Type` objects for two types that differ only in `dynamic`
    versus `Object?` aren't equal: for example, on the Dart VM, a `Type` object
    for `C<dynamic>` isn't `==` to one for `C<Object?>`. So code that uses
    `Type` objects as map keys can fail to find an entry, if the code that adds
    the entry and the code that looks it up reify different type arguments.
    This can't happen as a direct result of a migration that makes every
    `dynamic` explicit (though it can if the migration uses one of the
    shortcuts described in [Migration](#migration)). But it can happen later,
    during an incremental migration, if a raw type is written (or the
    migration's `<dynamic>` is removed) in a library that has the feature
    enabled, while a library that hasn't been migrated, or that still says
    `<dynamic>`, refers to the same type. Examples of code that is exposed to
    this include dependency injection frameworks that key providers by `Type`
    literals, and mocking libraries that keep a registry of values keyed by
    type (such as `package:mockito`'s `provideDummy`, which stores dummy value
    builders in a `Map<Type, ...>` and looks them up using a type argument).
    See also [Open questions](#open-questions).

## Migration

*This section is not normative.*

The intended migration is `dart migrate`, which enables a set of lints and
applies their quick fixes *before* the project's language version is bumped.
Each lint runs under the old language version and finds the places where
inference *will* behave differently once the feature is enabled; each fix makes
the old behavior explicit, usually by inserting `dynamic`. After that, bumping
the language version changes nothing.

Under this approach, a site where the feature reports an error costs the same
to migrate as a site where it changes a type to `Object?` or `void`: both are
fixed by writing `dynamic`.

The migration uses a new set of lints, written for this purpose, rather than
the existing diagnostics that detect similar cases (listed in the table below
for reference). Changing what the existing diagnostics report, or which fixes
they offer, would be a breaking change for the projects that already enable
them. The migration lints only report in libraries where the feature isn't
enabled; in a library where it is enabled, there's nothing left to migrate, so
they report nothing. Being new, they can also cover cases that the existing
diagnostics don't. For example, `strict-raw-types` doesn't flag a raw type
used as a type literal (`var t = List;`) or in a type test (`o is List`), but
both change meaning under this feature.

| Change | Similar existing diagnostic | Fix |
|---|---|---|
| Raw types (including in `with` clauses, type literals, and type tests) | `strict-raw-types` (except type literals and type tests) | `List` → `List<dynamic>` |
| Object patterns with an unconstrained type argument (`case Foo(:var x):`) | none | `Foo` → `Foo<dynamic>` |
| Unconstrained generic inference, empty collection literals | `inference_failure_on_function_invocation`, `inference_failure_on_generic_invocation`, `inference_failure_on_instance_creation`, `inference_failure_on_collection_literal` | add explicit type arguments |
| Variables with no type and no initializer | `inference_failure_on_uninitialized_variable` | add `dynamic` |
| Untyped parameters (other than declaring parameters with no default value, which already have type `Object?`) | `inference_failure_on_untyped_parameter` (note: the lint currently skips unused parameters) | add `dynamic` |
| Untyped optional parameters with a default value (other than declaring parameters) | `inference_failure_on_untyped_parameter` | add `dynamic` |
| Omitted return types | `inference_failure_on_function_return_type` | add `dynamic` |
| `var x = null;` | none | `dynamic x = null;` |
| Extra optional closure parameters | none | add `dynamic` |
| Recursive local functions | none for local functions | add a `dynamic` return type |
| Greatest closure (function literal returns) | none | add explicit types |
| Generators with no `yield` (function literals and local functions) | none | local functions: add a return type such as `Iterable<dynamic>`; function literals can't declare a return type, so they need an explicit context type or manual attention |

None of the existing diagnostics has a quick fix today, so all the fixes need
to be written. Fixes that would insert `Object?` (which some existing tools do
when adding a type annotation) aren't semantics-preserving where the current
type is `dynamic`; the migration must insert `dynamic` there.

Two cases don't need migration:

*   The greatest-closure change for conditional expressions, `??`, and `??=`
    only changes what the CFE does. The analyzer already uses `Object?`, so any
    affected code already shows an analyzer error.
*   The element type of a generator declared to return a supertype of `Object`
    can't be observed at compile time; only the reified type argument changes.

As indicated in the table above, one case can't always be migrated
mechanically: a generator function literal with no `yield`, such as
`() sync* {}`. A function literal can't declare a return type, so its old
element type can only be preserved by giving it an explicit context type (for
example, `Iterable<dynamic> Function() f = () sync* {};`) or by adjusting the
code that uses its result by hand. Because such generators, and code that
depends on their element type, should be rare, this is expected to be
acceptable.

Some fixes can do better than inserting `dynamic`:

*   **`main`:** a top-level function named `main` with no declared return type
    and no `return e;` statements can be left alone, whether or not it's
    `async`: its return type becomes `void`, rather than `dynamic`. *This isn't
    semantics-preserving: code that calls `main` and uses its result would
    break (see [Compatibility](#compatibility)). We expect such code to be
    rare.*
*   **Error handlers:** a fix can insert `Object e` (and `StackTrace s`) rather
    than `dynamic e` when the handler body doesn't rely on `e` being `dynamic`.
    For `Future.catchError`, a fix could instead convert the call to use the
    `Future.onError` extension method. Its handler parameter has the function
    type `FutureOr<T> Function(E, StackTrace)` rather than `Function`, so the
    handler's parameters get useful types from the context. For example,
    `future.catchError((e) { ... })` could become
    `future.onError<Object>((e, _) { ... })`. Some caveats:
    *   The handler must take two parameters, so a one-parameter handler needs
        a stack trace parameter added (as with `_` above).
    *   The handler's return type is checked against `FutureOr<T>` at compile
        time, rather than at runtime, so a handler that returns a value of the
        wrong type (including a block body that can complete without returning
        a value, when `T` isn't nullable) becomes a compile-time error.
    *   The `onError` parameters of `Future.then` and `Stream.listen` have no
        equivalent.

Inserting `dynamic` everywhere is conservative. In many places, changing a
type from `dynamic` to `Object?` would make no difference (for example, a raw
`List` whose elements are only passed along), so the raw type could be left
alone and simply take on its new meaning. A migration that inserts `dynamic`
only where it matters would have to check, for each site, whether the new
rules cause a compile-time error, resolve a member access differently (see
the extension members case in [Compatibility](#compatibility)), or change a
reified type argument. Writing and maintaining a dedicated tool to do that
would probably cost more than it's worth for this migration. However, the
author has recently started investigating how difficult it would be to add
"what if" functionality to the analyzer, allowing lints to speculatively
re-analyze statements and function bodies under changed circumstances. If
those investigations pan out, it might be possible to write a migration lint
that inserts `dynamic` only where it matters, without too high a maintenance
burden. Even then, this would only apply to declarations that aren't visible
outside their library, since changing the type of a public declaration
changes what other libraries see (see
[Language versioning](#language-versioning)).

Even without "what if" analysis, there are two ways to avoid inserting
`dynamic` in some common cases:

*   **Discarded results.** Some invocations can be recognized as safe to leave
    alone just by looking at the invocation and the declaration it invokes.
    For example, a type parameter that only appears in the return type doesn't
    matter if the return value is discarded. Similarly, a type parameter that
    only appears in the types of optional parameters doesn't matter if no
    arguments are passed for them. `Future.delayed(duration)` is a common case
    of both: `T` appears only in the return type `Future<T>` and in the
    omitted callback parameter, and the result is usually discarded (as in
    `await Future.delayed(duration);`).
*   **Classes designed to be used raw.** Some generic classes are meant to be
    used without type arguments. (The analyzer lets such a class be annotated
    with `@optionalTypeArgs`, from `package:meta`, so that `strict-raw-types`
    doesn't flag raw uses of it.) If such a class's type parameter has no
    bound, its author can change the declaration from `class C<T>` to
    `class C<T extends Object?>` before migrating. Raw uses of `C` then mean
    `C<Object?>` under the old rules as well as the new ones, so the migration
    has nothing to insert at those uses. *This is a far less invasive
    migration than inserting `<dynamic>` at every raw use, since only the
    declaration has to change. (The change takes effect immediately, in every
    library that uses `C` raw, so those uses still need to be checked, but
    they don't need to be edited.)*

Another possibility is a **public-API-only** mode, in which the migration
inserts `dynamic` only where a type is part of the library's public API: the
signatures of declarations visible outside the library (parameter types,
return types, field and top-level variable types, supertypes, type parameter
bounds, and typedefs), including types that are inferred for public
declarations (such as a public `var items = [];`). Inside the library (in
function bodies, local variables, and private declarations), types would be
allowed to change from `dynamic` to `Object?` or `void`, and the developer
would take responsibility for checking and fixing the effects of those
changes. This protects against the most expensive mistake, silently changing a
type that other libraries see, while avoiding most of the churn of inserting
`dynamic` everywhere. Open questions for this mode include whether the unit
of migration is the library or the package (declarations in a package's
`lib/src/` that aren't exported are only visible within the package), and how
to warn about places inside the library whose meaning changes without a
compile-time error (such as the extension members case in
[Compatibility](#compatibility)).

If an author bumps a library's language version without running the
migration, the types of its declarations can change silently. Because
declarations whose types can't be determined get default types (`Object?` or
`void`) rather than becoming errors, most of the library may still compile,
while code in other libraries that relied on `dynamic` breaks, or silently
changes behavior (see the extension members case in
[Compatibility](#compatibility)).

## Tooling

*This section is not normative.*

*   **Analyzer options.** The `strict-raw-types` and `strict-inference`
    analyzer modes flag places where Dart invents `dynamic`. In a library where
    the feature is enabled, those places don't exist: a raw type or an
    unconstrained type argument means `Object?`, and a declaration whose type
    can't be determined gets a default type (or, for a local variable
    declaration with no type and no initializer, it is a compile-time error).
    So in such a library, the analyzer shouldn't report the diagnostics
    associated with these modes (`strict_raw_type` and the
    `inference_failure_on_*` diagnostics), even if the modes are enabled in
    `analysis_options.yaml`.

    *Some of this follows from what the diagnostics already check: for
    example, `strict_raw_type` is only reported when instantiate to bound
    produces `dynamic`. But some of the `inference_failure_on_*` diagnostics
    (such as `inference_failure_on_function_invocation`) are reported whenever
    inference leaves a type argument unconstrained, whatever type fills it in,
    so they need an explicit change.*

    *This supports the following workflow. A developer runs `dart migrate`,
    which changes `void f(List items)` to `void f(List<dynamic> items)`. After
    the library's language version is bumped, they decide that `List<Object?>`
    is what they want, and delete `<dynamic>`. The result means what they
    intend, so it shouldn't be flagged, even if their `analysis_options.yaml`
    still enables `strict-raw-types`.*

    Once the feature is enabled by default, and the `analysis_options.yaml`
    files in the ecosystem have been cleaned up, `strict-raw-types` and
    `strict-inference` can be deprecated.
*   **`avoid_init_to_null`.** This lint flags `var x = null;` and suggests
    removing `= null`. With the feature enabled, that would turn a valid local
    variable declaration into an error, so the lint shouldn't fire on local
    `var` declarations with no type annotation when the feature is enabled.
    *(For a top-level variable or field with no type annotation, removing
    `= null` doesn't change its type, which is `Object?` either way.)*
*   **Implementation notes.**
    *   The shared front-end code passes a `topType` parameter when computing
        greatest closures, solely so that the analyzer and the CFE can use
        different top types. When the feature is enabled, both the analyzer and
        the CFE will use `Object?`.
    *   The analyzer returns `Map<dynamic, dynamic>` directly for an empty `{}`
        with no context, without going through inference, so that code needs to
        change too.
    *   For a generator with no `yield` and no context, the analyzer infers
        element type `dynamic` and the CFE infers `Null` (or `Never` when the end
        of the body is unreachable). Both change to `Never`.
    *   Separately from this feature, the analyzer used to ignore a `yield* e;`
        statement when `e` has type `dynamic` or `Never`, so it inferred
        `Iterable<int>` for `() sync* { yield 1; yield* d; }` where the CFE
        inferred `Iterable<dynamic>`. This has been fixed in the analyzer to
        match the CFE ([sdk#64825][]), so `yield* (throw 'x')` alone now gives
        `Never` in both tools.

[sdk#64825]: https://github.com/dart-lang/sdk/issues/64825
[sdk#63795]: https://github.com/dart-lang/sdk/issues/63795
[language#4724]: https://github.com/dart-lang/language/pull/4724

## Specification cleanups

While making the changes above, the following stale text in the language
specification should also be fixed. None of these items changes the meaning of
the specification as it's implemented today.

*   "Type dynamic": the statements that declarations with no type annotation have
    type `dynamic` and that omitted type arguments default to `dynamic` predate
    instantiate to bound and type inference.
*   "Parameterized Types": the statement that an omitted bound is `dynamic`
    conflicts with the section "Generics" and with null safety, where an
    omitted bound is `Object?`.
*   "The Instantiation to Bound Algorithm": the cycle-breaking and substitution
    steps still say to substitute `Null` in contravariant positions; null safety
    changed this to `Never`.
*   "Try": the desugaring still uses `on dynamic catch`, which null safety
    changed to `Object`.
*   "Instance Method Closurization" and "Super Closurization": a parameter with
    no type annotation is said to have runtime type `dynamic`, which ignores
    override inference; covariant parameters are said to have runtime type
    `Object`, which should be `Object?`.
*   "For-in": "a top type" can be reworded as "`dynamic`", since the other top
    types are already errors there.
*   "Overview": the statement that omitted type annotations are "generally
    filled in with the type `dynamic`" predates instantiate to bound and type
    inference, and should be updated to describe them instead.

The following items in the language specification need to change to match the
new behavior:

*   "Type FutureOr": the name `FutureOr` used as an expression is said to denote
    a `Type` object for `FutureOr<dynamic>`. With the feature enabled it should
    be `FutureOr<Object?>`, matching how other raw types used as expressions are
    handled by instantiate to bound.
*   "Lists" and "Set and Map Literal Inference": with an unconstrained context,
    the inferred element (or key and value) type of a collection literal is
    specified as the least upper bound of the element types, which doesn't
    cover a literal with no elements. These sections should say that such a
    literal gets `Object?` type arguments (or defer to generic inference and
    instantiate to bound, which gives the same result).

The type inference specification (`resources/type-system/inference.md`) needs
these updates to match:

*   The rules that give `dynamic` to untyped function literal parameters with
    no context, or with no corresponding parameter in the context, should
    follow [Parameters](#parameters).
*   The rule that gives `dynamic` to a parameter with no corresponding
    parameter in the combined member signature should follow
    [Parameters](#parameters).
*   The rule that gives `dynamic` to an untyped variable with no initializer
    should make it an error for a local variable declaration, and give
    `Object?` otherwise (see [Variables](#variables)).
*   The rule for a variable whose initializer has type `Null` should give
    `Object?`. (It currently says "a subtype of `Null`", which would include
    `Never`, although the implementations only apply the rule to `Null`.)
*   The rule that gives `dynamic` to omitted return types should give `void`,
    or `Object?` for getters and operators other than `[]=` (see
    [Return types](#return-types)).
*   It should describe inferring an untyped optional parameter's type from its
    default value, and giving any other untyped parameter with no other source
    of a type the type `Object?`.
*   Its description of recursive local functions should say that the rule in
    [Recursive local functions](#recursive-local-functions) applies, giving
    return type `void`.
*   Its rule for the initial value of `T` when computing the actual returned
    type of a block body sets `T` to `Null` if the end of the block is
    reachable, without excluding generators. For a `sync*` or `async*`
    function literal or local function, `T` should start as `Never` whether
    or not the end of the block is reachable, matching
    [Generator element types](#generator-element-types). (As written, the rule
    would also give `() sync* { yield 1; }` element type `int?`; both
    implementations already give `int`.) *([language#4724][] makes this
    change.)*
*   Its rule for `yield* e;` in function literal return type inference only
    covers an `e` whose type has `Iterable<E>` (or `Stream<E>`) as a
    superinterface. It should say that an `e` of type `dynamic` contributes
    `dynamic`, and an `e` of type `Never` contributes `Never`.

## Possible extensions

*This section is not normative. It describes two related changes that could be
made together with this feature, or later. Neither is part of this proposal.*

### Requiring `override` for override inference

Under this proposal, a member with missing types still gets them from override
inference, with nothing in its declaration to say so:

```dart
abstract class A {
  void m(int x);
}

class B extends A {
  void m(x) {}  // x is int, from A.m.
}
```

A reader of `B` can't tell whether `x` has a type without looking at `B`'s
supertypes. An extension could limit override inference to members marked with
an `override` keyword, as proposed in [language#1610][] (see
`working/1610 - override/proposal.md`). A member without the keyword would then
fall under this proposal's rules for declarations without a type, so in
`void m(x) {}` above, `x` would have type `Object?`, whereas in
`override void m(x) {}`, `x` would have type `int`.

[language#1610]: https://github.com/dart-lang/language/issues/1610

Considerations:

*   **Dependency.** The `override` keyword proposal hasn't been accepted, so
    this extension can't happen until it is.
*   **Breaking change.** Every override that relies on override inference and
    lacks the keyword would break. The `override` proposal itself notes that
    requiring the keyword in order to get the supertype's signature would be
    breaking, and it was later revised so that omitting `override` isn't an
    error (only a spurious `override` is). The migration would need to add
    the keyword wherever override inference is used, and could also convert
    existing `@override` annotations to the keyword. Adding it to every
    override, even unannotated ones, would match what users might expect, but
    could break packages that support a range of dependency versions: a member
    that overrides something under one version of a dependency might not under
    another, and a spurious `override` is an error.
*   **Fields with initializers.** Today, override inference takes precedence
    over an initializer. In this example, `x` has type `num`, not `int`:

    ```dart
    abstract class Base {
      num get x;
      set x(num v);
    }

    class Sub extends Base {
      var x = 0;  // x is num, from override inference.
    }
    ```

    If override inference required the keyword, `var x = 0;` without
    `override` would get type `int` from its initializer, and its implicit
    setter would no longer be a valid override of `set x(num v)`. The extension
    would need to decide whether that's acceptable, or whether fields need
    different treatment.

### Raw types as `_` in downwards contexts

Under this proposal, a raw type means instantiate to bound, so `List` means
`List<Object?>`:

```dart
List x = [3];  // x is List<Object?>, holding an <Object?>[3].
```

That's safe, but probably not what the author meant. An extension could treat
a raw type that's used as the declared type of a variable with an initializer
as having `_` (an unknown type to be inferred) for each missing type argument.
The initializer would then be inferred in the context `List<_>`, and the type
arguments would come from it:

```dart
List x = [3];  // Inferred as List<int> x = <int>[3];
```

With this extension, a raw type in such a position would give the precise
type, rather than a safe but uninformative one.

Considerations:

*   **Which positions.** It only makes sense where there's an expression to
    infer from, like a variable's initializer. A parameter type (`void f(List
    x)`) or a return type has nothing to infer from, and inferring a return
    type from the body would make a function's signature depend on its body.
    Those raw types would still mean instantiate to bound.
*   **Timing.** Shipping this extension together with this feature means
    affected code is migrated once. Shipping it later would be a second
    breaking change, because types that this feature makes `Object?` would
    become more specific, so for example `List x = [3]; x.add('a');` would
    break.
*   **`is` and `as`.** A similar affordance could apply to type tests and
    casts:

    ```dart
    Iterable<int> it = ...;
    if (it is List) ...  // Could promote `it` to List<int>.
    it as List;          // Could cast to List<int>.
    ```

    Today, `it is List` doesn't promote `it` at all, because `List` means
    `List<dynamic>`, which isn't a subtype of `Iterable<int>`. This variant
    needs different machinery, because there's no downwards inference
    involved: the type arguments would have to be computed from the static
    type of `it`, so that `it is List` succeeds exactly when `it is List<int>`
    does. Object patterns already do something similar: in
    `if (it case List())`, the pattern's type is inferred as `List<int>`. (By
    contrast, a raw type in a declared-variable pattern, as in
    `if (it case List l)`, means instantiate to bound.)

## Open questions

*   **Breakage measurements.** How much code does each part of this change
    affect? Counts should be attributed to root causes rather than raw
    diagnostics, and the error handler case should be counted separately.
*   **Variables initialized with `null`.** Under this proposal,
    `var x = null;` gives `x` the type `Object?`, while `var x;` is an error
    if `x` is a local variable. Should a local variable whose initializer has
    type `Null` (and no type annotation) be an error too? One argument for
    `Object?` is consistency with parameters: an untyped optional parameter
    whose default value is `null` gets type `Object?`, as an optional
    declaring parameter of a primary constructor with default value `null`
    already does. Such local variables appear to be rare in practice.
*   **Top-level variables and fields with no type and no initializer.** This
    proposal gives them type `Object?`, as it does for parameters. Should they
    be errors instead, like local variables, so that the error is reported at
    the declaration? (For a field initialized by a constructor, as in
    `class C { var x; C(this.x); }`, `Object?` matches the type a declaring
    parameter of a primary constructor gives its field, as in
    `class C(var x);`.) A measurement of how often such declarations occur,
    and of how often `Object?` would cause errors elsewhere, would help
    answer this.
*   **Augmentations and type inference.** This proposal assumes that
    augmentations are merged before type inference fills in the omitted types
    of the introductory declaration (as described in the augmentations
    feature specification), so a parameter's type can be inferred from a
    default value supplied by an augmentation. An alternative view is that
    the introductory declaration is inferred on its own, and augmenting
    declarations must then match it. Which model is intended, and what does
    it imply for parameters, fields, and top-level variables whose types are
    omitted?
*   **Least upper bounds that produce `Function`.** When the least upper bound
    of two function types with different shapes (different numbers of
    positional parameters, or different named parameters) is computed, the
    result is `Function`. An invocation of an expression whose static type is
    `Function` isn't checked at compile time; its arguments are only checked
    at runtime, just as for `dynamic`. So inference can invent this kind of
    dynamic behavior even though nothing in the program asks for it:

    ```dart
    void f(bool b) {
      var g = b ? (int x) => x : () => '';  // g has type Function.
      g(1, 2, 3);  // Accepted at compile time; throws at runtime.
    }
    ```

    One possible fix is for the least upper bound of two such function types
    to be `Object` instead of `Function`. That would be a breaking change of
    its own: code that invokes the result of such an expression, or passes it
    where a `Function` is expected, would break. In a large internal codebase,
    only a handful of sites rely on such a least upper bound being callable.
    Should this feature include that change?

    Another possible fix is to keep the least upper bound as it is, but stop
    allowing dynamic invocation of an expression whose static type is
    `Function`, so that invoking it requires a cast such as `as dynamic`.
    `Function` would remain the supertype of all function types. That would
    also cover code that declares a type as `Function` explicitly, so it would
    probably be considerably more breaking, and it would need to be measured.

    *The analogous case for records doesn't have this problem. The least upper
    bound of two record types with different shapes is `Record`, but the only
    members of `Record` are those of `Object`, so a value of static type
    `Record` can't be invoked, and its fields can't be accessed without a
    cast. A record literal whose context type is `Record` is inferred the same
    way as one with no context type.*
*   **Normalizing `dynamic` and `Object?` at runtime.** Should `Type` objects
    for types that differ only in `dynamic` versus `Object?` be equal, so that,
    for example, the `Type` objects for `List<dynamic>` and `List<Object?>` are
    `==` and have the same `hashCode`? That would remove the hazard for
    `Type`-keyed maps described in [Compatibility](#compatibility), and it's
    arguably what users would expect, since the two types are mutual subtypes
    and behave the same in `is` and `as` checks. It could be done by
    normalizing reified types (replacing `dynamic`, and perhaps `void`, with
    `Object?`), or only in `Type.operator ==` and `Type.hashCode`. But either
    way, it would change runtime behavior for all code, regardless of language
    version, so it would need its own breaking change review, and it would
    need to be implemented on every platform.
*   **Core libraries.** Some declarations in the core libraries introduce
    `dynamic` into user code. For example, several members in `dart:async`
    (such as `StreamConsumer.close`) are declared to return a raw `Future`,
    and `jsonDecode` in `dart:convert` returns `dynamic`. When the core
    libraries are opted into this feature, the raw types would change meaning
    (from `Future<dynamic>` to `Future<Object?>`) unless they're migrated to
    `Future<dynamic>`. Should the core libraries be migrated mechanically,
    preserving their current types, or should some of these declarations be
    changed alongside this feature (for example, to `Future<void>`, or to
    return `Object?`), each of which would be a breaking change of its own?

## Changelog

### 1.4

-   Use default types instead of errors for declarations whose types can't
    be determined: `Object?` for parameters (including declaring
    parameters of primary constructors, as today) and for top-level
    variables and fields with no initializer; `void` for omitted return
    types (including `async` functions, function types, old-style
    typedefs, and recursive local functions); and `Object?` for the
    return types of getters and operators other than `[]=`.
-   Keep local variable declarations with no type and no initializer as
    errors, with a rationale based on data from open-source code, and
    state that `var x = null;` getting type `Object?` is deliberate.
-   Update Compatibility, Migration (including `main`, converting
    `Future.catchError` calls to `Future.onError`, and a possible
    public-API-only migration mode), Tooling, and Specification cleanups
    to match.
-   Correct Runtime semantics, which said that changed reified types can
    only be observed through `Type` objects.
-   Specify that a parameter's type can be inferred from a default value
    supplied by an augmentation.
-   Remove the open questions about inferring parameter types from
    default values, primary constructors, and defaults instead of errors,
    which have been resolved, and add an open question about least upper
    bounds that produce `Function`.
-   Add open questions about variables initialized with `null`, top-level
    variables and fields with no type and no initializer, and how
    augmentations interact with type inference.

### 1.3

-   Specify that the `strict-raw-types` and `strict-inference` analyzer
    modes don't report in libraries with the feature enabled, and when
    they can be deprecated.
-   Specify that the migration uses a new set of lints rather than the
    existing diagnostics.
-   Describe two ways for the migration to avoid inserting `dynamic`:
    invocations whose results are discarded, and adding `extends Object?`
    to classes designed to be used raw.
-   Note the hazard for maps keyed by `Type` objects during an incremental
    migration.
-   Add open questions about normalizing `dynamic` and `Object?` at
    runtime, and about changing core library declarations.
-   Add the default bound of type parameters to the precedents, and use
    `on Object?` in the extension example.

### 1.2

-   Add an open question about defaults instead of errors (such as `void`
    for omitted return types).
-   Specify that the rules for declarations without a type apply to
    introductory declarations, not augmenting declarations.
-   Clarify wording in several places, including the types of `catch`
    clause variables, which variables a declaration needs a type for, and
    why `for`-`in` over `dynamic` keeps `dynamic`.

### 1.1

-   Note that an extension can start applying to a receiver whose type
    changes from `dynamic` to `Object?`, silently changing behavior.
-   Describe inserting `dynamic` only where it matters as a possible
    refinement of the migration.
-   Point to [sdk#63795][], which proposes the change to generators with no
    `yield` separately.
-   Note that [sdk#64825][] has been fixed.

### 1.0

-   Initial version.
