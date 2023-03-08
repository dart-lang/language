# Class modifiers

Author: Bob Nystrom, Lasse Nielsen

Status: Accepted

Version 1.6

Experiment flag: class-modifiers

This proposal specifies four modifiers that can be placed on classes and mixins
to allow an author to control whether the type allows being implemented,
extended, and/or mixed in from outside of the library where it's defined.

Informally, the new syntax is:

*   No modifier: Mostly as today where the class or mixin has no restrictions,
    except that we no longer allow a class to be used as a mixin by default.

*   `base`: As a modifier on a class, allows the class to be extended but not
    implemented. As a modifier on a mixin, allows it to be mixed in but not
    implemented. In other words, it takes away being able to implement
    the interface of the declaration.

*   `interface`: As a modifier on a class or mixin, allows the type to be
    implemented but not extended or mixed in. In other words, it takes away
    being able to inherit from the type.

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

[sealed]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/sealed-types/feature-specification.md
[pattern matching features]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/0546-patterns/feature-specification.md

In return for that restriction, in a switch, if you cover all of those subtypes,
then the compiler knows that you have [exhaustively][exhaustive] covered all
possible instances of the supertype. This is a big part of enabling a
[functional programming style][fp] in Dart.

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

    This means that you cannot just look at a single type declaration to see
    what you're allowed to do with it. You have to walk up the hierarchy looking
    for modifiers. I think it's important for users to be able to quickly tell
    what they can do with a type just by looking at its declaration, so I don't
    like this.

*   **No inherited restrictions.** The simplest option is to say that each type
    gets whatever restrictions you put on it. Since `MySubclass` has no
    modifiers, it has no restrictions. That's what you wrote, so that's what
    you get. If that's *not* what you want, then you should put a modifier on
    it.

    I like the simplicity of this. I think it's consistent with the rest of Dart
    which is permissive by default. Right now, you can make a class effectively
    `interface` by giving it only private generative constructors. Since there's
    no way for a class outside of the library to call one of those constructors,
    it cannot be extended externally. But you could subclass it inside the
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
    directly. You cannot add vehicles that, say, fly through space because the
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

### Inherited restrictions

Allowing you to ignore restrictions on your own types allows some useful
architectural patterns, but it's important that doing so doesn't let you ignore
restrictions on types from *other* libraries because then you could break the
invariants the library expects. In particular, consider:

```dart
// lib_a.dart
base class A {
  void _private() {
    print('Got it.');
  }
}

callPrivateMethod(A a) {
  a._private();
}
```

This library declares a class and marks it `base` to ensure that every instance
of `A` in the program must be an `A` or a class that inherits from it. That in
turn ensures that the call to `_private()` in `callPrivateMethod()` is always
safe.

Now consider:

```
// lib_b.dart
import 'lib_a.dart';

base class B extends A {} // OK: Inheriting.

class C implements B {} // OK: Ignoring restriction on own type B.
```

These two class declarations each seem to be fine. But put together, the result
is a class `C` that is a subtype of `A` but doesn't inherit from it and doesn't
have the `_private()` method that lib_a.dart expects.

So we want to allow libraries to ignore restrictions on their own types, but we
need to be careful that doing so doesn't break invariants in *other* libraries.
In practice, this means that when a class opts out of being implemented using
`base` or `final`, then that particular restriction cannot be ignored.

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
or mixin declaration are `abstract`, `sealed`, `base`, `interface`, `final`, and
`mixin`.

*The modifiers do not apply to other declarations like `enum`, `typedef`, or
`extension`.*

Many combinations don't make sense:

*   `base`, `interface`, and `final` all control the same two capabilities so
    are mutually exclusive.
*   `sealed` types cannot be constructed so it's redundant to combine with
    `abstract`.
*   `sealed` types cannot be extended or implemented, so it's redundant to
    combine with `final`, `base`, or `interface`.
*   `sealed` types cannot be mixed in outside of their library, so it
    contradicts `mixin` on a class. *It's useful to allow `sealed` on a mixin
    declaration because the mixin can be applied within the same library.
    A `sealed mixin class`  does not provide any significant extra
    functionality over a `sealed mixin`, you can replace `extends MixinClass`
    with `with Mixin`, so a `sealed mixin class` is not allowed.*
*   `interface` and `final` classes would prevent a mixin class from being used
    as a superclass or mixin outside of its library. *Like for `sealed`, an
    `interface mixin class` and `final mixin class` are not allowed, and
    `interface mixin` and `final mixin` declaration are recommended instead.*
