# Implementation Plan for "External and Abstract Variables"

Owner: eernst@google.com ([@eernstg](https://github.com/lrhn/) on GitHub)

Relevant links:

* [Tracking issue](https://github.com/dart-lang/sdk/issues/42560)
* [Feature specification](https://github.com/dart-lang/language/blob/master/accepted/future-releases/abstract-external-fields/feature-specification.md)

## Phase 0 (Preliminary steps)

### Experimental flag

The implementation of this feature is hidden behind an
[experiment flag][].
The flag `--enable-experiment=non-nullable`
must be passed to tools in order to enable the feature.

[experiment flag]: https://github.com/dart-lang/sdk/blob/master/docs/process/experimental-flags.md

This means that the feature is considered to be part of the null-safety
feature bundle, and it will be enabled by default along with null-safety.

### Tests

The language team adds
[tests](https://github.com/dart-lang/sdk/tree/master/tests/language/external_abstract_fields)
for the feature. The Co19 team adds tests for the specification.

## Phase 1 (Front End Implementation)

### CFE

The CFE implements parsing the new syntax, detecting static errors, and
performing the transformations that turns the new variable declarations into
external or abstract getters and/or setters.

### Analyzer

The analyzer implements parsing the new syntax and checking for static
errors. Based on input from Paul Berry, this is unlikely to rely on
desugaring, and approximately the following changes will be needed in the
analyzer:

- Modify the AST and summary representations to include support for
  `abstract` and `external` keywords on variables.
- Modify the mechanism for building element models to mark abstract fields
  as abstract, and external fields as external.
- Modify the error generation logic to suppress 'uninitialized field'
  errors for abstract and external fields.
- Modify the error generation logic to report errors if an abstract or
  external field is initialized.
- There may be a need for changes to ensure that an appropriate error is
  reported if a concrete class fails to implement a getter or setter which
  was introduced by an abstract variable.
- There may be a need to change the constant evaluator to avoid computing
  a value for an abstract/external variable.

## Phase 2 (Remaining Implementation)

### dart2js, DDC, VM

The feature is expected to be desugared, which means that it will not
exist in kernel code, and backends need not implement anything.

### Dartfmt

Define and implement formatting rules for the new syntax.
Add formatting tests.

### Formal specification

Add a formal specification of this feature to the language specification.

### Cider, DartPad

Cider and DartPad syntax highlighting uses codemirror, which should
be updated to support the new syntax:
https://github.com/codemirror/CodeMirror/blob/master/mode/dart/dart.js.

### IntelliJ

Update the IntelliJ parser to support the new syntax.

### Grok

Update Grok to handle the new AST.

### Analysis server

Code completion may need to change in order to include
new syntax.

### Update github syntax highlighting

Github's syntax highlighting should support the new syntax:
https://github.com/dart-lang/dart-syntax-highlight/tree/master/grammars.

When the grammar is updated, please create an issue on the
Dart-Code/Dart-Code repository, such that the grammar can be
copied and used with VS Code as well.

### VS Code

The grammar mentioned in the section about github is used with
VS Code as well. An issue should be created on Dart-Code/Dart-Code
when the grammar has been updated.

### Dartdoc

Dartdoc implements support for the new syntax.

### Co19 tests

The co19 team can start implementing tests early using the experimental flag.
Those tests should not be run by default until the feature has been released.

### Other Tools

Validate that build systems, code generators, Angular compiler all
work and are updated.

## Phase 3 (Release)

### Enabling

The language team enables the experimental flag
`external-abstract-variables` by default and releases this update in the
next stable Dart release.

### Use

This feature, in particular external instance variables, is expected to be
used heavily by the FFI team.

### Documentation

The language team adds the feature to the CHANGELOG. They write an
announcement and publish it.

## Phase 4 (Clean-up)

### Remove flag

The experiment flag `external-abstract-variable` and all code that depends
on it may be removed when the feature has been released. When all SDK tools
have done this, the flag is removed from the experiments flag definition
file.

## Timeline

Completion goals for the phases:

*   Phase 0 (Preliminary steps): TODO
*   Phase 1 (Front End Implementation): TODO
*   Phase 2 (Remaining Implementation): TODO
*   Phase 3 (Release): TODO
*   Phase 4 (Clean-up): TODO
