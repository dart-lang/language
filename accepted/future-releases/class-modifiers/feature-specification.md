# Class modifiers

Author: Bob Nystrom

Status: Accepted

Version 1.1

Experiment flag: class-modifiers

This proposal specifies four modifiers that can be placed on classes and mixins
to allow an author to control whether the type allows being implemented,
extended, and/or mixed in from outside of the library where it's defined.

Informally, the new syntax is:

*   No modifier: Mostly as today where the class or mixin has no restrictions,
    except that we no longer allow a class to be used as a mixin by default.

*   `base`: As a modifier on a class, allows the class to be extended but not
    implemented. As a modifier on a mixin, allows it to be mixed in but not
    implemented. In other words, it takes away implementation.

*   `interface`: As a modifier on a class or mixin, allows the type to be
    implemented but not extended or mixed in. In other words, it takes away
    being used as a subclass through extension or mixing in.

*   `final`: As a modifier on a class or mixin, prohibits extending,
    implementing, or mixing in.

*   `mixin class`: A declaration that defines both a class and a mixin.

This proposal is a blend of a few earlier proposals:

* [Class capabilities][]
* [Type modifiers][]
* [Access modifiers using closed, sealed, open and interface][leaf proposal]

[class capabilities]: https://github.com/dart-lang/language/blob/master/resources/class-capabilities/class-capabilities.md
[type modifiers]: https://github.com/dart-lang/language/blob/master/inactive/type-modifiers/feature-specification.md
[leaf proposal]: https://github.com/dart-lang/language/issues/2595

The [type modifiers][] document has some motivation and discussion around
defaults and keyword choice which may be a useful reference. Unlike that
proposal, this proposal is mostly non-breaking.

## Motivation

Dart's ethos is to be permissive by default. When you declare a class, it can be
constructed, subclassed, and even exposes an implicit interface which can be
implemented—a feature (possibly) unique to Dart. Users generally appreciate this
flexibility and the power it places in the hands of library consumers.

Why might the author of a class or mixin author want to *remove* capabilities?
Doesn't that just make the type less useful? The type does end up more
restricted, but in return, there are more invariants about the type that the
type author and users can rely on being true. Those invariants may make the type
easier to understand, maintain, evolve, or even just to use.

Here are some use cases where restricting capabilities may lead to more robust
software:

### Adding methods

It's a compile-time error to have an `implements` clause on a non-`abstract`
class unless it contains definitions of every member in the type that you claim
to implement. This is a *useful* error because it ensures that any member
someone can access on a type is actually defined and will succeed. It helps you
in case you forget to implement something.

But it also means that if a *new* member is added to a class then every single
class implementing that class's interface now has a new compile-time error since
they are very unlikely to coincidentally already have that member.

This makes it hard to add new members to existing public types in packages.
Since anyone could be implementing that type's interface, any new member is
potentially a breaking API change which necessitates a major version bump. In
practice, many API authors just document "please don't implement this class" and
then rely on users to not do that.

However, for widely used packages, that polite agreement isn't sufficient.
Instead, they are simply prevented from adding new members and APIs get frozen
in time.

If a type disallows being implemented, then it becomes easier to add new members
without worrying about breaking existing users. If the type also prevents being
extended, then it's entirely safe to add new members to it. This makes it easier
to grow and evolve APIs.

### Unintended overriding

Most types contain methods that invoke other methods on `this`, for example:

```dart
class Account {
  int _balance = 0;

  bool canWithdraw(int amount) => amount <= _balance;

  bool tryWithdraw(int amount) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, "amount", "Must be positive");
    }

    if (!canWithdraw(amount)) return false;
    _balance -= amount;
    return true;
  }

  // ...
}
```

The intent is that `_balance` should never be negative. There may be other code
in this class that breaks if that isn't true. However, there's nothing
preventing a subclass from doing:

