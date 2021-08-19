# Dart Import Shorthand Syntax

Author: lrn@google.com<br>Version: 2.0

This is a proposal for a shorter import syntax for Dart. It is defined as a shorthand syntax which expands to, and coexists with, the existing import syntax. It avoids unnecessary repetitions and uses short syntax for the most common imports.

## Motivation

Dart package imports are fairly verbose because they are based on URIs with no shorthands. A fairly typical import would be:

```dart
import "package:built_value/built_value.dart";
```

The repetition alone is grating, and Dart imports can typically be split into three groups:

* Platform libraries, `import "dart:async";`.
* Third-party packages, `import "package:built_value/built_value.dart";`.
* Same package relative import, `import "src/helper.dart";`.

The package imports are the ones with most overhead. For the rest, the surrounding quotes and trailing `.dart` are still so ubiquitous that they might as well be assumed.

## Syntax

The new syntax uses no quotes. Each shorthand library reference is provided as a *URI-like* character sequence containing no whitespace, and consisting only of identifiers/reserved words separated or prefixed by colons (`:`), dots (`.`) and slashes (`/`). 

The allowed formats are:

* A single shorthand Dart package name.
* A shorthand Dart package name followed by a colon, `:`, and a relative shorthand path.
* A `:` followed by a relative shorthand path.

_There are no shorthands for relative imports. Those imports refer to *files* without any abstraction, and using a URI is considered sufficient. Imports which mentions a package name can be abbreviated, treating the package as an abstraction._

A *shorthand Dart package name* is a *dotted name*: A non-empty `.` separated sequence of Dart identifiers or reserved words. Such a sequence can have just a single element and no separator.

A *relative shorthand path* is a non-empty `/` separated sequence of dotted names.

The grammar would be:

```
# Any sequence of letters, digits, `_` and `$`.
<SHORTHAND_IDENTIFIER> ::= 
    <INTEGER_LITERAL> | <INTEGER_LITERAL>? (<IDENTIFIER> | <RESERVED_WORD>)

<DOTTED_IDENTIFIER> ::=
   <SHORTHAND_IDENTIFIER> | <DOTTED_IDENTIFIER> '.' <SHORTHAND_IDENTIFIER>

<SHORTHAND_PATH> ::=
   <DOTTED_IDENTIFIER> | <SHORTHAND_PATH> '/' <DOTTED_IDENTIFIER>
   
<SHORTHAND_URI> ::=  
    <DOTTED_IDENTIFIER> (':' <SHORTHAND_PATH>)? |
    ':' <SHORTHAND_PATH>
   
<import_uri> ::= <uri> 
        | <SHORTHAND_URI>
```

Since a shorthand URI can only occur where a URI is expected, and a URI is currently always a string, there is no ambiguity in *parsing*. Tokenization is doable, but will probably initially allow whitespace between tokens because it doesn't yet know that it's a shorthand sequence. When it recognizes that a URI is expected and a non-string follows, it must combine the following tokens only as long as there is no space between them.

(We can allow spaces between identifiers/keywords and `:`, `.` and `/`, but it will be harder to read and it makes the grammar less extensible).

The shorthand syntax can also be used for `export` and declarations, but no in `part` declarations. The new syntax only denotes *libraries*, not *files*. It also does not work for `part of` declarations because `part of foo.bar.baz;` is already valid syntax. We may want to disallow this existing syntax so that you can use the full shorthand syntax with no exceptions. _(Please do disallow the old part-of format where you use the parent library *name*)._

## Semantics

An import of a single-identifier package name, `name`, is equivalent to an import of `"package:name/name.dart"`. This is the most common form of package imports, and it gets the shortest syntax.

An import of a dot-separated package name, `some.prefix.last`, is equivalent to an import of `"package:some.prefix.last/last.dart"`. The single-identifier case is just the special case where there is no prefix.

An import of a package-colon-path sequence, `name:path` is equivalent to an import of `"package:name/path.dart"`. (Notice the added `.dart`). This is used for packages which expose more than one library.

An import of a package-colon-path sequence, `:path` is equivalent to an import of `"package:name/path.dart"` where `name` is the name of the current package. This *only* works for code which is inside a package (for now, which occurs in a library with a `package:name/...` URI, but potentially extensible to `test/` and `bin/` directories that belong to the same package).

The package name `dart` is special-cased so that an import of `dart:async` will import `"dart:async"`, and an import of just `dart` is not allowed because there is no `dart:dart` library. This allows us to treat `dart:` as a platform supplied package with libraries `core.dart`, `async.dart`, etc., which may actually be an improvement over the current special-casing that we do. It does mean that `dart` is not available as a package name for user packages. _(It never was.)_

Examples:

* `import built_value;` means `import "package:built_value/built_value.dart";`
* `import built_value:serializer;` means `import "package:built_value/serializer.dart";`.
* `import :src/serializer_helper;` means `import "package:built_value/src/serializer_helper.dart";` when it occurs in the previous library.
* `import dart:async;` means `import "dart:async";`.
* `import hide hide hide;` is valid and means `import "package:hide/hide.dart" hide hide;`.

* `import pkg1 if (dart.libraries.io) pkg2;` works too, each URI is expanded individually.

## Consequences

Programmers can write less code. There will be some paths which cannot be written in the shorthand syntax, perhaps because they contain non-identifier characters or path segments starting with a digit. Those will still have to be written the old way, as URIs inside delimited strings.

The parser needs to be a little clever. If it tokenizes identifiers, reserved words, dots, colons and slashes first, then it has to combine them back into a single shorthand URI and check for separating whitespace. The reason this proposal does not allow even more complicated shorthand URIs is that it would make parsing even more problematic. The chosen design attempts a trade-off between allowing most existing package URIs to be written with the new syntax and allow the syntax to be parsed without too much overhead. 

If necessary, we could allow some infix operators in the import name, most likely `-`. In practice, most package names and files use `_` as separator, which is included in identifiers automatically.

### No shorthand for relative imports

A relative import like `import 'src/file.dart';` does not get a shorter form.

Since `src/file` is the minimum required information to locate the correct file, all we can save is the final `.dart`. We *could* allow a shorthand for this, the prior version of this proposal used `import ./src/file` to separate a relative path like `./sameDirFile` from a package named `sameDirFile`. The syntax is cumbersome and it makes the character count saving even smaller.

Since it's technically possible to have `dart` files not ending in `.dart`, a URI of `import "foo";` can already be valid. Changing its meaning is potentially breaking (even if very unlikely to be so in practice). 

One option is to check if a relative import path `"foo"` exists, and if not, check whether `"foo.dart"` does and use that instead.

Another option is to use a different quote character, say one of:

```dart
import <foo>;
import `foo`;
```

Neither is shorter than `import ./foo;`, which is also very clearly relative.

All in all, relative paths inside the same package can be seen as denoting *files*, so having to write the entire file name is reasonable, whereas an import like `import foo:bar` can be seen as denoting a logical library.

You *can* use `import :src/helper;` for files that have short paths, but when choosing between `import "next_to_me.dart";` and `import :src/helpers/factories/specific/next_to_me;` , the original syntax still wins. (Arguably, `:path` syntax might encourage people to make a flatter file structure, and if so, it might be better to drop the syntax instead of skewing people's motivations.)

## Version history

1.0: Original version uploaded as language issue [#649](https://github.com/dart-lang/language/issues/649).
2.0: Remove shorthands for relative imports, just use the URIs, and don't allow shorthand syntax in `part` declarations.
