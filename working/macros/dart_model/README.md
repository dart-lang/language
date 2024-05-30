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
