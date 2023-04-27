# Primary Constructors

Author: Erik Ernst

Status: Draft

Version: 1.0

Experiment flag: primary-constructors

This document specifies _primary constructors_. This is a feature that allows
one constructor and a set of instance variables to be specified in a concise
form in the header of the declaration. In order to use this feature, the given
constructor must satisfy certain constraints, e.g., it cannot have a body.

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

## Introduction

Primary constructors is a conciseness feature. It does not provide any new
semantics at all, it just allows us to express something which is already
possible in Dart using a less verbose notation. Here is a simple example:

```dart
// Current syntax.

class Point {
  int x;
  int y;
  Point(this.x, this.y);
}

// Same thing using a primary constructor.

class Point(int x, int y);
```

These examples will serve as an illustration of the proposed syntax, but
they will also show the semantics of the primary constructor declarations,
because they will work exactly as the example using the current syntax.

Note that an empty class body, `{}`, can be replaced by `;`.

The idea is that a parameter list that occurs just after the class name
specifies both a constructor declaration and a declaration of one instance
variable for each formal parameter in said parameter list.

A primary constructor cannot have a body, and it cannot have an initializer
list (and hence, it cannot have a superinitializer, e.g., `super(...)`, and
it cannot have assertions). 

The motivation for these restrictions is that a primary constructor is
intended to be small and easy to read at a glance. If more machinery is
needed then it is always possible to express the same thing as a
non-primary constructor (i.e., any constructor which isn't a primary
constructor).

The formal parameter declarations use the regular syntax, specified in the
grammar by the non-terminal `<formalParameterList>`.

This implies that there is no way to indicate that the instance variable
declarations should have the modifiers `covariant`, `late`, or `external`
(because formal parameters cannot have those modifiers). This omission is
not seen as a problem in this proposal: It is always possible to use a
normal constructor declaration and normal instance variable declarations,
and it is probably a useful property that the primary constructor uses a
formal parameter syntax which is completely like that of any other formal
parameter list. Just use a normal declaration. Use an initializing formal
in a primary constructor to initialize it from the primary constructor, if
needed.

An `external` instance variable amounts to an `external` getter and an
`external` setter. Such "variables" cannot be initialized by an
initializing formal anyway, so they do not fit into the treatment implied
by a primary constructor. Just use a normal declaration.

```dart
class LaCo {
  covariant late int x;
  external double d;
  LaCo(this.x);
}

class LaCo(this.x) {
  covariant late int x;
  external double d;
}
```

Super parameters can be declared in the same way as in non-primary
constructors:

```dart
class A {
  final int a;
  A(this.a);
}

class B extends A {
  B(super.a);
}

class A(final int a);
class B(super.a) extends A;
```

It could be argued that primary constructors should support arbitrary
superinvocations using the specified superclass:

```dart
class B extends A { // OK.
  B(int a): super(a);
}

class B(int a) extends A(a); // Could be supported, but isn't!
```

This is not supported for several reasons. First, primary constructors
should be small and easy to read. Next, it is not obvious how the
superconstructor arguments would fit into a mixin application (e.g., when
the superclass is `A with M1, M2`), or how readable it would be if the
superconstructor is named (`class B(int a) extends A.name(a);`). For
instance, would it be obvious to all readers that the superclass is `A` and
not `A.name`, and that all other constructors than the primary constructor
will ignore the implied superinitialization `super.name(a)` and do their
own thing (which might be implicit).

Next, the constructor can be named, and it can be constant:

```dart
class Point {
  final int x;
  final int y;
  const Point._(this.x, this.y);
}

class const Point._(final int x, final int y);
```

Note that the class header contains syntax that resembles the constructor
declaration, which may be helpful when reading the code.

The modifier `final` on a parameter in a primary constructor has no meaning
for the parameter itself, because there is no scope where the parameter can
be accessed. Hence, this modifier is used to specify that the instance
variables declared by this primary constructor are `final`.

In the case where the constructor is constant, and in the case where the class
is an inline class, the modifier `final` on every instance variable is 
required. Hence, it can be omitted:

```dart
inline class I {
  final int x;
  I.name(this.x);
}

inline class I.name(int x);

class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
}

class const Point(int x, int y);
```

This mechanism follows an existing pattern, where `const` modifiers can be
omitted in the case where the immediaty syntactic context implies that this
modifier _must_ be present. For example `const [const C()]` can be written
as `const [C()]`. In the examples above, the parameter-and-variable
declarations `final int x` and `final int y` are written as `int x` and
`int y`, and this is allowed because it would be a compile-time error to
omit `final` in an `inline` class, and in a class with a constant
constructor. In other words, when we see `inline` on the class or `const`
on the class name, we know that `final` is implied on all instance
variables.

A proposal which was mentioned during the discussions about primary
constructors was that the keyword `final` could be used in order to specify
that all instance variables introduced by the primary constructor are
`final` (but the constructor wouldn't be constant, and hence there's more
freedom in the declaration of the rest of the class). However, that
proposal is not included here, because it may be a source of confusion that
`final` may also occur as a modifier on the class itself, and also because
the resulting class header does not contain syntax which is already similar
to a non-primary constructor declaration.
`class final Point(int x, int y);` cannot use the similarity to a
non-primary constructor declaration to justify the keyword `final`.

