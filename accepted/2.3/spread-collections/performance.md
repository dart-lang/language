A key part of the spread proposal is the `...` syntax "desugars" to calls to a
public API on the object being spread. This is important because it allows users
to spread their own collection types. In other words, it makes the spread syntax
programmable.

That raises the question of *what* public API it should call. The API should be
simple to implement, but also efficient to execute. Whatever it desugars to,
we'll be stuck with forever. Since it's calling into user code which can have
arbitrary side effects, any change to the semantics could be breaking.

I came up with a handful of different desugarings and then wrote some, I hope,
robust benchmarks. I tested them across a few platforms, collection sizes, and
collection types. This produces something like a 5-dimensional hypercube of
configurations, so I sliced the data a bunch of different ways and tried to
summzarize the trends.

**TL;DR: I recommend, we:**

*   Desugar to `List.length` and `List.[]` at compile time if we statically know
    the Iterable object being spread implements List.

*   Desugar maps to `Map.keys` and `Map.[]`.

**Decided: After discussing this with the language leads, we've agree to:**

*   Keep desugaring iterables to `iterator`, but give implementations the
    *option* of using `length` and `[]` if the iterable is a List, Queue, or
    Set.

*   Keep desugaring maps to `entries`. We think user-defined Map classes are
    pretty rare, as is spreading maps. Implementations can always apply
    whatever optimizations they want when they detect that a map is a built-in
    map type.

The benchmark is [here][code], and the full data is [here][sheet] (not visible
outside of Google, sorry).

[code]: https://github.com/dart-lang/language/tree/master/accepted/2.3/spread-collections/benchmarks/bin/profile.dart
[sheet]: https://docs.google.com/spreadsheets/d/1gomXf2pPnMl95iCIHSVElB3c9giGaXDRNDJuyABXcw4/edit#gid=0&fvid=1718348639

## Methodology

Before I get into the options and results, here's a little on what I tested and
how.

### Platforms

I focused on three Dart implementations. I tested these on my Mac laptop:

*   **Ahead-of-time compiled and run on the Dart VM.** This is how Flutter
    applications are deployed, so it's performance is obviously relevant. I
    followed the instructions in [this issue][34343] to compile and run the
    code.

*   **Compiled to JS with dartj2s -O4 and run on V8 (Node).** Deployed Dart web
    apps use dart2js. As far as I can tell, most shipped apps use `-O4` which
    enables the "trust types" and "trust primitives" optimizations. Those are
    both unsafe, but everyone seems to use them. Dart2js does not appear to have
    optimized its implementation of the Dart 2 runtime type checks yet, so
    performance is very bad at `-O0`.

    I ran them on Node because it was convenient. The important bit is that it's
    running on V8.

*   **JIT from source on the VM.** This isn't a typical deployment
    configuration, but is a very different implementation. I wanted to make sure
    its performance wasn't highly divergent from the above two.

I did not benchmark DDC. It might be worth doing, but DDC isn't highly
performance critical and my guess is that there will not be too many performance
surprises there compared to the above.

[34343]: https://github.com/dart-lang/sdk/issues/34343

### Sizes

Each benchmark simulates spreading a number of collections of different sizes
and types. I tested spreading empty collections, collections with 5 elements,
and collections with 50 elements. I think those cover enough points on the size
spectrum to get a sense for how performance varies over time. I did local
testing with other sizes and didn't see anything interesting.

I believe most spreads will be relatively small.

When I report numbers independent of size, I'm roughly averaging the scores at
each size. If they vary significantly, I'll split them out. In practice, the
only large different I saw was the empty collection case (which I do think is
relevant in real-world code).

### Collection types

For types, each benchmark spreads a number of objects of different types. This
ensures the API being called is polymorphic and that the compiler can't optimize
out the dispatch. I tested four batches of objects:

*    MapIterable, WhereIterable, List, and CustomList (a simple custom
     implementation of List that wraps an inner List).

*    Just List and CustomList for the desugaring that requires the object to be
     a List.

*    LinkedHashMap and HashMap.

*    LinkedHashMap and SplayTreeMap. SplayTreeMap's implementation of the Map
     API is quite different from how other Map classes work, and has different
     performance. I wanted to tease that out. In practice, SplayTreeMap is
     rarely used, but this helps us ensure we don't pick for an API that's only
     faster for some implementations.

### Methodology

I took some tricks from benchmark_harness and Leaf and tried to write benchmarks
that minimize overhead and variance. The core benchmark function is:

```dart
double bench(void Function() action) {
  var iterations = 1;
  for (;;) {
    var watch = Stopwatch()..start();

    for (var i = 0; i < iterations; i++) {
      action();
    }

    watch.stop();

    var elapsed = watch.elapsedMicroseconds;
    if (elapsed >= _trialMicros) return elapsed / iterations;

    iterations *= 2;
  }
}
```

