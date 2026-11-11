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
  // Platform-specific private helper function local to "channel_io.dart".
}

augment class Channel {
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

augment class Channel {
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

augment class Channel {
  augment void close() => _unsupported('Channel.close');
}

augment Channel _openChannel(String name) => _unsupported('Channel.open');
```

Notice two central properties illustrated by this example:

1. **Configuration-independent static analysis**: Code generation must read
   the conditional part selected by the compilation environment in order to
   know which code to emit, but static analysis of `channel.dart` (and of
   any library that imports `channel.dart`) does not depend on any
   conditional part. The analyzer can ignore conditional `part` directives
   when summarizing `channel.dart` for client libraries. To preserve this
   property, a conditional part file cannot contain `export` directives,
   cannot introduce public top-level or member declarations (introductory
   declarations must have private names and are subject to constraints that
   prevent unconditional code from depending on them), cannot add
   superinterfaces (`extends`, `with`, or `implements`) or enum entries to
   augmented declarations, cannot add direct subtypes to `sealed` types
   declared in unconditional files, cannot specify default parameter values
   on augmenting declarations, and cannot complete `const` constructors
   (because static analysis needs to perform constant expression
   evaluation).

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

- It is a **compile-time error** if *P* does not parse as a `<partDeclaration>`,
  or if the `<uri>` in the leading `<partHeader>` (`part of <uri>;`) of *P*,
  resolved relative to *U*, does not denote *F*.

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

- If *D* is an `extension type`, an instance member declaration of *D*
  whose introductory declaration has the modifier `concrete` (or which is
  completed by an augmentation in the unconditional files of the library)
  is considered to be a concrete extension instance member declaration of
  *D*.

- If *D* is not an `extension type`, an incomplete instance member of *D*
  whose introductory declaration does not have the modifier `concrete`, and
  which is not completed by an augmentation in the unconditional files of
  the library, is considered to be a member of *D* whose _abstractness is
  undetermined_. A super-invocation which would invoke this member if it
  were implemented is a **compile-time error**. *In particular, we do not
  ignore it and proceed to use a declaration in a further superclass.*

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

- It is a **compile-time error** for a conditional part to contain an
  `export` directive.

- It is a **compile-time error** for a conditional part to contain an
  introductory top-level declaration with a public name.

- It is a **compile-time error** if an introductory `extension` declaration
  in a conditional part is applicable to an implicit extension member
  access in an unconditional file, or is referenced by an explicit
  extension member application in an unconditional file.
  *This allows unnamed and privately named `extension` declarations in a
  conditional part as long as they do not participate in extension
  resolution in unconditional files. A simpler, less expressive
  alternative is to make every introductory `extension` declaration in a
  conditional part a compile-time error.*

- It is a **compile-time error** for an augmenting type declaration in a
  conditional part that augments a declaration in an unconditional file
  to have an `extends`, `with`, or `implements` clause.

- It is a **compile-time error** for a type declaration in a conditional
  part, whether introductory or augmenting, to have a `sealed` class or
  `sealed` mixin declared in an unconditional file as a direct
  superinterface.

- It is a **compile-time error** for an augmenting `enum` declaration in a
  conditional part that augments an `enum` declaration in an unconditional
  file to declare any enum entries.

- It is a **compile-time error** for an augmenting declaration in a
  conditional part that augments a declaration in an unconditional file
  to contain an introductory member or constructor declaration with a
  public name *(including an constructor whose uniform name is `new`)*.

- It is a **compile-time error** for an augmenting declaration in a
  conditional part that augments a declaration in an unconditional file
  to contain an introductory instance member declaration that is not
  complete after all augmentations in the conditional part have been
  applied.
  *Note that for downstream code in other libraries, an unimplemented
  private member in an `abstract` class does not cause a compile-time
  error in concrete subclasses in other libraries, and if a concrete
  subclass is in the same library then standard completeness rules
  already report an error when the conditional part is included. This
  rule is only needed so that concrete subclasses in unconditional files
  of the same library can be analyzed without inspecting conditional
  parts.*

- It is a **compile-time error** for an augmenting declaration of a type `D`
  in a conditional part to contain an introductory private instance
  member declaration `m` with name `n` *(where a non-final variable with
  identifier `_v` introduces both a getter with name `_v` and a setter
  with name `_v=`)* if `D` is an `extension type` declared in an
  unconditional file, if `D` can be extended, implemented, or mixed in
  by declarations in other libraries, or if `D` has a member with name
  `n` in its interface in the unconditional files, unless `D` is not an
  `extension type`, `D` has a member with name `n` in its interface in
  the unconditional files, `D` inherits a concrete implementation of `n`
  in the unconditional files whose member signature is a valid override
  of the member signature of `n` in `D` in the unconditional files, and
  `m` is a complete declaration whose member signature is identical to
  the member signature of `n` in `D` in the unconditional files,
  including identical `covariant` parameter modifiers.

- It is a **compile-time error** for an augmenting declaration of a type `D`
  in a conditional part to contain an introductory private instance
  member declaration with name `n` *(with base name `b`, where `b` is `n`
  without a trailing `=` if `n` is a setter name)* if `D` does not have a
  member with name `n` in its interface in the unconditional files, and a
  subtype of `D` in an unconditional file declares a member with name `b`
  or `b=` that omits its return type, its variable type, or any formal
  parameter type.

- It is a **compile-time error** if an identifier reference, type
  annotation, constructor reference or invocation, super-constructor
  invocation, redirecting constructor invocation, initializing formal
  parameter, or statically resolved member access, method invocation,
  setter assignment, tear-off, or object pattern field access in an
  unconditional file resolves to an introductory declaration in a
  conditional part.

- It is a **compile-time error** for an augmenting generative constructor
  declaration in a conditional part that augments a constructor declared
  in an unconditional file to specify a default value for an optional
  formal parameter.

- It is a **compile-time error** for an augmenting constructor declaration
  in a conditional part that augments a constructor declared in an
  unconditional file to be `const` and complete.

- It is a **compile-time error** for an augmenting declaration of a type `D`
  in a conditional part to declare a non-`abstract`, non-`external`
  instance variable when `D` declares a `const` generative constructor,
  unless the variable has an initializing expression that is a constant
  expression and does not reference any constructor parameter or type
  parameter of `D`.
  *Adding an instance variable with a non-constant
  initializer to a class with a `const` constructor is already a
  compile-time error in the library itself, and adding a `final`
  instance variable with a constant initializer that does not depend on
  constructor parameters or type parameters gives every constant
  instance of `D` the same field value and cannot fail during
  downstream constant evaluation. However, if constant evaluation of `D`
  in downstream code is performed without inspecting conditional parts
  at all, one can more broadly make it a compile-time error for an
  augmenting declaration of `D` in a conditional part to declare any
  non-`abstract`, non-`external` instance variable when `D` declares a
  `const` generative constructor.*

- It is a **compile-time error** for an augmenting declaration of a `class`
  or `mixin class` `D` in a conditional part to contain an introductory
  constructor declaration if `D` does not explicitly declare any
  constructor in an unconditional file.

Some constraints apply for the unconditional files:

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
  that contains a super-invocation of a member `m`, an instance member
  `m` with indeterminate abstractness in `S` *(or in a superclass of
  `S`)* is not considered to be implemented in `S`, and "kills" any
  implementation of `m` in a further superclass of `S`. Consequently,
  the mixin application `S with M` has a **compile-time error** because `S`
  does not provide a concrete implementation of the super-invoked member
  `m`.

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

#### Platform-specific helper declarations and private state

Allowing introductory declarations with private names in conditional part files
makes it straightforward to write self-contained platform implementations
without auxiliary helper libraries, while the accompanying constraints preserve
configuration-independent static analysis:

- **Helper functions, classes, and extensions**: A conditional part file *P* can
  declare private top-level helper functions (`void _flushStdout()`), private
  implementation classes (`class _IoChannel extends Channel`), private
  extensions (`extension _IoStringExt on String`), and private top-level
  variables directly inside *P*, in addition to importing platform-specific
  helper libraries when desired. Because no reference in the unconditional files
  can resolve to these declarations, and private types in *P* cannot directly
  subtype `sealed` types from the unconditional files, the static analysis of
  the unconditional files (and of any importing library) is unaffected by their
  presence.

- **Platform-specific instance state and private members**: An augmenting type
  declaration in *P* can introduce private helper methods, private instance
  variables, and privately named constructors (provided that any new instance
  variable is initialized or compatible with constructors completed in the
  unconditional files, and does not add storage to a class with a `const`
  constructor). Furthermore, prohibiting `dynamic` member accesses and tear-offs
  in *L* using secret private names of *P* ensures that unconditional code
  cannot depend on those conditional private declarations even at run time.

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

## Appendix: Justification of compile-time error rules

A central design goal of conditional parts is that the choice of conditional
part file has no effect on the static analysis of the unconditional files of a
library *L* or of any library *L*<sub>0</sub> that imports *L*. Informally, a
conditional part has no effect on the "type of the library" *L*.

This appendix illustrates why each compile-time error rule motivated by this
property is needed. Throughout the examples below, we consider four files:

- Library *L*<sub>0</sub> in `'l0.dart'`, which imports `'l.dart'`.
- Library *L* in `'l.dart'`, which conditionally includes either `'p1.dart'` or
  `'p2.dart'` based on the `-DuseP2=true` compilation environment variable.
- Conditional part *P*<sub>1</sub> in `'p1.dart'`, selected by default when
  `useP2` is not `'true'`.
- Conditional part *P*<sub>2</sub> in `'p2.dart'`, selected when compiled with
  `-DuseP2=true`.

```dart
// Library file "l0.dart".
import 'l.dart';
// Declarations for each rule are shown below.
```

```dart
// Library file "l.dart".
part 'p1.dart'
    if (useP2 == 'true') 'p2.dart';
// Declarations for each rule are shown below.
```

```dart
// Part file "p1.dart".
part of 'l.dart';
// Declarations for each rule are shown below.
```

```dart
// Part file "p2.dart".
part of 'l.dart';
// Declarations for each rule are shown below.
```

For each rule, we show what happens in *L*<sub>0</sub> and *L* when that rule is
violated, demonstrating that the static analysis of *L*<sub>0</sub> or *L* would
differ depending on whether *P*<sub>1</sub> or *P*<sub>2</sub> is selected.

### Rules on the `concrete` modifier and incomplete members

#### Disallowing `concrete` on augmenting declarations

An augmenting declaration cannot have the modifier `concrete`. Only an
introductory declaration can be marked `concrete`.

```dart
// In "l.dart":
abstract class ServiceA1 {
  void run();
}

// In "p1.dart":
augment abstract class ServiceA1 {
  // Compile-time error: `concrete` on an augmenting declaration.
  augment concrete void run() {}
}

// In "p2.dart":
augment abstract class ServiceA1 {}

// In "l0.dart":
class MyServiceA1 extends ServiceA1 {
  void execute() {
    super.run();
  }
}
```

If `p1.dart` were allowed to add `concrete` to `ServiceA1.run`, then selecting
*P*<sub>1</sub> would make `ServiceA1.run` concrete: `MyServiceA1` in
*L*<sub>0</sub> would inherit a concrete implementation of `run` and
`super.run()` would be valid. Selecting *P*<sub>2</sub> with `-DuseP2=true`
would leave `ServiceA1.run` abstract, causing two compile-time errors in
*L*<sub>0</sub>: `MyServiceA1` would lack a concrete implementation of `run`,
and `super.run()` would target an abstract method.

#### Requiring `concrete` declarations to be completed

A declaration with the modifier `concrete` must be completed by an augmenting
declaration, and is not implicitly completed if it is a generative constructor.
Similarly, `concrete` is disallowed on already-complete declarations and on
constructors of a `mixin class` or `enum`, which cannot be completed in a
conditional part.

```dart
// In "l.dart":
class WorkerA2 {
  final int id;
  concrete WorkerA2();
  concrete int work();
}

// In "p1.dart":
augment class WorkerA2 {
  augment WorkerA2() : id = 0;
  augment int work() => 42;
}

// In "p2.dart":
// Compile-time error: `WorkerA2.new` and `WorkerA2.work` are
// marked `concrete` in "l.dart", but are not completed when
// "p2.dart" is selected.
augment class WorkerA2 {}

// In "l0.dart":
class SubWorkerA2 extends WorkerA2 {
  @override
  int work() => super.work() + 1;
}
```

Static analysis of *L* and *L*<sub>0</sub> relies on the `concrete` modifier in
`l.dart` to treat `WorkerA2.new` as initializing `id` and `WorkerA2.work` as
implemented. When *P*<sub>1</sub> is selected, both promises are fulfilled. When
*P*<sub>2</sub> is selected, if failing to complete a `concrete` declaration
were not an error, `WorkerA2.new` would fail to initialize the `final` variable
`id` in *L*, `WorkerA2` in *L* would be a concrete class with an unimplemented
method `work`, and `super.work()` in *L*<sub>0</sub> would target an abstract
member.

#### Undetermined abstractness of unmarked incomplete members

An incomplete instance member in *L* without the modifier `concrete` that is not
completed in the unconditional files of *L* has undetermined abstractness: it
does not satisfy concrete implementation checks, and a super-invocation in a
subclass that would target it if it were implemented is a compile-time error,
even if a superclass further up the hierarchy declares a concrete implementation.

```dart
// In "l.dart":
class BaseA3 {
  void action([int x = 0]) {}
}

abstract class MiddleA3 extends BaseA3 {
  void action();
}

// In "p1.dart":
augment abstract class MiddleA3 {
  augment void action() {}
}

// In "p2.dart":
augment abstract class MiddleA3 {}

// In "l0.dart":
class ConcreteLeafA3 extends MiddleA3 {} // Compile-time error: missing `action`.

class SuperCallLeafA3 extends MiddleA3 {
  @override
  void action([int x = 0]) {
    // Compile-time error: `MiddleA3.action` has undetermined abstractness.
    super.action(x);
  }
}
```

Here, both `p1.dart` and `p2.dart` are valid conditional parts: because
`MiddleA3` is `abstract` and `MiddleA3.action` is not marked `concrete`,
*P*<sub>1</sub> is permitted to complete `MiddleA3.action` while *P*<sub>2</sub>
is permitted to leave it abstract.

- If `ConcreteLeafA3` in *L*<sub>0</sub> were not required to implement
  `action`, it would be valid when *P*<sub>1</sub> is selected and a
  compile-time error when *P*<sub>2</sub> is selected.
- If `super.action(x)` in `SuperCallLeafA3` in *L*<sub>0</sub> ignored the
  incomplete `MiddleA3.action` declaration and resolved to `BaseA3.action`, then
  when *P*<sub>2</sub> is selected (`-DuseP2=true`), `MiddleA3.action` is
  indeed abstract and `super.action(x)` would validly invoke
  `BaseA3.action([int x = 0])` with one argument. When *P*<sub>1</sub> is
  selected, however, `MiddleA3.action()` is concrete and accepts zero arguments,
  so `super.action(x)` in *L*<sub>0</sub> would resolve to `MiddleA3.action()`
  and fail with a compile-time error because too many positional arguments are
  supplied.

### Restrictions on conditional part files

#### Rule 1: No `export` directives

A conditional part file cannot contain a `<libraryExport>` directive.

```dart
// Library file "extra.dart":
int extraValue = 42;

// In "p1.dart":
export 'extra.dart'; // Compile-time error under Rule 1.

// In "p2.dart":
// No export directive.

// In "l0.dart":
int useExtra() => extraValue;
```

If `p1.dart` were allowed to export `'extra.dart'`, then `extraValue` would be
in the exported namespace of *L* when *P*<sub>1</sub> is selected, making
`useExtra` in *L*<sub>0</sub> valid. When *P*<sub>2</sub> is selected with
`-DuseP2=true`, `extraValue` is not exported by *L*, making `extraValue` in
*L*<sub>0</sub> an unresolved identifier compile-time error.

#### Rule 2: Private names required for introductory top-level declarations

Every introductory top-level declaration in a conditional part file must have a
private name. Moreover, introductory unnamed `extension` declarations are
disallowed.

```dart
// In "p1.dart":
int publicHelper() => 1; // Compile-time error under Rule 2.

extension on String { // Compile-time error under Rule 2.
  int get customLength => length;
}

// In "p2.dart":
// Neither declaration is present.

// In "l0.dart":
int usePublicDeclarations() => publicHelper() + 'abc'.customLength;
```

If `p1.dart` were allowed to declare `publicHelper` or the unnamed `extension`,
both would be exported by *L* when *P*<sub>1</sub> is selected, so
`usePublicDeclarations` in *L*<sub>0</sub> (and any call in *L*) would be valid.
When *P*<sub>2</sub> is selected with `-DuseP2=true`, neither declaration exists,
so both `publicHelper()` and `'abc'.customLength` in *L*<sub>0</sub> fail with
compile-time errors.

#### Rule 3: No added superinterfaces on augmented types

An augmenting type declaration in a conditional part file cannot contain an
`extends`, `with`, or `implements` clause.

```dart
// In "l.dart":
abstract interface class Printable {}
class Item {}

// In "p1.dart":
augment class Item implements Printable {} // Compile-time error under Rule 3.

// In "p2.dart":
augment class Item {}

// In "l0.dart":
Printable asPrintable(Item item) => item;
```

When *P*<sub>1</sub> is selected, `Item` is a subtype of `Printable`, so
`asPrintable` in *L*<sub>0</sub> is well-typed. When *P*<sub>2</sub> is selected
with `-DuseP2=true`, `Item` is not a subtype of `Printable`, so returning `item`
from `asPrintable` in *L*<sub>0</sub> is a compile-time type error.

#### Rule 4: No direct subtyping of `sealed` types from unconditional files

An introductory type declaration in a conditional part file cannot have a
`sealed` class or `sealed` mixin from the unconditional files of *L* as a direct
superinterface.

```dart
// In "l.dart":
sealed class Response {}
class Ok extends Response {}

// In "p1.dart":
class _SecretError extends Response {} // Compile-time error under Rule 4.

// In "p2.dart":
// No subtype of Response.

// In "l0.dart":
int statusCode(Response r) => switch (r) {
  Ok() => 200,
};
```

Even though `_SecretError` has a private name (satisfying Rule 2), it is a
direct subtype of the `sealed` class `Response`. When *P*<sub>2</sub> is
selected with `-DuseP2=true`, `Ok` is the only direct subtype of `Response`, so
the `switch` expression in `statusCode` in *L*<sub>0</sub> (and in *L*) is
exhaustive. When *P*<sub>1</sub> is selected, `Response` has an additional
direct subtype `_SecretError`, causing the `switch` expression in
*L*<sub>0</sub> and *L* to fail exhaustiveness checking with a compile-time
error.

#### Rule 5: No added enum entries on augmented enums

An augmenting `enum` declaration in a conditional part file cannot declare enum
entries.

```dart
// In "l.dart":
enum Mode { fast }

// In "p1.dart":
augment enum Mode { slow } // Compile-time error under Rule 5.

// In "p2.dart":
augment enum Mode {}

// In "l0.dart":
int speed(Mode m) => switch (m) {
  Mode.fast => 100,
};
```

When *P*<sub>2</sub> is selected with `-DuseP2=true`, `Mode.fast` is the sole
value of `Mode`, and `speed` in *L*<sub>0</sub> is exhaustive. When
*P*<sub>1</sub> is selected, `Mode` has a second value `Mode.slow`, making the
`switch` expression in *L*<sub>0</sub> a non-exhaustive switch compile-time
error (and conversely, an expression `Mode.slow` in *L*<sub>0</sub> would be
valid under *P*<sub>1</sub> and a compile-time error under *P*<sub>2</sub>).

#### Rule 6: Private names and completeness required for introductory members in augmenting declarations

Inside an augmenting declaration of *D* in a conditional part file, every
introductory member or constructor must have a private name and must be complete
after applying all augmentations in the conditional part's enclosing conditional
subtree.

```dart
// In "l.dart":
class Box6 {
  Box6.create();
}

// In "p1.dart":
augment class Box6 {
  Box6(); // Compile-time error under Rule 6: public constructor.
  int unwrap() => 0; // Compile-time error under Rule 6: public method.
  void _missingHook(); // Compile-time error under Rule 6: incomplete member.
}

// In "p2.dart":
augment class Box6 {}

// In "l0.dart":
int useBox6() => Box6().unwrap();
class SubBox6 extends Box6 {
  SubBox6() : super.create();
}
```

- **Public name (`Box6()` and `unwrap`)**: In *L*<sub>0</sub>, `useBox6` is
  valid when *P*<sub>1</sub> is selected, and a compile-time error when
  *P*<sub>2</sub> is selected with `-DuseP2=true` because neither the unnamed
  constructor nor `unwrap` exists on `Box6`.
- **Completeness (`_missingHook`)**: When *P*<sub>2</sub> is selected, `Box6` in
  *L* and `SubBox6` in *L*<sub>0</sub> are valid concrete classes. When
  *P*<sub>1</sub> is selected, `_missingHook` is an unimplemented abstract
  private method of `Box6`, causing both `Box6` in *L* and `SubBox6` in
  *L*<sub>0</sub> to fail concrete-class implementation checking with a
  compile-time error.

#### Rule 7: No name or hierarchy conflicts with unconditional declarations

An introductory top-level declaration in a conditional part file cannot have the
same basename as any top-level declaration or import prefix in the unconditional
files of *L*; and an introductory member or constructor in an augmenting
declaration of *D* cannot have the same basename as any member or constructor in
*D* or in any superinterface, superclass, or subtype of *D* in the unconditional
files of *L*.

```dart
// In "l.dart":
int _topHelper() => 1;

class Super7 {
  num _calc() => 1;
}

class Mid7 extends Super7 {}

class Sub7 extends Mid7 {
  String _leafMethod() => 'ok';
  int testCalc() => super._calc();
  late final x = super._calc();
}

final sub7X = Sub7().x;

// In "p1.dart":
int _topHelper() => 2; // Compile-time error under Rule 7: top-level conflict.

augment class Mid7 {
  // Compile-time error under Rule 7: conflicts with `Super7._calc`.
  int _calc() => 2;
  // Compile-time error under Rule 7: conflicts with `Sub7._leafMethod`.
  int _leafMethod(int a) => a;
}

// In "p2.dart":
augment class Mid7 {}

// In "l0.dart":
int useSub7X() => sub7X;
```

- **Top-level conflict (`_topHelper`)**: *L* has a duplicate declaration
  compile-time error when *P*<sub>1</sub> is selected, and no error when
  *P*<sub>2</sub> is selected.
- **Superclass conflict (`_calc`)**: In `Sub7` in *L*, `super._calc()` resolves
  to `Mid7._calc` with return type `int` when *P*<sub>1</sub> is selected, and
  to `Super7._calc` with return type `num` when *P*<sub>2</sub> is selected.
  Consequently, when *P*<sub>1</sub> is selected, `testCalc` in *L* is valid and
  `sub7X` has inferred type `int`, making `useSub7X` in *L*<sub>0</sub> valid;
  when *P*<sub>2</sub> is selected, both `testCalc` in *L* and `useSub7X` in
  *L*<sub>0</sub> fail with compile-time type errors.
- **Subtype conflict (`_leafMethod`)**: When *P*<sub>2</sub> is selected,
  `Sub7._leafMethod` in *L* is valid. When *P*<sub>1</sub> is selected,
  `Sub7._leafMethod()` is an invalid override of `Mid7._leafMethod(int a)` in
  *L*, causing a compile-time error in *L*.

#### Rule 8: No static resolution from unconditional files to introductory declarations in a conditional part

Unconditional files of *L* cannot statically resolve any identifier, type,
constructor, member access, or object pattern field to an introductory
declaration in a conditional part.

```dart
// Library file "imported_by_l.dart":
num _compute() => 1.5;

extension ImportedExt on Object {
  num get tag => 1.5;
}

// In "l.dart":
import 'imported_by_l.dart';

class Holder8 {}

final computedValue = _compute();
final taggedValue = 'hello'.tag;
int readSecret(Holder8 h) => h._secret; // Compile-time error under Rule 8.

// In "p1.dart":
int _compute() => 1;

extension _P1Ext on String {
  int get tag => 1;
}

augment class Holder8 {
  int get _secret => 42;
}

// In "p2.dart":
augment class Holder8 {}

// In "l0.dart":
int useComputed() => computedValue;
int useTagged() => taggedValue;
```

If unconditional files could resolve to introductory declarations in `p1.dart`:

- **Shadowing imported declarations (`_compute`)**: When *P*<sub>1</sub> is
  selected, `int _compute()` in `p1.dart` would shadow `num _compute()` imported
  from `'imported_by_l.dart'`. The top-level variable `computedValue` in *L*
  would have inferred type `int`, making `useComputed` in *L*<sub>0</sub> valid.
  When *P*<sub>2</sub> is selected with `-DuseP2=true`, `_compute()` in *L*
  resolves to `'imported_by_l.dart'`, giving `computedValue` inferred type `num`
  and causing a compile-time type error in `useComputed` in *L*<sub>0</sub>.
- **Implicit extension resolution (`_P1Ext`)**: When *P*<sub>1</sub> is
  selected, `_P1Ext` on `String` is more specific than `ImportedExt` on `Object`,
  so `'hello'.tag` in *L* would resolve to `_P1Ext.tag` with return type `int`,
  giving `taggedValue` inferred type `int` and making `useTagged` in
  *L*<sub>0</sub> valid. When *P*<sub>2</sub> is selected, `'hello'.tag`
  resolves to `ImportedExt.tag` with return type `num`, causing a compile-time
  type error in `useTagged` in *L*<sub>0</sub>.
- **Direct member resolution (`h._secret`)**: `readSecret` in *L* would resolve
  to `Holder8._secret` and succeed when *P*<sub>1</sub> is selected, and fail
  with an unresolved getter compile-time error in *L* when *P*<sub>2</sub> is
  selected.

#### Rule 9: No `dynamic` access to secret private names of a conditional part

It is a compile-time error if a conditional part has a secret private name `_n`
and *L* contains a member access, method invocation, setter assignment,
tear-off, or object pattern field access with basename `_n` on a receiver of
static type `dynamic`.

```dart
// In "l.dart":
class Box9 {}
dynamic invokeSecret(dynamic d) => d._secret9();

// In "p1.dart":
augment class Box9 {
  // Compile-time error under Rule 9: `_secret9` is a secret private name of
  // "p1.dart", and "l.dart" accesses `_secret9` on a `dynamic` receiver.
  int _secret9() => 1;
}

// In "p2.dart":
augment class Box9 {}
```

Although `d._secret9()` has static type `dynamic` under both *P*<sub>1</sub> and
*P*<sub>2</sub>, Rule 9 prevents unconditional code in *L* from using `dynamic`
to circumvent Rule 8 and depend on secret private declarations introduced in
*P*<sub>1</sub> that do not exist when *P*<sub>2</sub> is selected.

#### Rule 10: No default parameter values on augmenting declarations

An augmenting function, method, or constructor declaration in a conditional part
cannot specify a default value for an optional parameter.

```dart
// In "l.dart":
class Parent10 {
  final int? value;
  Parent10([this.value]);
}

// In "p1.dart":
augment class Parent10 {
  // Compile-time error under Rule 10: specifies a default parameter value.
  augment Parent10([this.value = 0]);
}

// In "p2.dart":
augment class Parent10 {
  augment Parent10([this.value]);
}

// In "l0.dart":
class Child10 extends Parent10 {
  Child10([int super.value]);
}
```

In `Child10` in *L*<sub>0</sub>, the optional super-parameter `int super.value`
has a potentially non-nullable type `int` and no explicit default value. By the
super-parameter rules, it copies the default value of the associated superclass
constructor parameter `Parent10.value` if that default value's type is a subtype
of `int`.

- When *P*<sub>1</sub> is selected, `Parent10.value` has default value `0` of
  type `int`, so `super.value` in `Child10` inherits the default value `0` and
  *L*<sub>0</sub> has no compile-time errors.
- When *P*<sub>2</sub> is selected with `-DuseP2=true`, `Parent10.value` has
  default value `null` of type `Null`, which is not a subtype of `int`. As a
  result, `super.value` in `Child10` has no default value and a non-nullable
  type, causing a compile-time error in *L*<sub>0</sub>.

#### Rule 11: No completing constant constructors

An augmenting constructor declaration in a conditional part cannot be both
`const` and complete.

```dart
// In "l.dart":
class Token11 {
  final int code;
  const Token11(int x);
}

// In "p1.dart":
augment class Token11 {
  // Compile-time error under Rule 11.
  augment const Token11(int x) : code = x;
}

// In "p2.dart":
augment class Token11 {
  // Compile-time error under Rule 11.
  augment const Token11(int x) : code = 0;
}

// In "l0.dart":
const tokenSet = {Token11(1), Token11(2)};
```

Constant expression evaluation is performed during static analysis. When
*P*<sub>1</sub> is selected, `Token11(1)` and `Token11(2)` have distinct `code`
values `1` and `2`, so `tokenSet` in *L*<sub>0</sub> is valid. When
*P*<sub>2</sub> is selected with `-DuseP2=true`, both `Token11(1)` and
`Token11(2)` evaluate to canonicalized `Token11` instances with `code == 0`,
making `tokenSet` in *L*<sub>0</sub> a compile-time error due to equal elements
in a constant set literal.

#### Rule 12: Restrictions on instance variables and constructors in augmenting declarations

Rule 12 restricts augmenting declarations in a conditional part from introducing
instance variables or constructors that would invalidate constant constructors,
completed generative constructors, implicit default constructors, `mixin class`
constraints, primary constructor constraints, or mutable field checks in *L* and
*L*<sub>0</sub>:

```dart
// In "l.dart":
class ConstItem12 {
  final int id;
  const ConstItem12(this.id);
}

class Ready12 {
  Ready12();
}

class ImplicitCtor12 {}

mixin class Mixable12 {
  Mixable12();
}

class Primary12(final int x);

class Mutable12 {
  int count = 0;
  Mutable12();
}

// In "p1.dart":
int _counter12 = 0;

augment class ConstItem12 {
  // Compile-time error under Rule 12: adds a field to a class with a const
  // constructor.
  final int _tag = _counter12++;
}

augment class Ready12 {
  // Compile-time error under Rule 12: uninitialized non-nullable field when
  // `Ready12.new` is already complete in "l.dart".
  int _uninitialized;
}

augment class ImplicitCtor12 {
  // Compile-time error under Rule 12: suppresses the implicit default
  // constructor of `ImplicitCtor12`.
  ImplicitCtor12._();
}

augment mixin class Mixable12 {
  // Compile-time error under Rule 12: generative constructor in a mixin class.
  Mixable12._(int x);
}

augment class Primary12 {
  // Compile-time error under Rule 12: non-redirecting generative constructor
  // in a class with a primary constructor.
  Primary12._() : x = 0;
}

augment class Mutable12 {
  // Compile-time error under Rule 12: `const` constructor in a class with a
  // non-final field.
  const Mutable12._();
}

// In "p2.dart":
augment class ConstItem12 {}
augment class Ready12 {}
augment class ImplicitCtor12 {}
augment mixin class Mixable12 {}
augment class Primary12 {}
augment class Mutable12 {}

// In "l0.dart":
const item12 = ConstItem12(1);
ImplicitCtor12 makeImplicit12() => ImplicitCtor12();
class MixedIn12 with Mixable12 {}
```

When *P*<sub>2</sub> is selected with `-DuseP2=true`, every declaration in *L*
and *L*<sub>0</sub> is valid. When *P*<sub>1</sub> is selected, if Rule 12 did
not reject `p1.dart`:

- `ConstItem12._tag` has a non-constant initializer `_counter12++`, invalidating
  `const ConstItem12(this.id)` in *L* and `const item12 = ConstItem12(1)` in
  *L*<sub>0</sub>.
- `Ready12._uninitialized` is not initialized by `Ready12()` in *L*, causing a
  compile-time error on `Ready12()` in *L*.
- `ImplicitCtor12._()` suppresses the implicit default constructor
  `ImplicitCtor12()`, causing `makeImplicit12` in *L*<sub>0</sub> to fail with a
  compile-time error.
- `Mixable12._(int x)` violates the requirement that a `mixin class` cannot
  declare non-trivial generative constructors, invalidating `Mixable12` in *L*
  and `MixedIn12` in *L*<sub>0</sub>.
- `Primary12._() : x = 0` violates the requirement that every generative
  constructor in a class with a primary constructor must redirect to the primary
  constructor, causing a compile-time error in *L*.
- `const Mutable12._()` conflicts with the non-`final` instance variable
  `int count = 0` in `Mutable12`, causing a compile-time error in *L*.

#### Rule 13: No invalidation of library-wide checks

All standard augmentation and declaration rules apply when a conditional part is
applied to the unconditional files of *L*.

```dart
// In "l.dart":
int compute13(int x);

class Cycle13 {
  Cycle13.a() : this.b();
  Cycle13.b();
}

// In "p1.dart":
// Compile-time error under Rule 13: return type `num` does not match `int`.
augment num compute13(int x) => x;

augment class Cycle13 {
  // Compile-time error under Rule 13: creates a redirection cycle with
  // `Cycle13.a`.
  augment Cycle13.b() : this.a();
}

// In "p2.dart":
augment int compute13(int x) => x + 1;

augment class Cycle13 {
  augment Cycle13.b();
}
```

When *P*<sub>2</sub> is selected with `-DuseP2=true`, `compute13` is completed
with a matching signature and `Cycle13.b` is completed without redirecting to
`Cycle13.a`, so *L* has no compile-time errors. When *P*<sub>1</sub> is
selected, *L* fails signature matching on `compute13` and constructor
redirection cycle checking on `Cycle13`.

### Changelog

1.2 - November 4, 2026

* Add an appendix with examples justifying the compile-time error rules that
  ensure conditional parts do not affect the static analysis of the library or
  its importers.

1.1 - October 30, 2026

* Allow introductory declarations with private names in conditional part files,
  with static constraints ensuring that unconditional files and importing
  libraries remain independent of conditional parts (and disallowing `dynamic`
  access to secret private names of conditional parts).

1.0 - October 29, 2026

* First version of this document.
