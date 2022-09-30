# Dart Super Parameters

Author: lrn@google.com<br>Version: 1.3

## Background and Motivation

This document specifies a language feature which allows concise propagation of parameters of a non-redirecting generative constructor to the superclass constructor it invokes.

Currently a “forwarding constructor”, one which does nothing except forward parameters to its superclass constructor (like the constructors introduced by mixin application), has to repeat the names of parameters when passing them to the superclass constructor. This becomes extra egregious when the parameter is named.

Example:

```dart
class C extends D {
  C(int someMeaningfulName, {int? anotherName})
      : super(someMeaningfulName, anotherName: anotherName);
}
```

This example repeats `someMeaningfulName` once and `anotherName` twice.

We’ll introduce a short-hand syntax, similar to the `this.name` initializing formal parameter, which implicitly forwards the parameter directly to the superclass constructor.

## Feature specification

### Grammar

Like we currently allow <code>this.*id*</code> as an initializing formal in a non-redirecting generative constructor, with an implicit type derived from the *id* variable declaration, and introducing a final variable in the initializer list scope, we will also allow <code>super.*id*</code>.

We extend the grammar to:

```ebnf
<normalFormalParameterNoMetadata> ::= <functionFormalParameter>
  \alt <fieldFormalParameter>
  \alt <simpleFormalParameter>
  \alt <superFormalParameter>         ## new

<fieldFormalParameter> ::= \gnewline{}
  <finalConstVarOrType>? \THIS{} `.' <identifier> (<formalParameterPart> `?'?)?

<superFormalParameter> ::= \gnewline{}                                            ## new
  <finalConstVarOrType>? \SUPER{} `.' <identifier> (<formalParameterPart> `?'?)?  ## new
