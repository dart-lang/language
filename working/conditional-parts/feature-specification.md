# Conditional Parts

Author: Erik Ernst

Status: Draft

Version: 1.0

Experiment flag: conditional-parts

This document specifies _conditional parts_, a feature that extends `part`
directives with configurable URIs so that different compilation environments can
select different part files for inclusion in a library, while guaranteeing that
the choice of conditional part file has no effect on the static analysis of the
containing library or of any library that imports it.

This specification builds on [Parts with Imports][] and [Augmentations][].

[Parts with Imports]: ../../accepted/future-releases/parts-with-imports/feature-specification.md
[Augmentations]: ../augmentations/feature-specification.md

## Introduction

Dart supports platform-dependent libraries through configurable URIs in `import`
and `export` directives. For example:

```dart
import 'socket_default.dart'
    if (dart.library.io) 'socket_io.dart'
    if (dart.library.js_interop) 'socket_js.dart';
```

Conditional imports can be used when platform-specific code can live in
separate libraries with public APIs. However, the static analysis of a
library that conditionally imports another library depends on a huge number
of details in the conditionally imported declarations, including
potentially every declaration in the transitively imported libraries from
there. There is no notion of a library signature, and this implies that
there is no way to ensure once and for all that the static analysis
succeeds for every possible choice at any given conditional import. The
only way it can be known that a program with conditional imports has no
compile-time errors (or other statically detected issues) is by repeating
the entire analysis of the program with every possible combination of
conditional import choices.

The main purpose of the conditional parts feature is to decouple a library
_L_ from the material that it obtains by means of a conditional part
directive choosing one of the parts _P1_ .. _Pk_, in the sense that the
static analysis of _L_ or any library or part that imports _L_ yields the
same outcome no matter which part _Pj_ is chosen. This is achieved
by specifying conditional part files such that it is a compile-time error
for them to contain anything that violates this property.

Moreover, separate libraries cannot access library-private declarations of
the importing library, and they cannot provide platform-specific
implementations for members of a class declared in the importing library
without duplicating the entire declaration or forwarding through extra
wrapper interfaces.

Conditional parts address both limitations. A `part` directive can now use the
same configurable URI syntax as a conditional `import` or `export` directive to
select a platform-specific part file, while static restrictions on conditional
part files ensure that static analysis of the containing library as a whole—and
of every library importing it—is independent of which conditional part file is
selected.

Consider a library that exposes a platform-specific logger and an extensible
`Channel` class:

```dart
// Library file "channel.dart".
part 'channel_default.dart'
    if (dart.library.io) 'channel_io.dart'
    if (dart.library.js_interop) 'channel_js.dart';

void logMessage(String message);

abstract class Channel {
  final String _name;

  Channel(this._name);

  factory Channel.open(String name) => _openChannel(name);

  // Abstract method: subclasses must implement this, and `super.send` is
  // a compile-time error.
  void send(String payload);

  // Implemented in a conditional part: subclasses inherit a concrete
  // implementation, and `super.close` is allowed.
  concrete void close();
}

Channel _openChannel(String name);

class BufferedChannel extends Channel {
  final List<String> _buffer = [];

  BufferedChannel(super.name);

  @override
  void send(String payload) {
    _buffer.add(payload);
  }

  @override
  void close() {
    _buffer.clear();
    super.close(); // OK because `Channel.close` has the modifier `concrete`.
  }
}
```

Each conditional part file uses a standard `part of` directive pointing
back to `'channel.dart'`, thus unambiguously pairing up these two files,
and uses `import` directives and `augment` declarations to fill in the
platform-specific implementations:

```dart
// Part file "channel_io.dart".
part of 'channel.dart';

import 'dart:io';
import 'src/io_channel_helper.dart';

augment void logMessage(String message) {
  stdout.writeln(message);
}

augment class Channel {
  augment void close() {
    stdout.writeln('Closing $_name');
  }
}

augment Channel _openChannel(String name) => createIoChannel(name);
```

