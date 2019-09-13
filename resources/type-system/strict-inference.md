# Strict inference static analysis option

This document specifies the "Strict inference" mode enabled with a static
analysis option. As a static analysis option, we only intend to implement this
feature in the Dart Analyzer. Under this feature, when there is not enough
information available to infer an expression's type, where inference "falls
back" to `dynamic` (or the type's bound), inference is considered to have
failed, and an analyzer "Hint" is reported at the location of the expression.

## Enabling strict inference

To enable strict inference, set the `strict-inference` option to `true`, under
the Analyzer's  `language` section:

```yaml
analyzer:
  langauge:
    strict-inference: true
```

## Motivation

It is possible to write Dart code that passes all static analysis and
compile-time checks that is guaranteed to result in runtime errors. Common
examples include runtime type errors, and no-such-method errors. New and
experienced Dart developers alike write such code, and are surprised to see
such errors at runtime, which look like they should be caught at compile time.

The strict inference mode aims to highlight such code during static analysis.
Consider two motivating examples:

### Example: under-constrained list literals

```dart
fn(List<int> numbers) => print(numbers.first.isEven);

void main() {
  var args = ["one", "two", "three"];
  var useArgs = true;
  var numbers = useArgs ? args : [];
  fn(numbers);
}
```

Depending on the value of `useArgs`, the last line will result in a runtime
error. The developer thinks that `args` is an appropriate value to send to
`fn`, because `args` is assigned to `numbers`, and `numbers` is sent to `fn`,
so surely static analysis would have reported if this was illegal. In real
world cases of this code, `fn` and `main` may be authored by different
developers, and may be located in separate packages. `args` may have been
created in a third location, by a third developer, with a complex generic type.
Static analysis is supposed to help developers catch where they have
misunderstood an API or the type of an object they are handling.

The developer might think that the type of `[]` is unimportant, or that it is
inferred from the expression to the left of `:`. Instead, the type of `[]` is
only inferred from the types of its elements. As their are none, it "falls
back" to `dynamic`. Then type of the conditional expression `useArgs ?  args :
[]` is inferred from the "then" and "else" expressions, `args` (`List<String>`)
and `[]` (`List<dynamic>`), resulting in LUB of the two, `List<dynamic>`.

Static analysis allows a `List<dynamic>` argument for a `List<int>`, as an
implicit cast. At runtime, however, `args` (a `List<String>`) fails to cast to
`List<int>`.

To prevent such an error, an empty collection literal (`[]`, `{}`) without an
explicit type argument, and whose type cannot be inferred from downwards
inference is considered to have an inference failure. In this example, the
strict inference failure would report that the type of `[]` cannot be inferred,
and suggest that the developer add an explicit type argument. The developer
would likely add `<String>`, thinking "`args` is a `List<String>` and I think
that `fn` accepts a `List<String>`, so I'll make the empty list alternative
also a `List<String>`." At this point, existing static analysis will inform the
developer that a `List<String>` cannot be passed where a `List<int>` is
expected.

### Example: Under-constrained generic method invocations

Consider the signature of [`Iterable.fold`]:

> T fold <T>(T initialValue, T combine(T previousValue, E element))

```dart
void main() {
  var a = [1, 2, 3].fold(true, (s, x) => s + x);
}
```

There are no compile-time, static analysis errors in this code, but it is
guaranteed to produce a failure at runtime, when `true + 1` is executed. The
issue here is similar to the previous one: the developer likely thinks that the
type of `s` (`T`) will be inferred from the type of `initialValue`, and that
static analysis would report any issue with that type. But inference doesn't
flow between parameters like that. Instead, while trying to infer the `T` on
`fold`, there is not enough information from downwards inference (the type of
`a`); upwards inference first constrains `T` to be a supertype of the first
argument's type (`bool`), then must decide on the type of the second argument,
to use that as a second constraint. `s` is assumed to be `dynamic`, which makes
the argument's type `dynamic Function(dynamic, int)`. So inference additionally
constrains `T` to be a supertype of `dynamic`. The LUB of `bool` and `dynamic`
is `dynamic`, so the final static type of `T` is `dynamic`.

The issue would be revealed with either an explicit type on `fold`, an explicit
type for `a`, which would help to infer the type of `s`, or an explicit type
for `s`:

```dart
void main() {
  // Each of these produce an existing error:
  //
  //     "The operator '+' isn't defined for the class 'bool'."
  var b = [1, 2, 3].fold<bool>(true, (s, x) => s + x);
  bool c = [1, 2, 3].fold(true, (s, x) => s + x);

  // This produces an existing error:
  //
  //     "The argument type 'int Function(int, int)' can't be assigned to the 
  //     parameter type 'Object Function(Object, int)'"
  var d = [1, 2, 3].fold(true, (int s, int x) => s + x);

  // This produces an existing error:
  //
  //     "Couldn't infer type parameter 'T'. Tried to infer 'Object' for 'T'
  //     which doesn't work: Parameter 'combine' declared as
  //     'T Function(T, int)' but argument is 'int Function(int, int)'. The type
  //     'Object' was inferred from: Parameter 'initialValue' declared as 'T'
  //     but argument is 'bool'. Consider passing explicit type argument(s) to
  //     the generic."
  var e = [1, 2, 3].fold(true, (int s, x) => s + x);
}
```

In strict inference mode, the inference failure on `(s, x) => s + x` will be
reported, enouraging the developer to add a type to `s`, `a`, or `fold`,
revealing their misunderstanding of the types.

[`Iterable.fold`]: https://api.dartlang.org/stable/dart-core/Iterable/fold.html

## Conditions for strict inference failure

This is an exhaustive list of conditions that result in an inference failure,
under the strict inference mode. Examples are given for each condition, as
well as examples that highlight code without any inference failures.

### Uninitialized variable

A variable or field declared without a type (via `var` or `final`) and without
an initializer is considered an inference failure.

```dart
void main() {
  var x;        // Inference failure
  var y = 7;    // OK
}

