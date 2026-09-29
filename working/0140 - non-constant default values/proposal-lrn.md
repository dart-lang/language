# Dart - Non-constant default values

Dart optional parameter default values must be constant expressions. They are not in a constant context precisely because the language team wanted to keep the door open to having non-constant default value expressions.

Having non-constant default value expressions allows some pattern that require more complicated workarounds today. Example: A constructor which can take a list as argument, but if no list is given, it allocates a new growable list

With a non-constant default value, that would be:

```dart
class MyClass([final List<int> accumulator = <int>[]) { ... }
```

Without that, there are several different possibilities, which all differ from the desired behavior in different ways, or require significant extra code:

```dart
// Parameter is nullable.
class MyClass([List<int>? accumulator]) {
  final List<int> accumulator = accumulator ?? <int>[];  
}
```



```dart
// Constructor is factory.
class MyClass {
  final List<int> accumulator;
  factory([List<int> accumulator]) = MyClass._;
  new _(List<int>? accumulator) : accumulator = accumulator ?? <int>[];
}
```



```dart
// Requires special sentinel object which not all types allow.
class MyClass {
  static const List<int> _sentinal = _someSpecialValueImplementingListInt;
  final List<int> accumulator;
  new(List<int>? accumulator) 
      : accumulator = identical(accumulator, _sentinel) ? <int>[] : accumulator;
}
```

The problem is always that to allow omitting a value, there needs to be an intermediate constant value that represents "no value". Using `null` can leak into the API, or it can be hidden, but that requires using a `factory` constructor. Using something else requires there to _be_ something else. _For `List` it's easy to create a hidden subclass of `List<Never>` with a single constant instance. Other types may be `final`  or otherwise not subtypable._

Representing the missing value also an issue for normal methods, which have no forwarding factories. They can instead use public interfaces and private implementations where the public interface hides that the implementation parameter is nullable. That requires adding an entire extra class.

## Proposal

Allow default-value expressions to be non-constant expressions.

As non-constant expressions, they must be evaluated at a specified time, and they can refer to non-constant names in their scope.

### Static semantics

The lexical scope for a default value expression is the parameter scope for a function or non-initializing constructor, and it is the _initializer list scope_ for an initializing constructor.

It is a **compile-time error** if a default value expression refers to the name of a parameter of the same function that does not occur syntactically before it.

It is a **compile-time error** if a default value expression contains an assignment to a variable introduced by the parameter/initializer-list scope of the same function. _Could maybe be allowed, but to match instance variable initializers in primary constructors, let's not change any variable until we're past those._

It's a **compile-time error** if a default value expression of a parameter of a constant (necessarily generative) constructor is not a _potentially constant expression_. _Must be a generative constructor because a redirecting factory constructor cannot have default values and a non-redirecting factory constructor cannot be `const` (yet)._

_The existing typing rules requires the runtime type of the default value expression's value to be a subtype of the declared type of the constructor. Since the value is constant, the runtime type is available at compile-time. That's not the case for non-constant default value expressions. This instead changes to:_

* If a default value expression is a constant expression, it's a compile-time error if the runtime type of the expression's value is not a subtype of the parameter's declared type. _We can check at compile-time, so no need to wait until runtime to give the error._
* Otherwise it's a compile-time error if the static type of the default-value expression is not _assignable to_ the parameter's declared type. _(It can be a subtype, `dynamic`, or something otherwise runtime-coercible to the context (function) type.)_
* It's (still) a compile-time error if an optional parameter of a non-abstract, non-external, non-redirecting-factory-constructor function declaration (a "concrete parameter", one that is in scope for actual code) has a declared type that is not nullable and the parameter declaration has no default-value expression.

Default value expressions are considered _conditionally evaluated_ at the start of the body. Since they may or may not be evaluated, depending on the argument list, any promotions they introduce will be lost at the end of the expression.

### Runtime semantics

Default value expressions are evaluated during the _binding actuals to formals_ step. 

During that step, parameters of a declaration are processed in source order and matched to corresponding argument values, if any.

* If a parameter has an argument passed to it, the parameter processed with that value (bound to for plain parameters, other things for initializing formals, declaring parameters and super parameters) and the parameter name is bound to that value in the parameter scope (for normal parameters) and in the _initializer list scope_ (for initializing constructors).
* If a parameter is optional and has no argument passed for it, the default value expression is evaluated in the _initializer list scope_ of an initializing constructor and parameter scope for all other functions, and then the parameter is processed with the resulting value (or the invocation throws if the expression does). 
  * If the static type of the default value expression is not a subtype of the declared type of the parameter, then it must be `dynamic`, and a runtime cast to the declared type occurs as part of the evaluation. 
* If there is no default-value expression, the parameter is processed with the `null` value. _It must have a nullable type, otherwise a compile-time error would have occurred._