```dart
class BustedAccount extends Account {
  // YOLO.
  bool canWithdraw(int amount) => true;
}
```

Extending a class gives you free rein to override whatever methods you want,
while *also* inheriting concrete implementations of other methods that may
assume you *haven't* done that. If we prevent `Account` from being subclassed,
we ensure that when `tryWithdraw()` calls `canWithdraw()`, it calls the actual
`canWithdraw()` method we expect.

Note that it's *not* necessary to prevent *implementing* `Account` for this use
case. If you implement `Account`, you inherit *none* of its concrete
implementation, so you don't end up with methods like `tryWithdraw()` whose
behavior is broken.

### Safe private members

Consider:

```dart
class Account {
  int _balance = 0;

  bool tryTransfer(int amount, Account destination) {
    if (amount > _balance) return false;

    _balance -= amount;
    destination._balance += amount;
  }

  // ...
}
```

What would happen here if a class from another library implemented `Account` and
was passed as `destination` to `tryTransfer()`? When you implement a class's
interface from outside of the library where it's defined, none of its private
members are part of that interface. (If they were, you couldn't implement them.)

This isn't a widely known corner of the language, but if you try to access a
private member on a object that doesn't implement it (because the class only
implements the public part of the interface being implemented), Dart throws a
`NoSuchMethodException` at runtime.

In general, it's not safe to assume any object coming in to your library
actually has the private members you expect, because it could be an outside
implementation of your class's interface.

Dart users generally prefer to catch bugs at compile time. If we could prevent
other libraries from implementing the `Account` class's interface, then we
could be certain that any `Account` passed to `tryTransfer()` would be an
instance of *our* `Account` class (or a subclass of it) and thus be ensured
that all private members we expect are defined.

### Guaranteed initialization

Here's another example:

```dart
/// Assigns a unique ID to each instance.
class Handle {
  static int _nextID = 0;

  final int id;

  Handle() : id = _nextID++;
}

class Cache {
  final Map<int, Handle> _handles = {};

  void add(Handle handle) {
    _handles[handle.id] = handle;
  }

  Handle? find(int id) => _handles[id];
}
```

The `Cache` class assumes each `Handle` has a unique `id` field. The `Handle`
class's constructor ensures that (ignoring integer overflow for the moment).
This even works if you subclass `Handle`, since the subclass's constructor must
chain to and run the superclass constructor on `Handle`.

But if an unrelated type implements `Handle`'s interface, then there's no
guarantee that every instance of `Handle` has actually gone through that
constructor.

If the constructor is doing validation or caching, you might require that all
instances of the type have run it. But if the class's interface can be
implemented, then it's possible to route around the constructor and break the
class's invariants.

### Guardrails and intention

The previous sections show concrete, mechanical reasons why you might want to
remove type capabilities in order to enforce invariants and prevent bugs or
crashes.

But there are softer reasons to remove capabilities too. You may simply not
*intend* a type to be used in certain ways. There may be better ways for a user
of your API to solve their problem. Removing a capability helps guide them
towards how your API is supposed to be used.

It can make it simpler and easier to evolve your API. That in turn makes you
more productive, which lets you improve your API in ways that also directly
benefit your users.

## Restrictions within the same library

The previous sections show why you might want to prevent a type from being
extended or mixed in outside of the library where it's defined. But what about
*within* the same library? If it's *my* type, and I choose to prevent outside
code from extending or implementing it, can I ignore those restrictions within
my own library?

A closely related modifier we are working on is [`sealed`][sealed]. This works
in concert with the new [pattern matching features][] to let you define a closed
family of subtypes used for exhaustiveness checking. You put `sealed` on a
supertype. Then you are only allowed to directly extend, implement, or mix in
that supertype from within the same library.

[sealed]: https://github.com/dart-lang/language/blob/master/working/sealed-types/feature-specification.md
[pattern matching features]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/0546-patterns/feature-specification.md