```dart
// Part file "channel_js.dart".
part of 'channel.dart';

import 'dart:js_interop';
import 'src/js_channel_helper.dart';

@JS('console.log')
augment external void logMessage(String message);

augment class Channel {
  augment void close() {
    logMessage('Closing $_name');
  }
}

augment Channel _openChannel(String name) => createJsChannel(name);
```

```dart
// Part file "channel_default.dart".
part of 'channel.dart';

augment void logMessage(String message) {
  throw UnsupportedError('logMessage is not supported on this platform');
}

augment class Channel {
  augment void close() {
    throw UnsupportedError('Channel.close is not supported on this platform');
  }
}

augment Channel _openChannel(String name) {
  throw UnsupportedError('Channel.open is not supported on this platform');
}
```

Notice two central properties illustrated by this example:

1. **Configuration-independent static analysis**: Code generation must read the
   conditional part selected by the compilation environment in order to know
   which code to emit, but static analysis of `channel.dart` (and of any library
   that imports `channel.dart`) does not depend on any conditional part. The
   analyzer can ignore conditional `part` directives when summarizing
   `channel.dart` for client libraries. To preserve this property, a conditional
   part file cannot contain `export` directives, cannot introduce new top-level
   or member declarations, cannot add superinterfaces (`extends`, `with`, or
   `implements`) or enum entries, cannot specify default parameter values, and
   cannot complete `const` constructors (because static analysis needs to
   perform constant expression evaluation).

2. **The `concrete` modifier**: In `abstract class Channel`, both `send` and
   `close` are written without a body in `channel.dart`. Without an explicit
   distinction in `channel.dart`, static analysis ignoring conditional parts
   could not tell whether `super.close()` in `BufferedChannel` is valid or a
   compile-time error, nor whether a concrete subclass of `Channel` inherits an
   implementation of `close`. Marking `concrete void close();` in `channel.dart`
   declares that `close` is an implemented member for which a completing
   augmentation must exist. Consequently, `super.close()` is valid, subclasses
   inherit `close` as concrete, and a compile-time error occurs when compiling
   any configuration whose conditional part fails to complete `Channel.close`.
   Similarly, marking an incomplete non-`const` generative constructor with
   `concrete` indicates that its initializer list, redirection, or body will be
   supplied by an augmentation rather than implicitly defaulting to an empty
   initializer list and empty body.

## Specification

### Syntax

The word `concrete` is added as a built-in identifier.

The grammar of part directives (from [Parts with Imports][]) and member
declarations (from [Augmentations][] and [Primary Constructors][]) is modified
as follows, reusing `<configurableUri>`, `<configurationUri>`, and `<uriTest>`
from the language specification:

[Primary Constructors]: ../../accepted/3.13/primary-constructors/feature-specification.md

```ebnf
<partDirective> ::= // Modified rule.
    <metadata> 'part' <configurableUri> ';'

<declaration> ::= // Modified rule: allow 'concrete'.
    ...
  | ('external' | 'concrete') <constructorSignature> ';'
  | ('external' 'static'? | 'static' | 'concrete')? <getterSignature> ';'
  | ('external' 'static'? | 'static' | 'concrete')? <setterSignature> ';'
  | ('external' 'static'? | 'static' | 'concrete')? <functionSignature> ';'
  | ('external' | 'concrete')? <operatorSignature> ';'
  | ...
```

For easy reference, the above grammar rules rely on the following existing
grammar rules:

```ebnf
<configurableUri> ::=
    <uri> <configurationUri>*;

<configurationUri> ::=
    'if' '(' <uriTest> ')' <uri>;

<uriTest> ::=
    <dottedIdentifierList> ('==' <stringLiteral>)?;

<partHeader> ::= // Existing rule from Parts with Imports.
    <metadata> 'part' 'of' <uri> ';';

<partDeclaration> ::= // Existing rule from Parts with Imports.
    <partHeader> <importOrExport>* <partDirective>*
    (<metadata> <topLevelDeclaration>)* <EOF>;
```

A conditional part file uses the same `<partDeclaration>` syntax as any
other part file. *However, it is much more restricted when it comes to
non-syntax compile-time errors, which are specified below.*