*   `mixin` as a modifier can obviously only be applied to a `class`
    declaration, which makes it also a `mixin` declaration.
*   `mixin` as a modifier cannot be applied to a mixin-application `class`
    declaration (the `class C = S with M;` syntax for declaring a class). The
    remaining modifiers can.
*   Mixin declarations cannot be constructed, so `abstract` is redundant.

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
classDeclaration  ::= (classModifiers | mixinClassModifiers) 'class' typeIdentifier
                      typeParameters? superclass? interfaces?
                      '{' (metadata classMemberDeclaration)* '}'
                      | classModifiers 'class' mixinApplicationClass

classModifiers    ::= 'sealed'
                    | 'abstract'? ('base' | 'interface' | 'final')?

mixinClassModifiers ::= 'abstract'? 'base'? 'mixin'

mixinDeclaration  ::= mixinModifier? 'mixin' typeIdentifier typeParameters?
                      ('on' typeNotVoidList)? interfaces?
                      '{' (metadata classMemberDeclaration)* '}'

mixinModifier     ::= 'sealed' | 'base' | 'interface' | 'final'
```

## Static semantics

A pair of definitions:

*   A *pre-feature library* is a library whose language version is lower than
    the version this feature is released in.

*   A *post-feature library* is a library whose language version is at or above
    the version this feature is released in.

### Basic restrictions

It is a compile-time error to:

*   Extend a class marked `interface`, `final` or `sealed` outside of the
    library where it is declared.

    ```dart
    // a.dart
    interface class I {}
    final class F {}
    sealed class S {}

    // b.dart
    import 'a.dart';

    class C1 extends I {} // Error.
    class C2 extends F {} // Error.
    class C3 extends S {} // Error.
    ```

*   Implement the interface of a class, mixin, or mixin class marked `base`,
    `final` or `sealed` outside of the library where it is declared.

    ```dart
    // a.dart
    base class B {}
    final class F {}
    sealed class S {}

    base mixin BM {}
    final mixin FM {}
    sealed mixin SM {}

    // b.dart
    import 'a.dart';

    class C1 implements B {} // Error.
    class C2 implements F {} // Error.
    class C3 implements S {} // Error.

    class C1 implements BM {} // Error.
    class C2 implements FM {} // Error.
    class C3 implements SM {} // Error.
    ```

*   Mix in a mixin or mixin class marked `interface`, `final` or `sealed`
    outside of the library where it is declared.

    ```dart
    // a.dart
    interface mixin class I {}
    final mixin class F {}
    sealed mixin class S {}

    interface mixin IM {}
    final mixin FM {}
    sealed mixin SM {}

    // b.dart
    import 'a.dart';

    class C1 with I {} // Error.
    class C2 with F {} // Error.
    class C3 with S {} // Error.

    class C1 with IM {} // Error.
    class C2 with FM {} // Error.
    class C3 with SM {} // Error.
    ```

A typedef cannot be used to subvert these restrictions or any of the
restrictions below. When extending, implementing, or mixing in a typedef, we
look at the library where class or mixin the typedef resolves to is defined to
determine if the behavior is allowed. *Note that the library where the _typedef_
is defined does not come into play. Typedefs cannot be marked with any of the
new modifiers.*

### Disallowing implementation

It is a compile-time error if a subtype of a declaration marked `base` or
`final` is not marked `base`, `final`, or `sealed`. This restriction applies to
both direct and indirect subtypes and along all paths that introduce subtypes:
`implements` clauses, `extends` clauses, `with` clauses, and `on` clauses. This
restriction applies even to types within the same library.

*Once the ability to use as an interface is removed, it cannot be reintroduced
in a subtype. If a class is marked `base` or `final`, you may still implement
the class's interface inside the same library, but the implementing class must
again be marked `base`, `final`, or `sealed` to avoid it exposing an
implementable interface.*

Further, while you can ignore some restrictions on declarations within the same
library, you cannot use that to ignore restrictions inherited from other
libraries.

We say that `S` is a _direct declared superinterface_ of a class, mixin, or
mixin class declaration `D` if `D` has a superclass clause of the form
`C with M1 .. Mk` (where `k` may be zero when there is no `with` clause)
and `S` is `C`, or `S` is `Mj` for some `j` in 1 .. k,
or if `D` has an `implements` or `on` clause and `S` occurs as one of the operands of
that clause.

We then say that a class or mixin declaration `D` *cannot be implemented locally* if it
has a direct declared superinterface `S` such that:

*   `S` is from another library than `D`, and `S` has the modifier `base`,
    `final` or `sealed`, or

    ```dart
    // a.dart
    base mixin class S {}

    // b.dart
    import 'a.dart';

    // These cannot be implemented locally:
    sealed class DE extends S {}
    final class DM with S {}
    base mixin MO on S {}
    ```

*   `S` is from the same library as `D`, and `S` cannot be implemented locally.

    ```dart
    // a.dart
    base class B {}

    // b.dart
    import 'a.dart';

    // These cannot be implemented locally (from the previous rule):
    base class S extends B {}
    base mixin M on B {}

    // And thus these also cannot be implemented locally:
    base class DE extends S {}
    base class DM extends B with M {} // (from this and the previous rule).
    base mixin MO on S {}
    base mixin M2 on M {}
    ```

Otherwise, `D` can be implemented locally.

It is a compile-time error if:

*   A class, mixin, or mixin class declaration `D` has an `implements` clause
    where `S` is an operand, and `S` is a class, mixin, or mixin class
    declaration declared in the same library as `D`, and `S` cannot be
    implemented locally.

    ```dart
    // a.dart
    base class B {}

    // b.dart
    import 'a.dart';

    base class S extends B {} // Cannot be implemented locally but OK.

    base class D implements S {} // Error, cannot use "implements".
    ```

*   A class, mixin, or mixin class declaration `D` cannot be implemented
    locally, and `D` does not have a `base`, `final` or `sealed` modifier.
    _A declaration which cannot be implemented locally also cannot
    be allowed to be implemented in another library._

### Mixin restrictions

There are a few changes around mixins to support `mixin class` and disallow
using normal `class` declarations as mixins while dealing with language
versioning and backwards compatibility.

Currently, a class may only be used as a mixin if it has a default constructor.
This prevents the class from defining a `const` constructor or any factory
constructors. We loosen this somewhat.

Define a *trivial generative constructor* to be a generative constructor that:

*   Is not a redirecting constructor,

*   declares no parameters,

*   has no initializer list (no `: ...` part, so no asserts or initializers, and
    no super constructor invocation),

*   has no body (only `;`), and

*   is not `external`. *An `external` constructor is considered to have an
    externally provided initializer list and/or body.*

A trivial constructor may be named or unnamed, and `const` or non-`const`.
A *non-trivial generative constructor* is a generative constructor which is not a
trivial generative constructor.

Examples:

```dart
class C {
  // Trivial generative constructors:
  C();
  const C();

