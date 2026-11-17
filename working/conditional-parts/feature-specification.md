# Conditional Parts

Author: Erik Ernst

Status: Draft

Version: 1.2

Experiment flag: conditional-parts

This document specifies _conditional parts_, a feature that extends `part`
directives with configurable URIs so that different compilation environments can
select different part files for inclusion in a library, while guaranteeing that
the choice of conditional part file has no effect on the static analysis of the
containing library or of any library that imports it.

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
part file, while static restrictions on conditional part files ensure that
static analysis of the containing library as a whole—and of every library
importing it—is independent of which conditional part file is selected.

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

  // Method with undetermined abstractness: subclasses must
  // implement it, and `super.send...` is a compile-time error.
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
   conditional part. The analyzer can ignore conditional `part` directives
   when summarizing `channel.dart` for client libraries. To preserve this
   property, a conditional part file cannot contain `export` directives,
   constrains the introduction of public top-level or member declarations 
   (introductory declarations must have private names and are subject to
   constraints that prevent unconditional code from depending on them),
   cannot add superinterfaces (`extends`, `on`, `with`, or `implements`) or
   enum entries to augmented declarations, cannot add direct subtypes to
   `sealed` types declared in unconditional files, cannot specify default
   parameter values on augmenting declarations, and cannot complete `const`
   constructors (because static analysis needs to perform constant
   expression evaluation).

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
   complete `Channel.close`.  Similarly, marking an incomplete non-`const`
   generative constructor with `concrete` indicates that its initializer
   list, redirection, and/or body will be supplied by an augmentation
   rather than implicitly defaulting to an empty initializer list and empty
   body.

   *TODO: Can we eliminate abstractness control on constructors entirely?
   A constructor which is introduced in unconditional code may be
   generative with no initializer list and no body. Some instance variables
   may then be left uninitialized according to unconditional code. We can
   make it `concrete` and check that the missing initializer list elements
   are added in an augmentation in the conditional code. Is this enough
   to motivate having `concrete` support for constructors?*

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
`import` and `export` directives: the default `<uri>` is chosen unless one or
more `<configurationUri>` tests evaluate to true in the compilation environment,
in which case the `<uri>` of the first such `<configurationUri>` in source order
is chosen.*

We say that a Dart file *F* _includes_ the part file *P* denoted by the URI *U*
specified by a `<partDirective>` in *F* (resolved relative to the URI of *F*).

- It is a **compile-time error** if a `<configurableUri>` is empty, or it
  has no `<uri>` at the front and none of the `<configurationUri>` clauses
  is selected.

- It is a **compile-time error** if *P* does not parse as a `<partDeclaration>`,
  or if the `<uri>` in the leading `<partHeader>` (`part of <uri>;`) of *P*,
  resolved relative to *U*, does not denote *F*.

- It is a **compile-time error** if a the parent chain from any part file
  contains more than one conditional part directive. *Nested conditional
  parts are not supported.*

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

- It is a **compile-time error** if *D* is an `extension type` and *D* has
  an introductory instance member declaration with the modifier `concrete`.
  *Extension instance members cannot be abstract.*

- If *D* is not an `extension type`, and *D* is declared in a library
  whose unconditional files contain a conditional `part` directive, an
  incomplete instance member of *D* whose introductory declaration does not
  have the modifier `concrete`, and which is not completed by an
  augmentation in the unconditional files of the library, is considered to
  be a member of *D* whose _abstractness is undetermined_. A
  super-invocation which would invoke this member if it were implemented is
  a **compile-time error**. *In particular, we do not ignore it and proceed
  to use a declaration in a further superclass.*
  *In a library that has no conditional `part` directive, no conditional
  part can complete an incomplete instance member. Hence, such a member is
  abstract, and its treatment is unchanged.*

- A generative constructor of *D* whose introductory declaration has the
  modifier `concrete` (and is not completed in the unconditional files of
  the library) is treated during static analysis of the unconditional files
  as a complete generative constructor. It is assumed that it initializes
  every instance variable of the enclosing membered declaration that needs
  to be initialized.

During static analysis of a conditional part _P_, all conditional parts in
the parent chain from _P_ up to the library are considered to be
present. All other conditional parts are treated as if they were not
present.

#### Restrictions on conditional part files

*The intention is that it is a compile-time error for a conditional part file to contain any
directive or declaration that can alter or invalidate the static analysis of the
unconditional files of the containing library, or of any library importing the
containing library.*

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
  - The name _n_ does not occur in an unconditional file in the file tree
    of the enclosing library.
  - The declaration _D_ is an overriding declaration with the same
    member signature as the combined member signature _s_ of the same name
    in the direct superinterfaces of the enclosing type-introducing
    declaration _Dt_. Moreover, if _Dt_ inherits an implementation of _n_
    then it must have the same signature as _D_, and _D_ must be complete,
    or it must be completed by an augmentation in the same conditional
    part file _F_.

