# Dart Import Shorthand Syntax

Author: lrn@google.com<br>Version: 2.2.1

This is a proposal for a shorter import syntax for Dart. It is defined as a shorthand syntax which expands to, and coexists with, the existing import syntax. It avoids unnecessary repetitions and uses short syntax for the most common imports.

## Motivation

Dart package imports are fairly verbose because they are based on URIs with no shorthands. A fairly typical import would be:

```dart
import "package:built_value/built_value.dart";
```

The repetition alone is grating, and Dart imports can typically be split into three groups:

- Platform libraries, `import "dart:async";`.
- Third-party packages, `import "package:built_value/built_value.dart";`.
- Same package relative import, `import "src/helper.dart";`.

The package imports are the ones with the most overhead. For the relative imports, the surrounding quotes and trailing `.dart` are still so ubiquitous that they might as well be assumed.

The goal is to allow a very short import of a package’s default library: `import test;` is short for `import “package:test/test.dart”;`. Shorthands are added for the other commonly occurring import URI formats as well.

The commonly occurring import formats include:

```dart
import "dart:async";                       // Platform library.
import "package:path/path.dart";           // Default package library
import "package:collection/equality.dart"; // Alternative package library
import "package:analyzer/dart/ast.dart";   // Same, with path.
import "helper.dart";                      // Local relative file.
import "src/helper.dart";                  // Same, with down-path.
import "../main.dart";                     // Same, with up-path.
import "/main.dart";                       // Rooted relative path.
import "package:my.project.component/component.dart"; // Bazel package-name.
```

## Design

The new syntax uses no quotes. Each shorthand library reference is provided as a character sequence containing no whitespace, and consisting only of ASCII digit, letter and underscore (`_`)-based “words” separated or prefixed by colons (`:`), dots (`.`), dashes (`-`), and slashes (`/`). That syntax still covers *all commonly used imports*.

The new import URI shorthand can be split into *package* imports and *path* imports. (We say “import” here, because that’s the main use-case, but it also works the same for exports and part files.)