  // Non-trivial generative constructors:
  C(int x);
  C(this.x);
  C() {}
  C(): assert(true);
  C(): super();

  // Not generative constructors, so neither trivial generative nor non-trivial
  // generative:
  factory C.f = C;
  factory C.f2() { ... }
}
```

It's a compile-time error if:

*   A `mixin class` declaration has a superclass other than `Object`. *The
    declaration is limited to an `extends Object` clause or no `extends` clause,
    and no `with` clauses. The class grammar prohibits `on` clauses.*

*   A `mixin class` declaration declares any non-trivial generative constructor.
    *It may declare no constructors, in which case it gets a default
    constructor, or it can declare factory constructors and/or trivial
    generative constructors.*

These rules ensure that when you mark a `class` with `mixin` that it *can* be
used as one.

A class not marked `mixin` can still be used as a mixin when the class's
declaration is in a pre-feature library and it satisfies specific requirements.
Specifically:

It's a compile-time error for a declaration in library `L` to mix in a
non-`mixin` class declaration `D` from library `K` if any of:

*   `K` is a post-feature library,

*   The superclass of `D` is not `Object`, or

*   `D` declares any constructors.

*For pre-feature libraries, we cannot tell if the intent of `class` was
"just a class" or "both a class and a mixin". For compatibility, we assume
the latter, even if the class is being used as a mixin in a post-feature
library where it does happen to be possible to distinguish those two
intents.*

### Anonymous mixin applications

An *anonymous mixin application* class is a class resulting from a mixin application
that does not have its own declaration.
That is all mixin applications classes other than the final class
of a <Code>class C = S with M1, …, M<sub>n</sub>;</code> declaration, the mixin application of <code>M<sub>n</sub></code> to
the superclass <code>S with M1, …, M<sub>n-1</sub></code>, which is denoted by declaration and name `C`.

An anonymous mixin application class cannot be referenced anywhere except in
the context where the application occurs, so its only role is to be a superclass of
another class in the same library.

To ensure reasonable and correct behavior, we infer class modifiers on anonymous
mixin application classes as follows.

Let *C* be an anonymous mixin application with superclass *S* and mixin *M*. Then:

* If any of *S* or *M* has a `sealed` modifier, *C* is has a `sealed` modifier.
* Otherwise:
  * *C* is `abstract`, and
  * If either of *S* or *M* has a `base` or `final` modifier, then *C* has a `final` modifier.

_We do not distinguish whether *S* or *M* has `base` or `final` modifiers.
The modifier on *C* is there to satisfy the requirement that a subtype of a `base` or `final`
declaration is itself `base`, `final` or `sealed`. The anonymous mixin application class will
be immediately extended inside the same library, which is allowed by both `base` and `final`.,
and will not be used for anything else._

Adding `sealed` to an anonymous mixin application class with only one subclass ensures
that the subclass extending the mixin application class can be used
in exhaustiveness checking of the sealed superclass.
This is necessary since the anonymous mixin application class itself cannot be referenced.

### `@reopen` lint

We don't specify lints and metadata annotations in the language specification,
so this part of the proposal will not become a formal part of the language.
Instead, it's a suggested part of the overall user experience of the feature.

A metadata annotation `@reopen` is added to package [meta][] and a lint
"implicit_reopen" is added to the [linter][]. When the lint is enabled, a lint
warning is reported if a class or mixin is not annotated `@reopen` and it:

*   Extends or mixes in a class, mixin, or mixin class marked `interface` or
    `final` and is not itself marked `interface` or `final`.

[meta]: https://pub.dev/packages/meta
[linter]: https://dart.dev/guides/language/analysis-options#enabling-linter-rules

## Runtime semantics

There are no runtime semantics.

## Versioning

The changes in this proposal are guarded by a language version. This makes the
restriction on not allowing classes to be used as mixins by default
non-breaking.

*   `base`, `interface`, `final`, `sealed` and `mixin` can only be applied to
    classes and mixins in post-feature libraries.

*   When the `base`, `interface`, `final`, `mixin`, or `sealed` modifiers are
    placed on a class or mixin, the resulting restrictions apply to all other
    libraries, even pre-feature libraries.

    *In other words, we gate being able to _author_ the restrictions to
    post-feature libraries. But once a type has those restrictions, they apply
    to all other libraries, regardless of the versions of those libraries.
    "Ignorance of the law is no defense."*

*   We would like to add modifiers to some classes in platform (i.e. `dart:`)
    libraries when this feature ships. But we would also like to not immediately
    break existing code. To avoid forcing users to immediately migrate,
    declarations in pre-feature libraries can ignore *some*
    `base`, `interface` and `final` modifiers on *some* declarations
    in platform libraries.
    Instead, users will only have to abide by those restrictions
    when they upgrade their library's language version.
    _It will still not be possible to, e.g., extend or implement the `int` class,
    even if will now have a `final` modifier._

    This is a special case behavior only available to platform libraries.
    Package libraries should use versioning to to introduce breaking
    restrictions instead, and those libraries can then rely on the restrictions
    being enforced.

### Compatibility

When upgrading your library to the new language version, you can preserve the
previous behavior by adding `mixin` to every class declaration that can be used
as a mixin. If the class defines a generative constructor or extends anything
other than `Object`, then it already cannot be used as a mixin and no change is
needed.

## Implementation and documentation suggestions for usability

*This section is non-normative.  It's a set of suggestions to implementation and
documentation teams to help ensure that the feature is easy for users to use and
discover.*

### Errors, error recovery, and fixups

First of all, to the extent that it's reasonably feasible to do so, we should
try to make the parser understand that any time it sees a top level sequence of
any of the keywords `sealed`, `abstract`, `final`, `interface`, `base`, `mixin`,
or `class`, the user is trying to declare something class-like or mixin-like,
even if they left out an important keyword, used conflicting keywords, or put
keywords in the wrong order.  That way we can issue errors whose IDE fixups will
help the user clean up their class or mixin declaration, rather than just
`unexpected {` or something.  For example, this should be recognized by the
parser as an attempt to make a mixin or class:

```dart
interface sealed C {
  ...
}
```

(The parser will obviously issue an error, but it should still fire the
appropriate events to allow the analyzer to create a `ClassDeclaration` AST
node, and it should analyze the things inside the curly braces as class
members).

If the keywords aren't in the proper order (`sealed`/`abstract`, then
`final`/`interface`/`base`, then `mixin`, then `class`), or if a keyword was
repeated, the parser error should be on the first keyword token that's out of
order or repeated, and the fixup should offer to fix the order by sorting and
de-duplicating the keywords appropriately.  So in the example above, the "wrong
order" error should be on the keyword `sealed`, and the fixup should change it
to `sealed interface`, which is still an error for other reasons, but is at
least in the right order now.

With order and duplication out of the way, that leaves 127 possible combinations
of the 7 keywords.  The remaining error cases (and their associated IDE fixups)
are:

- Did you say both `abstract` and `sealed`?  Drop `abstract`; it’s redundant.
  Now there's only 95 possibilities.

- Did you say both `interface` and `final`?  Drop `interface`; it’s redundant.
  Now there's only 71 possibilities.

- Did you say both `base` and `final`?  Drop `base`; it’s redundant.  Now
  there's only 59 possibilities.

- Did you say both `interface` and `base`?  Say `final` instead.  Now there's
  only 47 possibilities.

- Did you say neither `mixin` nor `class`?  You have to pick one or the other or
  both.  The fixup can probably safely assume you mean `class`.  (Exception: if
  you just said `interface` and no other keywords, you probably mean `abstract
  class`).  Now there's only 36 possibilities.

- Did you say both `sealed` and `final`?  Drop `final`; it’s redundant.  Now
  there's only 33 possibilities.

- Did you say both `sealed` and `base`?  Drop `base`; it’s redundant.  Now
  there's only 30 possibilities.

- Did you say both `sealed` and `interface`?  Drop `interface`; it’s redundant.
  Now there's only 27 possibilities.

- Did you say both `mixin` and `class`, as well as one of the following
  keywords: `sealed`, `interface`, or `final`?  Drop `class` and replace
  `extends M` with `with M` wherever it appears in your library.  Now there's
  only 22 possibilities.

- Did you say both `abstract` and `mixin`, but not `class`?  Drop `abstract`;
  it’s redundant.  Now we are down to the 18 permitted possibilities.

If we take this sort of approach, then users who don't love reading
documentation will be able to just experimentally string together combinations
of the keywords we've made available to them, and the errors and fixups will
guide them to something valid, and then they can play around and see the effect.

### Introducing the feature to users

If we assume that most users will have access to the IDE fixups noted above, it
suggests that a nice way to introduce the feature to folks would be to gloss
over what combinations are redundant or contradictory, and just tell them in
plain English what each keyword does.  Users who love reading documentation can
read further and find out which combinations are prohibited; users who don't can
just try them out, and the IDE will train them which combinations are valid over
time.  So the core of the feature becomes explainable in just seven lines, three
of which are just restatements of things the user was already familiar with.
Something like:

- `sealed` means "this type has a known set of direct subtypes, so switching on
  it will require the switch to be exhaustive".

- `abstract` means "this type can't be constructed directly", but you already
  knew that.  It's only included in the list to help clarify that `abstract` is
  one of the seven keywords users should try combining together at the top of
  your declaration.

- `interface` means "this type can't be extended from outside this library".

- `base` means "this type can't be implemented from outside this library".

- `final` means "this type can neither be extended nor implemented from outside
  this library".

- `mixin` means "this type can be used in mixin-like ways, i.e. it can appear in
  the 'with' clause of other classes".  Granted, this is kind of a circular
  definition, but this explanation is intended for programmers familiar with
  Dart 2.19, and they're already familiar with mixins.

- `class` means "this type can be used in class-like ways, i.e. it can be
  extended, or constructed, unless otherwise forbidden".  Again, this is a
  circular definition, but our audience obviously already knows what classes
  are.  Including it in the list helps make it clear that we're putting mixins
  and classes on equal footing, and helps clarify why `mixin class` is a
  reasonable thing.

(Note that this list is deliberately in the order required by the grammar).

Obviously there are plenty of details left out of this description.  But
hopefully it should be enough to get people started using the feature, and the
errors and fixups would help keep them on the rails.

## Changelog

1.6

- Add implementation suggestions about errors, error recovery, and fixups for
  class modifiers.

1.5

- Fix mixin application grammar to match prose where `mixin` can't be applied
  to a mixin application class.

1.4

- Update rules to close loopholes on classes that don't want to expose
  interfaces (#2755, #2757).
- Only allow mixing in `mixin` and `mixin class` declarations,
  even inside the same library.
- Specify modifiers for anonymous mixin application classes.

1.3

- Specify and update restrictions on `mixin class` declarations to allow
  trivial generative constructors.

- Specify that "mixin application" class declarations (`class C = S with M`)
  cannot be `mixin class` declaration, but can use other modifiers

1.2

- Specify how all modifiers interact with language versioning (#2725).

1.1

- Clarify that all modifiers are gated behind a language version.

- Rationalize which modifiers can be combined with `mixin class` and specify
  behavior of `mixin class`.

- Rename to "Class modifiers" with the corresponding experiment flag name.