In return for that restriction, in a switch, if you cover all of those subtypes,
then the compiler knows that you have [exhaustively][exhaustive] covered all
possible instances of the supertype. This is a big part of enabling a [functional
programming style][fp] in Dart.

[exhaustive]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/0546-patterns/exhaustiveness.md

[fp]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/0546-patterns/feature-specification.md#algebraic-datatypes

The `sealed` modifier prevents direct subtyping from outside of the library
where the sealed type is defined. But it doesn't prevent you from subtyping
within the same library. In fact, the *whole point* of `sealed` is to define
subtypes within the same library so that you can pattern match on those to cover
the supertype.

### Extending non-extensible classes in the same library

Preventing a class from being extended gives you an important invariant: Calls
to members on `this` from within that class won't end up in overrides you don't
control. This invariant remains even if we let you extend the class in the same
library. Calls to those members may end up in overrides, but they will be
overrides you yourself wrote in that same library.

Extending non-extensible classes is also really *useful* in API design. It lets
you offer a class *hierarchy* to users that is closed to further extension.

Consider the earlier example where you have a `Shape` base class and a couple of
subclasses. Let's say you also have code in that library for performing
intersection tests on pairs of shapes. That intersection code needs special
support for each *pair* of types: square and square, square and circle, circle
and circle. That means it would be hard to correctly support users adding their
own new subclasses of `Shape` and passing them to the library.

As the shape library author, you want to subclass `Shape` yourself so that you
can define `Square` and `Circle`, but disallow others from doing so. (In this
specific example, you probably also want to prohibit `Shape` from being
implemented too.)

### Implementing non-implementable types in the same library

A key invariant you get by preventing a type from being implemented is that it
becomes safe to access private members defined on that type without risking a
runtime exception. You are ensured that any instance of the type is an instance
of a type from your library that includes all of its private members.

This invariant is still preserved if we allow you to implement the type from
within the same library. When you implement a type inside its library, the
private members *are* part of the interface. So any type implementing it must
also define those private members and you'll never hit a
`NoSuchMethodException`.

### Transitive restrictions

The previous two sections suggest that we *can* ignore extends and implements
restrictions within the same library, and I think there are compelling use cases
for why we *should*, at least for extends, if not both.

If we do, what restrictions do those *secondary* types have? Let's say I write:

```dart
interface class NoExtend {}

class MySubclass extends NoExtend {}
```

The `interface` modifier means that `NoExtend` can only be implemented outside
of this library and not extended. We ignore the restriction internally and
extend it with `MySubclass`, which doesn't have any modifiers. What capabilities
does `MySubclass` now expose externally? We have a few options:

*   **Inherit restrictions.** We could say that `MySubclass` implicitly gets an
    `interface` modifier which it inherits from `NoExtend`. This way, if you add
    a restriction to some type and temporarily ignore it, the language continues
    to enforce that restriction externally all throughout the subtype hierarchy.

    This means that you can't just look at a single type declaration to see what
    you're allowed to do with it. You have to walk up the hierarchy looking for
    modifiers. I think it's important for users to be able to quickly tell what
    they can do with a type just by looking at its declaration, so I don't like
    this.

*   **No inherited restrictions.** The simplest option is to say that each type
    gets whatever restrictions you put on it. Since `MySubclass` has no
    modifiers, it has no restrictions. That's what you wrote, so that's what
    you get. If that's *not* what you want, then you should put a modifier on
    it.

    I like the simplicity of this. I think it's consistent with the rest of Dart
    which is permissive by default. Right now, you can make a class effectively
    `interface` by giving it only private generative constructors. Since there's
    no way for a class outside of the library to call one of those constructors,
    it can't be extended externally. But you could subclass it inside the
    library with a new class that calls that private generative constructor from
    its own public one. That subclass is now externally extensible and the
    language quietly lets you do that.