### Static semantics

#### Unconditional files and conditional part files

A `<partDirective>` of the form `<metadata> 'part' <uri> ';'` *(with zero
`<configurationUri>` clauses)* is an _unconditional part directive_. A
`<partDirective>` with one or more `<configurationUri>` clauses is a
_conditional part directive_.

As specified for configurable URIs in the language specification, it is a
**compile-time error** if any string literal occurring as a `<uri>` or in a
`<uriTest>` of a `<partDirective>` contains a string interpolation.

In a given compilation environment, the `<configurableUri>` of a
`<partDirective>` _specifies a URI_ *U* using the same URI selection rules as
`import` and `export` directives: the default `<uri>` is chosen unless one or
more `<configurationUri>` tests evaluate to true in the compilation environment,
in which case the `<uri>` of the first such `<configurationUri>` in source order
is chosen.

We say that a Dart file *F* _includes_ the part file *P* denoted by the URI *U*
specified by a `<partDirective>` in *F* (resolved relative to the URI of *F*).

- It is a **compile-time error** if *P* does not parse as a `<partDeclaration>`,
  or if the `<uri>` in the leading `<partHeader>` (`part of <uri>;`) of *P*,
  resolved relative to *U*, does not denote *F*. *In particular, the `part`
  directive in *F* and the `part of` directive in *P* must agree, forming a loop
  of length 2.*

- All part-tree well-formedness rules from [Parts with Imports][] apply to the
  tree of included part files of a library *L*: it is a **compile-time error**
  if the *includes* relation has a cycle, if a part file is included more than
  once in the same library or across libraries in the same program, or if any
  included part file does not have the same language version, language-version
  override marker status, and enclosing package as its parent file.

For a library *L* with defining library file *F*<sub>0</sub>:

- The _unconditional files_ of *L* are *F*<sub>0</sub> together with every part
  file reachable from *F*<sub>0</sub> through zero or more *unconditional*
  `part` directives.

- A _conditional part file_ of *L* (in a given compilation environment) is any
  part file of *L* that is not an unconditional file of *L*. 
  
  *Equivalently, a part file of *L* is a conditional part file if and only
  if the path of `part` directives from *F*<sub>0</sub> to that file
  contains at least one conditional `part` directive. Every sub-part
  included by a conditional part file—whether by an unconditional or a
  conditional `part` directive—is therefore also a conditional part file.*

#### The `concrete` modifier

The modifier `concrete` can be placed on an incomplete introductory
declaration of an instance member (method, getter, setter, or operator) or
of a non-`const` generative constructor. It indicates that the declaration
is implemented by an augmenting declaration and must be complete once all
augmentations have been applied.

*A useful intuition about this modifier is that it implies that there must
be a complete augmenting declaration elsewhere (possibly in a conditional
part), and optionally some incomplete augmenting declarations (anywhere).
This perspective also motivates the choice to make it an error to mark a
declaration `concrete` if it is impossible to have such augmenting
declarations.*

It is a **compile-time error** if:

- An augmenting declaration *(a declaration with the modifier `augment`)*
  also has the modifier `concrete`. *Only an introductory declaration can
  be marked `concrete`.*

- A constructor declaration with the modifier `concrete` is complete. *That
  is, its formal parameter list contains an initializing formal parameter
  `this.x` or a super parameter `super.x`, or it has a body or an
  initializer list*.

- An instance member declaration with the modifier `concrete` is complete.
  *That is, the declaration is a non-abstract variable, or it is not a
  variable and it has a body.*

- A `mixin class` or `enum` declaration contains a constructor declaration
  with the modifier `concrete`. *A `mixin class` cannot declare non-trivial
  generative constructors, and generative constructors of an `enum` must be
  `const`, hence none of them can have a complete augmenting declaration in
  a conditional part.*

