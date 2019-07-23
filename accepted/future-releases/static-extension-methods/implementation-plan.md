# Implementation Plan for "Static Extension Methods"

Owner: lrn@google.com ([@lrhn](https://github.com/lrhn/) on GitHub)

Relevant links:

* [Tracking issue](https://github.com/dart-lang/language/issues/41)
* [Proposal](https://github.com/dart-lang/language/blob/master/accepted/future-releases/static-extension-methods/feature-specification.md)

## Phase 0 (Prerequisite)

### "extension-methods" Experimental flag

The implementation of this feature should be hidden behind an [experiment
flag][]. Tools must be passed the flag
`--enable-experiment=extension-methods` to enable the feature.

[experiment flag]: https://github.com/dart-lang/sdk/blob/master/docs/process/experimental-flags.md

While this feature is under development, individual tools may have incomplete or
changing implementations behind the flag. When all tools have completely
implemented the feature, the the feature will be enabled by default, and the
flag removed in a stable release.

### Tests

The language team adds tests for the feature.
The Co19 team adds tests for the specification.

## Phase 1 (Foundation)

### CFE

The CFE implements parsing the new syntax, type checking it, and compiling it to
Kernel. This includes making `extension` a built-in identifier.

This feature can likely be implemented entirely in the front end, so back-end
support may not be needed. If it does require Kernel changes, the back end will
need to handle those changes.

### Analyzer

The analyzer implements parsing the new syntax and type checking it.
This includes making `extension` a built-in identifier.

## Phase 2 (Tool Implementation)

### dart2js

If the feature is handled by the front end, there may be no dart2js work.
Otherwise, dart2js may need to handle any Kernel changes or otherwise add
support for this.

### Dartfmt

Define and implement formatting rules for the new syntax. Add formatting tests.
The new syntax is very similar to class syntax, so the formatting rules will likely be similar too.

### DDC

If this feature can be implemented entirely in the front end with no Kernel
changes, and DDC is entirely onto the CFE, then no DDC changes may be needed.
Otherwise, DDC may need to handle any Kernel changes or otherwise add support
for this.

Otherwise, if DDC still relies on the Analyzer, it depends on the Analyzer changes.

### Formal specification

Add formal specification to the language specification.

### Cider

Validate Cider support

### IntelliJ

Update the IntelliJ parser to support the new syntax.

### Grok

Update Grok to handle the new AST.

### Analysis server

Update to use the latest analyzer with support for the feature. There are a
handful of usability features that would be nice.

* Completion should suggest applicable extension methods.
* Conflicting extension methods should be reported in a useful way.

It would be excellent to have quick-fixes for:

*   Completing with and importing a known extension which is not imported in the current library
*   Insert an explicit extension type override in case of conflicting extensions, 
    or for available extensions which were not as specific as the one chosen by the language.

### Atom plug-in

The [Dart Atom plug-in][atom] has a grammar for syntax highlighting Dart code in
Atom. This same grammar is also used for syntax highlighting on GitHub. Update
this to handle the new syntax.

[atom]: https://github.com/dart-atom/dart

### VS Code

Update the syntax highlighting grammar to support the new syntax (and,
likely apply a very similar diff to the Atom grammar above).

### VM

If the feature is handled by the front end, there may be no VM work. Otherwise,
the VM may need to handle any Kernel changes or otherwise add support for this.

### Co19 tests

The co19 team can start implementing tests early using the experimental flag.
Those tests should not be run by default until the feature has been released.

### Usability validation

If usabilility tests haven't been done earlier, do at least some informal
testing on users to see if the limitations on the syntax are frustrating and if
there are improvements we should consider.

### Other Tools

Validate that build systems, code generators, Angular compiler all work and are updated

## Phase 3 (Release)

### Enabling

The language team updates the experimental flag `extension-methods` to
always be enabled and no longer be available to users, and releases this update
in the next stable Dart release.

### Use

The Dart team refactors existing code in the SDK and team-maintained packages
to use the new syntax where appropriate.

### Documentation

The language team adds the feature to the CHANGELOG. They write some sort of
announcement email or blog post.

## Phase 4 (Clean-up)

### Remove flag

All tools may now remove the dependencies on the flag in the experiments flag
definition file. When all SDK tools have done so, the flag is removed from the
experiments flag definition file.

## Timeline

Completion goals for the phases:

*   Phase 0 (Prerequisite): TODO
*   Phase 1 (Foundation): TODO
*   Phase 2 (Tool Implementation): TODO
*   Phase 3 (Release): TODO
*   Phase 4 (Clean-up): TODO
