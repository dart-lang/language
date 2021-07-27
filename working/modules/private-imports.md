# Private Imports

**NOTE: This will likely be proposed as part of a collection of changes related
to how libraries work. I'm writing it up for now as a separate document mainly
to make it easier to get feedback on it.**

This proposal enables a library to import private declarations from other
libraries within the same package. Since sharing private identifiers across
multiple files is the raison d'être of part files, this also proposes
eliminating those in order to reduce the overall complexity of the Dart
language.

## Motivation

Identifiers starting with `_` are private in Dart. A declaration named with a
leading underscore cannot be accessed outside of the library where it is
defined. Semantically, private names behave as if the leading underscore is
replaced with a unique [mangled name][] based on the library where the name
appears.

[mangled name]: https://en.wikipedia.org/wiki/Name_mangling

This simple mechanism works surprisingly well, but can be limiting. It is an
established pattern in Dart to locate multiple class declarations in the same
library so that they can share access to private state and behavior.

If you want that sharing, but don't want to cram everything into a single file,
you are obliged to use part files. Parts have their own problems. Part files all
share the exact same top level scope as the main library file and cannot have
their own imports. Any imports must go in the main library file.

### Code generation

Code generation often uses parts so that the main library can access private
declarations in the generated library (or vice versa). However, since parts
can't have imports, any dependencies needed by the generated code must be
hand-authored in the main library file. This breaks the desired encapsulation
of the code generator and increases the friction of maintaining code that uses
code generation.

### Clear box testing

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
dependencies of the library under test.

## Private Imports

When importing a library within your own package, you can opt in to also
importing its private identifiers by adding a *private import clause*, which
looks like `show _`:

```dart
import 'other.dart' show _;
```

**TODO: Better syntax? Allow only importing some private names?**

**TODO: We could consider something like https://github.com/dart-lang/language/issues/1627 to allow importing only certain private instance members.**

It is a compile-error to use a private import clause in an import if the library
containing the import and the library being imported are not in the same
package. A library's package is:

1.  If the library's URI is "package:" then the package is the first path
    component after "package:".

2.  Else, if the library's URI is a file path that falls within the `rootUri` of
    a package in the surrounding package_config.json file, then the package is
    that package.

3.  Otherwise, the library has no package. It can't have any private imports or
    be imported with a private import clause.

In practice, this means that a library's package is the [pub package] that
contains it. That includes both libraries under `lib/` as well as other top
level directories like `test/`, `bin/`, etc. In particular, this means that a
test in a package can import private names from the package's libraries under
`lib/`.

[pub package]: https://dart.dev/tools/pub/cmd

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
collision error if the importing library tries to use the name:

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
where they collide if they are textually identical.

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

2.  It is a compile-time error if multiple declarations match from more than
    one library. For example:

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

    Here, it is not clear if `_private()` is intended to refer to
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

3.  Else, if all matching declarations are from the same library, then the
    identifier is resolved to the private name in that library.

4.  Else, if no names match, perform the same process but looking for extension
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

These rules mean that a member only overrides an imported private member *when
it is statically known at the member declaration that an override is occurring.*
This example does *not* override the imported member:

```dart
// a.dart
class A {
  _private() => 'A._private()';
}

// b.dart
import 'a.dart' show _;

class B { // No superinterface from a.dart.
  _private() => 'B._private()'; // Private to current library.
}

class C extends B implements A {
  // Error, missing implementation of A._private().
}
```

## Eliminate parts

Since private imports cover the use cases of part files and more, we remove
support for part files.

In order to not break existing code, we gate the support for private imports and
disallowing parts behind a new language version. When users upgrade to the
latest version, they can copy the contents of all of their part files into the
main library file, or convert the part files into libraries that are
private-imported by the main library.

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
