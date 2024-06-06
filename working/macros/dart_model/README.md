# `dart_model` exploration

Code exploring
[a query-like API](https://github.com/dart-lang/language/issues/3706) for
macros, in particular with regard to incremental build performance and
convenience for macro authors.

_This code will be deleted/archived, do not use it for anything!_

Packages:

`dart_model` is a standalone data model, the input to a macro;\
`dart_model_analyzer_service` serves `dart_model` queries using the analyzer
as a library;\
`dart_model_repl` is a REPL that can issue queries and watch code for changes\
`macro_client` is for writing "macros";\
`macro_host` hosts a set of "macros" running against a codebase;\
`macro_protocol` is how "macros" communicate with their host;\
`testing` is for test "macros" and experiments with them.

The "macros" referred to in this exploration are independent of the in-progress
macro implementation, hence the "scare quotes".

## End to End Benchmarks

`testing/benchmark` is a tool to assist in benchmarking, it creates codebases
of the specified size and codegen strategy.

### Scenarios

`trivial_macros` is a scenario with three trivial macros: `Equals()`,
`HashCode()` and `ToString()`. These inspect the fields of a class and generate
corresponding (shallow) `operator==`, `hashCode` and `toString()`.

### Strategies

Four strategies are supported:

`macro` uses the experimental macro implementation from the SDK;\
`dartModel` uses this exploratory macro implementation;\
`manual` writes equivalent code directly in the source;\
`none` means the functionality is missing altogether.

### Example

To compare the SDK macros with this exploratory implementation:

```
$ cd testing/benchmark

# Create a large example using SDK macros: 64 large libraries, about 67k LOC.
$ dart bin/main.dart macros macro 64
# Now open /tmp/dart_model_benchmark/macros in your IDE and modify some files
# to see how the analyzer responds.

# Create an equivalent example using `dart_model`.
$ dart bin/main.dart dartModel dartModel 64
# In a new terminal, launch the "macro" host.
$ cd macro_host
$ dart bin/main.dart /tmp/dart_model_benchmark/dartModel/package_under_test
# In a second new terminal, launch the "macro" process.
$ cd testing/test_macros
$ dart bin/main.dart
# Now open /tmp/dart_model_benchmark/dartModel in your IDE and modify some
# files to see how the analyzer responds; you can watch the macro host terminal
# to see when it is rewriting augmentation files.
```

## Serialization Benchmarks

`testing/json_benchmark` is benchmarking related to JSON serialization.
