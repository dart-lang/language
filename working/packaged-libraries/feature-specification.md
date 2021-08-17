# Packaged Libraries

**Note: This proposal can be considered an alternative to [modules]. Both are
still in progress.**

[modules]: https://github.com/dart-lang/language/tree/master/working/modules

This proposal defines a handful of changes around libraries. Each solves
somewhat separate problems, but they all rely on knowing what *package* each
library belongs to. The overall goal is to make Dart more productive and
structured when programming in the large in the context a package ecosystem.
These changes may also help tools analyze, compile, and optimize libraries.

The changes are, briefly:

*   **Library groups.** We disallow arbitrary import cycles in libraries,
    especially across packages. Then we introduce a notion of a group of
    libraries for cases where a set of libraries in a package are mutually
    dependent.

*   **Capability controls on types.** We allow package authors to control
    whether their types allow instantiating, extending, implementing, and/or
    mixing in outside of the package.

*   **Private imports.** We provide a way for libraries to import the private
    members of other libraries in the same package. Since that covers main use
    case for part files without its shortcomings, we eliminate parts in order to
    simplify the language.

Before we get to the changes, we need to define what a package is.

## Dart packages

Dart has had "package:" imports for many years, but packages are not part of the
language itself in a meaningful sense. The only mention of the word "package"
in normative text in the language spec is:

> A URI of the form **package:*s*** is interpreted in an implementation specific
> manner.

It used to be that the [pub package manager] would collude with the Dart
implementations to resolve "package" imports without the language being directly
involved. When we added [language versioning] to Dart, the [package config file]
that Dart implementations use to resolve "package" imports became more deeply
tied to the language. A Dart language implementation *must* use that in order to
know what language version any given library uses. We build on that support to
formally define a package:

[pub package manager]: https://dart.dev/tools/pub/cmd
[language versioning]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/language-versioning/feature-specification.md
[package config file]: https://github.com/dart-lang/language/blob/master/accepted/future-releases/language-versioning/package-config-file-v2.md

A **package** is a named collection of libraries. Every library belongs to one
and only one package. The package that contains a given library is:

1.  If the library's resolved URI is "package:" then the package is the first
    path component after "package:".

2.  Else, if the library's URI is a file path that falls within the `rootUri` of
    a package in the `package_config.json` file used to resolve "package:"
    URIs, then the package is that package.

3.  Otherwise, the library is in an implicit unnamed package shared by all
    libraries that reach this clause.

In practice, this means that a library's package is the [pub package] that
contains it. That includes both libraries under `lib/` as well as other top
level directories like `test/`, `bin/`, etc.

[pub package]: https://dart.dev/guides/packages

## Library groups

Library groups give Dart more control over cyclic imports in their program.

### Motivation

Dart was originally designed to be a lightweight a scripting language. A Dart
program was conceived of as a loose pile of text resources at URIs on the web
that could freely reference each other and be run from source. This flexibility
permits cyclic imports and arbitrarily complex import graphs.

The libraries imported by a library affect how that latter library is itself
type-checked and compiled. The library likely uses imported types. It may have
constant declarations with expressions containing constants from other
libraries. The library may have declarations that rely on type inference flowing
through imported declarations.

This makes it hard to incrementally analyze or compile a Dart program. Modular
compilers like [webdev] have to perform a [strongly connected component]
analysis on the import graph of the entire program in order to infer which
pieces can be compiled separately.

[webdev]: https://dart.dev/tools/webdev
[strongly connected component]: https://en.wikipedia.org/wiki/Strongly_connected_component

The Dart language team is working on [static metaprogramming]. The current plan
is some form of [macros]. Macros would be written in Dart, but can also access
and modify the same Dart program. That introduces some ordering challenges. A
macro definition must itself be type-checked and compiled before it can be
applied to some other part of the program.

[static metaprogramming]: https://github.com/dart-lang/language/issues/1482
[macros]: https://github.com/dart-lang/language/tree/master/working/macros

In order to ensure that macros are compiled before they are used, we need some
reliable way to break the program into separately compiled parts. An obvious
boundary for that is libraries: We could say that a macro cannot be applied in
the same library where it is declared. As long as you can compile the library
where the macro is defined before any library that imports and uses it, you're
fine. Cyclic imports complicate that, unfortunately.

