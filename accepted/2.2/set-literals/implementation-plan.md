# Implementation Plan for Set literals

Relevant documents:
 - [Tracking issue](TODO)
 - [Full proposal](https://github.com/dart-lang/language/blob/master/accepted/2.2/set-literals/feature-specification.md)

## Implementation and Release plan

### Release flags

The implementation of this change will happen behind
an
[*experiments flag*](https://github.com/dart-lang/sdk/blob/master/docs/process/experimental-flags.md).
Tools need to be passed the flag `--enable-experiment=set-literals` for the
changes to be enabled.

### Task0 (Prerequisite)

All tools add support for experimental flags, if not yet supported.  This is
tracked as Phase 0 of [this issue](https://github.com/dart-lang/language/issues/60).

### Task1 : Task0 (Parsing support)

The CFE implements parsing support for the new literal syntax.

### Task2 : Task1 (CFE implementation)

The CFE implements support for set literals (errors and warnings, constant
evaluation, and any required changes to support the backends).

### Task3 : Task1 (Analyzer implementation)

The analyzer implements static checking for set literals (errors and wrarnings,
constant evaluation).

### Task4 : Task3 (DDC implementation)

DDC implements backend support.

### Task5 : Task2 (VM support)

VM implements backend support.

### Task6 : Task2 (dart2js support)

dart2js implements backend support.

### Task7 : Task0 (Intellij support)

IntelliJ parser supports set literals

### Task8 : Task1 (Grok support)

Grok implements any required support.

### Task9 : Task3 (Dartfmt support)

Dartfmt implements formatting support.

### Task9 : Task3 (Dartdoc support)

Dartdoc implements support.

### Task10 : (Specification)

Add set literals to formal spec

### Task11 : (Documentation)

Document in language references

### Task12 : (co19 tests)

co19 tests written.

### Task13 : (Language tests)

Language tests written.

### Task14 : Task1 (Angular compiler, sourcegen)

Angular compiler and sourcegen clients support set literals.

### Task15 : Task14 (Google3 roll)

Roll to google3 with flag enabled.

### Task16 : * (Launch)

Remove the experimental flag, enable by default, announce the feature.


## Timeline

Completion goals for the phases:

- Task0: Mid November 2018
- Task1: November 16, 2018 
- Task2, Task3: November 30, 2018
- Tasks 4-14: December 14, 2018
- Task15: December 21, 2018
- Task16: January, 2019
