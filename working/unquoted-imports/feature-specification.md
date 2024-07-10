# Unquoted imports

Author: Bob Nystrom

Status: In-progress

Version 0.3 (see [CHANGELOG](#CHANGELOG) at end)

Experiment flag: unquoted-imports

## Introduction

When one Dart library wants to use code from another library, there are
basically three places it can find that library and correspondingly three ways
to refer to it:

*   **SDK:** For libraries built directly into the host Dart SDK, you import
    them like:

    ```dart
    import 'dart:async';
    ```

*   **Package:** If you want to refer to a library in a
    package other than your own, you need to identify the package and the path
    to the library within that package's `lib/` directory, like:

    ```dart
    import 'package:flutter/material.dart';
    ```

    You can also use this to import packages in your own library if you like.

*   **Relative:** Within the `lib/` directory of the same package, you can refer
    to another library using relative paths like:

    ```dart
    import 'sibling.dart';
    import '../parent.dart';
    import 'subdirectory/offspring.dart';
    ```

(Note, throughout this proposal, we'll refer to "imports" but everything applies
equally well to exports.)

Package imports are the most common:

```
-- Scheme (352988 total) --
 233805 ( 66.236%): package   ==================================
  93583 ( 26.512%): relative  ==============
  25596 (  7.251%): dart      ====
      4 (  0.001%): file      =
```

It's unfortunate that the syntax used by 2/3rds of the imports in Dart is so
verbose. It's particularly unfortunate when you compare Dart to the rest of the
world. Here's how you idiomatically import `SomeUsefulThing` in various
languages:

```
import 'package:some_useful_thing/some_useful_thing.dart';  // Dart now
import SomeUsefulThing                                      // Swift
import org.cool.SomeUsefulThing                             // Kotlin
import org.cool.SomeUsefulThing;                            // Java
using CoolOrg.SomeUsefulThing;                              // C#
import { SomeUsefulThing } from "./SomeUsefulThing";        // TS/JS
import some_useful_thing                                    # Python
require 'some_useful_thing'                                 # Ruby
```

Our current syntax is really verbose, even worse than JavaScript, which is
saying something. We are the only language that requires a file extension in
every import (!). We're the only one with essentially two keywords (`import` and
`package`) that you have to write when importing from a package. Most don't
require quotation characters. In the common case of a package's name being the
same as its main library, you have to say the same name twice.

This proposal addresses that. It provides a shorter syntax for SDK and package
imports. With this proposal, you write:

```dart
import some_useful_thing;
```

Here are a range of representative imports and how they look before and after
this proposal:

```dart
// Before:
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:flutter/material.dart';
import 'package:analyzer/dart/ast/visitor/visitor.dart';
import 'package:widget.tla.server/server.dart';
import 'package:widget.tla.proto/client/component.dart';

// After:
import dart/isolate;
import flutter_test;
import path;
import flutter/material;
import analyzer/dart/ast/visitor/visitor;
import widget.tla.server;
import widget.tla.proto/client/component;
```

You can probably infer what's going on from the before and after, but the basic
idea is that the library is a slash-separated series of dotted identifier
segments. The first segment is the name of the package. The rest is the path to
the library within that package. A `.dart` extension is implicitly added to the
end. If there is only a single segment, it is treated as the package name and
its last dotted component is the path. If the package name is `dart`, it's a
"dart:" library import.

The way I think about the proposed syntax is that relative imports are
*physical* in that they specify the actual relative path on the file system from
the current library to another library *file*. Because those are physical file
paths, they use string literals and file extensions as they do today. SDK and
package imports are *logical* in that you don't know where the library your
importing lives on your disk. What you know is it's *logical name* and the
relative location of the library you want inside that package. Since these are
abstract references to a *library*, they are unquoted and omit the file
extension.

This proposal is similar to and inspired by Lasse's [earlier proposal][lasse],
along with the many comments and ideas on the [corresponding issue][649]. This
proposal is essentially a fleshed out version of [this comment][bob comment].

[lasse]: https://github.com/dart-lang/language/blob/main/working/0649%20-%20Import%20shorthand/proposal.md
[649]: https://github.com/dart-lang/language/issues/649
[bob comment]: https://github.com/dart-lang/language/issues/1941#issuecomment-973421638

### Is this worth improving?

One argument against better import syntax is that it adds complexity for
marginal benefit. It's not like you can express anything with this proposal
that you couldn't already express.

Still, I believe it's worth it. We have *never* liked the current package
import syntax. When it was first designed, it was intended to be a temporary
placeholder until better syntax came along. It just took a long time.

More to the point, user sentiment does affect their productivity and enjoyment
working with the language. One of the *first* things a Dart user does when
writing code is import other libraries to build on. If that initial experience
feels annoying or antiquated, it taints their impression of the language. The
current import syntax is a bouquet of dead flowers in the language's foyer.

We can easily improve it and should. The other languages users compare us to all
do this better. There's no compelling reason for us to have *clearly worse*
syntax for such a common operation.

### Design choices

Part of the reason we've never shipped a better syntax is because of
disagreement on minor points of syntax for the proposed improvement. Here are
the reasons for the choices this proposal makes:

### Path separator

An import shorthand syntax that only supported a single identifier would work
for packages like `test` and `args` that only expose a single library, but
would fail for even very common libraries like `package:flutter/material.dart`.
So we need some notion of a package name and a path within the that package.

Many languages use `.` as the path separator for a module path. It looks
familiar and clean. However, `.` is actually a valid character in directory and
library names. It's not that uncommon to see libraries with names like
`foo.widget.dart` or `some_model.pb.dart`. We can remove the `.dart` part, but
that still means we need to be able to understand that `foo.widget` and
`some_model.pb` are library names and not paths like `foo/widget.dart` and
`some_model/pb.dart`.

In fact, inside Google's monorepo, dotted package names are idiomatic and
universally used. If our import shorthand syntax couldn't hangle package names
with dots in them, no one inside Google would be able to use it.

Instead of `.`, this proposal uses `/`. This is obviously a natural path
separator since it's the main path separator character used in most operating
systems and in URLs on the web. Also, it is already the path separator character
used inside Dart imports today.

In fact, every "package:" import today *literally contains the proposed syntax
inside its import string:*

```dart
import 'package:flutter/material.dart';
import          flutter/material      ;

import 'package:analyzer/dart/ast/visitor/visitor.dart';
import          analyzer/dart/ast/visitor/visitor      ;

import 'package:widget.tla.proto/client/component.dart';
import          widget.tla.proto/client/component      ;
```

This strongly suggests users will have no trouble reading the syntax.

There are no technical problems with using `/` as the separator. It's already an
operator character in Dart. It does mean that `//` would be parsed as a comment
and not two path separators, but there's no point in having two adjacent path
separators anyway.

### Lexical analysis

In a programming language implementation, the first phase of compiling a file is
taking the series of individual characters in the source and grouping them into
a series of *tokens* or *lexemes* which are like the words and punctuation in
the language. For example, `123`, `class`, `"a string"`, and `someIdentifier`
are each individual tokens in Dart.

Given an import like:

```dart
import flutter/material;
```

Is the `flutter/material` part a single token or three (`flutter`, `/`, and
`material`)? The main advantage of tokenizing it as a single monolithic token is
that we could potentially allow characters or identifiers in there aren't
otherwise valid Dart. For example, we could let you use reserved words as path
segments:

```dart
import weird_package/for/if/ok;
```

The disadvantage is that the tokenizer doesn't generally have enough context to
know when it should tokenize `foo/bar` as a single import path token versus
three tokens that are presumably dividing two variables named `foo` and `bar`.

Unlike Lasse's [earlier proposal][lasse], this proposal does *not* tokenize an
import path as a single token. Instead, it's tokenized using Dart's current
lexical grammar.

This means you can't have a path segment that's a reserved word or is otherwise
not a valid Dart identifier. Fortunately, our published guidance has *always*
told users that [package names][name guideline] and [directories][directory
guideline] should be valid Dart identifiers. Pub will complain if you try to
publish a package whose name isn't a valid identifier. Likewise, the linter will
flag directory or library names that aren't identifiers.

[name guideline]: https://dart.dev/tools/pub/pubspec#name
[directory guideline]: https://dart.dev/effective-dart/style#do-name-packages-and-file-system-entities-using-lowercase-with-underscores

This guidance appears to have been successful. Looking at all of the directives
in a large corpus of pub packages and open source widgets:

```
-- Segment (663424 total) --
 656881 ( 99.014%): identifier                   ===============================
   2820 (  0.425%): built-in identifier          =
   2596 (  0.391%): dotted identifiers           =
    610 (  0.092%): reserved word                =
    448 (  0.068%): Non-identifier               =
     69 (  0.010%): dotted with non-identifiers  =
```

This splits every "package:" import's path into segments separated by `/`. Then
for each segment, it reports whether the segment is a valid identifier, a
built-in identifier like `dynamic` or `covariant`, etc. Almost all segments are
either valid identifiers, or dotted identifiers where each subcomponent is a
valid identifier.

(For the very small number that aren't, they can continue to use the old quoted
"package:" import syntax to import the library.)

I think this approach is much simpler than trying to add special lexing rules.
It's consistent with how Java, C# and other languages parse their imports. It
does mean users can do silly things like:

```dart
import strange /* comment */    .   but
    /  // line comment

    another  /


      fine;
```

But they can also choose to *not* do that.

## Syntax

The normative stuff starts now. Here is the proposal:

We add a new rule and hang it off the existing `uri` rule already used by import
and export directives:

```
uri                   ::= stringLiteral | packagePath
packagePath           ::= packagePathSegment ( '/' packagePathSegment )*
packagePathSegment    ::= dottedIdentifierList
dottedIdentifierList  ::= identifier ('.' identifier)*
```

An import or export can continue to use a `stringLiteral` for the quoted form
(which is what they will do for relative imports). But they can also use a
`packagePath`, which is a slash-separated series of segments, each of which is a
series of dot-separated identifiers. *(The `dottedIdentifierList` rule is
already in the grammar and is shown here for clarity.)*

### Part directive lookahead

*There are two directives for working with part files, `part` and `part of`. The
`of` identifier is not a reserved word in Dart. This means that when the parser
sees `part of`, it doesn't immediately know if it is looking at a `part`
directive followed by an unquoted identifier like `part of;` or `part
of.some/other.thing;` versus a `part of` directive like `part of thing;` or
`part of 'uri.dart';` It must lookahead past the `of` identifier to see if the
next token is `;`, `.`, `/`, or another identifier.*

*This may add some complexity to parsing, but should be minor. Dart's grammar
has other places that require much more (sometimes unbounded) lookahead.*

## Static semantics

The semantics of the new syntax are defined by taking the `packagePath` and
converting it to a string. The directive then behaves as if the user had written
a string literal containing that string. The process is:

1.  Let the *segment* for a `packagePathSegment` be a string defined by the
    ordered concatenation of the `identifier` and `.` terminals in the
    `packagePathSegment`, with all whitespace and comments removed. *So if
    `packagePathSegment` is `a  . b /* comment */ .  c`, then its *segment* is
    "a.b.c".*

2.  Let *segments* be an ordered list of the segments of each
    `packagePathSegment` in `packagePath`. *In other words, this and the
    preceding step take the `packagePath` and convert it to a list of segment
    strings while discarding whitespace and comments. So if `packagePathSegment`
    is `a . b /* comment */  /  c / d  . e`, then *segments* is ["a.b", "c",
    "d.e"].*

3.  If the first segment in *segments* is "dart":

    1.  It is a compile error if there are no subsequent segments. *There's no
        "dart:dart" or "package:dart/dart.dart" library. We reserve the right
        to use `import dart;` in the future to mean something useful.*

    2.  Let *path* be the concatenation of the remaining segments, separated
        by `/`. *In practice, since there are no directories for "dart:"
        libraries, there will always be a single remaining segment in valid
        imports. But a custom Dart embedder or future version of Dart could in
        theory introduce directories for SDK libraries.*

    3.  The URI is "dart:*path*". *So `import dart/async;` desugars to
        `import "dart:async";`.*

4.  Else if there is only a single segment:

    1.  Let *name* be the segment.

    2.  Let *path* be the last identifier in the segment. *If the segment is
        only a single identifier, this is the entire segment. Otherwise, it's
        the last identifier after the last `.`. So in `foo`, *path* is `foo`.
        In `foo.bar.baz`, it's `baz`.*

    3.  The URI is "package:*name*/*path*.dart". *So `import test;` desugars to
        `import "package:test/test.dart";`, and `import server.api;` desugars
        to `import "package:server.api/api.dart";`.*

5.  Else:

    1.  Let *path* be the concatenation of the segments, separated by `/`.

    3.  The URI is "package:*path*.dart". *So `import a/b/c/d;` desugars to
        `import "package:a/b/c/d.dart";`.

Once the `packagePath` has been converted to a string, the directive behaves
exactly as if the user had written a `stringLiteral` containing that same
string.

Given the list of segments, here is a complete implementation of the desugaring
logic in Dart:

```dart
String desugar(List<String> segments) => switch (segments) {
  ['dart']              => 'ERROR. Not allowed to import just "dart"',
  ['dart', ...var rest] => 'dart:${rest.join('/')}',
  [var name]            => 'package:$name/${name.split('.').last}.dart',
  _                     => 'package:${segments.join('/')}.dart',
};
```

## Runtime semantics

There are no runtime semantics for this feature.

## Compatibility

This feature is fully backwards compatible for `import`, `export`, and `part`
directives.

For all directives, we still allow quoted "dart:" and "package:" imports. Users
may be compelled to use the existing syntax in uncommon corner cases where the
library they are importing has a package, directory, or library name that isn't
a valid Dart identifier.

In practice, almost all "dart" and "package" URIs should be (automatically)
migrated to the new style and the old quoted forms will be essentially vestigial
syntax (similar to names after `library` directives). A future version of Dart
may make a breaking change and remove support for the old syntax.

### Part-of directives

The `part of` directive allows a library name after `of` instead of a string
literal. With this proposal, that syntax is now ambiguous. Is it interpreted
as a library name, or as an unquoted URI that should be desugared to a URI?
In other words, given:

```dart
part of foo.bar;
```

Is the file saying it's a part of the library containing `library foo.bar;` or
that it's part of the library found at URI `package:foo/bar.dart`?

Library names in `part of` directives have been deprecated for many years
because the syntax doesn't work well with many tools. How is a given tool
supposed to know where to find the library that happens to contain a `library`
directive with that name? The quoted URI syntax was added later specifically to
address that point and users are encouraged by documentation and lints to use
the quoted syntax.

Looking at a corpus of 122,420 files:

```
-- Directive (443733 total) --
 352744 ( 79.495%): import   =========================================
  55471 ( 12.501%): export   =======
  17823 (  4.017%): part     ===
  17695 (  3.988%): part of  ===
```

So `part of` directives are fairly rare to begin with. Of them, most use the
recommended URI syntax and would not be affected by this change:

```
-- Part of (17695 total) --
  13229 ( 74.761%): uri           ===================================
   4466 ( 25.239%): library name  ============
```

In total, only about 1% of directives are `part of` with a library name:

```
-- URI (443733 total) --
 352744 ( 79.495%): import                     ===========================
  55471 ( 12.501%): export                     =====
  17823 (  4.017%): part                       ==
  13229 (  2.981%): part of with uri           =
   4466 (  1.006%): part of with library name  =
```

Given that, I propose that we make a **breaking change** and remove support for
the long-deprecated library name syntax from `part of` directives. An unquoted
series of identifiers after `part of` then gets unambiguously interpreted as
this proposal's semantics. In other words, `part of foo.bar;` is part of the
library at `package:foo/bar.dart`, not part of the library with name `foo.bar`.

Users affected by the breakage can and should update their `part of` directive
to point to the URI of the library that the file is a part, using either the
quoted or unquoted syntax.

### Language versioning

To avoid breaking existing `part of` directives, this change is language
versioned. Only libraries whose language version is at or above the version that
this proposal ships in can use this new unquoted syntax in `part of` or any
other directive.

## Tooling

The best language features are designed holistically with the entire user
experience in mind, including tooling and diagnostics. This section is *not
normative*, but is merely suggestions and ideas for the implementation teams.
They may wish to implement all, some, or none of this, and will likely have
further ideas for additional warnings, lints, and quick fixes.

### Automated migration

Since the static semantics are so simple, it is trivial to write a `dart fix`
that automatically converts existing "dart:" and "package:" string-based
directives to the new syntax. A handful of regexes are sufficient to break an
existing import into a series of slash-separated segments which are
dot-separated identifiers. Then the above snippet of Dart code will convert that
to the new syntax.

### Lint

A good tool doesn't make users waste mental effort on pointless decisions. One
way we do that with Dart is through lints that give users opinionated guidance
when the choice otherwise doesn't really matter.

In this case, we should have a recommended lint that suggests users prefer the
new unquoted style whenever an existing directive could use it.

## Changelog

### 0.3

-   Address breaking change in `part of` directives with library names.

-   Note additional lookahead for parsing `part` and `part of` directives.

### 0.2

-   Handle dotted identifiers in single-segment imports specially. *This makes
    them work better for common cases in Google's monorepo.*

### 0.1

-   Initial draft.
