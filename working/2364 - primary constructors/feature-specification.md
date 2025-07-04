# Primary Constructors

Author: Erik Ernst

Status: Draft

Version: 1.6

Experiment flag: primary-constructors

This document specifies _primary constructors_. This is a feature that
allows one constructor and a set of instance variables to be specified in a
concise form in the header of the declaration, or in the body. In the case
where the constructor is specified in the header, some elements are still
specified in the class body, if present: The in-header constructor can have
an initializer list in the body, including assertions, instance variable
initializers, and/or a superinitializer. The in-header constructor can also
have a body in the class body.

One variant of this feature has been proposed in the [struct proposal][],
several other proposals have appeared elsewhere, and prior art exists in
languages like [Kotlin][kotlin primary constructors] and Scala (with
specification [here][scala primary constructors] and some examples
[here][scala primary constructor examples]). Many discussions about the
feature have taken place in github issues marked with the
[primary-constructors label][].

Recently, [Bob proposed][] that primary body constructors should use the syntax
`this.name(...)` rather than `primary C.name(...)`. This proposal includes
that choice.

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

A primary constructor in the header allows us to define the same class much
more concisely:

```dart
// A declaration with the same meaning, using a primary header constructor.
class Point(var int x, var int y);
```

A class that has a primary header constructor can not have any other
generative non-redirecting constructors. This requirement must be upheld
because it must be guaranteed that the primary header constructor is
actually executed on every newly created instance of this class.

A primary body constructor is slightly less concise, but it allows the
class header to remain simpler and more readable when there are many
parameters. The previous example would look as follows using a primary body
constructor:

```dart
// A declaration with the same meaning, using a primary body constructor.
class Point {
  this(var int x, var int y);
}
```

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

// Using a primary header constructor.
class Point(var int x, var int y);

// Using a primary body constructor.
class Point {
  this(var int x, var int y);
}
```

These examples will serve as an illustration of the proposed syntax, but
they will also illustrate the semantics of the primary constructor
declarations, because those declarations work exactly the same as the
declarations using the current syntax.

Note that an empty class body, `{}`, can be replaced by `;`.

The basic idea with the header form is that a parameter list that occurs
just after the class name specifies both a constructor declaration and a
declaration of one instance variable for each formal parameter in said
parameter list that has the _declaring_ modifier `var` or `final`.

With this feature, the declaration of formal parameters as `final` will be
a compile-time error. This ensures that `final int x` is unambiguously a
declaring parameter. Developers who wish to maintain a style whereby formal
parameters are never modified will have a lint to flag all such mutations.

Similarly, with this feature a regular (non-declaring) formal parameter can
not be declared with the syntax `var name`, it must have a type (`T name`)
or the type must be omitted (`name`).

A primary header constructor can have a body and/or an initializer list.
These elements are placed in the class body in a declaration that provides
"the rest" of the constructor declaration which is given in the header.

The parameter list of a primary constructor (in the header or in the body)
uses a slightly different grammar than other functions. The difference is
that it can include _declaring_ formal parameters. They can be recognized
unambiguously because they have the modifier `var` or `final`.

A primary body constructor can have a body and an initializer list as well
as initializing formals and super parameters, just like other constructors
in the body.

There is no way to indicate that the instance variable declarations should
have the modifiers `late` or `external` (because formal parameters cannot
have those modifiers). This omission is not seen as a problem in this
proposal: They can be declared using the same syntax as today, and
initialization, if any, can be done in a constructor body.

An `external` instance variable amounts to an `external` getter and an
`external` setter. Such a "variable" cannot be initialized by an
initializing formal anyway, but it may need to be "initialized" in the
sense that the intended program behavior requires that external setter to
be invoked, and this can be done in the constructor body.

```dart
// Current syntax.
class ModifierClass {
  late int x;
  external double d;
  ModifierClass(this.x);
}

// Using a primary header constructor.
class ModifierClass(this.x) {
  late int x;
  external double d;
}