This calculates the average number of microseconds it takes to invoke
`action()`. It dynamically figures out how many iterations of `action()` to
invoke to fit within a minimum amount of time so that we don't benchmark too
little real work. It ensures accessing the Stopwatch time itself is not part of
the benchmark.

It runs each benchmark this way once to warm up the JIT. Then it runs all of the
benchmarks 5 times and tracks all of the times. It uses the fastest time of the
five runs for each benchmark. The idea is that it must be *possible* to execute
the code that fast, so any slower time is overhead.

When testing locally, I also print out the standard deviation. I tweaked the
`_trialMicros` to try to get a reasonably small deviation.

I also track a "no-op" benchmark that doesn't do any spread work, but otherwise
looks like a benchmark. It walks over the collections being tested and allocates
the object to spread into, but doesn't actually spread. I use this to calculate
the overhead of the benchmark. This time is subtracted from all of the other
benchmarks.

I report scores in terms of the baseline, which is the specified desugaring. So,
a score of 1.1x means it runs 10% faster than the proposal's semantics, and a
0.5x means it runs at half the speed, or twice as slow.

## Spreading into lists and sets

For spreading an Iterable (which may or may not be a List) into a list or set
literal, there are a couple of options I considered:

Note that I don't show how the elements get inserted into the *resulting
collection*. That's an implementation detail whose behavior isn't user visible,
so isn't relevant here. Presumably, the implementation will do something
sufficiently fast regardless of how it gets the elements.

### Iterable.iterator

This is what the proposal currently specifies:

```dart
var iterator = from.iterator;
while (!iterator.moveNext()) {
  var element = iterator.current;
  // Add element to result...
}
```

This has a few things going for it: it's simple, already specified, and is what
the for-in statement desugars to.

Its performance is suspect, though. Even for an empty collection, it must
allocate an Iterator. Each iteration requires two method calls, `moveNext()`,
and `current`.

### Iterable.forEach()

This also works with any Iterable:

```dart
var temp = to;
from.forEach((element) {
  // Add element to result...
});
temp = null;
```

The shenanigans around `temp` are to ensure that the collection being spread
can't hang onto the closure after the spread is complete, invoke it, and cause
weird things to happen.

Since it uses [internal iteration][internal], the collection being spread has
maximum freedom to traverse itself efficiently. The flip side is that if we ever
want to support `break` or other ways to interrupt a spread, internal iteration
will make that *very* painful.

Performance may be good, because it doesn't need to do any allocation.  On the
other hand, it involves creating a closure which accesses a free variable. That
can be slow on some implementations.

[internal]: https://journal.stuffwithstuff.com/2013/01/13/iteration-inside-and-out/

### List.[]

If we know the object being spread happens to be a List, and not just an
Iterable, we can use the List subscript API:

```dart
var length = from.length;
for (var i = 0; i < length; i++) {
  var element = from[i];
  // Add element to result...
}
```

This obviously doesn't work if the object isn't a List. Objects like the result
of `.where()` and `.map()` are Iterables, but not Lists. But if it does work, it
has a lot of promise. `.length` returns a simple integer and requires no
allocation. For typical List classes, including the built in one, `[]` is simple
and efficient: just an addition and a dereference.

If it's fast enough for C, it's probably fast enough for everyone.

### Runtime hybrid

We could theoretically get the best of both worlds by checking at runtime to see
if the Iterable is a List and choosing the API based on that:

```dart
if (from is List<String>) {
  var length = from.length;
  for (var i = 0; i < length; i++) {
    var element = from[i];
    // Add element to result...
  }
} else {
  var iterator = from.iterator;
  while (!iterator.moveNext()) {
    var element = iterator.current;
    // Add element to result...
  }
}
```

### Evaluation

Here's what I found:

*   `Iterable.forEach()` 1.3x faster than `Iterable.iterator` on AoT, 2.9x on
    dart2js, but unfortunately 0.6x on the JIT VM.

    I think the performance is too divergent to feel comfortable betting on
    this. Also, I take some points away from this approach because using an
    internal iterator may paint us into a corner with future control flow
    changes. This isn't good enough to win out past that, even ignoring the poor
    JIT performance.

*   `List.[]` is much faster when the collection is empty: 3x Aot, 3x dart2js
    and 10x on the JIT (!). This is probably showing the benefit of not
    allocating the iterator. It's somewhat faster for non-empty collections too:
    1.7x AoT, 1.2x dart2js, 1.3x JIT.

    This looks pretty nice. I think empty collections will happen fairly
    frequently, and this is significantly faster even in non-empty cases.

