# Implementation Plan for "Spread Collections"

Owner: rnystrom@google.com ([@munificent](https://github.com/munificent/) on GitHub)

Relevant links:

* [Tracking issue](https://github.com/dart-lang/language/issues/47)
* [Proposal](https://github.com/dart-lang/language/blob/master/accepted/2.3/spread-collections/feature-specification.md)

## Phase 0 (Prerequisite)

### "spread-collections" Experimental flag

The implementation of this feature should be hidden behind an [experiment
flag][]. Tools must be passed the flag `--enable-experiment=spread-collections`
to enable the feature.

[experiment flag]: https://github.com/dart-lang/sdk/blob/master/docs/process/experimental-flags.md

While this feature is under development, individual tools may have incomplete or
changing implementations behind the flag. When all tools have completely
implemented the feature, the the feature will be enabled by default, and the
flag removed in a stable release.

### Tests

The language team adds tests for the feature.

## Phase 1 (Foundation)

### CFE

The CFE implements parsing the new syntax, type checking it, and compiling it to
Kernel. Since the CFE will be implementing constant evaluation, it also
implements evaluating `...` in constant collections.

This feature can likely be implemented entirely in the front end, so back-end
support may not be needed. If it does require Kernel changes, the back end will
need to handle those changes.

### Analyzer

The analyzer implements parsing the new syntax, type checking it, and
evaluating `...` in constant collections.

## Phase 2 (Tool Implementation)

### dart2js

If the feature is handled by the front end, there may be no dart2js work.
Otherwise, dart2js may need to handle any Kernel changes or otherwise add
support for this.

### Dartfmt

Define and implement formatting rules for the new syntax. Add formatting tests.

### DDC

If this feature can be implemented entirely in the front end with no Kernel
changes, and DDC is entirely onto the CFE, then no DDC changes may be needed.
Otherwise, DDC may need to handle any Kernel changes or otherwise add support
for this.

DDC may need to support canonicalizing constant collections with spread
operators.

### IntelliJ

Update the IntelliJ parser to handle the new syntax (this has some lead time,
so needs to be done early).

### Analyzer / analysis server

There a are a handful of usability features that would be nice:

*   Add a "quick fix" to turn common idioms into uses of the spread operator
    like:

    ```dart
    [a, b]..addAll(c)..add(d);

    // Into:
    [a, b, ...c, d]
    ```

    Depending on how dartfix is coming along, this could be added to that.

*   Auto-complete should gracefully handle the user typing `...` inside a
    collection literal if it doesn't already.

*   Good error messages if a user tries to use `...` outside of a collection
    literal, explaining where the syntax is allowed.

### dartfix

Possibly, expose the quick fix from above.

### linter

Add a lint rule (`prefer_spread_operators`?), corresponding to the analyzer
code assist that flags opportunities to use spreads.

### VM

If the feature is handled by the front end, there may be no VM work. Otherwise,
the VM may need to handle any Kernel changes or otherwise add support for this.

### Co19 tests

The co19 team can start implementing tests early using the experimental flag.
Those tests should not be run by default until the feature has been released.

## Phase 3 (Release)

### Enabling

The language team updates the experimental flag `spread-collections` to always
be enabled and no longer be available to users, and releases this update in the
next stable Dart release.

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
