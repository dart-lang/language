**DISCLAIMER**: All code in this package is experimental and should be treated
as such. The examples are unstable and may or may not work at any given time,
depending on the implementation status.

## Setup

Your SDK will need to match roughly the commit pinned in the pubspec.yaml file
of this package (see the `ref` lines). Otherwise you will get a kernel version
mismatch.

## Examples

The example macros live under `lib/` and there are programs using them under
`bin/`. To try and run an example, you need to enable the `macros` experiment,
`dart --enable-experiment=macros <script>`, but the implementations do not yet
support all the examples here so you should expect errors.

## Benchmarks

There is a basic benchmark at `benchmark/simple.dart`. You can run this tool
directly, and it allows toggling some options via command line flags. You can
also AOT compile the benchmark script itself to simulate an AOT compiled host
environment (compiler).

This benchmark uses a synthetic program, and only benchmarks the overhead of
running the macro itself, and the communication to and from the host program.
