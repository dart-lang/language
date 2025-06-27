# Primary Constructors

Author: Erik Ernst

Status: Draft

Version: 1.5

Experiment flag: primary-constructors

This document specifies _primary constructors_. This is a feature that
allows one constructor and a set of instance variables to be specified in a
concise form in the header of the declaration, or in the body. In order to
use this feature, the given constructor must satisfy certain constraints.
For example, a primary constructor in the header cannot have a body.

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
class Point(int x, int y);
```

A primary body constructor is slightly less concise, but it allows for
an initializer list and a superinitializer and a body. The previous
example would look as follows using a primary body constructor:

```dart
// A declaration with the same meaning, using a primary body constructor.
class Point {
  this(int x, int y);
}
```

In the examples below we show the current syntax directly followed by a
declaration using a primary constructor. The meaning of the two class
declarations with the same name is always the same. Of course, we would
have a name clash if we actually put those two declarations into the same
library, so we should read the examples as "you can write this _or_ you can
write that". So the example above would be shown as follows:

```dart
// Current syntax.
class Point {
  int x;
  int y;
  Point(this.x, this.y);
}

// Using a primary header constructor.
class Point(int x, int y);

// Using a primary body constructor.
class Point {
  this(int x, int y);
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
parameter list.

A primary header constructor cannot have a body, and it cannot have an normal
initializer list (and hence, it cannot have a superinitializer, e.g.,
`super.name(...)`). However, it can have assertions, it can have
initializing formals (`this.p`) and it can have super parameters
(`super.p`).

The motivation for these restrictions is that a primary constructor is
intended to be small and easy to read at a glance. If more machinery is
needed then it is always possible to express the same thing as a body
constructor.

The parameter list of a primary header constructor uses the same syntax as
constructors and other functions (specified in the grammar by the
non-terminal `<formalParameterList>`).

A primary body constructor can have a body and an initializer list as well
as initializing formals and super parameters, just like other constructors
in the body. It only differs from those other constructors in that a
parameter which is not an initializing formal and not a super parameter
serves to declare the formal parameter and the corresponding instance
variable.

The parameter list of a primary body constructor uses the same syntax as
constructors and other functions, except that it also supports a new
modifier, `novar`, indicating that the given parameter does not introduce
an instance variable (that is, this is just a regular parameter).

There is no way to indicate that the instance variable declarations should
have the modifiers `late` or `external` (because formal parameters cannot
have those modifiers). This omission is not seen as a problem in this
proposal: It is always possible to use a normal constructor declaration and
normal instance variable declarations, and it is probably a useful property
that the primary constructor uses a formal parameter syntax which is
completely like that of any other formal parameter list.

An `external` instance variable amounts to an `external` getter and an
`external` setter. Such "variables" cannot be initialized by an
initializing formal anyway, so they will just need to be declared using a
normal `external` variable declaration.

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

// Using a primary constructor.
class const Point._(final int x, final int y);

// Using a primary constructor.
class Point {
  const this._(final int x, final int y);
}
```

Note that the class header contains syntax that resembles the constructor
declaration, which may be helpful when reading the code.

With the primray header constructor, the modifier `const` could have been
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

The modifier `final` on a parameter in a primary constructor has the usual
effect that the parameter itself cannot be modified. However, this modifier
is also used to specify that the instance variable declaration which is
induced by this primary constructor parameter is `final`.

In the case where the constructor is constant, and in the case where the
declaration is an `extension type` or an `enum` declaration, the modifier
`final` on every instance variable is required. Hence, it can be omitted
from the formal parameter in the primary constructor, because it is implied
that this modifier must be present in the induced variable declarations in
any case:

```dart
// Current syntax.
class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
}

enum E {
  one('a'),
  two('b');

  final String s;
  const E(this.s);
}

// Using a primary header constructor.
class const Point(int x, int y);
enum E(String s) { one('a'), two('b') }

// Using a primary body constructor.
class Point {
  const this(int x, int y);
}

enum E {
  one('a'),
  two('b');

  const this(String s);
}
```

Note that an extension type declaration is specified to use a primary
header constructor (in that case there is no other choice, it is in the
grammar rules):

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
class Point(int x, [int y = 0]);

// Using a primary body constructor.
class Point {
  this(int x, [int y = 0]);
}
```

We can omit the type of an optional parameter with a default value,
in which case the type is inferred from the default value:

```dart
// Infer type from default value, in header.
class Point(int x, [y = 0]);

// Infer type from default value, in body.
class Point {
  this(int x, [y = 0]);
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
class Point(int x, {required int y});

// Using a primary body constructor.
class Point
  this(int x, {required int y});
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
class const D<TypeVariable extends Bound>.named(int x, [int y = 0])
    extends A with M implements B, C;

// Using a primary body constructor.
class D<TypeVariable extends Bound> extends A with M implements B, C {
  const this.named(int x, [int y = 0]);
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
class Point(int x, int y): assert(0 <= x && x <= y * y);

// Using a primary body constructor.
class Point {
  this(int x, int y): assert(0 <= x && x <= y * y);
}
```

Finally, when using a primary body constructor it is possible to use an
initializer list in order to invoke a superconstructor and/or initialize
some explicitly declared instance variables with a computed value.

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
class const A.someName(int x);

