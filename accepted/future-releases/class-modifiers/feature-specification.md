# Class modifiers

Author: Bob Nystrom, Lasse Nielsen

Status: Accepted

Version 1.7

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
    the interface of the declaration. _This also applies transitively
    to all subtypes, since implementing a subtype also means implementing
    the superinterface._

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
    it comes at the expense of flexibility. If a user *wants* to remove a
    restriction, they have no ability to.

    This would contrast with `sealed` where you can have subtypes of a sealed
    type that are not themselves sealed. This is a deliberate choice because
    there's no *need* for the direct subtypes of a sealed to be sealed in order
    for exhaustiveness checking to be sound. Since exhaustiveness is the goal
    and Dart is permissive by default, we allow subtypes of sealed types to be
    unsealed.

    It also prevents API designs that seem reasonable and useful to me. Imagine
    a library for transportation with classes like:

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

```dart
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
declaration are `abstract`, `sealed`, `base`, `interface`, `final`, and
`mixin`. Only the `base` modifier can appear before a `mixin` declaration.

*The modifiers do not apply to other declarations like `enum`, `typedef`, or
`extension`.*

Many combinations don't make sense:

*   `base`, `interface`, and `final` all control the same two capabilities so
    are mutually exclusive.
*   `sealed` types cannot be constructed so it's redundant to combine with
    `abstract`.
*   `sealed` types already cannot be mixed in, extended or implemented
    from another library, so it's redundant to combine with `final`,
    `base`, or `interface`.
*   `mixin` as a modifier can obviously only be applied to a `class`
    declaration, which makes it also introduce a mixin.
*   `mixin` as a modifier cannot be applied to a mixin-application `class`
    declaration (the `class C = S with M;` syntax for declaring a class). The
    remaining modifiers can.
*   A `mixin` or `mixin class` declaration is intended to be mixed in,
    so its declaration cannot have an `interface`, `final` or `sealed` modifier.
*   A `mixin` declaration cannot be constructed, so `abstract` is redundant.
*   `enum` declarations cannot be extended, implemented, mixed in,
    and can always be instantiated, so no modifiers apply to `enum`
    declarations.

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

The grammar is:

```
classDeclaration  ::= (classModifiers | mixinClassModifiers) 'class' typeIdentifier
                      typeParameters? superclass? interfaces?
                      '{' (metadata classMemberDeclaration)* '}'
                      | classModifiers 'class' mixinApplicationClass

classModifiers    ::= 'sealed'
                    | 'abstract'? ('base' | 'interface' | 'final')?

mixinClassModifiers ::= 'abstract'? 'base'? 'mixin'

mixinDeclaration  ::= 'base'? 'mixin' typeIdentifier typeParameters?
                      ('on' typeNotVoidList)? interfaces?
                      '{' (metadata classMemberDeclaration)* '}'