## Acyclic imports

We solve this problem by simply prohibiting cycles: It is a compile-time error
for a Dart library to import (or export) any library that imports (or exports)
it, either directly or transitively.

[the gordian way]: https://en.wikipedia.org/wiki/Gordian_Knot

In return for this restriction, a change to a library A will never affect the
static analysis, compilation, or runtime behavior of a library B unless A is a
dependency of B (directly or indirectly). A "downstream" change to some code
never requires anything "upstream" of it to be recompiled or reanalyzed. Given a
set of libraries, a tool or compiler can process them separately in [topological
order][topo] and will never need to revisit a library. Likewise, for macros, if
macros are always defined in libraries you import, then you can be certain that
the macros you apply can be compiled before you need to use them.

[topo]: https://en.wikipedia.org/wiki/Topological_sorting

### Library groups

Prohibiting cycles makes life easier for our tools, but users do actually use
cyclic imports. It's fairly common to find a few mutually dependent libraries in
real-world packages. While only around 3% of libraries on pub.dev are involved
in a cycle, those libraries are scattered widely across the ecosystem. About a
third of pub packages analyzed contain at least one import cycle.

You can break these cycles by refactoring your code and using things like
abstract classes and introducing separate "interface" libraries, but doing so
is tedious and the techniques are non-obvious for many. Instead, we allow users
to define a *library group*.

As the name implies, this is a group of mutually dependent libraries that are
allowed to import (or export) each other freely. A library can specify the name
of the group it belongs to using a `library` directive with an `in` clause:

```dart
library in some.group.name;
```

The dotted name implicitly defines a library group with that name. All libraries
in the same package that have `in` clauses with the same name are in the same
library group and may freely import each other. Libraries with no `in` clause
are not part of any group.

Since library groups are confined to a single package, group names only need to
be unique within a package. This also implies that **cyclic imports across
packages are completely prohibited.** While cyclic dependencies between pub
*packages* are not uncommon, cyclic imports between actual libraries within
those packages are exceedingly rare. Within Google, they are completely
prohibited by the build system. We don't think this will be much of a
restriction in practice.

The updated grammar for library directives is:

```
libraryName ::= metadata 'library' dottedIdentifierList?
                ( 'in' dottedIdentifierList )? ';'
```

**TODO: This feature seems like a user chore without much user value. We could
simply say that macros cannot be in library cycles. Is this worth keeping? Are
there other things library groups would be useful for (like inferring Blaze
targets or defining ABI boundaries)?**

## Private imports

**Note: This section is mostly identical to the existing [private imports] doc.
If you've already read that, you can skim this.**

[private imports]: https://github.com/dart-lang/language/blob/master/working/modules/private-imports.md

Identifiers starting with `_` are private in Dart. A declaration named with a
leading underscore cannot be accessed outside of the library where it is
defined. Semantically, private names behave as if the leading underscore is
replaced with a unique [mangled name][] based on the library where the name
appears.

[mangled name]: https://en.wikipedia.org/wiki/Name_mangling

### Motivation

This simple mechanism works surprisingly well, but can be limiting. It is an
established pattern in Dart to locate multiple class declarations in the same
library so that they can share access to private state and behavior.

If you want that sharing, but don't want to cram everything into a single file,
you are obliged to use part files. Parts have their own problems. Part files all
share the exact same top level scope as the main library file and cannot have
their own imports. Any imports must go in the main library file.

Code generation often uses parts so that the main library can access private
declarations in the generated library (or vice versa). However, since parts
can't have imports, any dependencies needed by the generated code must be
hand-authored in the main library file. This breaks the desired encapsulation
of the code generator and increases the friction of maintaining code that uses
code generation.

Clear box testing refers to unit tests that validate not just the external
public API of a class or library, but its private state and implementation as
well. The Dart language currently doesn't have good support for this. Since
tests are separate libraries from the code under test, any API being tested must
be public so the test can see it. That makes the API visible to all external
users of the library as well.

