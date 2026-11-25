# Conditional Parts

Author: Erik Ernst

Status: Draft

Version: 1.2

Experiment flag: conditional-parts

This document specifies _conditional parts_, a feature that extends `part`
directives with configurable URIs so that different compilation
environments can select different part files for inclusion in a library _L_,
while guaranteeing that the choice of conditional part file has no effect
on the static analysis of any library that imports _L_.

This specification builds on [Parts with Imports][] and [Augmentations][].

[Parts with Imports]: ../../accepted/future-releases/parts-with-imports/feature-specification.md
[Augmentations]: ../augmentations/feature-specification.md

Similar ideas have been discussed in the language team for a while. For
example, [Sealed Parts][] is a proposal where private declarations in the
sealed parts are not exposed to the parent library. The proposal in this
document uses a different approach in that private declarations in
conditional parts are available to the enclosing library, but it is
enforced that they do not influence downstream code by putting restrictions
on the code in conditional part files. This allows the compilation to
proceed in exactly the same manner as with regular part files when the
choice of which alternative to use has been made.

[Sealed Parts]: https://github.com/dart-lang/language/issues/3810

Another proposal is [Patch files using augmentation parts][], where
a part is marked as being an `augment part` and constrained in ways
that are similar to the constraints in the proposal in this document,
though in a much less complete form than this document. Another
difference is that this proposal allows several kinds of introductory
declarations with a public name in conditional parts, aided by
soundness restrictions.

[Patch files using augmentation parts]: https://github.com/dart-lang/language/issues/4568

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

A `part` directive can now use the same configurable URI syntax as a
conditional `import` or `export` directive to select a platform-specific
part file, while compile-time restrictions on conditional part files ensure
that the choice has no effect on downstream code. The configurable URI
syntax is generalized slightly, such that the "default" URI (at the front)
is optional; it is a compile-time error if no default is specified and no
configuration URI can be selected.

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

  // Abstract method: subclasses must implement it, and
  // `super.send...` is a compile-time error.
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
    super.close(); // OK: `Channel.close` is `concrete`.
  }
}
```

Each conditional part file uses a standard `part of` directive pointing
back to `'channel.dart'`, thus unambiguously pairing up these two files,
and uses `import` directives, `augment` declarations, and private helper
declarations to fill in the platform-specific implementations:

```dart
// Part file "channel_io.dart".
part of 'channel.dart';

import 'dart:io';

augment void logMessage(String message) {
  stdout.writeln(message);
  _flushStdout();
}

void _flushStdout() {
  // Platform-specific private helper local to "channel_io.dart".
}

augment abstract class Channel {
  int _closeCount = 0;

  augment void close() {
    _closeCount++;
    stdout.writeln('Closing $_name: $_closeCount');
  }
}

class _IoChannel extends Channel {
  _IoChannel(super.name);

  @override
  void send(String payload) {
    stdout.writeln('[$_name] $payload');
  }
}

augment Channel _openChannel(String name) => _IoChannel(name);
```

```dart
// Part file "channel_js.dart".
part of 'channel.dart';

import 'dart:js_interop';

@JS('console.log')
augment external void logMessage(String message);

augment abstract class Channel {
  augment void close() {
    logMessage('Closing $_name');
  }
}

class _JsChannel extends Channel {
  _JsChannel(super.name);

  @override
  void send(String payload) {
    logMessage('[$_name] $payload');
  }
}

augment Channel _openChannel(String name) => _JsChannel(name);
```

```dart
// Part file "channel_default.dart".
part of 'channel.dart';

Never _unsupported(String member) =>
    throw UnsupportedError('$member is not supported on this platform');

augment void logMessage(String message) => _unsupported('logMessage');

augment abstract class Channel {
  augment void close() => _unsupported('Channel.close');
}

augment Channel _openChannel(String name) =>
    _unsupported('Channel.open');
```

Notice two central properties illustrated by this example:

1. **Configuration-independent static analysis**: Code generation must read
   the conditional part selected by the compilation environment in order to
   know which code to emit, but static analysis of `channel.dart` (and of
   any library that imports `channel.dart`) does not depend on any
   conditional part. The analyzer can ignore the conditional `part`
   directive when summarizing `channel.dart` for client libraries. To
   preserve this property, a conditional part file is subject to several
   constraints: It cannot contain `export` directives, introduction of
   public declarations is constrained, superinterfaces (`extends`, `on`,
   `with`, or `implements`) or enum entries cannot be added by declarations
   augmenting declarations in unconditional files, direct subtypes cannot
   be added to `sealed` types declared in unconditional files, formal
   parameter default values cannot be specified in augmenting declarations,
   and augmenting declarations in conditional part files can only complete
   unconditional instance members or constructors that are marked `concrete`
   or are non-`const` `factory` constructors.

2. **The `concrete` modifier**: In `abstract class Channel`, both `send`
   and `close` are written without a body in `channel.dart`. Without an
   explicit distinction in `channel.dart`, static analysis ignoring
   conditional parts could not tell whether `super.close()` in
   `BufferedChannel` is valid or a compile-time error, nor whether a
   concrete subclass of `Channel` inherits an implementation of
   `close`. Marking `concrete void close();` in `channel.dart` declares
   that `close` is an implemented member for which a completing
   augmentation must exist. Consequently, `super.close()` is valid,
   subclasses inherit `close` as concrete, and a compile-time error occurs
   when compiling any configuration whose conditional part fails to
   complete `Channel.close`. Conversely, an incomplete instance member
   without `concrete` such as `send` cannot be completed in a conditional
   part and remains an ordinary abstract member. Similarly, marking an
   incomplete non-`const` generative constructor with `concrete` indicates
   that its initializer list, redirection, and/or body will be supplied by
   an augmentation rather than implicitly defaulting to an empty
   initializer list and empty body, whereas an incomplete generative
   constructor without `concrete` cannot be completed in a conditional
   part.

   *One might think that abstractness control on constructors is
   superfluous. However, a constructor which is introduced in unconditional
   code may be generative with no initializer list and no body. Some
   instance variables may then be left uninitialized according to
   unconditional code. This causes the unconditional code to have a
   compile-time error. But we can make it `concrete` and check that the
   missing initializer list elements are added in an augmentation in the
   conditional code of every choice of part file.*

## Specification

### Syntax

The word `concrete` is added as a built-in identifier.

The grammar of part directives (from [Parts with Imports][]) and member
declarations (from [Augmentations][] and [Primary Constructors][]) is modified
as follows:

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
  ;

<configurableUri> ::= // Modified rule.
    <uri>? <configurationUri>*;
```

