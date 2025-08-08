# Declaring and Primary Constructors

Author: Erik Ernst

Status: Draft

Version: 1.9

Experiment flag: declaring-constructors

This document specifies _declaring constructors_. This is a feature that
allows one constructor and a set of instance variables to be specified in a
concise form in the header of the declaration, or in the body. In the case
where the constructor is specified in the header, some elements can still be
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
that choice. Several recent updates to this proposal are based on ideas from
that proposal.

[struct proposal]: https://github.com/dart-lang/language/blob/master/working/extension_structs/overview.md
[kotlin primary constructors]: https://kotlinlang.org/docs/classes.html#constructors
[scala primary constructors]: https://www.scala-lang.org/files/archive/spec/2.11/05-classes-and-objects.html#constructor-definitions
[scala primary constructor examples]: https://www.geeksforgeeks.org/scala-primary-constructor/
[primary-constructors label]: https://github.com/dart-lang/language/issues?q=is%3Aissue+is%3Aopen+primary+constructor+label%3Aprimary-constructors
[Bob proposed]: https://github.com/dart-lang/language/blob/main/working/declaring-constructors/feature-specification.md

## Introduction

Declaring constructors is a conciseness feature. It does not provide any new
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

A declaring constructor in the header allows us to define the same class much
more concisely:

```dart
// A declaration with the same meaning, using a declaring header constructor.
class Point(var int x, var int y);
```

A class that has a declaring header constructor cannot have any other
non-redirecting generative constructors. This requirement must be upheld
because it must be guaranteed that the declaring header constructor is
actually executed on every newly created instance of this class. This rule
is further motivated below.

A declaring header constructor is also known as a _primary constructor_,
because all other generative constructors must invoke the primary one
(directly or indirectly).

A declaring body constructor is slightly less concise, but it allows the
class header to remain simpler and more readable when there are many
parameters. The previous example would look as follows using a declaring
body constructor:

```dart
// A declaration with the same meaning, using a declaring body constructor.
class Point {
  this(var int x, var int y);
}
```

In the examples below we show the current syntax directly followed by a
declaration using a declaring constructor. The meaning of the two (or more)
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

// Using a declaring header constructor (aka primary constructor).
class Point(var int x, var int y);

// Using a declaring body constructor.
class Point {
  this(var int x, var int y);
}
```

These examples will serve as an illustration of the proposed syntax, but
they will also illustrate the semantics of the declaring constructor
declarations, because those declarations work exactly the same as the
declarations using the current syntax.

Note that an empty class body, `{}`, can be replaced by `;`.

The basic idea with the header form is that a parameter list that occurs
just after the class name specifies both a constructor declaration and a
declaration of one instance variable for each formal parameter in said
parameter list that has the _declaring_ modifier `var` or `final`.

With this feature, all other declarations of formal parameters as `final`
will be a compile-time error. This ensures that `final int x` is
unambiguously a declaring parameter. Developers who wish to maintain a
style whereby formal parameters are never modified will have a
[lint][parameter_assignments] to flag all such mutations.

[parameter_assignments]: https://dart.dev/tools/linter-rules/parameter_assignmentshttps://dart.dev/tools/linter-rules/parameter_assignments

Similarly, with this feature a regular (non-declaring) formal parameter can
not use the syntax `var name`, it must have a type (`T name`) or the type
must be omitted (`name`).

A declaring header constructor can have a body and/or an initializer list.
These elements are placed in the class body in a declaration that provides
"the rest" of the constructor declaration which is given in the header.

The parameter list of a declaring constructor (in the header or in the body)
uses a slightly different grammar than other functions. The difference is
that it can include declaring formal parameters. They can be recognized
unambiguously because they have the modifier `var` or `final`.

A declaring body constructor can have a body and an initializer list as well
as initializing formals and super parameters, just like other constructors
in the body.

There is no way to indicate that the instance variable declarations should
have the modifiers `late` or `external` (because formal parameters cannot
have those modifiers). This omission is not seen as a problem in this
proposal: They can be declared using the same syntax as today, and
initialization, if any, can be done in a constructor body.

```dart
// Current syntax.
class ModifierClass {
  late int x;
  external double d;
  ModifierClass(this.x);
}

// Using a primary constructor.
class ModifierClass(this.x) {
  late int x;
  external double d;
}

// Using a declaring body constructor.
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

// Using a primary constructor.
class A(final int a);
class B(super.a) extends A;

