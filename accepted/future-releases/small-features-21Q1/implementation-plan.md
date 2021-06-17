# Implementation Plan for "Small Features 21Q1"

Owner: lrn@google.com ([@lrhn](https://github.com/lrhn/) on GitHub)

Relevant links:

* [Implementation issue](https://github.com/dart-lang/sdk/issues/44911)
* [Proposal](https://github.com/dart-lang/language/blob/master/working/small-features-21q1/feature-specification.md)

## Phase 0 (Prerequisite)

### "generic-metadata" Experimental flag

The implementation of parts of this feature ("generic metadata" and "generic function type arguments") should be developed behind an [experiment
flag][]. Tools must be passed the flag
`--enable-experiment=generic-metadata` to enable those features.

[experiment flag]: https://github.com/dart-lang/sdk/blob/master/docs/process/experimental-flags.md

While this feature is under development, individual tools may have incomplete or
changing implementations behind the flag. When all tools have completely
implemented the feature, the feature will be enabled by default, and the
flag removed in a stable release.

### "triple-shift" Experimental flag

The existing "triple-shift" experiment flag is already used for the partly implemented `>>>` operator. The flag is retained until we release the feature.

### Tests

The language team adds tests for the feature.

## Phase 1 (Foundation)

### CFE

The CFE implements parsing the new syntax, type checking it, and compiling it to
Kernel. Since the CFE performs constant evaluation, it also
implements the evaluation of metadata annotations.

The generic metadata feature can likely be implemented entirely in the front end and analyzer, with no back-end
support needed. Since the front-end already evaluates the constants, and might infer type arguments, back-ends are likely used to seeing the filled-in result anyway. The analyzer deals with *source*, and must be able to make the distinction between an omitted-and-inferred type argument and an explicit type argument on a metadata constructor invocation.

The generic function type argument feature can likely be *implemented* entirely in the front-end, by not disallowing generic function types as type arguments, but back-ends might need to find places where they assume that a type argument cannot be a generic function type.

The `>>>` feature is already implemented in the CFE.

### Analyzer

For generic metadata, the analyzer needs to represent the *source*, and therefore must be able to make the distinction between an omitted-and-inferred type argument and an explicit type argument on a metadata constructor invocation. This is important for other source-manipulating tools like the formatter. The AST for metadata invocations need to have a place to store the type arguments, which isn't there now.

If the analyzer assumes, and relies on the assumption, that type arguments cannot be generic function types, then it might need to fix that.

The analyzer also needs to support `const Symbol(">>>")`, but otherwise seems to support the `>>>` feature (`operator>>>`  and `#>>>` works).

Otherwise the analyzer is unlikely to need significant change for any of the features.

## Phase 2 (Tool Implementation)

### dart2js

If the feature is handled by the front end, there may be no dart2js work.
Otherwise, dart2js may need to handle any Kernel changes 

Dart2js supports `>>>` except for `new Symbol(">>>")`. This can be fixed by a single RegExp update.

### Dartfmt

The only new syntax is metadata type arguments. They need to be supported, but should likely be treated like any other constructor invocation. Define and implement formatting rules for the new syntax. Add formatting tests.

### DDC

If these features can be implemented entirely in the front end with no Kernel
changes, then no DDC changes may be needed.
Otherwise, DDC may need to handle any Kernel changes or otherwise add support
for this.

### IntelliJ

Update the IntelliJ parser to support the new syntax forms.

### Grok

Update Grok to handle the new AST.

### Analysis server

Update to use the latest analyzer with support for the feature. 

The analyzer should likely recognize the grammar even without the experiment flag, and report errors stating that the feature is not available yet, rather than trying to parse `>>>` as `>>` followed by `>`, which is never valid as an operator.

There are no new quick-fixes needed.

### VS Code and Github grammar

Update the (syntax highlighting grammar)[https://github.com/dart-lang/dart-syntax-highlight] to support the new syntax.

### VM

If the feature is handled by the front end, there may be no VM work. The VM already fully supports `>>>`, but it is possible that generic functions as type arguments may trigger some unused code paths.

### Co19 tests

The co19 team can start implementing tests early using the experimental flags.
Those tests should not be run by default until the feature has been released.

### Usability validation

No usability testing is planned. There is nothing *new* in these features (deliberately), just allowing existing syntax in new places, or one more operators which also exist in other languages.

## Phase 3 (Release)

### Enabling

The language team updates the experimental flags `generic-metadata` and `triple-shift` to
always be enabled and no longer be available to users, and releases this update
in the next stable Dart release.

### Use

The Dart library team introduces `int.operator>>>` as soon as possible.

### Documentation

The language team adds the feature to the CHANGELOG. They write some sort of
announcement email or blog post.

The language tour needs to be updated to mention `>>>` as a user definable
operator.

## Phase 4 (Clean-up)

### Remove flag

All tools may now remove the dependencies on the flag in the experiments flag
definition file. When all SDK tools have done so, the flag is removed from the
experiments flag definition file.

## Timeline

Completion goals for the phases:

*   Phase 0 (Prerequisite): Mostly done, tests by end of January.
*   Phase 1 (Foundation): Early February 2021.
*   Phase 2 (Tool Implementation): Mid March, 2021
*   Phase 3 (Release): TODO
*   Phase 4 (Clean-up): TODO
