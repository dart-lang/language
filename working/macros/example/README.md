**DISCLAIMER**: All code in this package is experimental and should be treated
as such.

This package some example macros (under `lib`), as well as some utilities to try
actually running those examples.

## Setup

Your SDK will need to match roughly the commit pinned in the pubspec.yaml file
of this package (see the `ref` lines). Otherwise you will get a kernel version
mismatch.

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
