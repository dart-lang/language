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

A primary constructor allows us to define the same class much more
concisely:

```dart
// A declaration with the same meaning, using a primary constructor.

class Point(int x, int y);
```

In the examples below we show the current syntax directly followed by a
declaration using a primary constructor. The meaning of the two class
declarations with the same name is always the same. Of course, we would
have a name clash if we actually put those two declarations into the same
library, so we should read the examples as "you can write this _or_ you can
write that". So the example above would be shown as follows:

```dart
class Point {
  int x;
  int y;
  Point(this.x, this.y);
}

class Point(int x, int y);
```

These examples will serve as an illustration of the proposed syntax, but
they will also illustrate the semantics of the primary constructor
declarations, because those declarations work exactly the same as the
declarations using the current syntax.

Note that an empty class body, `{}`, can be replaced by `;`.

The basic idea is that a parameter list that occurs just after the class
name specifies both a constructor declaration and a declaration of one
instance variable for each formal parameter in said parameter list.

A primary constructor cannot have a body, and it cannot have an initializer
list (and hence, it cannot have a superinitializer, e.g., `super(...)`, and
it cannot have assertions).

The motivation for these restrictions is that a primary constructor is
intended to be small and easy to read at a glance. If more machinery is
needed then it is always possible to express the same thing as a
non-primary constructor (i.e., any constructor which isn't a primary
constructor).

The parameter list uses the same syntax as constructors and other functions
(specified in the grammar by the non-terminal `<formalParameterList>`).

This implies that there is no way to indicate that the instance variable
declarations should have the modifiers `late` or `external` (because formal
parameters cannot have those modifiers). This omission is not seen as a problem
in this proposal: It is always possible to use a normal constructor declaration
and normal instance variable declarations, and it is probably a useful property
that the primary constructor uses a formal parameter syntax which is completely
like that of any other formal parameter list. Just use a normal declaration. Use
an initializing formal in a primary constructor to initialize it from the
primary constructor, if needed.

An `external` instance variable amounts to an `external` getter and an
`external` setter. Such "variables" cannot be initialized by an
initializing formal anyway, so they do not fit into the treatment implied
by a primary constructor. Just use a normal declaration.

```dart
class ModifierClass {
  late int x;
  external double d;
  ModifierClass(this.x);
}

class ModifierClass(this.x) {
  late int x;
  external double d;
}
```

`ModifierClass` as written does not make sense (`x` does not have to be
`late`), but there could be other constructors that do not initialize `x`.

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

The modifier `const` could have been placed on the class (`const class`)
rather than on the class name. This proposal puts it on the class name
because the notion of a "constant class" conflicts with with actual
semantics: It is the constructor which is constant because it is able to be
invoked during constant expression evaluation; it can also be invoked at
run time, and there could be other (non-constant) constructors. This means
that it is at least potentially confusing to say that it is a "constant
class", but it is consistent with the rest of the language to say that this
particular primary constructor is a "constant constructor". Hence `class
const Name` rather than `const class Name`.

The modifier `final` on a parameter in a primary constructor has no meaning
for the parameter itself, because there is no scope where the parameter can
be accessed. Hence, this modifier is used to specify that the instance
variables declared by this primary constructor are `final`.

In the case where the constructor is constant, and in the case where the
declaration is an `inline` class or an `enum` declaration, the modifier
`final` on every instance variable is required. Hence, it can be omitted:

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

enum E {
  one('a'),
  two('b');

  final String s;
  const E(this.s);
}

enum E(String s) { one('a'), two('b') }
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

<enumType> ::= // Modified rule.
     'enum' <enumNamePart> <mixins>? <interfaces>? '{'
        <enumEntry> (',' <enumEntry>)* (',')?
        (';' (<metadata> <classMemberDeclaration>)*)?
     '}';

<enumNamePart> ::= // New rule.
     <constructorName> <typeParameters>? <formalParameterList>
   | <typeWithParameters>;