// Using a primary body constructor.
class ModifierClass {
  late int x;
  external double d;
  this(this.x);
}
```

`ModifierClass` as written does not really make sense (`x` does not have to
be `late`), but there could be other constructors that do not initialize
`x`.

Super parameters can be declared in the same way as in a body constructor:

```dart
// Current syntax.
class A {
  final int a;
  A(this.a);
}

class B extends A {
  B(super.a);
}

// Using a primary header constructor.
class A(final int a);
class B(super.a) extends A;

// Using a primary body constructor.
class A {
  this(final int a);
}

class B extends A {
  this(super.a);
}
```

Next, the constructor can be named, and it can be constant:

```dart
// Current syntax.
class Point {
  final int x;
  final int y;
  const Point._(this.x, this.y);
}

// Using a primary header constructor.
class const Point._(final int x, final int y);

// Using a primary body constructor.
class Point {
  const this._(final int x, final int y);
}
```

Note that the class header contains syntax that resembles the constructor
declaration, which may be helpful when reading the code.

With the primary header constructor, the modifier `const` could have been
placed on the class (`const class`) rather than on the class name. This
proposal puts it on the class name because the notion of a "constant class"
conflicts with with actual semantics: It is the constructor which is
constant because it is able to be invoked during constant expression
evaluation; it can also be invoked at run time, and there could be other
(non-constant) constructors. This means that it is at least potentially
confusing to say that it is a "constant class", but it is consistent with
the rest of the language to say that this particular primary constructor is
a "constant constructor". Hence `class const Name` rather than `const class
Name`.

The modifier `final` on a parameter in a primary constructor specifies that
the instance variable declaration which is induced by this primary
constructor parameter is `final`.

In the case where the declaration is an `extension type`, the modifier
`final` on the representation variable can be specified or omitted. Note
that an extension type declaration is specified to use a primary header
constructor (in that case there is no other choice, it is in the grammar
rules):

```dart
// Using a primary header constructor.
extension type I.name(int x);
```

Optional parameters can be declared as usual in a primary constructor, with
default values that must be constant as usual:

```dart
// Current syntax.
class Point {
  int x;
  int y;
  Point(this.x, [this.y = 0]);
}

// Using a primary header constructor.
class Point(var int x, [var int y = 0]);

// Using a primary body constructor.
class Point {
  this(var int x, [var int y = 0]);
}
```

We can omit the type of an optional parameter with a default value,
in which case the type is inferred from the default value:

```dart
// Infer type from default value, in header.
class Point(var int x, [var y = 0]);

// Infer type from default value, in body.
class Point {
  this(var int x, [var y = 0]);
}
```

Similarly for named parameters, required or not:

```dart
// Current syntax.
class Point {
  int x;
  int y;
  Point(this.x, {required this.y});
}

// Using a primary header constructor.
class Point(var int x, {required var int y});

// Using a primary body constructor.
class Point {
  this(var int x, {required var int y});
}
```

The class header can have additional elements, just like class headers
where there is no primary constructor:

```dart
// Current syntax.
class D<TypeVariable extends Bound> extends A with M implements B, C {
  final int x;
  final int y;
  const D.named(this.x, [this.y = 0]);
}

// Using a primary header constructor.
class const D<TypeVariable extends Bound>.named(
  var int x, [
  var int y = 0,
]) extends A with M implements B, C;

// Using a primary body constructor.
class D<TypeVariable extends Bound> extends A with M implements B, C {
  const this.named(
    var int x, [
    var int y = 0,
  ]);
}
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

// Using a primary header constructor.
class Point(var int x, var int y) {
  this : assert(0 <= x && x <= y * y);
}

// Using a primary body constructor.
class Point {
  this(var int x, var int y): assert(0 <= x && x <= y * y);
}
```

When using a primary body constructor it is possible to use an initializer
list in order to invoke a superconstructor and/or initialize some
explicitly declared instance variables with a computed value. The primary
header constructor can have the same elements, but they are declared in the
class body.

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

class B extends A {
  final String s1;
  const this(int x, int y, {required final String s2})
      : s1 = y.toString(), assert(s2.isNotEmpty), super.someName(x + 1);
}
```

