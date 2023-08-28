# Value classes

Author: Bob Nystrom

Status: Draft

Version 0.1

This proposal provides an easier way to author classes with *value semantics*,
and eliminates what feel like pointless uses of `const` in many cases. If you
write:

```dart
value class Rect {
  int x;
  int y;
  int width;
  int height;

  Rect(this.x, this.y, this.width, this.height);
}
```

It is roughly as if you had written:

```dart
class Rect {
  final int x;
  final int y;
  final int width;
  final int height;

  const Rect(this.x, this.y, this.width, this.height);

  @override
  bool operator ==(other) =>
      other is Rect &&
      x == other.x &&
      y == other.y &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  Rect copy({int? x, int? y, int? width, int? height}) => Rect(
    x ?? this.x,
    y ?? this.y,
    width ?? this.width,
    height ?? this.height,
  );
}
```

In addition, any calls to `Rect(...)` are implicitly treated as `const
Rect(...)` if the arguments are constant expressions so you don't have to write
`cosnt`.

## Motivation

The [single most requested feature][number one] in Dart is "[data classes][]".

[number one]: https://github.com/dart-lang/language/issues?q=is%3Aissue+is%3Aopen+sort%3Areactions-%2B1-desc

[data classes]: https://github.com/dart-lang/language/issues/314

That term encompasses a few interrelated features:

*   A terse way to define a new type with some state.
*   Minimal redundancy when defining the type's fields and a constructor to
    initialize them.
*   Instances of the type are implicitly immutable (but possibly not *deeply*
    immutable).
*   The type implicitly has *value* semantics: It implements `==` and `hashCode`
    in terms of those fields.
*   Since the type is immutable, usually some sort of `copy()` or `copyWith()`
    method that provides an easy way to make a copy of an instance with some of
    its fields changed.

The first two bullet points are useful for all kinds of classes, not just
immutable ones with value semantics, so I think are better handled by separate
features that can be combined with this proposal as well as being used with
other class declarations. [Primary constructors][] is one such proposal.

This proposal then tackles the rest of them. You put a `value` modifier on a
class declaration, and it implicitly treats all instance fields as `final`, and
gives you implementations of `==`, `hashCode`, and `copyWith()` in terms of
them.

[primary constructors]: https://github.com/dart-lang/language/pull/3023

### Applicability

While the first two bullet points are useful for almost every class out there,
the remaining features are really only useful for classes that want value
semantics. How common is that? I analyzed a large corpus of pub packages and
open source Flutter widgets and apps:

```
-- Class (178325 total) --
 126147 ( 70.740%): no equals or hashCode, all fields immutable  ===========
  38165 ( 21.402%): no equals or hashCode, some mutable fields   ====
   8008 (  4.491%): equals and hashCode, all fields immutable    =
   5476 (  3.071%): equals and hashCode, some mutable fields     =
    425 (  0.238%): only hashCode, all fields immutable          =
     58 (  0.033%): only equals, all fields immutable            =
     43 (  0.024%): only equals, some mutable fields             =
      3 (  0.002%): only hashCode, some mutable fields           =
```

While immutability is common (70% of classes), most classes that declare only
final instance fields *don't* opt into value semantics by also implementing
`==` and `hashCode`. It's not clear how many of them *would* if doing so weren't
laborious.

It does seem that around 4% of existing classes could probably use this feature.
Note that this simple analysis doesn't consider whether the classes might be
prohibited from using this feature because they inherit from other classes that
don't work with it.

### Pointless `const`

When you construct an instance of a class in Dart, you have to explicitly choose
whether to call its constructor using `const` or not. This is important because `const` constructor calls are canonicalized but others are not:

```dart
class Point {
  final int x, y;
  const Point(this.x, this.y);
}

main() {
  var a = const Point(1, 2);
  var b = const Point(1, 2);
  var c = Point(1, 2);
  var d = Point(1, 2);

  print(identical(a, b)); // "true"
  print(identical(c, d)); // "false"
}
```

Canonicalization is helpful because `identical()` is a fast path to tell if two
objects are the same. Flutter in particular relies on this to make widget tree
rebuilding faster. If it sees that a widget is `identical()` to the one it saw
in the previous build, it knows that entire subtree must be the same. This is
why the Flutter team [recommends using `const` to create widgets whenever
possible][recommend].

[recommend]: https://docs.flutter.dev/perf/best-practices#control-build-cost

Performance is great, but it's annoying that users have to explicitly *opt in*
to faster code by writing `const` everywhere. It would be great if when the
language saw:

```dart
SizedBox(height: 16)
```

It could implicitly make the constructor call `const` since the argument is. We
discussed *always* doing this in the language, but unfortunately it's a breaking
change because object identity is visible, thanks to `identical()`.