// Using a declaring body constructor.
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

// Using a primary constructor.
class const Point._(final int x, final int y);

// Using a declaring body constructor.
class Point {
  const this._(final int x, final int y);
}
```

Note that the class header contains syntax that resembles the constructor
declaration, which may be helpful when reading the code.

With the primary constructor, the modifier `const` could have been
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

The modifier `final` on a parameter in a declaring constructor specifies
that the instance variable declaration which is induced by this declaring
constructor parameter is `final`.

In the case where the declaration is an `extension type`, the modifier
`final` on the representation variable can be specified or omitted. Note
that an extension type declaration is specified to use a primary
constructor (in that case there is no other choice, it is in the grammar
rules):

```dart
// Using a primary constructor.
extension type I.name(int x);
```

Optional parameters can be declared as usual in a declaring constructor,
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

// Using a declaring body constructor.
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

// Using a primary constructor.
class Point(var int x, {required var int y});

// Using a declaring body constructor.
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

// Using a primary constructor.
class const D<TypeVariable extends Bound>.named(
  var int x, [
  var int y = 0,
]) extends A with M implements B, C;

// Using a declaring body constructor.
class D<TypeVariable extends Bound> extends A with M implements B, C {
  const this.named(
    var int x, [
    var int y = 0,
  ]);
}
```

It is possible to specify assertions on a declaring constructor, just like
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

// Using a declaring body constructor.
class Point {
  this(var int x, var int y): assert(0 <= x && x <= y * y);
}
```

When using a declaring body constructor it is possible to use an
initializer list in order to invoke a superconstructor and/or initialize
some explicitly declared instance variables with a computed value. The
declaring header constructor can have the same elements, but they are
declared in the class body.

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

// Using declaring constructors.
class const A.someName(final int x);

class B extends A {
  final String s1;
  const this(int x, int y, {required final String s2})
      : s1 = y.toString(),
        assert(s2.isNotEmpty),
        super.someName(x + 1);
}
```

A formal parameter of a declaring constructor which does not have the
modifier `var` or `final` does not implicitly induce an instance
variable. This makes it possible to use a declaring constructor (thus
avoiding the duplication of instance variable names and types) even in the
case where some parameters should not introduce any instance variables (so
they are just "normal" parameters).

With a declaring header constructor (aka a primary constructor), the formal
parameters in the header are introduced into a new scope, known as the
_primary initializer scope_.  This scope is inserted as the current scope
in several locations. In particular, it is _not_ the enclosing scope for
the body scope of the class, even though it is located syntactically in the
class header. It is actually the other way around, namely, the class body
scope is the enclosing scope for the primary initializer scope.

The primary initializer scope is the current scope for the initializing
expression of each non-late instance variable declaration in the class
body, if any. Similarly, the primary initializer scope is the current scope
for the initializer list in the body part of the primary constructor, if
any.

In other words, when a class has a primary constructor, each of the
initializing expressions of a non-late instance variable has the same
declarations in scope as the initializer list would have if it had been a
regular (non-declaring) constructor in the body. This is convenient, and it
makes refactorings from one to another kind of constructor simpler and
safer.

```dart
// Current syntax.
class DeltaPoint {
  final int x;
  final int y;
  DeltaPoint(this.x, int delta): y = x + delta;
}

// Using an declaring body constructor.
class DeltaPoint {
  final int y;
  this(final int x, int delta) : y = x + delta;
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
evaluated during the execution of the declaring header constructor, such
that the value of a variable like `delta` is only used at a point in time
where it exists.

This can only work if the primary constructor is guaranteed to be
executed. Hence the rule, mentioned above, that there cannot be any other
non-redirecting generative constructors in a class that has a primary
constructor.

This further motivates the special terminology where a declaring header
constructor is known as a primary constructor as well: The _primary_
constructor is more powerful than other declaring constructors because it
changes the scoping for specific locations in the entire class body.

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

// Using a declaring body constructor.
class A {
  this(String _);
}

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
  }) : z = y + 1,
       w = const <Never>[],
       super('Something') {
    // ... a normal constructor body ...
  }
}
```

Note that the version with a primary constructor can initialize `z` in the
declaration itself, whereas the two other versions need to use an element
in the initializer list of the constructor to initialize `z`. This is
necessary because `y` isn't in scope in those two cases. Moreover, there
cannot be other non-redirecting generative constructors when there is a
primary constructor, but in the two other versions we could add another
non-redirecting generative constructor which could initialize `w` with some
other value, in which case we must also initialize `w` as shown in the
three cases.

