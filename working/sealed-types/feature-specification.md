# Sealed types

Author: Bob Nystrom

Status: In-progress

Version 1.0

This proposal specifies *sealed types*, which is core capability needed for
[exhaustiveness checking][] of subtypes in [pattern matching][]. This proposal
is a subset of the [type modifiers][] proposal. (We may wish to do all or parts
of the rest of that proposal, but they aren't needed for pattern matching, so
this proposal separates them out.) For motivation, see the previously linked
documents.

[exhaustiveness checking]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/exhaustiveness.md

[pattern matching]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md

[type modifiers]: https://github.com/dart-lang/language/blob/master/working/type-modifiers/feature-specification.md

## Introduction

Marking a type `sealed` applies two restrictions:

*   If it's a class, the type itself can't be directly constructed. The class is
    implicitly `abstract`.

*   All direct subtypes of the type must be defined in the same library. Any
    types that directly implement, extend, or mixin the sealed type must be
    defined in the library where the sealed type is defined.

In return for those restrictions, sealed provides two useful properties for
exhaustiveness checking:

*   All of the direct subtypes of the sealed type can be easily found and
    enumerated.

*   Any concrete instance of the sealed type must also be an instance of at
    least one of the known direct subtypes. In other words, if you match on a
    value of the sealed type and you have cases for all of the direct subtypes,
    the compiler knows those cases are exhaustive.

### Open subtypes

Note that it is *not* necessary for the subtypes of a sealed type to themselves
be sealed or closed to subclassing or implementing. Given:

```dart
sealed class Either {}

class Left extends Either {}
class Right extends Either {}
```

Then this switch is exhaustive:

```dart
test(Either either) {
  switch (either) {
    case Left(): print('Left');
    case Right(): print('Right');
  }
}
```

And this is still true even if some unrelated or unknown library contains:

```dart
class LeftOut extends Left {}
```

Or even:

```dart
class Ambidextrous implements Left, Right {}
```

The only property we need for exhaustiveness is that *all instances of the
sealed type must also be an instance of a direct subtype.* More precisely, any
instance of the sealed supertype must have at least one of the direct subtypes
in its superinterface graph.

### Sealed subtypes

At the same time, it can be useful to seal not just a supertype but one or more
of its subtypes. Doing so lets you define a sealed *hierarchy* where matching
various subtypes will exhaustively cover various branches of the hierarchy. For
example:

```dart
// UnitedKingdom --+-- NorthernIreland
//                 |
//                 +-- GreatBritain --+-- England
//                                    |
//                                    +-- Scotland
//                                    |
//                                    +-- Wales
sealed class UnitedKingdom {}
class NorthernIreland extends UnitedKingdom {}
sealed class GreatBritain extends UnitedKingdom {}
class England extends GreatBritain {}
class Scotland extends GreatBritain {}
class Wales extends GreatBritain {}
```

By marking not just `UnitedKingdom` `sealed`, but also `GreatBritain` means that
all of these switches are exhaustive:

```dart
test1(UnitedKingdom uk) {
  switch (uk) {
    case NorthernIreland(): print('Northern Ireland');
    case GreatBritain(): print('Great Britain');
  }
}

test2(UnitedKingdom uk) {
  switch (uk) {
    case NorthernIreland(): print('Northern Ireland');
    case England(): print('England');
    case Scotland(): print('Scotland');
    case Wales(): print('Wales');
  }
}

test3(GreatBritain britain) {
  switch (britain) {
    case England(): print('England');
    case Scotland(): print('Scotland');
    case Wales(): print('Wales');
  }
}
```

Note that the above examples are all exhaustive regardless of whether
`NorthernIreland`, `England`, `Scotland`, and `Wales` are marked `sealed`.

In short, `sealed` is mostly a property that affects how you can use the
*supertype* and does not apply any restrictions to the direct subtypes of the
sealed type, except that they must be defined in the same library.

## Syntax

A class or mixin declaration may be preceded with the built-in identifier
`sealed`:

```
classDeclaration ::=
  ( 'abstract' | 'sealed' )? 'class' identifier typeParameters?
  superclass? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
  | ( 'abstract' | 'sealed' )? 'class' mixinApplicationClass

mixinDeclaration ::= 'sealed'? 'mixin' identifier typeParameters?
  ('on' typeNotVoidList)? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
```

*Note that the grammar disallows `sealed` on a class marked `abstract`. All
sealed types are abstract, so it's redundant to allow both modifiers.*

**Breaking change:** Treating `sealed` as a built-in identifier means that
existing code that uses `sealed` as the name of a type will no longer compile.
Since almost all types have capitalized names in Dart, this is unlikely to be
break much code.

### Static semantics

It is a compile-time error to extend, implement, or mix in a type marked
`sealed` outside of the library where the sealed type is defined. *It is fine,
however to subtype a sealed type from another part file or [augmentation
library][] within the same library.*

[augmentation library]: https://github.com/dart-lang/language/blob/master/working/augmentation-libraries/feature-specification.md

A typedef can't be used to subvert this restriction. If a typedef refers to a
sealed type, it is also a compile-time error to extend, implement or mix in that
typedef outside of the library where the sealed the typedef refers to is
defined. *Note that the library where the _typedef_ is defined does not come
into play.*

A class marked `sealed` is implicitly an *abstract class* with all of the
existing restrictions and capabilities that implies. *It may contain abstract
member declarations, it is a compile-time error to directly invoke its
constructors, etc.*

### Runtime semantics

There are no runtime semantics.

### Core library

The "dart:core" types `bool`, `double`, `int`, `Null`, `num`, and `String` are
all marked `sealed`. *These types have always behaved like sealed types by
relying on special case restrictions in the language specification. That
existing behavior can now be expressed in terms of this general-purpose
feature.*
