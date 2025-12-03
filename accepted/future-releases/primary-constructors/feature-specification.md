# Primary Constructors

Author: Erik Ernst

Status: Accepted

Version: 1.13

Experiment flag: declaring-constructors

This document specifies _primary constructors_. This is a feature that allows
one constructor and a set of instance variables to be specified in a concise
form in the header of the declaration of a class or a similar entity. If the
primary constructor also needs an initializer list or body, those can be
specified inside the class body.

One variant of this feature has been proposed in the [struct proposal][],
several other proposals have appeared elsewhere, and prior art exists in
languages like [Kotlin][kotlin primary constructors] and Scala (with
specification [here][scala primary constructors] and some examples
[here][scala primary constructor examples]). Many discussions about the
feature have taken place in github issues marked with the
[primary-constructors label][].

[struct proposal]: https://github.com/dart-lang/language/blob/master/working/extension_structs/overview.md
[kotlin primary constructors]: https://kotlinlang.org/docs/classes.html#constructors
[scala primary constructors]: https://www.scala-lang.org/files/archive/spec/2.11/05-classes-and-objects.html#constructor-definitions
[scala primary constructor examples]: https://www.geeksforgeeks.org/scala-primary-constructor/
[primary-constructors label]: https://github.com/dart-lang/language/issues?q=is%3Aissue+is%3Aopen+primary+constructor+label%3Aprimary-constructors
[Bob proposed]: https://github.com/dart-lang/language/blob/main/working/declaring-constructors/feature-specification.md

## Introduction

Primary constructors is a conciseness feature. It does not provide any new
semantics at all. It just allows us to express something which is already
possible in Dart, using a less verbose notation. Consider this sample class
with two fields and a constructor:

```dart
// Current syntax.
class Point {
  int x;
  int y;
  Point(this.x, this.y);
}
```

A primary constructor allows us to define the same class much more concisely:

```dart
// A declaration with the same meaning, using a primary constructor.
class Point(var int x, var int y);
```

A class that has a primary constructor cannot have any other
non-redirecting generative constructors. This ensures that the primary
constructor is executed on every newly created instance of this class,
which is necessary for reasons that are discussed later.

In particular, every other generative constructor in a declaration that has
a primary constructor must be redirecting, and it must invoke the primary
constructor, directly or indirectly. This can be seen as a motivation for
the word _primary_ because it makes all other generative constructors
secondary in the sense that they depend on the primary one.

In the examples below we show the current syntax directly followed by a
declaration using a primary constructor. The meaning of the two (or more)
class declarations with the same name is always the same. Of course, we
would have a name clash if we actually put those two declarations into the
same library, so we should read the examples as "you can write this _or_
you can write that". So the example above would be shown as follows:

```dart
// Current syntax.
class Point {
  int x;
  int y;
  Point(this.x, this.y);
}

// Using a primary constructor.
class Point(var int x, var int y);
```

These examples will serve as an illustration of the proposed syntax, but
they will also illustrate the semantics of the primary constructor
declarations, because those declarations work exactly the same as the
declarations using the current syntax.

As part of this feature, an empty body of a class, mixin class, or
extension type (that is, `{}`), can be replaced by `;`.

The basic idea with a primary constructor is that a parameter list that
occurs just after the class name specifies both a constructor declaration
and a declaration of one instance variable for each formal parameter in
said parameter list that has the _declaring_ modifier `var` or `final`.

With this feature, all other declarations of formal parameters as `final`
will be a compile-time error. This ensures that `final int x` is
unambiguously a declaring parameter. Developers who wish to maintain a
style whereby formal parameters are never modified will have a
[lint][parameter_assignments] to flag all such mutations.

[parameter_assignments]: https://dart.dev/tools/linter-rules/parameter_assignments

Similarly, with this feature a regular (non-declaring) formal parameter can
not use the syntax `var name`, it must have a type (`T name`) or the type
must be omitted (`name`).

A primary constructor can have a body and/or an initializer list.
These elements are placed in the class body in a declaration that provides
"the rest" of the constructor declaration which is given in the header.

The parameter list of a primary constructor uses a slightly different
grammar than other functions. The difference is that it can include
declaring formal parameters. They can be recognized unambiguously because
they have the modifier `var` or `final`.