- A declaration with the modifier `concrete` is not complete after all
  augmentations in the library including those in included conditional part
  files have been applied. In particular, unlike an unmarked incomplete
  generative constructor, a `concrete` generative constructor is not implicitly
  completed with an empty initializer list and an empty body. This
  completeness check is performed with all possible selections of
  conditional part files included.

  *TODO: This set of inclusions can explode, and it may be non-trivial to
  compute. A simple case arises when there is just one conditional part in
  the entire library file set; in this case we just cover each of the
  specified choices in the conditional part directive. In the general case
  we could skip the completeness check in the analyzer and just perform the
  regular completeness checks for the given compilation environment during
  compilation.*

For static analysis of a class, mixin, mixin class, enum, or extension type
declaration *D* *(both when analyzing the unconditional files of the
library and when analyzing any library that imports it)*:

- Every conditional part directive is treated as if it were not present.
  *That is, all knowledge about completeness obtained in a conditional part
  is ignored, relying entirely on unconditional completeness, and on the
  modifier `concrete`.*

- If *D* is not an extension type, an instance member declaration of *D*
  whose introductory declaration has the modifier `concrete` (or which is
  completed by an augmentation in the unconditional files of the library)
  is considered to be a concrete member declaration of *D*:
  - It satisfies the interface of *D* when checking that a concrete class
    or enum implements all members of its interface.
  - Subclasses of *D* inherit a concrete implementation of the member,
    including for `noSuchMethod` forwarder checks.
  - Super-invocations (`super.m(...)`, `super.m`, `super.m = e`, and
    super-operator invocations) targeting the member are permitted, subject
    to the usual signature checks.

- If *D* is an `extension type`, an instance member declaration of *D*
  whose introductory declaration has the modifier `concrete` (or which is
  completed by an augmentation in the unconditional files of the library)
  is considered to be a concrete extension instance member declaration of
  *D*.

- If *D* is not an `extension type`, an incomplete instance member of *D*
  whose introductory declaration does not have the modifier `concrete`, and
  which is not completed by an augmentation in the unconditional files of
  the library, is considered to be a member of *D* whose abstractness is
  undetermined. A super-invocation which would invoke this member if it
  were implemented is a **compile-time error**. *In particular, we do not
  ignore it and proceed to use a declaration in a further superclass.*

- A generative constructor of *D* whose introductory declaration has the
  modifier `concrete` (and is not completed in the unconditional files of
  the library) is treated during static analysis of the unconditional files
  as a complete generative constructor.

During static analysis of a conditional part _P_, all conditional parts in
the parent chain from _P_ up to the library are considered to be
present. All other conditional parts are treated as if they were not
present.

#### Restrictions on conditional part files

*The intention is that it is a compile-time error for a conditional part file to contain any
directive or declaration that can alter or invalidate the static analysis of the
unconditional files of the containing library, or of any library importing the
containing library.*

Let *P* be a conditional part file of library *L*:

1. **No `export` directives**: It is a **compile-time error** if *P*
   contains a `<libraryExport>` directive. _Exports modify the exported
   namespace of L, which is observable in importers of L.*

   *`import` directives and `part` directives are permitted in P. Under
   [Parts with Imports][], `import` directives in P affect only the
   combined import scope and extension availability of P and its
   sub-parts.*

2. **No introductory top-level declarations**: It is a **compile-time
   error** if *P* contains a `<topLevelDeclaration>` that is not an
   augmenting declaration.  *That is, every top-level declaration in *P*
   must have the modifier `augment`.*

   *Platform-specific helper declarations can instead be placed in a
   separate library imported by *P*.*

3. **No added superinterfaces**: It is a **compile-time error** if an
   augmenting declaration of a `class`, `mixin`, `mixin class`, `enum`, or
   `extension type` in *P* contains an `extends` clause, a `with` clause,
   or an `implements` clause. *`on` clauses are already disallowed on
   augmenting `mixin` and `extension` declarations.*

4. **No added enum entries**: It is a **compile-time error** if an augmenting
   `enum` declaration in *P* declares one or more `<enumEntry>` elements. *Enum
   entries affect switch exhaustiveness, static member lookup on the enum, and
   the constant `values` list.*