class B extends A {
  final String s1;
  const this(novar int x, novar int y, {required String s2})
      : s1 = y.toString(), assert(s2.isNotEmpty), super.someName(x + 1);
}
```

A formal parameter of a primary body constructor which has the modifier
`novar` does not implicitly induce an instance variable. This makes it
possible to use a primary constructor (thus avoiding the duplication of
instance variable names and types) even in the case where some parameters
should not introduce any instance variables (so they are just "normal"
parameters).

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
  external int y;
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
    // A normal constructor body.
  }
}

// Using a primary body constructor.
class A(novar String _);

class E extends A {
  external int y;
  int z;
  final List<String> w;

  primary E({
    required LongTypeExpression x1,
    required LongTypeExpression x2,
    required LongTypeExpression x3,
    required LongTypeExpression x4,
    required LongTypeExpression x5,
    required LongTypeExpression x6,
    required LongTypeExpression x7,
    required LongTypeExpression x8,
    required this.y,
  }) : z = 1,
       w = const <Never>[],
       super('Something') {
    // A normal constructor body.
  }
}
```

Moreover, we may get rid of all those occurrences of `required` in the
situation where it is a compile-time error to not have them, but that is a
[separate proposal][inferred-required].

[inferred-required]: https://github.com/dart-lang/language/blob/main/working/0015-infer-required/feature-specification.md

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
     ('.' <identifierOrNew>)? <formalParameterList>
     <initializers>?

<classNamePartNoConst> ::= // New rule.
     <primaryHeaderConstructorNoConst>
   | <typeWithParameters>;

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
     'enum' <classNamePartNoConst> <mixins>? <interfaces>? '{'
        <enumEntry> (',' <enumEntry>)* (',')?
        (';' (<metadata> <classMemberDeclaration>)*)?
     '}';

<constructorName> ::= // Modified rule.
     (<typeIdentifier> | 'this') ('.' <identifierOrNew>)?

<identifierOrNew> ::=
     <identifier>
   | 'new'

<normalFormalParameterNoMetadata> ::= // Modified
     'novar'? <functionFormalParameter
   | 'novar'? <simpleFormalParameter
   | <fieldFormalParameter>
   | <superFormalParameter>
```

A class declaration whose class body is `;` is treated as a class declaration
whose class body is `{}`.

*The meaning of a primary constructor is defined in terms of rewriting it to a
body constructor and zero or more instance variable declarations. This implies
that there is a class body when there is a primary constructor. We do not wish
to define primary constructors such that the absence or presence of a primary
constructor can change the length of the superclass chain, and hence `class C;`
has a class body just like `class C(int i);` and just like `class C extends
Object {}`, and all three of them have `Object` as their direct superclass.*

### Static processing

Consider a class declaration or an extension type declaration with a
primary header constructor *(note that it cannot be a
`<mixinApplicationClass>`, because that kind of declaration does not
support primary constructors, it's just a syntax error)*. This declaration
is desugared to a class or extension type declaration without a primary
constructor. An enum declaration with a primary header constructor is
desugared using the same steps. This determines the dynamic semantics of a
primary constructor.

The following errors apply to formal parameters of a primary constructor.
Let _p_ be a formal parameter of a primary constructor in a class `C`:

A compile-time error occurs if _p_ contains a term of the form `this.v`, or
`super.v` where `v` is an identifier, and _p_ has the modifier
`covariant`. *For example, `required covariant int this.v` is an error.*

A compile-time error occurs if _p_ has both of the modifiers `covariant`
and `final`. *A final instance variable cannot be covariant, because being
covariant is a property of the setter.*

A compile-time error occurs if _p_ has both of the modifiers `covariant`
and `novar`. *A parameter with the modifier `novar` does not induce an
instance variable, so there is no variable and hence no setter.*

Conversely, it is not an error for the modifier `covariant` to occur on
another formal parameter _p_ of a primary constructor (this extends the
existing allowlist of places where `covariant` can occur).

The semantics of the primary constructor is found in the following steps,
where _D_ is the class, extension type, or enum declaration in the program
that includes a primary constructor, and _D2_ is the result of the
derivation of the semantics of _D_. The derivation step will delete
elements that amount to the primary constructor; it will add a new
constructor _k_; it will add zero or more instance variable declarations;
and it will add zero or more top-level constants *(holding parameter
default values)*.

Where no processing is mentioned below, _D2_ is identical to _D_. Changes
occur as follows:

Assume that `p` is an optional formal parameter in _D_ which is not an
initializing formal, and not a super parameter, and does not have the
modifier `novar`.

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
- A formal parameter with the modifier `novar` is copied unchanged from
  _L_ to _L2_.
- Otherwise, a formal parameter (named or positional) of the form `T p` or
  `final T p` where `T` is a type and `p` is an identifier is replaced in
  _L2_ by `this.p`, along with its default value, if any.
  Next, an instance variable declaration of the form `T p;` or `final T p;`
  is added to _D2_. The instance variable has the modifier `final` if the
  parameter in _L_ is `final`, or _D_ is an `extension type` declaration,
  or _D_ is an `enum` declaration, or the modifier `const` occurs just
  before the class name in _D_.
  In all cases, if `p` has the modifier `covariant` then this modifier is
  removed from the parameter in _L2_, and it is added to the instance
  variable declaration named `p`.

In every case, any DartDoc comments are copied along with the formal
parameter, and in the case where an instance variable is implicitly induced
the DartDoc comment is also added to that instance variable.

If there is an initializer list following the formal parameter list _L_ then
_k_ has an initializer list with the same elements in the same order.

*The current scope of the initializer list in _D_ is the body scope of the
enclosing declaration even when _D_ is a primary header constructor, which
means that they preserve their semantics when moved into the body.*

Finally, _k_ is added to _D2_, and _D_ is replaced by _D2_.

### Discussion

### Changelog

1.6 - June 27, 2025

* Explain in-header constructors as "move the parameter list", which also
  introduces support for in-header constructors with all features (initializer
  list, superinitializer, body), which will remain in the body.

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
