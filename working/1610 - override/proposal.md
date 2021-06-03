# Dart Override Language Feature

## Background and motivation

Dart currently has an [`@override`](https://api.dart.dev/stable/2.10.4/dart-core/override-constant.html) annotation declared in the `dart:core` library. It is used to mark that an instance method is intended to override a super-interface declaration. The analyzer warns if an annotated member declaration has no super-interface declaration with the same name. If the [annotate_overrides](https://dart-lang.github.io/linter/lints/annotate_overrides.html) lint is enabled, the analyzer also warns if a non-annotated member has a super-interface declaration with the same name.

The purpose of the annotation is to catch errors where a method name is mistyped or a super-interface member changes name. The lint is there to encourage users to use the annotation.

We have chosen to enable the lint by default in the set of lints recommended by the Dart team, meaning that we want all Dart code to use the annotation on every overriding instance member, and with the intend to later turn the annotation into a language feature instead of an annotation.

This is not without contention. The annotation is completely redundant, tools always know whether a member declaration overrides something or not. Having to write 10+ extra characters for something completely redundant is not how Dart is otherwise designed. On the other hand, that redundancy is what allows us to detect errors. If IDEs would display a marker on all overriding members, users would easily be able to *see* whether the intended override is mistyped or not. It wouldn't catch super-interface member renames, but that's also a breaking change and not something which should come as a complete surprise to subclass authors&mdash;if you upgrade your dependency to a new major version, you should read the release notes!

_The `override` is in `dart:core` rather than `package:meta`, and has been since it was introduced. Because of that, in `dart:core`, the `override` annotation is used by people who don't otherwise use annotations from `package:meta`. Users generally think of it as "part of the language"._

## Proposal

The simplest solution is to make `override` a built-in identifier and allow it as a modifier on instance member declarations. Example:

```dart
class Foo {
  override
  int foo() => 42;
}
```

Then we make it a compile-time error to not have the `override` modifier on something which overrides, and a compile-time error to have it on something which doesn't override.

The modifier goes before all other modifiers (including `external`). It refers to the context and to the declaration itself, so it feels fitting to put it "around" the entire declaration, more than those modifiers which merely change implementation details. The formatter can choose to put it on a line of its own, for maximum backwards compatibility, but that's easily configurable.

When applied to a non-final instance variable, we lose some precision. We propose no syntax to make the override apply to only the setter or the getter of a variable declaration, but it's possible for the super-interfaces to contain only a getter or a setter. In that case we allow and require the `override` modifier if the declaration overrides at least a getter or a setter from a super-interface.

In summary: 

* We make `override` a built-in identifier.
* We allow `override` to precede any instance member declaration, as the first modifier of the declaration. *(It's a compile-time error if `override` is applied to a non-instance member declaration)*.
* We make it a compile-time error if:
  * A non-variable instance member declaration, or an instance variable declaration which introduces only a getter, with name *n* in a class declaration *C* has an `override` modifier, and no super-interface of *C* declares a member named *n*.
  * An instance variable declaration with name *n* in a class declaration *C*, which introduces both a getter and a setter,  has an `override` modifier, and no super-interface of *C* declares a member named *n* or a setter name *n=*.
  * A non-variable instance member declaration, or an instance variable declaration which introduces only a getter, with name *n* in a class declaration *C* **does not** have an `override` modifier, and any super-interface of *C* declares a member named *n*.
  * An instance variable declaration with name *n* in a class declaration *C*, which introduces both a getter and a setter,  **does not** have an `override` modifier, and any super-interface of *C* declares a member named *n* or a setter name *n=*.

## Migration

This is a breaking change. It introduces new syntax, and requires you to use that new syntax. As such, all code must be migrated to the language version introducing the feature.

Migration is easily automatable: Add `override` to all declarations which need it, remove existing occurrences of`@override` . Which declarations need an `override` can be determined entirely from declarations and name resolution, without even having to understand types or interface signatures. A super-interface declares a member with a name if the interface declaration has a declaration with that name, or if its transitive super-interfaces declares a member of that name.

## Tool support

Every tool needs to support the new syntax, and compilers and the analyzer needs to support the new compile-time errors. That parts should be mostly uncontroversial.

### Formatter

The formatter needs to decide how to format the new modifier. We propose to keep it on a line by itself, like the current annotation. That'll cause minimal changes to existing code (you literally just remove the `@` from `@override`).

Since the modifier only applies to instance members, there are no complicated cases to consider.

### Migration tool

The migration tool should understand the rules, insert `override` and remove `@override` annotations when migrating.

### IDE integration/analysis server

The IDE integration should offer quick-fixes for:

* Adding an `override` modifier to a declaration which needs it.
* Removing an `override` modifier from a declaration which doesn't need it.
* Renaming a declaration with an `override` modifier which doesn't need it, if there is possibly misspelled super-interface member that it was likely intending to override.
* Renaming a declaration without an override modifier which clashes with a super-interface member of the same name, especially if the signatures don't match.

Further, it would make sense to auto-complete a cursor right after the word `override` (in a potentially valid position) with signatures for super-interface members. Maybe even allow initialisms of the name, so a cursor after `override fBZ` could offer completing to `override int fooBarZip()` if a super-interface declares that signature, and restrict the options to super-interface signatures after an `override`.

## Other languages

Other languages have similar features. This compares those features to this proposal to see whether there is something we would want to include or change. The other languages referenced here have some notion of signature based overloading, but that doesn't appear to influence the override pattern when you actually do override.

### Java

Java has an [`@Override` annotation](https://docs.oracle.com/javase/tutorial/java/annotations/predefined.html#:~:text=%40Override%20annotation). It works precisely the same as Dart's `@override` annotation, but without the lint that Dart has. (There are probably style guides requiring the use of the annotation, but it's not official). There does not appear to be anything new to learn from Java here.

### C++

The C++11 language added `override` as something you can write on virtual member declarations. It's not required, but if you use it, you get an error if you don't actually override anything. It's also equivalent to the Dart or Java annotation, without the lint to require you to use it.

### Kotlin

Kotlin requires `override` on overriding members. It is equivalent to Dart with the lint, or this feature as written.

Kotlin also allows you to seal a method against overriding by adding `final`. A plain `final` method is effectively non-virtual, a `final override` method just prevents further overrides.

Dart does not have `final` declarations. Adding them is an interesting possibility, but requires some extra thought because Dart doesn't distinguish between interfaces and classes. It's not an obvious addition to the `override` feature, more like a separate "sealing" feature of its own.

### C#

The C# type system allows `new`,`override` and `final` as markers on declarations, and allows you to declare a `new` method with the same name (and signature, they have overloading) which doesn't virtually override the corresponding superclass method. Instead it introduces a *new* virtual method on the subclass, and which *virtual* method family you call depends on the type of the receiver (there are overrides if you want something else). A single class can implement both `int Foo::foo(int)` and `int Bar::foo(int)` at the same time. 

You also have to declare members as `virtual`, otherwise they aren't.

Dart could do something similar, but it's a very large change to the object model, and it requires some new syntax for the scope overrides. Much larger change than just adding `override`.

## Alternatives

### Shorter syntax

The syntax verbosity isn't changed significantly by removing the `@`, and one of the reasons that override was originally not made part of the language was that it was both redundant and verbose, and some people didn't want to have to write it.

Maybe it will be easier to win over users with a shorter syntax. Consider adding `^` before the name of a declaration instead. Example:

```dart
int ^foo() => 42;
```

where the `^` means "overriding" in the same sense as the `override` modifier above. An operator needs an anchor, more than a modifier word, and almost all instance member declarations have names, so it's a consistent place to add an operator which works both for fields and methods. The exception is `operator` declarations, where the `^` would go before `operator`. Might look slightly odd for `^operator ^`.

The `^` is intended to "point to the supertype". The same completions could be offered after `^` as suggested after `override` above, and the same quick-fixes make sense too.

### Override only omitting types

We currently allow you to omit types from instance member declarations, both return type and parameter types. If you override something, you will inherit types from that something. If not, you default to `dynamic`. 

With the `override` feature, we could require you to write types on all non-overriding members, as a step towards "no implicit dynamic". Or we could do that later, as part of a more coherent "no implicit dynamic" feature.

## Interaction with future language features

### New getter/setter syntax

We have repeatedly considered new syntax for getter and setter declarations, one which treats them more as parts of the same property, rather than as individual and unrelated members.

One such syntax proposal could be:

```darrt
int foo {get; set}
```

which is equivalent to the current `int foo;` in that it introduces implicit default implementations for `get i` and `set i`.

Something like `int foo {get}` would then be equivalent to `final int foo;` (getter only, no setter, can only be set by initializer), and you can write custom implementations as:

```dart
int foo {
  get => _y; 
  set(v) => _y = v;
}
```

In either case, with explicit declarations for the default getter and setter, we can also explicitly override only one of them:

```dart
int foo {override get; set}
```

would mean overriding a getter, and not a setter. That's something we can't currently declare for fields.

All in all, the `override` feature seems to interact *positively* with better getter/setter declarations.

