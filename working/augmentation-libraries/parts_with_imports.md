# Part files with imports

Authors: rnystrom@google.com, jakemac@google.com, lrn@google.com <br>
Version: 1.0 (See [Changelog](#Changelog) at end)

This is a stand-along definition of _improved part files_, where the title of
this document/feature is highlighting only the most prominent part of the
feature. This document is extracted and distilled from the [Augmentations][]
specification. The original specification introduced special files for
declaring augmentations, and this document is the unification of those files
with the existing `part` files, generalizing library files, part files and
augmentation files into a consistent and (almost entirely) backwards compatible
extension of the existing part files.

Because of that, the motivation and design is based on the needs of
meta-programming and augmentations. It’s defined as a stand-alone feature, but
design choices were made based on the augmentations and macro features,
combined with being backwards compatible.

[Augmentations]: augmentations.md "Augmentations feature specification"

## Motivation

Dart libraries are the unit of code reuse. When an API is too large to fit into
a single file, you can usually split it into multiple libraries and then have
one main library export the others. That works well when the functionality in
each file is made of separate top-level declarations.

There are two cases where that approach does not work optimally.

If the separate classes are tightly coupled, and interact by accessing private
members of each other, they need to be in the same library. If the library file
becomes too big, the individual classes can be moved into separate *part
files*. Part files can be harder to work with than separate libraries because
they cannot declare their own imports, and all imports for the library must be
in the main library file. That makes it harder to manage and understand
imports, since the code that needs an import may not be in the same file as the
import itself. There have been requests to either loosen the “library privacy”
([#3125][]) or to allow better part files ([#519][]). This feature does not
loosen library privacy, but it improves part files to the point where it may
more tolerable to keep all the classes in the same library in some cases.

Also, sometimes a single *class* declaration is too large to fit comfortably
in a file. Dart libraries and even part files are no help there. Because of
this, users have asked for something like partial classes in C# ([#252][] 71 👍,
[#678][] 18 👍). C# also supports splitting [the declaration and implementation
of methods into separate files][partial]. Splitting classes, or other
declarations, into separate parts is what the [Augmentations][] feature solves.
The improved part files gives augmentations, and specifically macro generated
augmentations, a structured and capable way to add new code, including new
imports and new exports, to a library.

Finally, we take this opportunity to disallow the legacy
`part of library.name;` notation ([#2358][]). It won’t work some of the added
features, and the Dart language is moving away from giving libraries names.

[#252]: https://github.com/dart-lang/language/issues/252	"Partial classes and methods"
[#678]: https://github.com/dart-lang/language/issues/678	"Partial classes"
[partial]: https://github.com/jaredpar/csharplang/blob/partial/proposals/extending-partial-methods.md
[#3125]: https://github.com/dart-lang/language/issues/3125	"Shared library privacy"
[#519]: https://github.com/dart-lang/language/issues/519	"Allow imports in part files"
[#2358]: https://github.com/dart-lang/language/issues/2358	"Disallow part of dotted.name"

## Background

In pre-feature code (Dart code before this feature is introduced), a library is
defined by one library file, and a number of part files referenced directly by
the library file using `part` directives like `part 'part_file_name.dart';`,
placed in the header section of the library file after `library`, `import` and
`export` declarations. Each part file must start with a `part of` directive
having one of the forms `part of 'library_file_name.dart';` or
`part of library.name;`, where the library name is the name declared by the
library file using a `library library.name;` directive. The part file
designating its containing library is intended to ensure that a part file can
only ever be part of one library file, which is essential for, for example,
having useful language support when editing the part file.

The (URI) string version is the most useful for making analysis of a part file
possible and unique, because it uniquely defines the library by the URI that
the language itself uses to identify files and libraries. It’s technically
possible to have two separate libraries with the same declared library name,
which both include the same part file. The language has a restriction against
having two libraries with the same declared name in the same program *mainly*
to avoid this particular issue, but that still makes offline analysis of the
part file a problem.

Pre-feature part files inherit the entire import scope from the library file.
Each declaration of the library file and each part file is included in the
library’s declaration scope. It’s viable to think of part files as being
textually included in the library file. There is a is even a rule against
declaring a `part` inclusion of the same file more than once, which matches
perfectly with that way of thinking.

## Feature

This feature allows a part file to have `import`, `export` and `part`
directives of its own, where `import` directives only affect the part file
itself, and its transitive part files. A library is defined by the source code
of its library file and *all* transitively included part files, which can be an
arbitrarily deep *tree*. A part file inherits the imports and import prefixes
of its parent file (the library or part file that included it) into its
top-level scope, but can choose to ignore or shadow those using its own
imports.

The design goals and principles are:

*   *Backwards compatible*: If a part file has no `import`, `export` or `part`
    directive, it works just like it always has.
    *   Because of that, it’s always safe to move one or more declarations into
        a new part file. _(Although augmentation declarations modifies that
        slightly.)_
    *   Similarly it’s always possible and safe to combine a part file with no
        `import`s back into its parent file.
*   *Library member declarations are library-global*: All top-level
    declarations in the library file and all transitive part files are equal,
    and are all in scope in every file. They introduce declarations into the
    library’s declaration scope, which is the most significant scope in all
    files of the library. If there is any conflict, top-level declarations win!
*   *The unit of ownership is the library*. It’s quite possible for one part
    file to introduce a conflict with another part file. It always was, but
    there are new ways too. If that happens, the library owner, who most likely
    introduced the problem, is expected to fix it. There is no attempt to hide
    name conflicts between declarations in separate tree-branches of the
    library structure.
*   *Import inheritance is a only suggestion*: Aka. other files’ imports cannot
    break your code (at least if you’re not depending on them). A part file is
    never restricted by the imports it inherits from its parent file. It can
    ignore and override all of them with imports of its own. That allows a
    file, like a macro generated file, to import all its own dependencies and
    be completely self-contained when it comes to imports. _It still needs to
    fit into the library and not conflict with existing top-level names. That’s
    why a macro should document any non-fresh names it introduces, so a library
    using the macro can rename any declarations that would conflict._

### Grammar

We extend the grammar of part files to allow `import`, `export` and `part` file
directives. We allow `part` files directives to use a configurable URI like the
other two. We restrict the `part of` directive to only allow the string version.

```ebnf
-- Changed "<uri>" to "<configurableUri>".
<partDirective> ::= <metadata> `part' <configurableUri> `;'

-- Removed "<dottedIdentifier>" as option, retaining only "<uri>".
<partHeader> ::= <metadata> `part' `of' <uri> `;'

-- Added "<importOrExport>* <partDirective>*"
<partDeclaration> ::=
  <partHeader> <importOrExport>* <partDiretive>* (<metadata>
  <topLevelDeclaration>)* <EOF>
```

The grammar change is small, mainly adding `import`, `export` and `part`
directives to part files.

The change to `part of` directives to not allow a dotted name was made because
we want a part file of a part file to refer back to its parent part file, but a
dotted library name can only refer to a library. _That doesn’t mean that
part-of-dotted-name cannot be supported for part files that are part files of a
library file. It’s also that the Dart team wants to remove the feature, and has
been linting against its use for quite a while already. Dotted names in part-of
being partially incompatible with the new feature just means that now is a good
opportunity to get rid of them._

The change to a configurable URI for `part` files was made because it can ease
one of the shortcomings of using libraries for platform-dependent code: That
other libraries cannot provide implementations for private members, or code
that accesses private members, without duplicating the entire library. With
part files having their own imports, adding configurable URIs for `part`
directives gives a way to avoid that code duplication, possibly even more
conveniently if also using augmentations.

The configurable URI for a `part` works just as for imports and exports, it
chooses the URI that the `part` directive refers to, and after that the
included file works just as any other part file.

It’s a **compile-time error** if a Dart (parent) file with URI *P* has a `part`
directive with a URI *U*, and the source content for the URI *U* does not parse
as a `<partDirective>`, or if its leading `<partHeader>`'s `<uri>` string,
resolved as a URI reference against the URI *U*, does not denote the library of
*P*. _That is, if a Dart file has a part directive, its target must be a part
file whose “part of” directive points back to the first Dart file. Nothing new,
except that now the parent file may not be a library file.)_

### Resolution and scopes (part and import directives)

A pre-feature library defines a *top-level scope* extending the import scope
(all declarations imported by non-prefixed import directives) with a
declaration scope containing all top-level declarations of the library file and
all part files, and all import prefixes declared by the library file. The
import prefixes are added to the same scope as library declarations, and there
is a name conflict if a top-level declaration has the same base name as an
import prefix.

This feature splits the top-level declaration scope from the import prefix
scope to allow a part file to override the import prefix, but not the top-level
declaration.

Each Dart file (library file or part file) defines a _combined import scope_
which combines the combined import scope of its parent file with its own
imports and import prefixes. The combined import scope of a dart files is
defined as:

*   Let *C* be the combined import scope of the parent file, or an empty scope
    if the current file is a library file.
*   Let *I*  be a scope containing all the imported declarations of all
    non-prefixed `import` directives of the current file. The parent scope of
    *I* is *C*.
    *   The import scope are computed the same way as for a pre-feature
        library. The implicit import of `dart:core` only applies to the
        library file. _As usual, it’s a compile-time error if any `import`‘s
        target URI does not resolve to a valid Dart library file._
    *   Let’s introduce *importsOf*(*S*), where *S* is a set of `import`
        directives from a single Dart file, to refer to that computation, which
        introduces a scope containing the declarations introduced by all the
        `import` s (the declarations of the export scope of each imported
        library, minus those hidden by a `show` or `hide` operator, combined
        such that a name conflicts of different declarations is not an error,
        but the name is marked as conflicted in the scope, and then referencing
        it is an error.)
*   Let *P* be a *prefix scope* containing all the import prefixes declared by
    the current file. The parent scope of *P* is *I*.
    *   The *P* scope contains an entry for each name where the current file
        has an `import` directive with that name as prefix, `as name`. (If an
        import is `deferred`, it’s a compile-time error if more than one
        `import` directive in the same file has that prefix name, as usual.
        _It’s not an error if two import deferred prefixes have the same name
        if they occur in different files, other file’s imports are only
        suggestions._)
    *   The *P* scope binds each such name to a *prefix import scope*,
        *P*<sub>*name*</sub>, computed as *importsOf*(*S*<sub>*name*</sub>)
        where *S*<sub>*name*</sub> is the set of import directives with that
        prefix name.
    *   If an import is `deferred`, its *P*<sub>*name*</sub> is a *deferred
        scope* which has an extra `loadLibrary` member added, as usual, and the
        import has an implicit `hide  loadLibrary` modifier.
    *   If *P*<sub>*name*</sub> is not `deferred`, and the parent scope in *C*
        has a non-deferred prefix import scope with the same name,
        *C*<sub>*name*</sub>, then the parent scope of *P*<sub>*name*</sub> is
        *C*<sub>*name*</sub>. _A part file can use the same prefix as a prefix
        that it inherits, because inherited imports are only suggestions. If it
        adds to that import scope, by importing into it, that can shadow
        existing declarations, just like in the top-level declaration scope. A
        deferred prefix import scope cannot be extended, and cannot extend
        another prefix scope, deferred prefix scopes are always linked to a
        single import directive._
    *   _It’s possible to look further up in the import chain *C* for a prefix
        scope to extend. Here it’s chosen that that importing parent file gets
        to decide which names the part file has access to. If it wants to make
        a transitive parent import prefix available, it should just not shadow
        it._

That is: The combined import scope of a Dart file is a chain of the combined
import scopes of the file and its parent files, each step adding two scopes:
The (unnamed, top-level) import scope of the unprefixed imports and the prefix
scope with prefixed imports, each shadowing names further up in the chain.

The *top-level scope* of a Dart file is a library *declaration scope*
containing every top-level library member declaration in every library or part
file of the library. The parent scope of the top-level scope of a Dart file is
the combined import scope of that Dart file. _Each Dart file has its own copy
of the library declaration scope, all containing the same declarations, because
the declaration scopes of different files have different parent scopes._

**It’s a compile-time error ** if any file declares an import prefix with the
same base name as a top-level declaration of the library.

_We have split the prefixes out of the top-level scope, but we maintain that
they must not have the same names anyway. Any prefix that has the same name as
a top-level declaration of the library is impossible to reference, because the
library declaration scope always precedes the prefix scope in any scope chain
lookup. This does mean that adding a top-level declaration in one part file may
conflict with a prefix name in another part file in a completely different
branch of the library file tree. That is not a conflict with the “other file’s
imports cannot break your code” principle, rather the error is in the file
declaring the prefix. Other files’ top-level declarations can totally break
your code. Top-level declarations are global and the unit of ownership is the
library, so the library author should fix the conflict by renaming the prefix.
That such a name conflict is a compile-time error, makes it much easier to
detect if it happens._

### Export directives

Any Dart file can contain an `export` directive. It makes no difference which
file an `export` is in, its declarations (filtered by any `hide` or `show`
modifiers) are added to the library’s single export scope, along with those of
any other  `export`s in the library and the non-private declarations of the
library itself. Conflicts are handled as usual (as an error if it’s not the
*same* declaration).

Allowing a part file to have its own export is mainly intended for macro
generated parts and for conditionally included parts, most other libraries will
likely still keep all `export` directives in the library file.

## Terminology

With libraries now being trees of files, not just a single level of parts, we
introduce terminology to concisely express relation of files. (Some of this has
already been defined above, but is also included here for completeness.)

A *Dart file* is a file containing valid Dart source code,
and is identified by its URI.

A Dart file is either a *library file* or a *part file*,
each having its own grammar.

*   _(With this feature those grammars differ only at the very top,
    where a library file can have an optional script tag and an optional
    `library` declaration, and a part file must start with a `part of`
    declaration)_.

We say that a Dart file *includes* a part file, or that the part file
_is included by_ a Dart file, if the Dart file has a `part` directive with a
URI denoting that part file.

*   _It’s a compile-time error if a Dart file has two `part` directives with
    the same URI, so each included part file is included exactly once._
*   _It’s a compile-time error if a `part` directive denotes a file which is
    not a part file._

The *parent file* of a part file is the file denoted by the URI of the
`part of` declaration of the part file. A library file has no parent file.

*   _It’s a compile-time error if a part file is included by any Dart file
    other than the part file’s parent file._
*   The *includes* and *is the parent file of* properties are equivalent for
    the files of a Dart program. A Dart file includes a part file if, and only
    if, the Dart file is the parent file of the part file, otherwise there is a
    compile-time error. (There are no restrictions on the parent file of a part
    file which is not part of a library of a Dart program. Dart semantics is
    only assigned to entire libraries and programs, not individual part files.
    We’ll refer to the relation as both one file being included by another, and
    the former file being the parent (file) of the latter file.

Two or more part files are called *sibling part files* (or just
*sibling parts*) if if they are all included by the same (parent) file.

A file is a *sub-part* of an *ancestor* Dart file, if the file is included by
the Dart file, or if the file is a *sub-part* of a file included by the
*ancestor* Dart file.

*   This “sub-part/ancestor” relation is the transitive closure of the
    *included by* relation. We’ll refer to it by saying either that one Dart
    file is an ancestor file of another part file, or that a part file is a
    sub-part of another Dart file.
*   _It’s a compile-time error if a part file is a sub-part of itself._
    That is, if the *includes* relation has a cycle. This is not a *necessary*
    error from the language's perspective, since no library can contain such a
    part file without introducing another error; at the first `part` directive
    which includes a file from the cycle, the including file is not the parent
    of that file.
    The rule is included to as a help to tools that try to analyzer Dart code
    starting at individual files, they can then assume that either a part file
    has an ancestor which is a library file, or there is a compile-time error.
    Or an infinite number of part files.)

The *sub-tree* of a Dart file is the set of files containing the file itself
and all its sub-parts. The *root* of a sub-tree is the Dart file that all other
files in the tree are in the sub-parts of.

We say that a Dart file *contains* another Dart file if the latter file is in
the sub-tree of the former (short for “the sub-tree set of the one file
contains the other file”).

The *least containing sub-tree* or *least containing file* of a number of
Dart files from the same library, is the smallest sub-tree of the library
which contains all the files, or the root file of that sub-tree.
Here _least_ is by set inclusion, because any other sub-tree that contains the
two files also contains the entire smallest sub-tree. _A tree always has a
least containing sub-tree for any set of nodes._

*   The least containing file of *two* distinct files is either one of those
    two files, or the two files are contained in two *distinct* included part
    files. The least containing file is the only file which contains *both*
    files, and not in the *same* included file.
*   Generally, the least containing file of any number of files
*   is the *only* file which contains all the files, and which does not contain
    them all in one sub-part.
    _(If a file contains all the original files, then either they are in the
    same included part file, and then that part file is a lesser containing
    file, or not all are in the same included part file, so either in different
    included parts or some in the file itself, and then no included part file
    contains all the files, so there is no lesser containing file.)_

The *files of a library* is the entire sub-tree of the defining library file.
It contains the library file.
The sub-tree of a part file of a library contains no library file.

In short:

*   A *parent* file *includes* a part file. Adding transitivity and reflexivity,
    an *ancestor* file *contains* any *sub-part* file, and itself.
*   A Dart file defines a *sub-tree* containing itself as *root*
    and all the *sub-trees* of all the part files it *includes*.
    As a tree, it trivially defines a partial ordering of files with a least
    upper bound, which is the _least containing file_.

## Language versioning and tooling

This feature is language versioned, so no existing code is affected at launch.

The feature has no effect at the library boundary level, meaning the export
scope of a library, so pre-feature and post-feature libraries can safely
coexist.

As with pre-feature libraries, all files in a library must have the same
associated *language version*. If any file has a language-version override
marker (a line like `// @dart=3.12` before any Dart code), then *every file* in
the library *must* have a language override marker. _(And they must still have
the same language version, so it must be the same marker.)_

Also, every file in a library must belong to the same *package*. The Dart
language itself has no notion of packages, but the tooling uses a file’s
package to derive its default language version. The Dart SDK will require that
all files in a package belong to the same library, ensuring that they’ll always
have the same language version. Also, if the library file is inside the `lib/`
directory, so it has a `package:` URI as canonical URI, then so must all its
sub-part files. We haven’t specified these requirements before,
it has always been assumed, but technically it is possible to write programs
where a part belongs to different package than their library. The Dart SDK’s
multi-language-version support, which based on files belonging to packages,
will not support libraries that are not entirely in a single package.

That is, the extra restrictions enforced by Dart tools are:

*   If any file of a library has a `// @dart=` language version marker, then
    *all* files in that library must have a language version marker with
    *the same* language version.
    Or, phrased differently starting at the root:
    *   If a library file has a language version marker,
        then it’s a compile-time error for any sub-part file
        to not have the same language version marker.
    *   If a library file has no language version marker,
        then it’s a compile-time error for any sub-part file
        to have a language version marker.

*   If a library file belongs to a package,
    then all its sub-part files must belong to the same package.
*   If a library file has a `package:` URI (is located inside the package-URI
    directory specified by the package configuration, usually
    `"packageUri": "lib/"` of a `package_config.json` file),
    then all its sub-part files must also be inside that package-URI directory.
    *   _A library file outside of the `lib/` directory can technically have
        part files inside the `lib/` directory, specified using `package:`
        URIs, but those part files can only be included in a program by
        referencing the library file, which means the part files might as well
        be placed outside of the `lib/` directory._

### User guidance tooling

The analyzer and analysis server needs to support and understand the new
feature. No new user-facing features are needed, but some error handling
and user guidance may be useful. The following are ideas for
hypothetical features that the tool may choose to add.

##### Annotations applying to sub-tree

Usually an annotation placed on the `library` declaration applies to the entire
library. There are no annotations that are defined as applying only to a single
file, or to be placed on `part of ` declarations.

It might be useful to have some annotations that apply either to an entire
sub-tree or to a single file. The individual annotations should decide how they
can be applied.

It may very well be that annotations affecting declarations (which is typically
what annotations on library declarations do) have no benefit from being limited
based on something as (so far) semantically arbitrary as source ordering.

##### An `// ignore` applying to a sub-tree

The analyzer recognizes `// ignore: …` comments as applying to the same or next
line. For ignoring multiple warnings, there is a `// ignore_for_file: …`
comment which covers the entire file.

It can be considered whether to have an `// ignore_for_all_files: …` (or a
better name) which applies to an entire subtree, not just the current file.

It may very well be better to *not* that, and have each sub-part write its own
`// ignore_for_file: ...`. That makes it very easy to see which ignores are in
effect for a file.

##### Invalid part file structure correction

When analyzing an incomplete or invalid Dart program, any and all of the compile-time errors above may apply.

It’s possible to have part files with parent-file cycles, part files with a
parent URI which doesn’t denote any existing file, or files with a `part`
directive with a URI that doesn’t denote any existing file. This isn’t *new* to
enhanced part files, other than the cycle where it used to immediately be an
error if the parent file wasn’t a library file.

If a tool can see that one Dart file includes a part file, and the part file
has a non-existing file URI as its parent file, it could be a quick-fix to
update the URI in the part file’s `part of` directive to point to the file that
includes it.

Similarly if a part file’s parent file doesn’t include the part file, then a
`part` directive can be added, or if the parent file has a `part ` directive
which doesn’t point to an existing file (and maybe only if the name is
*similar*), then that part directive can be updated to point to the part file.

### Migration

The only non-backwards compatible change is to disallow `part of dotted.name;`.
That use has been discouraged by the
[`use_string_in_part_of_directives`][string_part_of_lint] lint, which was
introduced with Dart 2.19 in January 2023, and has been part of the official
“core” Dart lints since June 2023. The “core” lints are enforced more strongly
than the “recommended” lints, including counting against Pub score, so any
published code has had incentive to satisfy the lint.

The lint has a quick-fix, so migration can be achieved by enabling the lint
(directly, or by including the “recommended” or “core” lint sets, which is
already itself recommended practice) and running `dart fix`, which will change
any `part of dotted.name;` to the future-safer `part of 'parent_file.dart';`.

All in all, there is very little expected migration since all actively
developed code, which is expected to use and follow recommended or core lints,
will already be compatible.

[string_part_of_lint]: https://dart.dev/tools/linter-rules/use_string_in_part_of_directives	"use_string_in_part_of_directives lint"

## Changelog

### 1.0

*   Initial version. The corresponding version of [Augmentations], which refers
    to part files with imports, is version 1.21.

*   Combines augmentation libraries, libraries and part files into just
    libraries and part files, where the part files can have import, export and
    further part directives. Those part directives can use configurable imports.
*   Is backwards compatible with existing `part` files (other than disallowing
    the long-discouraged `part of dotted.name;`).
*   Unlike augmentation libraries, improved part files inherit the imports of
    their parent file(s). A part file can still choose to ignore that and
    import all its own dependencies directly. The feature ensures that
    inherited imports cannot get in the way of a part file which wants to do.

### Augmentations 1.20

Original specification which this feature was extracted from.
