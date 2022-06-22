# Reflected Imports Feature Specification

Authors: Bob Nystrom, Jake Macdonald

Status: In progress

Version 1.0 (see [CHANGELOG](#CHANGELOG) at end)

## Motivation

When a macro is applied to a declaration, it can introspect over various
properties of the declaration. It can use that to generate code as well as
building up generated Dart code "from scratch" as literal source. In many cases,
a macro only needs to introspect over the applied declaration to know what code
to produce. But often, a macro wants to refer to some known existing code.

### Generating references to known code

For example, a macro that generates a serialization method for a class might
want to implement the body of the method by generating some calls to a known
utility function:

```dart
// package:serialize/helpers.dart:
Map<String, Object?> serializeIterable(Iterable<Object?> elements) {
  // Helper functionality...
}

// package:serialize/serialize.dart:
macro class Serialize {
  // Generate code that calls to `serializeIterable()`
  // from "serialize_helpers.dart"...
}

// my_app.dart
import 'package:serialize/serialize.dart';

@Serialize
class Foo {
  // ...
}
```

In theory, the macro could just inline the code for any utility functionality it
needs right into the generated code, but that leads to code duplication and
larger executables. We want it to be easy for macros to reuse code so that
macros don't lead to bloated applications.

This is challenging because the macro generated code may refer to a library
that hasn't been imported where the macro is applied. In the example here,
"my_app.dart" doesn't know anything about "serialize/helpers.dart".

### Accessing known declarations during introspection

In the above example, the macro doesn't *use* "serialize/helpers.dart" or even
ask any questions about it while the macro is running. It just inserts a
reference to it in the generated code. But sometimes a macro may want to
introspect over a specific known declaration independent of the one that macro
was applied to.

For example, consider a serialization macro. It walks over the fields of the
class the macro is applied to. If it encounters a field whose type implements
`CustomSerializer`, then it wants to generate code that defers to the field's
own serialization behavior. Otherwise, it generates some default serialization
code.

To do that, while the macro is running and introspecting over the class, it
needs to be able to ask "Is this field's type a subtype of `CustomSerializer`?"
Note that the macro can't just use Dart's own `is` operator for this: the
field's type exposed to the macro is a *metaobject* representating the
*introspection* of the field's type. While the macro is running, there is no
actual field and no value for it.

What the macro needs is a way to get a corresponding metaobject for
`CustomSerializer` that it can use in [the macro introspection API][api] for
things like subtype tests, as in:

[api]: https://github.com/dart-lang/sdk/blob/main/pkg/_fe_analyzer_shared/lib/src/macros/api/introspection.dart

```dart
for (var field in await builder.fieldsOf(clazz)) {
  if (await field.type.isSubtypeOf(customSerializerType)) {
    // Generate code to call custom serializer...
  } else {
    // Generate default serialization code...
  }
}
```

Here, `customSerializerType` needs to be an instance of `StaticType` (the macro
introspection API's notion of a type) that refers to the Dart class
`CustomSerializer`. In other words, the macro author needs a way to "lift" the
`CustomSerializer` from a normal Dart type to the meta-level that macros operate
at.

### Static import graphs

A straightforward solution would be for the macro API to provide an imperative
function that takes a library and declaration name and gives back an
introspection object referring to it, like:

```dart
var customSerializerType = Identifier.fromLibrary(
    'package:serialize/serialize.dart', 'CustomSerializer');
```

However, this doesn't work with the compilation process. Macros require a Dart
program to be compiled in a series of stages. A Dart library defining a macro
must be completely compiled before the macro is applied by some other library.
That ensures the macro is compiled and able to be run before any uses of it are
encountered.

To enable that, a Dart compiler must be able to traverse the import graph of the
entire program and stratify it into a well-defined compilation order where macro
definitions are built before their uses. That process breaks if a new connection
between libraries can spontaneously appear while a macro is running. With a
procedural API, there is no way to know what *other* libraries the macro will
refer to until the macro itself is running and calling that API.

To ensure that the entire dependency graph is known statically before any code
is compiled, the compiler needs to be able to statically tell which known
libraries the macro generate references to or introspects over.

### References to unavailable libraries

An imperative API doesn't work, so maybe the macro should just directly import
any known library that it wants to generate references to or use in
introspection. Since the library applying the macro imports the library where
the macro is defined, that ensures there is a transitive import from the library
where the macro is used to the library the generated code refers to.

This solves the static import graph problem, but causes another one: It means
that the entire known library must be compiled and available for use by the
macro. It's unlikely that the macro needs to *use* the known library. It
probably doesn't need to construct instances of its types or call functions
when the macro itself is running. It just needs to generate code that does that.

And, in many cases, it may not be *possible* to use the library while the macro
is running. Macros run in their own limited execution environment where core
libraries like "dart:html" and "dart:io" aren't available. Any library that
imports those directly or indirectly can't be imported by a macro, but we do
want to support macros that can generate code that *refers to* those libraries.

## Goals

Summarizing the above, the requirements are:

*   Give macros a way to insert references to known declarations in generated
    code.
*   Let macros introspect over declarations in known libraries for things like
    subtype tests.
*   Enable the Dart compiler to statically understand the library dependency
    graph of the program, before executing any macros.
*   Allow macros to refer to declarations even in libraries that can't be run
    in the macro execution environment.

## Reflected imports

To do all of the above, we add a new kind of import, a *reflected import*. The
grammar is:

```
importSpecification ::=
    'import' configurableUri ('deferred'? 'as' identifier)? combinator* ';'
  | 'import' uri 'reflected' 'as' identifier combinator* ';'
```

It looks like

```dart
import 'package:serializable/serializable.dart' reflected as serializable;
```

The design is akin to deferred imports. An import marked with the `reflected`
modifier provides access to the imported library for use in metaprogramming.
This is *not* the same as a regular import. A reflected import doesn't provide
direct access to the declarations or code in the library.

Instead, the import prefix (which must be provided) defines an object-like
namespace that can be used to access reflective metaobjects *describing* the
imported library. The prefix exposes a getter for every public declaration
defined by the imported library. Each getter returns an `Identifier` object that
is resolved to the corresponding declaration in the library.

```dart
import 'package:listenable/listenable.dart' reflected as listenable;

main() {
  print(listenable.Listenable.runtimeType); // "Identifier".
}
```

Getters are only defined for the declarations the library actually contains, so
if a macro author mistakenly tries to refer to an unknown or misspelled
declaration from a reflected import, the macro will fail to compile.

```dart
import 'package:listenable/listenable.dart' reflected as listenable;

main() {
  print(listenable.Listenible.runtimeType);
  //               ^^^^^^^^^^ Error: Unknown getter "Listenible".
}
```

### Using reflected imports in generated code

These `Identifier` objects can be inserted into code generated by a macro. When
they are, the `Identifier` retains its original resolution to the imported
library and generates an unambiguous reference to the corresponding declaration
in the library.

**TODO: Show an example of using a reflected import to refer to a class and a
function from a library in macro generated code.**

In concrete terms, when the macro execution environment compiles the macro's
generated code to an augmentation library, it finds every `Identifier` that is
resolved to a library. For each one, it generates a unique prefix. Then in the
produced augmentation library, it synthesizes an import for the resolved library
with that prefix and then compiles all `Identifiers` that resolve to that
library to prefixed identifiers using that prefix.

In practical terms, the macro author doesn't have to worry about
the name being shadowed by other names in scope where the generated code is
output. They can call a getter on the reflected import's prefix, insert the
result directly in generated code, and end up with a valid reference to the
imported declaration.

### Using reflected imports in introspection

In order to introspect over a declaration from a reflected import, the
`Identifier` must first be resolved to a declaration. The [macro introspection
API exposes][api] methods to do that.

The rules for introspection on identifiers from reflected imports are the same
as other identifiers a macro might encounter. This means you cannot navigate
to type declarations until after the types phase, and you cannot navigate to
other declarations until after the declarations phase. All type declarations
will also not be introspectable until the definitions phase.

**TODO: Would be good to show a concrete example of a macro using a reflected
import and introspecting over it in a subtype test.**

Requiring the macro to go through those APIs instead of eagerly exposing the
declaration introspection objects directly on the reflected import prefix spares
the compiler and macro execution environment from having to build full
introspection objects for every public declaration in the reflected on library.

## Restrictions

Reflected imports pierce the boundary between compile-time and runtime. In order
to avoid adding significantly complexity to our compilers and runtimes, and to
avoid bloating end user programs, there are some limitations in how they can be
used.

### Using reflected imports

In order to define getters returning `Identifier` objects for every declaration
in a reflected imported library, the compiler needs to know the static API
signature of the library&mdash;the set of all public top level declarations.
This way, it knows which getters are available.

Then, at runtime, the Dart program needs to be able to instantiate and return
instances of the `Identifier` class whenever those getters are called. This
class is defined in the macro API and is only available in the macro execution
environment.

This implies that **reflected imports can only appear in libraries that are run
in the macro execution environment.** You can think of the macro environment as
a distinct Dart "platform" and only it supports reflected imports. When
targeting any other execution environment, a Dart compiler reports a
compile-time error if it encounters a reflected import.

**TODO: How can we enforce this compile time restriction when macros
themselves are imported via normal imports? Do we need something like
https://github.com/dart-lang/language/pull/1831?**

This also means that macros cannot be _unit tested_. That is, you cannot
import, instantiate, and execute them as at runtime in the normal VM
environment (or any other normal runtime environment).

### Config-specific imports

When a reflected import is encountered, the compiler needs to know which
declarations it contains. The compiler needs this when it is compiling *the
macro* (which is targeting the macro execution environment) and not when it is
compiling *the end user program* (which may target the web, Flutter, etc.).

That means that when the reflected import is compiled, the compiler doesn't know
the final targeted platform. That in turn means that the compiler doesn't know
which branch to choose in any config-specific imports since it doesn't know
which platform flags will have which values. (Macros themselves are
configuration-independent and don't have access to the program's target
configuration either.)

Thus, when determining what declarations are available for a reflected import,
**the compiler always uses the default URI for any config-specific imports or
exports that it encounters.**. This may result in generating code which is not
actually compatible with all platforms, if the API differs across the
configuration specific imports.

**TODO: Consider making it a compile-time error for a reflected import to
having any config-specific imports, directly or transitively?**

## Changelog