There is no way to indicate that the implicitly induced instance variable
declarations should have the modifiers `late` or `external`. This omission
is not seen as a problem in this proposal: They can be declared using the
same syntax as today, and initialization, if any, can be done in a
constructor body. Note that it does not make sense to declare an instance
variable as `late` if it is always initialized in the very first phase of
the constructor execution.

```dart
// Current syntax.
class ModifierClass {
  late int x;
  external double d;
  ModifierClass(this.x); // Can initialize `x`, but it preempts `late`.
}

// Using a primary constructor.
class ModifierClass(this.x) {
  late int x;
  external double d;
}
```

Super parameters can be declared in the same way as in a constructor today:

```dart
// Current syntax.
class A {
  final int a;
  A(this.a);
}

class B extends A {
  B(super.a);
}

// Using a primary constructor.
class A(final int a);
class B(super.a) extends A;
```

Next, the constructor can be named, and it can be constant:

```dart
// Current syntax.
class Point {
  final int x;
  final int y;
  const Point._(this.x, this.y);
}

// Using a primary constructor.
class const Point._(final int x, final int y);
```

Note that the class header contains syntax that resembles the constructor
declaration, which may be helpful when reading the code.

With the primary constructor, the modifier `const` could have been
placed on the class (`const class`) rather than on the class name. This
feature puts it on the class name because the notion of a "constant class"
conflicts with with actual semantics: It is the constructor which is
constant because it is able to be invoked during constant expression
evaluation; it can also be invoked at run time, and there could be other
(non-constant) constructors. This means that it is at least potentially
confusing to say that it is a "constant class", but it is consistent with
the rest of the language to say that this particular primary constructor is
a "constant constructor". Hence `class const Name` rather than `const class
Name`.

The modifier `final` on a parameter in a primary constructor specifies
that the instance variable declaration which is induced by this declaring
constructor parameter is `final`.

In the case where the declaration is an `extension type`, the modifier
`final` on the representation variable can be specified or omitted. It is
an error to specify the modifier `var` on the representation variable.

An extension type declaration is specified to use a primary constructor (it
is not supported to declare the representation variable using a normal
instance variable declaration):

```dart
// Using a primary constructor.
extension type const E.name(int x);
```

Optional parameters can be declared as usual in a primary constructor,
with default values that must be constant as usual:

```dart
// Current syntax.
class Point {
  int x;
  int y;
  Point(this.x, [this.y = 0]);
}

// Using a primary constructor.
class Point(var int x, [var int y = 0]);
```

We can omit the type of an optional parameter with a default value,
in which case the type is inferred from the default value:

```dart
// Infer the declared type from the default value.
class Point(var int x, [var y = 0]);
```

Similarly for named parameters, required or not:

```dart
// Current syntax.
class Point {
  int x;
  int y;
  Point(this.x, {required this.y});
}

// Using a primary constructor.
class Point(var int x, {required var int y});
```

The class header can have additional elements, just like class headers
where there is no primary constructor:

```dart
// Current syntax.
class D<TypeVariable extends Bound>
    extends A with M implements B, C {
  final int x;
  final int y;
  const D.named(this.x, [this.y = 0]);
}

// Using a primary constructor.
class const D<TypeVariable extends Bound>.named(
  final int x, [
  final int y = 0,
]) extends A with M implements B, C;
```

It is possible to specify assertions on a primary constructor, just like
the ones that we can specify in the initializer list of a regular
constructor:

```dart
// Current syntax.
class Point {
  int x;
  int y;
  Point(this.x, this.y): assert(0 <= x && x <= y * y);
}

// Using a primary constructor.
class Point(var int x, var int y) {
  this : assert(0 <= x && x <= y * y);
}
```

When using a primary constructor it is possible to use an initializer list
in order to invoke a superconstructor and/or initialize some explicitly
declared instance variables with a computed value.

```dart
// Current syntax.
class A {
  final int x;
  const A.someName(this.x);
}

class B extends A {
  final String s1;
  final String s2;

  const B(int x, int y, {required this.s2})
      : s1 = y.toString(), super.someName(x + 1);
}

// Using primary constructors.
class const A.someName(final int x);

class const B(int x, int y, {required final String s2}) extends A {
  final String s1;
  this : s1 = y.toString(), super.someName(x + 1);
}
```