For easy reference, the above grammar rules rely on the following existing
grammar rules:

```ebnf
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

*As specified for configurable URIs in the language specification, it is a
compile-time error if any string literal occurring as a `<uri>` or in a
`<uriTest>` of a `<partDirective>` contains a string interpolation.*

*In a given compilation environment, the `<configurableUri>` of a
`<partDirective>` specifies a URI U using the same URI selection rules as
`import` and `export` directives: the default `<uri>`, if present, is
chosen unless one or more `<configurationUri>` tests evaluate to true in
the compilation environment, in which case the `<uri>` of the first such
`<configurationUri>` in source order is chosen.*

We say that a Dart file *F* _includes_ the part file *P* denoted by the URI *U*
specified by a `<partDirective>` in *F* (resolved relative to the URI of *F*).

- It is a **compile-time error** if a `<configurableUri>` is empty, or it
  has no `<uri>` at the front and none of the `<configurationUri>` clauses
  is selected.

- It is a **compile-time error** if *P* does not parse as a `<partDeclaration>`,
  or if the `<uri>` in the leading `<partHeader>` (`part of <uri>;`) of *P*,
  resolved relative to *U*, does not denote *F*.

- It is a **compile-time error** if a conditional part file contains a
  conditional `part` directive, or if the unconditional files of a library
  *L* together contain more than one conditional `part` directive. *Hence,
  a library has at most one conditional `part` directive, which occurs in
  an unconditional file, and each selected conditional part is included
  together with the entire unconditional file tree under it. There are no
  nested conditional parts and no combinations of independent conditional
  `part` directives in the same library.*

- All part-tree well-formedness rules from [Parts with Imports][] apply to the
  tree of included part files of a library *L*: it is a **compile-time error**
  if the *includes* relation has a cycle, if a part file is included more than
  once in the same library or across libraries in the same program, or if any
  included part file does not have the same language version, language-version
  override marker status, and enclosing package as its parent file.

For a library *L* with library file *F*<sub>0</sub>:

- The _unconditional files_ of *L* are *F*<sub>0</sub> together with every part
  file reachable from *F*<sub>0</sub> through one or more *unconditional*
  `part` directives.

- A _conditional part file_ of *L* (in a given compilation environment) is any
  part file of *L* that is not an unconditional file of *L*.

  *Equivalently, a part file of *L* is a conditional part file if and only
  if the path of `part` directives from *F*<sub>0</sub> to that file
  contains a conditional `part` directive. Every sub-part included by a
  conditional part file is therefore also a conditional part file.*

Finally, we reduce the support for instance variable promotions: a private
instance variable whose introductory declaration occurs in the
unconditional files of a library with conditional parts is not promotable.

#### The `concrete` modifier

The modifier `concrete` can be placed on an incomplete introductory
declaration of an instance member (method, getter, setter, or operator) or
of a non-constant generative constructor. It indicates that the declaration
is implemented by an augmenting declaration and must be complete once all
augmentations have been applied.

*A useful intuition about this modifier is that it implies that there must
be a complete augmenting declaration elsewhere (typically in a conditional
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
  constant, hence none of them can have a complete augmenting declaration in
  a conditional part.*

- An `extension type` or `extension` declaration has an introductory
  instance member declaration with the modifier `concrete`. *Extension and
  extension type instance members cannot be abstract.*

- A declaration with the modifier `concrete` is not complete after all
  augmentations in the library including those in the included conditional
  part subtree have been applied. In particular, unlike an unmarked
  incomplete generative constructor, a `concrete` generative constructor is
  not implicitly completed with an empty initializer list and an empty
  body. This completeness check is performed for each URI listed in the
  library's conditional `part` directive *(if any)*, together with the
  unconditional file tree under that URI.

For static analysis by the analyzer, the conditional `part` directive *(if
any)* is treated as if it were not present. *That is, all knowledge about
completeness obtained in a conditional part is ignored, relying entirely on
unconditional completeness, and on the modifier `concrete`.*

For static analysis of a class, mixin, mixin class, enum, or extension type
declaration *D* *(both when analyzing the unconditional files of the
library and when analyzing any library that imports it)*:

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

- If *D* is not an `extension type`, an incomplete instance member of *D*
  whose introductory declaration does not have the modifier `concrete`, and
  which is not completed by an augmentation in the unconditional files of
  the library, is an abstract member of *D*. *Because a conditional part
  cannot complete such a member, its abstractness does not depend on which
  conditional part is selected.*

- A generative constructor of *D* whose introductory declaration has the
  modifier `concrete` (and is not completed in the unconditional files of
  the library) is treated during static analysis of the unconditional files
  as a complete generative constructor. It is assumed that it initializes
  every instance variable of the enclosing membered declaration that needs
  to be initialized. *An unmarked incomplete generative constructor cannot
  be completed in a conditional part, so it is implicitly completed with an
  empty initializer list and empty body as usual.*

During static analysis of a conditional part file _P_, the entire
conditional part subtree containing _P_ *(that is, the branch of the
library's conditional `part` directive containing _P_, together with all
unconditional sub-parts under it)* is considered to be present together
with the unconditional files of the library. All other branches of the
conditional `part` directive are treated as if they were not present.

#### Restrictions on conditional part files

*The intention is that it is a compile-time error for a conditional part
file to contain any directive or declaration that can alter or invalidate
the static analysis of the unconditional files of the containing library,
or of any library importing the containing library.*

We say that an augmenting declaration *D* _augments an unconditional
declaration_ if the introductory declaration with the same name as *D* in
the augmentation context of *D* occurs in an unconditional file.
*The declaration which is augmented by *D* according to [Augmentations][]
can itself be an augmenting declaration in a conditional part. The rules
below refer to the introductory declaration, such that they also apply
when a conditional part contains several augmenting declarations of the
same declaration.*

- It is a **compile-time error** for a conditional part to contain an
  `export` directive.

- It is a **compile-time error** for a conditional part to contain an
  introductory top-level declaration with a public name.

- It is a **compile-time error** for a conditional part _F_ to contain an
  introductory declaration _D_ whose name _n_ is private, unless one of the
  following conditions hold:
  - No name whose basename is the basename of _n_ occurs in an
    unconditional file in the file tree of the enclosing library.
  - The declaration _D_ is an overriding declaration with the same member
    signature as the combined member signature _s_ of the same name in the
    direct superinterfaces of the enclosing type-introducing declaration
    _D_<sub>t</sub>. Moreover, if _D_<sub>t</sub> inherits an
    implementation of _n_ then it must have the same signature as _D_, and
    _D_ must be complete, or it must be completed by an augmentation in the
    same conditional part file _F_ or in a file in the file tree under _F_.

- It is a **compile-time error** for an introductory `extension` declaration
  in a conditional part to contain an instance member declaration whose
  name is public, or whose name is private and has the same basename as a
  name occurring in an unconditional file in the file tree of the enclosing
  library.
  *Note that all operators and `call` have public names. Hence no member
  declared in an introductory `extension` in a conditional part can match
  any implicit extension member resolution in an unconditional file
  (including property accesses, method invocations, operator invocations,
  function expression invocations of `call`, object patterns, and
  relational patterns). This avoids type-based applicability analysis over
  unconditional files while still allowing private helper extensions local
  to a conditional part. A simpler, less expressive alternative is to make
  every introductory `extension` declaration in a conditional part a
  compile-time error.*

- It is a **compile-time error** for an augmenting type introducing
  declaration in a conditional part that augments an unconditional
  declaration to have an `extends`, `on`, `with`, or `implements` clause.

- It is a **compile-time error** for a type introducing declaration in a
  conditional part, whether introductory or augmenting, to have a `sealed`
  class or a `sealed` mixin declared in an unconditional file as a direct
  superinterface.

- It is a **compile-time error** for an augmenting `enum` declaration in a
  conditional part that augments an unconditional declaration to declare
  any enum entries.

- It is a **compile-time error** for an augmenting type introducing
  declaration _D_ in a conditional part that augments an unconditional
  declaration to contain an introductory member or constructor declaration
  _D_<sub>m</sub> with a public name _n_, which includes a constructor
  whose uniform name is `new`, except for the following case:

  _D_<sub>m</sub> is an instance member declaration, and all of the
  following conditions hold:
  - _D_ is an `enum` or `class` declaration which is not a `mixin class`.
  - _n_ is not `==`, `hashCode`, or `noSuchMethod`.
  - _D_ inherits a concrete implementation of _n_ in the unconditional
    files, and _D_<sub>m</sub> is a complete declaration, or it is
    completed by an augmenting declaration in the same conditional part
    file or in the file tree under it. _D_<sub>m</sub> has the same member
    signature as said inherited implementation, and as the combined member
    signature of the same name in the direct superinterfaces of _D_. *The
    inherited implementation must be a valid implementation of n in D.*
  - No top-level declaration, import prefix, or imported declaration with
    the basename of _n_ is in scope at an unconditional declaration of _D_.
    *This would cause n to be shadowed by the member declaration for code
    in the bodies of D members.*

  *In other words, a conditional part can override an inherited public
  instance member of a class or an enum when the override changes neither
  the interface of D nor the abstractness of the member.*

- It is a **compile-time error** for an augmenting declaration in a
  conditional part that augments an unconditional declaration to contain
  an introductory instance member declaration that is not complete after
  all augmentations in the conditional part have been applied.
  *The conditional code cannot add an obligation to implement a member,
  private or public, to be fulfilled by code in unconditional files, or
  at some other location in downstream code.*

  *Note that for downstream code in other libraries, an unimplemented
  private member in an `abstract` class does not cause a compile-time
  error in concrete subclasses in other libraries. We still maintain this
  error in order to avoid the situation where a noSuchMethod thrower
  is implicitly generated in such subclasses.*

- It is a **compile-time error** for an augmenting declaration _D_ in a
  conditional part that augments an unconditional declaration to contain an
  introductory private instance member declaration with name _n_ unless one
  of the following conditions holds:
  - _D_ is not an `extension type` nor a `mixin`, _D_ inherits a concrete
    implementation of _n_ in the unconditional files, and no top-level
    declaration or import prefix with the basename of _n_ is in scope at
    an unconditional declaration of _D_.
    *The last requirement ensures that an unqualified occurrence of the
    name in a member of an unconditional declaration of _D_ has the same
    meaning whether or not the conditional part is included.*
  - Neither _D_ nor any subtype of _D_ in the library has a public name or
    is aliased by a `typedef` with a public name in the library, and no
    identifier whose basename is the basename of _n_ occurs in an
    unconditional file.
  - _D_ is not a `mixin` or `mixin class`, no identifier whose basename is
    the basename of _n_ occurs in an unconditional file, and no augmenting
    declaration in a conditional part that augments an unconditional
    declaration of a type other than _D_ contains an introductory instance
    member declaration with the same basename as _n_. *In other words, a
    conditional part can add a private instance member with a fresh name to
    a single type declared in an unconditional file.  Introductory type
    declarations in the conditional part can override it.*

- It is a **compile-time error** for an augmenting generative constructor
  declaration or member declaration in a conditional part that augments a
  constructor or member declared in an unconditional file to specify a
  default value for an optional formal parameter, or (for the constructor)
  to declare an optional formal parameter as a super-parameter (`super.p`).

- It is a **compile-time error** for an augmenting declaration in a
  conditional part that augments an unconditional declaration _D_ to be
  complete *(including a non-`abstract` augmenting variable declaration
  completing an introductory getter or setter)* if:
  - _D_ is an instance member declaration of a `class`, `mixin`,
    `mixin class`, or `enum` whose introductory declaration does not have
    the modifier `concrete`, or
  - _D_ is a constructor declaration whose introductory declaration neither
    has the modifier `concrete` nor is a non-`const` `factory` constructor.
  *Consequently, an unmarked incomplete instance member in an unconditional
  file remains abstract in every configuration, an unmarked incomplete
  generative constructor remains implicitly completed, and no `const`
  constructor (generative or `factory`) can be completed in a conditional
  part. Top-level, `static`, `extension`, `extension type`, and
  non-`const` `factory` declarations cannot be abstract and may be
  completed in a conditional part without `concrete`.*

- It is a **compile-time error** for an augmenting declaration of a type _D_
  in a conditional part that augments an unconditional declaration to
  declare a non-`abstract`, non-`external` instance variable if _D_ is a
  `mixin`, a `mixin class`, or declares a `const` generative constructor.
  *A `mixin` or `mixin class` with an instance variable cannot be mixed
  into a class with a `const` constructor, and adding an instance variable
  to a type with a `const` generative constructor can affect constant
  evaluation in downstream code; any constant-valued field can be expressed
  as a getter or `static const` variable instead.*

- It is a **compile-time error** for an augmenting `mixin` declaration in a
  conditional part that augments an unconditional declaration to contain a
  super-invocation of a member named _n_, unless a declaration of that
  mixin in an unconditional file contains a super-invocation of a member
  named _n_.
  *For example, `super.m()` and `super.m` invoke the member named `m`,
  `super.m = e` invokes the member named `m=`, and `super + e` invokes the
  member named `+`. This ensures that the set of super-invoked members of
  a mixin is determined by the unconditional files, such that the
  requirements on the superclass in a mixin application do not depend on
  a conditional part. A simpler, less expressive alternative is to make
  every super-invocation in such an augmenting `mixin` declaration a
  compile-time error. A `mixin class` needs no such rule because its
  superclass is `Object`, and every superclass in a mixin application has
  a concrete implementation of each member of `Object`.*

- It is a **compile-time error** for an augmenting declaration _D_ of a
  `class`, `mixin class`, or `enum` in a conditional part that augments an
  unconditional declaration to contain an introductory constructor
  declaration if _D_ does not explicitly declare any constructor in an
  unconditional file. *This would eliminate the default constructor, which
  can break downstream code.*

#### Modular static analysis

Let *L* be a library and let *L*<sub>*u*</sub> be the set of unconditional files
of *L*.

- Analyzing libraries that import *L*: Because no valid conditional part
  file of *L* can change *L*'s exported namespace, public type hierarchy,
  `sealed` subtype sets, public member signatures, abstract-versus-concrete
  member status, default parameter values, enum entries, or constant
  expressions, a tool analyzing any library *L'* that imports or exports *L* may
  ignore the conditional `part` directive *(if any)* in *L*<sub>*u*</sub>.

- Analyzing *L*<sub>*u*</sub>: Because no reference in *L*<sub>*u*</sub> can
  resolve to an introductory private declaration in a conditional part file, and
  no introductory private declaration in a conditional part file can conflict
  with, shadow, or add abstract members or `sealed` subtypes to declarations in
  *L*<sub>*u*</sub>, all identifier resolution, field promotability, type
  inference, type checking, override checking, super-invocation checking,
  switch exhaustiveness checking, and constant evaluation in
  *L*<sub>*u*</sub> are completely determined by *L*<sub>*u*</sub> alone
  (ignoring any conditional `part` directive). If *L*<sub>*u*</sub>
  contains no conditional `part` directive, completeness of all
  declarations in *L*<sub>*u*</sub> is also checked on *L*<sub>*u*</sub>
  alone.

- Analyzing and compiling *L* in a compilation environment: With a given
  compilation environment, the conditional `part` directive *(if any)*
  specifies a URI, determining the complete tree of files of *L*. Static
  analysis of the selected conditional part files checks their directives,
  introductory private declarations, and augmenting declarations against
  *L*<sub>*u*</sub>, applies all augmentations in augmentation application
  order, and verifies that every declaration requiring completion
  *(top-level, `static`, `extension`, `extension type`, non-constant
  `factory`, `concrete`, and introductory member declarations in
  conditional parts)* is complete.

  *This process is identical to the analysis and compilation process where
  the conditional `part` directive in L (if any) has been replaced by the
  unconditional (regular) `part` directive specifying the same choice of
  part file.*

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

As required by [Parts with Imports][], every part file of a library,
including every conditional part file, must have the same language version
as its parent file.

### Discussion

#### Use a different word than `concrete`

Lots of possible choices. However, none of the reserved or built-in
identifiers seem to be a very good match.

The patch mechanism uses `external`, which is somewhat confusing
conceptually, but seems to work fine in the context of patching.

#### Make `concrete` a regular identifier

We could avoid making `concrete` a built-in identifier (it would then be a
`<typeIdentifier>`). This would allow us to avoid a (probably tiny) amount
of breakage in existing code.

On the other hand, this might give rise to less informative diagnostics in
case of syntax errors around the word `concrete`.

#### Drop the support for the `concrete` modifier entirely

Instead of requiring `concrete` to complete an unconditional instance
member in a conditional part, we could drop `concrete` entirely and treat
every incomplete instance member in a library with a conditional part as
having undetermined abstractness. This would avoid a certain amount of
syntactic complexity, since developers wouldn't have to learn or place the
`concrete` keyword.

However, undetermined abstractness requires a set of special cross-library
constraints on subclasses, super-invocations, mixin applications,
`noSuchMethod` forwarders, `Enum` subtypes, and private name collisions,
making every super-invocation targeting such a member a compile-time error
and turning every ordinary abstract member in a library into one with
undetermined abstractness as soon as a conditional `part` directive is
added.

#### Require `concrete` on all conditionally completed declarations

This specification requires `concrete` on unconditional instance members
and generative constructors completed in a conditional part, while allowing
declarations that cannot be abstract (such as top-level, `static`,
`extension`, `extension type`, and non-`const` `factory` declarations) to
be completed without `concrete`.

We could go further and require `concrete` on all incomplete declarations
completed in a conditional part (or even in any augmentation), and make it
an error for an unmarked incomplete declaration to be completed anywhere.
That would make conditional completion syntactically uniform across all
declaration kinds at the cost of extra `concrete` modifiers on declarations
that are already unambiguously non-abstract.

#### Restrict parts such that a conditional part is the only part directive

This specification allows at most one conditional `part` directive in the
unconditional files of a library, alongside any number of unconditional
`part` directives, and each conditional part branch may itself have a tree
of unconditional sub-parts.

We could go even further and require that a conditional `part` directive
must be the _only_ `part` directive in the library, though unconditional
`part` directives do not introduce any configuration combinations and are
straightforward to keep. Conversely, allowing multiple independent
conditional `part` directives in the same library would create a
combinatorial explosion in completeness checking and would break standalone
analysis of a single conditional part branch (for example, two independent
conditional parts could each introduce the same fresh private instance
member on two different classes and conflict only when both are selected
together).

#### Should we check completeness only during compilation?

Consider all `concrete` declarations in an unconditional file of a library
_L_, as well as all declarations which are incomplete when taking only the
unconditional part tree into account and which are incapable of being
abstract (for example, top-level, `static`, `extension`, `extension type`,
or non-`const` `factory` declarations).

Because a library has at most one conditional `part` directive, checking
that every branch completes all of these declarations is linear in the
number of URIs in that directive rather than combinatorial. Even so, we
could choose to perform this completeness check only during compilation, or
only on explicit developer request, if loading all platform-specific part
trees during analysis is undesirable.

#### Variable declarations and `concrete`

The grammar allows `concrete` on incomplete getters and setters (`concrete int
get x;`, `concrete set x(int value);`), rather than on variable declarations. A
variable declaration without `abstract` *(such as `int? x;` or `final int x;`)*
already declares a complete variable with backing storage, while `concrete
abstract int x;` would juxtapose apparently contradictory modifiers. Under
[Augmentations][], explicit getter and setter declarations `concrete int get x;`
and `concrete set x(int value);` can still be completed either by augmenting
getters and setters or by an augmenting variable declaration `augment int x =
0;` (subject to the restrictions on augmenting instance variables above).

In other words, this proposal avoids `concrete abstract` variable
declarations because they may seem contradictory, but the same thing can be
expressed using an abstract `concrete` getter declaration and possibly an
abstract `concrete` setter declaration.

#### Standalone analysis of unselected conditional part files

In an IDE, a developer may open a conditional part file *P* *(such as
`channel_js.dart`)* that is not selected by the tool's default compilation
environment. Because *P* starts with `part of 'channel.dart';`, the tool
can locate the parent file *F*, verify that *F* contains a
`<partDirective>` whose `<configurableUri>` lists a URI resolving to *P*,
and analyze *P* directly against the configuration-independent static model
of the unconditional files of the library. In this case it doesn't need to
load or resolve conditional part files for other platforms.

### AI disclosure

The compile-time error specifications in this document (in particular, the ones
restricting the code in conditional part files) were developed in a series of
steps where various AI agents were asked to find violations of the core property
of this proposal, namely, that the static analysis of a library that contains
conditional parts does not depend on which part file is chosen as the meaning of
any given conditional part directive. The agents proposed error specifications
and created example programs (shown in the appendix below) to illustrate the
specific kind of violation of this "does not depend" property that the given
error prevents. AI agents were also used to find inconsistencies and mistakes in
the document.

### Appendix: Justification of the restrictions on conditional part files

This appendix revisits each error specification in the section
'Restrictions on conditional part files'. For each of them it shows the
error specification *(without its commentary)*, an example which is
accepted if that error specification is removed, and an explanation of how
the example then allows the choice of conditional part to influence the
static analysis of code outside the conditional parts.

Every example uses the following four files:

```dart
// Library file 'l.dart'.
part 'p1.dart'
    if (useP2 == 'true') 'p2.dart';