```dart
class Point {
  final int x;
  final int y;
  Point(this.x, this.y);
}

class final Point(int x, int y); // Not supported!
```

Optional parameters can be declared as usual in a primary constructor, with
default values that must be constant as usual:

```dart
class Point {
  int x;
  int y;
  Point(this.x, [this.y = 0]);
}

class Point(int x, [int y = 0]);
```

Similarly for named parameters, required or not:

```dart
class Point {
  int x;
  int y;
  Point(this.x, {required this.y});
}

class Point(int x, {required int y});
```

The class header can have additional elements, just like class headers
where there is no primary constructor:

```dart
class D<TypeVariable extends Bound> extends A with M implements B, C {
  final int x;
  final int y;
  const D.named(this.x, [this.y = 0]);
}

class const D.named<TypeVariable extends Bound>(int x, [int y = 0])
    extends A with M implements B, C;
```

There was a proposal that the primary constructor should be expressed at
the end of the class header, in order to avoid readability issues in the
case where the superinterfaces contain a lot of text. It would then use
the keyword `new` or `const`, optionally followed by `'.' <identifier>`,
just before the `(` of the primary constructor parameter list:

```dart
class D<TypeVariable extends Bound> extends A with M implements B, C
    const.named(
  LongTypeExpression x1,
  LongTypeExpression x2,
  LongTypeExpression x3,
  LongTypeExpression x4,
  LongTypeExpression x5,
) {
  ... // Lots of stuff.
}
```

That proposal may certainly be helpful in the case where the primary
constructor receives a large number of arguments with long types, etc.
However, the proposal has not been included here. One reason is that it
could be better to use a non-primary constructor whenever there is so much
text. Also, it could be helpful to be able to search for the named
constructor using `D.named`, and that would fail if we use the approach
where it occurs as `new.named` or `const.named` because that particular
constructor has been expressed as a primary constructor.

## Specification

### Syntax

The grammar is modified as follows. Note that the changes include
support for inline classes, because they're intended to use primary
constructors as well.

```
 <topLevelDefinition> ::=
     <classDeclaration>
   | <inlineClassDeclaration> // New alternative.
   | ...;

<classDeclaration> ::= // First alternative modified.
     (<classModifiers> | <mixinClassModifiers>)
     'class' <classNamePart> <superclass>? <interfaces>? <classBody>
   | ...;

<classNamePart> ::= // New rule.
     'const'? <constructorName> <typeParameters>? <formalParameterList>
   | <typeWithParameters>;

<classBody> ::= // New rule.
     '{' (<metadata> <classMemberDeclaration>)* '}'
   | ';';

<inlineClassDeclaration> ::=
     'final'? 'inline' 'class' <classNamePart> <interfaces>? <inlineClassBody>;

<inlineClassBody> ::=
     '{' (<metadata> <inlineMemberDeclaration>)* '}'
   | ';';

<inlineMemberDeclaration> ::= <classMemberDeclaration>;
```

The word `inline` is now used in the grammar, but it is not a reserved word
or a built-in identifier.

### Static processing

A class declaration (of any kind including `inline`) with a primary
constructor is desugared to a class declaration without a primary
constructor. This determines the static analysis and dynamic semantics of
the primary constructor.

*In other words, there is no other semantics than the desugaring. When
desugared, the resulting class declaration is treated exactly the same as
it would have been if the developer had written the result of the
desugaring step in the first place.*

The desugaring consists of the following steps, where _D_ is the class
declaration in the program that includes a primary constructor, and _D2_ is
the result of the desugaring. The desugaring step will delete elements
that amount to the primary constructor, and it will add a new constructor
_k_.

Where no processing is mentioned below, _D2_ is identical to _D_. Changes
occur as follows:

_k_ is a constant constructor iff the keyword `const` occurs just before
the class name in _D_.

If the class name `C` in _D_ is followed by `.id` where `id` is an
identifier then _k_ has the name `C.id`. If it is followed by `.new` then
_k_ has the name `C`. If the class name is not followed by `.` then _k_ has
the name `C`.

If it exists, _D2_ omits the part derived from `'.' <identifierOrNew>` that
follows the class name in _D_.

_D2_ omits the formal parameter list _L_ that follows the class name and
possibly `.id` in _D_.

The formal parameter list _L2_ of _k_ is identical to _L_, except that each
formal parameter is processed as follows.

In particular, the formal parameters in _L_ and _L2_ occur in the same
order, and mandatory (respectively optional) positional parameters remain
mandatory (respectively optional, with the same default value, if any), and
named parameters preserve the name and the property of being `required`.

- An initializing formal parameter *(e.g., `this.x`)* is copied from _L_ to
  _L2_ without changes.
- A super parameter is copied from _L_ to _L2_ without changes.
- A formal parameter of the form `T p` or `final T p` where `T` is a type
  and `p` is an identifier is replaced in _L2_ by `this.p`. Also, an
  instance variable declaration of the form `T p;` or `final T p;` is added
  to _D2_. The instance variable has the modifier `final` if the parameter
  in _L_ is `final`, or the class has the modifier `inline`, or the
  modifier `const` occurs just before the class name in _D_.

Finally, _k_ is added to _D2_.

### Changelog

1.0 - April 27, 2023

* First version of this document released.