A formal parameter of a primary constructor which does not have the
modifier `var` or `final` does not implicitly induce an instance
variable. This makes it possible to use a primary constructor (thus
avoiding the duplication of instance variable names and types) even in the
case where some parameters should not introduce any instance variables (so
they are just "normal" parameters).

With a primary constructor, the formal parameters in the header are
introduced into a new scope, known as the _primary initializer scope_.
This scope is inserted as the current scope in several locations. In
particular, it is _not_ the enclosing scope for the body scope of the
class, even though it is located syntactically in the class header. It is
actually the other way around, namely, the class body scope is the
enclosing scope for the primary initializer scope.

The primary initializer scope is the current scope for the initializing
expression of each non-late instance variable declaration in the class
body, if any. Similarly, the primary initializer scope is the current scope
for the initializer list in the body part of the primary constructor, if
any.

In other words, when a class has a primary constructor, each of the
initializing expressions of a non-late instance variable has the same
declarations in scope as the initializer list would have if it had been a
regular constructor in the body. This is convenient, and it makes
refactorings from one to another kind of constructor simpler and safer.

```dart
// Current syntax.
class DeltaPoint {
  final int x;
  final int y;
  DeltaPoint(this.x, int delta): y = x + delta;
}

// Using a primary constructor with a body part.
class DeltaPoint(final int x, int delta) {
  final int y;
  this : y = x + delta;
}

// Using a primary constructor and the associated new scoping.
class DeltaPoint(final int x, int delta) {
  final int y = x + delta;
}
```

When there is a primary constructor, we can allow the initializing
expressions of non-late instance variables to access the constructor
parameters because it is guaranteed that the non-late initializers are
evaluated during the execution of the primary constructor, such that the
value of a variable like `delta` is only used at a point in time where it
exists.

This can only work if the primary constructor is guaranteed to be
executed. Hence the rule, mentioned above, that there cannot be any other
non-redirecting generative constructors in a class that has a primary
constructor.

Finally, here is an example that illustrates how much verbosity this
feature tends to eliminate:

```dart
// Current syntax.
class A {
  A(String _);
}

class E extends A {
  LongTypeExpression x1;
  LongTypeExpression x2;
  LongTypeExpression x3;
  LongTypeExpression x4;
  LongTypeExpression x5;
  LongTypeExpression x6;
  LongTypeExpression x7;
  LongTypeExpression x8;
  late int y;
  int z;
  final List<String> w;

  E({
    required this.x1,
    required this.x2,
    required this.x3,
    required this.x4,
    required this.x5,
    required this.x6,
    required this.x7,
    required this.x8,
    required this.y,
  })  : z = y + 1,
        w = const <Never>[],
        super('Something') {
    // ... a normal constructor body ...
  }
}

// Using a primary constructor.
class A(String _);

class E({
  required var LongTypeExpression x1,
  required var LongTypeExpression x2,
  required var LongTypeExpression x3,
  required var LongTypeExpression x4,
  required var LongTypeExpression x5,
  required var LongTypeExpression x6,
  required var LongTypeExpression x7,
  required var LongTypeExpression x8,
  required this.y,
}) extends A {
  late int y;
  int z = y + 1;
  final List<String> w = const <Never>[];

  this : super('Something') {
    // ... a normal constructor body ...
  }
}
```

Note that the version with a primary constructor can initialize `z` in the
declaration itself, whereas the other version needs to use an element in
the initializer list of the constructor to initialize `z`. This is
necessary because `y` isn't in scope in the initializer list element in the
non-primary-constructor class. Moreover, there cannot be other
non-redirecting generative constructors when there is a primary
constructor, but in the class that does not have a primary constructor we
could add another non-redirecting generative constructor which could
initialize `w` with some other value, in which case we must also initialize
`w` as shown.

## Specification

### Syntax

The grammar is modified as follows. Note that the changes include grammar
rules for extension type declarations because they're using primary
constructors as well.

