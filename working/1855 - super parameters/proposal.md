# Dart Super-Initializer Parameters

Author: lrn@google.com<br>Version: 1.0

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

It’s a compile-time error if a super-parameter in any declaration other than a non-redirecting generative constructor.

It’s a compile-time error if `var` occurs as the first token of a `<superFormalParameter>` production. (It’s generally a compile-time error if `const` or `late` occurs in a parameter declaration, this also applies to super-parameters).

We then treat each positional super-parameter as if it was an implicit positional argument to the super-constructor invocation at the end of the initializer list (which is `super()` if not explicitly specified), appended to any existing positional arguments in source order, and each named super-parameter as if it was an implicit named argument to the super-constructor invocation with the same name and value. If this would be invalid, the constructor is invalid.
Further, the super-parameter also introduces a final variable with the same name and value into the initializer-list scope, just like initializing formals do.

#### More formally

##### Definitions

We define the *name* of a parameter declaration as the identifier naming it for normal parameters, and the identifier after `this.` or `super.` for initializing formals and super parameters. _The obvious definition, just stating it._ It’s a compile-time error if a function has two parameter declarations with the same name.

Let *C* be a non-redirecting generative constructor with super-constructor invocation *s* at the end of its initializer list (if none is written, it’s implicitly `super()`). Let *D* be the superclass constructor targeted by *s*.

We define the _associated super-constructor parameter_ for each super-parameter *p* of *C* as follows:

- If *p* is a positional parameter, let *k* be the number of positional arguments of *s* and let *j* be the number of positional super-parameters of *C* up to and including *p* in source order. The associated super-constructor parameter of *p* is the *k*+*j*‘th positional parameter of *D*, if *D* has that many positional parameters
- If *p* is a named parameter with name *n*, the associated super-constructor parameter is the named parameter of *D* with name *n*, if *D* has a named parameter with that name.

It’s a **compile-time error** if a non-redirecting generative constructor has a super-parameter with no associated super-constructor parameter.

_All we need to for this definition is the ability to resolve the superclass constructor and see its argument structure._

##### Type inference

We define the *type* of a parameter declaration, *p*, of a non-redirecting generative constructor, *C*,  as:

- If the parameter has a type in its `<finalConstVarOrType>`, that’s the type of the parameter.
- If the parameter is an initializing formal (`this.name`) the type of the parameter is the declared/inferred type of the instance variable named `name` of the surrounding class (which must exist, otherwise it’s a compile-time error.)
- If the parameter is a positional super parameter (`super.name`), the type of the parameter is the associated super-constructor parameter (which must exist, otherwise it’s a compile-time error).

Each super-parameter introduces a final variable with the same name and type into the initializer list scope (just like initializing formals).

When inferring the super-constructor invocation, *s*, targeting the super constructor *D*, we include the implicit super-parameters from the constructor parameter list:

- Let *k* be the number of positional arguments of *s*.
- Let *j* be the number of positional super-parameters of *C*.
- It’s a compile-time error if *D* has fewer than *k*+*j*  positional parameters.  _(Redundant with “all super parameters must have associated super-constructor parameter”.)_
- It’s a compile-time error if *D* has more than *k*+*j* *required* positional parameters.
- For 0 &le; *i* < *k*, it’s a compile-time error if the static type of the *k*’th positional argument of *s* is not assignable to the *k*‘th positional parameter of *D*. _(We use *assignable* here, which means that we do allow implicit coercions like downcast or `.call` method tear-off)_.
- For 1 &le; i &le; j, it’s a compile-time error if the type of the (1-based) *i*‘th positional super-parameter of *C* is not assignable to the *k*+*i*‘th positional parameter of *D*.
- It’s a compile-time error if *D* has a required named parameter named *n*, *s* does not have a named argument named *n* and *C* does not have a named super-parameter named *n*.
- It’s a compile-time error *s* has a named argument *a* named *n* and *D* does not have a named parameter named *n* *or* *D* does have a named parameter *q* named *n* and the type of *a* is not assignable to the type of *q*.
- It’s a compile-time error if *C* has a named super-parameter *p* with name *n* and the type of *p* is not assignable to the type if its corresponding super-constructor parameter of *D*. (We know it exists.)

##### Invocation

When invoking a non-redirecting generative constructor *C*, parameter binding occurs as follows:

- As usual for non-super-parameters.
- Binding a value *v* to a super-parameter *p* with name *n*:
  - Binds the final variable *n* to *v* in the run-time initializer list scope.
  - Binds a fresh variable <code>_$*n*</code> to *v* in the run-time initializer list scope as well.

When reaching the super-constructor invocation, *s*, targeting the super-constructor *D*, the argument list passed to *D* is:

- The positional arguments of *s*,  
- followed by the values of each of the positional super-parameters of *C* as positional arguments, in source order (can be referenced without risk of being shadowed as <code>_$*n*</code>),
- followed by the named arguments of *s*,
- followed by named arguments corresponding to each named super-parameter of *C* with the same name as the parameter and the value of that parameter (a super-parameter named *n* has the associated argument <Code>*n*: _$*n*</code>).

##### Desugaring

This was specified without trying to desugar into existing valid Dart code.

We *can* desugar the desired behavior into existing Dart code, but that requires some amount of rewriting in the constructor body to enforce the “initializer-only” scope of variables introduced by initializing formals and super parameters. Example:

```dart
C(super.x, this.y, {required super.z}) : super.foo() {
  something(x, y, z);
}
```

*could* be (re)written as:

```dart
C(final TypeOfX x, final TypeOfY y, {final required TypeOfZ z}) 
    : this.y = y, super(x, z: z) {
  something(this.x, this,y, this.z);
}
```

The change of `x, y, z` to `this.x, this.y, this.z` is necessary to ensure the body code still references the instance variables, not the newly-introduced “normal” parameters which are visible in the body unlike the variables introduced by initializing formals and, now, super-parameters.

We so far prefer to avoid doing that kind of non-local rewriting, which means that we will need to treat this as a feature by itself, not something that can easily be “lowered” to existing code.

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
}
```

This shows that you still can’t just forward *every* parameter, you have to write each parameter out. You avoid having to write it *again* in the super-invocation, but have to write and look at the `super.` instead.

## Revisions

1.0: Initial version