5. **No introductory member declarations**: It is a **compile-time error** if
   the body of an augmenting `class`, `mixin`, `mixin class`, `enum`,
   `extension`, or `extension type` declaration in *P* contains a member
   declaration that is not an augmenting declaration. *That is, every member
   declaration in *P* must have the modifier `augment`.*

   *Public members would alter the interface or static namespace of the type.
   Even private members enter the merged member namespace of the enclosing
   declaration across the entire library, where they can change lexical
   identifier resolution inside member bodies in the unconditional files, cause
   override conflicts in subclasses, or add uninitialized fields.*

6. **No default parameter values**: It is a **compile-time error** if an
   augmenting function, method, or constructor declaration in *P* specifies a
   default value (`=` `<expression>`) for an optional positional or named formal
   parameter.

   *This implies that default values must be declared in the unconditional
   files of L. In particular, this is needed in generative constructors
   because super-parameters in other libraries may need to use this default
   value. We may be able to relax this requirement for non-constructors.*

7. **No completing `const` constructors**: It is a **compile-time error**
   if an augmenting constructor declaration in *P* has the modifier `const`
   and is complete. *This is necessary because constant expression
   evaluation is part of the static analysis.*

8. **Restrictions on augmenting instance variables**: In [Augmentations][], a
   non-`abstract` augmenting instance variable declaration completes an
   incomplete getter (and setter, if mutable) while introducing backing storage.
   It is a **compile-time error** if *P* contains a non-`abstract`,
   non-`external` augmenting instance variable declaration *v* in an augmenting
   declaration of *D*, and either:
   - *D* declares a `const` generative constructor *(which includes the
     case where *D* is an `enum`)*, or
   - *v* is `final` or has a potentially non-nullable type, *v* is not `late`,
     *v* has no initializing expression, and *D* either has no generative
     constructors or has at least one non-redirecting generative constructor
     that is completed *(explicitly or implicitly by default)* in the
     unconditional files of *L*.

   *Adding backing storage to a class with a `const` constructor would make
   constant evaluation and canonicalization depend on *P*. Adding an
   uninitialized non-`late` `final` or potentially non-nullable field when *D*
   already has a complete generative constructor in the unconditional files
   would invalidate that constructor.*

9. **No invalidation of library-wide checks**: All existing augmentation
   and declaration rules apply to the semantic declarations obtained after
   applying the augmentations in *P* *(in the standard pre-order
   depth-first augmentation application order specified in
   [Augmentations][])*. Any error arising from applying *P* (such as a
   signature mismatch, completing an already-complete declaration, creating
   a constructor redirection cycle, completing a constructor of a class
   with a primary constructor as non-redirecting, failing to complete a
   required incomplete declaration, or declaring an import prefix in *P*
   with the same basename as a top-level declaration of *L*) is a
   **compile-time error**.

#### Modular static analysis

Let *L* be a library and let *L*<sub>*u*</sub> be the set of unconditional files
of *L*.

- **Analyzing libraries that import *L***: Because no valid conditional part
  file of *L* can change *L*'s exported namespace, type hierarchy, member
  signatures, abstract-versus-concrete member status, default parameter values,
  enum entries, or constant expressions, a tool analyzing any library *L'* that
  imports or exports *L* may ignore all conditional `part` directives in
  *L*<sub>*u*</sub>.

- **Analyzing *L*<sub>*u*</sub>**: All identifier resolution, type inference,
  type checking, override checking, super-invocation checking, switch
  exhaustiveness checking, and constant evaluation in *L*<sub>*u*</sub> are
  completely determined by *L*<sub>*u*</sub> alone (ignoring conditional `part`
  directives). If *L*<sub>*u*</sub> contains no conditional `part` directives,
  completeness of all declarations in *L*<sub>*u*</sub> is also checked on
  *L*<sub>*u*</sub> alone.

- **Analyzing and compiling *L* in a compilation environment**: Given a
  compilation environment, each conditional `part` directive specifies a URI,
  determining the complete tree of files of *L*. Static analysis of the selected
  conditional part files checks their directives and augmenting declarations
  against *L*<sub>*u*</sub>, applies all augmentations in augmentation
  application order, and verifies that every declaration requiring completion
  *(top-level, `static`, `extension`, non-`const` `factory`, and `concrete`
  declarations)* is complete.