```ebnf
<classDeclaration> ::= // First alternative modified.
     (<classModifiers> | <mixinClassModifiers>)
     'class' <classNameMaybePrimary> <superclass>? <interfaces>? <classBody>
   | ...;

<primaryConstructor> ::= // New rule.
     'const'? <typeWithParameters> ('.' <identifierOrNew>)?
     <declaringParameterList>;

<classNameMaybePrimary> ::= // New rule.
     <primaryConstructor>
   | <typeWithParameters>;

<typeWithParameters> ::= <typeIdentifier> <typeParameters>?

<classBody> ::= // New rule.
     '{' (<metadata> <memberDeclaration>)* '}'
   | ';';

<extensionTypeDeclaration> ::= // Modified rule.
     'extension' 'type' <primaryConstructor> <interfaces>?
     <extensionTypeBody>;

<extensionTypeBody> ::=
     '{' (<metadata> <memberDeclaration>)* '}'
   | ';';

<enumType> ::= // Modified rule.
     'enum' <classNameMaybePrimary> <mixins>? <interfaces>? '{'
        <enumEntry> (',' <enumEntry>)* ','?
        (';' (<metadata> <memberDeclaration>)*)?
     '}';

<constructorSignature> ::= // Modified rule.
     <constructorName> <formalParameterList> // Old form.
   | <constructorHead> <formalParameterList>; // New form.

<constantConstructorSignature> ::= // Modified rule.
     'const' <constructorSignature>;

<constructorName> ::=
     <typeIdentifier> ('.' <identifierOrNew>)?;

<constructorTwoPartName> ::= // New rule.
     <typeIdentifier> '.' <identifierOrNew>;

<constructorHead> ::= // New rule.
     'new' <identifier>?;

<factoryConstructorHead> ::= // New rule.
     'factory' <identifier>?;

<identifierOrNew> ::=
     <identifier>
   | 'new'

<factoryConstructorSignature> ::= // Modified rule.
     'const'? 'factory' <constructorTwoPartName>
      <formalParameterList> // Old form.
   | 'const'? <factoryConstructorHead>
      <formalParameterList>; // New form.

<redirectingFactoryConstructorSignature> ::= // Modified rule.
     <factoryConstructorSignature> '=' <constructorDesignation>;

<primaryConstructorBodySignature> ::= // New rule.
     'this' <initializers>?;

<methodSignature> ::= // Add one new alternative.
     ...
   | <primaryConstructorBodySignature>;

<declaration> ::= // Add one new alternative.
     ...
   | <primaryConstructorBodySignature>;

<simpleFormalParameter> ::= // Modified rule.
     'covariant'? <type>? <identifier>;

<fieldFormalParameter> ::= // Modified rule.
     <type>? 'this' '.' <identifier> (<formalParameterPart> '?'?)?;

<declaringParameterList> ::= // New rule.
     '(' ')'
   | '(' <declaringFormalParameters> ','? ')'
   | '(' <declaringFormalParameters> ','
         <optionalOrNamedDeclaringFormalParameters> ')'
   | '(' <optionalOrNamedDeclaringFormalParameters> ')';

<declaringFormalParameters> ::= // New rule.
     <declaringFormalParameter> (',' <declaringFormalParameter>)*;

<declaringFormalParameter> ::= // New rule.
     <metadata> <declaringFormalParameterNoMetadata>;

<declaringFormalParameterNoMetadata> ::= // New rule.
     <declaringFunctionFormalParameter>
   | <fieldFormalParameter>
   | <declaringSimpleFormalParameter>
   | <superFormalParameter>;

<declaringFunctionFormalParameter> ::= // New rule.
     'covariant'? ('var' | 'final')? <type>?
     <identifier> <formalParameterPart> '?'?;

<declaringSimpleFormalParameter> ::= // New rule.
     'covariant'? ('var' | 'final')? <type>? <identifier>;

<optionalOrNamedDeclaringFormalParameters> ::= // New rule.
     <optionalPositionalDeclaringFormalParameters>
   | <namedDeclaringFormalParameters>;

<optionalPositionalDeclaringFormalParameters> ::= // New rule.
     '[' <defaultDeclaringFormalParameter>
     (',' <defaultDeclaringFormalParameter>)* ','? ']';

<defaultDeclaringFormalParameter> ::= // New rule.
     <declaringFormalParameter> ('=' <expression>)?;

<namedDeclaringFormalParameters> ::= // New rule.
     '{' <defaultDeclaringNamedParameter>
     (',' <defaultDeclaringNamedParameter>)* ','? '}';

<defaultDeclaringNamedParameter> ::= // New rule.
     <metadata> 'required'? <declaringFormalParameterNoMetadata>
     ('=' <expression>)?;
```