```

## Static semantics

The modifiers introduce restrictions on which other declarations can
depend on the modified declaration, and how.
To express this, we first introduce some terminology that makes it
easy to express the relations between declarations.

### Terminology.

We distinguish libraries by whether they have this feature enabled,
and whether they are platform libraries.

*   A *pre-feature library* is a library whose language version is lower than
    the version this feature is released in.

*   A *post-feature library* is a library whose language version is at or above
    the version this feature is released in.

*   A *platform library* is a library with a `dart:...` URI. A platform library
    is always a post-feature library in an SDK supporting the feature,
    but for backwards compatibility, pre-feature libraries may ignore
    some modifiers in platform libraries, as if the library was also a
    pre-feature library.

We define the relations between declarations and the other declarations
they are declared as subtypes of as follow.

*   A declaration *S* is _the declared superclass_ of a `class` declaration
    *D* iff:
    * *D* has an `extends T` clause and `T` denotes *S*.
    * *D* has the form `... class ... = T with ...` and `T` denotes *S*.

    _A type clause `T` denotes a declaration *S* if `T` of the from
    <code>*id*</code> or <code>*id*\<typeArgs\></code>, and *id*
    is an identifier or qualified identifier which resolves to *S*,
    or which resolves to a type alias with a right-hand-side which
    denotes *S*._
    _(This allows us to refer to the "declared superclass" uniformly
    across mixin-application `class` declaration and a "normal" `class`
    declaration, even though the former cannot have any `extends` clause.
    A `class` declaration has at most one declared superclass declaration,
    it can have none if it's a non-mixin application declaration with no
    `extends` clause.)

*   A declaration *S* is a _declared mixin_ of a `class` or `enum` declaration
    which has a `with T1, ..., Tn` clause where any of `T1`,...,`Tn`
    denotes *S*.

*   A declaration *S* is a _declared interface_ of a `class`, `mixin class`,
    `mixin` or `enum` declaration which has an `implements T1, ..., Tn` clause
    where any of `T1`,...,`Tn` denotes *S*.

*   A declaration *S* is a _declared `on` type_ of a `mixin` declaration
    which has an `on T1, ..., Tn` clause where any of `T1`,...,`Tn` denotes *S*.

_We need these independently, but we also need the union of these relations,
capturing that a declaration depends directly on another in *any* way._

*   A declaration *S* is a direct superdeclaration of a declaration *D*
    iff *S* is a declared superclass, mixin, interface or `on` type of *D*.

_We then define the transitive closure of this relation, expression
that a declaration depends on another through any number of intermediate
declarations._

*   A declaration *S* is a proper superdeclaration of a declaration *D* iff
    either *S* is a direct superdeclaration of *D*, or there exists a
    declaration *P* such that *P* is a direct superdeclaration of *D* and
    *S* is a proper superdeclaration of *P*.

_The language prevents dependency cycles in declarations, because cycles prevent
subtyping from being well-defined. Because of that, the
"proper superdeclaration" relation is a directed acyclic relation.
Or alternatively, we could write the rule against cycles as it being
a compile-time error if any declaration *S* is a proper superdeclaration
of itself._

_Finally we define the reflexive closure of the proper superdeclaration
relations, because it's sometimes useful to talk about a the entire
super-hierarchy of a declaration including itself._

*   A declaration is a superdeclaration of a declaration *D* iff
    *S* is *D* or *S* is a proper superdeclaration of *D*.

_With all these syntactic relations between declarations in place,
we can specify the restrictions imposed by modifiers._

### Basic restrictions

It's a compile-time error if:

*   A declaration depends directly on a `sealed` declaration from another
    library. _No exceptions, not even for platform libraries._

    More formally:
    A declaration *D* from library *L* has a direct superdeclaration *S*
    marked `sealed` (so necessarily a `class` declaration) in a library
    different from *L*.

    ```dart
    // a.dart
    sealed class S {}

    // b.dart
    import 'a.dart';

    class E extends S {} // Error.
    class I implements S {} // Error.
    mixin O on S {}  // Error.
    class M with S {} // Error, for several reasons.
    ```

*   A class extends a declaration marked `interface` or `final` from
    another library _(with some exceptions for platform libraries)_.

    _(You cannot inherit implementation from a class marked `interface`
    or `final` except inside the same library. Unless you are in a
    pre-feature library and you are inheriting from a platform library.)_

    More formally:
    A declaration *C* from library *L* has a declared superclass declaration
    *S* marked `interface` or `final` from library *K*, and neither
    * *L* and *K* is the same library, nor
    * *K* is a platform library and *L* is a pre-feature library.

    ```dart
    // a.dart
    interface class I {}
    final class F {}

    // b.dart
    import 'a.dart';

    class C1 extends I {} // Error.
    class C2 extends F {} // Error.
    ```

*   A declaration implements another declaration, and the other
    declaration itself, or any of its super-declarations,
    are marked `base` or `final` and are not from the first declaration's
    library _(with some exceptions for platform libraries)_.

    _(You can only implement an interface if *all* `base` or `final`
    superdeclarations are inside your own library. Or if you're in
    a pre-feature library and all `base` or `final` superdeclarations
    are in platform libraries.)_

    More formally:
    A declaration *C* in library *L* has a declared interface *P*,
    and *P* has any superdeclaration *S*, from a library *K*,
    which is marked `base` or `final` _(including *S* being *P* itself)_,
    and neither:
    * *K* and *L* is the same library, mor
    * *K* is a platform library and *L* is a pre-feature library.

    ```dart
    // a.dart
    base class S {}
    base mixin M {}
    final class F {}

    // b.dart
    import 'a.dart';

    // Direct implementation of other-library `base` class.
    base class D implements S {} // Error
    mixin N implements M {} // Error.
    enum E implements F { e } // Error.

    // Indirect implementation of other-library `base` class.
    base class P extends S {}
    base class C implements P {} // Error.
    ```

*   A declaration has a `base` or `final` superdeclaration,
    and is not itself marked `base`, `final` or `sealed`.
    _This also applies to declarations inside the same library._

    _(A `base` or `final` declaration doesn't expose an implementable
    interface, and for that to matter, nor must any of its subclasses.
    The entire subclass tree below such a declaration must prevent
    implementation too.)_

    More formally:
    A `class`, `mixin class` or `mixin` declaration *D* in a post-feature
    library has any proper superdeclaration marked `base` or `final`,
    and *D* is not itself marked `base`, `final` or `sealed`.

    ```dart
    // a.dart
    base class B {}
    sealed class S extends B {}
    enum E extends S { e }

    class C0 extends B {} // Error.
    class C1 implements B {} // Error.

    base mixin BM {}

    mixin M0 implements B {} // Error
    mixin M1 on B {} // Error

    // b.dart
    import 'a.dart';

    base class V1 extends B {}
    final class V2 extends B {}
    sealed class V3 extends B {}

    enum E2 with BM { e } // Not a class/mixin class/mixin declaration.

    class C2 extends B {} // Error.
    class C3 with BM {} // Error.
    ```

_An `enum` declaration still cannot be implemented, extended or mixed in
anywhere, independently of modifiers._

A type alias (`typedef`) cannot be used to subvert these restrictions
or any of the restrictions below. The actual superdeclaration used in
these checks is the one that the type alias expands to. *Note that
the library where the _type alias_ is defined does not come into play.
Type aliases cannot be marked with any of the new modifiers.*

### Mixin restrictions

As before, a declared superclass declaration must be a `class` declaration
_(you can only extend another class)_ and a declared interface declaration
must be a `class` or `mixin` declaration, and now it may also
be a `mixin class` declaration _(you can only implement something which
has an interface, and not `enum`s which cannot be implemented at all)_.

The new `mixin class` declaration has a set of syntactic rules which
ensures that it can be used as both a `class` and a `mixin`.

It's a compile-time error if a `mixin class` declaration:
*   has an `interface`, `final` or `sealed` modifier. _This is baked
    into the grammar, but it bears repeating._
*   has an `extends` clause,
*   has a `with` clause, or
*   declares any non-trivial generative constructor.

A *trivial generative constructor* is a generative constructor that:
*   Is not a redirecting constructor _(`Foo(...) : this.other(...);`),
*   declares no parameters (parameter list is precisely `()`),
*   has no initializer list (no `: ...` part, so no asserts or initializers, and
    no explicit super constructor invocation),
*   has no body (only `;`), and
*   is not `external`. _An `external` constructor is considered to have an
    externally provided initializer list and/or body._

_A trivial generative constructor may be named or unnamed,
and may be `const` or non-`const`._
A *non-trivial generative constructor* is a generative constructor which
is not a trivial generative constructor.

_A trivial generative constructor has no effect on object construction,
so it can be safely ignored and omitted when the `mixin class` is used
as a mixin, but it allows the `mixin class` declaration to also be used a
superclass, even for subclasses with constant constructors._

Examples:

```dart
mixin class C {
  // Trivial generative constructors:
  C();
  const C();
  C.named();
  const C.alsoNamed();

  // Non-trivial generative constructors:
  C(int x); // Error.
  C(this.x); // Error.
  C() {} // Error.
  C(): x = 0;
  C(): assert(true); // Error.
  C(): super(); // Error.
  C(): this.named();

  // Not generative constructors, so neither trivial generative nor non-trivial
  // generative:
  factory C.f = C;
  factory C.f2() { ... }

  int? x;
}

