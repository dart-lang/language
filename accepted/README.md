# Accepted language features

This directory holds feature specifications, implementation plan documents, etc.
for accepted Dart language changes. 

For the full Dart Language Specification, please see our homepage:
https://dart.dev/guides/language/spec

## Feature Specification Status

The following table shows the status of various feature specification
documents in this repository.

- Status 'Done' means that this feature is specified in the language
  specification, and the feature specification is now kept around only as
  background information.
- Status 'Abandoned' means that a different feature specification is now
  dealing with the given topic, and this one was never released or
  integrated into the language specification.
- Status 'Specified' means that a feature specification has been written
  and has been accepted by the language team. This feature specification is
  currently the source of truth about the given feature, but it will be
  integrated into the language specification later (at which time it will
  be 'Done').
- Status 'Ongoing' means that the feature has not yet been fully designed
  and specified. It is often the case that there exist one or more feature
  specification proposals in the `working` subdirectory if this repository.
- Status 'Library' means that this feature is a library feature. It will be
  integrated into library documentation, not into the language
  specification.

| Version | Subdirectory/document              | Status     |
|--------:|------------------------------------|:----------:|
|     2.0 | [sound-type-system.md](https://github.com/dart-lang/language/blob/main/accepted/2.0/sound-type-system.md)| Done |
|     2.1 | [int-literal-as-double-value](https://github.com/dart-lang/language/blob/main/accepted/2.1/int-literal-as-double-value)| Done |
|         | [super-mixins](https://github.com/dart-lang/language/blob/main/accepted/2.1/super-mixins)| Done |
|     2.2 | [set-literals](https://github.com/dart-lang/language/blob/main/accepted/2.2/set-literals)| Done |
|     2.3 | [control-flow-collections](https://github.com/dart-lang/language/blob/main/accepted/2.3/control-flow-collections)| Abandoned |
|         | [spread-collections](https://github.com/dart-lang/language/blob/main/accepted/2.3/spread-collections)| Abandoned |
|         | [unified-collections](https://github.com/dart-lang/language/blob/main/accepted/2.3/unified-collections)| Done |
|     2.5 | [constant-update-2018](https://github.com/dart-lang/language/blob/main/accepted/2.5/constant-update-2018)| Done | 
|         | [contravariant-superinterface-2018](https://github.com/dart-lang/language/blob/main/accepted/2.5/contravariant-superinterface-2018)| Done |
|     2.7 | [static-extension-methods](https://github.com/dart-lang/language/blob/main/accepted/2.7/static-extension-methods)| Done |
|     2.8 | [language-versioning](https://github.com/dart-lang/language/blob/main/accepted/2.8/language-versioning)| Specified |
|    2.12 | [abstract-external-fields](https://github.com/dart-lang/language/blob/main/accepted/2.12/abstract-external-fields)| Specified |
|         | [nnbd](https://github.com/dart-lang/language/blob/main/accepted/2.12/nnbd)| Specified |
|    2.13 | [nonfunction-type-aliases](https://github.com/dart-lang/language/blob/main/accepted/2.13/nonfunction-type-aliases)| Specified |
|    2.14 | [small-features-21Q1](https://github.com/dart-lang/language/blob/main/accepted/2.14/small-features-21Q1)| Done |
|         | [triple-shift-operator](https://github.com/dart-lang/language/blob/main/accepted/2.14/triple-shift-operator)| Done |
|    2.15 | [constructor-tearoffs](https://github.com/dart-lang/language/blob/main/accepted/2.15/constructor-tearoffs)| Specified |
|    2.17 | [1847-finalization-registry](https://github.com/dart-lang/language/blob/main/accepted/2.17/1847-finalization-registry)| (Library?) |
|         | [enhanced-enums](https://github.com/dart-lang/language/blob/main/accepted/2.17/enhanced-enums)| Specified |
|         | [named-arguments-anywhere](https://github.com/dart-lang/language/blob/main/accepted/2.17/named-arguments-anywhere)| Specified |
|         | [super-parameters](https://github.com/dart-lang/language/blob/main/accepted/2.17/super-parameters)| Specified |
|    2.18 | [horizontal-inference](https://github.com/dart-lang/language/blob/main/accepted/2.18/horizontal-inference)| Specified |
|    2.19 | [unnamed-libraries](https://github.com/dart-lang/language/blob/main/accepted/2.19/unnamed-libraries)| Specified |
|     3.0 | [patterns](https://github.com/dart-lang/language/blob/main/accepted/3.0/patterns)| Specified |
|         | [class-modifiers](https://github.com/dart-lang/language/blob/main/accepted/3.0/class-modifiers)| Specified |
|         | [records](https://github.com/dart-lang/language/blob/main/accepted/3.0/records)| Specified |
|     3.2 | [private-field-promotion issue](https://github.com/dart-lang/language/issues/2020)| Specified |
|     3.3 | [extension-types](https://github.com/dart-lang/language/blob/main/accepted/future-releases/extension-types/feature-specification.md)| Specified |
|     3.4 | [inference-update-3](https://github.com/dart-lang/language/issues/1618)| Specified |
|     3.6 | [digit-separators](https://github.com/dart-lang/language/blob/main/accepted/future-releases/digit-separators/feature-specification.md)| Specified |
|     3.7 | [wildcard-variables](https://github.com/dart-lang/language/blob/main/accepted/future-releases/wildcard-variables/feature-specification.md)| Specified |
|         | [inference-using-bounds](https://github.com/dart-lang/language/blob/main/accepted/future-releases/3009-inference-using-bounds/design-document.md)| Specified |
|     3.8 | [null-aware-elements](https://github.com/dart-lang/language/blob/main/accepted/future-releases/0323-null-aware-elements/feature-specification.md)| Specified |
|     3.9 | [sound-flow-analysis](https://github.com/dart-lang/language/issues/3100)| Implemented, needs specification |
|    3.10 | [dot-shorthands](https://github.com/dart-lang/language/blob/main/accepted/3.10/dot-shorthands/feature-specification.md)| Specified |
|    3.12 | [private-named-parameters](https://github.com/dart-lang/language/blob/main/accepted/future-releases/2509-private-named-parameters/feature-specification.md)| Specified |
|    3.13 | [primary-constructors](https://github.com/dart-lang/language/blob/main/accepted/future-releases/primary-constructors/feature-specification.md)| Specified |
|     3.? | [parts-with-imports](https://github.com/dart-lang/language/blob/main/accepted/future-releases/parts-with-imports/feature-specification.md)| Ongoing |
|     3.? | [augmentations](https://github.com/dart-lang/language/blob/main/working/augmentations/feature-specification.md)| Ongoing |
|     3.? | [static-extensions](https://github.com/dart-lang/language/blob/main/working/0723-static-extensions/feature-specification.md)| Ongoing |
|     3.? | [unquoted-imports](https://github.com/dart-lang/language/blob/main/accepted/future-releases/unquoted-imports/feature-specification.md)| Ongoing |

Some feature specifications are located in the
[future-releases](https://github.com/dart-lang/language/tree/main/accepted/future-releases)
directory and haven't yet been released.
