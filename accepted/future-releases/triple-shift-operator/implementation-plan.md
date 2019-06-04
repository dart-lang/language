# Implementation Plan for the `>>>` operator.

Relevant documents:
- [Feature specification](https://github.com/dart-lang/language/blob/master/accepted/future-releases/triple-shift-operator/feature-specification.md)
## Implementation and Release plan

### Phase 0 (Preliminaries)

#### Specification

The language specification already specifies `>>>` as a user-implementable
operator.

The `int` operator will act as documented in the feature specification
when added.

#### Tests

The language team adds a set of tests for the new feature,
both the general implementable operator,
and the specific `int.operator>>>` implementation

The co19 team start creating tests early, such that those tests can be
used during implementation as well.

The language specification is already updated with this feature.

### Phase 1 (Implementation)

All tools implement syntactic support for the `>>>` operator.
The syntax is guarded by the experiments flag `tripple-shift`,
so to enable the syntax, the tools need to be passed a flag
like `--enable-experiments=tripple-shift`.

This also includes all derived syntax required by the specification, 
including the `>>>=` assignment oprator and the `#>>>` symbol.
The `Symbol` constructor must also accept `>>>` as an argument.

### Phase 2 (Use)

The library team implements `int.operator>>>`.
This likely needs to be implemented as a branch
which enables the experiments flag by default.
As such, it can only be tested on that branch.
Backends are free to optimize this operation further at any point.

It is possible to delay the `int` operator until a later release,
but it would be a better user experience to get it out as soon as possible.

(It is not yet clear what semantics JS compilers will choose for `int.>>>`,
this will also have to be decided).

### Phase 3 (Release)

The feature is released as part of the next stable Dart release.

## Timeline

Completion goals for the phases:
- Phase 0: (TODO)
- Phase 1: (TODO)
- Phase 2: (TODO)
- Phase 3: (TODO)