A formal parameter of a primary constructor which does not have the
modifier `var` or `final` does not implicitly induce an instance
variable. This makes it possible to use a primary constructor (thus
avoiding the duplication of instance variable names and types) even in the
case where some parameters should not introduce any instance variables (so
they are just "normal" parameters).

With a primary header constructor, the formal parameters in the header are
introduced into a new scope. This means that the parameters whose name is
not introduced by any nested scope (e.g., the class body scope) is in scope
in the class body. It is a compile-time error to refer to such a parameter
anywhere except in an initializing expression of a non-late instance
variable declaration.

```dart
// Current syntax.
class DeltaPoint {
  final int x;
  final int y;
  DeltaPoint(this.x, int delta): y = x + delta;
}

// Using a primary header constructor.
class DeltaPoint(final int x, int delta) {
  final int y = x + delta;
}
```

This is possible because it is guaranteed that the non-late initializers
are evaluated during the execution of the primary header constructor, such
that the value of a variable like `delta` is only used at a point in time
where it exists.

Similarly, if an identifier expression in an initializing expression of a
non-late instance variable declaration resolves to a final instance
variable (this is currently an error, there is no access to `this`), and
there is a primary header constructor parameter that corresponds to this
instance variable (that is, a declaring parameter or an initializing formal
with the same name), it will evaluate to the value of the parameter.
For example, `x` is used in the initializer for `y` in the example above,
which is possible because of this mechanism.

This can only work if the primary header constructor is guaranteed to be
executed. Hence the rule that there cannot be any other generative
constructors in a class that has a primary header constructor.

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
  })  : z = 1,
        w = const <Never>[],
        super('Something') {
    // ... a normal constructor body ...
  }
}

// Using a primary body constructor.
class A(String _);

class E extends A {
  late int y;
  int z;
  final List<String> w;

  this({
    required var LongTypeExpression x1,
    required var LongTypeExpression x2,
    required var LongTypeExpression x3,
    required var LongTypeExpression x4,
    required var LongTypeExpression x5,
    required var LongTypeExpression x6,
    required var LongTypeExpression x7,
    required var LongTypeExpression x8,
    required this.y,
  }) : z = 1,
       w = const <Never>[],
       super('Something') {
    // ... a normal constructor body ...
  }
}
```

Moreover, we may get rid of all those occurrences of `required` in the
situation where it is a compile-time error to not have them, but that is a
separate proposal, [here][inferred-required] or [here][simpler-parameters]

[inferred-required]: https://github.com/dart-lang/language/blob/main/working/0015-infer-required/feature-specification.md
[simpler-parameters]: https://github.com/dart-lang/language/blob/main/working/simpler-parameters/feature-specification.md

## Specification

### Syntax

The grammar is modified as follows. Note that the changes include support
for extension type declarations, because they're intended to use primary
constructors as well.

```
<classDeclaration> ::= // First alternative modified.
     (<classModifiers> | <mixinClassModifiers>)
     'class' <classNamePart> <superclass>? <interfaces>? <classBody>
   | ...;

<primaryHeaderConstructorNoConst> ::= // New rule.
     <typeIdentifier> <typeParameters>?
     ('.' <identifierOrNew>)? <declaringParameterList>

<classNamePart> ::= // New rule.
     'const'? <primaryHeaderConstructorNoConst>
   | <typeWithParameters>;

<typeWithParameters> ::= <typeIdentifier> <typeParameters>?

<classBody> ::= // New rule.
     '{' (<metadata> <classMemberDeclaration>)* '}'
   | ';';

<extensionTypeDeclaration> ::= // Modified rule.
     'extension' 'type' <classNamePart> <interfaces>?
     <extensionTypeBody>;

<extensionTypeMemberDeclaration> ::= <classMemberDeclaration>;

<extensionTypeBody> ::=
     '{' (<metadata> <extensionTypeMemberDeclaration>)* '}'
   | ';';