A _primary constructor_ declaration consists of a `<primaryConstructor>` in
the declaration header plus optionally a member declaration in the body
that starts with a `<primaryConstructorBodySignature>`.

A class, mixin class, or extension type declaration whose body is `;` is
treated as the corresponding declaration whose body is `{}` and otherwise
the same. This rule is not applicable to a `<mixinApplicationClass>` *(for
instance, `class B = A with M;`)*.

The grammar is ambiguous with regard to the keyword `factory`. *For
example, `factory() => C();` could be a method named `factory` with an
implicitly inferred return type, or it could be a factory constructor whose
name is the name of the enclosing class.*

This ambiguity is resolved as follows: When a Dart parser expects to parse
a `<memberDeclaration>`, and the beginning of the declaration is `factory`
or one or more of the modifiers `const`, `augment`, or `external` followed
by `factory`, it proceeds to parse the following input as a factory
constructor.

*This is similar to how a statement starting with `switch` or `{` is parsed
as a switch statement or a block, never as an expression statement.*

*Another special exception is introduced with factory constructors in order
to avoid breaking existing code:*

Consider a factory constructor declaration of the form `factory C(...`
optionally starting with zero or more of the modifiers `const`, `augment`,
or `external`. Assume that `C` is the name of the enclosing class, mixin
class, enum, or extension type. In this situation, the declaration declares
a constructor whose name is `C`.

*Without this special rule, such a declaration would declare a constructor
named `C.C`. With this rule it declares a constructor named `C`, which
is the same as today.*

Let _D_ be a class, extension type, or enum declaration.

A compile-time error occurs if _D_ includes a `<classNameMaybePrimary>`
that does not contain a `<primaryConstructor>`, and the body of _D_
contains a member declaration that starts with a
`<primaryConstructorBodySignature>`.

*It is an error to have the body part of a primary constructor in the class
body, but no primary constructor in the header.*

A compile-time error occurs if a `<defaultDeclaringNamedParameter>` has the
modifier `required` as well as a default value.

### Static processing

The ability to use `new` or `factory` as a keyword and omitting the class
name in declarations of ordinary (non-primary) constructors is purely
syntactic. The static analysis and meaning of such constructors is
identical to the form that uses the class name.

The name of a primary constructor of the form
`'const'? id1 <typeParameters>? <declaringParameterList>` is `id1` *(that
is, the same as the name of the class)*.
The name of a primary constructor of the form
`'const'? id1 <typeParameters>? '.' id2 <declaringParameterList>` is
`id1.id2`.

A compile-time error occurs if a class, mixin class, enum, or extension
type has a primary constructor whose name is also the name of a constructor
declared in the body, or if it declares a primary constructor whose name is
`C.n`, and the body declares a static member whose basename is `n`.

Consider a class, mixin class, enum, or extension type declaration _D_ with
a primary constructor *(note that it cannot be a `<mixinApplicationClass>`,
because that kind of declaration does not syntactically support primary
constructors)*. This declaration is treated as a class, mixin class, enum,
respectively extension type declaration without a primary constructor which
is obtained as described in the following. This determines the dynamic
semantics of a primary constructor.

A compile-time error occurs if the body of _D_ contains a non-redirecting
generative constructor, unless _D_ is an extension type.

*For a class, mixin class, or enum declaration, this ensures that every
generative constructor invocation will invoke the primary constructor,
either directly or via a series of generative redirecting constructors.
This is required in order to allow non-late instance variable initializers
to access the parameters.*

If _D_ is an extension type, it is a compile-time error if the primary
constructor that _D_ contains does not have exactly one parameter.

*For an extension type, this ensures that the name and type of the
representation variable is well-defined, and existing rules about final
instance variables ensure that every other non-redirecting generative
constructor will initialize the representation variable. Moreover, there
are no initializing expressions of any instance variable declarations, so
there is no conflict about the meaning of names in such initializing
expressions. This means that we can allow those other non-redirecting
generative constructors to coexist with a primary constructor.*

The declaring parameter list of the primary constructor introduces a new
scope, the _primary initializer scope_, whose enclosing scope is the body
scope of _D_. Each of the parameters in said parameter list is introduced
into this scope.