- It is a **compile-time error** if an introductory `extension` declaration
  in a conditional part is applicable to an implicit extension member
  access in an unconditional file.
  *This allows unnamed and privately named `extension` declarations in a
  conditional part as long as they do not participate in extension
  resolution in unconditional files. A simpler, less expressive
  alternative is to make every introductory `extension` declaration in a
  conditional part a compile-time error.*

- It is a **compile-time error** for an augmenting type declaration in a
  conditional part that augments an unconditional declaration to have an
  `extends`, `on`, `with`, or `implements` clause.

- It is a **compile-time error** for a type declaration in a conditional
  part, whether introductory or augmenting, to have a `sealed` class or
  `sealed` mixin declared in an unconditional file as a direct
  superinterface.

- It is a **compile-time error** for an augmenting `enum` declaration in a
  conditional part that augments an unconditional declaration to declare
  any enum entries.

- It is a **compile-time error** for an augmenting declaration in a
  conditional part that augments an unconditional declaration `D` to
  contain an introductory member or constructor declaration with a public
  name, which includes a constructor whose uniform name is `new`. However,
  it is not an error for the augmenting declaration to contain an
  introductory instance member declaration with a public name `n` if `D`
  is an `enum`, or a `class` which is not a `mixin class`, and all of the
  following conditions hold:
  - `n` is not `==`, `hashCode`, or `noSuchMethod`.
  - `D` inherits a concrete implementation of `n` in the unconditional
    files, and the declaration is complete.
  - The declaration has the same member signature as that implementation,
    and as the combined member signature of the same name in the direct
    superinterfaces of `D`.
  - No top-level declaration, import prefix, or imported declaration with
    the basename of `n` is in scope at an unconditional declaration of `D`.

  *In other words, a conditional part can override an inherited public
  instance member of a class or an enum when the override changes neither
  the interface of `D` nor the abstractness of the member. The member
  signature includes the modifier `covariant` on each parameter. The last
  condition ensures that an unqualified occurrence of the name in a member
  of an unconditional declaration of `D` denotes the instance member
  whether or not the conditional part is included. The rules about
  instance variables below apply to such a declaration as well.*

- It is a **compile-time error** for an augmenting declaration in a
  conditional part that augments an unconditional declaration to contain
  an introductory instance member declaration that is not complete after
  all augmentations in the conditional part have been applied.
  *Note that for downstream code in other libraries, an unimplemented
  private member in an `abstract` class does not cause a compile-time
  error in concrete subclasses in other libraries, and if a concrete
  subclass is in the same library then standard completeness rules
  already report an error when the conditional part is included. This
  rule is only needed so that concrete subclasses in unconditional files
  of the same library can be analyzed without inspecting conditional
  parts.*

- It is a **compile-time error** for an augmenting declaration of a type `D`
  in a conditional part that augments an unconditional declaration to
  contain an introductory private instance member declaration with name
  `n` *(where a non-final variable with identifier `_v` introduces both a
  getter with name `_v` and a setter with name `_v=`)* unless one of the
  following conditions holds:
  - `D` is not an `extension type` nor a `mixin`, `D` inherits a concrete
    implementation of `n` in the unconditional files, and no top-level
    declaration or import prefix with the basename of `n` is in scope at
    an unconditional declaration of `D`.
    *The last requirement ensures that an unqualified occurrence of the
    name in a member of an unconditional declaration of `D` has the same
    meaning whether or not the conditional part is included.*
  - Neither `D` nor any subtype of `D` in the library has a public name or
    is aliased by a `typedef` with a public name in the library, and `D`
    does not have a member with name `n` in its interface in the
    unconditional files.
  - `D` is not a `mixin` or `mixin class`, the basename of `n` does not
    occur in an unconditional file, and no augmenting declaration in a
    conditional part in the same compilation environment that augments an
    unconditional declaration of a type other than `D` contains an
    introductory instance member declaration with the same basename as
    `n`.
    *In other words, a conditional part can add a private instance member
    with a fresh name to a single type declared in an unconditional file.
    Introductory type declarations in the conditional part can override
    it. Note that if a concrete class in the unconditional files
    implements `D` without inheriting the new member then standard
    completeness rules report an error when the conditional part is
    included.*