<enumType> ::= // Modified rule.
     'enum' <classNamePart> <mixins>? <interfaces>? '{'
        <enumEntry> (',' <enumEntry>)* (',')?
        (';' (<metadata> <classMemberDeclaration>)*)?
     '}';

<constructorSignature> ::= // Modified rule.
     <constructorName> <declaringParameterList>
   | 'this' ('.' <identifierOrNew>);

<constantConstructorSignature> ::= // Modified rule.
     'const' <constructorSignature>;

<constructorName> ::= // Modified rule.
     (<typeIdentifier> | 'this') ('.' <identifierOrNew>)?

<identifierOrNew> ::=
     <identifier>
   | 'new'

<simpleFormalParameter> ::= // Modified rule.
     'covariant'? <type>? <identifier>;

<fieldFormalParameter> ::= // Modified rule.
     <type>? 'this' '.' <identifier> (<formalParameterPart> '?'?)?;

<declaringParameterList> ::= // New rule.
     '(' ')'
   | '(' <declaringFormalParameters> ','? ')'
   | '(' <declaringFormalParameters> ',' <optionalOrNamedDeclaringFormalParameters> ')'
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

A class declaration whose class body is `;` is treated as a class declaration
whose class body is `{}`.

Let _D_ be a class, extension type, or enum declaration.

A compile-time error occurs if _D_ includes a `<classNamePart>` that
contains a `<primaryHeaderConstructorNoConst>`, and the body of _D_
contains a `<constructorSignature>` beginning with `this` that contains a
`<declaringParameterList>`.

*That is, it is an error to have a declaring parameter list of a primary
constructor both in the header and in the body.*

A compile-time error occurs if _D_ includes a `<classNamePart>` that
does not contain a `<primaryHeaderConstructorNoConst>`, and the body of _D_
contains a `<constructorSignature>` beginning with `this` that does not
contain a `<declaringParameterList>`.

*It is an error to have a primary constructor in the class body, but
no declaring parameter list, neither in the header nor in the body. Note
that constant constructors are included because a
`<constantConstructorSignature>` contains a `<constructorSignature>`.*

A compile-time error occurs if _D_ includes a `<classNamePart>` beginning
with `const`, and the body of _D_ contains a `<constructorSignature>`
beginning with `this` which is not part of a
`<constantConstructorSignature>`.

*That is, it is an error for the header to contain `const` if there is a
primary constructor in the body as well, and it does not contain
`const`. In short, if the header says `const` then a primary body
constructor must also say `const`. On the other hand, it is allowed to omit
`const` in the header and have `const` in a primary body
constructor. Finally, it is allowed to omit `const` in both locations. In
this case the constructor is not constant.*

*The meaning of a primary constructor is defined in terms of rewriting it to a
body constructor and zero or more instance variable declarations. This implies
that there is a class body when there is a primary constructor. We do not wish
to define primary constructors such that the absence or presence of a primary
constructor can change the length of the superclass chain, and hence `class C;`
has a class body just like `class C(int i);` and just like `class C extends
Object {}`, and all three of them have `Object` as their direct superclass.*

### Static processing

Consider a class, enum or extension type declaration _D_ with a primary
header constructor *(note that it cannot be a `<mixinApplicationClass>`,
because that kind of declaration does not support primary constructors,
that is a syntax error)*. This declaration is treated as a class, enum, or
extension type declaration without a primary header constructor which is
obtained as described in the following. This determines the dynamic
semantics of a primary constructor.

A compile-time error occurs if the body of _D_ contains a non-redirecting
generative constructor. *This ensures that every constructor invocation
for this class will invoke the primary header constructor, either directly
or via a series of generative redirecting constructors. This is required in
order to allow initializers with no access to `this` to use the
parameters.*

The declaring parameter list of the primary header constructor introduces a
new scope, the _declaring parameter scope_, whose enclosing scope is the
type parameter scope of _D_, if any, and otherwise the enclosing library
scope. The body scope of _D_ has the declaring parameter scope as its
enclosing scope.