class C {
  final f;      // Inference failure
  final g = 7;  // OK

  C(this.f);

  static var s; // Inference failure
}
```

### Function parameter

A function parameter declared without a type (via `var`, `final` or without a
modifier), which does not inherit a type (in the case of a method), and whose
type cannot be inferred from downwards inference (in the case of a function
literal) is considered an inference failure. A function literal's parameter
types are commonly inferred when assigning the literal to a variable typed with
a typedef, or when passing the literal as an argument whose corresponding
parameter is  function-typed.

```dart
void f1(a) => print(a);           // Inference failure
void f2(var a) => print(a);       // Inference failure
void f3(final a) => print(a);     // Inference failure
void f4(int a) => print(a);       // OK
void f5<T>(T a) => print(a);      // OK
void f6([var a = 7]) => print(a); // Inference failure
void f7([int a = 7]) => print(a); // OK
void f8({var a}) => print(a);     // Inference failure
void f9({int a}) => print(a);     // OK

class C {
  C.x(var a) {}               // Inference failure
  C.y(int a) {}               // OK
  void f1(var a) => print(a); // Inference failure
  void f2(int a) => print(a);
}

class D extends C {
  @override
  void f2(a) => print(a); // OK
}

class E extends C {
  @override
  void f2(var a) => print(a); // OK
}

void fA(String cb(var a)) => print(cb(7)); // Inference failure
void fB(String cb(int x)) => print(cb(7)); // OK

// Typedef parameters cannot be specified with `var`.
typedef Callback = void Function(int); // OK