- It is a **compile-time error** for a declaration in a conditional part,
  whether introductory or augmenting, to declare a non-`final` instance
  variable or concrete instance getter with a private name `_x`, or for a
  class or enum declaration in a conditional part, whether introductory or
  augmenting, to induce a `noSuchMethod` forwarder for a getter with a
  private name `_x`, if `_x` is promotable in the unconditional files.
  *That is, if a property access to `_x` is subject to promotion when the
  unconditional files are analyzed with every conditional part directive
  ignored. This includes the case where the unconditional files declare
  `_x` as a `late final` instance variable, an `abstract final` instance
  variable, or an abstract getter.*
  For this purpose, an instance getter in an unconditional file whose
  introductory declaration has the modifier `concrete` is a concrete
  getter. *Hence `_x` is not promotable in the unconditional files, and a
  conditional part can complete the getter without restrictions.*

- It is a **compile-time error** for an augmenting generative constructor
  declaration in a conditional part that augments a constructor declared
  in an unconditional file to specify a default value for an optional
  formal parameter, or to declare an optional formal parameter as a
  super-parameter (`super.p`).

- It is a **compile-time error** for an augmenting constructor declaration
  in a conditional part that augments a constructor declared in an
  unconditional file to be `const` and complete.

- It is a **compile-time error** for an augmenting declaration of a type `D`
  in a conditional part that augments an unconditional declaration to
  complete a declaration of `operator ==` or `hashCode` *(including by an
  augmenting instance variable declaration `hashCode`)* unless the
  introductory declaration of that member has the modifier `concrete`.

- It is a **compile-time error** for an augmenting declaration of a `mixin`
  or `mixin class` `D` in a conditional part that augments an unconditional
  declaration to declare a non-`abstract`, non-`external` instance
  variable.

- It is a **compile-time error** for an augmenting `mixin` declaration in a
  conditional part that augments an unconditional declaration to contain a
  super-invocation of a member named `n`, unless a declaration of that
  mixin in an unconditional file contains a super-invocation of a member
  named `n`.
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

- It is a **compile-time error** for an augmenting declaration of a type `D`
  in a conditional part to declare a non-`abstract`, non-`external`
  instance variable when `D` declares a `const` generative constructor,
  unless the variable is an introductory private `final` instance variable,
  has an initializing expression that is a constant expression, and the
  initializing expression evaluates without error as a constant expression
  to a constant value whose type is a subtype of the variable's type.
  *Adding an instance variable with a non-constant
  initializer to a class with a `const` constructor is already a
  compile-time error in the library itself, and adding a `final`
  instance variable with a validated constant initializer whose type and
  expression do not depend on constructor parameters or type parameters
  gives every constant instance of `D` the same field value and cannot
  fail during downstream constant evaluation. However, if constant
  evaluation of `D` in downstream code is performed without inspecting
  conditional parts at all, one can more broadly make it a compile-time
  error for an augmenting declaration of `D` in a conditional part to
  declare any non-`abstract`, non-`external` instance variable when `D`
  declares a `const` generative constructor.*

- It is a **compile-time error** for an augmenting declaration of a `class`
  or `mixin class` `D` in a conditional part to contain an introductory
  constructor declaration if `D` does not explicitly declare any
  constructor in an unconditional file.

Some constraints apply to declarations that depend on an instance member
with indeterminate abstractness. They apply in the library that declares
the member, and in every other library:

*The general principle is that the implementation of a member with
indeterminate abstractness is treated as absent when it is required to be
present, and as present when it is required to be absent. Hence, every
construct which is only correct when the member is abstract, or only
correct when the member is concrete, is a compile-time error. The
constraints below apply this principle.*

- An instance member with indeterminate abstractness in the superclass
  of a class, mixin class, or enum `C` *(including in any mixin applied
  to `C`)* is not considered to be implemented in `C` unless `C`
  declares an implementation. *It is not sufficient that there exists a
  further superclass of said superclass that implements the instance
  member. In other words, an indeterminately abstract member will "kill"
  an inherited implementation, even in the situation where it would be a
  correct override of the member signature of the indeterminately
  abstract member.* If `C` is concrete this may cause the declaration of
  `C` to have a **compile-time error** because it does not fully implement
  its interface.

- It is a **compile-time error** if a super-invocation in a class, mixin, mixin
  class, or enum `C` targets an instance member with indeterminate
  abstractness, or if an instance member with indeterminate abstractness in
  a superclass overrides the concrete member in a further superclass that
  would otherwise be the target of the super-invocation. *In other words,
  an instance member with indeterminate abstractness also "kills" any
  inherited implementation in a further superclass for the purpose of
  resolving super-invocations.*

- In a mixin application `S with M`, where `M` is a `mixin` declaration
  that contains a super-invocation of a member `m`, an instance member `m`
  with indeterminate abstractness in `S` (or in a superclass of `S` and not
  overridden) is not considered to be implemented in `S`, and "kills" any
  implementation of `m` in a further superclass of `S`. Consequently, the
  mixin application `S with M` has a **compile-time error** because `S`
  does not provide a concrete implementation of the super-invoked member
  `m`.

