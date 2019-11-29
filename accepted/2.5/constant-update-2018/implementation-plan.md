# Implementation Plan for the Q4 2018 Constant Update

Relevant documents:
 - [Tracking issue](https://github.com/dart-lang/language/issues/60)
 - [Full proposal](https://github.com/dart-lang/language/blob/master/accepted/2.5/constant-update-2018/feature-specification.md)

## Implementation and Release plan

### Release flags

The implementation of these changes must happen behind an [*experiments flag*](https://github.com/dart-lang/sdk/blob/master/docs/process/experimental-flags.md).
Tools need to be passed the flag `--enable-experiment=constant-update-2018`
for the changes to be enabled.

The `--enable-experiment` option takes a comma separated list of names of experiments
to enable, and the option can be passed multiple times to a tool, 
enabling any experiment mentioned in any of the option arguments.

The list of available flags at any time is defined by a 
`.dart` experiments flag definition file (location and exact content TBD).
The file lists flags that are currently available to users, 
as well as some prior flags that are now enabled by default and not available 
to users.

While developing, individual tools may have incomplete implementations behind the flag.
When all tools have completely implemented the feature,
the the feature will be enabled, and the flag removed, in a stable release.


### Phase 0 (Prerequisite)

All tools add support for experimental flags, if not yet supported.
Tools must refuse to run if supplied with unsupported experimental flags.

Projects embedded in other tools, like the Common Front-end (CFE) embedded in the VM or dart2js,
must be able to receive experimental flags programmatically from the embedder, 
which can then accept them on the command line.

#### Tests

The language team adds tests for the new syntax.

### Phase 1 (Implementation)

#### Analyzer and CFE 
The analyzer and CFE implements support for the new constant and potentially constant expressions
behind the experimental flag.

The CFE plans to implement constant evaluation itself, rather than deferring it to the 
backends. The new constant features will be included in this implementation,
so back-ends should not need to implement the new behavior.

If the implementation requires changes to the Kernel format, then backends may need to adapt to that,
just as with any other Kernel format change.

#### Intellij/Grok/Dartfmt

Support for the new constant expressions is added to the relevant tooling.

It is very likely that no changes are needed here, 
as long as the analyzer supports the new expressions.
All the affected expressions are already valid non-constant expressions.

#### Co19 tests

The co19 team can start implementing tests early using the experimental
flag. 
Those tests should not be tested by default by the Dart SDK until the
feature has been released.

### Phase 2 (Release)

#### Language team

The language team updates the experimental flag `const-update-2018` to
always be enabled and no longer be available to users, and releases
This update is released as part of the next stable Dart release.

### Phase 3 (Clean-up)

All tools may now remove the dependencies on the flag in
the experiments flag definition file.

When all SDK tools have done so, 
the flag is removed from the experiments flag definition file.

## Timeline

Completion goals for the phases:

- Phase 0: Mid November 2018
- Phase 1: Early December 2018
- Phase 2: Mid December 2018
- Phase 3: Q1 2019
