# Implementation Plan for "Control Flow Collections"

Owner: rnystrom@google.com ([@munificent](https://github.com/munificent/) on GitHub)

Relevant links:

* [Tracking issue](https://github.com/dart-lang/language/issues/78)
* [Proposal](https://github.com/dart-lang/language/blob/master/working/control-flow-collections/feature-specification.md)

## Phase 0 (Prerequisite)

### "control-flow-collections" Experimental flag

The implementation of this feature should be hidden behind an [experiment
flag][]. Tools must be passed the flag
`--enable-experiment=control-flow-collections` to enable the feature.

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
implements evaluating `if` in constant collections. This is thus
blocked on the CFE implementing constant evaluation in general.

This feature can likely be implemented entirely in the front end, so back-end
support may not be needed. If it does require Kernel changes, the back end will
need to handle those changes.

### Analyzer

The analyzer implements parsing the new syntax, type checking it, and
evaluating `if` in constant collections.

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

Update the IntelliJ parser to support the new syntax.

### Grok

Update Grok to handle the new AST.

### Analysis server

Update to use the latest analyzer with support for the feature. There are a
handful of usability features that would be nice.

Users may expect `while` loops to work in collections. Good error messaging will
help them understand that restriction. Likewise, users may expect the body of an
`if` or `for` element to be a block, not an element. Parsers should handle that
gracefully and error messages should be helpful.

It would be excellent to have quick-fixes for:

*   **Switching out an element using a conditional operator:**

    ```dart
    [
      before,
      condition ? first : second,
      after
    ]
    ```

    Fix:

    ```dart
    [
      before,
      if (condition) first else second,
      after
    ]
    ```

*   **Omitting an element using a conditional operator and `null` filtering:**

    ```dart
    [
      before,
      condition ? first : null,
      after
    ].where((e) => e != null).toList()
    ```

    Fix:

    ```dart
    [
      before,
      if (condition) first,
      after
    ]
    ```

    (This requires some care because the user may intend to filter out *other*
    nulls as well.)

*   **Using `Map.fromIterable()`:**

    ```dart
    Map.fromIterable(things,
      key: (e) => someExpression(e),
      value: (e) => anotherExpression(e)
    )
    ```

    Fix:

    ```dart
    {
      for (var e in things)
        someExpression(e): anotherExpression(e)
    }
    ```

### Atom plug-in

The [Dart Atom plug-in][atom] has a grammar for syntax highlighting Dart code in
Atom. This same grammar is also used for syntax highlighting on GitHub. Update
this to handle the new syntax.

[atom]: https://github.com/dart-atom/dart

### VS Code

Update the syntax highlighting grammar to support the control flow syntax (and,
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

## Phase 3 (Release)

### Enabling

The language team updates the experimental flag `control-flow-collections` to
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