- It is a **compile-time error** if a name `m` is noSuchMethod forwarded in
  a concrete class or enum `C`, and a superclass of `C` *(including any
  mixin applied to `C`)* has an accessible declaration of `m` with
  indeterminate abstractness which is not a correct override of the member
  signature named `m` in the interface of `C`.
  *In other words, the existing error about a noSuchMethod forwarder that
  would override an inherited concrete declaration treats a member with
  indeterminate abstractness as concrete. `C` can avoid the error by
  declaring `m`.*

- It is a **compile-time error** if a mixin application `S with M` occurs
  in a library other than the library that declares `M`, `M` declares an
  instance member with a private name `_n`, and `S` has an instance member
  with the same name whose abstractness is indeterminate *(declared in
  `S`, or declared in a superclass of `S` or in a mixin applied to it, and
  not overridden)*.
  *In this situation it is already an error if `S` has a concrete member
  named `_n`: the analyzer reports a private name collision in a mixin
  application. In other words, that error treats a member with
  indeterminate abstractness as concrete, such that it does not depend on
  whether a conditional part completes the member.*

#### Modular static analysis

Let *L* be a library and let *L*<sub>*u*</sub> be the set of unconditional files
of *L*.

- **Analyzing libraries that import *L***: Because no valid conditional part
  file of *L* can change *L*'s exported namespace, public type hierarchy,
  `sealed` subtype sets, public member signatures, abstract-versus-concrete
  member status, default parameter values, enum entries, or constant
  expressions, a tool analyzing any library *L'* that imports or exports *L* may
  ignore all conditional `part` directives in *L*<sub>*u*</sub>.

- **Analyzing *L*<sub>*u*</sub>**: Because no reference in *L*<sub>*u*</sub> can
  resolve to an introductory private declaration in a conditional part file, and
  no introductory private declaration in a conditional part file can conflict
  with, shadow, or add abstract members or `sealed` subtypes to declarations in
  *L*<sub>*u*</sub>, all identifier resolution, type inference, type checking,
  override checking, super-invocation checking, switch exhaustiveness checking,
  and constant evaluation in *L*<sub>*u*</sub> are completely determined by
  *L*<sub>*u*</sub> alone (ignoring conditional `part` directives). If
  *L*<sub>*u*</sub> contains no conditional `part` directives, completeness of
  all declarations in *L*<sub>*u*</sub> is also checked on *L*<sub>*u*</sub>
  alone.

- **Analyzing and compiling *L* in a compilation environment**: Given a
  compilation environment, each conditional `part` directive specifies a URI,
  determining the complete tree of files of *L*. Static analysis of the selected
  conditional part files checks their directives, introductory private
  declarations, and augmenting declarations against *L*<sub>*u*</sub>, applies
  all augmentations in augmentation application order, and verifies that every
  declaration requiring completion *(top-level, `static`, `extension`,
  non-constant `factory`, `concrete`, and introductory member declarations in
  conditional parts)* is complete.

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

### Use a different word than `concrete`

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

This would imply that every instance member which is made conditional by
having its implementation in a conditional part would have an undetermined
abstractness property, which would in turn make all super-invocations
targeting this declaration a compile-time error.

This would allow us to avoid a certain amount of syntactic complexity. For
example, developers wouldn't have to think about the meaning of this
keyword and they wouldn't have to decide whether or not it should be used
in each case where they are writing an introductory instance member
declaration in a library that has conditional parts.

#### Enforce `concrete` consistently

We could go in the opposite direction and make the use of `concrete`
required with all incomplete declarations. This means that a `concrete`
declaration must be completed in some augmentation, and it might even be a
requirement that the complete augmentation is in a conditional part.

Conversely an introductory declaration which is not complete and does not
include the modifier `concrete` must remain incomplete in all augmenting
declarations, and it is a compile-time error if it is not capable of being
abstract (e.g., if it is a static or top-level declaration).

This would turn completion in augmenting declarations into a tightly
controlled property, which means that there's no ambiguity: Abstract
declarations can be recognized as such, and that's true for concrete
declarations as well.

#### Restrict parts such that a conditional part is always alone

It might simplify things in a useful way if we introduced the restriction
that a conditional part must be the only part in the given library.

There could be a tree of part files under each of the variants, but we
would then constrain them to be reached via a non-conditional part
directive. That is, we might have 5 different parts reached by a
conditional part directive in the library (which would then also be the
_only_ part directive in that library), and each of them could have a tree
of further part files under them, but the whole subtree would always be
enabled at the same time.

The general case (as currently specified) is quite complex: There could be
some conditional part directives and some non-conditional (normal) ones,
and there could be any number of combinations of enablement of the
conditional ones, including the fact that the subtrees of each conditional
part could again be conditional, typcially based on different criteria. It
seems likely that the full generality is difficult to implement and
maintain, and it may not bring much value compared to the simpler
approaches.