// Followed by the declarations shown as "In 'l.dart'".
```

```dart
// Part file 'p1.dart', selected by default.
part of 'l.dart';

// Followed by the declarations shown as "In 'p1.dart'".
```

```dart
// Part file 'p2.dart', selected when `useP2` is 'true'.
part of 'l.dart';

// Followed by the declarations shown as "In 'p2.dart'".
```

```dart
// Library file 'main.dart'.
import 'l.dart';

// Followed by the declarations shown as "In 'main.dart'".
```

A part file which is not shown in an example contains no declarations.

In each example, `p1.dart` satisfies every rule, and `p2.dart` violates the
rule under consideration and no other rule. Without that rule, `l.dart` has
no compile-time errors with `p1.dart` and no compile-time errors with
`p2.dart`, but the static analysis of `main.dart` depends on which part is
selected. *The rule about incomplete introductory instance members is an
exception, as explained below.*

#### Export directives

> It is a **compile-time error** for a conditional part to contain an
> `export` directive.

```dart
// Library file 'extra.dart'.
int extraValue = 42;

// In 'p2.dart'.
export 'extra.dart';

// In 'main.dart'.
int useExtra() => extraValue;
```

When `p2.dart` is selected, the exported namespace of `l.dart` contains
`extraValue`, and `useExtra` has no errors. When `p1.dart` is selected,
`extraValue` is an undefined name in `main.dart`.

#### Public top-level declarations

> It is a **compile-time error** for a conditional part to contain an
> introductory top-level declaration with a public name.

```dart
// In 'p2.dart'.
int publicHelper() => 1;