// Invalid mixin classes.
mixin class E extends Object {} // Error.
mixin class E with C {} // Error.
```

There are also changes to which declarations can be mixed in.

A post-feature class can no longer be used as a mixin unless it's declared
as a `mixin class`. In post-feature code, you can *only* mix in
`mixin` or `mixin class` declarations
Pre-feature code is not changed, so some pre-feature classes can still
be mixed in, and the SDK exception allows pre-feature code to pretend
platform libraries are still pre-feature libraries.

The formal rules for which declarations can be mixed in become:


It's a compile-time error if a `class` or `enum` declaration *D* from
library *L* has *S* from library *K* as a declared mixin, unless:
*   `S` is a `mixin` or `mixin class` declaration _(necessarily from
    a post-feature library)_, or
*   `S` is a non-mixin `class` declaration which has `Object` as superclass
    and declares no generative constructor, and either
    * *K* is a pre-feature library, or
    * *K* is a platform library and *L* is a pre-feature library.

_That is, a class not marked `mixin` can still be used as a mixin when the
class's declaration is in a pre-feature library and it satisfies specific
requirements._

_For pre-feature libraries, we cannot tell if the intent of `class` was
"just a class" or "both a class and a mixin". For compatibility, we assume
the latter, even if the class is being used as a mixin in a post-feature
library where it does happen to be possible to distinguish those two
intents._

### `@reopen` lint

We don't specify lints and metadata annotations in the language specification,
so this part of the proposal will not become a formal part of the language.
Instead, it's a suggested part of the overall user experience of the feature.

A metadata annotation `@reopen` is added to package [meta][] and a lint
"implicit_reopen" is added to the [linter][]. When the lint is enabled, a lint
warning is reported if a class is not annotated `@reopen` and it:

*   extends a class marked `interface` or `final`
    and is not itself marked `interface` or `final`, or
*   extends a `sealed` class which itself transitively extends a class marked
    `interface` or `final`.

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

*   We will add modifiers to some classes in platform (i.e., `dart:`)
    libraries when this feature ships. But we will also like to not immediately
    break existing code. To avoid forcing users to immediately migrate,
    declarations in pre-feature libraries can ignore *some*
    `base`, `interface` and `final` modifiers on *some* declarations in platform
    libraries, and can mix in non-`mixin` classes from platform libraries,
    as long as such a class has `Object` as superclass and declares
    no constructors. ([legacy-mixin-tests][]).
    Instead, users will only have to abide by those restrictions when they
    upgrade their library's language version to 3.0 or later.
    _It will still not be possible to, e.g., extend or implement the `int` class,
    even if will now have a `final` modifier._
    Going through a pre-feature library does not remove transitive restrictions
    for code in post-feature libraries. Any post-feature library declaration
    which has a platform library class marked `base` or `final` as a
    superinterface must be marked `base`, `final` or `sealed`,
    and cannot be implemented locally, even if the superinterface chain goes
    through a pre-feature library declaration, and even if that declaration
    ignores the `base` modifier.

    This ability to ignore modifiers only apply to platform libraries
    accessed from pre-feature libraries, because code doesn't get to
    decide the version of the SDK that it runs on, unlike how a package
    can depend on specific versions of another package.
    Packages should use package versioning to introduce breaking restrictions
    instead (a major version semantic version upgrade), but those libraries
    can then rely on the restrictions being enforced.
    The platform libraries will bear the cost of not being able to rely
    on its own modifiers until all code in a program is language version 3.0
    later.

[legacy-mixin-tests]: https://dart-review.googlesource.com/c/sdk/+/287665

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

1.7

* Update the modifiers applied to anonymous mixin applications to closer
  match the superclass/mixin modifiers.
* State that `enum` declarations count as `final`.
* Rephrase semantics completely, based only on relations between declarations.
* Say that pre-feature libraries can mix in non-`mixin` platform library classes
  which satisfy the old requirements for being used as a mixin.

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