*   **Disallow removing restrictions.** We could say that you can ignore a
    type's restrictions within the same library, but any types that do that
    *must* have the same restrictions as the type they extend or implement. So
    if you implement a class marked `base` in the same library, that
    implementing class must also be marked `base` or `final`.

    This avoids any confusion about whether a subtype removes a restriction. But
    it comes at the expense of flexiblity. If a user *wants* to remove a
    restriction, they have no ability to.

    This would constrast with `sealed` where you can have subtypes of a sealed
    type that are not themselves sealed. This is a deliberate choice because
    there's no *need* for the direct subtypes of a sealed to be sealed in order
    for exhaustiveness checking to be sound. Since exhaustiveness is the goal
    and Dart is permissive by default, we allow subtypes of sealed types to be
    unsealed.

    It also prevents API designs that seem reasonable and useful to me. Imagine
    a library for transportion with classes like:

    ```dart
    abstract final class Vehicle {}

    class LandVehicle extends Vehicle {}
    class AquaticVehicle extends Vehicle {}
    class FlyingVehicle extends Vehicle {}
    ```

    It allows you to define new subclasses of the various modalities. You can
    add cars, bikes, canoes, and gliders to it. But it deliberately does not
    want to support adding entire new modalities by extending `Vehicle`
    directly. You can't add vehicles that, say, fly through space because the
    library isn't designed to support that.

    If we require subclasses to have the same restrictions, then there's no way
    to make `Vehicle` `final` while allowing `LandVehicle` and friends to be
    extended.

*   **Trust but verify.** In the earlier example, it's not clear what the author
    *intends*. Maybe they deliberately didn't put any modifiers on `MySubclass`
    because they *want* to re-add the capability that its superclass removed.
    But maybe they just didn't notice that `NoExtend` removed them, or they
    forgot to put `interface` on `MySubclass`.

    Since it's not clear what they meant, the language could require them to
    clarify. If you define a subtype of a type that has removed a capability, we
    could require you to annotate specifically when you re-add that capability.
    If you don't intend to re-add a capability, you restate the restriction:

    ```dart
    interface class NoExtend {}
    interface class MySubclass extends NoExtend {}
    ```

    And if you *do* intend to loosen it, you make that explicit by some marker
    like:

    ```dart
    interface class NoExtend {}
    reopen class MySubclass extends NoExtend {}
    ```

    Here "reopen" means, "I know I didn't put any other modifier here and that
    means this class has more capabilities than my parent."

    Personally, I think this is probably more modifiers than we want and is
    more trouble than it's worth. I worry about having to explain to users that
    a class marked `reopen` means the same thing as a class not marked with it.
    But I do think it could be useful to offer this as a lint with a metadata
    annotation for users that are more cautious, like:

    ```dart
    interface class NoExtend {}
    @reopen class MySubclass extends NoExtend {}
    ```

This proposal takes the last option where types have exactly the restrictions
they declare but a lint can be turned on for users who want to be reminded if
they re-add a capability in a subtype.

## Mixin classes