// In 'main.dart'.
int usePublicHelper() => publicHelper();
```

`publicHelper` is exported by `l.dart` only when `p2.dart` is selected.
Hence `usePublicHelper` has no errors with `p2.dart`, and it invokes an
undefined function with `p1.dart`.

#### Private declarations whose name occurs in an unconditional file

> It is a **compile-time error** for a conditional part _F_ to contain an
> introductory declaration _D_ whose name _n_ is private, unless one of the
> following conditions hold:
> - No name whose basename is the basename of _n_ occurs in an
>   unconditional file in the file tree of the enclosing library.
> - The declaration _D_ is an overriding declaration with the same
>   member signature as the combined member signature _s_ of the same name
>   in the direct superinterfaces of the enclosing type-introducing
>   declaration _D_<sub>t</sub>. Moreover, if _D_<sub>t</sub> inherits an
>   implementation of _n_ then it must have the same signature as _D_, and
>   _D_ must be complete, or it must be completed by an augmentation in the
>   same conditional part file _F_ or in a file in the file tree under _F_.

```dart
// In 'l.dart'.
class A {
  int _value() => 1;
}

class B extends A {
  late final x = _value();
}

// In 'p2.dart'.
String _value() => 'two';

// In 'main.dart'.
int useX(B b) => b.x;
```

The name `_value` occurs in `l.dart`, and the declaration in `p2.dart` is
not an overriding declaration. When `p1.dart` is selected, `_value()` in
`B` invokes the inherited method `A._value`, so `B.x` has the inferred type
`int`, and `useX` has no errors. When `p2.dart` is selected, the lexical
lookup of `_value` in the body of `B` finds the top-level function, so
`B.x` has the inferred type `String`, and `useX` has a compile-time error.

The rule has an exception for an overriding private declaration, whose
requirements are needed for the following reasons:

- The declaration _D_ must have the same member signature as the combined
  member signature _s_ in the direct superinterfaces of _D_<sub>t</sub>.
  Assume that `l.dart` declares `class A { num _value() => 1.5; }`,
  `class B extends A {}`, and `final x = B()._value();`, and `p2.dart`
  declares `augment class B { @override int _value() => 1; }`. This
  satisfies the rule about private instance members because `B` inherits
  concrete `A._value` and no top-level `_value` is in scope. However, `x`
  has the inferred type `num` with `p1.dart` and `int` with `p2.dart`, so
  `int useX() => x;` in `main.dart` has a compile-time error with `p1.dart`
  only.

- If _D_<sub>t</sub> inherits an implementation of _n_ then it must have
  the same signature as _D_. Assume that `l.dart` declares
  `class A { num _value() => 1.5; }`,
  `abstract interface class I { int _value(); }`,
  `abstract class B extends A implements I {}`, and
  `class C extends B { @override int _value() => 1; late final x = super._value(); }`,
  and `p2.dart` declares
  `augment abstract class B { @override int _value() => 1; }`. Here
  `B._value` matches the combined member signature `int _value()` of `B`'s
  direct superinterfaces and satisfies the rule about private instance
  members. However, `super._value()` in `C` invokes `A._value` with
  `p1.dart` and `B._value` with `p2.dart`, so `C.x` has the inferred type
  `num` with `p1.dart` and `int` with `p2.dart`, and `int useX(C c) => c.x;`
  in `main.dart` has a compile-time error with `p1.dart` only.

- _D_ must be complete, or completed in _F_ or a file under _F_, so that
  an overriding declaration in a conditional part cannot leave the member
  abstract.

#### Instance members of introductory extensions

> It is a **compile-time error** for an introductory `extension` declaration
> in a conditional part to contain an instance member declaration whose
> name is public, or whose name is private and has the same basename as a
> name occurring in an unconditional file in the file tree of the enclosing
> library.

```dart
// In 'l.dart'.
extension ObjectTag on Object {
  num get tag => 1.5;
}

