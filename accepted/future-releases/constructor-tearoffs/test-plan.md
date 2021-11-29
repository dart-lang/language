# Dart Constructor Tear-Offs Test Plan

The Dart constructor tear-off feature contains multiple independent language changes. Each should be tested, as should their combination with each other and with other relevant language features.

The features can be summarized as:

* Named constructor tear-offs
  * Expressions of the for <code>*C*.*name*</code>. or <code>*C*\<*typeArgs*>.*name*</code>, with type arguments potentially being inferred, evaluate to functions.
  * Preserves identity as specified.
* Unnamed constructor syntax alternative
  * Everywhere you can currently reference or declare an unnamed constructor, you can also refer to it or declare it as <code>*C*.new</code>.
  * The unnamed and `new`-named constructors are two ways to refer to the *same* thing. (Can't declare both).
* Unnamed constructor tear-offs
  * Expressions of the for <code>*C*.new</code>. or <code>*C*\<*typeArgs*>.new</code>, with type arguments potentially being inferred, evaluate to functions.
  * Preserves identity as specified.
* Explicit instantiated function tear-off
  * Expressions of the form <code>*f*\<*typeArgs*></code>, not followed by an argument list and where *f* denotes a generic function declaration or generic instance method, now does instantiated tear-off.
* Explicit type literal instantiation
  * Expressions of the form <code>*T*\<*typeArgs*></code>, not followed by an argument list and where *T* denotes a type declaration (class, mixin or type alias), now evaluates to a `Type` object for the instantiated type.

Each feature should be tested, both for correct and incorrect usage. Further, we should check that any new syntax is not allowed in places where it isn't defined.

## Named constructor tear-off

### Correct usage

The possible constructors tear-offs

* Check that constructors of non-generic classes can be torn off (`C.foo`).
* Check that constructors of instantiated generic classes can be torn off (`G<int>.foo`).
* Check that constructors of uninstantiated generic classes can be torn off, and that type inference infers the correct type arguments.
   * Instantiate to bounds if not context type, or not relevant context type (`var x = G.foo`).
   * Based on context type if relevant (`G<int> Function() f = G.foo1`).
   * Check that the inferred cannot be super-bounded or malbounded.
* Check that the resulting function has the correct static type and runtime type.

The possible constructor types (all combinations except "const factory non-redirecting" exist):

* Constant or not
* Factory or not
* Redirecting or not

The possible sources of tear-offs:

* From a class declaring the constructor.
* From a mixin-application which introduces a forwarding constructor.
* Any of those through an alias which is:
  * Not generic.
  * A proper rename (static type may not match runtime type, static type is based on alias type argument bounds, runtime type is based on class type argument bounds).
  * Not a proper rename
    * Not same number of type arguments (fewer or more)
    * Not same order of type arguments

#### Covered by tests

* [tear_off_test][]
* [aliased_constructor_tear_off_test][]

### Incorrect usage

* Attempting to tear-off non-constructors using new instantiated <Code>*C*\<*typeArgs*>.*name*</code> syntax.
  * (If <code>*name*</code> doesn't refer to a constructor, must then treat <code>*C*\<*typeArgs*></code> as type literal, and therefore only allow members of `Type`, which are also members of `Object` and therefore never valid as constructor names).
* Incorrect number or type of explicit type arguments.
* Unsatisfiable type parameters for inferred type arguments.

#### Covered by tests

* [tear_off_error_test][]

## Unnamed constructor alternative syntax

### Correct usage

* The `.new` name can be used anywhere the plain constructor name can.
  * Declarations
  * Invocations
  * Generative constructor super-constructor invocation in initializer list
  * Redirecting generative constructor target
  * Redirecting factory constructor target
  * (Dartdoc?)
* The two naming conventions can be used interchangeably, both refer to the same constructor

#### Covered by tests

* [unnamed_new_test][]

## Incorrect usage

* Can't use `.new` or `new` to declare non-constructors, nor to call methods.
* The `new` name is not in *scope* (like constructor names generally aren't).

#### Covered by tests

* [unnamed_new_error_test][]

## Unnamed/`new`-named constructor tearoffs

* Same tests as for named constructor tearoffs.

#### Covered by tests

* [tear_off_test][]
* [aliased_constructor_tear_off_test][]
* [tear_off_error_test][]

## Explicit instantiated function tear-off

### Correct usage

* Works for any static, top-level, local function declaration.
  * Also static functions accessed through a type alias.
  * Through import prefix.
* Works for instance methods other than `call` methods of `Function`-typed objects.
* Result has expected static and runtime type.

#### Covered by tests

* [explicit_instantiated_tearoff_test][]

### Incorrect usage

* Does not work for function values.
  * Including torn off methods and constructors.
* Includes function-typed getters.
* Does not work for `call` methods of function values.
* Does not work for *constructors* (`class C<T> { C.name();}` does not allow `C.name<int>`).
* Non-constant instantiation in constant context.
* Type bounds must not be violated.

#### Covered by tests

* ?

## Explicit instantiated type literal

### Correct usage

* Can instantiate any generic type (class, mixin, type alias).
* Allows super-bounded types.
* Result is `Type` object.
* `Type` objects for same generic type are equal if created using equal type arguments.
* Identical if passed equal and constant type arguments.
* Through type aliases, equal/identical if expansion is equal.

#### Covered by tests

* [explicit_instantiated_type_literal_test][]
* [aliased_type_literal_instantiation_test][]

### Incorrect usage

* Non-constant instantiation in constant context.
  * Even if type parameter of type alias is not used in result.

* Cannot call static members on instantiated type literals. (That's a constructor reference, if anything).
  * <code>*C*\<*typeArgs*>.anything</code> does not create a type literal.
  * <code>*C*\<*typeArgs*>..anything</code> *probably does* (<code>*C*..toString()</code> works today, invokes `toString` of `Type` object).
  * <code>*C*\<*typeArgs*>?.anything</code> also works (possibly with a warning about the `?` being unnecessary).
  * Does not allow malbounded types.

#### Covered by tests

* [explicit_instantiated_type_literal_error_test][]



[tear_off_test]: http://github.com/dart-lang/sdk/blob/master/tests/language/constructor/tear_off_test.dart
[unnamed_new_error_test]: http://github.com/dart-lang/sdk/blob/master/tests/language/constructor/unnamed_new_error_test.dart
[unnamed_new_test]: (http://github.com/dart-lang/sdk/blob/master/tests/language/constructor/unnamed_new_test.dart
[explicit_instantiated_tearoff_test]: http://github.com/dart-lang/sdk/blob/master/tests/language/generic_methods/explicit_instantiated_tearoff_test.dart
[explicit_instantiated_type_literal_error_test]: http://github.com/dart-lang/sdk/blob/master/tests/language/type_object/explicit_instantiated_type_literal_error_test.dart
[explicit_instantiated_type_literal_test]: http://github.com/dart-lang/sdk/blob/master/tests/language/type_object/explicit_instantiated_type_literal_test.dart
[aliased_constructor_tear_off_test]: http://github.com/dart-lang/sdk/blob/master/tests/language/typedef/aliased_constructor_tear_off_test.dart
[aliased_type_literal_instantiation_test]: http://github.com/dart-lang/sdk/blob/master/tests/language/typedef/aliased_type_literal_instantiation_test.dart
