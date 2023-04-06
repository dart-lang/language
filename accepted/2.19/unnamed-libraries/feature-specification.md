# Unnamed Libraries

Author: srawlins@google.com

Version 1.0

Specification for issue [#1073](https://github.com/dart-lang/language/issues/1073)

## Motivation

Users would like to both document a library and associate metadata with a
library without needing to decide on a library name.

Declaring a library with a library declaration has become increasingly rare,
with the availability of a 'part of' syntax with a URI string, and with the
decline of the mirror system. Tools such as dartdoc and the test package
attempt to support "library-level" documentation comments and annotations by
looking at such elements associated with the first directive in a library, or
the first declaration. Allowing users to write `library;` without a name gives
a specific and meaningful syntax for library-level documentation and metadata.
With this syntax, users do not need to conceive of a unique library naming
scheme, nor do they need to write out names which are never used.

## Specification

With this feature, library directives are allowed to be written without a name:

```dart
// Existing named library syntax:
library qualified.named.separated.by.dots;

// New unnamed library syntax:
library;
```

Prior to this feature, a library can be _explicitly named_ with a library
directive, or _implicitly named_ when written without a library directive. An
implicitly named library has the empty string as its name. With this feature, a
library with a library directive without a name is an implicitly named library.

### Grammar

The language grammar is changed to allow library directives without name.

The section containin

> ```latex
> <libraryName> ::= <metadata> \LIBRARY{} <dottedIdentifierList> `;'
> ```

becomes:

> ```latex
> <libraryName> ::= <metadata> \LIBRARY{} <dottedIdentifierList>? `;'
> ```

### Parts

A library part specifies the library to which it belongs using the part-of
directive, which accepts two ways of referring to a library. A part-of
directive can specify a library by URI, which is the more common way, and does
not require the library to be explicitly named. In an older style, a part-of
directive can instead specify a library by its name. A part-of directive cannot
refer by name to an implicitly named library.  Therefore, with this feature, a
part-of directive using a library name cannot refer to a library with a library
directive without a name.

### `dart:mirrors`

The mirror system has at least one mechanism that uses a library's name,
`MirrorSystem.findLibrary`. This function cannot find an implicitly named
library. Therefore it cannot find a library with a library directive without a
name.

## Summary

We allow library directives without name.

## Versions

1.0, 2022-09-14: Initial version