*   The runtime hybrid is about 1.7x faster on AoT and 1.2x faster on JIT at all
    sizes. Empty collections are *much* slower on dart2js, 0.2x, getting
    gradually better at large sizes. It's probably about as fast as the baseline
    at ~40 elements and marginally faster after that.

    I'm dubious about relying on runtime type checks in the first place, and
    these numbers definitely don't sell the approach.

**Recommendation: If the static type of the spread object is List, use
`List.[]`. Otherwise, use the current specified `Iterable.iterator` approach.**

This does mean that type inference and static types in general could
*theoretically* cause the observed behavior of a spread to change. In practice
every list I've seen in the wild conforms to the "list protocol" where
`.length`, `[]`, and `iterator` all do what you expect.

## Spreading maps

Here are the options I considered:

### `Map.entries`

This is what the proposal says now. I didn't put much thought into it when I
picked this. It seemed simple to spec, so I went with it.

```dart
var entries = from.entries.iterator;
while (!entries.moveNext()) {
  var entry = entries.current;
  var key = entry.key;
  var value = entry.value;
  // Add key:value to result...
}
```

This isn't a very frequently used or idiomatic API. (I think it was only added
to Map in Dart 2?) It's got some obvious points against it: You have to allocate
an entries *iterable* and then an entries *iterator*, even for an empty map.

Then, for each entry, you have to allocate a MapEntry object. If Dart had real
stack-allocated value types, which might not be a concern, but we don't.

### `Map.keys`

If a Dart user manually writes code to walk over the entries in a map, they
often use a for-in loop over the keys, which desugars to:

```dart
var keys = from.keys.iterator;
while (!keys.moveNext()) {
  var key = keys.current;
  var value = from[key];
  // Add key:value to result...
}
```

Like `entries`, this requires two up front allocations for the keys iterable and
iterator. However, for each entry, no additional allocation is needed. It does
require looking up each value by its key, though, which likely involves some
redundant work already done when iterating over the keys.

### `Map.forEach()`

This is the API that has the closest parallel in Iterable, which has some vague
elegance appeal:

```dart
var temp = to;
from.forEach((key, value) {
  // Add key:value to result...
});
temp = null;
```

Like `Iterable.forEach()` this requires no up front allocations, or any
allocations per entry. It does require an efficient implementation of closures.
It has the weirdness around leaking the closure and the problems with internal
iteration.

### Evaluation

*   `Map.keys` is much faster when the collection is empty: 2x AoT, 1.3x
    dart2js, 2.2x JIT. It is significantly faster on the VM on non-empty
    collections: 1.3x AoT and 1.4x JIT. On dart2js non-empty collections are as
    fast as using `Map.entries`.

*   `Map.forEach()` is faster than `Map.entries` too. When the collection is
    empty: 1.x AoT, 5.5x dartj2, and 1.8x JIT. When non-empty, the performance
    difference isn't as stark: 1.6x AoT, 1.1 dart2js, and 1.7x JIT.

Those are close enough that you really need to compare them to each other.

*   On non-empty collections, `Map.forEach()` is slightly faster than
    `Map.keys`: 1.2x AoT, 1.1x dart2js, 1.2x JIT.

*   On empty collections, it gets weird. `Map.foreach()` is 0.6x on AoT, 4.0x on
    dart2js, and 0.8x on JIT.

It's hard to know how to read those numbers. It seems like `forEach()` is
slightly faster most of the time, but not reliably. I am worried about
desugaring to internal iteration, and I want to see a clearer speed win to
justify it. I don't see that here.

**Recommendation: `Map.keys` is clearly faster and is more idiomatic. Use that
instead of `Map.entries`.**

## Protocols

I considered another option: We could define three *protocols*: "iterable",
"list", and "map". Each defines how a conforming implementation of the
corresponding classes behaves. For example, if `Iterable.isEmpty` returns
`true`, then `Iterable.iterator.moveNext()` should return `false`. Basically,
define how the API needs to behave to present a consistent view of an underlying
series of elements or entries. Then we'd say that you can only spread objects
that are conforming implementations.

This is pretty similar to how there is an implicit "hashable" protocol that any
class used as a map key is expected to follow. If you define a class that
returns two different `hashCode` values for two objects that are `==`, you're
gonna have a bad time.

Then, the spec would say that a Dart implementation is free to compile a spread
to use the Iterable, List, or Map API in any way it chooses—even taking
different choices at different parts of the same program—as long as the protocol
specifies it.

This is a lot of complexity, but would give implementations maximum freedom. I
thought this might be worth doing if there was significant performance
divergence across implementations. If, say, `Map.entries` was catastrophically
slow on the VM but lightning fast on dart2js, it would be good if the spec let
each take its own path.

Fortunately, the benchmarks don't seem to show that, so I think we can pick a
single platform-independent desugaring.
