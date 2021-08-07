# Motivation

Over the past several years, we have accumulated a set of problems or feature
requests that all relate to making the large-scale composition of a Dart program
more structured and user-controllable.

Dart was originally designed more like a scripting language&mdash;a Dart program
is a loose pile of text files all freely related to each other and able to do
pretty much what they want. That simplicity and flexibility are two strengths of
Dart that we don't want to lose. At the same time, the complete lack of
structure and control can make it hard to work with Dart at scale.

This document lists a number of problems or ideas all in this space that might
improve the experience of working on large Dart programs. It may be that these
can't all be solved, or that their solutions will come from mostly unrelated
language changes. But since they generally touch on the same issues around
libraries, encapsulation, and composing Dart programs, we want to look at them
holistically.

## Macro compilation

For static metaprogramming, we need to ensure a macro body has been completely
type checked and compiled before it is used. Since the macro is itself Dart
code, that means taking the Dart program and breaking it into well-defined
pieces that can be compiled separately.

The natural boundary for that is libraries. But Dart allows cyclic imports in
libraries, which makes that much harder.

## Separate compilation and dynamic loading

In C/C++, you can take a large program and compile parts of it in separate
binary libraries. Those libraries can be dynamically loaded at runtime if
needed. This gives you a way to upgrade parts of the executable later, support
plug-ins, or speed up initial startup.

To do this, a developer needs a way to author the boundaries between the
different libraries. To use a dynamically loaded library, the library needs some
well-defined interface that both sides agree on to communicate, an [ABI].

[ABI]: https://en.wikipedia.org/wiki/Application_binary_interface
[fork]:

