# Implementation plan for super mixins

Relevant documents:
 - [Tracking issue](https://github.com/dart-lang/language/issues/12)
 - [Discussion issue](https://github.com/dart-lang/language/issues/7)
 - [Full proposal](https://github.com/dart-lang/language/blob/master/accepted/2.1/super-mixins/feature-specification.md)
 - [Mixin inference](https://github.com/dart-lang/language/blob/master/accepted/2.1/super-mixins/mixin-inference.md)

## Implementation and Release plan

### Release flags

Old school super-mixins are currently behind a flag in the analyzer, and
available by default on the VM.  They are not supported in dart2js and DDC, but
some uses may accidentally work.  We will not have a separate release flag for
this feature.  Platforms that currently have an `enableSuperMixins` flag will
initially launch this feature behind this flag as described below.  The VM will
pick up support for this without a flag.

### Phase 0 (Syntax)

#### CFE

CFE adds support for the new syntax without (necessarily) implementing errors
and warnings.  This unblocks the analyzer work.

### Phase 1 (Frontend support)

#### CFE

Initial support is provided by translating mixin declarations
into classes as follows:
```dart
  mixin M on S0, S1, ..., Sk implements I0, ..., Im { ...}
```

May be translated to:

```dart
  class M extends S0 with S1, ..., Sk implements I0, ..., Im { ...}
```

This allows existing code that is currently written as the latter to be
rewritten using the new syntax without loss of functionality.

Note that mixin inference must continue to be supported on the translated
declarations in order for this to be useful for migration purposes.

#### Analyzer/CFE

Errors per the specification are implemented in the analyzer or the CFE (both
for declarations and for uses), and support for surfacing these errors is added
to the analyzer.

#### Analyzer/Linter

Implement a lint that fires when an old-school super mixin is used.

#### Intellij/Grok/Dartfmt

Support for the new mixin declaration syntax is added to the relevant tooling.

### Phase 2 (Functional backend support)

#### Language team

Turn on old-school mixin lint in flutter, and move flutter over to the new
declaration syntax.

### Dart2js, DDC

Implement support for the new syntax, and for the semantics to the extent that
they are supported today (specifically, non-super-mixins using the mixin
declaration syntax should work).  This should be possible by translation to
classes if necessary.

### Phase 3 (Flutter migration)

### Analyzer/CFE
Move support for the new mixin declaration syntax out from behind the
`enableSuperMixins` flag.  Support for the old style syntax remains behind the
flag.

### Language team

After suitable migration period, remove `enableSuperMixins` flag from flutter
analysis_options.yaml.

### Phase 4 (Full support)

### Dart2js, DDC

Implement support for the feature.

### Dartdoc, Dartpad, Documentation sites

Support verified, documentation in place.

### Phase 5 (Release and launch)

### Analyzer/CFE

Remove support for old style super-mixins.

### Language team
Clean up any remaining uses of old style super mixins, communicate and launch.

## Timeline

Completion goals for the phases:

- Phase 0: 2018.08.24
- Phase 1: 2018.09.07
- Phase 2: 2018.09.17
- Phase 3: 2018.10.15
- Phase 4: ???
- Phase 5: ???