Our analysis tools provide some support for clear box testing through the
[`@visibleForTesting`][visible] annotation. This can be placed on a public
declaration and users will get a static warning if the declaration is used
anywhere but tests. But this is only a tooling-level feature. The language
itself doesn't enforce this.

[visible]: https://api.flutter.dev/flutter/meta/visibleForTesting-constant.html

Part files are not a workable solution here because making the test a part of
the main library would force all of the test's imports to become real
dependencies of the library under test. We don't want library code to become
directly coupled to the test framework.

### Private imports

To address the above, we allow libraries to import private declarations from
other libraries. When importing a library within your own package, you can opt
in to also importing its private identifiers by adding a *private import
clause*, which looks like `show _`:

```dart
import 'other.dart' show _;
```

**TODO: Better syntax? Allow only importing some private names?**

**TODO: We could consider something like [#1627] to allow importing only certain private instance members.**

[#1627]: https://github.com/dart-lang/language/issues/1627

It is a compile-error to use a private import clause in an import if the library
containing the import and the library being imported are not in the same
package. You can access private declarations of your own code, but you cannot
break the encapsulation of a package because that would make it harder for the
maintainer of the package to evolve it without breaking your code.

It is a compile-time error to use a private import clause on an export
directive. Private identifiers cannot be exported.

### Lexical name resolution

For the most part, imported private identifiers are resolved and behave like
other identifiers. Imported private identifiers in the top-level namespace like
class declarations, extensions, mixins, top-level variables, and top-level
functions are simply imported into the current library's lexical scope under
their bare name:

```dart
// a.dart
class _Class {}

void _function() {}

var _variable = 3;

// b.dart
import a show _;

main() {
  _Class();
  _function();
  _variable = 4;
  print(_variable);
}
```

Importing two textually identical private names from different libraries is a
collision error if the importing library uses the name:

```dart
// a.dart
var _colliding = 1;

// b.dart
var _colliding = 2;

// c.dart
import 'a.dart' show _;
import 'b.dart' show _;

main() {
  print(_colliding); // Error.
}
```

Even though the private identifiers are considered distinct in their defining
libraries (for example, a superclass in one library and a subclass of it in
another can define private instance methods with the same name that do not
collide), when imported into a library, they behave like public identifiers
where they collide if they are textually identical. As with public names, if the
current library declares a top-level name that collides with an imported
top-level private name, then no error occurs. A library's own declarations
always shadow imported ones.

Static members, constructors, and enum cases with private names are accessible
from imported types (which also may or may not be private):

```dart
// a.dart
class _Private {
  static var _privateField = 1;
  static var publicField = 2;
}

class Public {
  static var _privateField = 1;
  static var publicField = 2;
}

// b.dart
import 'a.dart' show _;

main() {
  // These are all OK:
  print(_Private._privateField);
  print(_Private.publicField);
  print(Public._privateField);
  print(Public.publicField);
}
```

When a library is imported with a prefix and a private import clause, then
top-level private identifiers are available from the prefix:

```dart
// a.dart
var _private = 1;

// b.dart
import 'a.dart' as a show _;

main() {
  print(a._private);
}
```

*(This is an effective way of using another library's private declarations
without having them collide with the library's own private names.)*

### Instance member access

To resolve a private identifier after a `.`, `?.`, or `..` where the left-hand
side is an expression or `super` (in other words, not a prefix or type name as
handled above):

1.  Look for instance members with the same textual name on the static type of
    the receiver. Include only types and superinterfaces defined in the current
    library or in libraries that were imported with a private import clause.

2.  If any of the members is declared in the current library, then the name
    resolves to the private name in this library. Local private instance members
    shadow imported ones.

3.  Else, it is a compile-time error if multiple declarations match from
    more than one library. For example:

    ```dart
    // a.dart
    class A {
      _private() => 'A._private()';
    }

    // b.dart
    import 'a.dart' show _;

    class B extends A {
      _private() => 'B._private()';
    }

    // c.dart
    import 'a.dart' show _;
    import 'b.dart' show _;

    main() {
      B()._private(); // Error.
    }
    ```

    Here, it is not clear if `_private()` in "c.dart" is intended to refer to
    `A._private()` or `B._private()`. Note that this is only an error because
    "c.dart" explicitly imports both libraries. There is no error here:

    ```dart
    // a.dart
    class A {
      _private() => 'A._private()';
    }

    // b.dart
    import 'a.dart' show _;

    class B extends A {
      _private() => 'B._private()';
    }

    // c.dart
    import 'b.dart' show _;

    main() {
      B()._private(); // Refers to B._private().
    }
    ```

    To avoid these errors, in many cases users can upcast to the specific type
    whose private method they want to call:

    ```dart
    import 'a.dart' show _;
    import 'b.dart' show _;

    main() {
      (B() as A)._private(); // Refers to A._private().
    }
    ```

4.  Else, if all matching declarations are from the same library, then the
    identifier is resolved to the private name in that library.

5.  Else, if no names match, perform the same process but looking for extension
    members defined on the type of the receiver.

If the receiver has type `dynamic`, then private members are always resolved
to the current library. There is no way to dynamically access a private member
from another library.

### Instance member declarations

A library may or may not wish to override an imported private instance member
in a supertype. Since the library has chosen to deliberately import the other
library's private identifiers, the assumption is that if an instance member
declaration appears to override an imported private member, then it should.
More precisely:

When declaring an instance member with a private name:

1.  Look for any matching declarations in superinterfaces in the current library
    and any libraries imported with private import clauses.

2.  It is a compile error if there are multiple matching declarations in
    different libraries. For example:

    ```dart
    // a.dart
    class A {
      _private() => 'A._private()';
    }

    // b.dart
    class B {
      _private() => 'B._private()';
    }

    // c.dart
    import 'a.dart' show _;
    import 'b.dart' show _;

    class C implements A, B {
      void _private() {} // Error.
    }
    ```

    Here, it is ambiguous whether C is overriding `A._private()` or
    `B._private()`. Note that those *are* distinct members:

    ```dart
    // a.dart
    class A {
      _private() => 'A._private()';
    }

    printA(A a) => print(a._private();

    // b.dart
    class B {
      _private() => 'B._private()';
    }

    printB(B b) => print(b._private();

    // c.dart
    import 'a.dart' show _;
    import 'b.dart' show _;

    class C extends A with B {}

    main() {
      var c = C();
      printA(c); // "A._private()".
      printB(c); // "B._private()".
    }
    ```

    Because the two private members do have different "mangled" names, we don't
    allow a single method declaration to override both.

    **TODO: Is this what we want?**

3.  Else, if all matching declarations are from the same library, then the
    member is an override whose name is that library's private identifer.

4.  Otherwise if there are no matching superinterface declarations, then the
    member is a new private declaration in the current library.

**TODO: If we make `override` a real language feature, then we could say that
private members marked `override` use the private name of the superclass,
otherwise, they are treated as new private members in the current library.**

These rules mean that a member only overrides an imported private member *when
it is statically known at the member declaration that an override is occurring.*
This example does *not* override the imported member:

```dart
// a.dart
class A {
  _private() => 'A._private()';
  callFromA() => _private();
}

// b.dart
import 'a.dart' show _;

mixin B { // No superinterface from a.dart.
  _private() => 'B._private()'; // Private to current library.
  callFromB() => _private();
}

class C extends A with B {}

main() {
  var c = C();
  print(c.callFromA()); // "A._private()".
  print(c.callFromB()); // "B._private()".
}
```

### Eliminating part files

Since private imports cover the use cases of part files and more, we remove
support for part files.

In order to not break existing code, we gate the support for private imports and
disallowing parts behind a new language version. When users upgrade to the
latest version, they can copy the contents of all of their part files into the
main library file, or convert the part files into libraries that are
private-imported by the main library or vice versa if the part accesses private
names from the main library.

We will want to migrate packages that code generate parts to support generating
libraries with private imports before this feature rolls out widely.

This is a significant change, but should be fairly mechanical for users to do.
If it proves too difficult, we could retain support for part files until Dart
3.0.

Of the 1,970 most recent packages on pub (as of early 2021), 374 (19%) contain
at least one part file. 38,677 of 41,279 libraries (94%) did not use part files.
Part files are not uniformly distributed across the ecosystem. The ten packages
with the most part files account for 1,842 of the 4,559 part files (40%). Note
that this only analyzes packages on disc so does not include part files produced
by code generators whose output is not committed with the package's code.

## Type capabilities

There are three fundamental kinds of entities in Dart's semantics:

*   A **class** has a set of member declarations and a superclass (which may be
    Object). You can use a class to **construct** new instances (if not
    abstract) and/or you can **extend** one as a superclass.

*   An **interface** is a set of member signatures with no imperative code.

*   A **mixin** is a set of member declarations. Unlike a class, a mixin does
    *not* have a superclass. You have to apply the mixin to some concrete
    superclass in order to get a class that you can construct.

Dart's syntax somewhat obscures this. There is no dedicated syntax for declaring
an interface. Until Dart 2.1.0, there was also no syntax for declaring a mixin.
Instead, a class declaration can, unless prohibited by its own structure, be
used as an interface, superclass, or mixin.

### Motivation

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

Likewise, allowing any class to be subclassed (unless the author carefully hides
all generative constructors on the class) comes with some consequences:

*   Internally refactoring the implementation of a class may break unintented
    subclasses that are overriding certain methods and expect them to be called
    in certain contexts.

*   Adding a new member to the class can be a breaking change if it happens to
    collide with a member someone has added to a subclass.

*   Changing a constructor from generative to factory will break any subclass
    using it as a super constructor.

In other words, implementing or subclassing creates an extremely tight, coupling
between the author's class and these potentially unintended subclasses or
implementers. That makes evolving the superclass [difficult][fragile].

[fragile]: https://en.wikipedia.org/wiki/Fragile_base_class

Because of this, users ask for control over the affordances a declaration
provides ([349][], [704][], [987][]). Note that, except for exhaustiveness
checking, these problems mostly come into play when *other, unknown users* of a
type start working with it. Within *your own code*, you can be trusted to use
types correctly, and can fix any breakage caused by changing a class's
interface.

[349]: https://github.com/dart-lang/language/issues/349
[704]: https://github.com/dart-lang/language/issues/704
[987]: https://github.com/dart-lang/language/issues/987

Thus **the restrictions only apply to code using a type outside of the package
where the type is declared.** Inside the type's own package, you are free to use
types however you want. It's your code. This gives you the freedom to, for
example, mock a class in your own package's tests without allowing the class to
be implemented externally if you don't want it to be.

### Capabilities

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

### Mixins and classes

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
used as a class inside the package. Dart users today are already used to using
`abstract class` to declare interfaces, so this isn't too much of a stretch.
Also, this leaves `interface` available as potential future syntax for defining
a pure interface, if a need for such thing should arrive.

### Choosing defaults

The defaults when you don't add any modifiers are fairly restrictive: A class
can only be constructed and neither subclassed nor implemented. A mixin by
default doesn't expose an interface. Why not default to being permissive and
require type authors to *remove* capabilities they don't want?

We know empirically that most types are *not* subclassed or implemented. We
don't know how many of them are *intended* to allow that, but given the low rate
of actual subclassing and implementing the odds are good that many aren't
designed for that use. Kotlin and Swift both default their classes to sealed
(not subclassable). (I've heard from some on the C# team that they wish they had
done the same.) Most other languages don't allow you to implement a class *at
all*.

Given all that, it's a fairly safe bet that most classes aren't designed to be
subclassed and most classes and mixins aren't designed to be implemented. If
that's true, then defaulting to *not* allowing those is the most *terse*
default: it means that across the whole ecosystem, everyone authoring what they
intend will lead to the shortest overall code.

A common criticism of Java is that it is verbose: programmers are forced to
write modifiers all the time. Much of that comes from having to put `private` on
most members because that's the most common access control that users *want*,
but not the language's default. If Java had defaulted to `private`, it would be
a more concise language.

It's also worth considering the harm of a type author getting it wrong. If we
default to allowing a capability and a package author forgets to remove it, then
a change to the type that they think is safe can break downstream users after
the package is irrevocably published. In the case of deep dependency graphs,
users may not even be able to fix the breakage because it may occur in a
transitive dependency.

If we default to not allowing a capability and a package author forgets to add
it, then a consumer can't perform an operation the package author intends to
support. The consumer is stuck (if they can't work around it), but not broken.
They can usually just file a bug, the package author adds the modifier, and
pushes a new patch release. In the meantime, if the user needs, they can fork
the package and use a dependency override. In other words, lacking a capability
behaves like a missing desired feature, but doesn't lead to spontaneous
unexpected breakage.

Note that worrying about which modifiers to add is only a concern for authors of
reused library packages. Most Dart programmers are *application*
authors&mdash;the packages they create use other packages but are not used by
anyone else. Since types allow all capabilities within a package, it means **an
application author never needs to worry about putting any modifiers on their own
types.** They can just write `class` and `mixin` and go on about their business.

### Static semantics

Within a package, despite all the new modifiers, the semantics are roughly the
same. The rules for using a type within its package are as permissive as possible
and are based on the structure of the type itself, as in current Dart:

*   It is a compile-time error to invoke a generative constructor of a class if
    the class defines or inherits any unimplemented abstract members. *You can
    directly construct abstract classes internally if it wouldn't cause a
    problem to do so. Mixins never have generative constructors.*

*   It is a compile-time error to extend a class that has at least one factory
    constructor and no generative constructors. It is a compile time error to
    extend a mixin.

*   It is a compile-time error to mix in a class.

The rules for using types *outside* of their package are based on the
capabilities the type explicitly permits:

*   It is a compile-time error to invoke a generative constructor of a class
    marked `abstract` outside of the package where the class is defined.

*   It is a compile-time error for a class to appear in an `extends` clause
    outside of the package where the class is defined unless the class is marked
    `open`.

*   It is a compile-time error for a type to appear in an `implements` clause
    outside of the package where the type is defined unless the type is marked
    `interface`.

*   It is a compile-time error for a class to appear in a `with` clause.

We also want to make sure the type structurally supports any capability it
claims to offer. This helps package maintainers catch mistakes where they
inadvertently break a capability that the type offers.

*   It is a compile-time error if a non-abstract class contains an abstract
    method or inherits an abstract method with no corresponding implementation.
    *Since a non-abstract class declares that code outside the package can
    construct it, this rule ensures that it is safe to do so. Abstract classes
    and mixins may contain both abstract and non-abstract members.*

*   It is a compile-time error if a public-named type marked `class` does not
    have a public-named constructor. *The constructor can be a default or
    factory constructor, and can be unnamed.*

*   It is a compile-time error if a public-named type marked `interface` has any
    private members. *This is to avoid the problem where an external
    implementation of an interface may omit private members that the package
    then assumes it can call when given an instance of that interface.*

    **TODO: Is this too much of a restriction?**

*   It is a compile-time error if a class C marked `interface` has a superclass
    D which is not also marked `interface`, unless C and D are declared in the
    same package. *In other words, someone can't extend a class with an
    interface that they don't control and then retroactively expose its
    interface by way of a subclass. This ensures that if you declare a class C
    with no interface, then any object of type C will reliably be an instance of
    your actual class C or some other type you control.*

**TODO: If we add some notion of "private libraries", then rewrite the above
to take them into account.**

### Capabilities on legacy classes

The above syntax means that it an error to implement, mixin, or extend a class
declared just using `class`. This would break nearly all existing Dart code if
it were retroactively applied to existing code.

Fortunately, we have [language versioning][] to help. Dart libraries still at
the language version before this proposal ships behave as if all class
declarations are implicitly marked with all of the capabilities the class can
support. In particular:

*   All classes and mixins are treated as implicitly marked `interface`.

*   If the class has at least one generative constructor (which may be default),
    it is treated as implicitly marked `open`.

*   If the class has no non-default generative constructors, and `Object` as
    superclass, it continues to expose an implicit mixin.

[language versioning]: https://dart.dev/guides/language/evolution#language-versioning

When updating a library to the language version that supports this proposal,
you'll want to decide what capabilities to offer, or just place all the
modifiers you need to preserve the class's current behavior.

Migrating a class that is used both as a class and a mixin is harder. For that,
you will have to migrate it to two separate declarations and give one of them
a different name. Fortunately, classes used this way are very rare.

**TODO: Treat libraries under `lib/src/` as private?**
