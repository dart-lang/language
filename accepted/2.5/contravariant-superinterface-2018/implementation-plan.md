# Implementation Plan for the Q1 2019 Superinterface Contravariance Error.

Relevant documents:
 - [Tracking issue](https://github.com/dart-lang/language/issues/113)
 - [Feature specification](https://github.com/dart-lang/language/blob/master/accepted/future-releases/contravariant-superinterface-2018/feature-specification.md)


## Implementation and Release plan

This feature is concerned with the introduction of one extra compile-time
error, and the breakage has been estimated to be very low.
Still, we will use an 
[experiments flag](https://github.com/dart-lang/sdk/blob/master/docs/process/experimental-flags.md)
in order to enable a controlled deployment.


### Phase 0 (Release flag)

In this phase every tool adds support for an experiments flag: The flag
`--enable-experiment=covariant-only-superinterfaces` must be passed for the
changes to be enabled.


### Phase 1 (Implementation)

All tools add the implementation of the associated compile-time check, and
start emitting the new error during static analysis if the experimental flag
is supplied.


### Phase 2 (Release)

A single commit removes the experimental flag from all implementations,
causing them all to start emitting the new error during static analysis under
normal execution.  The update is released as part of the next stable Dart release.


## Timeline

Completion goals for the phases:

- Phase 0: Q1 2019
- Phase 1: Q1 2019
- Phase 2: Q1 2019