*This implies that every parameter of the primary header constructor is in
scope in the class body, unless the class body has a declaration with the
same name (which would shadow the parameter).*

A compile-time error occurs if an identifier resolves to a primary header
constructor parameter, unless the identifier occurs in an initializing
expression of a non-late instance variable declaration.

*We can only use these parameters when it is guaranteed that the primary
header constructor is currently being executed.*

Assume that the primary header constructor has a declaring parameter with
the name `n`, or an initializing formal parameter with the name `n`. Assume
that an initializing expression of a non-late instance variable contains an
identifier expression of the form `n` which is resolved as a reference to
the instance variable which is initialized by said parameter *(that
instance variable must also have the name `n`)*. In this case, the
identifier expression evaluates to the value of the parameter.

*This means that initializing expressions can, apparently, use the value of
instance variables declared by the same class (not, e.g., inherited ones).
They will actually get the value of the primary header parameter, but this
value is also guaranteed to be the initial value of the corresponding
instance variable.*

*Note that it only applies to identifier expressions. In particular, this
does not allow initializing expressions to assign to other instance
variables.*

The following errors apply to formal parameters of a primary constructor,
be it in the header or in the body. Let _p_ be a formal parameter of a
primary constructor in a class `C`:

A compile-time error occurs if _p_ contains a term of the form `this.v`, or
`super.v` where `v` is an identifier, and _p_ has the modifier
`covariant`. *For example, `required covariant int this.v` is an error.*

A compile-time error occurs if _p_ has both of the modifiers `covariant`
and `final`. *A final instance variable cannot be covariant, because being
covariant is a property of the setter.*

A compile-time error occurs if _p_ has the modifier `covariant`, but
neither `var` nor `final`. *This parameter does not induce an instance
variable, so there is no setter.*

Conversely, it is not an error for the modifier `covariant` to occur on a
declaring formal parameter _p_ of a primary constructor. This extends the
existing allowlist of places where `covariant` can occur.

*A primary body constructor does not give rise to additional scopes or
additional rules about access to this. The following applies to both the
header and the body form of primary constructors.*

The semantics of the primary constructor is found in the following steps,
where _D_ is the class, extension type, or enum declaration in the program
that includes a primary constructor, and _D2_ is the result of the
derivation of the semantics of _D_. The derivation step will delete
elements that amount to the primary constructor; it will add a new
constructor _k_; it will add zero or more instance variable declarations.

Where no processing is mentioned below, _D2_ is identical to _D_. Changes
occur as follows:

Assume that `p` is an optional formal parameter in _D_ which has the
modifier `var` or the modifier `final` *(that is, `p` is a declaring
parameter)*.

Assume that `p` does not have a declared type, but it does have a default
value whose static type in the empty context is a type (not a type schema)
`T` which is not `Null`. In that case `p` is considered to have the
declared type `T`. When `T` is `Null`, `p` is considered to have the
declared type `Object?`. If `p` does not have a declared type nor a default
value then `p` is considered to have the declared type `Object?`.

*Dart has traditionally assumed the type `dynamic` in such situations. We
have chosen the more strictly checked type `Object?` instead, in order to
avoid introducing run-time type checking implicitly.*

The current scope of the formal parameter list and initializer list (if
any) of the primary constructor in _D_ is the body scope of the class.

*We need to ensure that the meaning of default value expressions is
well-defined, taking into account that a primary header constructor is
physically located in a different scope than in-body constructors. We do
this by specifying the current scope explicitly as the body scope, in spite
of the fact that the primary constructor is actually placed outside the
braces that delimit the class body.*

Next, _k_ has the modifier `const` iff the keyword `const` occurs just
before the name of _D_ or before `this`, or _D_ is an `enum` declaration.

