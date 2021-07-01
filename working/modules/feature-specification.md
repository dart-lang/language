# Modules

**TODO: This proposal is incomplete and in-progress. Any of this may change and
we have not committing to shipping anything.**

Modules aggregate Dart libraries into larger collections that can be compiled
separately. A modular compiler can compile each module independently and the
declarative module structure enables a compiler to know which Dart source
changes require which modules to be rebuilt.

Modules also intend to make large-scale code maintainance and reuse clearer and
more robust.

A module specifies:

*   A set of Dart libraries that it contains.
*   Its **dependencies**, the set of other modules that it depends on.
*   Whether or not the module is public or private to the package it belongs to.

There are a couple of restrictions:

*   A module may only contain libraries from the same package.
*   A library may only import (or export or part) libraries that are either in
    its own module, or in modules that the library's module directly depends on.
*   Module dependencies may not have cycles. The module dependency graph is a
    [DAG][]. (However, *within* a module, *libraries* may freely import each other,
    including cycles.)
*   A module cannot depend on a private module from another package.

[dag]: https://en.wikipedia.org/wiki/Directed_acyclic_graph

The first two rules mean that there is a strict nesting: packages *contain*
modules which *contain* libraries (which may contain parts).

In return for following these rules, **a change to a library in module A will
never affect the static analysis, compilation, or runtime behavior of a library
in module B unless A is a dependency of B (directly or indirectly).** A
"downstream" change to some code never requires anything "upstream" of it to be
recompiled or reanalyzed. Given a set of modules, a tool or compiler can process
them separately in [topological order][topo] and will never need to reprocess a
module.

[topo]: https://en.wikipedia.org/wiki/Topological_sorting

## Motivation

**TODO**

## Authoring modules

**TODO**

## Capability controls on types

There are three fundamental kinds of entities in Dart's semantics:

*   A **class** has a set of member declarations and a superclass (which may be
    Object). You can use a class **construct** new instances (if not abstract)
    and/or you can **extend** one as a superclass.

*   An **interface** is a set of member *signatures*.

*   A **mixin** is a set of member declarations. Unlike a class, a mixin does
    *not* have a superclass. You have to apply the mixin to some concrete
    superclass in order to get a class that you can construct.

Dart's syntax somewhat obscures this. There is no dedicated syntax for declaring
an interface. Until recently there was also no syntax for declaring a mixin.
Instead, a class declaration can, unless prohibited by its own structure, be
used as an interface, superclass, or mixin.

Inferring interfaces from classes and mixins a useful tool to avoid the
redundancy found in Java and C# code. It provides consumers of the class maximum
flexibility. But it comes at a cost:

*   Since a class may be used as an interface, adding a method is potentially a
    breaking change, even if the author never intended the class's interface to
    be implemented. In practice, many class maintainers *document* how the class
    should be used and don't consider it a breaking change (and thus don't
    change the package's major version) if they change a class in a way would
    break users not following that documentation.

*   When a class implicitly permits anything, it can be hard to tell how it is
    *intended* to be used. Restricting the options can provide a simpler, more
    guided API.

*   Changes to a class can break one of its capabilities. If you change a
    generative constructor to a factory constructor, that will break any
    subclasses that chained to that constructor. Since the language doesn't
    know whether or not you intend that class to be subclassed in other
    packages, it can't alert you to the consequences of that change.

*   In order to get [exhaustiveness checking][ex] on pattern matching, we need
    some notion of a sealed family of types. Otherwise, there's no way to tell
    if a switch case has covered all types.

[ex]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md#exhaustiveness-and-reachability

Because of these, users ask for control over the affordances a declaration
provides ([349][], [704][], [987][]). Modules are a natural boundary for those
restrictions.

[349]: https://github.com/dart-lang/language/issues/349
[704]: https://github.com/dart-lang/language/issues/704
[987]: https://github.com/dart-lang/language/issues/987

Note that the above problems only come into play when *unknown code* works with
a type. Thus these restrictions only apply to code using a type outside of the
module where the type is declared. Inside the types's own module, you are free
to use types however you want. It's your code.

### Types of types and capabilities

Restating the above, there are four affordances a type might offer:
**construct**, **extend**, **implement**, and **mix in**. An analysis of the
class declarations in Google's corpus shows these combinations are most common:

```
Construct               63.93% 6605
(none)                  14.09% 1456
Implement                9.77% 1009
Extend                   6.47%  668
Construct + Implement    2.36%  244
Mixin                    1.25%  129
```

All other combinations are less than 1%. Every combination occurs in practice,
though the few examples of combinations involving mixins and classes seem to be
historical from the time before Dart's dedicated mixin syntax.

## Mixins and classes

Combinations of classes and interfaces make sense. Likewise, it seems natural to
derive an interface from a mixin. But deriving both a class and a mixin from the
same declaration has proven to be confusing.

A mixin, by definition, has no superclass. In order to construct or extend
something, it must be a full-formed class with an inheritance chain all the way
up to Object. When you derive a mixin from a class today, Dart discards the
superclass and any inherited methods.

This is a continuing source of confusion for users, which is one reason we added
dedicated `mixin` syntax. Now that we have language versioning, we can complete
that transition. With this proposal, **a class declaration no longer defines an
implicit mixin declaration.** The only way to create a mixin is using `mixin`.

### Syntax

