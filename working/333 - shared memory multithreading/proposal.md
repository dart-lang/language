# Shared Memory Multithreading for Dart

This proposal tries to address two long standing gaps which separate Dart from
other more low-level languages:

- Dart developers should be able to utilize multicore capabilities without
  hitting limitations of the isolate model.

- Interoperability between Dart and native platforms (C/C++, Objective-C/Swift,
  Java/Kotlin) requires aligning concurrency models between Dart world and
  native world. The misalignment is not an issue when invoking simple native
  synchronous APIs from Dart, but it becomes a blocker when:

  - working with APIs pinned to a specific thread (e.g. `@MainActor` APIs in
    Swift or UI thread APIs on Android)

  - dealing with APIs which want to call _back_ from native into Dart on an
    arbitrary thread.

  - using Dart as a container for shared business logic - which can be invoked
    on an arbitrary thread by surrounding native application.

  Native code does not _understand_ the concept of isolates.

See [What issues are we trying to solve?](#what-issues-are-we-trying-to-solve)
for concrete code examples.

> [!NOTE]
>
> Improving Dart's interoperability with native code and its multicore
> capabilities not only benefits Dart developers but also unlocks improvements
> in the Dart SDK. For example, we will be able to move `dart:io` implementation
> from C++ into Dart and later split it into a package.

The core of this proposal are two new concepts:

- [Shareable Data](#shareable-data) introduces the relaxation of isolate model
  allowing controlled sharing of mutable data and static state between isolates
  within an isolate group. This allows developer to write Dart code which can
  access shared mutable state concurrently.
- [Shared Isolates](#shared-isolates) introduces a concept of _shared isolate_,
  an isolate which only has access to a state shared between all isolates of the
  group. This concept allows to bridge interoperability gap with native code.
  _Shared isolate_ becomes an answer to the previously unresolved question
  _"what if native code wants to call back into Dart from an arbitrary thread,
  which isolate does the Dart code run in?"_.

In addition to introducing these new concepts the proposal tries to suggest a
number of API changes to various core libraries which are essentially to making
Dart a good multithreaded language. Some of this proposals, like adding
[atomics](#atomic-operations), are fairly straightforward and non-controversial,
others, like [coroutines](#coroutines), are included to show the extent of
possible changes and to provoke thought.

The [Prototyping Roadmap](#prototyping-roadmap) section of the proposal tries to
suggest a possible way forward with validating some of the possible benefits of
the proposal without committing to specific major changes in the Dart language.

## What issues are we trying to solve?

### Parallelizing work-loads

When using isolates it is relatively straightforward to parallelize two types of
workloads:

- The output is a function of input without any significant dependency on other
  state and the input is _cheap to send_ to another isolate. In this case
  developer can use [`Isolate.run`][] to off load the computation to another
  isolate without paying significant costs for the transfer of data.
- The computation that is self contained and runs in background producing
  outputs that are _cheap to send_ to another isolate. In this case a persistent
  isolate can be spawned and stream data to the spawner.

Anything else hits the problem that transferring data between isolates is
asynchronous and incurs copying costs which are linear in the size of
transferred data.

Consider for example a front-end for Dart language which tries to parse a large
Dart program. It is possible to parallelize parsing of strongly connected
components in the import graph, however you can't fully avoid serialization
costs - because resulting ASTs can't be directly shared between isolates.
Similar example is parallelizing loading of ASTs from a large Kernel binary.

> [!NOTE]
>
> Users can create data structures outside of the Dart heap using `dart:ffi` to
> allocate native memory and view it as typed arrays and structs. However,
> adopting such data representation in an existing Dart program is costly and
> comes with memory management challenges characteristic of low-level
> programming languages like C. That's why we would like to enable users to
> share data without requiring them to manually manage lifetime of complicated
> object graphs.
>
> It is worth highlighting **shared memory multithreading does not necessarily
> imply simultaneous access to mutable data.** Developers can still structure
> their parallel code using isolates and message passing - but they can avoid
> the cost of copying the data by sending the message which can be directly
> shared with the receiver rather than copied.

[`Isolate.run`]: https://api.dart.dev/stable/3.2.6/dart-isolate/Isolate/run.html

### Interoperability

Consider the following C code using a miniaudio library:

```cpp
static void DataCallback(
   ma_device* device, void* out, const void* in, ma_uint32 frame_count) {
  // Synchronously process up to |frame_count| frames.
}

ma_device_config config = ma_device_config_init(ma_device_type_playback);
// This function will be called when miniaudio needs more data.
// The call will happend on a backend specific thread dedicated to
// audio playback.
config.dataCallback      = &DataCallback;
// ...
```

Porting this code to Dart using `dart:ffi` is currently impossible, as FFI only
supports two specific callback types:

- [`NativeCallable.isolateLocal`][native-callable-isolate-local]: native caller
  must have an exclusive access to an isolate in which callback was created.
  This type of callback works if Dart calls C and C calls back into Dart
  synchronously. It also works if caller uses VM C API for entering isolates
  (e.g.`Dart_EnterIsolate`/`Dart_ExitIsolate`).
- [`NativeCallable.listener`][native-callable-listener]: native caller
  effectively sends a message to the isolate which created the callback and does
  not synchronously wait for the response.

Neither of these work for this use-case where native caller wants to perform a
synchronous invocation. There are obvious ways to address this:

1. Create a variation of `NativeCallable.isolateLocal` which enters (and after
   call leaves) the target isolate if the native caller is not already in the
   target isolate.

2. Create `NativeCallable.onTemporaryIsolate` which spawns (and after call
   destroys) a temporary isolate to handle the call.

Neither of these are truly satisfactory:

- Allowing `isolateLocal` to enter target isolate means that it can block the
  caller if the target isolate is busy doing _something_ (e.g. processing some
  events) in parallel. This is unacceptable in situations when the caller is
  latency sensitive e.g. audio thread or even just the main UI thread of an
  application.
- Using temporary isolate comes with a bunch of ergonomic problems as every
  invocation is handled using a freshly created environment and no static state
  is carried between invocations - which might surprise the developer. Sharing
  mutable data between invocations requires storing it outside of Dart heap
  using `dart:ffi`.

> [!NOTE]
>
> This particular example might not look entirely convincing because it can be
> reasonably well solved within confines of isolate model.
>
> When you look at an _isolate_ as _a bag of state guarded by a mutex_, you
> eventually realize that this bag is simply way too big - it encompasses the
> static state of the whole program - and this is what makes isolates unhandy to
> use. The rule of thumb is that _coarse locks lead to scalability problems_.
>
> How do you solve it?
>
> _Spawn an isolate that does one specific small task_. In the context of this
> example:
>
> - One isolate (_consumer_) is spawned to do nothing but synchronously handle
>   `DataCallback` calls (using an extension of `isolateLocal` which enters and
>   leaves isolate is required).
> - Another isolate (_producer_) is responsible for generating the data which is
>   fed to the audio-library. The data is allocated in the native heap and
>   directly _shared_ with _consumer_.
>
> However, isolates don't facilitate this style of programming. They are too
> _coarse_ - so it is easy to make a mistake, touch a static state you are not
> supposed to touch, call a dependency which schedules an asynchronous task,
> etc. Furthermore, you do still need a low overhead communication channel
> between isolates. The shared memory is _still_ part of the solution here, even
> though in this particular example we can manage with what `dart:ffi` allows
> us. And that is, in my opinion, a pretty strong signal in favor of more shared
> memory support in the language.

Another variation of this problem occurs when trying to use Dart for sharing
business logic and creating shared libraries. Imagine that `dart:ffi` provided a
way to export static functions as C symbols:

```dart
// foo.dart
import 'dart:ffi' as ffi;

// See https://dartbug.com/51383 for discussion of [ffi.Export] feature.
@ffi.Export()
void foo() {

}
```

Compiling this produces a shared library exporting a symbol with C signature:

```cpp
// foo.h

extern "C" void foo();
```

The native code loads shared library and calls this symbol to invoke Dart code.
Would not this be great?

Unfortunately currently there is no satisfactory way to define what happens when
native code calls this exported symbol as the execution of `foo` is only
meaningful within a specific isolate. Should `foo` create an isolate lazily?
Should there be a single isolate or multiple isolates? What happens if `foo` is
called concurrently from different threads? When should this isolate be
destroyed?

These are all questions without satisfactory answers due to misalignment in
execution modes between the native caller and Dart.

Finally, the variation of the interop problem exists in an opposite direction:
_invoking a native API from Dart on a specific thread_. Consider the following
code for displaying a file open dialog on Mac OS X:

```objc
NSOpenPanel* panel = [NSOpenPanel openPanel];

// Open the panel and return. When user selects a file
// the passed block will be invoked.
[panel beginWithCompletionHandler: ^(NSInteger result){
   // Handle the result.
}];
```

Trying to port this code to Dart hits the following issue: you can only use this
API on the UI thread and Dart's main isolate is not running on the UI thread.
Workarounds similar to discussed before can be applied here as well. You wrap a
piece of Dart code you want to call on a specific thread into a function and
then:

1. Send Dart `isolateLocal` callback to be executed on the specific thread, but
   make it enter (and leave) the target isolate.
2. Create an isolate specific to the target thread (e.g. special _platform
   isolate_ for running on main platform thread) and have callbacks to be run in
   that isolate.

However the issues described above equally apply here: you either hit a problem
with stalling the caller by waiting to acquire an exclusive access to an isolate
or you hit a problem with ergonomics around the lack of shared state.

See [go/dart-interop-native-threading][] and [go/dart-platform-thread][] for
more details around the challenge of crossing isolate-to-thread chasm and why
all different solutions fall short.

[native-callable-isolate-local]: https://api.dart.dev/stable/3.2.4/dart-ffi/NativeCallable/NativeCallable.isolateLocal.html
[native-callable-listener]: https://api.dart.dev/stable/3.2.4/dart-ffi/NativeCallable/NativeCallable.listener.html
[go/dart-interop-native-threading]: http://go/dart-interop-native-threading
[go/dart-platform-thread]: http://go/dart-platform-thread

## Map of the Territory

Before we discuss our proposal for Dart it is worth look at what other popular
and niche languages do around share memory multithreading. If you feel familiar
with the space feel free to skip to [Shareable Data](#shareable-data) section.

**C/C++**, **Java**, **Scala**, **Kotlin**, **C#** all have what I would call an
unrestricted shared memory multithreading:

- objects can be accessed (read and written to) from multiple threads at once
- static state is shared between all threads
- you can spawn new threads using core APIs, which are part of the language
- you can execute code on any thread, even when the thread was spawned
  externally: thread spawned by Java can execute C code and the other way around
  thread spawned by C can execute Java code (after a little dance of _attaching
  Java VM to a thread_).

**Python** and **Ruby**, despite being scripting languages, both provide similar
capabilities around multithreading as well (see [`Thread`][Ruby Thread] in Ruby
and [`threading`][] library in Python). The following Ruby program will spawn 10
threads which all update the same global variable:

```ruby
count = 0
threads = 5.times.map do |i|
  puts "T#{i}: starting"
  Thread.new do
    count += 1
    puts "T#{i}: done"
  end
end

threads.each { |t| t.join }
puts "Counted to #{count}"
```

```console
$ ruby test.rb
T0: starting
T1: starting
T2: starting
T3: starting
T4: starting
T1: done
T4: done
T0: done
T2: done
T3: done
Counted to 5
```

Concurrency in both languages is severely limited by a global lock which
protects interpreter's integrity. This lock is known _Global Interpreter Lock_
(GIL) in Python and _Global VM Lock_ (GVL) in Ruby. GIL/GVL ensures that an
interpreter is only running on one thread at a time. Scheduling mechanisms built
into the interpreter allow it to switch between threads giving each a chance to
run concurrently. This means executions of Python/Ruby code on different threads
are interleaved, but serialized. You can observe non-atomic behaviors and data
races (the VM will not crash though), but you can't utilize multicore
capabilities. CPython developers are actively exploring the possibility to
remove the GIL see [PEP 703][].

**Erlang** is a functional programming language for creating highly concurrent
distributed systems which represents another extreme: no shared memory
multithreading or low-level threading primitives at all. Design principles
behind **Erlang** are summarized in Joe Armstrong's PhD thesis [Making reliable
distributed systems in the presence of software
errors][Joe Armstrong PhD Thesis]. Isolation between lightweight processes which
form a running application is the idea at the very core of **Erlang**'s design,
to quote section 2.4.3 of the thesis:

> The notion of isolation is central to understanding COP, and to the
> construction of fault-tolerant software. Two processes operating on the same
> machine must be as independent as if they ran on physically separated machines
>
> ...
>
> Isolation has several consequences:
>
> 1. Processes have “share nothing” semantics. This is obvious since they are
>    imagined to run on physically separated machines.
> 2. Message passing is the only way to pass data between processes. Again since
>    nothing is shared this is the only means possible to exchange data.
> 3. Isolation implies that message passing is asynchronous. If process
>    communication is synchronous then a software error in the receiver of a
>    message could indefinitely block the sender of the message destroying the
>    property of isolation.
> 4. Since nothing is shared, everything necessary to perform a distributed
>    computation must be copied. Since nothing is shared, and the only way to
>    communicate between processes is by message passing, then we will never
>    know if our messages arrive (remember we said that message passing is
>    inherently unreliable.) The only way to know if a message has been
>    correctly sent is to send a confirmation message back.

**JavaScript** is a variation of _[communicating event-loops][]_ model and its
capabilities clearly both inspired and defined capabilities of Dart's own
isolate model. An isolated JavaScript environment allows only for a single
thread of execution, but multiple such environments
(_[workers][Using Web Workers]_) can be spawned in parallel. These workers share
no object state and communicate via message passing which copies the data sent
with an exception of [transferrable objects][] . Recent versions of
**JavaScript** poked a hole in the isolation boundary by introducing
[`SharedArrayBuffer`][]: allowing developers to share unstructured blobs of
memory between workers.

**Go** [concurrency][go-concurrency] model can be seen as an implementation of
_[communicating sequential processes][]_ formalism proposed by Hoare. **Go**
applications are collections of communicating _goroutines_, lightweight threads
managed by **Go** runtime. These are somewhat similar to **Erlang** processes,
but are not isolated from each other and instead execute inside a shared memory
space. Goroutines communicate using message passing through _channels_. **Go**
does not prevent developer from employing shared memory and provides a number of
classical synchronization primitives like `Mutex`, but heavily discourages this.
Effective Go [contains][effective-go-sharing] the following slogan:

> Do not communicate by sharing memory; instead, share memory by communicating.

> [!NOTE]
>
> It is worth pointing out that managed languages which try to hide shared
> memory (isolated environments of **JavaScript**) and languages which try to
> hide threading (**Go**, **JavaScript**, **Erlang**) are bound to have
> difficulties communicating with languages which don't hide these things. These
> differences create an impedance mismatch between native caller and managed
> callee or the other way around. This is similar to what **Dart** is
> experiencing.

**Rust** gives developers access to shared memory multithreading, but leans onto
_ownership_ expressed through its type system to avoid common programming
pitfalls. See [Fearless Concurrency][] for an overview. **Rust** provides
developers with tools to structure their code both using shared-state
concurrency and message passing concurrency. **Rust** type system makes it
possible to express ownership transfer associated with message passing, which
means the message does not need to be copied to avoid accidental sharing.

**Rust** is not alone in using its type system to eliminate data races. Another
example is **Pony** and its [reference capabilities][].

**Swift** does not fully hide threads and shared memory multi-threading, but it
provides high-level concurrency abstractions _tasks_ and _actors_ on top of
low-level mechanisms (see [Swift concurrency][] for details). **Swift** actors
provide a built-in mechanism to serialize access to mutable state: each actor
comes with an _executor_ which runs tasks accessing actor's state. External code
must use asynchronous calls to access the actor:

```swift
actor A {
    var data: [Int]

    func add(value: Int) -> Int {
      // Code inside an actor is fully synchronous because
      // it has exclusive access to the actor.
      data.append(value)
      return data.count
    }
}

let actor : A

func updateActor() async {
  // Code outside of the actor is asynchronous. The actor
  // might be busy so we might need to suspend and wait
  // for the reply.
  let count = await actor.add(10)
}
```

**Swift** is moving towards enforcing "isolation" between concurrency domains: a
value can only be shared across the boundary (e.g. from one actor to another) if
it conforms to a [`Sendable` protocol][]. Compiler is capable of validating
obvious cases: a deeply immutable type or a value type which will be copied
across the boundary are both obviously `Sendable`. For more complicated cases,
which can't be checked automatically, developers have an escape hatch of simply
declaring their type as conformant by writing `@unchecked Sendable` which
disables compiler enforcement. Hence my choice of putting _isolation_ in quotes.

**OCaml** is multi-paradigm programming language from the ML family of
programming languages. Prior to version 5.0 **OCaml** relied on a _global
runtime lock_ which serialized access to the runtime from different threads
meaning that only a single thread could run **OCaml** code at a time - putting
**OCaml** into the same category as **Python**/**Ruby** with their GIL/GVL.
However in 2022 [after 8 years of work][multicore-ocaml-timeline] **OCaml** 5.0
brought multicore capabilities to **OCaml**. The _**OCaml** Multicore_ project
was seemingly focused on two things:

1. Modernizing runtime system and GC in particular to support multiple threads
   of execution using runtime in parallel (see [Retrofitting Parallelism onto
   OCaml][]).
2. Incorporating _effect handlers_ into the **OCaml** runtime system as a
   generic mechanism on top of which more concrete concurrency mechanisms (e.g.
   lightweight threads, coroutines, `async/await` etc) could be implemented (see
   [Retrofitting Effect Handlers onto OCaml][]).

Unit of parallelism in **OCaml** is a _[domain][ocaml-domain]_ - it's an OS
thread plus some associated runtime structures (e.g. thread local allocation
buffer). Domains are _not_ isolated from each other: they allocate objects in a
global heap, which is shared between all domains and can access and mutate
shared global state.

[PEP 703]: (https://peps.python.org/pep-0703/)
[communicating event-loops]: http://www.erights.org/talks/promises/paper/tgc05.pdf
[transferrable objects]: https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Transferable_objects
[`SharedArrayBuffer`]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer
[Using Web Workers]: https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Using_web_workers
[Ruby Thread]: https://docs.ruby-lang.org/en/3.2/Thread.html
[`threading`]: https://docs.python.org/3/library/threading.html
[Fearless Concurrency]: https://doc.rust-lang.org/book/ch16-00-concurrency.html#fearless-concurrency
[reference capabilities]: https://bluishcoder.co.nz/2017/07/31/reference_capabilities_consume_recover_in_pony.html
[Joe Armstrong PhD Thesis]: https://erlang.org/download/armstrong_thesis_2003.pdf
[Swift concurrency]: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/
[`Sendable` protocol]: https://github.com/apple/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md
[communicating sequential processes]: https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf
[go-concurrency]: https://go.dev/tour/concurrency/1
[effective-go-sharing]: https://go.dev/doc/effective_go#sharing
[multicore-ocaml-timeline]: https://tarides.com/blog/2023-03-02-the-journey-to-ocaml-multicore-bringing-big-ideas-to-life/
[Retrofitting Parallelism onto OCaml]: https://core.ac.uk/download/pdf/328720849.pdf
[Retrofitting Effect Handlers onto OCaml]: https://kcsrk.info/papers/drafts/retro-concurrency.pdf
[ocaml-domain]: https://v2.ocaml.org/manual/parallelism.html#s:par_domains

## Shareable Data

I propose to extend Dart with a shared memory multithreading but provide a clear
type-based delineation between two concurrency worlds. **Only instances of
classes implementing `Shareable` interface can be concurrently mutated by
another thread.** We restrict the kind of data that a shareable class can
contain: **fields of shareable classes can only contain references to instances
of shareable classes.** This requirement is enforced at compile time by
requiring that declared types of all fields are shareable.

```dart
// dart:core

/// [Shareable] instances can be shared between isolates in
/// a group and mutated concurrently.
///
/// A class implementing [Shareable] can only declare fields
/// which have a declared type that is a subtype of [Shareable].
abstract interface class Shareable {
}
```

```dart
class S implements Shareable {
  // ...
}
```

> [!NOTE]
>
> I choose marker interface rather than dedicated syntax (e.g.
> `shareable class`) because marker interface comes handy when declaring type
> bounds for generics and allows to perform runtime checking if needed.

References to shareable instances can be passed between isolates within an
isolate group directly.

```dart
class S implements Shareable {
  int v = 0;
}

void main() async {
  final s = S();

  await Isolate.run(() {
    // Even though the function is running in a different
    // isolate it has access to the original `s` and
    // mutations of `s.v` performed in this isolate will be
    // visible to other isolates.
    //
    // (Subject to memory model constraints).
    s.v = 10;
  });

  expect(equals(10), s.v);
}
```

To make state sharing between isolates simpler we also allow to declare static
fields which are shared between all isolates in the isolate group. `shared`
global fields are required to have shareable declared type.

```dart
// All isolates within an isolate group share this variable.
shared int v = 0;
```

Shareable classes are not required to be immutable. Field reads and writes are
_atomic_, but other than that there are no implicit synchronization, locking or
strong memory barriers associated with fields. Possible executions in terms of
observed values will be specified by the Dart's [memory model](#memory-models) -
which I propose to model after JavaScript's and Go's: **program which is free of
data races will execute in a sequentially consistent manner**.

> [!CAUTION]
>
> Atomicity of field access means considerable overhead on 32-bit platforms for
> reads/writes into unboxed `int` and `double` fields - because these fields are
> 64-bits wide. We might want to eschew atomicity guarantees and allow load
> tearing for primitive fields - though it makes semantics somewhat
> unpredictable and architecture dependent. The same concern applies to unboxed
> SIMD values inside `Shareable` objects.

### Shareable Types

> Type is _shareable_ if and only if one of the following applies:
>
> - It is `Null` or `Never`.
> - It is an interface type which is subtype of `Shareable`.
> - It is a record type where all field types are shareable.
> - It is a nullable type `T?` where `T` is shareable type.

### Why type based opt-in?

There are two main reasons for choosing explicit opt-in into shareability:

1. **Aligning with emerging JS and Wasm capabilities.** Current proposals for
   shared memory multithreading on the Web (see details
   [below](#web-js-and-wasm)) propose partitioning shareable objects from
   non-shareable. We would like to make sure that Dart's semantics is possible
   to translate to both JS and Wasm - allowing us to fully implement our
   concurrency story on the Web.
2. **Enabling graceful adoption of shared memory multithreading.** Shared memory
   multithreading is complicated enough by itself, so I feel that it would
   complicate things more if we were to forcefully bring all existing libraries
   (not written with shared memory in mind) into the world where any data can be
   accessed from multiple threads at once. Existing code will continue to run
   _as is_ within isolates. Newly written code can choose to opt-in into
   shareability where it matters for performance or interoperability reasons.
   Marking class as `Shareable` gives a strong signal that the developer has
   considered implications of sharing instances of these class across threads
   and took measure to ensure that it is safe.

I would like to introduce shared memory multithreading into Dart in a way that
avoids subtle breakages in the existing code. Consider for a moment a library
which maintains a global cache internally and is written under the assumption
that Dart is a single threaded:

```dart
int _nextId = 0;

int allocateId() => _nextId++;
```

This was a valid way to structure this code in single-threaded Dart, but the
same code becomes thread _unsafe_ in the presence of shared memory
multithreading.

### Generics

When declaring a generic type the developer will have to use type parameter
bounds to ensure that resulting class conforms to restrictions imposed by
`Shareable`:

```dart
class X<T> implements Shareable {
  T v;  // compile time error.
}

class Y<T extends Shareable> implements Shareable {
  T v;  // ok.
}
```

> [!NOTE]
>
> We could really benefit from the ability to use intersection types here (see
> [#2709][] and [#1152][], which would allow to specify complicated bounds like
> `T extends Shareable & I`. In the absence of intersections types developers
> would be forced to declare intermediate interfaces which implement all
> required interfaces (e.g.
> `abstract interface ShareableI implements Shareable, I {}`) and require users
> to implement those by specifying `T extends ShareableI`.

[#2709]: https://github.com/dart-lang/language/issues/2709
[#1152]: https://github.com/dart-lang/language/issues/1152

### Functions

Shareability of a function depends on the values that it captures. We could
define that any **function is shareable iff it captures only variables of
shareable declared type**. Incorporating this property into the type system
naturally leads to the desire to use _intersection types_ to express the
property that some value is both a function of a specific type _and_ shareable:

```dart
class A implements Shareable {
  void Function() f;  // compile time error
  void Function() & Shareable f;  // ok
}
```

Introducing intersection types into type system might be a huge undertaking. For
the purposes of developing an MVP we can choose one of the two approaches:

- Ignore functions entirely: consider functions un-shareable. It becomes a
  compile time error to have a function type field inside a shareable class.
- Allow function type fields inside a shareable class, but enforce shareability
  in runtime on assignment to the field.

### Shareable core types

The following types will become shareable:

- `num` (`int` and `double`), `String`, `bool`, `Null`, `BigInt`
- `Enum` and consequently all user defined enums
- `RegExp`, `DateTime`, `Uri`
- `TypedData` - which makes all typed data types shareable.
- `Pointer`
- `Type` and `Symbol`
- `StackTrace`

#### Collections

`dart:core` will provide shareable variants of all collection classes:

```dart
abstract interface class ShareableList<E extends Shareable?>
    implements List<E>, Shareable {
}

abstract interface class ShareableSet<E extends Shareable?>
    implements Set<E>, Shareable {
}

abstract interface class ShareableMap<K extends Shareable?,
                                  V extends Shareable?>
    implements Map<K, V>, Shareable {
}
```

Default implementations of `List`, `Set` and `Map` will be changed to be
shareable if their element type is shareable

```dart
<Shareable>[] is ShareableList<Shareable> // => true
```

We will also provide methods to convert collections to their shareable
counterparts:

```dart
extension ToShareableList<E extends Shareable?> on List<E> {
  /// Converts the list to [ShareableList] if it is not already shareable.
  ShareableList<E> toShareable() =>
    switch (this) {
      final ShareableList<Shareable?> shareable => shareable,
      _ => ShareableList<E>.from(this),
    };
}

extension ToShareableSet<E extends Shareable?> on Set<E> {
  ShareableSet<E> toShareable() => /* ... */
}

extension ToShareableMap<K extends Shareable?,
                         V extends Shareable?> on Map<K, V> {
  ShareableMap<K, V> toShareable() => /* ... */
}
```

### `SendPort` semantics

`SendPort` is extended with a new method to which allows sending `Shareable`
values by reference without copying:

```dart
abstract interface class SendPort {
    /// Sends an asynchronous [message] through this send port, to its
    /// corresponding [ReceivePort].
    ///
    /// The message is passed by reference to the receiver without
    /// copying.
    ///
    /// If sender and receiver do not share the same code then
    /// an [IllegalArgument] exception is thrown.
    void share(Shareable message);
}
```

### `ShareableBox<T>`

In some situations we might need to put a non-shareable value inside a shareable
type. This is okay as long as we can guarantee that this value will only be
accessed within the isolate it originally belonged to.

```dart
abstract interface class ShareableBox<T> implements Shareable {
    factory ShareableBox(T value);
    T get value;
}

abstract interface class MutableShareableBox<T> implements ShareableBox<T> {
    factory MutableShareableBox(T value);
    set value(T newValue);
}
```

> [!NOTE]
>
> It is possible to implement `ShareableBox<T>` on top of `Expando` but for
> efficiency reasons we might want to provide a built-in implementation
>
> ```dart
> class _MutableShareableBoxImpl<T> implements MutableShareableBox<T> {
>     final _lock = Lock();
>     var _token = _AccessToken();
>     static final _values = Expando<AccessToken, (T,)>();
>
>     T get value => _lock.runLocked(() =>
>        switch (_values[_token]) {
>          (final v,) => v,
>          _ => throw StateError("not owned by current isolate"),
>        };
>     });
>
>     set value(T v) {
>        _lock.runLocked(() {
>          // If we don't own this box then reset access token so that
>          // expandos in the other isolate can get cleared.
>          if (_values[_token] == null) {
>      	    _token = _AccessToken();
>          }
>          _values[_token] = v;
>        });
>     }
> }
>
> final class _AccessToken implements Shareable {}
> ```

## Shared Isolates

Lets take another look at the following example:

```dart
int global = 0;

void main() async {
  global = 42;
  await Isolate.run(() {
    print(global);  // => 0
    global = 24;
  });
  print(global);  // => 42
}
```

Stripped to the bare minimum the example does not seem to behave in a confusing
way: it seems obvious that each isolate has its own version of `global` variable
and mutations of `global` are not visible across isolates. However, in the real
world code such behavior might be hidden deep inside a third party dependency
and thus much harder to detect and understand. This behavior also makes
interoperability with native code more awkward than it ought to be: calling Dart
requires an isolate, something that native code does not really know or care
about. Consider for example the following code:

```dart
int global;

@pragma('vm:entry-point')
int foo() => global++;
```

The result of calling `foo` from the native side depends on which isolate the
call occurs in.

`shared` global variables allow developers to tackle this problem - but hidden
dependency on global state might introduce hard to diagnose and debug bugs.

I propose to tackle this problem by introducing the concept of _shared isolate_:
**code running in a _shared isolate_ can only access `shared` state and not any
of isolated state, an attempt to access isolated state results in a dynamic
`IsolationError`**.

```dart
// dart:isolate

class Isolate {
  /// Run the given function [f] in the _shared isolate_.
  ///
  /// Shared isolate contains a copy of the
  /// global `shared` state of the current isolate and does not have any
  /// non-`shared` state of its own. An attempt to access non-`shared` static variable throws [IsolationError].
  ///
  /// If [task] is not [Shareable] then [ArgumentError] is thrown.
  static Future<S> runShared<S extends Shared>(S Function() task);
}
```

```dart
int global = 0;

shared int sharedGlobal = 0;

void main() async {
  global = 42;
  sharedGlobal = 42;
  await Isolate.runShared(() {
    print(global);  // IsolationError: Can't access 'global' when running in shared isolate
    global = 24;  // IsolationError: Can't access 'global' when running in shared isolate

    print(sharedGlobal);  // => 42
    sharedGlobal = 24;
  });
  print(global);  // => 42
  print(sharedGlobal);  // => 24
}
```

### Why not compile time isolation?

It is tempting to try introducing a compile time separation between functions
which only access `shared` state and functions which can access isolated state.
However an attempt to fit such separation into the existing language quickly
breaks down.

One obvious approach is to introduce a modifier (e.g. `shared`) which can be
applied to function declarations and impose a number of restrictions that
`shared` functions have to satisfy. These restrictions should guarantee that
`shared` functions can only access `shared` state.

```dart
shared void foo() {
  // ...
}
```

- You can't override non-`shared` method with `shared` method.
- Within a `shared` function
  - If `f(...)` is a static function invocation then `f` must be a `shared`
    function.
  - If `o.m(...)` is an instance method invocation, then `o` must be a subtype
    of `Shareable` and `m` must be `shared` method.
  - If `C(...)` is a constructor invocation then `C` must be a shareable class.
  - If `g` is a reference to a global variable then `g` must be `shared`.

> [!NOTE]
>
> You can pass non-`Shareable` values to `shared` methods but you can't do
> anything useful with them because you can't touch their state. In other words
> non-`Shareable` types become opaque within `shared` methods.

This approach seems promising on the surface, but quickly hits issues:

- It's unclear how to treat `Object` members like `toString`, `operator ==` and
  `get hashCode`. These can't be marked as `shared` but should be accessible to
  both `shared` and non-`shared` code.
- It's unclear how to treat function expression invocations:
  - Function types don't encode necessary separation between `shared` and
    non-`shared` functions.
  - Methods like `List<T>.forEach` pose challenge because they should be usable
    in both `shared` and non-`shared` contexts.

**This makes us think that language changes required to achieve sound compile
time delineation between `shared` and isolate worlds are too complicated to be
worth it.**

### Upgrading `dart:ffi`

Introduction of _shared isolate_ allows to finally address the problem of native
code invoking Dart callbacks from arbitrary threads.
[`NativeCallable`](https://api.dart.dev/dev/3.3.0-246.0.dev/dart-ffi/NativeCallable-class.html)
can be extended with the corresponding constructor:

```dart
class NativeCallable<T extends Function> {
  /// Constructs a [NativeCallable] that can be invoked from any thread.
  ///
  /// When the native code invokes the function [nativeFunction], the corresponding
  /// [callback] will be synchronously executed on the same thread within a
  /// shared isolate corresponding to the current isolate group.
  ///
  /// [callback] must be [Shareable] that is: all variables it captures must
  /// have shareable declared type.
  external factory NativeCallable.shared(
    @DartRepresentationOf("T") Function callback,
    {Object? exceptionalReturn});
}
```

The function pointer returned by `NativeCallable.shared(...).nativeFunction`
will be bound to an isolate group which produced it using the same trampoline
mechanism FFI uses to create function pointers from closures. Returned function
pointer can be called by native code from any thread. It does not require
exclusive access to a specific isolate and thus avoids interoperability pitfalls
associated with that:

- No need to block native caller and wait for the target isolate to become
  available.
- Clear semantics of globals:
  - `shared` global state is accessible and independent from the current thread;
  - accessing non-`shared` state will throw an `IsolationError`.

#### Linking to Dart code from native code

An introduction of _shared isolate_ allows us to adjust our deployment story and
make it simpler for native code to link, either statically or dynamically, to
Dart code.

> [!NOTE]
>
> Below when I say _native library_ I mean _a static library or shared object
> produced from Dart code using an AOT compiler_. Such native library can be
> linked with the rest of the native code in the application either statically
> at build time or dynamically at runtime using appropriate native linkers
> provided by the native toolchain or the OS. The goal here is that using Dart
> from a native application becomes indistinguishable from using a simple C
> library.

Consider for example previously given in the
[Interoperability](#interoperability) section:

```dart
// foo.dart

import 'dart:ffi' as ffi;

// See https://dartbug.com/51383 for discussion of [ffi.Export] feature.
@ffi.Export()
void foo() {

}
```

which produces a native library exporting a C symbol:

```cpp
// foo.h

extern "C" void foo();
```

Shared isolates give us a tool to define what happens when `foo` is invoked by a
native caller:

- There is a 1-1 correspondence between the native library and an isolate group
  corresponding to this native library (e.g. there is a static variable
  somewhere in the library containing a pointer to the corresponding isolate
  group).
- When an exported symbol is invoked the call happens in the shared isolate of
  that isolate group.

> [!NOTE]
>
> Precise mechanism managing isolate group's lifetime does not matter for the
> purposes of the document and belongs to the separate discussion.

## Core Library Changes

### Upgrading `dart:async` capabilities

#### Shareable `Future` and `Stream` instances

`Future` and `Stream` should receive the same treatment as `List`: `dart:async`
should be extended with shareable versions of these and a way to convert an
existing object to a shareable one.

```dart
class ShareableFuture<T implements Shareable?>
    implements Future<T>, Shareable {
}

class ShareableStream<T implements Shareable?>
    implements Stream<T>, Shareable {
}

extension ToShareableFuture<E extends Shareable?> on Future<E> {
  /// Converts the [Future] to [ShareableFuture] if it is not already shareable.
  ShareableFuture<E> toShareable() => /* ... */;
}

extension ToShareableStream<E extends Shareable?> on Stream<E> {
  /// Converts the [Future] to [ShareableFuture] if it is not already shareable.
  ShareableStream<E> toShareable() => /* ... */;
}
```

The reason for providing these is to allow developers to structure their code
using well understood primitives futures and streams instead of devising new
primitives which reimplement some of the same functionality and is compatible
with threading.

#### Executors of async callbacks

Consider the following code:

```dart
Future<void> foo() async {
  await something();
  print(1);
}

void main() async {
  await Isolate.runShared(() async {
    await foo();
  });
}
```

What happens when `Future` completes in a shared isolate? Who drives event loop
of that isolate? Which thread will callbacks run on?

I propose to introduce another concept similar to `Zone`: `Executor`. Executors
encapsulate the notion of the event loop and control how tasks are executed.

```dart
abstract interface class Executor implements Shareable {
    /// Returns the current executor.
    static Executor get current;

    Isolate get owner;

    /// Schedules the given task to run in the given executor.
    ///
    /// If the current isolate is not the [owner] of this executor
    /// the behavior depends on [copy]:   ///
    ///   * When [copy] is `false` (which is default) [task] is
    ///     expected to be [Shareable] and is transfered to the
    ///     target isolate directly. If it is not [Shareable] then
    ///     `ArgumentError` will be thrown.
    ///   * If [copy] is `true` then [task] is copied to the
    ///     target isolate using the same algorithm [SendPort.send]
    ///     uses.
    ///
    void schedule(void Function() task,
                  {bool copy = false});
}
```

How a particular executor runs scheduled tasks depends on the executor itself:
e.g. an executor can have a pool of threads or notify an embedder that it has
tasks to run and let embedder run these tasks.

All built-in asynchronous primitives will make the following API guarantee: **a
callback passed to `Future` or `Stream` APIs will be invoked using executor
which was running the code which registered the callback.**

> [!NOTE]
>
> We need to be careful here to prevent crossing shareable and non-shareable
> domains. If you have a `Future<T>` where `T` is not a subtype of `Shareable`
> we should not allow registering multiple callbacks on it in a shared isolate
> because these callbacks end up running concurrently.
>
> Consider for example the following code:
>
> ```dart
> final executor = ThreadPool(concurrency: 2);
>
> executor.schedule(() {
>   final Future<List<int>> list = Future.value(<int>[]);
>   list..then(cb1)..then(cb2);
> });
> ```

In other words `fut1 = fut.then(cb)` is equivalent to:

```dart
final result = ShareableBox(Completer<R>());
final callback = ShareableBox(Zone.current.bind(cb));
final executor = Executor.current;
fut.then((v) {
  executor.schedule(() {
    try {
      final r = callback.value(v);
      result.value.complete(r);
    } catch (e, st) {
      result.value.completeError(e, st);
    }
  });
});
final fut1 = result.value.future;
```

> [!NOTE]
>
> There is a clear parallel between `Executor` and `Zone`: asynchronous
> callbacks attached to`Stream` and `Future` are bound to the current `Zone`.
> Original design suggested to treat `Zone` as an executor - but this obscured
> the core of the proposal, so current version splits this into a clear separate
> concept of `Executor`.

#### Structured Concurrency

_Structured concurrency_ is a way of structuring concurrent code where lifecycle
of concurrent tasks has clear relationship to the control-flow structure of the
code which spawned those tasks. One of the most important properties of
structured concurrency is an ability to cancel pending subtasks and propagate
the cancellation recursively.

Consider for example the following code:

```dart
Future<Result> doSomething() async {
    final (a, b) = await (requestA(), computeB()).wait;
    return combineIntoResult(a, b);
}
```

If Dart supported _structured concurrency_, then the following would be
guaranteed:

- If either `requestA` or `computeB` fails, then the other is _canceled_.
- `doSomething` computation can be _canceled_ by the holder of the
  `Future<Result>` and this cancellation will be propagated into `requestA` and
  `computeB`.
- If `computeB` throws an error before `requestA` is awaited then `requestA`
  still gets properly canceled.

Upgrading `dart:async` capabilities in the wake of shared-memory multithreading
is also a good time to introduce some of the structured concurrency concepts
into the language. See
[Cancellable Future](https://gist.github.com/mraleph/6daf658c95be249c2f3cbf186a4205b9)
proposal for the details of how this could work in Dart.

See also:

- [JEP 453 - Structured Concurrency](https://openjdk.org/jeps/453)
- [Wikipedia - Structured Concurrency](https://en.wikipedia.org/wiki/Structured_concurrency)

### `dart:concurrent`

`dart:concurrent` will serve as a library hosting low-level concurrency
primitives.

#### `Thread` and `ThreadPool`

Isolates are _not_ threads even though they are often confused with ones. A code
running within an isolate might be executing on a dedicated OS thread or it
might running on a dedicated pool of threads. When expanding Dart's
multithreading capabilities it seems reasonable to introduce more explicit ways
to control threads.

```dart
// dart:concurrent

abstract class Thread implements Shareable {
  /// Runs the given function in a new thread.
  ///
  /// The function is run in a shared isolate, meaning that
  /// it will not have access to the non-shared state.
  ///
  /// The function will be run in a `Zone` which uses the
  /// spawned thread as an executor for all callbacks: this
  /// means the thread will remain alive as long as there is
  /// a callback referencing it.
  external static Thread start<T>(FutureOr<T> Function() main);

  /// Returns the current thread on which the execution occurs.
  ///
  /// Note: Dart code is only guaranteed to be pinned to a specific OS thread during a synchronous execution.
  external static Thread get current;

  Future<void> join();

  void interrupt();

  external set priority(ThreadPriority value);
  ThreadPriority get priority;
}

/// An [Executor] backed by a fixed size thread
/// pool and owned by the shared isolate of the
/// current isolate (see [Isolate.runShared]).
abstract class ThreadPool implements Executor {
  external factory ThreadPool({required int concurrency});
}
```

Additionally I think providing a way to synchronously execute code in a specific
isolate on the _current_ thread might be useful:

```dart
class Isolate {
    T runSync<T>(T Function() cb);
}
```

##### Asynchronous code and threads

Consider the following example:

```dart
Thread.start(() async {
  var v = await foo();
  var u = await bar();
});
```

Connecting execution / scheduling behavior to `Zone` allows us to give a clear
semantics to this code: this code will run on a specific (newly spawned) thread
and will not change threads between suspending and resumptions.

#### Atomic operations

`AtomicRef<T>` is a wrapper around a value of type `T` which can be updated
atomically. It can only be used with true reference types - an attempt to create
an `AtomicRef<int>`, `AtomicRef<double>` , `AtomicRef<(T1, ..., Tn)>` will
throw.

> [!NOTE]
>
> `AtomicRef` uses method based `load` / `store` API instead of simple
> getter/setter API (i.e. `abstract T value`) for two reasons:
>
> 1. We want to align this API with that of extensions like `Int32ListAtomics`,
>    which use `atomicLoad`/`atomicStore` naming
> 2. We want to keep a possibility to later extend these methods, e.g. add a
>    named parameter which specifies particular memory ordering.

```dart
// dart:concurrent

class AtomicRef<T extends Shareable> implements Shareable {
  /// Atomically updates the current value to [desired].
  ///
  /// The store has release memory order semantics.
  void store(T desired);

  /// Atomically reads the current value.
  ///
  /// The load has acquire memory order semantics.
  T load();

  /// Atomically compares whether the current value is identical to
  /// [expected] and if it is sets it to [desired] and returns
  /// `(true, expected)`.
  ///
  /// Otherwise the value is not changed and `(false, currentValue)` is
  /// returned.
  (bool, T) compareAndSwap(T expected, T desired);
}

class AtomicInt32 implements Shareable {
  void store(int value);
  int load();
  (bool, int) compareAndSwap(int expected, int desired);

  int fetchAdd(int v);
  int fetchSub(int v);
  int fetchAnd(int v);
  int fetchOr(int v);
  int fetchXor(int v);
}

extension Int32ListAtomics on Int32List {
  void atomicStore(int index, int value);
  int atomicLoad(int index);
  (bool, int) compareAndSwap(int index, int expected, int desired);
  int fetchAdd(int index, int v);
  int fetchSub(int index, int v);
  int fetchAnd(int index, int v);
  int fetchOr(int index, int v);
  int fetchXor(int index, int v);
}

// These extension methods will only work on fixed-length builtin
// List<T> type and will throw an error otherwise.
extension RefListAtomics<T extends Shareable> on List<T> {
  void atomicStore(int index, T value);
  T atomicLoad(int index);
  (bool, T) compareAndSwap(T expected, T desired);
}
```

#### Locks and conditions

At the bare minimum libraries should provide a non-reentrant `Lock` and a
`Condition`. However we might want to provide more complicated synchronization
primitives like re-entrant or reader-writer locks.

```dart
// dart:concurrent

// Non-reentrant Lock.
class Lock implements Shareable {
  void acquireSync();
  bool tryAcquireSync({Duration? timeout});

  void release();

  Future<void> acquire();
  Future<bool> tryAcquire({Duration? timeout});
}

class Condition implements Shareable {
  bool waitSync(Lock lock, {Duration? timeout});
  Future<bool> wait(Lock lock, {Duration? timeout});

  void notify();
  void notifyAll();
}
```

> [!NOTE]
>
> Java has a number of features around synchronization:
>
> - It allows any object to be used for synchronization purposes.
> - It has convenient syntax for grabbing a monitor associated with an object:
>   `synchronized (obj) { /* block */ }`.
> - It allows marking methods with `synchronized` keyword - which is more or
>   less equivalent to wrapping method's body into `synchronized` block.
>
> I don't think we want these features in Dart:
>
> - Supporting synchronization on any object comes with severe implementation
>   complexity.
> - A closure based API `R withLock<R>(lock, R Function() body)` should provide
>   a good enough alternative to special syntactic forms like `synchronized`.
> - An explicit locking in the body of the method is clearer than implicit
>   locking introduced by an attribute.

#### Coroutines

Given that we are adding support for OS threads we should consider if we want to
add support for _coroutines_ (also known as _fibers_, or _lightweight threads_)
as well.

```dart
abstract interface class Coroutine {
  /// Return currently running coroutine if any.
  static Coroutine? get current;

  /// Create a suspended coroutine which will execute the given
  /// [body] when resumed.
  static Coroutine create(void Function() body);

  /// Suspends the given currently running coroutine.
  ///
  /// This makes `resume` return with
  /// Expects resumer to pass back a value of type [R].
  static void suspend();

  /// Resumes previously suspended coroutine.
  ///
  /// If there is a coroutine currently running the suspends it
  /// first.
  void resume();

  /// Resumes previously suspended coroutine with exception.
  void resumeWithException(Object error, [StackTrace? st]);
}
```

Coroutines is a very powerful abstraction which allows to write straight-line
code which depends on asynchronous values.

```dart
Future<String> request(String uri);

extension FutureSuspend<T> on Future<T> {
  T get value {
    final cor = Coroutine.current ?? throw 'Not on a coroutine';
    late final T value;
    this.then((v) {
      value = v;
      cor.resume();
    }, onError: cor.resumeWithException);
    cor.suspend();
    return value;
  }
}

List<String> requestAll(List<String> uris) =>
  Future.wait(uris.map(request)).value;

SomeResult processUris(List<String> uris) {
	final data = requestAll(uris);
  // some processing of [data]
  // ...
}

void main() {
  final uris = [...];
  Coroutine.create(() {
    final result = processUris(uris);
    print(result);
  }).resume();
}
```

#### Blocking operations

It might be useful to augment existing types like `Future`, `Stream` and
`ReceivePort` with blocking APIs which would only be usable in shared isolate
and under condition that it is not going to block the executor's event loop.

### `dart:ffi` updates

`dart:ffi` should expose atomic reads and writes for native memory.

```dart
extension Int32PointerAtomics on Pointer<Int32> {
  void atomicStore(int value);
  int atomicLoad();
  (bool, int) compareAndSwap(int expected, int desired);
  int fetchAdd(int v);
  int fetchSub(int v);
  int fetchAnd(int v);
  int fetchOr(int v);
  int fetchXor(int v);
}

extension IntPtrPointerAtomics on Pointer<IntPtr> {
  void atomicStore(int value);
  int atomicLoad();
  (bool, int) compareAndSwap(int expected, int desired);
  int fetchAdd(int v);
  int fetchSub(int v);
  int fetchAnd(int v);
  int fetchOr(int v);
  int fetchXor(int v);
}

extension PointerPointerAtomics<T> on Pointer<Pointer<T>> {
  void atomicStore(Pointer<T> value);
  Pointer<T> atomicLoad();
  (bool, Pointer<T>) compareAndSwap(Pointer<T> expected, Pointer<T> desired);
}
```

For convenience reasons we might also consider making the following work:

```dart
final class MyStruct extends Struct {
  @Int32()
  external final AtomicInt value;
}
```

The user is expected to use `a.value.store(...)` and `a.value.load(...` to
access the value.

> [!CAUTION]
>
> Support for `AtomicInt` in FFI structs is meant to enable atomic access to
> fields without requiring developers to go through `Pointer` based atomic APIs.
> It is **not** meant as a way to interoperate with structs that contain
> `std::atomic<int32_t>` (C++) or `_Atomic int32_t` (C11) because these types
> don't have a defined ABI.

## Prototyping Roadmap

The change of this impact has to be carefully evaluated. I suggest we start with
bare minimum needed to validate share memory concurrency in a realistic setting:

1. Implement `shared` global fields using a VM specific pragma
   `@pragma('vm:shared')`.
2. Hiding under an experimental flag and in a separate library (e.g.
   `dart:concurrent`):

- Introduce `Shareable` interface and enforce suggested restrictions using a
  Kernel transformation instead of incorporating them into CFE.
- Introduce minimum amount of core library changes (e.g. `ShareableList`).

With these changes we can try prototyping a multicore based optimization in
either CFE or analyzer and assess the usability and the impact of the change.

Next we can add support for shared isolates and use that to prototype and
evaluate benefits for the interop (e.g. write some code which uses thread pinned
native API).

With feedback from these experiments we can update the proposal and formulate
concrete plans on how we should proceed.

## Appendix

### Memory Models

Memory model describes the range of possible behaviors of multi-threaded
programs which read and write shared memory. Programmer looks at the memory
model to understand how their program will behave. Compiler engineer looks at
the memory model to figure out which code transformations and optimization are
valid. The table below provides an overview of memory models for some widely
used languages.

| Language   | Memory Model                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C#         | Language specification itself (ECMA-334) does not describe any memory mode. Instead the memory model is given in Common Language Infrastructure (ECMA-335, section _I.12.6 Memory model and optimizations_). ECMA-335 memory model is relatively weak and CLR provides stronger guarantees documented [here](https://github.com/dotnet/runtime/blob/main/docs/design/specs/Memory-model.md). See [dotnet/runtime#63474](https://github.com/dotnet/runtime/issues/63474) and [dotnet/runtime#75790](https://github.com/dotnet/runtime/pull/75790) for some additional context. |
| JavaScript | Memory model is documented in [ECMA-262 section 13.0 _Memory Model_](https://262.ecma-international.org/13.0/#sec-memory-model)_._ This memory model is fairly straightforward: it guarantees sequential consistency for atomic operations, while leaving other operations unordered.                                                                                                                                                                                                                                                                                         |
| Java       | Given in [Java Language Specification (JLS) section 17.4](https://docs.oracle.com/javase/specs/jls/se19/html/jls-17.html#jls-17.4)                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Kotlin     | Not documented. Kotlin/JVM effectively inherits Java's memory model. Kotlin/Native - does not have a specified memory model, but likely follows JVM's one as well.                                                                                                                                                                                                                                                                                                                                                                                                            |
| C++        | Given in the section [Multi-threaded executions and data races](https://eel.is/c++draft/intro.multithread) of the standard (since C++11). Notably very fine grained                                                                                                                                                                                                                                                                                                                                                                                                           |
| Rust       | No official memory model according to [reference](https://doc.rust-lang.org/reference/memory-model.html), however it is documented to "[blatantly inherit C++20 memory model](https://doc.rust-lang.org/nomicon/atomics.html)"                                                                                                                                                                                                                                                                                                                                                |
| Swift      | Defined to be consistent with C/C++. See [SE-0282](https://github.com/apple/swift-evolution/blob/main/proposals/0282-atomics.md)                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Go         | Given [here](https://go.dev/ref/mem): race free programs have sequential consistency, programs with races still have some non-deterministic but well-defined behavior.                                                                                                                                                                                                                                                                                                                                                                                                        |

### Platform capabilities

When expanding Dart's capabilities we need to consider if this semantic can be
implemented across the platforms that Dart runs on.

#### Native

No blockers to implement any multithreading behavior. VM already has a concept
of _isolate groups_: multiple isolates concurrently sharing the same heap and
runtime infrastructure (GC, program structure, debugger, etc).

#### Web (JS and Wasm)

No shared memory multithreading currently (beyond unstructured binary data
shared via `SharedArrayBuffer`). However there is a Stage 1 TC-39 proposal
[JavaScript Structs: Fixed Layout Objects and Some Synchronization Primitives](https://github.com/tc39/proposal-structs)
which introduces the concept of _struct_ - fixed shape mutable object which can
be shared between different workers. Structs are very similar to `Shareable`
objects I propose, however they can't have any methods associated with them.
This makes structs unsuitable for representing arbitrary Dart classes - which
usually have methods associated with them.

Wasm GC does not have a well defined concurrency story, but a
[shared-everything-threads](https://github.com/WebAssembly/shared-everything-threads/pull/23)
proposal is under design. This proposal seems expressive enough for us to be
able to implement proposed semantics on top of it.

> [!NOTE]
>
> Despite shared memory Wasm proposal has an issue which makes it challenging
> for Dart to adopt it:
>
> 1. It prohibits sharable and non-shareable structs to be subtypes of each
>    other.
> 2. It prohibits `externref` inside shareable structs
>
> Dart has `Object` as a base class for both shareable and non-shareable
> classes. If a program contains `Shareable` type - such type would need to be
> represented as a `shared` struct which means we have to mark `Object` struct
> as `shared` as well. But this means Dart objects can no longer directly
> contain `externref`s inside them.
>
> Assuming that Wasm is going to move forward with type based partitioning, we
> can still resolve this conundrum by employing a
> [`ShareableBox`](#shareableboxt)-like wrapper, which can be implemented on top
> of TLS storage and `WeakMap`.
>
> An alternative could be to tweak semantics of Wasm's `externref` a bit: tag
> `externref` with their origin and dynamically checking origin match when
> `externref` is passed back from Wasm to the host environment (see
> [Dynamic sharedness checks as an escape hatch](https://github.com/WebAssembly/shared-everything-threads/issues/37)
> issue).

### `dart:*` race safety

When implementing `dart:*` libraries we should keep racy access in mind.
Consider for example the following code:

```dart
class _GrowableList<T> implements List<T> {
  int length;
  final _Array storage;

  T operator[](int index) {
    RangeError.checkValidIndex(index, this, "index", this.length);
    return unsafeCast(storage[index]);  // (*)
  }

  T removeLast() {
    final result = this[length];
    storage[length--] = null;
    return result;
  }
}
```

This code is absolutely correct in single-threaded environment, but can cause
heap-safety violation in a racy program: if `operator[]` races with `removeLast`
then `storage[index]` might return `null` even though `checkValidIndex`
succeeded.

## Acknowledgements

The author thanks @aam @brianquinlan @dcharkes @kevmoo @liamappelbe @loic-sharma
@lrhn @yjbanov for providing feedback on the proposal.