#### Should we check completeness only during compilation?

Consider all `concrete` declarations in a non-conditional file of a library
_L_. Consider also all declarations which are incomplete when taking only
the non-conditional part tree into account, and which are incapable of
being abstract (for example, top-level declarations or `static`
declarations).

These declarations would be subject to a completeness check: Each
combination of enablement of specific conditional parts must satisfy the
requirement that every one of these declarations has exactly one complete
augmenting declaration.

We could perform the completeness check only during compilation, or only on
explicit developer request.

The point is that this step needs to consider every possible combination of
inclusion/non-inclusion of the conditional parts of this library, which
could be a large number of cases.

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

The first group of examples is concerned with the rules about the contents
of a conditional part. In each of these examples, `p1.dart` satisfies every
rule, and `p2.dart` violates the rule under consideration and no other
rule. Without that rule, `l.dart` has no compile-time errors with `p1.dart`
and no compile-time errors with `p2.dart`, but the static analysis of
`main.dart` depends on which part is selected. *The rule about incomplete
introductory instance members is an exception, as explained below.*

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
> - The name _n_ does not occur in an unconditional file in the file tree
>   of the enclosing library.
> - The declaration _D_ is an overriding declaration with the same
>   member signature as the combined member signature _s_ of the same name
>   in the direct superinterfaces of the enclosing type-introducing
>   declaration _Dt_. Moreover, if _Dt_ inherits an implementation of _n_
>   then it must have the same signature as _D_, and _D_ must be complete,
>   or it must be completed by an augmentation in the same conditional
>   part file _F_.

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

#### Extensions which are applicable in unconditional files

> It is a **compile-time error** if an introductory `extension` declaration
> in a conditional part is applicable to an implicit extension member
> access in an unconditional file.

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

#### Superinterfaces of augmented type declarations

> It is a **compile-time error** for an augmenting type declaration in a
> conditional part that augments an unconditional declaration to have an
> `extends`, `on`, `with`, or `implements` clause.

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

> It is a **compile-time error** for a type declaration in a conditional
> part, whether introductory or augmenting, to have a `sealed` class or
> `sealed` mixin declared in an unconditional file as a direct
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

> It is a **compile-time error** for an augmenting declaration in a
> conditional part that augments an unconditional declaration `D` to
> contain an introductory member or constructor declaration with a public
> name, which includes a constructor whose uniform name is `new`. However,
> it is not an error for the augmenting declaration to contain an
> introductory instance member declaration with a public name `n` if `D`
> is an `enum`, or a `class` which is not a `mixin class`, and all of the
> following conditions hold:
> - `n` is not `==`, `hashCode`, or `noSuchMethod`.
> - `D` inherits a concrete implementation of `n` in the unconditional
>   files, and the declaration is complete.
> - The declaration has the same member signature as that implementation,
>   and as the combined member signature of the same name in the direct
>   superinterfaces of `D`.
> - No top-level declaration, import prefix, or imported declaration with
>   the basename of `n` is in scope at an unconditional declaration of `D`.

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
such as `Box.named();`, and an invocation `Box.named()` in `main.dart`.

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
  error with `p1.dart` because it does not implement `foo`.

- `operator ==`, `hashCode`, and `noSuchMethod` are excluded because a
  declaration that overrides the implementation in `Object` changes
  whether the instances of `D` have primitive equality, respectively
  whether `D` has a non-trivial `noSuchMethod`.

- The member signature must be the same as the signature of the inherited
  implementation because a super-invocation in a subclass of `D` is
  checked against the declaration that it invokes.

- The last condition is concerned with lexical scopes. Assume that `l.dart`
  imports `dart:math`, a class `S` declares `num max(num a, num b) => a;`,
  and `class D extends S` declares `late final x = max(1, 2);`. An
  inherited member is not in the lexical scope of the body of `D`, so `max`
  denotes the imported function, and `D.x` has the inferred type `int`. If
  `p2.dart` adds an overriding declaration of `max` to `D` then `max`
  denotes that instance member, and `D.x` has the inferred type `num`.

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

> It is a **compile-time error** for an augmenting declaration of a type `D`
> in a conditional part that augments an unconditional declaration to
> contain an introductory private instance member declaration with name
> `n` *(where a non-final variable with identifier `_v` introduces both a
> getter with name `_v` and a setter with name `_v=`)* unless one of the
> following conditions holds:
> - `D` is not an `extension type` nor a `mixin`, `D` inherits a concrete
>   implementation of `n` in the unconditional files, and no top-level
>   declaration or import prefix with the basename of `n` is in scope at
>   an unconditional declaration of `D`.
> - Neither `D` nor any subtype of `D` in the library has a public name or
>   is aliased by a `typedef` with a public name in the library, and `D`
>   does not have a member with name `n` in its interface in the
>   unconditional files.
> - `D` is not a `mixin` or `mixin class`, the basename of `n` does not
>   occur in an unconditional file, and no augmenting declaration in a
>   conditional part in the same compilation environment that augments an
>   unconditional declaration of a type other than `D` contains an
>   introductory instance member declaration with the same basename as
>   `n`.

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

