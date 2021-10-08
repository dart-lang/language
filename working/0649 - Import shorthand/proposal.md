# Dart Import Shorthand Syntax

Author: lrn@google.com<br>Version: 2.1

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

The package imports are the ones with the most overhead. For the rest, the surrounding quotes and trailing `.dart` are still so ubiquitous that they might as well be assumed.

## Syntax

The new syntax uses no quotes. Each shorthand library reference is provided as a *URI-like* character sequence containing no whitespace, and consisting only of ASCII digit, letter, `$` and `_`-based “words” separated or prefixed by colons (`:`), dots (`.`) and slashes (`/`). 

The allowed formats are:

- A single shorthand Dart package name.
- A shorthand Dart package name followed by a colon, `:`, and a relative shorthand path.
- A `:` followed by a relative shorthand path.
- A `./` or `../` followed by a relative shorthand path.

A *shorthand Dart package name* is a *dotted identifier*: A non-empty `.` separated sequence of shorthand identifiers. Such a sequence can have just a single element and no separator.

A *relative shorthand path* is a non-empty `/` separated sequence of dotted identifiers, which again can have just a single element.

The grammar would be:

```
# Any sequence of letters, digits, `_` and `$`.
<SHORTHAND_IDENTIFIER> ::= <IDENTIFIER_PART>+

<DOTTED_IDENTIFIER> ::=
   <SHORTHAND_IDENTIFIER> | <DOTTED_IDENTIFIER> '.' <SHORTHAND_IDENTIFIER>

<SHORTHAND_PATH> ::=
   <DOTTED_IDENTIFIER> | <SHORTHAND_PATH> '/' <DOTTED_IDENTIFIER>
   
<SHORTHAND_URI> ::=  
    <DOTTED_IDENTIFIER> (':' <SHORTHAND_PATH>)? |
    ':' <SHORTHAND_PATH>
    './' <SHORTHAND_PATH>
    '../' <SUPER_PATH>

<SUPER_PATH> ::= '../' <SUPER_PATH> | <SHORTHAND_PATH>
   
<import_uri> ::= <uri> 
        | <SHORTHAND_URI>
```

A shorthand identifier is any sequence of ASCII digits, letters, `$` or `_` characters. Adding this directly to the lexical grammar is ambiguous with, at least, identifiers, number literals and reserved words, so the parser may have to, e.g, first do normal tokenization with the existing grammar, then try to combine adjacent identifiers, number literals, `/`, `:` and `.` tokens into a shorthand URI when the parser knows that it expects an import URI and the next token is not a string literal.

Since a shorthand URI can only occur where a URI is expected, and a URI is currently always a string literal, there is no ambiguity in *parsing*, we know when to expect a shorthand URI based on the previous code.

The shorthand syntax can be used for `import`, `export`, `part` declarations. We may want to also allow it for `part-of` declarations, but since `part of foo.bar.baz;` is already valid syntax, we also need to *discontinue* that existing syntax in the same language version which introduces the new syntax. (That is a risk, because it means existing code may stay syntactically valid and change its meaning, rather than just becoming invalid. The alternative is to deprecated the existing `part of` syntax, not allow the new syntax in `part of` declarations yet, and then introduce it later when the existing uses have been removed).

## Semantics

A shorthand single-identifier package name, `name`, is equivalent to an URI of `"package:name/name.dart"`. This is the most common form of package imports, and it gets the shortest syntax.

A shorthand dot-separated package name, `some.prefix.last`, is equivalent to a URI of `"package:some.prefix.last/last.dart"`. _The single-identifier case is just the special case where there is no prefix._

A shorthand package-colon-path sequence, `name:path`, is equivalent to a URI of `"package:name/path.dart"`. (Notice the added `.dart`). This is used for packages which expose more than one library. You can do `analyzer:src/ast.dart` as well, but the majority of other-package non-default-library imports will still be top-level libraries. _(We_ could _allow only a single identifier when the package name is specified, so it’s `name:library`, not `name:path`. That would force other-package deep-linking to use strings, which might highlight that something fishy is going on.)_

A shorthand colon-path sequence, `:path` is equivalent to an import of `"package:name/path.dart"` where `name` is the name of the _current package_. This *only* works for code which is actually inside a package. Being “inside a package” in this regard is defined in the same way as used for language versioning, which means that the `test/` and `bin/` directories of a Pub package are inside the same package as the `lib/` directory, even if they cannot be referenced using a `package:` URI. Effectively `:path` becomes the canonical way for libraries outside of `lib/` to refer to package-URIs, without needing to repeat the package name. Inside `lib/` you can use either `:path` or a relative path like the ones below.