final taggedValue = 'hello'.tag;

// In 'p2.dart'.
extension _StringTag on String {
  int get tag => 1;
}

// In 'main.dart'.
int useTagged() => taggedValue;
```

When `p1.dart` is selected, `'hello'.tag` invokes `ObjectTag.tag`, so
`taggedValue` has the inferred type `num`, and `useTagged` has a
compile-time error. When `p2.dart` is selected, `_StringTag` is more
specific than `ObjectTag`, `'hello'.tag` invokes `_StringTag.tag`, so
`taggedValue` has the inferred type `int`, and `useTagged` has no errors.
The same issue arises when the unconditional file resolves an extension
implicitly via an object pattern (`switch ('hello') { String(:final tag) =>
tag }`), a function expression invocation (`'hello'()`), an operator
expression (`box + 1`), or a relational pattern, as well as when both
extensions declare a private member `_tag` whose basename occurs in
`l.dart`.

#### Superinterfaces of augmented type declarations

> It is a **compile-time error** for an augmenting type introducing
> declaration in a conditional part that augments an unconditional
> declaration to have an `extends`, `on`, `with`, or `implements` clause.

```dart
// In 'l.dart'.
abstract interface class Printable {}

class Item {}

// In 'p2.dart'.
augment class Item implements Printable {}

