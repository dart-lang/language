# Private Named Parameters

Author: Bob Nystrom

Status: In-progress

Version 0.1 (see [CHANGELOG](#CHANGELOG) at end)

Experiment flag: private-named-parameters

This proposal makes it easier to initialize and declare private instance fields
using named constructor parameters. It addresses [#2509][] and turns code like
this:

[#2509]: https://github.com/dart-lang/language/issues/2509

```dart
class House {
  int? _windows;
  int? _bedrooms;
  int? _swimmingPools;

  House({
    int? windows,
    int? bedrooms,
    int? swimmingPools,
  })  : _windows = windows,
        _bedrooms = bedrooms,
        _swimmingPools = swimmingPools;
}
```

Into this:

```dart
class House {
  int? _windows;
  int? _bedrooms;
  int? _swimmingPools;

  House({this._windows, this._bedrooms, this._swimmingPools});
}
```

Calls to the constructor are unchanged and continue to use the public argument
names:

```dart
House(windows: 5, bedrooms: 3);
```

This proposal harmonizes with (and in a couple of places mentions) the [primary
constructors][] proposal. When combined with that proposal, the above example
becomes:

[primary constructors]: https://github.com/dart-lang/language/blob/main/working/2364%20-%20primary%20constructors/feature-specification.md

```dart
class House({
  var int? _windows,
  var int? _bedrooms,
  var int? _swimmingPools,
});
```

Without this proposal, the example here wouldn't be able to use a primary
constructor at all without giving up either privacy on the fields or named
parameters in the constructor.

## Motivation

Dart uses a leading underscore in an identifier to make a declaration private to
its library. Privacy is only meaningful for declarations that could be accessed
from outside of the library: top-level declarations and members on types.

Local variables and parameters aren't in scope outside of the library where they
are defined, so privacy doesn't come into play. Except, that is, for named
parameters. A *named* parameter has one foot on each side of the function
boundary. The parameter defines a local variable that is accessible inside the
function, but it also specifies the name used at the callsite to pass an
argument for that parameter:

```dart
test({String? _hmm}) {
  print(_hmm);
}

main() {
  test(_hmm: 'ok?');
}
```

A public function containing a named parameter whose name is private raises
difficult questions. Is there any way to pass an argument to the function from
outside of the library? If the parameter is required, does that mean the
function is effectively uncallable? Or do we not treat the identifier as private
even though it starts with an underscore if it happens to be a parameter name?

The language currently resolves these questions by routing around them: it is a
compile-time error to have a named parameter with a private name. Users must use
a public name instead. For most named parameters, this restriction is harmless.
The parameter is only used within the body of the function and its idiomatic for
local variables to not have private names anyway.

### Initializing formals

However, initializing formals (the `this.` before a constructor parameter)
complicate that story. When a named parameter is also an initializing formal,
then the name affects *three* places in the program:

1.  The name of the parameter variable inside the body of the constructor.

2.  The name used to pass an argument at the callsite.

3.  The name of the corresponding instance field to initialize with that
    parameter.

For example:

```dart
class House {
  int? bedrooms; // 3. The corresponding field.
  House({this.bedrooms})
    : assert(bedrooms == null || bedrooms >= 0); // 1. The parameter variable.
}

main() {
  House(bedrooms: 2); // 2. The argument name.
}
```

This creates a tension. A user may want:

*   **To make a field private.** We [actively encourage them to do so][effective
    private] because encapsulation is a key software engineering principle.

*   **To make a constructor parameter named.** This is idiomatic in the Flutter
    framework and Flutter applications and can be important for readability if
    a constructor takes multiple parameters of the same type.

*   **To use an initializing formal to initialize a field from a constructor
    parameter.** It's the most concise way to initialize a field, avoids the
    unusual initializer syntax, and makes it clear to a reader that the field
    is directly initialized from that parameter.

They want encapsulation, readability at callsites, and brevity in the class
definition, but because of the compile-error on private named parameters, they
can only [pick two][].

[effective private]: https://dart.dev/effective-dart/design#prefer-making-declarations-private

[pick two]: https://en.wikipedia.org/wiki/Project_management_triangle

### Workaround

When users run into this restriction, they may deal with it by sacrificing one
of the three features:

*   They can make the field public and just expect users to not use it. (Often,
    the class is in application code where it's not imported anyway so it
    doesn't matter much.)

*   They can make the parameter positional instead.

*   They can commit to the API they want by making the field private and the
    parameter named, but use a public name for the parameter. Then instead of
    using an initializing formal, they manually initialize the field from the
    parameter, as in:

    ```dart
    class House {
      int? _windows;
      int? _bedrooms;
      int? _swimmingPools;

      House({
        int? windows,
        int? bedrooms,
        int? swimmingPools,
      })  : _windows = windows,
            _bedrooms = bedrooms,
            _swimmingPools = swimmingPools;
    }
    ```

The first two are hard to measure without interviewing users because we don't
know which fields are intentionally public and which constructor parameters are
intentionally positional versus which are simply workarounds to the above
problem.

We can get data on the third one. I scanned a large corpus of pub packages and
looked at every constructor initializer:

```
-- Parameter initializer (42184 total) --
  32958 ( 78.129%): Other                     ===========================
   9226 ( 21.871%): Make private: _foo = foo  ========
```

Over a fifth of all field initializers are simply initializing a private a field
with a parameter whose name is the same as the field with the underscore
stripped off. These are places where the user could be using the shorter `this.`
initializing formal if the underscore wasn't getting in the way.

### Primary constructors

The language team is currently working on a proposal for [primary
constructors][]. That proposal lets a constructor parameter not just
*initialize* a field, but *declare* it too.

[primary constructors]: https://github.com/dart-lang/language/blob/main/working/2364%20-%20primary%20constructors/feature-specification.md

This is a highly desired feature. The most-voted open issue in the language repo
is for [data classes][]. That concept encompasses a few features, but if you
look at the comments, many users are specifically requesting primary
constructors. The issue for [primary constructors][primary ctors issue]
specifically is the #11 upvoted request.

[data classes]: https://github.com/dart-lang/language/issues/314
[primary ctors issue]: https://github.com/dart-lang/language/issues/2364

With that feature, users will encounter the limitation around private named
parameters even more often. In-header primary constructors exacerbate this issue
because an in-header primary constructor *can't* have an initializer list. Users
will be forced to either make the field public, the parameter positional, or not
use a primary constructor at all.

We don't want to put users in a position where the code that's most pleasant to
write requires them to sacrifice semantic properties they want like
encapsulation.

## Proposal

The basic idea is simple. We let users use a private name in a named parameter.
The compiler removes the `_` from the argument name but keeps it for the
corresponding initialized or declared field. In other words, we do exactly what
users are doing by hand when they write an initializer like:

```dart
class House {
  int? _windows;
  int? _bedrooms;
  int? _swimmingPools;

  House({
    int? windows,
    int? bedrooms,
    int? swimmingPools,
  })  : _windows = windows,
        _bedrooms = bedrooms,
        _swimmingPools = swimmingPools;
}
```

With this proposal, the above class can be written with identical semantics like
so:

```dart
class House {
  int? _windows;
  int? _bedrooms;
  int? _swimmingPools;

  House({this._windows, this._bedrooms, this._swimmingPools});
}
```

When this proposal is combined with primary constructors, they can write:

```dart
class House({
  var int? _windows,
  var int? _bedrooms,
  var int? _swimmingPools,
});
```

### Concerns

This proposal makes the language implicitly convert a private named parameter
into the verbose pattern users do today where they declare a public named
parameter and explicitly initialize the private field from it:

```dart
class C {
  int? _variable;

  C({int? variable}) : _variable = variable;
}
```

While verbose, this code has the advantage of being very clear what's going on.
A reader can see that the argument name they must use at the callsite is
`variable`, the field is named `_variable`, and the latter is initialized from
the former.

Discarding the `_` implicitly may be confusing for users. If a user sees a class
like:

```dart
class C({int? _variable}) {}
```

They may try to call it like `C(_variable: 123)` and be confused that it doesn't
work. There's nothing in the code hinting that the `_` is removed from the
argument name.

In general, we try to design features that are both useful once you know
them and intuitive to learn in the first place. This feature is helpful for
brevity once you know the "trick", but it's opaque when it comes to learning.
This is a real concern with the feature, but I believe the brevity makes it
worth the learnability cost.

We mitigate confusion here in a couple of ways:

#### Only allow the syntax where it's meaningful

At the language level, this proposal only allows `_` in a named parameter when
doing so is *useful and meaningful*. It doesn't allow *any* named parameter to
start with underscore, only a named parameter that declares or initializes a
private instance field.

A private named parameter *looks weird* since privacy makes little sense for an
argument name and makes even less sense for the local parameter variable. (We
already have a lint that warns on using `_` for local variable names since it
accomplishes nothing.)

If a user sees `_` on a parameter and is trying to figure out what's going on,
they will reliably be in a context where that parameter is also referring to a
field. If we're lucky, that may lead them to intuit that the privacy is for the
field, not the parameter.

#### Provide a teaching error if they use `_` for other named parameters

If a user tries to put `_` before a named parameter that *isn't* an initializing
formal or declaring parameter, it's an error. That error message can explain
that it's forbidden *here* but that the syntax can be used to declare or
initialize a private field.

#### Provide a teaching error if they use `_` on the argument name

If a user sees a named parameter with a private name, they may try to call the
constructor with that same private argument name, like `C(_variable: 123)`.
When they do, this is always an error.

The error message for that can explain that the `_` is only used to make the
corresponding field private and that the argument should be the public name. The
first time a user tries to call one of these constructors the wrong way, we can
teach them the feature.

## Static semantics

An identifier is a **private name** if it starts with an underscore (`_`),
otherwise it's a **public name**.

A private name may have a **corresponding public name**. If the characters of
the identifier with the leading underscore removed form a valid identifier and a
public name, then that is the private name's corresponding public name. *For
example, the corresponding public name of `_foo` is `foo`.* If removing the
underscore does not leave something which is is a valid identifier *(as in `_`
or `_2x`)* or leaves another private name *(as in `__x`)*, then the private name
has no corresponding public name.

Given a named initializing formal or field parameter (for a primary constructor)
with private name *p* in constructor C:

*   If *p* has no corresponding public name *n*, then compile-time error. *You
    can't use a private name for a named parameter unless there is a valid
    public name that could be used at the callsite.*

*   If any other parameter in C has declared name *p* or *n*, then
    compile-time error. *If removing the `_` leads to a collision with
    another parameter, then there is a conflict.*

*   Otherwise, the name of the parameter in C is *n*. *If the parameter is
    named, this then avoids the compile-time error that would otherwise be
    reported for a private named parameter.*

*   The name of the local variable in the initializer list scope of C is *p*.
    *In the initializer list, the private name is used. Inside the body of the
    constructor, uses of *p* refer to the field, not the parameter.*

*   If the parameter is an initializing formal, then it initializes a
    corresponding field with name *p*.

*   Else the field parameter induces an instance field with name *p*.

*For example:*

```dart
// Note: Also uses an in-body primary constructor.
class Id {
  late final int _region = 0;

  this({this._region, final int _value}) : assert(_region > 0 && _value > 0);

  @override
  String toString() => 'Id($_region, $_value)';
}

main() {
  print(Id(region: 1, value: 2)); // Prints "Id(1, 2)".
}
```

*Note that the proposal only applies named parameters and only to ones which are
initializing formals or field parameters. A named parameter can only have a
private name in a context where it is _useful_ to do so because it corresponds
to a private instance field. For all other named parameters it is still a
compile-time error to have a private name.*

## Runtime semantics

There are no runtime semantics for this feature. It's purely a compile-time
renaming.

## Compatibility

This proposal takes code that it is currently a compile-time error (a private
named parameter) and makes it valid in some circumstances (when the named
parameter is an initializing formal or field parameter). Since it simply expands
the set of valid programs, it is backwards compatible. Even so, it should be
language versioned so that users don't inadvertently use this feature while
their program allows being run on older pre-feature SDKs.

## Tooling

The best language features are designed holistically with the entire user
experience in mind, including tooling and diagnostics. This section is *not
normative*, but is merely suggestions and ideas for the implementation teams.
They may wish to implement all, some, or none of this, and will likely have
further ideas for additional warnings, lints, and quick fixes.

### API documentation generation

Authors documenting an API that uses this feature should refer to the
constructor parameter by its public name since that's what users will pass.
Likewise, docs generator like [`dart doc`][dartdoc] should document the
constructor's parameter with its public name. The fact that the parameter
initializes or declares a private field is an implementation detail of the
class. What a user of the class cares about is the corresponding public name for
the constructor parameter.

[dartdoc]: https://dart.dev/tools/dart-doc

### Lint and quick fix to use private named parameter

There is currently a lot of code in the wild like this:

```dart
class House {
  int? _windows;
  int? _bedrooms;
  int? _swimmingPools;

  House({
    int? windows,
    int? bedrooms,
    int? swimmingPools,
  })  : _windows = windows,
        _bedrooms = bedrooms,
        _swimmingPools = swimmingPools;
}
```

That code can be automatically converted to use private named parameters. The
rewrite rule logic is if:

*   A constructor has a public named parameter.
*   The class has an instance field with the same name but prefixed with `_`.
*   The constructor initializer list initializes the field with that parameter.

Then a quick fix can remove the initializer and rename the parameter to be an
initializing formal with the private name.

Since there's no reason to *not* prefer using an initialing formal in cases
like this, it probably makes sense to have a lint encouraging this as well.

### Good error messages when users misuse this feature

Since this feature likely isn't as intuitive as we hope to be, error messages
are even more important to help users understand what the language is doing and
getting them back on the right path.

The [Concerns][] section suggests two error cases and how good messaging there
can help users learn the feature.

[concerns]: #concerns

## Changelog

### 0.2

-   Add section about concerns for learnability and mitigations.

### 0.1

-   Initial draft.