```

The word `inline` is now used in the grammar, but it is not a reserved word
or a built-in identifier.

### Static processing

A class declaration with a primary constructor *(including `inline`, but
not `<mixinApplicationClass>`, because the grammar rules do not include
those)* is desugared to a class declaration without a primary
constructor. An enum declaration with a primary constructor is desugared
using the same steps. This determines the static analysis and dynamic
semantics of a primary constructor.

*In other words, there is no other semantics than the desugaring. When
desugared, the resulting class declaration is treated exactly the same as
it would have been if the developer had written the result of the
desugaring step in the first place.*

A compile-time error occurs if a formal parameter that contains a
term of the form `this.v`, or `super.v` where `v` is an identifier has the
modifier `covariant`. *For example, `required covariant int this.v` is an
error.*

Conversely, it is not an error for the modifier `covariant` to occur on
other formal parameters of a primary constructor. *This extends the
existing whitelist of places where `covariant` can occur.*

The desugaring consists of the following steps, where _D_ is the class or
enum declaration in the program that includes a primary constructor, and
_D2_ is the result of desugaring. The desugaring step will delete elements
that amount to the primary constructor, and it will add a new constructor
_k_.

Where no processing is mentioned below, _D2_ is identical to _D_. Changes
occur as follows:

The current scope of the formal parameter list of the primary constructor
in _D_ is the current scope of the class/enum declaration *(in other words,
the default values cannot see declarations in the class body)*.  Every
default value in the primary constructor of _D_ is replaced by a fresh
private name `_n`, and a constant variable named `_n` is added to the
top-level of the current library. *(This means that we can move the
parameter declarations including the default value without changing its
meaning.)*

Next, _k_ is a constant constructor iff the keyword `const` occurs just
before the class name in the header of _D_, or _D_ is an `enum`
declaration.

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
  in _L_ is `final`, or _D_ has the modifier `inline` or is an `enum`
  declaration, or the modifier `const` occurs just before the class name in
  _D_.  In all cases, if `p` has the modifier `covariant` then this
  modifier is removed from the parameter in _L2_, and it is added to the
  instance variable declaration named `p`.

Finally, _k_ is added to _D2_.

### Discussion

There was a [proposal from Bob][] that the primary constructor should be
expressed at the end of the class header, in order to avoid readability
issues in the case where the superinterfaces contain a lot of text. It
would then use the keyword `new` or `const`, optionally followed by `'.'
<identifier>`, just before the `(` of the primary constructor parameter
list:

[proposal from Bob]: https://github.com/dart-lang/language/issues/2364#issuecomment-1203071697

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
However, the proposal has not been included in this proposal. One reason is
that it could be better to use a non-primary constructor whenever there is
so much text. Also, it could be helpful to be able to search for the named
constructor using `D.named`, and that would fail if we use the approach
where it occurs as `new.named` or `const.named` because that particular
constructor has been expressed as a primary constructor.

A variant of this idea, from Leaf, is that we could allow one constructor
in a class with no primary constructor in the header to be marked as a
"primary constructor in the body". This would allow the constructor to have
a body and an initializer list. As a strawman, let's say that we do this by
adding the reserved word `var` in front of a normal constructor
declaration:

```dart
class D<TypeVariable extends Bound> extends A with M implements B, C {
  int i;

  var D.named(
    LongTypeExpression x1,
    LongTypeExpression x2,
    LongTypeExpression x3,
    LongTypeExpression x4,
    LongTypeExpression x5,
  ) :
      i = 1,
      assert(x1 != x2),
      super.name(x3, y: x4) {
    ... // Normal constructor body.
  }

  ... // Lots of stuff.
}
```

Presumably, a `var` constructor, if present, should occur right next to the
instance variable declarations, such that it is immediately visible
(because the first word in that constructor declaration is `var`) that this
construct will introduce instance variables.

The only special thing about a `var` constructor is that the non-super,
non-this parameters are subject to the same processing as in a primary
constructor, that is, each of them will introduce an instance variable.
This proposal does not include that feature, but `var` constructors are
probably completely compatible with primary constructors as specified
here.

### Changelog

1.0 - April 28, 2023

* First version of this document released.