The binding actuals to formals step happens for different functions at different times. In general, its treated as if the default value expressions were executed at the beginning of the function body execution. That matters for generators which don't start executing the body immediately, and for `async` functions which should report errors in their `Future`.

* For a non-generator function or setter, whether sync or `async`,  binding actuals to formals happens as the first step of the invocation, just before running the body. If a default value expression throws, it's reported the same way as if the body had thrown (the synchronous function call throws synchronously, the `async` function call's future completes asynchronously with the error).
* For a synchronous generator, a  `sync*` function, binding actuals to formals happens the first time the `moveNext` method is called on an `Iterator`  provided by the  `iterator`  getter of the `Iterable` returned by the function. Each iteration has its own local variables which need to be initialized. _The binding could also happen when the `iterator` getter is read, but that provides authors a way to have side-effects that happen on reading `.iterator`, which can be earlier than the actual start of the body._
* For an asynchronous generator, an  `async*` function, binding actuals to formals happens when the body starts running, which happens as an asynchronous event after calling the `listen` method of a `Stream` returned by the function. _If a default value expression throws, it will be reported the same way as if the function body throws, as an error and done event on the stream subscription._
* In an `async` or `async*` function, default value expressions _cannot_ be asynchronous and cannot use `await` expressions.
  * _It could probably be allowed. Should it? It's no worse than having the first statement of the body be `arg ??= await _createDefault();`._
* A non-redirecting factory constructor behaves the same way as any synchronous non-generator function.
* A redirecting factory constructor cannot have default value expressions.
* A redirecting generative constructor binds actuals to formals just before evaluating the argument expressions of its redirection clause.
* An initializing constructor binds actuals to formals _before_ executing instance variable initializers, which is again before executing the initializer list. _This is required for primary constructors to have parameter values that instance variable initializers can refer to._

#### Dynamic invocations

The binding actuals to formals step of a dynamic invocation needs to be specified in more detail than was previously needed. When user code can run during the step, and the argument list can turn out to be invalid for the parameter list it's applied to, then it's detectable if any default value expressions run before a type error is thrown.

To be consistent with default value expressions happening as the first thing _after_ calling the function, and dynamic invocations not being able to call the function with invalid arguments, the parameter list must be checked completely before starting to call the function.

A _dynamic invocation_ of a function with parameter list _P_ applied to an argument list _A_ starts by checking _shape and type validity_:

* It's a runtime error if the argument list _A_ does not provide an argument for every _required_ parameter of _P_.
* It's a runtime error if the argument list _A_ provides an argument that does not correspond to any parameter of _P_.
* It's a runtime error if any argument's value has a runtime type that is not a subtype of the corresponding parameter's declared type. 
  * This includes covariant parameters, whose declared type is not necessarily the same as the parameter type of the runtime type of the function.
  * _If `foo` is a tear-off of a `Iterable<int> foo([covariant int x = "not at int" as dynamic]) sync* {…}` function with a static type of `dynamic` or `Function`, then `var iterable = foo("not an int");` will throw when invoked because `"not an int"` is not an `int`, but `foo()` will be a valid invocation that will throw when `.iterator.moveNext()` is called on the returned `Iterable`._
  * _Alternative is to delay the type-check of covariant parameters until the binding actuals to formals step, when the body starts running. That'll be a change from the current behavior which throws eagerly._
* Otherwise the function is invoked with the argument list _A_ as normal, known that _A_ is a valid type-sound argument list for that function.

This order is required for tear-offs of generators to work correctly. No actual binding of actuals to formals happens until the returned iterable/stream is started, but an invalid argument needs to be reported before that iterable/stream can be returned (to match current behavior).

_The likely reason for the current `covariant` behavior is that the function is treated as having the declared parameters, which are bound to the arguments when the function is called, and those parameters are cloned into new variables for each read of `iterator`. The binding actuals to formals step can be performed once, and the parameter variables cloned when needed. That implementation is no longer possible if each iteration needs to run non-constant default value expressions independently._

### Recognizing if argument is passed

If default values can have side effects, then a function can deduce whether the default value was computed or the same value was passed as an argument. It's not pretty, because it can't use local variables:

```dart
class C {
  static bool _fooXPassed = false;
  bool _wasFooXPassed {
    var result = _fooXPassed;
    _fooXPassed = false;
    return result;
  }
  void foo([int x = (_fooXPassed = true ? 0 : 0)]) {
    if (_wasFooXPassed) {
      print("No argument, default value: $x");
    } else {
      print("Argument: $x");
    }
  }
}
void main() {
  C().foo(0); // Argument: 0
  C().foo(); // No argument, default value: 0
}
```

There is currently nothing in the language that allows making that distinction, other than using a default value that is not available to callers. That was one of the original workarounds, and not all types allow for such a value to exist. For example  `int` allows _all_ values can be created by a caller.