#### Promotion of private instance variables

> It is a **compile-time error** for a declaration in a conditional part,
> whether introductory or augmenting, to declare a non-`final` instance
> variable or concrete instance getter with a private name `_x`, or for a
> class or enum declaration in a conditional part, whether introductory or
> augmenting, to induce a `noSuchMethod` forwarder for a getter with a
> private name `_x`, if `_x` is promotable in the unconditional files.
> For this purpose, an instance getter in an unconditional file whose
> introductory declaration has the modifier `concrete` is a concrete
> getter.

```dart
// In 'l.dart'.
class A {
  final int? _value;
  A(this._value);
}

A makeA();

final valueOrZero = (A a) => a._value != null ? a._value : 0;

// In 'p1.dart'.
augment A makeA() => A(1);

// In 'p2.dart'.
class _B extends A {
  bool _toggle = false;

  _B() : super(null);

  @override
  int? get _value => (_toggle = !_toggle) ? 1 : null;
}

augment A makeA() => _B();

// In 'main.dart'.
int value = valueOrZero(makeA());
```

`_value` is promotable in the unconditional files. When `p1.dart` is
selected, the second occurrence of `a._value` is promoted to `int`, so
`valueOrZero` has the inferred type `int Function(A)`, and `main.dart` has
no errors. When `p2.dart` is selected, the concrete getter `_B._value`
prevents promotion of `_value` in the entire library, so `valueOrZero` has
the inferred type `int? Function(A)`, and `main.dart` has a compile-time
error. If the analysis of `l.dart` ignored `p2.dart` and promoted
`a._value` then the program would be unsound: `valueOrZero(makeA())` reads
`_value` twice, obtains `1` and then `null`, and returns `null` with the
static type `int`.

#### Default values and super-parameters of constructors

> It is a **compile-time error** for an augmenting generative constructor
> declaration in a conditional part that augments a constructor declared
> in an unconditional file to specify a default value for an optional
> formal parameter, or to declare an optional formal parameter as a
> super-parameter (`super.p`).

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

#### Constant constructors

> It is a **compile-time error** for an augmenting constructor declaration
> in a conditional part that augments a constructor declared in an
> unconditional file to be `const` and complete.

```dart
// In 'l.dart'.
class Token {
  const Token(int code);
}

// In 'p2.dart'.
augment class Token {
  augment const Token(int code) : assert(code > 0);
}

// In 'main.dart'.
const zero = Token(0);
```

Constant expressions are evaluated during static analysis. When `p1.dart`
is selected, the constructor of `Token` is implicitly completed, and
`Token(0)` is a constant expression. When `p2.dart` is selected, the
evaluation of `Token(0)` fails because the assertion fails, which is a
compile-time error in `main.dart`.

#### Completing `operator ==` and `hashCode`

> It is a **compile-time error** for an augmenting declaration of a type `D`
> in a conditional part that augments an unconditional declaration to
> complete a declaration of `operator ==` or `hashCode` *(including by an
> augmenting instance variable declaration `hashCode`)* unless the
> introductory declaration of that member has the modifier `concrete`.

```dart
// In 'l.dart'.
class Key {
  const Key();
  bool operator ==(Object other);
}

// In 'p2.dart'.
augment class Key {
  augment bool operator ==(Object other) => other is Key;
}

// In 'main.dart'.
const keys = {Key()};
```

When `p1.dart` is selected, `Key` inherits `operator ==` from `Object`, so
`Key` has primitive equality, and `keys` has no errors. When `p2.dart` is
selected, `Key` overrides `operator ==`, so it does not have primitive
equality, and `keys` has a compile-time error because an element of a
constant set must have primitive equality. If the declaration in `l.dart`
has the modifier `concrete` then it is known from the unconditional files
that `Key` does not have primitive equality.

#### Instance variables of mixins

> It is a **compile-time error** for an augmenting declaration of a `mixin`
> or `mixin class` `D` in a conditional part that augments an unconditional
> declaration to declare a non-`abstract`, non-`external` instance
> variable.

```dart
// In 'l.dart'.
mixin Counter {
  int get count;
}

// In 'p2.dart'.
augment mixin Counter {
  augment final int count = 0;
}

// In 'main.dart'.
class Tally with Counter {
  const Tally();

  @override
  int get count => 0;
}
```

