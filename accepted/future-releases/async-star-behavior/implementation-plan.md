# Implementation Plan for async-star/await-for behavior.

Relevant documents:
- [Feature specification](https://github.com/dart-lang/language/blob/master/accepted/future-releases/async-star-behavior/feature-specification.md)
## Implementation and Release plan

### Phase 0 (Preliminaries)

#### Specification

The language specification already specifies the desired behavior.

#### Tests

The language team adds a set of tests for the new, desired behavior.
See [https://dart-review.googlesource.com/c/sdk/+/85391].

### Phase 1 (Implementation)

Only tools with run-time behavior are affected.
Tools like the analyzer and dart-fmt should not require any change.

The Kernel and the back-ends need to collaborate on this change since the
behavior is an interaction between the Kernel's "continuation" transformer
and classes in the individual back-end libraries (in "async_patch.dart" files).

The new behavior is guarded by the experiments flag `async-yield`,
so to enable the new behavior, the tools need to be passed a flag
like `--enable-experiments=async-yield`.

### Phase 2 (Preparation)

This change is potentially breaking since it changes the interleaving
of asynchronous execution.
Very likely there is no code *depending* on the interleaving, given that it
is un-intuitive and surprising to users, but some users have hit the problem,
and it's unclear whether they have introduced a workaround.

We need to check that Google code and Flutter code is not affected by the
behavior. If it is, the code should be fixed before we release the change.
The only way to check this is to actually run an updated SDK against the code
base.

### Phase 3 (Release)

The feature is released as part of the next stable Dart release.

## Timeline

Completion goals for the phases:
- Phase 0: (TODO)
- Phase 1: (TODO)
- Phase 2: (TODO)
- Phase 3: (TODO)
