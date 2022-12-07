# "Base", "interface", and "final" types

Author: Bob Nystrom

Status: In-progress

Version 1.0

This proposal specifies three modifiers that can be placed on classes and mixins
to allow an author to control whether the type allows being implemented,
extended, both, or neither. The proposed modifiers are:

*   No modifier: As today, the type has no restrictions.
*   `base`: The type can be extended (if a class) or mixed in (if a mixin) but
    not implemented.
*   `interface`: The type can be implemented but not extended or mixed in.
*   `final`: The type can't be extended, mixed in, or implemented.

This proposal is a blend of three earlier proposals:

* [Type modifiers][]
* ["Closed" and "base"][]
* [Access modifiers using closed, sealed, open and interface][leaf proposal]

The [type modifiers][] document has some motivation and discussion around
defaults and keyword choice which may be a useful reference. Unlike that
proposal, this proposal is non-breaking.

[type modifiers]: https://github.com/dart-lang/language/blob/master/working/type-modifiers/feature-specification.md
["closed" and "base"]: https://github.com/dart-lang/language/issues/2595
https://github.com/dart-lang/language/issues/2595
[leaf proposal]: https://github.com/dart-lang/language/issues/2595

This proposal also allows `mixin` to be used as a modifier on `class` to
indicate that a type is explicitly intended to be used as both a class and a
mixin.

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

Eventually, we would like classes to not be usable as a mixin by default. Being
extensible and implementable seems to be the right default for classes based on
Dart's history and talking to users. But being usable as a mixin by default is
rarely (but not *never*) useful and often confusing. It makes classes brittle
for little upside.

Instead, under this proposal we require authors to explicitly opt in to allowing
the class to be used as a mixin by adding a `mixin` modifier to the class:

```dart
class OnlyClass {}

class FailUseAsMixin extends OtherSuperclass with OnlyClass {} // Error.

mixin class Both {}

class UsesAsSuperclass extends Both {}

class UsesAsMixin extends OtherSuperclass with Both {} // OK.
```

This change is guarded by a language version. Any class declaration in a library
whose language version is before the one this feature ships in can be used as a
mixin as long as the class meets the mixin restrictions. Classes in libraries
whose version is later than that must be explicitly marked `mixin class` to
allow the class to be used in a `with` clause.

When upgrading your library to the new language version, you can preserve the
existing behavior by adding `mixin` to every class declaration that can be used
as a mixin. If the class defines a generative constructor or extends anything
other than `Object`, then it already can't be used as a mixin and no change is
needed.

## Syntax

This proposal builds on the existing sealed types proposal so the grammar
includes those changes. The full set of modifiers that can appear before a class
or mixin are `abstract`, `sealed`, `base`, `interface`, `final`, and `mixin`.
Some combinations don't make sense:

*   `sealed` implies `abstract`, so they can't be combined.
*   `sealed` implies non-extensibility, so can't be combined with `interface`
    or `final`.
*   `sealed` implies non-implementability, so can't be combined with `base` or
    `final`.
*   `base`, `interface`, and `final` all control the same two capabilities so
    are mutually exclusive.
*   `mixin` as a modifier can obviously only be applied to a class. It can be
    combined with any other modifiers that can be applied to a class.

The remaining valid combinations are:

<table><tr><td>

```
class
sealed class
base class
interface class
final class
abstract class
abstract base class
abstract interface class
abstract final class
```

</td><td>

```
mixin class
sealed mixin class
base mixin class
interface mixin class
final mixin class
abstract mixin class
abstract base mixin class
abstract interface mixin class
abstract final mixin class
```

</td><td>

```
mixin
sealed mixin
base mixin
interface mixin
final mixin
```

</td></tr></table>

The grammar is:

```
classDeclaration ::=
  classModifiers 'class' identifier typeParameters?
  superclass? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
  | classModifiers 'class' mixinApplicationClass

mixinDeclaration ::= mixinModifier? 'mixin' identifier typeParameters?
  ('on' typeNotVoidList)? interfaces?
  '{' (metadata classMemberDeclaration)* '}'

classModifiers ::= ( 'sealed' | 'abstract'? typeModifier? ) 'mixin'?
mixinModifier ::= 'sealed' | typeModifier
typeModifier ::= 'base' | 'interface' | 'final'
```

### Static semantics

It is a compile-time error to:

*   Extend a class marked `interface` or `final` outside of the library where it
    is declared.

*   Implement a type marked `base` or `final` outside of the library where it is
    declared.

*   Extend or mix in a type marked `base` outside of the library where it is
    declared without also being marked `base` or `final`. *This ensures that a
    subtype can't escape the `base` restriction of its supertype by offering its
    _own_ interface that could then be implemented without inheriting the
    concrete implementation from the supertype.*

*   Mix in a class not marked `mixin` outside of the library where it is
    declared, unless the class declaration is in a library whose language
    version is older than the version this feature ships in.

*   Apply the `mixin` modifier to a class whose superclass is not `Object` or
    that declares a generative constructor. *The `mixin` modifier states that
    you intend the class to be mixed in, which is inconsistent with defining a
    class that can't be used as a mixin. Note that this means that the `mixin`
    modifier becomes a helpful reminder to ensure that you don't inadvertently
    break your class's ability to be used as a mixin.*

*   Mix in a class whose superclass is not `Object` or that declares a
    generative constructor. *Because of the previous rule, this rule only comes
    into play when you use a class not marked `mixin` as a mixin within the
    library where it's declared. When you do that, the existing restriction
    still applies that the class being used as a mixin must be valid to do so.*

A typedef can't be used to subvert these restrictions. When extending,
implementing, or mixing in a typedef, we look at the library where type the
typedef resolves to is defined to determine if the behavior is allowed. *Note
that the library where the _typedef_ is defined does not come into play.*

### `@reopen` lint

We don't specify lints and metadata annotations in the language specification,
so this part of the proposal will not become a formal part of the language.
Instead, it's a suggested part of the overall user experience of the feature.

A metadata annotation `@reopen` is added to package [meta][] and a lint
"require_reopen" is added to the [linter][]. When the lint is enabled, a lint
warning is reported if a class or mixin is not annotated `@reopen` and it:

*   Extends or mixes in a type marked `interface` or `final` and is not itself
    marked `interface` or `final`.

*   Extends, implements, or mixes in a type marked `base` or `final` and is
    not itself marked `base`, `final`, or `sealed`.

[meta]: https://pub.dev/packages/meta
[linter]: https://dart.dev/guides/language/analysis-options#enabling-linter-rules

### Runtime semantics

There are no runtime semantics.
