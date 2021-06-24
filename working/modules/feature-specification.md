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

Dart defaults to being maximally permissive. When you define a class, it can,
unless prohibited by its own structure, be used as an interface, superclass, or
mixin. This is useful for consumers of the class because they are given the
flexibility to do with it as they will. This flexibility comes with some
downsides:

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

Because of these, users ask for control over the affordances a class provides
([349][], [704][], [987][]). Adding modules to the language is a good
opportunity to add those.

Note that the above reasons only come into play when *unknown code* works with
a class. Thus these restrictions only apply to code using a class outside of
the module where the class is declared. Inside the class's own module, you are
free to use the class however you want. It's your class.

There are four capabilities a class may expose to outside code:

[349]: https://github.com/dart-lang/language/issues/349
[704]: https://github.com/dart-lang/language/issues/704
[987]: https://github.com/dart-lang/language/issues/987

*   **Constructible.** – Whether a new instance can be created by calling one of
    its constructors.

*   **Extensible.** – Whether the class can be used as a superclass of another
    class in its `extends` clause.

*   **Implementable.** – Whether the class exposes an interface that can be
    implemented.

*   **Mix-in** – Whether the class defines a mixin can be mixed in to other
    classes.

Ideally, a class would have full control over which of these capabilities it
allows and all combinations would be expressible. Dart already supports a
couple of combinations: an `abstract class` cannot be constructed, and a `mixin`
declaration cannot be constructed or extended.

An analysis of Google's corpus shows these combinations are most common:

```
Construct               63.93% 6605
(none)                  14.09% 1456
Implement                9.77% 1009
Extend                   6.47%  668
Construct + Implement    2.36%  244
Mixin                    1.25%  129
```

All other combinations are less than 1% *but do occur in practice*. The latter
implies that we should support all 16 combinations. To keep declarations terse,
the default behavior should reflect the most common combinations and modifiers
should opt for less common choices. Given the numbers above, that means classes
should default to constructible, but not extensible, implementable, or
mixin-able ("miscible"?).

### Syntax

Following Dart's existing syntax, we use `mixin` to allow mixing-in and
`abstract` to prevent constructing. Following Java and others, we use
`interface` to allow implementing. Following Swift and Kotlin, we use `open` to
allow subclassing.

Using all of those strictly as modifiers on `class` would lead to some awkard
combinations (like `abstract interface` for what would just be `interface` in
other languages), so the rules for combining them are a little more complex. In
grammarese, the allowed combinations and modifier orders are:

```
topLevelDeclaration ::=
    abstractClassDeclaration
  | classDeclaration
  | interfaceDeclaration
  | mixinDeclaration
  // existing rules...

abstractClassDeclaration ::= 'open'? 'abstract' 'class' // ...
classDeclaration         ::= 'open'? 'interface'? 'mixin'? 'class' // ...
mixinDeclaration         ::= 'open'? 'interface'? 'mixin' // ...
interfaceDeclaration     ::= 'interface' // ...
```

That yields these combinations:

```
class                               // 63.93% Construct
abstract class                      // 14.09% (none)
interface                           //  9.77% Implement
open abstract class                 //  6.47% Extend
interface class                     //  2.36% Implement Construct
mixin                               //  1.25% Mix-in
open class                          //  0.86% Extend Construct
open interface                      //  0.76% Implement Extend
open interface class                //  0.20% Implement Extend Construct
open mixin                          //  0.14% Mix-in Extend
interface mixin                     //  0.09% Mix-in Implement
open interface mixin                //  0.03% Mix-in Implement Extend
mixin class                         //  0.02% Mix-in Construct
open mixin class                    //  0.02% Mix-in Extend Construct
interface mixin class               //  0.01% Mix-in Implement Construct
open interface mixin class          //  0.00% Mix-in Implement Extend Construct
```

Note that the names gradually get longer for less common combinations, so it
seems this is roughly in line with keeping the common options terse.

### Static semantics

There are four "kinds" of types: `abstract class`, `class`, `interface`, and
`mixin`.

The rules for using the type within its module are as permissive as possible
and are based on the structure of the type itself, as in current Dart:

*   It is a compile-time error to invoke a generative constructor of a type if
    the type defines or inherits any unimplemented abstract members. *You can
    directly construct anything internally if it wouldn't cause a problem to do
    so, even an interface or an abstract class.* **TODO: Even a mixin?**

*   It is a compile-time error to extend a type that has at least one factory
    constructor and no generative constructors.

*   It is a compile-time error to mix in a type that explicitly declares a
    generative constructor or has a superclass other than `Object`.

The rules for using types *outside* of their module are based on the
capabilities the type explicitly provides:

*   It is a compile-time error to invoke a generative constructor of an abstract
    class, interface, or mixin outside of the module where the type is defined.

*   It is a compile-time error for a type to appear in an `extends` clause
    outside of the module where the type is defined unless the type is marked
    `open`.

*   It is a compile-time error for a type to appear in an `implements` clause
    outside of the module where the type is defined unless the type is an
    interface or is marked `interface`.

*   It is a compile-time error for a type to appear in a `with` clause outside
    of the module where the type is defined unless the type is a mixin or is
    marked `mixin`.

We also want to make sure the type structurally supports any capability it
claims to offer. This helps package maintainers catch mistakes where they
inadvertently break a capability that the type offers.

*   It is a compile-time error if a non-abstract class contains an abstract
    method or inherits an abstract method no corresponding implementation.
    *Since a non-abstract class declares that code outside the module can
    construct it, this rule ensures that it is safe to do so.*

    *All other kinds of types -- abstract classes, interfaces, and mixins -- may
    contain both abstract and non-abstract members. Even interfaces can contain
    non-abstract members. This is because while an interface can't be
    constructed or extended outside of the module, it can be internally if it
    has no abstract members.*

*   It is a compile-time error if a public-named type marked `class` does not
    have a public-named constructor. *The constructor can be a default or
    factory constructor, and can be unnamed.*

*   It is a compile-time error if a public-named type marked `interface` has any
    private members. *This is to avoid the problem where an external
    implementation of an interface may omit private members that the module then
    assumes it can call when given an instance of that interface.*

    **TODO: Is this too much of a restriction?**

*   It is a compile-time error if a public-named type marked `mixin` defines
    any constructors. **TODO: Is this restriction correct?**

*   It is a compile-time error if a class C marked `interface` has a superclass
    D which is not also marked `interface`, unless C and D are declared in the
    same module. *In other words, someone can't extend a class with no interface
    that they don't control and then retroactively give it an interface by way
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

*   All classes are treated as implicitly marked `interface`.

*   If the class has at least one generative constructor (which may be default)
    and is not marked `abstract` it is treated as implicitly marked `open`.

*   If the class has no constructors, it is treated as implicitly marked
    `mixin`.

[language versioning]: https://dart.dev/guides/language/evolution#language-versioning

When updating a library to the language version that supports modules, you'll
want to decide what capabilities to offer, or just place all the modifiers you
can to preserve the class's current behavior.

**TODO: Investigate tooling to automatically migrate.**

## Capability controls on members

**TODO: Do we want 'final' non-overridable members?**

## Implicit modules and legacy code

**TODO**