A shorthand dot-slash-path or dot-dot-slash-path sequence, `./path` or `../super-path`, is equivalent to a relative URI of `"./path.dart"` (aka. `"path.dart"`) or `"../super-path.dart"`.  _The `../` path may start with more than one `../` sequence, but `..` can’t occur as a path segment later._

The package name `dart` is special-cased so that an import of `dart:async` will import `"dart:async"`, and an import of just `dart` is not allowed because there is no `dart:dart` library. _This could allow us to generally treat `dart:` URIs as a platform supplied package named `dart` with libraries `core.dart`, `async.dart`, etc., which may actually be an improvement over the current special-casing that we do. It does mean that `dart` is not available as a package name for user packages. (It never was.)_

Examples:

- `import built_value;` means `import "package:built_value/built_value.dart";`
- `import built_value:serializer;` means `import "package:built_value/serializer.dart";`.
- `import :src/int_serializer;` means `import "package:built_value/src/int_serializer.dart";` when it occurs in the previous `serializer.dart` library, or anywhere else in the same Pub package.
- `import ./src/int_serializer;` means `import "./src/int_serializer.dart"`, aka.`import "src/int_serializer.dart"`, when it occurs inside the previous `serializer.dart` library.
- `import ../serializer;` means `import "../serializer.dart"` when it occurs inside the previous `src/int_serializer.dart` library.
- `import dart:async;` means `import "dart:async";`.
- `import hide hide hide;` is valid and means `import "package:hide/hide.dart" hide hide;`.
- `import pkg1 if (dart.libraries.io) pkg2;` works too, each URI is expanded individually.

## Consequences

Programmers can write less code. There will be some paths which cannot be written in the shorthand syntax, perhaps because they contain non-identifier characters. Those will still have to be written the old way, as URIs inside delimited strings.

#### Parsing

The parser needs to be a little clever. If it tokenizes identifiers, numbers, reserved words, dots, colons and slashes first, then it has to combine them back into a single shorthand URI. Alternatively, it can re-scan the source after seeing `import`. That may still mean ending up in the middle of a number token and needing to do something special about that. Something like `import ./foo/2.2e+1;` needs to fail at the `+`, because everything up to that point is a valid shorthand URI. The reason this proposal does not allow even more complicated shorthand URIs is that it would make parsing even more problematic. The chosen design attempts a trade-off between allowing most existing package URIs to be written with the new syntax and allow the syntax to be parsed without too much overhead.

If necessary, we could allow some infix operators in the import name, most likely `-`. In practice, most package names and files use `_` as separator, which is included in identifiers automatically.  (If it helps parsing to allow `+` and `-` in shorthand URIs, so that it always includes any entire double literal that it contains any part of, then we can allow that too.)

#### Belonging to a package

The `:path` shorthand introduces the notion of “belonging to a package” to the *language*. Previously, that was only a concern for compilers and tools, but with this, it begins affecting the meaning of *source code*. (Arguably, it did before too, because changing language version affects the meaning of source code too, but that’s more indirect than determining which file gets imported.)

#### Part of legacy syntax

We need to remove the existing `part of` syntax based on package names before we can allow shorthand URIs in `part of` declarations. Potentially, we could allow only *relative* `part of ` shorthand URIs and retain the existing name-based `part of` syntax with its current meaning, just deprecated. That’s also potentially very confusing.

If we remove the legacy syntax, that also removes the last non-`dart:mirrors` use of package names, and it might be worth introducing unnamed library declarations at the same time (allowing `library;` as a declaration which you can hang annotations and documentation on, without having to come up with a name).

Removing the existing `part of foo.bar;` syntax *at the same time* as introducing a new `part of foo.bar;` syntax with a different meaning is *risky*. Much code has already moved to using `part of "uri";`, but there is a significant amount of old-style `part of` declarations in the wild. (Replacing with a URI is also not something which can be done on a file-by-file basis, the conversion needs to find the URI of the library owning the library since the name alone doesn’t describe that, which is also the major short-coming of the name-based `part of` syntax.) 

That means that a proper migration where we also change the meaning of `part of` will likely need a dedicated migration tool, making this feature a larger undertaking than without that change. The alternative is to say that shorthand URI syntax does not work for `part of` declarations *yet*, and the old-style name-based `part of` is now deprecated and causes warning. Potentially allow relative shorthand URIs, which should be sufficient for most cases.

## Version history

1.0: Original version uploaded as language issue [#649](https://github.com/dart-lang/language/issues/649).
2.0: Remove shorthands for relative imports, just use the URIs, and don't allow shorthand syntax in `part` declarations.<br>2.1 Reinstate shorthands for relative imports, but keep `:` as the marker for same-package paths. Grammar allows multiple leading `../`’s. More discussion on `part of`.