We support all combinations of the above four capabilities, except for
combinations with Mixin + Construct or Mixin + Extend.

Following Dart's existing syntax, we use `class` to define classes, `mixin`
define mixins, and `abstract` to prevent constructing. Following Java and
others, we use `interface` (as a modifier here) to allow implementing. Following
Swift and Kotlin, we use `open` to allow subclassing.

The updated grammar is:

```
topLevelDeclaration ::=
    classDeclaration
  | mixinDeclaration
  // existing rules...

classDeclaration ::= 'open'? 'interface'? 'abstract'? 'class' identifier
  typeParameters? superclass? interfaces?
  '{' (metadata classMemberDeclaration)* '}'

mixinDeclaration ::= 'interface'? 'mixin' identifier typeParameters?
  ('on' typeNotVoidList)? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
```

That yields these combinations:

```
class                         // 63.93% Construct
abstract class                // 14.09% (none)
interface abstract class      //  9.77% Implement
open abstract class           //  6.47% Extend
interface class               //  2.36% Implement Construct
mixin                         //  1.25% Mix-in
open class                    //  0.86% Extend Construct
open interface abstract class //  0.76% Implement Extend
open interface class          //  0.20% Implement Extend Construct
interface mixin               //  0.09% Mix-in Implement
```

Using `abstract class` to opt out of constructing is pretty verbose, especially
when combined with other modifiers. We could conceivably drop it from classes
that have `interface`:

```
interface abstract class      -> interface
open interface abstract class -> open interface
```

But it might be confusing that a type declared using only `interface` does in
fact define a class that may have concrete methods and even be constructed and
used as a class inside the module. Dart users today are already used to using
`abstract class` to declare interfaces, so this isn't too much of a stretch.
Also, this leaves `interface` available as potential future syntax for defining
a pure interface, if a need for such thing should arrive.

### Static semantics

Within a module, despite all the new modifiers, the semantics are roughly the
same. The rules for using a type within its module are as permissive as possible
and are based on the structure of the type itself, as in current Dart:

*   It is a compile-time error to invoke a generative constructor of a class if
    the class defines or inherits any unimplemented abstract members. *You can
    directly construct abstract classes internally if it wouldn't cause a
    problem to do so. Mixins never have generative cosntructors.*

*   It is a compile-time error to extend a class that has at least one factory
    constructor and no generative constructors. It is a compile time error to
    extend a mixin.

*   It is a compile-time error to mix in a class.

The rules for using types *outside* of their module are based on the
capabilities the type explicitly permits:

*   It is a compile-time error to invoke a generative constructor of a class
    marked `abstract` outside of the module where the class is defined.

*   It is a compile-time error for a class to appear in an `extends` clause
    outside of the module where the class is defined unless the class is marked
    `open`.

*   It is a compile-time error for a type to appear in an `implements` clause
    outside of the module where the type is defined unless the type is marked
    `interface`.

*   It is a compile-time error for a class to appear in a `with` clause.

We also want to make sure the type structurally supports any capability it
claims to offer. This helps package maintainers catch mistakes where they
inadvertently break a capability that the type offers.

*   It is a compile-time error if a non-abstract class contains an abstract
    method or inherits an abstract method with no corresponding implementation.
    *Since a non-abstract class declares that code outside the module can
    construct it, this rule ensures that it is safe to do so. Abstract classes
    and mixins may contain both abstract and non-abstract members.*

*   It is a compile-time error if a public-named type marked `class` does not
    have a public-named constructor. *The constructor can be a default or
    factory constructor, and can be unnamed.*

*   It is a compile-time error if a public-named type marked `interface` has any
    private members. *This is to avoid the problem where an external
    implementation of an interface may omit private members that the module then
    assumes it can call when given an instance of that interface.*

    **TODO: Is this too much of a restriction?**

*   It is a compile-time error if a class C marked `interface` has a superclass
    D which is not also marked `interface`, unless C and D are declared in the
    same module. *In other words, someone can't extend a class with an interface
    that they don't control and then retroactively expose its interface by way
    of a subclass. This ensures that if you declare a class C with no interface,
    then any object of type C will reliably be an instance of your actual class
    C or some other type you control.*

### Capabilities on legacy classes

The above syntax means that it an error to implement, mixin, or extend a class
declared just using `class`. This would break nearly all existing Dart code if
it were retroactively applied to existing code.

Fortunately, we have [language versioning][] to help. Dart libraries still at
the language version before modules will behave as if all class declarations
are implicitly marked with all of the capabilities the class can support. In
particular:

*   All classes and mixins are treated as implicitly marked `interface`.

*   If the class has at least one generative constructor (which may be default),
    it is treated as implicitly marked `open`.

*   If the class has no non-default generative constructors, and `Object` as
    superclass, it continues to expose an implicit mixin.

[language versioning]: https://dart.dev/guides/language/evolution#language-versioning

When updating a library to the language version that supports modules, you'll
want to decide what capabilities to offer, or just place all the modifiers you
need to preserve the class's current behavior.

Migrating a class that is used both as a class and a mixin is harder. For that,
you will have to migrate it to two separate declarations and give one of them
a different name. Fortunately, classes used this way are very rare.

**TODO: Investigate tooling to automatically migrate.**

## Capability controls on members

**TODO: Do we want 'final' non-overridable members?**

**TODO: Protected?**

## Implicit modules and legacy code

**TODO**