The same parameter list also introduces the _primary parameter scope_,
whose enclosing scope is also the body scope of the class. Every primary
parameter which is not declaring, not initializing, and not a super
parameter is introduced into this scope.

The primary initializer scope is the current scope for the initializing
expression, if any, of each non-late instance variable declaration. It is
also the current scope for the initializer list in the body part of the
primary constructor, if any.

The primary parameter scope is the current scope for the body of the body
part of the primary constructor, if any.

*Note that the _formal parameter initializer scope_ of a normal
(non-declaring) constructor works in very much the same way as the primary
initializer scope of a primary constructor. The difference is that the
latter is the current scope for the initializing expressions of all
non-late instance variable declarations, in addition to the initializer
list of the body part of the constructor.*

*The point is that the body part of the primary constructor should have
access to the "regular" parameters, but it should have access to the
instance variables rather than the declaring or initializing parameters
with the same names. For example:*

```dart
class C(var String x) {
  void Function() captureAtDeclaration = () => print(x);
  void Function() captureInInitializer;
  void Function()? captureInBody;

  this : captureInInitializer = (() => print(x)) {
    captureInBody = () => print(x);
  }
}

main() {
  var c = C('parameter');
  c.x = 'updated'; // Update `c.x` from 'parameter' to 'updated'.
  c.captureAtDeclaration(); // Prints "parameter".
  c.captureInInitializer(); // Prints "parameter".
  c.captureInBody!(); // Prints "updated".
}
```

*This scoping structure is highly unusual because the declaring parameter
list of a primary constructor is outside the class body, and yet it is
treated as if it were nested inside the body, and occurring in multiple
locations! However, this ensures that the non-late variable initializers
are treated the same as the initializer elements of an ordinary
constructor. Note that this only occurs when the class has a
primary constructor. There is no access to any constructor parameters in
the initializing expression of a non-late instance variable in those cases.
For example:*

```dart
String x = 'top level';

class C(String x) {
  String instance = x;
  late String lateInstance = x;
}

main() {
  var c = C('parameter');
  print(c.instance); // Prints "parameter".
  print(c.lateInstance); // Prints "top level".
}
```

A compile-time error occurs if an assignment to a primary parameter occurs
in the initializing expression of a non-late instance variable, or in the
initializer list of the body part of a primary constructor.

*This includes expressions like `p++` where the assignment is implicit.
The rule only applies for non-late variables because the primary parameters
are not in scope in the initializing expression of a late variable.*

Consider a class with a primary constructor that also has a body part with
an initializer list. A compile-time error occurs if an instance variable
declaration has an initializing expression, and it is also initialized by
an element in the initializer list of the body port.

*This is already an error when the instance variable is final, but no such
error is raised when the instance variable is mutable and the initializer
list is part of a non-primary constructor. However, with a primary
constructor this situation will always cause the value of the initializing
expression in the variable declaration to be overwritten by the value in
the initializer list, which makes the situation more confusing than
useful.*

The following errors apply to formal parameters of a primary constructor.
Let _p_ be a formal parameter of a primary constructor in a class, mixin
class, enum, or extension type declaration _D_ named `C`:

A compile-time error occurs if _p_ contains a term of the form `this.v`, or
`super.v` where `v` is an identifier, and _p_ has the modifier
`covariant`. *For example, `required covariant int this.v` is an error. The
reason for this error is that the modifier `covariant` must be specified on
the declaration of `v` which is known to exist, not on the parameter.*

A compile-time error occurs if _p_ has the modifier `covariant`, but
not `var`. *This parameter does not induce a setter.*

Conversely, it is not an error for the modifier `covariant` to occur on a
declaring formal parameter _p_ of a primary constructor. This extends the
existing allowlist of places where `covariant` can occur.

The semantics of the primary constructor is found in the following steps,
where _D_ is the class, mixin class, extension type, or enum declaration in
the program that includes a primary constructor _k_, and _D2_ is the result
of the derivation of the semantics of _D_. The derivation step will delete
elements that amount to the primary constructor. Semantically, it will add
a new constructor _k2_, and it will add zero or more instance variable
declarations.

*Adding program elements 'semantically' implies that this is not a source
code transformation, it is a way to obtain semantic program elements that
differ from the ones that are obtained from pre-feature declarations, but
can be specified in terms of pre-feature declarations.*