void main() {
  var f = (var a) {};      // Inference failure
  fA((a) => a * a);        // OK
  fB((a) => a * a);        // OK
  Callback g = (var a) {}; // OK
}
```

### Collection literal

An empty collection literal with no explicit type argument whose type cannot be
inferred from downwards inference is considered an inference failure.

Inference on a collection literal that might be empty at runtime, and might not
(as per collection-for and collection-if) uses the types of all possible
elements. Therefore there is never an inference failure on such a collection
literal.

```dart
void main(List<String> args) {
  var a = [];   // Inference failure
  var b = {};   // Inference failure
  final c = []; // Inference failure
  const d = []; // Inference failure

  void mapFunction(map = {}) {}             // Inference failure
  var d = args.isEmpty ? [] : args.take(1); // Inference failure
  var e = args ?? [];                       // OK; the type of the right side of
                                            // `??` is inferred from the left.
  dynamic returnsList() => [];              // Inference failure

  int len(List list) => list.length;
  List h = []; // OK; `List h` is shorthand for `List<dynamic> h`.
  len([]);     // OK; `List list` is shorthand for `List<dynamic> list`.
}
```

### Instance creation

Instantiating a generic class without explicit type argument(s), in which one
or more type arguments cannot be inferred from downwards or upwards inference
is considered an inference failure. This includes type parameters with an
explicit bound.

```dart
class C<T> {
  T t;

  C();
  C.of(this.t);
}

class D<T extends num> {}

void main() {
  var f = Future.value();          // Inference failure
  var g = Future.error("Error");   // Inference failure
  Future<void> h = Future.value(); // OK
  var i = Future<void>.value();    // OK
  var j = Future.value(7);         // OK
  var l = List();                  // Inference failure
  var c1 = C();                    // Inference failure
  var d = D();                     // Inference failure
  C<int> c2 = C();                 // OK
  C c3 = C<int>();                 // OK
  var c4 = C.of(42 as dynamic);    // OK
}

Future<void> fn() => Future.error("Error"); // OK
```

### Function call

Calling a generic function without explicit type arguments, such that one or
more type arguments cannot be inferred from downwards or upwards inference is
considered an inference failure. This includes type parameters with an explicit
bound.

```dart
T f1<T>(dynamic a) => a as T;

void main() {
  f1(7);                    // Inference failure
  var a = f1(7);            // Inference failure
  var b = [1, 2, 3].cast(); // Inference failure
}
```

### Function return types

Declaring a recursive local function, a top-level function, a method, a
typedef, a generic function type, or a function-typed function parameter
without a return type is an inference failure. The return type of non-recursive
local functions can always be inferred from downwards or upwards inference, as
it will have a body, and the return type of the body is known (even if there
are inference failures within).

```dart
f1() {                                // Inference failure
  print(1);
}
f2() => 7;                            // Inference failure

void main() {
  f3() => 7;                          // OK (non-recursive)
  f4() {                              // OK (non-recursive)
    return 7;
  }
  f5(int n) => n < 2 ? 1 : f5(n - 1); // Inference failure
}

class C {
  m1() => 7;                          // Inference failure
  static m2() => 7;                   // Inference failure
}

typedef Callback1 = Function(int);    // Inference failure
typedef Callback2(int i);             // Inference failure

void f6(callback()) {                 // Inference failure
  callback();
}
void f7(int callback(callback2())) {  // Inference failure
  callback(() => print(7));
}

Function(int) f8 = (int n) {          // Inference failure
  print(n);
};
```

## Cascading failures

The following section is non-normative.

In strict inference mode, an inference failure does not change the values of
types that are inferred. As a result, inference failures do not cascade. This
leads to results which may be surprising. Here are some common scenarios in
which there are fewer inference failures than one might expect.

*  The type of a collection literal with elements whose types feature inference
   failures does not itself feature an inference failure.

   ```dart
   var a;           // Inference failure
   var b = {a};     // OK
   var c = {a: 7};  // OK
   var d = {7: a};  // OK
   var e = {a};     // OK
   var f = {[]};    // One inference failure, on the list.
   var g = [b, c];  // OK
   var h = [...[]]; // One inference failure, on the inner list.
   ```

*  The return type of a non-recursive local function. Regardless of the body of
   the function, inference _will_ yield a type from that body.

   ```dart
   fn(var a) => a;
   ```

*  The untyped loop variable in a for loop. Regardless of the type (inferred or
   explicit) of the for loop collection, the type of the loop variable is
   always inferred.

   ```dart
   var list = [];
   list.add(1);
   list.add("Hello");
   for (var el in list) print(el);
   ```

*  The type of a field-initializing constructor parameter.

   ```dart
   class C {
     var a;     // Inference failure
     C(this.a); // OK
   }
   ```
