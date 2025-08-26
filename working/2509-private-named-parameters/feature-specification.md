# Private Named Parameters

Author: Bob Nystrom

Status: In-progress

Version 0.2 (see [CHANGELOG](#CHANGELOG) at end)

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
are defined, but named parameters can be referenced from outside of the library.
This raises the question of how to interpret a private named parameter:

```dart
test({String? _hmm}) {
  print(_hmm);
}

main() {
  test(_hmm: 'ok?');
}
```

Should this be allowed? And if so, do we treat this as a named parameter which
can only be called from within the defining library?

The language currently resolves this by saying that it is a compile-time error
to have a named parameter with a private name. Users must use a public name
instead. For most named parameters, this restriction is harmless. The parameter
is only used within the body of the function and it is idiomatic for local
variables to not have private names anyway.

### Initializing formals

However, initializing formals (the `this.` before a constructor parameter)
complicate that story. When a named parameter is also an initializing formal,
then the name affects *three* places in the program:

1.  The name of the parameter variable inside the constructor initializer list.
    (Inside the constructor *body*, it's the instance field that is in scope.)

2.  The name used to pass an argument at the call site.

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

They want encapsulation, readability at call sites, and brevity in the class
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

The basic idea is simple. We let users use a private name in a named parameter
when the parameter also initializes or declares a field. The compiler removes
the `_` from the argument name but keeps it for the corresponding field. In
other words, we do exactly what users are doing by hand when they write an
initializer like:

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
A reader can see that the argument name they must use at the call site is
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
doing so is *useful and meaningful* because it declares or initializes a private
instance field. If the named parameter does neither of those, this proposal
still prohibits the parameter from having a private name.

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

### Super parameters

We allow private named parameters for initializing formals and (assuming primary
constructors exist), declaring parameters. What about the other special kind of
constructor parameter, super parameters (the `super.` syntax)?

Those are unaffected by this proposal. A super parameter generates an implicit
argument that forwards to a superclass constructor. The super constructor's
argument name is always public, even if the corresponding constructor parameter
uses this feature and has a private name. Thus, super parameters continue to
always use public names. For example:

```dart
class Tool {
  int _price;

  Tool({this._price}); // Private name here.
}

void cheapTool() => Tool(price: 1); // Called with public name.

class Hammer extends Tool {
  Hammer({super.price}); // And thus call with public name here too.
}

void pricyHammer() => Hammer(price: 200);
```

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
    public name that could be used at the call site.*

*   If any other parameter in C has declared name *p* or *n*, then
    compile-time error. *If removing the `_` leads to a collision with
    another parameter, then there is a conflict.*

If there is no error then:

*   The parameter name of the parameter in the constructor is the public name
    *n*. This means that the parameter has a public name in the constructor's
    function signature, and arguments for this parameter are given using the
    public name. All uses of the constructor, outside of its own code, see only
    the public name.

*   The local variable introduced by the parameter, accessible only in the
    initializer list, still has the private name *p*. *Inside the body of the
    constructor, uses of _p_ refer to the instance variable, not the parameter.*

*   The instance variable initialized by the parameter (and declared by it, if
    the parameter is a field parameter), has the private name *p*.

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

The reason a parameter has a private name is only a convenience for the
maintainer of that constructor so that they can use an initializing formal or
declaring parameter. A *user* of that constructor doesn't care about that
implementation detail.

Therefore, generated documentation from tools like [`dart doc`][] and in-IDE
contextual help should show the public names for parameters. For named
parameters, the public name is what users must write for the corresponding named
argument. Even for positional parameters, the name is what matters, and not that
it happens to correspond to a private field.

[dartdoc]: https://dart.dev/tools/dart-doc

When writing a doc comment that refers to a private named parameter, the
reference should be the private name. That's the name that is actually in scope
where the doc comment is resolved. But, as with the constructor's signature, doc
generators are encouraged to remove the `_` and show the public name for that
reference.

For example, given some code like:

```dart
class C {
  final int _positional;
  final int _named;

  /// Creates a new instance initialized from [_positional] and [_named].
  C(this._positional, {this._named});
}
```

Ideally, the generated documentation for the constructor would look something
like:

> ### C(int positional, {int named})
>
> Creates a new instance initialized from `positional` and `named`.

Or, put another way, if a class maintainer changes a parameter with a public
name to instead have a private name in order to take advantage of an
initializing formal or declaring parameter, then the generated documentation
should not change.

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
-   Add section on super parameters.

### 0.1

-   Initial draft.
