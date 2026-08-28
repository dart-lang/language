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

This proposal:

- allows developer to selectively break isolation boundary between isolates by
declaring some static fields to be [_shared_](#shared-fields) between isolates
within isolate group.

- introduces the concept of [_shared isolate_](#shared-isolates),
an isolate which only has access to a state shared between all isolates of the
group. This concept allows to bridge interoperability gap with native code.
_Shared isolate_ becomes an answer to the previously unresolved question
_"what if native code wants to call back into Dart from an arbitrary thread,
which isolate does the Dart code run in?"_.

> [!NOTE]
>
> Earlier version of this proposal was also introducing the concept of
> _shareable data_ based on a marker interface (`Shareable`) which
> required developer to explicitly opt in into shared memory multithreading
> for their classes. In this model only instances of classes which implement
> the marker interface could be shared between isolates.
>
> Based on the extensive discussions with the language team and implementors
> I have arrived to the conclusion that this separation does not have clear
> benefits which are worth the associated implementation complexity.
> Consequently I remove this concept from the proposal and instead propose
> that we eventually allow unrestricted _share everything_ multithreading
> within the isolate group.

Additionally the proposal tries to suggest a number of API changes to various
core libraries which are essentially to making Dart a good multithreaded
language. Some of this proposals, like adding [atomics](#atomic-operations),
are fairly straightforward and non-controversial, others, like
[coroutines](#coroutines), are included to show the extent of
possible changes and to provoke thought.

The [Implementation Roadmap](#implementation-roadmap) section of the proposal
tries to suggest a possible way forward with validating some of the possible
benefits of the proposal without committing to specific major changes in the
Dart language.

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
with the space feel free to skip to [Shared Isolate](#shared-isolate) section.

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

## Shared Fields

Normally each isolate gets its own fresh copy of all static fields. If one
isolate changes one of the fields no other isolate can observe this change.
I propose to punch a hole in this boundary by allowing programmer to opt out
of this isolation: a field marked as `shared` will be shared between all
isolates. Changing a field in one isolate can be observed from another isolate.

Shared fields should guarantee atomic initialization: if multiple threads
access the same uninitialized field then only one thread will invoke the
initializer and initialize the field, all other threads will block until
initialization it complete.

In the _shared **everything** multithreading_ shared fields can be allowed to
contain anything - including instances of mutable Dart classes. However,
initially I propose to limit shared fields by allowing only _trivially shareable
types_, which include:

- Objects which do not contain mutable state and thus can already pass through
  `SendPort` without copying:
  - strings;
  - numbers;
  - instances of [deeply immutable][] types;
  - instances of internal implementation of `SendPort`;
  - tear-offs of static methods;
  - compile time constants;
- Objects which contain non-structural (binary) mutable state:
  - `TypedData`
  - `Struct` instances
- Closures which capture variables which are annotated with `@pragma('vm:shared')`
  and are of trivially shareable types;

Sharing of these types does not break isolate boundaries.

[deeply immutable]: https://github.com/dart-lang/sdk/blob/bb59b5c72c52369e1b0d21940008c4be7e6d43b3/runtime/docs/deeply_immutable.md

> [!NOTE]
>
> It might seem strange to include mutable types like `TypedData` into trivially
> shareable, but in reality allowing to share these type does not actually
> introduce any fundamentally new capabilities. A `TypedData` instance can
> already be backed by native memory and as such shared between two
> isolates.

> [!NOTE]
>
> Types like `SendPort` are not `final` so strictly speaking we can't make a
> decision whether an instance of `SendPort` is trivially shareable or not
> based on the static type alone. Instead we must dynamically check if
> `SendPort` is an internal implementation or not. Similar tweak should probably
> be applied to the specification of `@pragma('vm:deeply-immutable')`
> allowing classes containing `SendPort` fields to be marked `deeply-immutable`
> at the cost of introducing additional runtime checks when the object is created.

> [!CAUTION]
>
> Shared field reads and writes are _atomic_ for reference types, but other
> than that there are no implicit synchronization, locking or strong memory
> barriers associated with shared fields. Possible executions in terms of
> observed values will be specified by the Dart's [memory model](#memory-models)
> which I propose to model after JavaScript's and Go's: **program which is
> free of data races will execute in a sequentially consistent manner**.
>
> Furthermore, shared fields of `int` and `double` types are allowed to exhibit
> _tearing_ on 32-bit platforms.

> [!NOTE]
>
> There is no static type marker for a trivially shareable closure. For convenience
> reasons we should allow writing `@pragma('vm:shared') void Function() foo;` but
> will have to check shareability in runtime when such variable is initialized.

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
  external static Future<S> runShared<S>(S Function() task);
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

> [!NOTE]
>
> It is tempting to try introducing a compile time separation between functions
> which only access `shared` state and functions which can access isolated state.
> However an attempt to fit such separation into the existing language requires
> significant and complex language changes: type system would need capabilities
> to express which functions touch isolate state and which only touch `shared`
> state. Things will get especially complicated around higher-order functions
> like those on `List`.

### Upgrading `dart:ffi`

Introduction of _shared isolate_ allows to finally address the problem of native
code invoking Dart callbacks from arbitrary threads.
[`NativeCallable`](https://api.dart.dev/dev/3.3.0-246.0.dev/dart-ffi/NativeCallable-class.html)
can be extended with the corresponding constructor:

```dart
class NativeCallable<T extends Function> {
  /// Constructs a [NativeCallable] that can be invoked from any thread.
  ///
  /// When the native code invokes the function [nativeFunction], the
  /// corresponding [callback] will be synchronously executed on the same
  /// thread within a shared isolate corresponding to the current isolate group.
  ///
  /// Throws [ArgumentError] if [callback] captures state which can't be
  /// transferred to shared isolate without copying.
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

In _shared **everything** multithreading_ world `callback` can be allowed to
capture arbitrary state, however in _shared **native memory** multithreading_
this state has to be restricted to trivially shareable types. To make it
completely unambigious we impose an additional requirement that all variables
captured by a closure will need to be annotated with `@pragma('vm:shared')`:


```dart
// This code is okay because the variable is annotated and `int` is
// trivially shareable.
@pragma('vm:shared')
int counter = 0;
NativeCallable.shared(() {
  counter++;
});

// This code causes a runtime error because `counter` is not not
// annotated with vm:shared pragma.
int counter = 0;
NativeCallable.shared(() {
  counter++;
});

// This code is not okay because `List<T>` is not trivially shareable.
@pragma('vm:shared')
List<int> list = [];
NativeCallable.shared(() {
  list.add(1);
});
```

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

What happens when `Future` completes in the shared isolate? Who drives event loop
of that isolate? Which thread will callbacks run on?

I propose to introduce another concept similar to `Zone`: `Executor`. Executors
encapsulate the notion of the event loop and control how tasks are executed.

```dart
abstract interface class Executor {
    /// Current executor
    static Executor get current;

    Isolate get owner;

    /// Schedules the given task to run in the given executor.
    void schedule(void Function() task);
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

abstract class Thread {
  /// Runs the given function in a new thread.
  ///
  /// The function is run in the shared isolate, meaning that
  /// it will not have access to the non-shared state.
  ///
  /// The function will be run in a `Zone` which uses the
  /// spawned thread as an executor for all callbacks: this
  /// means the thread will remain alive as long as there is
  /// a callback referencing it.
  external static Thread start<T>(FutureOr<T> Function() main);

  /// Current thread on which the execution occurs.
  ///
  /// Note: Dart code is only guaranteed to be pinned to a specific OS thread
  /// during a synchronous execution.
  external static Thread get current;

  external Future<void> join();

  external void interrupt();

  external set priority(ThreadPriority value);

  external ThreadPriority get priority;
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
    external T runSync<T>(T Function() cb);
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
throw. The reason from disallowing this types is to avoid implementation
complexity in `compareAndSwap` which is defined in terms of `identity`. We also
impose the restriction on `compareAndSwap`.

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

final class AtomicRef<T> {
  /// Creates an [AtomicRef] initialized with the given value.
  ///
  /// Throws `ArgumentError` if `T` is a subtype of [num] or [Record].
  external factory AtomicRef(T initialValue);

  /// Atomically updates the current value to [desired].
  ///
  /// The store has release memory order semantics.
  external void store(T desired);

  /// Atomically reads the current value.
  ///
  /// The load has acquire memory order semantics.
  external T load();

  /// Atomically compares whether the current value is identical to
  /// [expected] and if it is sets it to [desired] and returns
  /// `(true, expected)`.
  ///
  /// Otherwise the value is not changed and `(false, currentValue)` is
  /// returned.
  ///
  /// Throws argument error if `expected` is a instance of [int], [double] or
  /// [Record].
  external (bool, T) compareAndSwap(T expected, T desired);
}

final class AtomicInt32 {
  external void store(int value);
  external int load();
  external (bool, int) compareAndSwap(int expected, int desired);

  external int fetchAdd(int v);
  external int fetchSub(int v);
  external int fetchAnd(int v);
  external int fetchOr(int v);
  external int fetchXor(int v);
}

final class AtomicInt64 {
  external void store(int value);
  external int load();
  external (bool, int) compareAndSwap(int expected, int desired);

  external int fetchAdd(int v);
  external int fetchSub(int v);
  external int fetchAnd(int v);
  external int fetchOr(int v);
  external int fetchXor(int v);
}

extension Int32ListAtomics on Int32List {
  external void atomicStore(int index, int value);
  external int atomicLoad(int index);
  external (bool, int) compareAndSwap(int index, int expected, int desired);
  external int fetchAdd(int index, int v);
  external int fetchSub(int index, int v);
  external int fetchAnd(int index, int v);
  external int fetchOr(int index, int v);
  external int fetchXor(int index, int v);
}

extension Int64ListAtomics on Int64List {
  external void atomicStore(int index, int value);
  external int atomicLoad(int index);
  external (bool, int) compareAndSwap(int index, int expected, int desired);
  external int fetchAdd(int index, int v);
  external int fetchSub(int index, int v);
  external int fetchAnd(int index, int v);
  external int fetchOr(int index, int v);
  external int fetchXor(int index, int v);
}


// These extension methods will only work on fixed-length builtin
// List<T> type and will throw an error otherwise.
extension RefListAtomics<T> on List<T> {
  external void atomicStore(int index, T value);
  external T atomicLoad(int index);
  external (bool, T) compareAndSwap(T expected, T desired);
}
```

#### Locks and conditions

At the bare minimum libraries should provide a non-reentrant `Lock` and a
`Condition`. However we might want to provide more complicated synchronization
primitives like re-entrant or reader-writer locks.

```dart
// dart:concurrent

// Non-reentrant Lock.
final class Lock {
  external void acquireSync();
  external bool tryAcquireSync({Duration? timeout});

  external void release();

  external Future<void> acquire();
  external Future<bool> tryAcquire({Duration? timeout});
}

final class Condition {
  external bool waitSync(Lock lock, {Duration? timeout});
  external Future<bool> wait(Lock lock, {Duration? timeout});

  external void notify();
  external void notifyAll();
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
  external static Coroutine? get current;

  /// Create a suspended coroutine which will execute the given
  /// [body] when resumed.
  external static Coroutine create(void Function() body);

  /// Suspends the given currently running coroutine.
  external static void suspend();

  /// Resumes previously suspended coroutine.
  ///
  /// If there is a coroutine currently running the suspends it
  /// first.
  external void resume();

  /// Resumes previously suspended coroutine with exception.
  external void resumeWithException(Object error, [StackTrace? st]);
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
  external void atomicStore(int value);
  external int atomicLoad();
  external (bool, int) compareAndSwap(int expected, int desired);
  external int fetchAdd(int v);
  external int fetchSub(int v);
  external int fetchAnd(int v);
  external int fetchOr(int v);
  external int fetchXor(int v);
}

extension IntPtrPointerAtomics on Pointer<IntPtr> {
  external void atomicStore(int value);
  external int atomicLoad();
  external (bool, int) compareAndSwap(int expected, int desired);
  external int fetchAdd(int v);
  external int fetchSub(int v);
  external int fetchAnd(int v);
  external int fetchOr(int v);
  external int fetchXor(int v);
}

extension PointerPointerAtomics<T> on Pointer<Pointer<T>> {
  external void atomicStore(Pointer<T> value);
  external Pointer<T> atomicLoad();
  external (bool, Pointer<T>) compareAndSwap(Pointer<T> expected, Pointer<T> desired);
}
```

For convenience reasons we might also consider making the following work:

```dart
final class MyStruct extends Struct {
  @Int32()
  external final AtomicInt32 value;
}
```

The user is expected to use `a.value.store(...)` and `a.value.load(...` to
access the value.

> [!CAUTION]
>
> Support for `AtomicInt<N>` in FFI structs is meant to enable atomic access to
> fields without requiring developers to go through `Pointer` based atomic APIs.
> It is **not** meant as a way to interoperate with structs that contain
> `std::atomic<int32_t>` (C++) or `_Atomic int32_t` (C11) because these types
> don't have a defined ABI.

## Implementation Roadmap

We start by implementing _shared isolates_ and allowing `shared` global
fields (designated via `@pragma('vm:shared')` rather than a keyword) of
trivially shareable types. We then expose shared isolates to FFI by introducing
`NativeCallable.shared` and allowing to call into an isolate group from
an arbitrary thread.

These changes do not significantly change the shape of Dart programming
language, they streamline the interoperability with native code but do not
introduce any new fundamental capabilities: developers can already share
native memory between isolates and that simply makes such sharing more
convenient to use. There is no sharing of mutable Dart objects at this stage
yet.

Consequently I feel that this set of features (_shared **native** memory
multithreading_) can be shipped to Dart developers and that will significantly
streamline out interoperability story.

Separately from this we will work on allowing to share arbitrary Dart objects
_under an experimental flag_. And use these capabilities to prototype
multicore based optimizations in either CFE or analyzer and assess the
usability and the impact of the change.

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
be shared between different workers. Structs can't have any methods associated
with them. This makes structs unsuitable for representing arbitrary Dart
classes - which usually have methods associated with them.

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
> If Dart introduces share memory multithreading it would need to mark
> `struct` type representing `Object` as `shared`, but this means Dart objects
> can no longer directly contain `externref`s inside them.
>
> Assuming that Wasm is going to move forward with type based partitioning, we
> would need to resolve this conundrum by employing some sort of thread local
> wrapper, which can be implemented on top of TLS storage and `WeakMap`.

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
