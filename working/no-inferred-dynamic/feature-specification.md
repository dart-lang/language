# No Inferred Dynamic

Author: Paul Berry

Status: Draft

Version 1.0 (see [Changelog](#changelog) at end)

Experiment flag: no-inferred-dynamic

This feature removes the places where Dart's type inference produces the type
`dynamic` without being asked to. After this change:

*   When inference has to fill in a type argument and has no information to go
    on, it uses `Object?` instead of `dynamic`.
*   When a declaration has no type annotation and inference has no way to
    determine its type, that's a compile-time error.

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
`dynamic` can be traced back to the declaration of `d`. What changes is that
inference no longer *invents* `dynamic` where nothing in the program says so.

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

Nothing is missing from this declaration: it has an initializer, and inference
has a perfectly good answer available. The `dynamic` is invented.

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
looking. This proposal settles all of these cases on `Object?`, as the
specification already says.

### Precedent

Dart has already moved away from inventing `dynamic` several times. Most
recently, the [primary constructors][] feature gives a declaring parameter with
no type annotation and no default value the type `Object?`, and does the same
when the default value is `null`, explaining: *"Dart has traditionally assumed
the type `dynamic` in such situations. We have chosen the more strictly checked
type `Object?` instead, in order to avoid introducing run-time type checking
implicitly."* (This proposal extends that feature's rule for default values to
all parameters, and makes the case with no default value an error; see
[Parameters](#parameters).)

[primary constructors]: ../../accepted/3.13/primary-constructors/feature-specification.md

Before that, null safety removed several places where Dart invented `dynamic`:

| Case | Before null safety | With null safety |
|---|---|---|
| `catch (e)` | `dynamic` | `Object` |
| Parameter of `operator ==` | `dynamic` | `Object` |
| Function literal parameter whose context type is a subtype of `Null` | `dynamic` | `Object?` |
| Recursive call to a local function with no declared return type | `dynamic` | inference failure (as specified; see [Recursive local functions](#recursive-local-functions)) |

The third row is exactly the change this proposal makes elsewhere, and the
fourth is a precedent for making inference failures into compile-time errors.

## Overview

*This section is informal. The normative rules are in
[Static semantics](#static-semantics).*

The changes follow two rules:

*   **A type argument that inference would have to invent becomes `Object?`.**
    This covers raw types (`List` means `List<Object?>`), unconstrained type
    variables in generic inference (`var l = [];` gives `List<Object?>`), and
    greatest closures.
*   **A declaration whose type can't be determined becomes a compile-time
    error.**
    This covers variables with no type and no initializer, parameters with no
    type and nothing to infer one from, omitted return types (outside of
    function literals and non-recursive local functions, whose return types are
    inferred from their bodies), and recursive local functions with no declared
    return type.

Why treat these two cases differently? It comes down to how useful it is to fill
in `Object?`. Filling `Object?` in for a type argument is generally still
useful: for example, a `List<Object?>` can be iterated, printed, and passed
along, and only the uses that really need a more specific type are errors. On
the other hand, filling `Object?` in as the type of a variable or parameter is
practically useless, because Dart doesn't narrow a variable's type when a value
is assigned to it, so nearly every use site would then be an error. Reporting a
single error at the declaration site puts the error where the fix goes.

There are three deliberate exceptions:

*   A variable whose initializer has type `Null` (as in `var x = null;`) gets
    type `Object?`, since the author did write an initializer.
*   A parameter named `_` with no type and nothing to infer one from (as in
    `void f(_) {}`) gets type `Object?`, unless it's a declaring parameter of a
    primary constructor. As a parameter type, `Object?` accepts any argument,
    and since such a `_` can't be referred to, nothing is lost.
*   A generator function literal or local function with no `yield` gets element
    type `Never`, since it produces no elements.

| Construct | Today | With this feature |
|---|---|---|
| `List x;` (raw type) | `List<dynamic>` | `List<Object?>` |
| `class D<T extends Comparable<T>> {}` then `D d;` | `D<Comparable<dynamic>>` | `D<Comparable<Object?>>` |
| `var l = [];` | `List<dynamic>` | `List<Object?>` |
| `var m = {};` | `Map<dynamic, dynamic>` | `Map<Object?, Object?>` |
| `var x;` | `dynamic` | error |
| `var x = null;` | `dynamic` | `Object?` |
| `void f(x) {}` | `x` is `dynamic` | error |
| `void f(_) {}` | `_` is `dynamic` | `_` is `Object?` |
| `void f([x = 0]) {}` | `x` is `dynamic` | `x` is `int` |
| `class C(var x);` (primary constructor) | `x` is `Object?` | error |
| `var g = (x) => x;` | `x` is `dynamic` | error |
| `f() {}` (top-level) | returns `dynamic` | error |
| `fib(int n) => ... fib(n - 1) ...;` (local) | returns `dynamic` | error |
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

*A bound that is written as `Object` is unaffected: `class F<T extends Object>
{}` already instantiates to `F<Object>`.*

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
fields. It matches the rule the primary constructors feature uses for a
declaring parameter whose default value is `null`. An initializer of type
`Never` (such as `throw 'x'`) gives the variable type `Never`, as it does
today. (The type inference specification says that `dynamic` is used whenever
the initializer's type is a subtype of `Null`, which would include `Never`, but
the implementations only do this for `Null`; see
[Specification cleanups](#specification-cleanups).)*

#### Generator element types

*   If a function literal or local function is a generator, its return type is
    inferred from its body, and its body contains no `yield` or `yield*`
    statements, then its inferred element type is `Never`, whether or not the
    end of the body is reachable. So its inferred return type is
    `Iterable<Never>` for `sync*` and `Stream<Never>` for `async*` (unless the
    context type wins, as it does today). *(In the terms of the type inference
    specification, the generator's "actual returned type" is `Never`.)*

    ```dart
    var f = () sync* {};   // Iterable<Never> Function()
    var g = () async* {};  // Stream<Never> Function()
    ```

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

It's a compile-time error if a variable declaration (a local variable
declaration, or a top-level, static, or instance variable declaration) declares
a variable without a type annotation and without an initializing expression,
unless its type is provided by override inference.

*This applies whether the variable is declared with `var`, `final`, `late`,
`abstract`, or `external`:*

```dart
var a;            // Error.
final b;          // Error.
late var c;       // Error.

class C {
  static var s;   // Error.
  final f;        // Error.
  C(this.f);
}

abstract class Base {
  int get i;
  abstract var j; // Error.
}

class Sub extends Base {
  var i;          // OK: type int, from override inference.
  Sub(this.i);
}
```

*Variables that get their types from an enclosing construct aren't variable
declarations in this sense, and are unaffected: a `for`-in loop variable gets
its type from the iterable, a `catch` clause's variables are `Object` and
`StackTrace`, and a pattern variable gets its type from the matched value.*

*The rationale for making these declarations errors is that Dart doesn't narrow
a variable's declared type when a value is assigned to it, so giving such a
variable the type `Object?` would make most later uses errors anyway. Reporting
the error at the declaration site rather than the usage sites is more useful. A
side benefit of making these declarations errors is that it opens up the
possibility of a future language change that would make some of these
declarations valid again (e.g., by letting the type be determined by the first
assignment).*

#### Parameters

A formal parameter with no type annotation gets its type from the first of the
following that applies:

1.  Override inference (*including from a combined member signature*).
2.  For an initializing formal (`this.x`) or a super parameter (`super.x`), the
    corresponding field or super constructor parameter.
3.  For a parameter of a function literal whose context type is a function type
    with a corresponding parameter, that corresponding parameter.
4.  **New:** if the parameter is optional and has a default value, the default
    value. Its type is the static type of the default value expression,
    inferred in the empty context, or `Object?` if that type is `Null`.
5.  If the parameter's name is the wildcard `_` and it isn't a declaring
    parameter of a primary constructor, `Object?`. *(A declaring parameter
    named `_` declares a field or representation variable named `_`, which can
    be read, so it's treated like any other declaring parameter.)*

If none of these applies, it's a compile-time error.

*Item 4 is the rule the primary constructors feature already uses for
declaring parameters, extended to all parameters. Today, a default value
determines the type of a declaring parameter only; an ordinary untyped
parameter with a default value has type `dynamic`. A parameter's default value
is part of its function's signature, not its body, so this doesn't make a
signature depend on a body. See also [Open questions](#open-questions).*

*This applies to parameters of functions, methods, constructors, setters,
operators, and function literals, and to the parameters inside old-style
function-typed parameters and typedefs. For an old-style function-typed
parameter itself, such as `void f(callback())` or `void f(_())`, the optional
type written before the name is its return type, so a missing one is covered
by [Return types](#return-types) rather than by this rule.*

*Some consequences:*

*   *An untyped optional parameter with a default value gets its type from the
    default value, and one with no default value (and no type from anywhere
    else) is an error. This applies to declaring parameters of primary
    constructors too. For them, the only change is that a parameter with no
    default value becomes an error, where the primary constructors feature
    gives it type `Object?`. See [Open questions](#open-questions).*

    ```dart
    void f([x = 0]) {}        // OK: x is int (today: dynamic).
    void g({y = null}) {}     // OK: y is Object? (today: dynamic).
    void h([z]) {}            // Error (today: z is dynamic).
    class C(var x);           // Error (today: x is Object?).
    class D([var x = 0]);     // OK: x is int, as today.
    class E(var _);           // Error (today: the field `_` is Object?).
    extension type F(x);      // Error (today: x is Object?).
    ```

*   *A function literal with no context, or whose context type isn't a function
    type (such as `Function` or `Object`), can't have untyped parameters,
    except optional ones with default values:*

    ```dart
    var g = (x) => x;        // Error.
    var h = (int x) => x;    // OK.
    var i = ([x = 0]) => x;  // OK: x is int, from the default value.
    ```

*   *A function literal with extra optional parameters (beyond its context
    function type) can't leave them untyped, unless they have default values.*

    ```dart
    void f(void Function(int) callback) {}

    f((a, [b]) {});     // Error: `b` has no corresponding context parameter.
    f((a, {b}) {});     // Error: same reason.
    f((a, [b = 0]) {}); // OK: `b` is int, from the default value.
    f((a, [_]) {});     // OK: `_` has type Object?.
    ```

*   *Likewise, a method that adds a parameter (beyond the parameters in the
    combined member signature of the members it overrides) can't leave that
    parameter untyped, unless it has a default value. (Today such a parameter
    gets type `dynamic`.)*

    ```dart
    abstract class A {
      void m(int x);
    }

    class B extends A {
      void m(x, [y]) {}      // Error: `y` has no type. (`x` is int.)
    }

    class C extends A {
      void m(x, [y = '']) {} // OK: `y` is String. (`x` is int.)
    }
    ```

*   *Unlike the existing `inference_failure_on_untyped_parameter` diagnostic,
    this rule doesn't exempt parameters that the body never refers to. A
    parameter's type is part of its function's signature, so it can't depend on
    the body.*

*   *The error handlers taken by `Future.catchError`, `Future.then`'s `onError`,
    and `Stream.listen`'s `onError` are declared with type `Function`, so their
    parameters must be typed. See [Compatibility](#compatibility).*

#### Return types

It's a compile-time error if any of the following has no declared return type
and its return type isn't provided by override inference:

*   a top-level function, a static method, or an instance method or operator
    other than `[]=`,
*   a top-level, static, or instance getter,
*   an old-style function-typed formal parameter (`void f(int callback())`),
*   a generic function type (`Function(int)`), or
*   an old-style typedef (`typedef F(int x);`).

*Setters and `operator []=` aren't affected: when their return type is omitted
it's already `void`. Function literals and non-recursive local functions aren't
affected: their return types are inferred from their bodies.*

```dart
f() {}                  // Error.
get g => 1;             // Error.
void h(callback()) {}   // Error.
typedef F(x);           // Error (return type; `x` is also untyped).
typedef G = Function(); // Error.

void main() {
  local() => 1;         // OK: return type int, inferred from the body.
}
```

*`main` isn't special: `main() {}` is an error. See [Migration](#migration) for
how this is handled.*

#### Recursive local functions

It's a compile-time error if a local function declaration has no declared
return type and its body refers to the function itself (by calling it or by
tearing it off).

```dart
void main() {
  fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);      // Error.
  int fib2(int n) => n < 2 ? n : fib2(n - 1) + fib2(n - 2); // OK.
}
```

*The type inference specification already says that, with null safety, a
recursive call whose result type is needed for inference is an inference
failure. Neither implementation does this today: both give the recursive call
type `dynamic`, and that `dynamic` becomes the function's inferred return type
whenever the call's result is returned. This rule makes the error simple and
syntactic.*

### What doesn't change

*   **Explicit `dynamic`** keeps its meaning, and so does everything derived from
    it: member accesses, calls, and index operations on `dynamic` still have
    type `dynamic`.
*   **`for`-in over a `dynamic` iterable.** The language specification says that
    when the static type of the iterable is a top type, the loop treats it as
    `Iterable<dynamic>`. But it's a compile-time error unless that type is
    assignable to `Iterable<dynamic>`, so the only valid case is iterating a
    `dynamic` value, and the loop variable's `dynamic` comes from that value.
    This is propagation, not invention, and it's unchanged.

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
change, some reified type arguments change too:

```dart
List x = [];   // a List<Object?> at runtime (was List<dynamic>)
Object f() sync* { yield 1; }  // returns an Iterable<Object?> (was Iterable<dynamic>)
```

`dynamic` and `Object?` are mutual subtypes, so `is` and `as` checks behave the
same either way. The difference can only be observed through `Type` objects,
for example `runtimeType`, `toString()`, or `==` on `Type` values.

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

*`dynamic` and `Object?` are mutual subtypes, so mixing libraries on different
language versions raises no soundness questions; the only difference is which
static errors are reported.*

## Compatibility

Moving a library to a language version that has this feature can break code in
that library in these ways:

*   Code that relied on `dynamic` produced by instantiate to bound, by
    unconstrained inference, or by a greatest closure, now sees `Object?`, so
    member accesses and calls that were dynamically dispatched become
    compile-time errors.
*   Declarations with no type that can't be inferred become compile-time errors.
*   Untyped optional parameters with a default value change from `dynamic` to
    the default value's type, so code that relied on `dynamic` (for example,
    assigning a `String` to a parameter whose default is `0`) becomes a
    compile-time error.
*   Recursive local functions with no declared return type become compile-time
    errors.

Some specific cases are worth calling out:

*   **Error handlers taking `Function`.** The parameter of `Future.catchError`,
    the `onError` parameter of `Future.then`, and the `onError` parameter of
    `Stream.listen`
    are declared with type `Function`, because a handler may take either one
    argument or two. So a handler like `future.catchError((e) { ... })` has no
    context for its parameter types and becomes an error. It needs to be written
    `(Object e) { ... }` or `(Object e, StackTrace s) { ... }`. This pattern is
    common, so it's likely to be the largest single source of errors from the
    parameter rule.
*   **`main`.** Writing `main() {}` becomes an error. See the
    [migration](#migration) section for a recommendation on how to address
    this.
*   **Primary constructors.** A declaring parameter with no type annotation, no
    type from override inference, and no default value becomes an error, even
    though today it has type `Object?` rather than `dynamic`.
*   **Generators with no `yield`.** A generator function literal or local
    function with no `yield` now has element type `Never`, so code that relies
    on a different element type for its result can break. For example, given
    `var l = (() sync* {})().toList();`, `l.add(null)` compiles today (the
    analyzer infers `List<dynamic>` and the CFE `List<Null>`) but is a
    compile-time error with this feature. Such code should be rare. *(The change
    to generators declared to return a supertype of `Object` can't break code at
    compile time; see [Runtime semantics](#runtime-semantics).)*

## Migration

*This section is not normative.*

The intended migration is `dart migrate`, which enables a set of lints and
applies their quick fixes *before* the project's language version is bumped.
Each lint runs under the old language version and finds the places where
inference *will* behave differently once the feature is enabled; each fix makes
the old behavior explicit, usually by inserting `dynamic`. After that, bumping
the language version changes nothing.

Under this approach, a site where the feature reports an error costs the same
to migrate as a site where it changes a type to `Object?`: both are fixed by
writing `dynamic`.

| Change | Existing lint | Fix |
|---|---|---|
| Raw types (including in `with` clauses) | `strict-raw-types` | `List` → `List<dynamic>` |
| Object patterns with an unconstrained type argument (`case Foo(:var x):`) | none | `Foo` → `Foo<dynamic>` |
| Unconstrained generic inference, empty collection literals | `inference_failure_on_function_invocation`, `inference_failure_on_generic_invocation`, `inference_failure_on_instance_creation`, `inference_failure_on_collection_literal` | add explicit type arguments |
| Variables with no type and no initializer | `inference_failure_on_uninitialized_variable` | add `dynamic` |
| Untyped parameters | `inference_failure_on_untyped_parameter` (note: the lint currently skips unused parameters) | add `dynamic` |
| Untyped optional parameters with a default value (other than declaring parameters) | `inference_failure_on_untyped_parameter` | add `dynamic` |
| Untyped declaring parameters of primary constructors with no default value | none | add `Object?` (their current type) |
| Omitted return types | `inference_failure_on_function_return_type` | add `dynamic` |
| `var x = null;` | none | `dynamic x = null;` |
| Extra optional closure parameters | none | add `dynamic` |
| Recursive local functions | none for local functions | add a `dynamic` return type |
| Greatest closure (function literal returns) | none | add explicit types |
| Generators with no `yield` (function literals and local functions) | none | local functions: add a return type such as `Iterable<dynamic>`; function literals can't declare a return type, so they need an explicit context type or manual attention |

None of the existing diagnostics has a quick fix today, so the fixes need to be
written, and several lints are new. Fixes that would insert `Object?` (which
some existing tools do when adding a type annotation) aren't
semantics-preserving where the current type is `dynamic`; the migration must
insert `dynamic` there.

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
    and no `return` statements should be migrated to return type `void`, or
    `Future<void>` if it's `async`, rather than `dynamic`. *This isn't
    semantics-preserving: code that calls `main` and uses its result would
    break. We expect such code to be essentially nonexistent, except that test
    runners sometimes write `await other_test.main();`. That's why an `async`
    `main` becomes `Future<void>`: with `void`, that line would be an error.*
*   **Error handlers:** a fix can insert `Object e` (and `StackTrace s`) rather
    than `dynamic e` when the handler body doesn't rely on `e` being `dynamic`.

*If an author bumps a library's language version without running the
migration, the types of its public declarations can change silently: the
library itself may still compile, while code in other libraries that relied on
`dynamic` breaks.*

## Tooling

*This section is not normative.*

*   **Analyzer options.** The existing `strict-inference` and `strict-raw-types`
    analyzer options become redundant for code with the feature enabled. They
    can be deprecated, pointing users at the feature.
*   **`avoid_init_to_null`.** This lint flags `var x = null;` and suggests
    removing `= null`. With the feature enabled, that would turn a valid
    declaration into an error, so the lint shouldn't fire on `var` declarations
    with no type annotation when the feature is enabled.
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
    *   Separately from this feature, the analyzer currently ignores a `yield*
        e;` statement when `e` has type `dynamic` or `Never`, so it infers
        `Iterable<int>` for `() sync* { yield 1; yield* d; }` where the CFE
        infers `Iterable<dynamic>`. This is being fixed in the analyzer to match
        the CFE ([sdk#64825][]). After that fix, `yield* (throw 'x')` alone
        gives `Never` in both tools.

[sdk#64825]: https://github.com/dart-lang/sdk/issues/64825

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
    should make it an error (see [Variables](#variables)).
*   The rule for a variable whose initializer has type `Null` should give
    `Object?`. (It currently says "a subtype of `Null`", which would include
    `Never`, although the implementations only apply the rule to `Null`.)
*   The rule that gives `dynamic` to omitted return types should make them
    errors (see [Return types](#return-types)).
*   It should describe inferring an untyped optional parameter's type from its
    default value.
*   Its description of recursive local functions should say that the rule in
    [Recursive local functions](#recursive-local-functions) applies.
*   Its rule for the initial value of `T` when computing the actual returned
    type of a block body sets `T` to `Null` if the end of the block is
    reachable, without excluding generators. For a `sync*` or `async*`
    function literal or local function, `T` should start as `Never` whether
    or not the end of the block is reachable, matching
    [Generator element types](#generator-element-types). (As written, the rule
    would also give `() sync* { yield 1; }` element type `int?`; both
    implementations already give `int`.)
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
fall under this proposal's rules for declarations without a type, so
`void m(x) {}` above would be an error, and `override void m(x) {}` would be
valid, with `x` of type `int`.

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
*   **Inferring parameter types from default values.** This proposal infers an
    untyped optional parameter's type from its default value (as in
    `void f([x = 0])`, where `x` becomes `int`), extending the rule the primary
    constructors feature uses for declaring parameters. That's new inference,
    not just the removal of an invented `dynamic`. The alternative is to make
    every untyped parameter with no other source of type an error, even with a
    default value. That's simpler, but either it's inconsistent with primary
    constructors or it removes inference that feature has already shipped. Is
    extending the rule the right choice?
*   **Primary constructors.** This proposal makes an untyped declaring
    parameter of a primary constructor with no default value (as in
    `class C(var x);`) a compile-time error, for consistency with other
    parameters. That changes the primary constructors feature, which currently
    gives such a parameter type `Object?` and doesn't involve `dynamic` at all.
    Is that change worth making, or should declaring parameters keep `Object?`
    as an exception to the parameter rule?

## Changelog

### 1.0

-   Initial version.