And maybe that's what you want for some types. Identity can be useful for
mutable types: It gives you a way to tell if two objects that seem to be "the
same" right now may diverge later when one is mutated.

But for immutable types with value semantics, if they look the same now, they
always will. That makes identity less useful. That's why when we added records
to the language, we avoided this annoyance. A record literal will be
automatically constant if its fields are. You never have to write `const`.

This proposal does the same thing for classes marked `value`. When invoking
a value class's constructor, if the argument expressions are all constant, then
the constructor call implicitly becomes `const`.

This means that you get canonicalization for free whenever possible without
having to remember to opt into it at constructor calls, for the classes that
support it.

## Syntax

The only syntax change is allowing `value` as a modifier on class declarations:

```
classDeclaration  ::= (classModifiers | mixinClassModifiers) 'value'? 'class'
                      typeIdentifier
                      typeParameters? superclass? interfaces?
                      '{' (metadata classMemberDeclaration)* '}'
                      | classModifiers 'mixin'? 'class' mixinApplicationClass
```

If it appears, it is right before `class`, after any other modifiers.

## Static semantics

## Instance fields

All instance field declarations in the class are treated as if they are
implicitly marked `final`. It is a compile-time error to *explicitly* mark an
instance field `final` (since it's redundant and likely indicates confusion on
the user's part).

Static fields are not implicitly final.

**TODO: This seems like a potential source of confusion. Maybe implicitly final
fields are a mistake?**

Any non-`late` instance field without an initializer at its declaration is
called a *value field*. These are the fields that will be used in the
implementations of `==`, `hashCode`, and `copyWith()`.

Other instance fields, those marked `late` or with initializers, are still
implicitly final, but are not considered value fields. These can be useful for
storing information in the object that isn't part of it's user-visible "value",
like cached data, metadata, debug info, etc..

It is a compile-time error if a value field has a private name. *Since
`copyWith()` uses named parameters to update the fields, a private name would
prevent you from updating that field's value using `copyWith()`.*

## Inheritance

Inheriting from stateful classes makes value semantics more complex. We have to
decide how the compiler-provided methods take into account instance fields from
superclasses. We must also be sensitive to what kinds of changes to a class
become breaking API changes to downstream users of the class without the
superclass author realizing.

At the same time, we don't want to place so many restrictions on value classes
that they can't be used for real-world problems in existing codebases.

The rules are:

*   A value class can only extend another value class or `Object`. *This means
    that removing `value` from an extensible class is a breaking API change.*

*   A value class may apply mixins and implement as many interfaces as it wants.

This means that every instance field in a value class that requires
initialization is declared by some value class, either itself or one of its
value class superclasses. In other words, every field the automatically
generated methods use is a value field.

When referring to the *value fields* of a value class, we mean the value fields
it declares and the value fields it inherits from other value classes.

It is a compile-time error for a value field in a class to shadow a value field
in a superclass. *Shadowing fields is never a good idea, and shadowing a value
field would make it impossible to distinguish their corresponding parameters in
`copyWith()`.*

It's reasonable to declare a value class that has no actual value fields. This
can be useful if you want it to be a base class for other value classes.

## Implicit const constructors

Since all instance fields in a value class must be final, most constructors can
and should be `const`. To make that easier, any generative constructor in a
value class is implicitly treated as being marked `const` if doing so would be
valid (including the default constructor, if applicable).

Restating the existing specification, "would be valid" means:

*   Every instance variable initializer in the class must be a constant
    expression:

    ```dart
    value class A {
      int x = 1;

      A(); // Implicitly const constructor.
    }

    value class B {
      final int x = DateTime.now().second;

      B(); // Not implicitly const constructor.
    }
    ```

*   The superclass constructor initializer, if any, must refer to a constant
    constructor:

    ```dart
    value class Base {
      Base.noConst() { print('Not constant.'); }
      const Base.yesConst();
    }

    value class A {
      int x = 1;

      A() : super.yesConst(); // Implicitly const constructor.
    }

    value class B {
      int = DateTime.now().second;

      B() : super.noConst(); // Not implicitly const constructor.
    }
    ```

*   Every expression in constructor field initializers must be potentially
    constant:

    ```dart
    value class A {
      int x;

      A() : x = 1; // Implicitly const constructor.
    }

    value class B {
      int x;

      B() : x = DateTime.now().second; // Not implicitly const constructor.
    }
    ```

## Constants

Since value class instances have no object identity (see "Identity" below), an
implementation is free to canonicalize constants or not. That in turn implies
that there is no need for a user to explicitly decide whether to invoke a value
class's const constructor with `const` or not.

Again similar to records, the compiler automatically infers whether an instance
creation of a value class creates a constant or not.

An instance creation expression that invokes a const constructor in a value
class can be a constant or potentially constant expression. It is a compile-time
constant expression if all of its type arguments are connstant type expressions
and its arguments are constant expressions, regardless of whether the call is
preceded by `const`.

*In other words, if a value class constructor call can be const, it
automatically will be. This should eliminate many annoying uses of `const` in
code like Flutter build methods, provided that common types like `EdgeInsets`,
`Text`, `SizedBox`, `Color`, etc. can be migrated to value classes.*

## Members

### `==` and `hashCode`

Value classes have value equality, which means two instances are equal if they
are the same class and all of their corresponding value fields are equal:

```dart
value class Point(int x, int y);

main() {
  var a = Point(1, 2);
  var b = Point(1, 2);
  print(a == b); // true.
}
```

A value class gets an implicit definition of `==` and `hashCode` with those
semantics. More precisely, the `==` method on value class `r` with right operand
`o` is defined as:

1.  If `o` is not an instance of `r`'s type then `false`.

    *`o` may be an instance of a _subtype_ of `r`'s type. In other words, this
    test is implemented like `o is R` where `R` is the type of `r`, including
    any type arguments used by the receiver instance. This means that `==` may
    not be symmetric if a value class is also extended.*

2.  For each pair of corresponding value fields `rf` and `of` in unspecified
    order:

    1.  If `rf == of` is `false` then `false`.

3.  Else, `true`.

*The order that fields are iterated is potentially user-visible since
user-defined `==` methods can have side effects. Most well-behaved `==`
implementations are pure. The order that fields are visited is deliberately left
unspecified so that implementations are free to reorder the field comparisons
for performance.*

The implementation of `hashCode` follows this. The hash code returned should
depend on the field values such that two instances that compare equal must have
the same hash code.

*Note that a value class that inherits from another value class tests its
inherited fields directly instead of relying on calling `super.==()` or
`super.hashCode`. This distinction mostly doesn't matter but is potentially
user visible given that there may be user-defined implementations of those
methods in the inheritance chain.*

### `copyWith()`

Since value classes are immutable, to "modify" one requires constructing a new
instance with the changed values. This can be done by calling the constructor:

```dart
main() {
  var origin = Point(0, 0);
  var oneRight = Point(1, origin.y);
}
```

That can be verbose if a value class has many fields and the copy is changing
only a few of them. To make that easier, a value class also automatically gets a
method named `copyWith()` that produces a copy of the current instance with
some values changed.

The generated `copyWith()` takes a named parameter for each of the class's value
fields. The parameter has the same name as the field and the parameter's type is
the type of the corresponding field.

The method returns a new instance of the same type as its receiver. The new
instance's field values are initialized with the values of the corresponding
arguments. If no argument is passed, then the current instance's field value is
used instead.

*If the underlying field is itself nullable, the generated `copyWith()` still
distinguishes between a passed argument overriding the value even if that value
is `null`. For example:*

```
value class MaybeInt {
  int? n;
}

main() {
  var three = MaybeInt(3);
  var nothing = three.copyWith(n: null);
  print(nothing.n); // "null".
}
```

*This means the `copyWith()` method can't strictly be expressed in terms of code
a user could write today. We could potentially allow user code to express the
same behavior by allowing non-constant default values:*

```dart
class MaybeInt {
  int? n;

  MaybeInt(this.n);

  MaybeInt copyWith({int? n = this.n}) => MaybeInt(n);
}
```

*Supporting non-const default values is not needed for this proposal.*

The new instance created by `copyWith()` does not invoke any user-defined
constructor on the value class. It's as if each value class has an implicit
hidden constructor used only by `copyWith()` that initializes all of its fields
and calls the corresponding hidden constructor on any value superclass.

### Explicit implementations

A value class implicitly gets automatic declarations of `==`, `hashCode`, and
`copyWith()`. These methods are declared and implemented directly on the value
class itself.

If a value class declaration contains an explicit declaration of one of these
methods, then the automatic implementation is not provided. *In other words, a
value class author can opt out of these automatic methods by providing their own
implementations.*

If a value class inherits a definition of one of these methods from some
superclass or mixin, then the automatically provided ones will override them.
*In other words, its as if the compiler inserts these method declarations
directly into the value class itself and doesn't inherit them from `Object`.*

## Runtime semantics

### Identity

One use case of value classes is performance. We'd like compilers to be able to
inline the memory used for an instance of a value class directly on the stack
or in the surrounding object where it is used. This means that passing an
instance of a value class around could require copying it. Since value classes
must be immutable, these potential copies are mostly not user visible.

The exception is `identical()` , which is (more or less) based on the instance's
memory address for instances of other classes. To avoid making copies
user-visible through uses of `identical()`, instances of value classes don't
have a well-defined persistent identity based on its allocation.

This is very similar to how records behave. Calling `identical()` with an
instance of a value class as an argument returns:

*   `false`, if the other argument is not an instance of the same value class.
*   `false`, if any pair of corresponding type arguments are not the same type.
*   `false`, if any pair of corresponding fields are not identical.
*   Otherwise it *may* return `true`, but is not required to.

*If an implementation can easily determine that two instances of a value class
passed to `identical()` have the same field values, then it should return
`true`. Typically, this is because the two arguments to `identical()` are
pointers pointing at the same address in memory. But if an implementation would
have to do a slower field-wise comparison to determine identity, it's probably
better to return `false` quickly.*

*In other words, if `identical()` returns `true`, then the instances are
definitely indistinguishable. But if it returns `false`, they may or may not
be.*

#### Canonicalization and structural equivalence

Since records also don't have defined identity, canonicalization was redefined
in terms of structural equivalence. We extend that definition:

Dart values *a* and *b* are *structurally equivalent* if:

*   *a* and *b* are both instances of the same value class, and they have the
    same type arguments, and each corresponding pair of instance fields are
    structurally equivalent, then *a* and *b* are structurally equivalent.

*   Otherwise, use [the existing definition of structural equivalence][structural].

[structural]: https://github.com/dart-lang/language/blob/main/accepted/3.0/records/feature-specification.md#canonicalization

## Migration

This is a new feature that doesn't affect the behavior of existing code, so
there is no breakage or necessary migration.

Users are free to write `value` on new classes, or add it to existing classes.
Note that the latter can be a breaking API change for that class:

*   If users of the class were relying on the class having separate object
    identity even when different instances have the same state, that will no
    longer work. For example, using it as a key in an `IdentityHashMap`. In
    practice, code relying on identity for correctness is rare.

*   As with adding any method to an existing class, the generated `copyWith()`
    method could collide with a method of the same name but different signature
    in a subclass.

One of the benefits of this feature is that it may allow users to eliminate
useful-but-verbose `const` keywords sprinkled throughout their Flutter code. To
get the most benefit from this, some of the most common Flutter classes would be
migrated to value classes. From analyzing the bodies of `build()` methods in a
corpus of open source code, that's:

```
-- Class (72694 total) --
  20589 ( 28.323%): EdgeInsets                                        ===
  10867 ( 14.949%): Text                                              ==
   9158 ( 12.598%): SizedBox                                          ==
   4355 (  5.991%): Icon                                              =
   2308 (  3.175%): TextStyle                                         =
   1795 (  2.469%): Color                                             =
   1745 (  2.400%): Duration                                          =
   1046 (  1.439%): Center                                            =
    790 (  1.087%): BorderRadius                                      =
    757 (  1.041%): Divider                                           =
    741 (  1.019%): InputDecoration                                   =
    738 (  1.015%): BoxDecoration                                     =
    690 (  0.949%): Padding                                           =
    659 (  0.907%): Locale                                            =
    641 (  0.882%): BoxConstraints                                    =
    632 (  0.869%): Spacer                                            =
    494 (  0.680%): Offset                                            =
    421 (  0.579%): Key                                               =
    419 (  0.576%): EdgeInsetsDirectional                             =
    408 (  0.561%): Radius                                            =
    389 (  0.535%): Size                                              =
    349 (  0.480%): MaterialApp                                       =
    278 (  0.382%): CircularProgressIndicator                         =
    231 (  0.318%): MyHomePage                                        =
    208 (  0.286%): NeverScrollableScrollPhysics                      =
    199 (  0.274%): RoundedRectangleBorder                            =
    194 (  0.267%): ValueKey<String>                                  =
    187 (  0.257%): YSpace                                            =
    182 (  0.250%): BouncingScrollPhysics                             =
    180 (  0.248%): BorderSide                                        =
    165 (  0.227%): MediaQueryData                                    =
    153 (  0.210%): SnackBar                                          =
    144 (  0.198%): StandardMessageCodec                              =
    141 (  0.194%): TextSpan                                          =
    134 (  0.184%): OutlineInputBorder                                =
    122 (  0.168%): Expanded                                          =
    118 (  0.162%): IconThemeData                                     =
    112 (  0.154%): AlwaysScrollableScrollPhysics                     =
    112 (  0.154%): ClampingScrollPhysics                             =
    107 (  0.147%): Interval                                          =
```

Whether migrating any or some of these classes to use `value` makes sense is
for the Flutter framework team to decide. This feature was designed so that it
should at least be *possible* by allowing value classes to implement interfaces
and be subclassed.