A package import is a shorthand for a `package:` URI. It specifies, implicitly or explicitly, a package *name* and a *file path* inside that package (the two parts of a <code>package:*package_name*/*file_path*.dart</code> URI). You omit the final `.dart` in the file name.

A path import is a shorthand for a relative path-only URI reference, which will be resolved against the current file’s URI. It contains just a path, and is recognizable as a path by starting with one of `/`, `./` or `../`. Again you omit the final `.dart` in the file name.

In both cases, we restrict the characters that can occur in the path and package_name. Since there are no quotes to delimit the shorthand, we instead end it at the first non-allowed character. Grammatically, that’s always going to be whitespace or a `;` in valid programs.

### Package import shorthand syntax

The *general package shorthand* syntax is `import package_name:path`. 

You can omit the path (including the colon) to get a *package default shorthand*. That’s the syntax we want for `import test;`. It means the same as `import test:test;`.

You can omit the package name, and have just the colon and path, to get a *current package shorthand*, which uses the package of the surrounding as the package, so an `import :path` means the same as `import current_package:path`.

The package name `dart` is special-cased to mean a *platform library shorthand*, so `import dart:async` does import `dart:async`.

### Path import shorthand syntax

A path import shorthand starts with `/`, `./` or `../`. It is simply a shorthand for appending `.dart` to the path. So `import ./path` is a shorthand for

```
import "./path.dart"
```

and similarly for `/path` and `../path`.

As one exception, we actually count the number of leading `../`s in a relative path and makes it a compile-time error if there are more than the containing file’s URI has parent directories. (The URI resolution algorithm is defined as ignoring that situation, but it’s safer to not ignore something which is an error.)

## Syntax

The grammar is:

```
# Any sequence of letters, digits, and `_`. (No `$`.)
<SHORTHAND_NAME_PART> ::= [a-zA-Z0-9_]+

<SHORTHAND_NAME> ::= 
     <SHORTHAND_NAME_PART>
   | <SHORTHAND_NAME> '-' <SHORTHAND_NAME_PART>
    
<DOTTED_NAME> ::=
    <SHORTHAND_NAME> 
  | <DOTTED_NAME> '.' <SHORTHAND_NAME>

<SHORTHAND_PATH> ::=
    <DOTTED_NAME> 
  | <SHORTHAND_PATH> '/' <DOTTED_NAME>
   
<PACKAGE_REFERENCE> ::=
    <DOTTED_NAME> ':' <SHORTHAND_PATH>
  | <DOTTED_NAME>
  | ':' <SHORTHAND_PATH>
  
<PATH_REFERENCE> ::=  
    '/' <SHORTHAND_PATH>
  | './' <SHORTHAND_PATH>
  | '../' <SUPER_PATH>
  
<SUPER_PATH> ::= 
    '../' <SUPER_PATH> 
  | <SHORTHAND_PATH>
   
<SHORTHAND_URI> ::= 
    <PACKAGE_REFERENCE> 
  | <PATH_REFERENCE>

<part_uri> ::=
    <uri>
  | <PATH_REFERENCE>

<import_uri> ::= 
    <uri> 
  | <SHORTHAND_URI>
```

A shorthand name is any sequence of ASCII digits, letters, `_` or `-` characters, where `-`s, `.`s and `/`s can only be separators (not leading or trailing or having two adjacent ones like  `--` or `..`, except for leading `../`s in the super-path) . Adding this directly to the lexical grammar is ambiguous with, at least, identifiers, number literals and reserved words, so the parser may have to, e.g, first do normal tokenization with the existing grammar, then try to combine adjacent identifiers, number literals, `/`, `:` , `-`, and `.` tokens into a shorthand URI when the parser knows that it expects an import URI and the next token is not a string literal.

Since a shorthand URI can only occur where a URI is expected, and a URI is currently always a string literal, there is no ambiguity in *parsing*, we know when to expect a shorthand URI based on the previous code.

The shorthand syntax can be used for `import`, `export`, `part` declarations. We may want to also allow it for `part-of` declarations, but since `part of foo.bar.baz;` is already valid syntax, we also need to *discontinue* that existing syntax in the same language version which introduces the new syntax. (That is a risk, because it means existing code may stay syntactically valid and change its meaning, rather than just becoming invalid. The alternative is to deprecated the existing `part of` syntax, not allow the new syntax in `part of` declarations yet, and then introduce it later when the existing uses have been removed).

## Semantics

### Package references

Let *p* be a `<PACKAGE_REFERENCE>`.

If *p* is a *general package shorthand*, `<DOTTED_IDENTIFIER> ':' <SHORTHAND_PATH>`, of the form <Code>*name*:*path*</code>, and *name* is not `dart`, then *p* is shorthand for an `<uri>` of the form <Code>"package:*name*/*path*.dart"</code>.

Otherwise, if *name* is `dart`, then *p* a *platform library shorthand* and is a shorthand for <code>"dart:*path*”</code> (and *path* then needs to be the name of a platform library.)

If *p* is a *package default shorthand*, a `<DOTTED_NAME>`, <code>*name*</code>, then:

* If *name* is a single `<SHORTHAND_NAME>`, then *p* is shorthand for <code>"package:*name*/*name*.dart"</code>.
* If *name* is a `<DOTTED_NAME> '.’ <SHORTHAND_NAME>` of the form <code>*prefix*.*last*</code> then *p* is shorthand for <Code>"package:*name*/*last*.dart</code>.

If *p* is a *current package shorthand*, `: <SHORTHAND_PATH>`, of the form <Code>:*path*</code>, then let *name* be the package name of the package that the surrounding file belongs to. Then *p* is shorthand for <Code>"package:*name*/*path*.dart"</code>. _(A leading-`:`-reference *only* works for code which is actually inside a package. Being “inside a package” in this regard is defined in the same way as used for language versioning, which means that the `test/` and `bin/` directories of a Pub package are inside the same package as the `lib/` directory, even if they cannot be referenced using a `package:` URI. Effectively `:path` becomes a canonical way for libraries outside of `lib/` to refer to package-URIs of the same package, without needing to repeat the package name.)_

### Path references

A path reference is relative to the URI of the current library. A path reference (`<PATH_REFERENCE>`) *path* is a shorthand for a `<uri>` of the form <code>"*path*.dart"</code>.

It’s a compile-time error if a `'../' <SUPER_PATH>` has more leading `../`s than the surrounding library’s URI has super-directories. _So, if inside `package:foo/src/example.dart` one does an `import ../../foo.dart;`, it is a compile-time error. The library’s URI only has one super-directory (`package:foo/`, the package name is not a directory). This differs from how relative URI resolution works, because it allows having too many leading `../`s, and just ignores the extra ones._

We restrict `part` and `part of`  to only using path references. That way a part and its library *must* be in the same library, which is a reasonable constraint, and it avoids giving new meaning to the existing `part of some.library.name;` syntax, which we will simply disallow.

### Examples

Assume the following shorthands occur inside the package `foo`, either in the `lib/` directory, where the containing file has a `package:foo/…` URI, or in the `test/` directory, where the containing file has a `file:///…` URI.

| Containing file                      | Shorthand     | Shorthand for                            |
| ------------------------------------ | ------------- | ---------------------------------------- |
| `package:foo/src/bar.dart`           | `bar`         | `package:bar/bar.dart`                   |
| (aka `…/foo/lib/src/bar.dart`)       | `bar:baz`     | `package:bar/baz.dart`                   |
|                                      | `bar:baz/qux` | `package:bar/baz/qux.dart`               |
|                                      | `:bar`        | `package:foo/bar.dart`                   |
|                                      | `:src/bar`    | `package:foo/src/bar.dart`               |
|                                      | `./baz`       | `package:foo/src/baz.dart`               |
|                                      | `./baz/qux`   | `package:foo/src/baz/qux.dart`           |
|                                      | `../bar`      | `package:foo/bar.dart`                   |
|                                      | `../misc/bar` | `package:foo/misc/bar.dart`              |
|                                      | `../../bar`   | **Invalid** (too many `..`s)             |
|                                      | `/bar`        | `package:foo/bar.dart`                   |
|                                      | `/src/bar`    | `package:foo/src/bar.dart`               |
| `file:///something/foo/bin/run.dart` | `bar`         | `package:bar/bar.dart`                   |
|                                      | `bar:baz`     | `package:bar/baz.dart`                   |
|                                      | `bar:baz/qux` | `package:bar/baz/qux.dart`               |
|                                      | `:bar`        | `package:foo/bar.dart`                   |
|                                      | `:src/bar`    | `package:foo/src/bar.dart`               |
|                                      | `./baz`       | `file:///something/foo/bin/baz.dart`     |
|                                      | `./baz/qux`   | `file:///something/foo/bin/baz/qux.dart` |
|                                      | `../bar`      | `file:///something/foo/bar.dart`         |
|                                      | `../misc/bar` | `file:///something/foo/misc/bar.dart`    |
|                                      | `../../bar`   | `file:///something/bar.dart`             |
|                                      | `/bar`        | `file:///bar.dart`                       |
|                                      | `/src/bar`    | `file:///src/bar.dart`                   |
| `file:///home/me/bin/script.dart`    | `bar`         | `package:bar/bar.dart`                   |
| (not inside a Pub package,           | `bar:baz`     | `package:bar/baz.dart`                   |
| but assume some packages available). | `bar:baz/qux` | `package:bar/baz/qux.dart`               |
|                                      | `:bar`        | **INVALID** (no current package)         |
|                                      | `:src/bar`    | **INVALID** (no current package)         |
|                                      | `./baz`       | `file:///home/me/bin/baz.dart`           |
|                                      | `./baz/qux`   | `file:///home/me/bin/baz/qux.dart`       |
|                                      | `../bar`      | `file:///home/me/bar.dart`               |
|                                      | `../misc/bar` | `file:///home/me/misc/bar.dart`          |
|                                      | `../../bar`   | `file:///home/bar.dart`                  |
|                                      | `/bar`        | `file:///bar.dart`                       |
|                                      | `/src/bar`    | `file:///src/bar.dart`                   |

## Consequences

Programmers can write less code. There will be some paths which cannot be written in the shorthand syntax, perhaps because they contain non-identifier characters. Those will still have to be written the old way, as URIs inside delimited strings. It’s expected that almost all imports can use the new syntax.

That moves code authors away from writing URIs. That’s a good thing, since confusing URIs and paths have led to a number of problems over the years. URIs are complicated and have their own semantics, not all of which match Dart well. If you have to write the restricted shorthand syntax instead, the ways you can make mistakes is reduced significantly.

#### Parsing

The parser needs to be a little clever. If it tokenizes identifiers, numbers, reserved words, dots, colons and slashes first, then it has to combine them back into a single shorthand URI. Alternatively, it can re-scan the source after seeing `import`. That may still mean ending up in the middle of a number token and needing to do something special about that. Something like `import ./foo/2.2e+1;` needs to fail at the `+`, because everything up to that point is a valid shorthand URI. The reason this proposal does not allow even more complicated shorthand URIs is that it would make parsing even more problematic. The chosen design attempts a trade-off between allowing most existing package URIs to be written with the new syntax and allow the syntax to be parsed without too much overhead.

If necessary, we could allow some infix operators in the import name, most likely `-`. In practice, most package names and files use `_` as separator, which is included in identifiers automatically.  (If it helps parsing to allow `+` and `-` in shorthand URIs, so that it always includes any entire double literal that it contains any part of, then we can allow that too.)

#### Belonging to a package

The `:path` shorthand introduces the notion of “belonging to a package” to the *language*. Previously, that was only a concern for compilers and tools, but with this, it begins affecting the meaning of *source code*. (Arguably, it did before too, because changing language version affects the meaning of source code too, but that’s more indirect than determining which file gets imported.)

#### Part-of legacy syntax

We need to remove the existing `part of` syntax based on package names before we can allow shorthand URIs in `part of` declarations. 

Removing the existing `part of foo.bar;` syntax *at the same time* as introducing a new `part of foo.bar;` syntax with a different meaning is *risky*. Much code has already moved to using `part of "uri";`, but there is a significant amount of old-style `part of` declarations in the wild. (Replacing with a URI is also not something which can be done on a file-by-file basis, the conversion needs to find the URI of the library owning the library since the name alone doesn’t describe that, which is also the major short-coming of the name-based `part of` syntax.) 

To avoid the problem, we allow only *path* references as `part of ` shorthand URIs.

We can remove the existing name-based `part of` syntax, making the format simply invalid. That would *require* a migration (making this language change a breaking change, not just an enhancement), meaning that it requires a proper migration with a dedicated migration tool, making this feature a larger undertaking than without that change. 

We can also keep the old syntax with its current meaning, just make it deprecated, and remove it later (Dart 3.0 at the latest). That’s potentially very confusing, if `import foo;` means one thing and `part of foo;` means something else (but hopefully the deprecation warning will help you figure out what to do instead). 

If we do remove the legacy syntax, that also removes the last non-`dart:mirrors` use of package names, and it might be worth introducing unnamed library declarations at the same time (allowing `library;` as a declaration which you can hang annotations and documentation on, without having to come up with a name).

#### Redundancy

Inside the `lib/` directory (in any file with a `package:` URI), shorthands of `:path` and `/path` are equivalent.

The former is an implicit `package:` URI into the current package, the latter is a relative path relative to the root of the current (`package:`) URI. Both end up pointing to the same `package:` URI.

Since using `/` in a file with with a `file:` URI is going to be incredibly rare, we might only need `:`.

On the other hand, since `:` is new functionality, allowing you to omit the current package’s name, but `/path.dart` is already a valid import, we could consider dropping `:` instead.

### Case

Our paths are still case sensitive. Since Dart runs on both Unixes and Windows, where file systems are case-sensitive and non-case-sensitive respectively, it has to assume that a directory can contain both `Foo.dart` and `foo.dart`. In practice, that never happens for someone following the conventions for naming files and directories (they’re all lower case). Not everyone does, though.

We could take a stand, and *only* allow lower-case letters in shorthands, but there are thousands of files containing imports of UpperCamelCased file names (for example code converted or generated from Java classes).

We could make the shorthand *case insensitive*, but then it becomes a new import syntax, not just a shorthand for writing a URI (because URIs are guaranteed to be case sensitive).

It’s not clear that there is something clean we can do here, but if there was, now would be a good time to do it.

## Version history

1.0: Original version uploaded as language issue [#649](https://github.com/dart-lang/language/issues/649).

2.0: Remove shorthands for relative imports, just use the URIs, and don't allow shorthand syntax in `part` declarations.<br>2.1: Reinstate shorthands for relative imports, but keep `:` as the marker for same-package paths. Grammar allows multiple leading `../`’s. More discussion on `part of`.

2.2, 2021-11-02: Use `:` as marker for same-package paths and retain `/` as a path reference. Allow `-` in URI path segments.

2.2.1. Fix typos.