The constructor `const Tally()` invokes a forwarding constructor of the
mixin application `Object with Counter`, and that constructor is constant
only if `Counter` declares no instance variables. When `p1.dart` is
selected, `Counter` declares no instance variables, and `Tally` has no
errors. When `p2.dart` is selected, `Counter` declares the instance
variable `count`, and `const Tally()` is a compile-time error.

#### Super-invocations in mixins

> It is a **compile-time error** for an augmenting `mixin` declaration in a
> conditional part that augments an unconditional declaration to contain a
> super-invocation of a member named `n`, unless a declaration of that
> mixin in an unconditional file contains a super-invocation of a member
> named `n`.

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
super-invocation of a member `m` and `S` does not have a concrete
implementation of `m`. When `p1.dart` is selected, `AutoFlush` contains no
super-invocations, and `Base with AutoFlush` has no errors. When `p2.dart`
is selected, `AutoFlush` contains a super-invocation of `close`, and
`Base with AutoFlush` is a compile-time error because `Base` has no
concrete implementation of `close`. If the analysis of `main.dart` ignored
`p2.dart` then `Buffer().flush()` would invoke a member that has no
implementation.

#### Instance variables of classes with constant constructors

> It is a **compile-time error** for an augmenting declaration of a type `D`
> in a conditional part to declare a non-`abstract`, non-`external`
> instance variable when `D` declares a `const` generative constructor,
> unless the variable is an introductory private `final` instance variable,
> has an initializing expression that is a constant expression, and the
> initializing expression evaluates without error as a constant expression
> to a constant value whose type is a subtype of the variable's type.

```dart
// In 'l.dart'.
class Base<T> {
  const Base();
  T? get _default => null;
}

class Box<T> extends Base<T> {
  const Box();
}

// In 'p2.dart'.
const Object _zero = 0;

augment class Box<T> {
  @override
  final T? _default = _zero as T?;
}

// In 'main.dart'.
const box = Box<String>();
```

`Box._default` satisfies the rule about private instance members because
`Box` inherits a concrete implementation of `_default`. However, its
initializing expression is not a constant expression because it references
the type parameter `T`. When
`p1.dart` is selected, `Box<String>()` is a constant expression. When
`p2.dart` is selected, the evaluation of `Box<String>()` evaluates
`_zero as String?`, which fails, and this is a compile-time error in
`main.dart`. In contrast, `Box<int>()` has no errors with either part.

#### Suppressing the default constructor

> It is a **compile-time error** for an augmenting declaration of a `class`
> or `mixin class` `D` in a conditional part to contain an introductory
> constructor declaration if `D` does not explicitly declare any
> constructor in an unconditional file.

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

#### Constraints on members with indeterminate abstractness

The remaining error specifications are concerned with declarations that
depend on a member with indeterminate abstractness. In each of the
following examples, both parts satisfy every rule, and `p2.dart` completes
a member which `p1.dart` leaves abstract. The constraint under
consideration makes a declaration in `main.dart` an error no matter which
part is selected. Without the constraint, that declaration has an error
with one of the parts, and no errors with the other part.

#### Implementing a member with indeterminate abstractness

> An instance member with indeterminate abstractness in the superclass
> of a class, mixin class, or enum `C` *(including in any mixin applied
> to `C`)* is not considered to be implemented in `C` unless `C`
> declares an implementation. If `C` is concrete this may cause the
> declaration of `C` to have a **compile-time error** because it does not
> fully implement its interface.

```dart
// In 'l.dart'.
abstract class Middle {
  void action();
}

mixin Indexed {
  int get index;
}

// In 'p2.dart'.
augment abstract class Middle {
  augment void action() {}
}

augment mixin Indexed {
  augment int get index => 0;
}

// In 'main.dart'.
class Leaf extends Middle {}

enum Color with Indexed { red }
```

Without this constraint, `Leaf` has a compile-time error when `p1.dart` is
selected because it has no implementation of `action`, and it has no errors
when `p2.dart` is selected because it inherits `Middle.action`.

`Color` shows why an implementation in a further superclass is not
sufficient. Without this constraint, `Color` has no errors when `p1.dart`
is selected because it inherits an implementation of `index` from the
superclass of every enum. When `p2.dart` is selected, `Color` has a
compile-time error because an enum cannot inherit a concrete member named
`index` from a mixin.

With this constraint, `Leaf` and `Color` have a compile-time error with
either part because they do not declare an implementation of `action`
respectively `index`.

#### Super-invocations of a member with indeterminate abstractness

> It is a **compile-time error** if a super-invocation in a class, mixin,
> mixin class, or enum `C` targets an instance member with indeterminate
> abstractness, or if an instance member with indeterminate abstractness in
> a superclass overrides the concrete member in a further superclass that
> would otherwise be the target of the super-invocation.