// In 'main.dart'.
Printable asPrintable(Item item) => item;
```

`Item` is a subtype of `Printable` only when `p2.dart` is selected. Hence
`asPrintable` has no errors with `p2.dart`, and it has a compile-time error
with `p1.dart`.

#### Direct subtypes of sealed types

> It is a **compile-time error** for a type introducing declaration in a
> conditional part, whether introductory or augmenting, to have a `sealed`
> class or a `sealed` mixin declared in an unconditional file as a direct
> superinterface.

```dart
// In 'l.dart'.
sealed class Response {}

class Ok extends Response {}

// In 'p2.dart'.
class _Pending extends Response {}

// In 'main.dart'.
int statusCode(Response response) => switch (response) {
  Ok() => 200,
};
```

When `p1.dart` is selected, `Ok` is the only direct subtype of `Response`,
and the switch expression is exhaustive. When `p2.dart` is selected,
`_Pending` is another direct subtype of `Response`, and the switch
expression has a compile-time error because it is not exhaustive. Moreover,
`main.dart` cannot denote `_Pending` in a case.

#### Enum entries

> It is a **compile-time error** for an augmenting `enum` declaration in a
> conditional part that augments an unconditional declaration to declare
> any enum entries.

```dart
// In 'l.dart'.
enum Mode { fast }

// In 'p2.dart'.
augment enum Mode { _slow }

// In 'main.dart'.
int speed(Mode mode) => switch (mode) {
  Mode.fast => 100,
};
```

When `p1.dart` is selected, `Mode.fast` is the only value of `Mode`, and
the switch expression is exhaustive. When `p2.dart` is selected, `Mode` has
a second value, and the switch expression has a compile-time error because
it is not exhaustive. The entry has a private name in order to show that
the rule is needed for every entry. A public entry `slow` would in addition
make the expression `Mode.slow` in `main.dart` correct with `p2.dart` only.

#### Public members and constructors

> It is a **compile-time error** for an augmenting type introducing
> declaration _D_ in a conditional part that augments an unconditional
> declaration to contain an introductory member or constructor declaration
> _D_<sub>m</sub> with a public name _n_, which includes a constructor
> whose uniform name is `new`, except for the following case:
>
> _D_<sub>m</sub> is an instance member declaration, and all of the
> following conditions hold:
> - _D_ is an `enum` or `class` declaration which is not a `mixin class`.
> - _n_ is not `==`, `hashCode`, or `noSuchMethod`.
> - _D_ inherits a concrete implementation of _n_ in the unconditional
>   files, and _D_<sub>m</sub> is a complete declaration, or it is
>   completed by an augmenting declaration in the same conditional part
>   file or in the file tree under it. _D_<sub>m</sub> has the same member
>   signature as said inherited implementation, and as the combined member
>   signature of the same name in the direct superinterfaces of _D_.
> - No top-level declaration, import prefix, or imported declaration with
>   the basename of _n_ is in scope at an unconditional declaration of _D_.

```dart
// In 'l.dart'.
class Box {}

// In 'p2.dart'.
augment class Box {
  int unwrap() => 0;
}

// In 'main.dart'.
int useBox() => Box().unwrap();
```

The interface of `Box` has a member named `unwrap` only when `p2.dart` is
selected. Hence `useBox` has no errors with `p2.dart`, and it has a
compile-time error with `p1.dart`. The same holds for a public constructor
such as `Box.named();` in a class that already declares a constructor in
`l.dart`, and an invocation `Box.named()` in `main.dart`.

The rule has an exception for a declaration that overrides an inherited
concrete member of a class or an enum without changing its member
signature. The requirements of the exception are needed for the following
reasons:

- A `mixin` and a `mixin class` are excluded because the implementation
  which is overridden is not known when they are applied as mixins. Assume
  that `l.dart` declares `class A { void foo() {} }` and `mixin M on A {}`,
  and `p2.dart` adds `void foo() {}` to `M`. Moreover, `main.dart` declares
  `abstract class S implements A {}` and `class C extends S with M {}`. In
  this case `C` has no errors with `p2.dart`, and it has a compile-time
  error with `p1.dart` because it does not implement `foo`. Similarly, if
  `l.dart` declares `mixin class M {}`, `p2.dart` adds
  `@override String toString() => 'M';` to `M`, and `main.dart` declares
  `class S { @override String toString({int radix = 10}) => 'S'; }` and
  `class C extends S with M {}`, then `C` has no errors with `p1.dart` and
  has an invalid-override error with `p2.dart`.

- `operator ==`, `hashCode`, and `noSuchMethod` are excluded because a
  declaration that overrides the implementation in `Object` changes
  whether the instances of _D_ have primitive equality, respectively
  whether _D_ has a non-trivial `noSuchMethod`.

- The member signature must be the same as the combined member signature
  in the direct superinterfaces of _D_ so that the interface of _D_ does
  not change, and the same as the signature of the inherited implementation
  because a super-invocation in a subclass of _D_ is checked against the
  declaration that it invokes.

- The last condition is concerned with lexical scopes. Assume that `l.dart`
  imports `dart:math`, a class `S` declares `num max(num a, num b) => a;`,
  and `class D extends S` declares `late final x = max(1, 2);`. An
  inherited member is not in the lexical scope of the body of `D`, so `max`
  denotes the imported function, and `D.x` has the inferred type `int`. If
  `p2.dart` adds an overriding declaration of `max` to `D` then `max`
  denotes that instance member, and `D.x` has the inferred type `num`.
  Hence, `int useX(D d) => d.x;` in `main.dart` has a compile-time error
  with `p2.dart` only.

#### Incomplete introductory instance members

> It is a **compile-time error** for an augmenting declaration in a
> conditional part that augments an unconditional declaration to contain
> an introductory instance member declaration that is not complete after
> all augmentations in the conditional part have been applied.

```dart
// In 'l.dart'.
abstract class Shape {}

