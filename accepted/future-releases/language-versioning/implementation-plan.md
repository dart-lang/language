# Implementation Plan for "Language Versioning"

Owner: lrn@google.com ([@lrhn](https://github.com/lrhn/) on GitHub)

Relevant links:

* [Tracking issue](https://github.com/dart-lang/language/issues/94)
* [Proposal](https://github.com/dart-lang/language/blob/master/accepted/future-releases/language-versioning/feature-specification.md)

## Phase 0 (Prerequisite)

### "language-versioning" Experimental flag

This feature does not need an [experiment flag] for user consumption.

We may want a flag for testing purposes, but the implementation teams should consider that internally.

[experiment flag]: https://github.com/dart-lang/sdk/blob/master/docs/process/experimental-flags.md

### Tests

The language team specifies the feature.

## Phase 1 (Foundation)

### Pub

The Pub tool already generates the necessary `.dart_tool/package_config.json` file.

### CFE

The CFE already recognizes the `//@dart=2.5` markers, but needs to migrate to using the *new* package configuration file.

The CFE then needs to enable the language version checking and the interaction with experiments flags.

The first features to be affected by language versioning will be any features introduced in the same Dart release as language versioning itself.

The effect of language versioning, at least until the release of NNBD, is simply to disallow some language features. Those language features are non-breaking (NNBD will likely be the first large-scale breaking language change), so it should be possible to parse the entire program unconditionally and simply report on any disallowed features occurring in a library.

This feature can likely be implemented entirely in the front end, so back-end
support may not be needed.

### Analyzer

The analyzer needs to do the same version detection and feature detection as the CFE.

Unlike the CFE, the analyzer may need to look at more than one program at a time, and as such, it may need to have multiple package configurations in play at the same time. For example, a nested package should be recognized so that its libraries are not attributed to the outer package, even if the two packages have separate `.dart_tool/package_config.json` files.

## Phase 2 (Tool Implementation)

### dart2js

If the feature is handled by the front end, there may be no dart2js work.

### Dartfmt

The Dart formatter may not need to recognize language versioning *yet*. 

Formatting a program according to the most recent syntax is sufficient as long as all syntax changes are incremental. Even the planned NNBD change is syntactically incremental, and where it changes semantics of existing code, it does not change how that code should be formatted.

The formatter does need to *retain* any language version markers above all library declarations.

### DDC

If this feature can be implemented entirely in the front end with no Kernel
changes, and DDC is entirely onto the CFE, then no DDC changes may be needed.
Otherwise, DDC may need to handle any Kernel changes or otherwise add support
for this.

Otherwise, if DDC still relies on the Analyzer, it depends on the Analyzer changes.

### Formal specification

Add formal specification to the language specification.

### Cider

There is no new syntax.

### IntelliJ

There is no new syntax.

### Grok

There is no new syntax. If the AST wants to represent the language version or a language version marker explicitly, then Grok needs to support the new AST.

### Analysis server

Update to use the latest analyzer with support for the feature. 

### Atom plug-in

The [Dart Atom plug-in][atom] has a grammar for syntax highlighting Dart code in
Atom. This same grammar is also used for syntax highlighting on GitHub. 

We may want to update this to *hightlight* a language version marker comment.

[atom]: https://github.com/dart-atom/dart

### VS Code

Update the syntax highlighting grammar (likely apply a very similar diff to the Atom grammar above).

### VM

If the feature is handled by the front end, there may be no VM work.

### Co19 tests

It is unclear how to *test* this feature without knowing which other features are gated by the versioning. 

If we have another feature released in the same release, then we can check that enabling language versioning can *disable* the other experiment for libraries with a lower language version marker.

### Usability validation

If usabilility tests haven't been done earlier, do at least some informal
testing on users to see if the limitations on the syntax are frustrating and if
there are improvements we should consider.

### Other Tools

Validate that build systems, code generators, Angular compiler all work and are updated

## Phase 3 (Release)

### Enabling

The feature is enabled in a stable Dart release.

### Use

The Dart team refactors existing code in the SDK and team-maintained packages
to use the new syntax where appropriate.

### Documentation

The language team adds the feature to the CHANGELOG. They write some sort of
announcement email or blog post.

## Phase 4 (Clean-up)

## Timeline

Completion goals for the phases:

*   Phase 0 (Prerequisite): TODO
*   Phase 1 (Foundation): TODO
*   Phase 2 (Tool Implementation): TODO
*   Phase 3 (Release): TODO
*   Phase 4 (Clean-up): TODO