In line with Dart's permissive default nature, Dart allows any class declaration
to also be used as a mixin (in spec parlance, it allows a mixin to be "derived
from a class declaration"), provided the class meets the restrictions that
mixins require: Its immediate superclass must be `Object` and it must not
declare any generative constructors.

In practice, mixins are quite different from classes and it's uncommon for users
to deliberately define a type that is used as both. It's easy to define a class
without *intending* it to be used as a mixin and then accidentally forbid that
usage by adding a generative constructor or superclass to the class. That is a
breaking change to any downstream user that had that class in a `with` clause.

Using a class as a mixin is rarely useful, but it is sometimes, so we don't want
to prohibit it entirely. We just want to flip the default since allowing all
classes to be used as mixins makes them more brittle with relatively little
upside. Under this proposal we require authors to explicitly opt in to allowing
the class to be used as a mixin by adding a `mixin` modifier to the class:

```dart
class OnlyClass {}

class FailUseAsMixin extends OtherSuperclass with OnlyClass {} // Error.

mixin class Both {}

class UsesAsSuperclass extends Both {}

class UsesAsMixin extends OtherSuperclass with Both {} // OK.
```

## Syntax

This proposal builds on the existing sealed types proposal so the grammar
includes those changes. The full set of modifiers that can appear before a class
or mixin are `abstract`, `sealed`, `base`, `interface`, `final`, and `mixin`.
Many combinations don't make sense:

*   `base`, `interface`, and `final` all control the same two capabilities so
    are mutually exclusive.
*   `sealed` types can't be constructed so it's redundant to combine with
    `abstract`.
*   `sealed` types can't be extended or implemented, so it's redundant to
    combine with `final`.
*   `sealed` types can't be extended so it contradicts `base`.
*   `sealed` types can't be implemented, so it contradicts `interface`.
*   `sealed` types can't be mixed in outside of their library, so it contradicts
    `mixin` on a class. *It's useful to allow `sealed` on a mixin declaration
    because the mixin can be applied within the same library. But a class can
    already be used as a mixin within its own library even without the `mixin`
    modifier, so allowing `sealed mixin class` adds nothing.*
*   `interface` and `final` classes prevent the class from being used as a
    superclass but mixing in a mixin class also makes the class a superclass, so
    they contradict the `mixin` modifier. *An `interface mixin class M {}` would
    prohibited from appearing in an `extends` clause but could still be in
    `extends Object with M` which has the exact same effect.*
*   `mixin` as a modifier can obviously only be applied to a class.
*   Mixin declarations can't be constructed, so `abstract` is redundant.

The remaining valid combinations and their capabilities are:

| Declaration | Construct? | Extend? | Implement? | Mix in? | Exhaustive? |
|--|--|--|--|--|--|
|`class`                    |**Yes**|**Yes**|**Yes**|No     |No     |
|`base class`               |**Yes**|**Yes**|No     |No     |No     |
|`interface class`          |**Yes**|No     |**Yes**|No     |No     |
|`final class`              |**Yes**|No     |No     |No     |No     |
|`sealed class`             |No     |No     |No     |No     |**Yes**|
|`abstract class`           |No     |**Yes**|**Yes**|No     |No     |
|`abstract base class`      |No     |**Yes**|No     |No     |No     |
|`abstract interface class` |No     |No     |**Yes**|No     |No     |
|`abstract final class`     |No     |No     |No     |No     |No     |
|`mixin class`              |**Yes**|**Yes**|**Yes**|**Yes**|No     |
|`base mixin class`         |**Yes**|**Yes**|No     |**Yes**|No     |
|`abstract mixin class`     |No     |**Yes**|**Yes**|**Yes**|No     |
|`abstract base mixin class`|No     |**Yes**|No     |**Yes**|No     |
|`mixin`                    |No     |No     |**Yes**|**Yes**|No     |
|`base mixin`               |No     |No     |No     |**Yes**|No     |
|`interface mixin`          |No     |No     |**Yes**|No     |No     |
|`final mixin`              |No     |No     |No     |No     |No     |
|`sealed mixin`             |No     |No     |No     |No     |**Yes**|

The grammar is:

```
classDeclaration  ::= classModifiers 'class' identifier typeParameters?
                      superclass? interfaces?
                      '{' (metadata classMemberDeclaration)* '}'
                      | classModifiers 'class' mixinApplicationClass

classModifiers    ::= 'sealed'
                    | 'abstract'? ('base' | 'interface' | 'final')?
                    | 'abstract'? 'base'? 'mixin'

mixinDeclaration  ::= mixinModifier? 'mixin' identifier typeParameters?
                      ('on' typeNotVoidList)? interfaces?
                      '{' (metadata classMemberDeclaration)* '}'

mixinModifier     ::= 'sealed' | 'base' | 'interface' | 'final'
```

## Static semantics

It is a compile-time error to:

*   Extend a class marked `interface` or `final` outside of the library where it
    is declared.

*   Implement a class or mixin marked `base` or `final` outside of the library
    where it is declared.

*   Mix in a mixin marked `interface` or `final` outside of the library where it
    is declared.

*   Extend a class marked `base` outside of the library where it is declared
    unless the extending class is marked `base` or `final`. *This ensures that a
    subtype can't escape the `base` restriction of its supertype by offering its
    _own_ interface that could then be implemented without inheriting the
    concrete implementation from the supertype.*

*   Mix in a mixin or mixin class marked `base` outside of the library where it
    is declared unless the class mixing it in is marked `base` or `final`. *As
    with the previous rule, ensures you can't get a backdoor interface on a
    mixin that doesn't want to expose one.*

*   Mix in a class not marked `mixin` outside of the library where it is
    declared, unless the class declaration being used as a mixin is in a library
    whose language version is older than the version this feature ships in.

*   Apply `mixin` to a class whose superclass is not `Object` or that declares a
    generative constructor. *A `mixin class` states that you intend the class to
    be mixed in, which is inconsistent with defining a class that can't be used
    as a mixin. Note that this means that `mixin` on a class becomes a helpful
    reminder to ensure that you don't inadvertently break your class's ability
    to be used as a mixin.*

*   Mix in a class whose superclass is not `Object` or that declares a
    generative constructor. *Because of the previous rule, this rule only comes
    into play when you use a class not marked `mixin` as a mixin within the
    library where it's declared. When you do that, the existing restriction
    still applies that the class being used as a mixin must be valid to do so.*

A typedef can't be used to subvert these restrictions. When extending,
implementing, or mixing in a typedef, we look at the library where class or
mixin the typedef resolves to is defined to determine if the behavior is
allowed. *Note that the library where the _typedef_ is defined does not come
into play.*

### `@reopen` lint

We don't specify lints and metadata annotations in the language specification,
so this part of the proposal will not become a formal part of the language.
Instead, it's a suggested part of the overall user experience of the feature.

A metadata annotation `@reopen` is added to package [meta][] and a lint
"require_reopen" is added to the [linter][]. When the lint is enabled, a lint
warning is reported if a class or mixin is not annotated `@reopen` and it:

*   Extends or mixes in a class or mixin marked `interface` or `final` and is
    not itself marked `interface` or `final`.

*   Extends, implements, or mixes in a class or mixin marked `base` or `final`
    and is not itself marked `base`, `final`, or `sealed`.

[meta]: https://pub.dev/packages/meta
[linter]: https://dart.dev/guides/language/analysis-options#enabling-linter-rules

## Runtime semantics

There are no runtime semantics.

## Versioning

The changes in this proposal are guarded by a language version. This makes the
restriction on not allowing classes to be used as mixins by default
non-breaking.

Let `n` be the language version this proposal ships in. Then:

*   A class declaration in a library whose language version is `< n` can be used
    as a mixin as long as the class meets the mixin restrictions. *This is is
    true even if the library where the class is being used as a mixin is `>=
    n`.*

*   A class declaration in a library whose version is `>= n` must be explicitly
    marked `mixin class` to allow the class to be used in a `with` clause. *This
    is true even if the library where the class is being used as a mixin is `<
    n`.*

*   The `base`, `interface`, and `final` modifiers on classes and mixins can
    only be used in libraries whose language version is `>= n`.

### Compatibility

When upgrading your library to the new language version, you can preserve the
previous behavior by adding `mixin` to every class declaration that can be used
as a mixin. If the class defines a generative constructor or extends anything
other than `Object`, then it already can't be used as a mixin and no change is
needed.

## Changelog

1.1

- Clarify that all modifiers are gated behind a language version.

- Rationalize which modifiers can be combined with `mixin class` and specify
  behavior of `mixin class`.

- Rename to "Class modifiers" with the corresponding experiment flag name.