class Circle extends Shape {}

// In 'p2.dart'.
augment abstract class Shape {
  void _draw();
}
```

This rule differs from the other rules: It protects the unconditional files
of the same library, and the example is not free of errors without it. If
the rule is removed then `p2.dart` violates no rule about conditional
parts. However, `Circle` is then a concrete class which does not implement
`Shape._draw`. `Circle` is correct according to the unconditional files, so
this is a compile-time error in `l.dart` which only exists when `p2.dart`
is selected. In other words, `l.dart` could not be analyzed without
inspecting its conditional parts. With the rule, the error is reported in
`p2.dart`. A library that imports `l.dart` is not affected: A concrete
subclass of `Shape` in another library is not required to implement a
private member of `l.dart`.

#### Private instance members

> It is a **compile-time error** for an augmenting declaration _D_ in a
> conditional part that augments an unconditional declaration to contain an
> introductory private instance member declaration with name _n_ unless one
> of the following conditions holds:
> - _D_ is not an `extension type` nor a `mixin`, _D_ inherits a concrete
>   implementation of _n_ in the unconditional files, and no top-level
>   declaration or import prefix with the basename of _n_ is in scope at
>   an unconditional declaration of _D_.
> - Neither _D_ nor any subtype of _D_ in the library has a public name or
>   is aliased by a `typedef` with a public name in the library, and no
>   identifier whose basename is the basename of _n_ occurs in an
>   unconditional file.
> - _D_ is not a `mixin` or `mixin class`, no identifier whose basename is
>   the basename of _n_ occurs in an unconditional file, and no augmenting
>   declaration in a conditional part that augments an unconditional
>   declaration of a type other than _D_ contains an introductory instance
>   member declaration with the same basename as _n_.

```dart
// In 'l.dart'.
class Reader {}

class Writer {}

// In 'p2.dart'.
augment class Reader {
  int _position(int offset) => offset;
}

augment class Writer {
  String _position(String label) => label;
}

// In 'main.dart'.
class ReadWriter extends Reader implements Writer {}
```

None of the three conditions holds for `_position`: `Reader` and `Writer`
are public, they do not inherit a member named `_position`, and both of
them receive a member with that name. When `p1.dart` is selected,
`ReadWriter` has no errors. When `p2.dart` is selected, `ReadWriter` has
two superinterfaces that declare `_position` with signatures that have no
combined member signature, which is a compile-time error. `ReadWriter`
cannot resolve the conflict by declaring a member named `_position`
because that name is private to `l.dart`.

The conditions contain further requirements because a single added member
can be sufficient to cause an error in another library:

- An `extension type` cannot rely on the first condition. Assume that
  `l.dart` declares `class A { void _m() {} }` and
  `extension type E(A a) implements A {}`, and `p2.dart` adds
  `void _m() {}` to `E`. In this case
  `extension type F(E e) implements E, A {}` in `main.dart` has a conflict
  between the extension type member `E._m` and the non-extension member
  `A._m`.

- A `mixin` cannot rely on the first or the third condition, and a
  `mixin class` cannot rely on the third condition. Assume that `p2.dart`
  adds `void _m() {}` to a mixin `M` which is declared in `l.dart`. In
  this case `class Base with M {}` followed by
  `class Derived extends Base with M {}` in `main.dart` has a private name
  collision in the mixin application `Base with M`.

- The first condition requires that no top-level declaration or import
  prefix with the same basename is in scope. Assume that `l.dart` declares
  `int _helper() => 1;`, `class S { String _helper() => 's'; }`, and
  `class D extends S { late final x = _helper(); }`. An inherited member is
  not in the lexical scope of the body of `D`, so `_helper()` invokes the
  top-level function, and `D.x` has the inferred type `int`. If `p2.dart`
  adds `String _helper() => 'd';` to `D` then `_helper()` invokes that
  instance method, and `D.x` has the inferred type `String`. Hence,
  `int useX(D d) => d.x;` in `main.dart` has a compile-time error with
  `p2.dart` only.

#### Default values and super-parameters

> It is a **compile-time error** for an augmenting generative constructor
> declaration or member declaration in a conditional part that augments a
> constructor or member declared in an unconditional file to specify a
> default value for an optional formal parameter, or (for the constructor)
> to declare an optional formal parameter as a super-parameter (`super.p`).

```dart
// In 'l.dart'.
class Parent {
  final int? value;
  concrete Parent([int? value]);
}

// In 'p1.dart'.
augment class Parent {
  augment Parent([this.value]);
}

// In 'p2.dart'.
augment class Parent {
  augment Parent([this.value = 0]);
}