Where no processing is mentioned below, _D2_ is identical to _D_. Changes
occur as follows:

Let `p` be a formal parameter in _k_ which has the modifier `var` or the
modifier `final` *(that is, `p` is a declaring parameter)*.

Consider the situation where `p` has no type annotation:
- if the combined member signature for a getter with the same name as `p`
  from the superinterfaces of _D_ exists and has return type `T`, the
  parameter `p` has declared type `T`. If no such getter exists, but a
  setter with the same basename exists, with a formal parameter whose type
  is `T`, the parameter `p` has declared type `T`. *In other words, an
  instance variable introduced by a declaring parameter is subject to
  override inference, just like an explicitly declared instance variable.*
- otherwise, if `p` is optional and has a default value whose static type
  in the empty context is a type `T` which is not `Null` then `p` has
  declared type `T`. When `T` is `Null`, `p` instead has declared type
  `Object?`.
- otherwise, if `p` does not have a default value then `p` has declared
  type `Object?`.

*Dart has traditionally assumed the type `dynamic` in such situations. We
have chosen the more strictly checked type `Object?` instead, in order to
avoid introducing run-time type checking implicitly.*

The current scope of the formal parameter list of the primary constructor
in _D_ is the body scope of the class.

*We need to ensure that the meaning of default value expressions is
well-defined, taking into account that a primary constructor is physically
located in a different scope than other constructors. We do this by
specifying the current scope explicitly as the body scope, in spite of the
fact that the primary constructor is actually placed outside the braces
that delimit the class body.*

Next, _k2_ has the modifier `const` iff the keyword `const` occurs just
before the name of _D_, or _D_ is an `enum` declaration.

Consider the case where _k_ is a primary constructor. If the name `C` in
_D_ and the type parameter list, if any, is followed by `.id` where `id` is
an identifier then _k2_ has the name `C.id`. If it is followed by `.new`
then _k2_ has the name `C`. If it is not followed by `.` then _k2_ has the
name `C`. _D2_ omits the part derived from `'.' <identifierOrNew>` that
follows the name and type parameter list in _D_, if said part exists.
Moreover, _D2_ omits the formal parameter list _L_ that follows the name,
type parameter list, if any, and `.id`, if any.

The formal parameter list _L2_ of _k2_ is identical to _L_, except that each
formal parameter is processed as follows.

The formal parameters in _L_ and _L2_ occur in the same order, and
mandatory positional parameters remain mandatory, and named parameters
preserve the name and the modifier `required`, if any. An optional
positional or named parameter remains optional; if it has a default value
`d` in _L_ then it has the default value `d` in _L2_ as well.

- An initializing formal parameter *(e.g., `T this.x`)* is copied from _L_
  to _L2_, along with the default value, if any, and is otherwise unchanged.
- A super parameter is copied from _L_ to _L2_ along with the default
  value, if any, and is otherwise unchanged.
- A formal parameter which is not covered by the previous two cases and
  which does not have the modifier `var` or the modifier `final` is copied
  unchanged from _L_ to _L2_ *(this is a plain, non-declaring parameter)*.
- Otherwise, a formal parameter (named or positional) of the form `var T p`
  or `final T p` where `T` is a type and `p` is an identifier is replaced
  in _L2_ by `this.p`, along with its default value, if any. If the
  parameter has the modifier `var` and _D_ is an extension type declaration
  then a compile-time error occurs. Otherwise, a semantic instance variable
  declaration corresponding to the syntax `T p;` or `final T p;` is added
  to _D2_. It includes the modifier `final` if the parameter in _L_ has the
  modifier `final` and _D_ is not an `extension type` decaration; if _D_ is
  an `extension type` declaration then the name of `p` specifies the name
  of the representation variable. In all cases, if `p` has the modifier
  `covariant` then this modifier is removed from the parameter in _L2_, and
  it is added to the instance variable declaration named `p`.

If there is an initializer list following the formal parameter list _L_
then _k2_ has an initializer list with the same elements in the same order.

Finally, _k2_ is added to _D2_, and _D_ is replaced by _D2_.

### Language versioning

This feature is language versioned.