```dart
// In 'l.dart'.
class Base {
  num value() => 1.5;
}

abstract class Middle extends Base {
  @override
  int value();
}

// In 'p2.dart'.
augment abstract class Middle {
  augment int value() => 1;
}

// In 'main.dart'.
class Leaf extends Middle {
  @override
  int value() => super.value();
}
```

The lookup of the member which is invoked by a super-invocation ignores
abstract declarations. Without this constraint, `super.value()` invokes
`Base.value` when `p1.dart` is selected. Its return type is `num`, so
`Leaf.value` has a compile-time error. When `p2.dart` is selected,
`super.value()` invokes `Middle.value`. Its return type is `int`, so
`Leaf.value` has no errors. With this constraint, `super.value()` is a
compile-time error with either part.

#### Mixin applications and members with indeterminate abstractness

> In a mixin application `S with M`, where `M` is a `mixin` declaration
> that contains a super-invocation of a member `m`, an instance member `m`
> with indeterminate abstractness in `S` (or in a superclass of `S` and not
> overridden) is not considered to be implemented in `S`, and "kills" any
> implementation of `m` in a further superclass of `S`. Consequently, the
> mixin application `S with M` has a **compile-time error** because `S`
> does not provide a concrete implementation of the super-invoked member
> `m`.

```dart
// In 'l.dart'.
class Recorder {
  void record(String event) {}
}

abstract class RemoteRecorder implements Recorder {
  @override
  void record(String event);
}

// In 'p2.dart'.
augment abstract class RemoteRecorder {
  augment void record(String event) {}
}

// In 'main.dart'.
mixin Timestamps on Recorder {
  @override
  void record(String event) {
    super.record('${DateTime.now()}: $event');
  }
}

abstract class TimestampedRecorder extends RemoteRecorder with Timestamps {}
```

`Timestamps` contains a super-invocation of `record`, so the superclass in
an application of `Timestamps` must have a concrete implementation of
`record`. Without this constraint, `RemoteRecorder with Timestamps` has a
compile-time error when `p1.dart` is selected because
`RemoteRecorder.record` is abstract, and it has no errors when `p2.dart` is
selected. With this constraint, the mixin application is a compile-time
error with either part.

#### `noSuchMethod` forwarders and members with indeterminate abstractness

> It is a **compile-time error** if a name `m` is noSuchMethod forwarded in
> a concrete class or enum `C`, and a superclass of `C` *(including any
> mixin applied to `C`)* has an accessible declaration of `m` with
> indeterminate abstractness which is not a correct override of the member
> signature named `m` in the interface of `C`.

```dart
// In 'l.dart'.
abstract class A {
  void m(int i);
}

// In 'p2.dart'.
augment abstract class A {
  augment void m(int i) {}
}

// In 'main.dart'.
abstract class B {
  void m([int i]);
}

class C extends A implements B {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
```

The interface of `C` has the member signature `void m([int i])`. Without
this constraint, `C` has no errors when `p1.dart` is selected: It has no
concrete member named `m`, so a `noSuchMethod` forwarder is induced. When
`p2.dart` is selected, `C` inherits the concrete method `A.m`, which is
not a correct override of `void m([int i])`. This is a compile-time error
because an implicitly induced `noSuchMethod` forwarder cannot override a
declared method. With this constraint, `C` has a compile-time error with
either part, and it can avoid the error by declaring `m`.

#### Private name collisions and members with indeterminate abstractness

> It is a **compile-time error** if a mixin application `S with M` occurs
> in a library other than the library that declares `M`, `M` declares an
> instance member with a private name `_n`, and `S` has an instance member
> with the same name whose abstractness is indeterminate *(declared in
> `S`, or declared in a superclass of `S` or in a mixin applied to it, and
> not overridden)*.

```dart
// In 'l.dart'.
mixin Disposable {
  void _release();
}

// In 'p2.dart'.
augment mixin Disposable {
  augment void _release() {}
}

// In 'main.dart'.
class Base with Disposable {}

class Derived extends Base with Disposable {}
```

The analyzer reports a private name collision for a mixin application
`S with M` in a library other than the one that declares `M`, when `M`
declares a private instance member and `S` has a concrete member with the
same name. Without this constraint, `Base with Disposable` in the
declaration of `Derived` has no errors when `p1.dart` is selected because
`Base` has no concrete member named `_release`. When `p2.dart` is selected,
`Base` has the concrete member `_release`, and the mixin application has a
private name collision. With this constraint, the mixin application is a
compile-time error with either part.

### Changelog

1.2 - November 16, 2026

* Improve on the restrictions on conditional parts.

1.1 - October 30, 2026

* Allow introductory declarations with private names in conditional part files,
  with static constraints ensuring that unconditional files and importing
  libraries remain independent of conditional parts (and disallowing `dynamic`
  access to secret private names of conditional parts).

1.0 - October 29, 2026

* First version of this document.
