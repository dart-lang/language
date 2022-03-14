**DISCLAIMER**: All code in this package is experimental and should be treated
as such.

This package some example macros (under `lib`), as well as some utilities to try
actually running those examples.

## Setup

You may need to edit the `pubspec.yaml` file to run these examples. It requires
a path dependency on the SDK packages to work (until
https://github.com/dart-lang/pub/issues/3336 is resolved). The current paths
assume the dart sdk is in a sibling directory to the language repo, in a
directory called `dart-lang-sdk`.

Your SDK will also need to be very recent, in particular it must include
commit 54e773.

## Benchmarks

There is a basic benchmark at `benchmark/simple.dart`. You can run this tool
directly, and it allows toggling some options via command line flags. You can
also AOT compile the benchmark script itself to simulate an AOT compiled host
environment (compiler).

This benchmark uses a synthetic program, and only benchmarks the overhead of
running the macro itself, and the communication to and from the host program.

## Examples

There is an example program at `bin/user_main.dart`. This _cannot_ be directly
executed but you can compile and execute it with the `bin/run.dart` script.

**NOTE**: This is not meant to be a representative example of how a script using
macros would be compiled and ran in the real world, but it does allow you to
execute the program.
