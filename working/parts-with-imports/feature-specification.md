# Parts with Imports

Authors: rnystrom@google.com, jakemac@google.com, lrn@google.com

Version: 1.3 (See [Changelog](#Changelog) at end)

Experiment flag: enhanced-parts

This is a standalone definition of _enhanced part files_, where the title of
this document/feature is highlighting only the most prominent part of the
feature. This document is extracted and distilled from the [Augmentations][]
specification. The original specification introduced special files for
declaring augmentations, and this document is the unification of those files
with the existing `part` files, generalizing library files, part files and
augmentation files into a consistent and (almost entirely) backwards compatible
extension of the existing part files.

Because of that, the motivation and design is based on the needs of
meta-programming and augmentations. It's defined as a stand-alone feature, but
design choices were made based on the augmentations and macro features,
combined with being backwards compatible.

[Augmentations]: ../augmentations/feature-specification.md "Augmentations feature specification"

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
import itself. There have been requests to either loosen the "library privacy"
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
`part of library.name;` notation ([#2358][]). It won't work with some of
the added features, and the Dart language is moving away from
giving libraries names.

[#252]: https://github.com/dart-lang/language/issues/252    "Partial classes and methods"
[#678]: https://github.com/dart-lang/language/issues/678    "Partial classes"
[partial]: https://github.com/jaredpar/csharplang/blob/partial/proposals/extending-partial-methods.md
[#3125]: https://github.com/dart-lang/language/issues/3125  "Shared library privacy"
[#519]: https://github.com/dart-lang/language/issues/519    "Allow imports in part files"
[#2358]: https://github.com/dart-lang/language/issues/2358  "Disallow part of dotted.name"

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
the language itself uses to identify files and libraries. It's technically
possible to have two separate libraries with the same declared library name,
which both include the same part file. The language has a restriction against
having two libraries with the same declared name in the same program *mainly*
to avoid this particular issue, but that still makes offline analysis of the
part file a problem.

Pre-feature part files inherit the entire import scope from the library file.
Each declaration of the library file and each part file is included in the
library's declaration scope. It's viable to think of part files as being
textually included in the library file. There is even a rule against
declaring a `part` inclusion of the same file more than once, which matches
perfectly with that way of thinking.

## Feature

This feature allows a part file to have `import`, `export` and `part` directives
of its own, where `import` directives only affect the part file itself, and its
transitive part files. A library is defined by the source code of its library
file and *all* transitively included part files, which can be an arbitrarily
deep *tree*. A part file inherits the imported declarations and import prefixes
of all its transitive parent files (the library or part files that included it),
but can choose to ignore or shadow those using its own imports.

The design goals and principles are:

*   *Backwards compatible*: If a part file has no `import`, `export` or `part`
    directive, it works just like it always has.
    *   Because of that, it's always safe to move one or more declarations into
        a new part file.
    *   Similarly it's always possible and safe to combine a part file with no
        `import`s back into its parent file.

    _(Augmentations modify both of these properties slightly, because order of
    declarations may also matter.)_

*   *Library member declarations are library-global*: All top-level declarations
    in the library file and all transitive part files are equal, and are all in
    scope in every file. They introduce declarations into the library's
    declaration scope, which is the most significant scope in all files of the
    library. If there is any conflict with imported names, top-level
    declarations win!

*   *The unit of ownership is the library*. It's quite possible for one part
    file to introduce a conflict with another part file. It always was, but
    there are new ways too. If that happens, the library owner, who most likely
    introduced the problem, is expected to fix it. There is no attempt to hide
    name conflicts between declarations in separate tree-branches of the
    library structure.

*   *Import inheritance is a only suggestion*: Aka. ancestor files' imports
    shouldn't break your code (if you're not depending on them).
    A part file is never _restricted_ by the imports inherited from its parent file.
    It can ignore and override all of them with imports of its own, and by making
    explicit references to its own imported names.
    That allows such a file, for example code-generated file, to import all its
    own dependencies and be completely self-contained when it comes to imports.
    _It still needs to fit into the library and not conflict with existing
    top-level names. That's why a code generator should document any non-fresh
    names it introduces, so a library using the macro can rename any declarations
    that would conflict._
    Because adding more extension declarations can affect the resolution of
    implicit extension applications, a part file which aims to be completely
    independent of its parent imports, should import its own extensions
    *and* use only explicit extension applications of those.
    _That is something code generation may want to do anyway. It doesn't care
    about the verbosity, and it's safe against any later changes._

    *   The ability to be indpendent of parent file imports should make it
        possible to convert an existing library into a part file of another library.
        Since a library is self-contained and imports all external names that it
        refers to, making it a part file will not cause any conflict due to
        inherited imports. _(Obviously still need to avoid conflicts with
        top-level declarations, and it may need to make extension applications
        explicit in the rare case when the library already contains a different
        applicable extension that is equally or more specific.)_
    *   And similarly, if a part file *is* self-contained, it can be converted
        into a separate library and imported back into the original library, or
        it can be moved to another position in the part tree hierarchy. _(Again
        augmentations introduce complications, which is why it's usually a good
        idea to keep all augmentations inside the same part sub-tree)._

### Grammar

We extend the grammar of part files to allow `import`, `export` and `part` file
directives. We restrict the `part of` directive to only allow the string version.

```ebnf
-- Removed "<dottedIdentifier>" as option, retaining only "<uri>".
<partHeader> ::= <metadata> `part' `of' <uri> `;'

-- Added "<importOrExport>* <partDirective>*"
<partDeclaration> ::=
  <partHeader> <importOrExport>* <partDirective>* (<metadata>
  <topLevelDeclaration>)* <EOF>
```

The grammar change is small, mainly adding `import`, `export` and `part`
directives to part files.

The change to `part of` directives, to not allow a dotted name, was made because
we want a part file of a part file to refer back to its parent part file, but a
dotted library name can only refer to a library. _That doesn't mean that
part-of-dotted-name cannot be supported for part files that are part files of a
library file. It's also that the Dart team wants to remove the feature, and has
been linting against its use for quite a while already. Dotted names in part-of
being partially incompatible with the new feature just means that now is a good
opportunity to get rid of them._

It's a **compile-time error** if a Dart (parent) file with URI *P* has a `part`
directive with a URI *U*, and the source content for the URI *U* does not parse
as a `<partDeclaration>`, or if its leading `<partHeader>`'s `<uri>` string,
resolved as a URI reference against the URI *U*, does not denote the library of
*P*. _That is, if a Dart file has a part directive, its target must be a Dart
part file whose "part of" directive points back to the first Dart file.
Nothing new, except that now the parent file may not be a library file._

### Resolution and scopes (part and import directives)

Imports, and import prefixes, of a parent file can now be shadowed by
part files. To support that, each file gets its own import scope,
import prefix scope and top-level scope.

A _pre-feature library_ has only an _import scope_ with the namespace of
all names imported by non-prefixed imports, which is the parent scope of the 
*top-level scope* with a namespace containing all top-level declarations of
the library, from both library file and part files, _and_ all prefix names
of prefixed imports in the library file.
The import prefixes are added to the same scope as library declarations, 
and it is a normal scope-name-conflict if a top-level declaration
has the same base name as an import prefix.
The same scope is used by all files of the library.

A _post-feature library_ splits the top-level declaration scope from the
import prefix scope to allow a part file to inherit and override the
import prefixes of its parent file separately from the shared top-level
declarations.

Each Dart file (library file or part file) defines a _combined import scope_
which extends the combined import scope of its parent file with its own
imports and import prefixes. _It is this combined import scope that
sub-parts inherit and extend_. The combined import scope of a Dart file *F* is
defined as:

*   First we'll give a name to a namespace created by import statements that
    are imported into the same namespace.
    Define *importsOf*(*S*), where *S* is a set of `import` directives from
    a single Dart file, as the namespace containing the exported declarations
    of each library imported by one of those directives, minus those hidden
    by a `show` or `hide` operator on the import directive.
    Solve name conflicts the same ways as today; different declarations
    with the same name makes the name "conflicted" unless exactly one
    of those declarations is a non-platform-library declaration, in which case
    the name will denote that declaration in the namespace. _It's then a
    compile-time error if an identifier denotes a conflicted namespace entry._
    _(This is the existing way to combine imported names from multiple imports
    into a single namespace, we're just giving it a name.)_
*   Let *C* be the combined import scope of the parent file of *F*,
    or an empty scope if *F* is a library file.
*   Let *I*, the *import scope* of *F*, be a scope with *C* as parent scope
    and _importsOf_(*NP*) as namespace, where *NP* is the set of unprefixed
    import directives of *F*.
    If *F* is a library file, and *F* does not contain any import of `dart:core`,
    a synthetic `import 'dart:core';` directive is added to *NP*.
    *   The import namespace is computed the same way as for a pre-feature
        library. The implicit import of `dart:core` only applies to the
        library file. _As usual, it's a **compile-time error** if any `import`‘s
        target URI does not resolve to a valid Dart library file._
*   Let *P*, the *prefix scope* of *F*, be a scope with *I* as parent scope
    and a namespace containing every import prefix declared by an import
    declaration of *F*.
    *   The *P* scope contains an entry for each name where the current file
        has an `import` directive with that name as prefix. If an
        import is `deferred`, it's a **compile-time error** if more than one
        `import` directive in the same file has that prefix name, as usual.
        _It's not an error if two deferred import prefixes have the same name
        if they occur in different files, other file's imports are only
        suggestions._)
    *   The *P* scope binds each such name to a *prefix import scope*,
        *P*<sub>*name*</sub>, computed as *importsOf*(*S*<sub>*name*</sub>)
        where *S*<sub>*name*</sub> is the set of import directives of *F*
        with that prefix name.
    *   If an import is `deferred`, its *P*<sub>*name*</sub> is a *deferred
        scope* which has an extra `loadLibrary` member added, and the
        import implicitly hides any member named `loadLibrary` in the
        (singular) imported library's export scope _(as usual)_.
    *   If *P*<sub>*name*</sub> is _not_ `deferred`, and the parent scope in *C*
        has a non-deferred prefix import scope with the same *name*,
        *C*<sub>*name*</sub>, then the parent scope of *P*<sub>*name*</sub> is
        *C*<sub>*name*</sub>.
        _A part file can use the same prefix as a prefix that it inherits,
        because inherited imports are only suggestions.
        If it adds to that import scope, by importing into it, that can shadow
        existing declarations, just like in the top-level declaration scope.
        A deferred prefix import scope cannot be extended, and cannot extend
        another prefix scope. Deferred prefix scopes are always linked to a
        single import directive, and a single library, which can be loaded
        individually of any other import._
    *   Otherwise *P*<sub>*name*</sub> has no parent scope.
        _If the the parent's combined import scope, *C*, has an non-prefix
        declaration for a prefix name in *F*, it would be possible to look
        further up in the import chain of *C*, past the shadowing import,
        for a prefix scope to extent. We will not do that. A part file's
        parent file's combined import scope is the abstraction that represents
        every import above it in the tree._
* The combined import scope of *F* is the scope chain starting with *P*.

That is: The combined import scope of a Dart file is a chain of prefix
scope, the import scope and the the combined import scope chain of its
parent file. Each part file level adds two scopes to the chain,
each able to shadow names in its parent scope.

The *top-level namespace* of a Dart library is a *declaration namespace*
containing every top-level library member declaration in every library or part
file of the library. 
The *top-level scope* of *F* has the top-level namespace of the library
as namespace, and the combined import scope of *F* as parent scope.
_Each Dart file has its own scope containing the top-level namespace,
all containing the same declarations. The top-level declaration scopes
of different files have different parent scopes, allowing each file
to have its own imports, but always letting the library's own declarations
shadow any import._

It's a **compile-time error** if any file declares an import prefix with the
same base name as a top-level declaration of the library.

_We have split the prefixes out of the top-level scope, but we maintain that
they must not have the same names anyway. Not because it's a problem for the
compiler or language, but because it's probably a sign of a user error.
Any prefix that has the same name as a top-level declaration of the library
is impossible to reference, because the library declaration scope
always precedes the prefix scope in any scope chain lookup.
This does mean that adding a top-level declaration in one part file may
conflict with a prefix name in another part file in a completely different
branch of the library file tree. That is not a conflict with the "other file's
imports cannot break your code" principle, rather the error is in the file
declaring the prefix. Other files' top-level declarations can totally break
your code. Top-level declarations are global and the unit of ownership is the
library, so the library author should fix the conflict by renaming the prefix.
That such a name conflict is a compile-time error, makes it easier to
detect when it happens._

#### Resolving implicitly applied extensions

The only change to implicit extension application in this feature
is in the definition of whether an extension is *available*.
Whether an extension is *applicable*, its *specificity* if applicable,
and how that is used to to choose between multiple available and applicable
extensions is unchanged.

An extension declaration being *available* has been defined as being
declared or *imported* by the current library.
Being imported by a library means that the library has at least one
import directive which *imports the extensions*, which again means that it
imports a library which has the extension declaration in its export scope,
and the import directive does not have a `show` or `hide` combinator
which hides the name of the extension declaration.

With this feature, imports are not global to the entire library,
and neither is extension availability.

Extension availability is defined *per file*, and an extension
is available *in a Dart file* if any of:
* The extension is declared by the library of the Dart file.
* The extension is available *by import* in the Dart file.

where an extension is available by import in a Dart file if any of:
* That file contains an import directive which *imports the extension*.
* That file is a part file and the extension is (recursively) available
  by import in its parent file.

(One way to visualize the availability is to associate declared
or imported extensions with scopes. If a file has an import directive
which imports an extension, the extension is associated with the
import scope or prefix scope of that file, depending on whether
the import is prefixed or not. A declaration in the library itself
is associated with the top-level scope of each file.
Then an extension is available in a file if it is associated with
any scope in the top-level scope chain of that file.)

There is no attempt to *prioritize* available extensions based on
where they are imported. Every extension imported or declared in the
file's top-level scope chain is equally available.

It is not possible to *hide* an extension from a part file, if 
the extension is available in the parent file.
That means that a parent file import *can* break a part file
by importing another applicable extension.

_Conflicts a must resolved as usual: Avoid importing one extension,
if it isn't used (which can now mean moving its import and use to a sibling
part file), use a more precise receiver type if possible and it
solves the problem, or use an explicit extension application._

_It is possible for an extension declaration to be available,
and not be accessible by name. An extension imported with a prefix 
in a parent file may have the entire prefix shadowed by an import
in the current file. That does not make the extension unavailable.
This is not new, extensions could always be shadowed by library
declarations, or be imported with a name conflict,
and they would still be available for implicit use._

### Export directives

Any Dart file can contain an `export` directive. It makes no difference which
file an `export` is in, its exported declarations (filtered by any `hide` or
`show` combinators) are added to the library's single export scope,
along with those of any other `export` directives in the library and
the all non-private declarations of the library itself. Conflicts are handled
as usual (as a compile-time error if it's not the *same* declaration).

_Allowing a part file to have its own export is mainly for consistency.
Most libraries will likely keep all `export` directives in the library file,
but generated part files may want to, for example, re-export declarations of
framework types that are exposed by their generated code._

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

*   _It's a **compile-time error** if a Dart file has two `part` directives with
    the same URI, so each included part file is included exactly once._
*   _It's a **compile-time error** if a `part` directive denotes a file which is
    not a Dart part file._

The *parent file* of a part file is the file denoted by the URI of the
`part of` declaration of the part file. A library file has no parent file.

*   _It's a **compile-time error** if a part file is included by any Dart file
    other than the part file's parent file._
*   The *includes* and *is the parent file of* properties are equivalent for
    the files of a valid Dart program. A Dart file includes a part file if,
    and only if, the Dart file is the parent file of the part file, otherwise
    there is a **compile-time error**.
    _(There are no restrictions on the parent file of a part file which is not
    part of a library of a Dart program. Dart semantics is only assigned to
    entire libraries and programs, not individual part files.)_
    We'll refer to this relation as both one file being included by another, and
    the former file being the parent (file) of the latter file.

Two or more part files are called *sibling part files* (or just
*sibling parts*) if if they are all included by the same (parent) file.

A file is a *sub-part* of an *ancestor* Dart file, if the file is included by
the Dart file, or if the file is a *sub-part* of a file included by the
*ancestor* Dart file.

*   This "sub-part/ancestor" relation is the transitive closure of the
    *included by* relation. We'll refer to it by saying either that one Dart
    file is an ancestor file of another part file, or that a part file is a
    sub-part of another Dart file.
*   <a name="part_cycle"></a>_It's a **compile-time error** if a part file is
    a sub-part of itself._
    That is, if the *includes* relation has a cycle. _This is not a *necessary*
    error from the language's perspective, since no library can contain such a
    part file without introducing another error; at the first `part` directive
    reachable from a library file which includes a file from the cycle,
    the including file is not the parent of that file._
    _The rule is included as a help to tools that try to analyzer Dart code
    starting at individual files, they can then assume that either a part file
    has an ancestor which is a library file, or there is a **compile-time error**.
    Or an infinite number of part files._

The *sub-tree* of a Dart file is the set of files containing the file itself
and all its sub-parts. The *root* of a sub-tree is the Dart file that all other
files in the tree are in the sub-parts of.

We say that a Dart file *contains* another Dart file if the latter file is in
the sub-tree of the former (short for "the sub-tree set of the one file
contains the other file"). 
_A file containing another is equivalent to the former being an ancestor
of the latter._

The *least containing sub-tree* or *least containing file* of a number of
Dart files from the same library, is the smallest sub-tree of the library
which contains all the files, or the root file of that sub-tree.
Here _least_ is by set inclusion, because any other sub-tree that contains the
two files also contains the entire smallest sub-tree. _A tree always has a
least containing sub-tree for any set of nodes._

*   The least containing file of *two* distinct files is either one of those
    two files, or it's the only file where file which
    contains *both* files, and not in the *same* included file.
*   Generally, the least containing file of any number of distinct files
    is the *only* file which contains all the files, and which does not contain
    them all in one sub-part.
    _(If a file contains all the original files, then either they are in the
    same included part file, and then that part file is a lesser containing
    file, or not all are in the same included part file, so either in different
    included parts or some in the file itself, and then no included part file
    contains all the files, so there is no lesser containing file.)_

The *files of a library* is the entire sub-tree of the defining library file,
and the only subtree which contains the library file.
The sub-tree of a part file of a library contains only part files.

In short:

*   A *parent* file *includes* a part file. Adding transitivity and reflexivity,
    an *ancestor* file *contains* any *sub-part* file, and itself.
*   A Dart file defines a *sub-tree* containing itself as *root*
    and all the *sub-trees* of all the part files it *includes*.
    As a tree, it trivially defines a partial ordering of files with a least
    upper bound, which is the _least containing file_.

## Language versioning and tooling

Dart language versioning is an extra-linguistic feature which allows the SDK
tooling to compile programs containing libraries written for different versions
of the language. As such, the language semantics (usually) do not refer to
language versions at all.

Similarly the language has no notion of a "package", but tooling does consider
Dart files to belong to (at most) one package, and some of the files as
"having a `package:` URI". This information is written into a metadata file,
`package_config.json` that is also used to resolve `package:` URIs, and to
assign default language versions to files that belong to a package.

Because of that, the restrictions in this section are not *language* rules,
instead they are restrictions enforced by the *tooling* in order to allow
multi-language-version programs to be compiled.

### Pre-feature code interaction and migration

This feature is language versioned, so no existing code is affected at launch.

The only non-backwards compatible change is to disallow `part of dotted.name;`.
That use has been discouraged by the
[`use_string_in_part_of_directives`][string_part_of_lint] lint, which was
introduced with Dart 2.19 in January 2023, and has been part of the official
"core" Dart lints since June 2023. The "core" lints are enforced more strongly
than the "recommended" lints, including counting against Pub score, so any
published code has had incentive to satisfy the lint.

The lint has a quick-fix, so migration can be achieved by enabling the lint
(directly, or by including the "recommended" or "core" lint sets, which is
already itself recommended practice) and running `dart fix`, which will change
any `part of dotted.name;` to the future-safer `part of 'parent_file.dart';`.

All in all, there is very little expected migration since all actively
developed code, which is expected to use and follow recommended or core lints,
will already be compatible.

[string_part_of_lint]: https://dart.dev/tools/linter-rules/use_string_in_part_of_directives "use_string_in_part_of_directives lint"

We will enforce a set of rules that weren't as clearly defined before
(see next section), and therefore maybe not strictly enforced, so there is a
risk that some pathologically designed library may break one of those rules.
Other than that, a pre-feature library can be used as post-feature library as
long as it satisfies these very reasonable rules.

The feature has no effect at the library boundary level, meaning the export
scope of a library, so pre-feature and post-feature libraries can safely
coexist. A library can start using the feature without any effect on client
libraries. There is no need to worry about migration order.

### Explicit sanity rules

The following rules are rules enforced by tooling, not the language, since they
rely on features that are not part of the language (files having a language
version, a language version marker, or belonging to a package).

All pre-feature libraries should already be following these rules, which exist
mainly ensure that different files of a library will *always* have the same
language versions. _Some of these rules have not all been expressed explicitly
before, because they are considered blindingly obvious. We're making them
explicit here, and will enforce the rules strictly for post-feature code, if we
didn't already._

*   It's a **compile-time error** if two Dart files of a library do not have the
    same language version. _All Dart files in a library must have the same
    language version._ Can be expressed locally as:
    *   It's a **compile-time error** if the associated language version of a part
        file is not the same as the language version of its parent file.

*   It's a **compile-time error** if any file of a library has a
    language-version override marker (a line like `// @dart=3.12` before any
    Dart code), and any *other* file of the same library does not have a
    language-version override marker. _While it's still possible for that
    library to currently have the same language version across all files, that
    won't stay true if the default language version for the package changes._
    Can be expressed locally as:

    *   If a part file has a language version marker, then it's a compile-time
        error if its parent files does not have a language version marker. _The
        version marker it has must be for the same version due to the previous
        rule._

    *   If a part file has no language version marker, then it's a compile-time
        error if its parent file has a language version marker.

*   It's a **compile-time error** if two Dart files of a library do not belong
    to the same package. _Every file in a library must belong to the same
    package to ensure that they always have the same default language version.
    It's also likely to break a lot of assumptions if they don't._ Can be
    expressed locally as:

    *   It's a **compile-time error** if a part file does not belong to the same
        package as its parent file.

    The Dart SDK's multi-language-version support, which based on files
    belonging to packages, will not support libraries that are not entirely in a
    single package.

*   We *may* want to also make it a **compile-time** error if two Dart files of
    a library are not both inside the `lib/` directory or both outside of it.
    _Having a parent file inside `lib/` with a part file outside will not
    compile if the parent file is accessed using a `package:` URI. Having a
    parent file outside of `lib/` with a part file inside works, but the part
    file might as well be outside since the only way to use it is to go through
    the parent file._ The only reason to maybe not enforce this rule would be a
    file inside `lib/` that is *never* accessed using a`package:` URI, and which
    depends on files outside of `lib/` for something. If some frameworks do
    that, maybe a Flutter `main` file, then we should just keep giving warnings
    about the pattern. The `lib/` directory should be self-contained because all
    libraries in it can be accessed by other packages, and no other files can.

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
based on something as (so far) semantically arbitrary as source ordering. But on
the other hand, users may choose to order source depending on properties that
annotations apply to. _The analyzer may want to review annotations that apply to
a library for whether they can reasonably apply to any sub-tree of parts. For
example `@Deprecated(…)` could apply to every member in a sub-tree, allowing a
library to keep its deprecated API, and that APIs necessary imports,
separate from the rest, so that it can all be removed as a single operation,
and then marking all that API as deprecated with one annotation._

##### An `// ignore` applying to a sub-tree

The analyzer recognizes `// ignore: …` comments as applying to the same or next
line. For ignoring multiple warnings, there is a `// ignore_for_file: …` comment
which covers the entire file. There is no `ignore_for_library` that would apply
to the entire library, including parts.

It can be considered whether to have an `// ignore_for_all_files: …` (or a
better name) which applies to an entire sub-tree, not just the current file, and
not the entire library. It would apply to the entire library if applied to the
library file.

It may very well be better to *not* that, and have each sub-part write its own
`// ignore_for_file: ...`. That makes it very easy to see which ignores are in
effect for a file.

##### Invalid part file structure correction

When analyzing an incomplete or invalid Dart program, any and all of the
compile-time errors above may apply.

It's possible to have part files with parent-file cycles, part files with a
parent URI which doesn't denote any existing file, or files with a `part`
directive with a URI that doesn't denote any existing file. This isn't *new* to
enhanced part files, other than the cycle where it used to immediately be an
error if the parent file wasn't a library file.

If a tool can see that one Dart file includes a part file, and the part file
has a non-existing file URI as its parent file, it could be a quick-fix to
update the URI in the part file's `part of` directive to point to the file that
includes it.

Similarly if a part file's parent file doesn't include the part file, then a
`part` directive can be added, or if the parent file has a `part ` directive
which doesn't point to an existing file (and maybe only if the name is
*similar*), then that part directive can be updated to point to the part file.

### Migration

The only non-backwards-compatible change is to disallow `part of dotted.name;`.
That use has been discouraged by the
[`use_string_in_part_of_directives`][string_part_of_lint] lint, which was
introduced with Dart 2.19 in January 2023, and has been part of the official
"core" Dart lints since June 2023. The "core" lints are enforced more strongly
than the "recommended" lints, including counting against Pub score, so any
published code has had incentive to satisfy the lint.

The lint has a quick-fix, so migration can be achieved by enabling the lint
(directly, or by including the "recommended" or "core" lint sets, which is
already itself recommended practice) and running `dart fix`, which will change
any `part of dotted.name;` to the future-safer `part of 'parent_file.dart';`.

All in all, there is very little expected migration since all actively
developed code, which is expected to use and follow recommended or core lints,
will already be compatible.

All exsisting valid pre-feature code that is not affected by that
`part of` change, should also be valid post-feature code.

[string_part_of_lint]: https://dart.dev/tools/linter-rules/use_string_in_part_of_directives "use_string_in_part_of_directives lint"

### Development

The experiment name for this feature is `enhanced-parts`.

The augmentations feature does not depend on this feature,
but may interact with it. It may be reasonable to enable this feature's
experiment automatically if the augmentations experiment is enabled.

## Feature Summary

*   **Breaking**: A `part of` file directive cannot use a library name any more.
*   A part file can contain `import`, `export` and `part` directives.
*   Part files of a library must form a tree.
    _A part can, and must, only be part of one parent file._
*   Exports are independent of where they occur, all works like today.
*   Imports are local to the importing file and its subparts,
    and can shadow imports inherited from parent file.
*   Import prefixes shadow normal imports.
    *   They can inherit parent file prefix scopes with the same name.
*   Declarations of all files of a library are in scope in all files.
    *   Shadows any imported name.
    *   Must not shadow any import prefix.
*   Extensions are available in a file if they are imported by the file,
    or if they are available in its parent file.
*   A part file and its parent must be in the same package,
    or not in any package _(aka. "the default package")_.
    *   Neither or both should be inside `lib/` of a Pub package.

It was previously specified that `part` directives could use configurable URIs.
This has been removed, and will be treated as a separate feature.
_It's unclear whether it would require signficant work for the analyzer
to recognize and handle part files that are not part of a parent file due
to configuration, but which would be in another configuration._

## Changelog

### 1.3

*   Make _conditional part directives_ not part of the feature.
    Keep it as an optional extra feature.
*   The experiment flag name is now `enhanced-parts`.    

### 1.2

*   Move to a separate proposal directory and give its own experiment flag
    name ("parts-with-imports").

### 1.1

*   Specifies resolution of implicit extension declarations.
*   Names the feature "Enhanced parts".
*   Fixes some typos.

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