Dart has no concept of an ABI and no existing way for a user to define a
chunk of Dart code that should be compiled as a separately loadable unit. (It
has an [FFI], but that's for talking between Dart and C, not between two
separately compiled pieces of Dart.

The [isolate API] is a step in this direction, but it doesn't cover this use
case. It can load Dart code dynamically *from source* with the JIT, but not
compiled Dart code. It *can* spawn a new isolate using the same compiled code as
the main application. But this is a concurrency tool (essentially [fork]), not a
dynamic loading one, since the spawned code must already be compiled into the
executable.

[isolate api]: https://medium.com/dartlang/dart-asynchronous-programming-isolates-and-event-loops-bffc3e296a6a
[fork]: https://en.wikipedia.org/wiki/Fork_(system_call)

The .NET framework has [assemblies][] which can be dynamically loaded. The JVM
ecosystem has compiled .class files and [class loaders][], but Dart has nothing
analogous. It has incremental modular compilation *as an internal tool feature
for faster iteration*, but no externally usable construct for a compiled,
reusable, dynamically loadable piece of Dart code.

[assemblies]: https://docs.microsoft.com/en-us/dotnet/standard/assembly/
[class loaders]: https://www.baeldung.com/java-classloaders

## Better Blaze/Bazel/build_runner integration

In order to use Dart within the Blaze/Bazel build system, users must also create
BUILD files and set up packages and targets for the Dart libraries they want to
compile. The BUILD files are another thing for Dart users to author and
maintain.

Bazel packages and targets somewhat map to pub packages and libraries, but in
practice a single Bazel target often contains a number of Dart libraries. Unlike
library imports and pub dependencies, Bazel target are prohibited from having
any cycles. Our compiler integration into Bazel uses build targets as the unit
of modular compilation.

The Dart [webdev] tools also need the ability to do modular compilation of Dart
code. That again requires splitting the Dart program into acyclic collections
of libraries. Instead of hand-authored BUILD files, build_runner automatically
infers the sets of independently buildable units by finding the strongly
connected components of the import graph.

[webdev]: https://dart.dev/tools/webdev

All of this is extra-linguistic. Since Dart has no notion of these, we can't
integrate them into the syntax or hang useful language features off them.

## Package public API control

A pub package may contain a variety of libraries under `lib/`, some of which
are intended to be used by consumers of the package and others which are only
intended to be used by the package itself. By convention, libraries under
`lib/src/` are considered private to the package, and all other libraries are
public.

This convention is not enforced by the language. This means that sometimes users
*do* import private libraries from `lib/src/`. This can mean unexpected breakage
when the package maintainer makes a change to one of those libraries.

It also means the language loses the ability to do better static checking or
optimization based on knowing which libraries are encapsulated by the package.
For example, the unused code warnings our tools show for private declarations
could be extended to unused public declarations inside private libraries if the
language could be certain that no outside code was using them.

A modular compiler might be able to devirtualize methods in classes in private
libraries if it could rely on knowing that no code outside of the package could
be importing and subclassing that class.

## Finer-grained public API control

When a library is intended to be public and used outside of the package, *all*
of it is considered public. Aside from using library privacy, which also hides
the declaration for other libraries inside the package too, there's no way to
make *some* of a public library not available for use outside of the package.
It's all or nothing.

## Access controls for package maintainers

In Dart, every class can implicitly be extended or have its implicit interface
implemented. This is nice for flexibility, but can place a burden on package
maintainers.

Since a class may be used as an interface, adding a method is potentially a
breaking change, even if the author never intended the class's interface to be
implemented. In practice, many class maintainers *document* how the class should
be used and don't consider it a breaking change (and thus don't change the
package's major version) if they change a class in a way would break users not
following that documentation.

When a class implicitly permits anything, it can be hard to tell how it is
*intended* to be used. Restricting the options can provide a simpler, more
guided API.

Changes to a class can break one of its capabilities. If you change a generative
constructor to a factory constructor, that will break any subclasses that
chained to that constructor. Since the language doesn't know whether or not you
intend that class to be subclassed in other packages, it can't alert you to the
consequences of that change.

Because of these, users ask for control over the affordances a declaration
provides ([704], [835], [987], [1446]). Modules are a natural boundary for those
restrictions.

[704]: https://github.com/dart-lang/language/issues/704
[835]: https://github.com/dart-lang/language/issues/835
[987]: https://github.com/dart-lang/language/issues/987
[1446]: https://github.com/dart-lang/language/issues/1446

## Exhaustiveness checking

Many of our users would like to program in an algebraic datatype functional
style ([83], [349]). Key to that is [pattern matching] over a set of types. In
order to ensure that every possible type is handled, users expect the compiler
to perform [exhaustiveness checking][ex]. That in turn means that the language
needs to express a *closed* or *sealed* family of subtypes. Otherwise, there's
no way to tell if a pattern match has covered all types.

[83]: https://github.com/dart-lang/language/issues/83
[349]: https://github.com/dart-lang/language/issues/349
[pattern matching]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md
[ex]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md#exhaustiveness-and-reachability

## Clearbox testing

Dart's privacy model is library-based. A private member or declaration cannot
be accessed at all outside of the library where it is defined. Since tests are
separately libraries from the code under test, this implies that tests can only
access the public API of the code being tested.

Clear box testing refers to unit tests that validate not just the external
public API of a class or library, but its private state and implementation as
well. Dart doesn't have good support for this. Any API being tested must be
visible so the test can see it. But that makes the API visible to all external
users of the library as well.

Our analysis tools provide some support for clear box testing through the
[`@visibleForTesting`][visible] annotation. This can be placed on a public
declaration and users will get a static warning if the declaration is used
anywhere but tests. But this is only a tooling-level feature. The language
itself doesn't enforce it.

[visible]: https://api.flutter.dev/flutter/meta/visibleForTesting-constant.html

## Generated code dependencies

Since Dart is statically typed and small code size is critical for mobile client
apps, Dart's metaprogramming solutions are run at compile time. In practice,
this usually means code generation. The user hand-authors a library, and a code
generator outputs a separate file that fills in the missing features for that
library.

That generated file could be a separate library or a part file. Code generators
often use parts in order to be able to access private declarations in the
hand-authored file (or vice versa). However, since parts can't have imports, any
dependencies needed by the generated code must be hand-maintained in the main
library file. This breaks the desired encapsulation of the code generator and
increases the friction of maintaining code that uses code generation.

## Import syntax

A Dart program made of multiple files is tied together using import (and export)
directives. The original design of this syntax was based on the idea that Dart
programs would be run from source in a browser and that many imported libraries
would be imported directly from real URIs on the web. This meant that the import
syntax had to work even without being able to do such fundamental operations as
"list the contents of a directory" or "quickly see if a path exists".

Today, Dart programs are compiled on a developer's machine before being deployed
and imports are processed at compile time and read from a normal file system.
The URI-based syntax's verbosity provides little benefit. The syntax for
importing a library from another pub package&mdash;incredibly common
today&mdash;is particularly long. Here are some examples:

```dart
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:flutter/material.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:widget.tla.server/server.dart';
import 'package:widget.tla.proto/client/component.dart';
import 'test_utils.dart';
import '../util/dart_type_utilities.dart';
import '../../../room/member/membership.dart';
import 'src/assets/source_stylesheet.dart';
```

An import syntax that took for granted being processed at compile time on a
local, accessible file system against a known set of package dependencies could
likely be much shorter ([10018], [649]).

[10018]: https://github.com/dart-lang/sdk/issues/10018
[649]: https://github.com/dart-lang/language/issues/649