### Dynamic semantics

In a given compilation environment, each `<partDirective>` specifies a single
part file URI as defined by its `<configurableUri>`. Once the resulting tree of
part files of the library has been selected and all augmentations have been
applied in augmentation application order to produce combined semantic
declarations, the dynamic semantics of the library are identical to those
specified by [Parts with Imports][] and [Augmentations][].

### Language versioning

This feature is language versioned.

*Enabling this feature makes `concrete` a built-in identifier, which is a
breaking syntactic change for pre-feature code that uses `concrete` as a type
name or import prefix.*

As required by [Parts with Imports][], every part file of a library—including
every conditional part file—must have the same language version as its parent
file.

### Discussion

TODO Make `concrete` a regular identifier, not built-in?
TODO Drop `concrete` entirely and make it an error to super-invoke when
underdefined.

TODO Perhaps it is necessary to require that every part file in a library
file tree is conditional if at least one of them is conditional? The
problem is that we may not want to specify and implement what it means for
an analysis to take the non-conditional parts into account, and ignore the
conditional parts.

TODO We can allow incomplete augmenting declarations on complete
declarations even in conditional parts. But it is useful?
TODO It must be an error for a conditional part to contain a complete
constant constructor declaration.

TODO `concrete` could just be `external`, that's what the patch mechanism
does today.

TODO Is it supported to have conditional parts of conditional parts?

TODO IS it supported to have multiple conditional parts in the same
library? Do the have to use the same conditions?

TODO Could we use a compile-time only check on the completeness of
declarations which are required to be complete? (That is, the analyzer
doesn't know, but every compilation will reveal whether this particular
configuration does satisfy the completeness requirement.)

TODO Can we have a declaration which is complete in some configurations and
incomplete in others ()

#### Platform-specific helper declarations and private state

Disallowing introductory top-level and member declarations in conditional part
files keeps the library's top-level namespace and every class's member namespace
invariant across all configurations, while remaining expressive in practice:

- **Helper functions, classes, and extensions**: Because a conditional part file
  can have its own `import` directives, any platform-specific helper classes,
  functions, extensions, or top-level state can be placed in a separate helper
  library *(for instance, `'src/io_helpers.dart'`)* imported only by that
  conditional part file.

- **Platform-specific instance state**: When a class needs platform-specific
  instance fields, it can either expose `factory` constructors completed in the
  conditional part that return platform-specific subclasses declared in an
  imported helper library, or declare a private field *(such as `final Object?
  _handle;`)* and a `concrete` generative constructor in the unconditional
  library file whose completing augmentation in each conditional part
  initializes `_handle`.

#### Variable declarations and `concrete`

The grammar allows `concrete` on incomplete getters and setters (`concrete int
get x;`, `concrete set x(int value);`), rather than on variable declarations. A
variable declaration without `abstract` *(such as `int? x;` or `final int x;`)*
already declares a complete variable with backing storage, while `concrete
abstract int x;` would juxtapose contradictory modifiers. Under
[Augmentations][], explicit getter and setter declarations `concrete int get x;`
and `concrete set x(int value);` can still be completed either by augmenting
getters and setters or by an augmenting variable declaration `augment int x =
0;` (subject to the restrictions on augmenting instance variables above).

#### Standalone analysis of unselected conditional part files

In an IDE, a developer may open a conditional part file *P* *(such as
`channel_js.dart`)* that is not selected by the tool's default compilation
environment. Because *P* starts with `part of 'channel.dart';`, the tool can
locate the parent file *F*, verify that *F* contains a `<partDirective>` whose
`<configurableUri>` lists a URI resolving to *P*, and analyze *P* directly
against the configuration-independent static model of the unconditional files of
the library—without needing to load or resolve conditional part files for other
platforms.

### Changelog

1.0 - October 28, 2026

* First version of this document.