// In 'main.dart'.
class Child extends Parent {
  Child([int super.value]);
}
```

The super-parameter `int super.value` in `Child` specifies no default
value, so it obtains the default value of the corresponding parameter of
`Parent`, if that value has the type `int`. When `p2.dart` is selected, the
default value is `0`, and `Child` has no errors. When `p1.dart` is
selected, the default value is `null`, and `Child` has a compile-time error
because an optional parameter of type `int` has no default value.

The same difference arises with a super-parameter. Assume that `Parent`
has a superclass `GrandParent` whose constructor has the parameter list
`([this.value = 0])`, `p1.dart` contains
`augment Parent([int? value]) : super(value);`, and `p2.dart` contains
`augment Parent([super.value]);`. In this case the parameter of `Parent`
has the default value `0` with `p2.dart`, and `null` with `p1.dart`.

For member declarations, default values are disallowed so that
unconditional files can be analyzed without inspecting conditional parts:
if `l.dart` declares a class `Service` with `concrete void run([int
timeout]);`, then allowing `p2.dart` to specify `augment void run([int
timeout = 10]) {}` while `p1.dart` specifies `augment void run([int
timeout]) {}` would make the missing-default-value error on `Service.run`
depend on which part is selected.

#### Completing unconditional instance members and constructors

> It is a **compile-time error** for an augmenting declaration in a
> conditional part that augments an unconditional declaration _D_ to be
> complete *(including a non-`abstract` augmenting variable declaration
> completing an introductory getter or setter)* if:
> - _D_ is an instance member declaration of a `class`, `mixin`,
>   `mixin class`, or `enum` whose introductory declaration does not have
>   the modifier `concrete`, or
> - _D_ is a constructor declaration whose introductory declaration neither
>   has the modifier `concrete` nor is a non-`const` `factory` constructor.

```dart
// In 'l.dart'.
abstract class Middle {
  void action();
}

class Token {
  const Token(int code);
}

// In 'p2.dart'.
augment abstract class Middle {
  augment void action() {}
}

augment class Token {
  augment const Token(int code) : assert(code > 0);
}

// In 'main.dart'.
class Leaf extends Middle {}

const zero = Token(0);
```

When `p1.dart` is selected, `Middle.action` is abstract, so `Leaf` has a
compile-time error because it does not implement `action`. When `p2.dart`
is selected, `Middle.action` is concrete, so `Leaf` inherits an
implementation of `action` and has no errors. Allowing an unmarked
incomplete instance member to be completed in a conditional part would
similarly disrupt super-invocations, mixin applications with
super-invocations, `noSuchMethod` forwarders, `Enum` subtypes inheriting
`index`, private name collisions in mixin applications, and primitive
equality when completing operator `==` or `hashCode`.

For constructors, constant expressions are evaluated during static
analysis. When `p1.dart` is selected, `Token`'s constructor is implicitly
completed and `Token(0)` is a valid constant expression. When `p2.dart` is
selected, evaluating `Token(0)` fails because the assertion fails, causing
a compile-time error in `main.dart`. Similarly, completing an unmarked
non-`const` generative constructor in a conditional part would make field
initialization checks on the unconditional files depend on which
conditional part is selected.

#### Instance variables of mixins and classes with constant constructors

> It is a **compile-time error** for an augmenting declaration of a type _D_
> in a conditional part that augments an unconditional declaration to
> declare a non-`abstract`, non-`external` instance variable if _D_ is a
> `mixin`, a `mixin class`, or declares a `const` generative constructor.

```dart
// In 'l.dart'.
mixin Counter {
  concrete int get count;
}

class Box<T> {
  const Box();
}

// In 'p1.dart'.
augment mixin Counter {
  augment int get count => 0;
}

// In 'p2.dart'.
const dynamic _zero = 0;

augment mixin Counter {
  augment final int count = 0;
}

augment class Box<T> {
  final T _default = _zero;
}

// In 'main.dart'.
class Tally with Counter {
  const Tally();
}

const box = Box<String>();
```

The constructor `const Tally()` invokes a forwarding constructor of the
mixin application `Object with Counter`, and that constructor is constant
only if `Counter` declares no instance variables (the same applies when
applying a `mixin class`). When `p1.dart` is selected, `Counter` declares
no instance variables, and `Tally` has no errors. When `p2.dart` is
selected, `Counter` declares the instance variable `count`, and
`const Tally()` is a compile-time error.

For `Box`, `_default` satisfies the rule about private instance members
because `Box` is not a `mixin` or `mixin class`, `_default` does not occur
in `l.dart`, and no other augmented type declares `_default`. Moreover,
`_zero` is a constant expression of type `dynamic`, so without this rule
`l.dart` has no compile-time errors with either `p1.dart` or `p2.dart`.
When `p1.dart` is selected, `Box<String>()` is a constant expression. When
`p2.dart` is selected, evaluating `Box<String>()` attempts to initialize
`_default` of type `String` with `0`, which fails and causes a compile-time
error in `main.dart`.

#### Super-invocations in mixins

> It is a **compile-time error** for an augmenting `mixin` declaration in a
> conditional part that augments an unconditional declaration to contain a
> super-invocation of a member named _n_, unless a declaration of that
> mixin in an unconditional file contains a super-invocation of a member
> named _n_.

```dart
// In 'l.dart'.
class Resource {
  void close() {}
}

mixin AutoFlush on Resource {
  concrete void flush();
}

// In 'p1.dart'.
augment mixin AutoFlush {
  augment void flush() {}
}

// In 'p2.dart'.
augment mixin AutoFlush {
  augment void flush() {
    super.close();
  }
}

// In 'main.dart'.
abstract class Base implements Resource {}

class Buffer extends Base with AutoFlush {
  @override
  void close() {}
}
```

A mixin application `S with M` is a compile-time error if `M` contains a
super-invocation of a member _m_ and `S` does not have a concrete
implementation of _m_. When `p1.dart` is selected, `AutoFlush` contains no
super-invocations, and `Base with AutoFlush` has no errors. When `p2.dart`
is selected, `AutoFlush` contains a super-invocation of `close`, and
`Base with AutoFlush` is a compile-time error because `Base` has no
concrete implementation of `close`. If the analysis of `main.dart` ignored
`p2.dart` then `Buffer().flush()` would invoke a member that has no
implementation.

#### Suppressing the default constructor

> It is a **compile-time error** for an augmenting declaration _D_ of a
> `class`, `mixin class`, or `enum` in a conditional part that augments an
> unconditional declaration to contain an introductory constructor
> declaration if _D_ does not explicitly declare any constructor in an
> unconditional file.

```dart
// In 'l.dart'.
class Widget {}

// In 'p2.dart'.
augment class Widget {
  Widget._internal();
}

// In 'main.dart'.
Widget makeWidget() => Widget();
```

When `p1.dart` is selected, `Widget` declares no constructors, so it has a
default constructor, and `makeWidget` has no errors. When `p2.dart` is
selected, `Widget` declares a constructor, so it has no default
constructor, and `Widget()` is a compile-time error.

### Changelog

1.2 - November 23, 2026

* Improve on the restrictions on conditional parts.

1.1 - October 30, 2026

* Allow introductory declarations with private names in conditional part files,
  with static constraints ensuring that unconditional files and importing
  libraries remain independent of conditional parts (and disallowing `dynamic`
  access to secret private names of conditional parts).

1.0 - October 29, 2026

* First version of this document.
