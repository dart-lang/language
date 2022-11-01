# "Closed" and "base" types

Author: Bob Nystrom

Status: In-progress

Version 1.0

This proposal specifies `closed` and `base` modifiers on classes and mixins,
which allow an author to prohibit the type being extended or implemented,
respectively.

This proposal is a subset of the [type modifiers][] strawman, which also
contains most of the motivation. It is split out here because the type modifiers
strawman also proposes prohibiting classes being used as mixins, which is a
larger breaking change. This proposal is non-breaking.

[type modifiers]: https://github.com/dart-lang/language/blob/master/working/type-modifiers/feature-specification.md

## Motivation

Why might a class or mixin author want to *remove* capabilities? Doesn't that
just make the type less useful? The type does end up more restricted, but in
return, there are more invariants about the type that you can rely on being
true. Those invariants may make the type easier to understand, maintain, evolve,
or even just to use.

### Preventing subclassing

Most types contain methods that invoke other methods on `this`, for example:

```dart
class Account {
  int _balance = 0;

  bool canWithdraw(int amount) => amount <= _balance;

  bool tryWithdraw(int amount) {
    if (amount <= 0) throw ArgumentError("Amount must be positive.");

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
while also inheriting concrete implementations of other methods that may
assume you haven't.

If we can prevent Account from being subclassed, we ensure that when
`tryWithdraw()` calls `canWithdraw()`, it calls the actual `canWithdraw()`
method we expect.

Note that it's *not* necessary to prevent *implementing* `Account` for this use
case. If you implement `Account`, you inherit *none* of its concrete
implementation, so you don't end up with methods like `tryWithdraw()` whose
behavior is broken.

### Preventing implementing

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

This code may fail with a `NoSuchMethodException` at runtime. Spot the bug?
There's nothing preventing someone from passing in their own implementation of
`Account` defined in another library that doesn't have a `_balance` field. In
general, it's not safe to assume any object coming in to your library actually
has the private members you expect, because it could be an outside
implementation of the class's interface.

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
But if an unrelated type could implement `Handle`'s interface, then there's
no guarantee that every instance of `Handle` has actually gone through that
constructor.

If the constructor is doing validation or caching, you might want to assume that
all instances of the type must run it. But if the class's interface can be
implemented, then it's possible to route around the constructor and break the
class's invariants.

By preventing a class from having its interface implemented, you ensure that
every instance of the class you will ever see has all of the private members you
defined on it and has gone through the constructors you defined.

## Syntax

A class declaration may be preceded with the identifiers `closed` and/or `base`:

```
classDeclaration ::=
  'closed'? 'abstract'? 'base'? 'class' identifier typeParameters?
  superclass? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
  | 'closed'? 'abstract'? 'base'? 'class' mixinApplicationClass
```

A mixin declaration may be preceded with the identifier `base`:

```
mixinDeclaration ::= 'base'? 'mixin' identifier typeParameters?
  ('on' typeNotVoidList)? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
```

### With sealed types

This proposal will likely build on top of the [sealed types][] proposal, in
which case the full grammar is:

[sealed types]: https://github.com/dart-lang/language/blob/master/working/sealed-types/feature-specification.md

```
classDeclaration ::=
  classModifiers 'class' identifier typeParameters?
  superclass? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
  | classModifiers 'class' mixinApplicationClass

classModifiers ::= 'sealed' | 'abstract'? 'closed'? 'base'?

mixinDeclaration ::= ('sealed' | 'base')? 'mixin' identifier typeParameters?
  ('on' typeNotVoidList)? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
```

Note that the grammar disallows combining `sealed` with `closed` or `base` since
a sealed type is already prohibited from being extended or implemented outside
of the current library. We *do* allow a class to be marked `closed abstract
base` instead of treating `sealed` as a synonym for that because there are
subtle differences if the class has subtypes in the same library:

```dart
// lib.dart
sealed class A {}
class B extends A {}
class C extends A {}

closed abstract base class D {}
class E extends D {}
class F extends D {}
```

Here, pattern matching on `B` and `C` exhaustively covers `A`, but matching on
`E` and `F` does not cover `D`. Marking `D` as `closed abstract base` means that
users are prevented from extending, implementing, or constructing it, but the
maintainer of `lib.dart` can freely add new subtypes of `D` without breaking
users by causing what were exhaustive pattern matches to no longer be
exhaustive. In other words, it gives the supertype author the ability to opt
out of exhaustiveness checks while still defining a type that is otherwise as
restricted as `sealed`.

### Static semantics

It is a compile-time error to:

*   Extend a class marked `closed` outside of the library where it is defined.

*   Implement a type marked `base` outside of the library where it is defined.

*   Extend or mix in a type marked `base` without also being marked `base`.
    *This ensures that a subtype can't escape the `base` restriction of its
    supertype by offering its _own_ interface that could then be implemented
    without inheriting the concrete implementation from the supertype. Note that
    this restriction applies even when both types are in the same library.*

*   Mix in a class marked `closed` or `base`. *We want to eventually move away
    from classes as mixins. We don't want to break existing uses of classes as
    mixins but since no existing code is using these modifiers, we can prevent
    classes using those modifiers from also being used as mixins.*

A typedef can't be used to subvert these restrictions. When extending,
implementing, or mixing in a typedef, we look at the library where type the
typedef resolves to is defined to determine if the behavior is allowed. *Note
that the library where the _typedef_ is defined does not come into play.*

### Runtime semantics

There are no runtime semantics.