Since the functionality is available, just not convenient, we may want to consider adding the ability to directly query whether an argument was passed, likely as a separate or later feature (fx [#3680][])

[#3680]: https://github.com/dart-lang/language/issues/3680	"Late parameters, late-init-query operator, parameter element"

### Copying default values

The specification has places where it says that a synthetic function copies the default value of another function ("has the same default values as …" or similar):

* Mixin application forwarding constructors
* `noSuchMethod` forwarders.
* Super parameters.

The last two of these already have problems because there may be no default value to copy, or it may be of a type that isn't valid for the actual parameter ([#3331][]). Mixin application forwarding constructors have none of those issues, their target is a concrete declaration which has a default value of a valid type, but implementations still need to refer to those constant values, even if they're not directly accessible from the library of the mixin application.

[#3331]: https://github.com/dart-lang/language/issues/3331 "Don't invent a default value when no well-defined value is available"

Instead of trying to patch these issues, and likely new ones introduced by non-constant default values, we instead properly introduce the concept of _forwarding an argument_ and _forwarding an argument list_:

* If one function _forwards an argument_ (from its argument list) into an argument list for another invocation, then that argument occurs either at a _corresponding_ position (if positional) or with the same name (if named) in the other argument list _if there is an argument in the forwarding declaration's argument list_. If there is no such argument for an optional parameter, then there is also no argument in the forwarded-to argument list..
  * It may not be the same positional index. A `super` parameter can forward a _subset_ of the positional parameters of an initializing constructor to a superclass constructor, _if_ the parameter had an argument in the original . _Using `super`-parameters guarantees that those super-parameters are the only positional arguments to the super-constructor, so they will occur in the same order, which also ensures that there is no positional argument forwarded after an argument which was not there._
* If a function _forwards its argument list_ to another invocation, it forwards all its arguments. _No function can be called with more arguments than it has parameters, so that corresponds to forwarding the arguments for all parameters._

With that:

* If a `super`-parameter adds an argument in the superclass constructor invocation at the same name (if named) or at index _n_ (if positional with _n_ - 1 earlier positional `super` parameters, where index is 1-based). 

  * If the `super`-parameter has no default value expression, it forwards its argument to that position (meaning no argument is passed if no argument is received).
    * If that `super`-parameter is optional and not nullable, it's not an error if it has no default value expression. However, it is then a compile-time error to refer to the initializer-list scope variable introduced by the parameter. It counts only as _potentially assigned_.
  * If the `super`-parameter has a default value expression and no argument is provided, the default value expression is evaluated, and that value is passed as the argument and bound to the initializer-list scope variable.
    * It's a compile-time error to have a super-parameter with a default value expression after an optional super-parameter without a default-value expression. _(Because that would imply passing an argument value after and argument with no value, which is not currently supported._)
  * If the `super`-parameter has a default value and an argument is passed, then that value is passed as  argument and bound to the initializer-list scope variable.

  That is, _you can omit the default values of named and/or trailing positional super-parameters and have the actual argument, or lack of argument, forwarded to the superconstructor._

* A mixin application class forwarding constructor has the same _signature_ as the superclass constructor with the same name, and it _forwards its argument list_ to the superclass constructor in its super-call. _As if every parameter was a super-parameter with no default value._

* A `noSuchMethod`-forwarder has the same signature as the member signature it implements. It creates an `Invocation` object from the actual parameters.
  * _Alternative: Use `null` as value for any optional argument that wasn't passed, ensuring that all parameters are represented in the `Invocation`, whether `null` is a valid value for the parameter or not. (But do not try to introduce any default values, which isn't possible anyway since `noSuchMethod` forwarders are based on signatures that do not contain default value expressions.)_

* A forwarding factory constructor forwards its argument list to the target constructor (same as today, and evidence that the runtimes can handle doing so.)
  * _We could allow a parameter to have a default value expression, in which case it'll be evaluated if there is no argument, and its value passed to the target constructor. However, then all prior optional positional parameters must have default value expressions too._

#### Examples of default value copying issues

```dart
abstract class C {
  void foo([int x]);
}
class D implements C {
  void noSuchMethod(Invocation i) {
    print(i.positionalArguments.first);
  }
}
void main() {
  D().foo(); // Throws in some compilers, prints `null` in others.
}
```

```dart
class C {
  new([num? x = double.nan]) {
    print(x);
  }
}
class D extends C {
  new v1([double super.x]); 
  new v2([int? super.x]); 
  // new v3([int super.x]); // Error, `null` is not valid default value
}
void main() {
    D.v1(); // Prints `NaN`
    D.v2(); // Prints `null`
}
```

```dart
class C {
  factory ([int x]) = C._;
  new _([num x = double.nan]) {
    print(x);
  }
}
void main() {
  C(); // Correctly prints `NaN`
  var f = C.new;
  f(); // Correctly prints `NaN`
}
```