Consider the case where _D_ is a primary header constructor. If the name
`C` in _D_ and the type parameter list, if any, is followed by `.id` where
`id` is an identifier then _k_ has the name `C.id`. If it is followed by
`.new` then _k_ has the name `C`. If it is not followed by `.`  then _k_
has the name `C`. If it exists, _D2_ omits the part derived from
`'.' <identifierOrNew>` that follows the name and type parameter list, if
any, in _D_. Moreover, _D2_ omits the formal parameter list _L_ that
follows the name, type parameter list, if any, and `.id`, if any.

Otherwise, _D_ is a primary body constructor. If the reserved word `this`
is followed by `.id` where `id` is an identifier then _k_ has the name
`C.id`. If it is followed by `.new` then _k_ has the name `C`. If it is not
followed by `.`  then _k_ has the name `C`.

The formal parameter list _L2_ of _k_ is identical to _L_, except that each
formal parameter is processed as follows.

The formal parameters in _L_ and _L2_ occur in the same order, and
mandatory positional parameters remain mandatory, and named parameters
preserve the name and the modifier `required`, if any.  An optional
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
  in _L2_ by `this.p`, along with its default value, if any.  Next, an
  instance variable declaration of the form `T p;` or `final T p;` is added
  to _D2_. The instance variable has the modifier `final` if the parameter
  in _L_ has the modifier `final`, or _D_ is an `extension type`
  declaration, or _D_ is an `enum` declaration. In all cases, if `p` has
  the modifier `covariant` then this modifier is removed from the parameter
  in _L2_, and it is added to the instance variable declaration named `p`.

In every case, any DartDoc comments are copied along with the formal
parameter, and in the case where an instance variable is implicitly induced
the DartDoc comment is also added to that instance variable.

If there is an initializer list following the formal parameter list _L_ then
_k_ has an initializer list with the same elements in the same order.

*The current scope of the initializer list in _D_ is the body scope of the
enclosing declaration even when _D_ is a primary header constructor, which
means that they preserve their semantics when moved into the body.*

Finally, _k_ is added to _D2_, and _D_ is replaced by _D2_.

### Warnings

The language does not specify warnings, but the following is recommended:

A warning is emitted in the case where an identifier expression is resolved
to yield the value of a declaring or initializing formal parameter in a
primary header constructor, and this identifier occurs in a function
literal, and the corresponding instance variable is non-final.

The point is that it is highly confusing if such a parameter reference is
considered to be "the same thing" as the variable with the same name which
is in scope, but the parameter has the initial value of that instance
variable and the instance variable has been modified in the meantime.

### Discussion

This proposal includes support for adding the primary header parameters to
the scope of the class, as proposed by Slava Egorov.

It uses a simple scoping structure based directly on the syntax: The
primary header parameters are added to the scope which is the enclosing
scope of the class body scope. This allows non-late instance variable
initializers (and no other locations) to use the primary header parameters
whose name is not also the name of a declaration in the class body.

For parameters which are directly associated with an instance variable
declaration (that is, a declaring parameter or an initializing formal
parameter), there is a special "backup" rule: Assume that `id` is an
identifier expression in a non-late variable initializer. Assume that `id`
resolves to an instance variable of the same class that has such a
corresponding parameter. This used to be an error (because the location
where `id` occurs does not have access to `this`), but it will now evaluate
to the value of the corresponding parameter. Note that this value is
guaranteed to also be the initial value of the corresponding instance
variable.

This differs from an approach in the case where there is an instance
variable and a primary header parameter with the same name where there is
no correspondence:

```dart
class A(int x) {
  int x = 42;
  final y = x + 1;
}
```

In this case the primary header parameter `x` is just a plain parameter (it
does not declare an instance variable named `x` and it doesn't initialize
any such instance variable). With this proposal the occurrence of `x` in
the initializing expression of `y` is a compile-time error (there is no
access to `this`, and the "backup rule" doesn't apply).

Alternatively, if we simply say that the primary header parameters are in
scope in the non-late instance variable initializers then we'd allow `x` to
refer to the parameter even though it has nothing whatsoever to do with the
instance variable named `x`. This proposal does not use this alternative
approach because it is considered highly confusing that the two occurrences
of `x` in the class body are completely different entities.

### Changelog

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