Moreover, we may get rid of all those occurrences of `required` in the
situation where it is a compile-time error to not have them, but that is a
separate proposal, [here][inferred-required] or [here][simpler-parameters].

[inferred-required]: https://github.com/dart-lang/language/blob/main/working/0015-infer-required/feature-specification.md
[simpler-parameters]: https://github.com/dart-lang/language/blob/main/working/simpler-parameters/feature-specification.md

## Specification

### Syntax

The grammar is modified as follows. Note that the changes include support
for extension type declarations, because they're intended to use declaring
constructors as well.

```ebnf
<classDeclaration> ::= // First alternative modified.
     (<classModifiers> | <mixinClassModifiers>)
     'class' <classNamePart> <superclass>? <interfaces>? <classBody>
   | ...;

<primaryConstructorNoConst> ::= // New rule.
     <typeIdentifier> <typeParameters>?
     ('.' <identifierOrNew>)? <declaringParameterList>

<classNamePart> ::= // New rule.
     'const'? <primaryConstructorNoConst>
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
     <constructorName> <formalParameterList>
   | <declaringConstructorSignature>;

<declaringConstructorSignature> ::= // New rule.
     'this' ('.' <identifierOrNew>)? <declaringParameterList>?;

<constantConstructorSignature> ::= // Modified rule.
     'const' <constructorName> <formalParameterList>
   | <declaringConstantConstructorSignature>;

<declaringConstantConstructorSignature> ::= // New rule.
     'const' 'this' ('.' <identifierOrNew>)? <declaringParameterList>;

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

A _declaring constructor_ declaration is a declaration that contains a
`<declaringConstructorSignature>` with a `<declaringParameterList>`, or a
declaration that contains a `<declaringConstantConstructorSignature>`, or
it is a `<primaryConstructorNoConst>` in the header of a class, enum, or
extension type declaration, together with a declaration in the body that
contains a `<declaringConstructorSignature>` *(which does not contain a
`<declaringParameterList>`, because that's an error)*.

A class declaration whose class body is `;` is treated as a class
declaration whose class body is `{}`.

Let _D_ be a class, extension type, or enum declaration.

A compile-time error occurs if _D_ includes a `<classNamePart>` that
contains a `<primaryConstructorNoConst>`, and the body of _D_ contains a
`<declaringConstructorSignature>` that contains a
`<declaringParameterList>`.

*It is an error to have a declaring parameter list both in the header and
in the body.*

A compile-time error occurs if _D_ includes a `<classNamePart>` that
does not contain a `<primaryConstructorNoConst>`, and the body of _D_
contains a `<declaringConstructorSignature>` that does not
contain a `<declaringParameterList>`.

*It is an error to have a declaring constructor in the class body, but
no declaring parameter list, neither in the header nor in the body.*

*The keyword `const` can be specified in the class header when it contains
a primary constructor, and in this case `const` can not be specified in the
part of the primary constructor that occurs in the body (that is, the
declaration that starts with `this` and contains an initializer list and/or
a constructor body, if any). The rationale is that when the class header
contains any parts of a declaring constructor, the class header must be the
location where all parts of the signature of that primary constructor are
specified.*

A compile-time error occurs if a class contains two or more declarations of
a declaring constructor.

*The meaning of a declaring constructor is defined in terms of rewriting it
to a body constructor (a regular one, not declaring) and zero or more
instance variable declarations. This implies that there is a class body
when there is a declaring constructor. We do not wish to define declaring
constructors such that the absence or presence of a declaring constructor
can change the length of the superclass chain, and hence `class C;` has a
class body just like `class C(int i);` and just like `class C extends
Object {}`, and all three of them have `Object` as their direct
superclass.*

A compile-time error occurs if a `<defaultDeclaringNamedParameter>` has the
modifier `required` as well as a default value.

### Static processing

The name of a primary constructor of the form 
`'const'? id1 <typeParameters>? <declaringParameterList>` is `id1` *(that
is, the same as the name of the class)*.
The name of a primary constructor of the form 
`'const'? id1 <typeParameters>? '.' id2 <declaringParameterList>` is 
`id1.id2`.

A compile-time error occurs if a class, enum, or extension type has a
primary constructor whose name is also the name of a constructor declared
in the body.

Consider a class, enum, or extension type declaration _D_ with a declaring
header constructor, also known as a primary constructor *(note that it
cannot be a `<mixinApplicationClass>`, because that kind of declaration
does not support declaring constructors, that is a syntax error)*. This
declaration is treated as a class, enum, respectively extension type
declaration without a declaring header constructor which is obtained as
described in the following. This determines the dynamic semantics of a
declaring header constructor, and simiarly for a declaring body
constructor.

A compile-time error occurs if the body of _D_ contains a non-redirecting
generative constructor, unless _D_ is an extension type.

*For a class or an enum declaration, this ensures that every generative
constructor invocation will invoke the declaring header constructor, either
directly or via a series of generative redirecting constructors. This is
required in order to allow initializers with no access to `this` to use the
parameters.*

If _D_ is an extension type, it is a compile-time error if _D_ does not
contain a declaring constructor that has exactly one declaring parameter
which is `final`.

*For an extension type, this ensures that the name and type of the
representation variable is well-defined, and existing rules about final
instance variables ensure that every other non-redirecting generative
constructor will initialize the representation variable. Moreover, there
are no initializing expressions of any instance variable declarations, so
there is no conflict about the meaning of names in such initializing
expressions. This means that we can allow those other non-redirecting
generative constructors to coexist with a primary constructor.*

A compile-time error occurs if the name of the primary constructor is the
same as the name of a constructor (declaring or not) in the body.

*Moreover, it is an error if two constructor declarations in the body,
declaring or otherwise, have the same name. This is just restating a
compile-time error that we already have.*

The declaring parameter list of the declaring header constructor introduces
a new scope, the _primary initializer scope_, whose enclosing scope is the
body scope of _D_. Every primary parameter is entered into this scope.

The same parameter list also introduces the _primary parameter scope_,
whose enclosing scope is also the body scope of the class. Every primary
parameter which is not declaring, not initializing, and not a super
parameter is entered into this scope.

The primary initializer scope is the current scope for the initializing
expression, if any, of each non-late instance variable declaration. It is
also the current scope for the initializer list in the body part of the
declaring header constructor, if any.

The primary parameter scope is the current scope for the body of the body
part of the declaring header constructor, if any.

*Note that the _formal parameter initializer scope_ of a normal
(non-declaring) constructor works in very much the same way as the primary
initializer scope of a primary constructor. The difference is that the
latter is the current scope for the initializing expressions of all
non-late instance variable declarations, in addition to the initializer
list of the body part of the constructor.*

*The point is that the constructor body should have access to the "regular"
parameters, but it should have access to the instance variables rather than
the declaring or initializing parameters with the same names, also in the
case of a declaring header constructor with a body in the class body. With
an in-body declaring constructor, these rules just repeat what is already
specified for the scoping of other constructors. For example:*

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
non-declaring constructor. Note that this only occurs when the class has a
primary constructor, it does not occur when the class has an in-body
declaring constructor, or when it does not have any declaring constructors
at all. There is no access to any constructor parameters in the
initializing expression of a non-late instance variable in those cases.
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

The following errors apply to formal parameters of a declaring constructor,
be it in the header or in the body. Let _p_ be a formal parameter of a
declaring constructor in a class, enum, or extension type declaration _D_
named `C`:

A compile-time error occurs if _p_ contains a term of the form `this.v`, or
`super.v` where `v` is an identifier, and _p_ has the modifier
`covariant`. *For example, `required covariant int this.v` is an error. The
reason for this error is that the modifier `covariant` must be specified on
the declaration of `v` which is known to exist, not on the parameter.*

A compile-time error occurs if _p_ has both of the modifiers `covariant`
and `final`. *A final instance variable cannot be covariant, because being
covariant is a property of the setter.*

A compile-time error occurs if _p_ has the modifier `covariant`, but
neither `var` nor `final`. *This parameter does not induce an instance
variable, so there is no setter.*

Conversely, it is not an error for the modifier `covariant` to occur on a
declaring formal parameter _p_ of a declaring constructor. This extends the
existing allowlist of places where `covariant` can occur.

The following applies to both the header and the body form of declaring
constructors.

The semantics of the declaring constructor is found in the following steps,
where _D_ is the class, extension type, or enum declaration in the program
that includes a declaring constructor, and _D2_ is the result of the
derivation of the semantics of _D_. The derivation step will delete
elements that amount to the declaring constructor; it will add a new
constructor _k_; and it will add zero or more instance variable
declarations.

Where no processing is mentioned below, _D2_ is identical to _D_. Changes
occur as follows:

Assume that `p` is an optional formal parameter in _D_ which has the
modifier `var` or the modifier `final` *(that is, `p` is a declaring
parameter)*.

Assume that the combined member signature for a getter with the same name
as `p` from the superinterfaces of _D_ exists, and has return type `T`. In
that case the parameter `p` has declared type `T` as well.

*In other words, an instance variable introduced by a declaring parameter
is subject to override inference, just like an explicitly declared instance
variable.*

Otherwise, assume that `p` does not have a declared type, but it does have
a default value whose static type in the empty context is a type (not a
type schema) `T` which is not `Null`. In that case `p` is considered to
have the declared type `T`. When `T` is `Null`, `p` is considered to have
the declared type `Object?`. If `p` does not have a declared type nor a
default value then `p` is considered to have the declared type `Object?`.

*Dart has traditionally assumed the type `dynamic` in such situations. We
have chosen the more strictly checked type `Object?` instead, in order to
avoid introducing run-time type checking implicitly.*

The current scope of the formal parameter list of the declaring constructor
in _D_ is the body scope of the class.

*We need to ensure that the meaning of default value expressions is
well-defined, taking into account that a declaring header constructor is
physically located in a different scope than in-body constructors. We do
this by specifying the current scope explicitly as the body scope, in spite
of the fact that the declaring constructor is actually placed outside the
braces that delimit the class body.*

Next, _k_ has the modifier `const` iff the keyword `const` occurs just
before the name of _D_ or before `this`, or if _D_ is an `enum`
declaration.

Consider the case where _D_ is a declaring header constructor. If the name
`C` in _D_ and the type parameter list, if any, is followed by `.id` where
`id` is an identifier then _k_ has the name `C.id`. If it is followed by
`.new` then _k_ has the name `C`. If it is not followed by `.`  then _k_
has the name `C`. If it exists, _D2_ omits the part derived from
`'.' <identifierOrNew>` that follows the name and type parameter list, if
any, in _D_. Moreover, _D2_ omits the formal parameter list _L_ that
follows the name, type parameter list, if any, and `.id`, if any.

Otherwise, _D_ is a declaring body constructor. If the reserved word `this`
is followed by `.id` where `id` is an identifier then _k_ has the name
`C.id`. If it is followed by `.new` then _k_ has the name `C`. If it is not
followed by `.` then _k_ has the name `C`.

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
parameter, and in the case where an instance variable is implicitly
induced, the DartDoc comment is also added to that instance variable.

If there is an initializer list following the formal parameter list _L_
then _k_ has an initializer list with the same elements in the same order.

Finally, _k_ is added to _D2_, and _D_ is replaced by _D2_.

### Discussion

This proposal includes support for adding the declaring header parameters to
the scope of the class, as proposed by Slava Egorov.

The scoping structure is highly unusual because the formal parameter list
of a primary constructor is located outside the class body, and still the
corresponding scopes (the primary initializer scope and the primary
parameter scope) have the class body scope as their enclosing
scope. However, this causes the scoping to be the same for elements in the
initializer list and in the initializing expressions of non-late instance
variables, and that allows us to move code from an initializer list to a
variable initializer and vice versa without worrying about changing the
meaning of the code. This in turn makes it easier to change a regular
(non-declaring) constructor to a primary constructor, or vice versa. So we
assume that the unusual scoping structure will make sense in practice.

The proposal allows an `enum` declaration to include the modifier `const`
just before the name of the declaration when it has a primary constructor,
but it also allows this keyword to be omitted. The specified constructor
will be constant in both cases. This differs from the treatment of regular
(non-declaring) constructors in an `enum` declaration: They _must_ have the
modifier `const`, it is never inferred. This discrepancy was included
because the syntax `enum const E(String s) {...}` seems redundant because
`enum` implies that every constructor must be constant. This is not the
case in the body where a constructor declaration may be physically pretty
far removed from any syntactic hint that the constructor must be constant
(if we can't see the word `enum` then we may not know that it is that kind
of declaration, and the constructor might be non-const).

### Changelog

1.9 - July 31, 2025

* Change the scoping such that non-late initializing expressions have the
  primary constructor parameters as the enclosing scope.

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