*It introduces a breaking change in the grammar, which implies that
developers must explicitly enable it. In particular, the feature disallows
`var x`, `final x`, and `final T x` as formal parameter declarations in all
functions that are not primary constructors. Moreover, `factory() {}` in a
class body used to be a method declaration whose name is `factory`. With
this feature, it is a factory constructor declaration whose name is the
name of the enclosing class, enum, or extension type declaration.*

### Discussion

This design includes support for adding the primary constructor
parameters to the scope of the class, as proposed by Slava Egorov.

The scoping structure is highly unusual because the formal parameter list
of a primary constructor is located outside the class body, and still the
corresponding scopes (the primary initializer scope and the primary
parameter scope) have the class body scope as their enclosing
scope. However, this causes the scoping to be the same for elements in the
initializer list and in the initializing expressions of non-late instance
variables, and that allows us to move code from an initializer list to a
variable initializer and vice versa without worrying about changing the
meaning of the code. This in turn makes it easier to change a regular
(non-primary) constructor to a primary constructor, or vice versa. So we
expect the unusual scoping structure to work reasonably well in practice.

The proposal allows an `enum` declaration to include the modifier `const`
just before the name of the declaration when it has a primary constructor,
but it also allows this keyword to be omitted. The specified constructor
will be constant in both cases. This differs from the treatment of regular
(non-primary) constructors in an `enum` declaration: They _must_ have the
modifier `const`, it is never inferred. This discrepancy was included
because the syntax `enum const E(String s) {...}` seems redundant because
`enum` implies that every constructor must be constant. This is not the
case in the body where a constructor declaration may be physically pretty
far removed from any syntactic hint that the constructor must be constant
(if we can't see the word `enum` then we may not know that it is that kind
of declaration, and the constructor might be non-const).

### Changelog

1.13 - November 25, 2025

* Specify that an assignment to a primary parameter in initialization code
  is an error. Specify an error for double initialization of a mutable
  instance variable in the declaration and in a primary constructor
  initializer list.

1.12 - November 6, 2025

* Eliminate in-body declaring constructors. Revert to the terminology where
  the feature and the newly introduced declarations are known as 'primary',
  because every other kind is now gone.

1.11 - October 30, 2025

* Introduce the new syntax for the beginning of a constructor declaration
  (`new();` rather than `ClassName();`). Specify how to handle the
  ambiguity involving the keyword `factory`. Clarify that this feature is
  language versioned.

1.10 - October 3, 2025

* Rename the feature to 'declaring constructors'. Fix several small errors.

1.9 - August 8, 2025

* Change the scoping such that non-late initializing expressions have the
  primary constructor parameters as the enclosing scope. Adjust several
  grammar rules. Clarify or correct several compile-time errors. Adjust the
  rules about extension types to avoid a breaking change. Specify override
  inference for getters and setters introduced by declaring parameters with
  no explicit type. Perform several other smaller adjustments.

1.8 - July 16, 2025

* Rename the feature to 'declaring constructors', which is more informative.
  This means that a primary body constructor is now an in-body declaring
  constructor, and an in-header primary constructor is an in-header declaring
  constructor. On top of this, the in-header form is also known as a
  _primary_ constructor, because every other generative constructor must
  ultimately invoke the primary one.

1.7 - July 4, 2025

* Update the parts after the 'Syntax' section to use the new syntax of
  version 1.6, and also to enable the scoping where initializing expressions
  with no access to `this` can evaluate final instance variables by reading the
  corresponding primary constructor formal parameter.

1.6 - June 27, 2025

* Explain in-header constructors as "move the parameter list", which also
  introduces support for in-header constructors with all features (initializer
  list, superinitializer, body), which will remain in the body. This version
  only updates the introduction and the 'Syntax' section.

1.5 - November 25, 2024

* Reintroduce in-body primary constructors with syntax `this(...)`.

1.4 - November 12, 2024

* Add support for a full initializer list (which adds elements of the form
  `x = e` and `super(...)` or `super.name(...)`). Add the rule that a
  parameter introduces an instance variable except when used in the
  initializer list.

1.3 - July 12, 2024

* Add support for assertions in the primary constructor. Add support for
  inferring the declared type of an optional parameter based on its default
  value.

1.2 - May 24, 2024

* Remove support for primary constructors in the body of a declaration.

1.1 - August 22, 2023

* Update to refer to extension types rather than inline classes.

1.0 - April 28, 2023

* First version of this document released.