```

_That is, exactly the same grammar as initializing formals, but with `super` instead of `this`._

## Semantics

It’s a **compile-time error** if a super-parameter declaration occurs in any declaration other than a non-redirecting generative constructor of a class declaration.

_All non-redirecting generative constructors of a class declaration have a super-constructor invocation at the end of their initializer list. If none is written (or there is even no initializer list), the default is an invocation of `super()`, targeting the unnamed superclass constructor. It’s a compiler-time error if the superclass does not have the specified constructor, or it’s not a generative constructor. The new enhanced `enum` declarations, on the other hand, do have non-redirecting generative constructors, but those cannot not have any super-invocations, and they also have no known superclass constructor to forward parameters to._

It’s a **compile-time error** if `var` occurs as the first token of a `<superFormalParameter>` production. (It’s generally a compile-time error if `const` or `late` occurs in a parameter declaration, this also applies to super-parameters).

It’s also a **compile-time** error if a constructor has a positional super-parameter and the super-constructor invocation at the end of its initializer list has a positional argument.

We define the *name of a parameter declaration* as the identifier naming it for normal parameters, and the identifier after `this.` or `super.` for initializing formals and super parameters. _(It’s the obvious definition, just stating it.)_

It’s a **compile-time error** if a constructor _(or any function)_ has two parameter declarations with the same name.

It’s a **compile-time error** if a constructor has a named super-parameter with name *n* and a super-constructor invocation with a named argument with name *n*.

Let *C* be a non-redirecting generative constructor with, implicit or explicit, super-constructor invocation *s* at the end of its initializer list. Let *D* be the superclass constructor targeted by *s* (which must exist).

We define the _associated super-constructor parameter_ for each super-parameter *p* of *C* as follows:

- If *p* is a positional parameter, let *j* be the number of positional super-parameters of *C* up to and including *p* in source order. The associated super-constructor parameter of *p* is the *j*th positional parameter of *D* (1-based), if *D* has that many positional parameters.
- If *p* is a named parameter with name *n*, the associated super-constructor parameter is the named parameter of *D* with name *n*, if *D* has a named parameter with that name.

It’s a **compile-time error** if a non-redirecting generative constructor has a super-parameter with no associated super-constructor parameter.

_All we need for this definition is the ability to resolve the superclass constructor and see its argument structure._

#### Type inference

##### Parameter types and default values

We infer the *type* of a parameter declaration, *p*, of a non-redirecting generative constructor, *C*,  as:

- If the *p* has a type in its `<finalConstVarOrType>`, that remains the type of the parameter.
- Otherwise, if the parameter is an initializing formal (`this.name`) the inferred type of the parameter is the declared/inferred type of the instance variable named `name` of the surrounding class (which must exist, otherwise it’s a compile-time error.)
- Otherwise, if the parameter is a super parameter (`super.name`) the inferred type of the parameter is the associated super-constructor parameter (which must exist, otherwise we’d have a compile-time error).
- Otherwise the inferred type of the parameter is `dynamic`. _(Is it `Object?` now?)_

We also copy the default value of the associated super-constructor if applicable:

- If *p* is optional, does not declare a default value, the associated super-constructor parameter is also optional and has a default value *d*, and *d* is a subtype of the (declared or inferred above) type of *p*, then *p* gets the default value *d.*
- It’s then a **compile-time error** if *p* is optional, its type is potentially non-nullable and it still does not have a default value.

It’s a **compile-time error** if a super-parameter has a type which is not a subtype of the type of its associated super-constructor parameter.

##### Introduced names in initializer list

Each super-parameter, *p<sub>n</sub>* with name *n* and (inferred or declared) type *T<sub>n</sub>*, introduces a final binding with the same name *n* and static type *T<sub>n</sub>* into the initializer list scope (just like initializing formals).

##### Super-constructor invocation

When inferring the super-constructor invocation, *s*, targeting the super constructor *D*, we include the implicit super-parameters from the constructor parameter list:

The super-constructor invocation *s* infers a super-constructor invocation *s’* such that

- The same constructor is targeted by *s’* as by *s* (same leading `super` or <code>super.*id*</code> constructor reference).

- If *s* has positional arguments, *a*<sub>1</sub>..*a<sub>k</sub>*, and *a<sub>i</sub>* infers *m<sub>i</sub>* with a context type *T<sub>i</sub>*, which is the type of the *i*th positional parameter of the targeted super-constructor, then *s’* has positional arguments *m*<sub>1</sub>..*m<sub>k</sub>*.

- For each super parameter *p* in *C*, in source order, where *p* has parameter name *n*, (inferred or declared) type *T*, associated super-constructor parameter *q*, and where *S* is the type of the parameter *q*:

  - Let <Code>*x*<sub>n</sub></code> be an identifier for then name *n*. As an expression, <code>*x*<sub>n</sub></code> denotes the final variable introduced into the initializer list scope by *p*.
  - Then *s’* has an argument following the previously mentioned arguments:
    - <code>x<sub>*n*</sub></code> if *p* is positional, or
    - <Code>x<sub>n</sub>: *x*<sub>*n*</sub></code> if *q* is named.

  _Currently named parameters always follow positional parameters, so by keeping the source order, named arguments also follow positional arguments. There can’t be both positional arguments from *s* and from *C*._

- For each named argument <code>*x*: *e*</code> of *s*, in source order:

  - if *e* infers *m* with context type *S*, where *S* is the type of the parameter named *x* of the targeted super-constructor,
  - then <code>*x*: *m*</code> is a named argument of *s’* following the previously mentioned arguments.

_Not using inference on the implicit arguments means that we won’t apply implicit coercions, like downcast from `dynamic` or `.call`-tear-off if assignment from the declared type of a super parameter to a super-constructor parameter’s type requires it. For example: `C(dynamic super.x) : super();` will not be inferred to be `C(dynamic super.x) : super(x as int);`, it’s just a compile-time error that `dynamic` is not a subtype of `int`, just as it is for redirecting factory constructors.

#### Run-time Invocation

When invoking a non-redirecting generative constructor *C*, parameter binding occurs as follows:

- As usual for non-super-parameters.
- Binding a value *v* to a super-parameter *p* with name *n*:
  - Binds the final variable named *n* to *v* in the run-time initializer list scope.

## Summary

Effectively, each super parameters, <code>super.*p*</code>:

- Introduces a final variable <code>*p*</code> with the parameter’s name, just like <code>this.*p*</code> does, only in scope in the initializer list.
- Implicitly adds that variable as an implicit argument to the super-constructor invocation.
- Implicitly infers its type and default value, if not specified, if applicable, from the associated super-constructor parameter that they are forwarded to.
- Cannot be positional if the super-constructor invocation already has positional arguments.
- But can always be named.

## Examples

```dart
class B {
  final int foo;
  final int bar;
  final int baz;
  B(this.foo, this.bar, [this.baz = 4]);
}
class C extends B {
  C(super.foo, super.bar, [super.baz = 4]);
  // Same as:
  // C(super.foo, super.bar, [super.baz = 4]) : super(foo, bar, baz);
}
```

This shows that you still can’t just forward *every* parameter, you have to write each parameter out. You avoid having to write it *again* in the super-invocation, but have to write and look at the `super.` instead.

```dart
class B {
  final int? foo;
  final int? bar;
  final int? baz;
  B.named({this.foo, this.bar, this.baz});
}
class C extends B {
  C(int bar, {super.foo}) : super.named(bar: bar, baz: 42);
  // Same as
  // C(int bar, {int? foo}) : super.named(foo: foo, bar: bar, baz: 42);
}
```

## Revisions

1.0: Initial version

1.1: Don’t allow both positional super parameters and explicit positional arguments. Inherit default value.

1.2: Don’t do inference (and implicit coercion) on the implicit arguments.

1.3: Make it explicit that you can't use super parameters in the new enum declarations.
