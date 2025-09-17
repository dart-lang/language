# Shared _Native_ Memory Multithreading

This document specifies subset of the original [proposal](proposal.md), which
is currently being implemented as part of
[Issue #56841](https://github.com/dart-lang/sdk/issues/56841).

## Problem: Synchronous Interoperability Chasm

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

See [go/dart-interop-native-threading][] and [go/dart-platform-thread][] for
more details around the challenge of crossing isolate-to-thread chasm and why
all different solutions fall short.

[native-callable-isolate-local]: https://api.dart.dev/stable/3.2.4/dart-ffi/NativeCallable/NativeCallable.isolateLocal.html
[native-callable-listener]: https://api.dart.dev/stable/3.2.4/dart-ffi/NativeCallable/NativeCallable.listener.html
[go/dart-interop-native-threading]: http://go/dart-interop-native-threading
[go/dart-platform-thread]: http://go/dart-platform-thread

## Proposed Solution

We propose to reduce the distance between native code and Dart by:

- Allowing to execute Dart code within specific _isolate group_, but outside
  of a specific isolate.
- Introducing APIs and core library changes to facilitate writing Dart code
  which utilizes **shared _native_ memory** without breaking existing
  Dart-level isolation boundaries.

### Trivially shareable objects

_Trivially shareable objects_ are objects which can be shared across isolate
boundaries (within an isolate group) without breaking isolation of mutable
Dart state.

- Instances of `String`, `int`, `double`, `bool` and `Null` are trivially shareable.
- Instances of [deeply immutable][] types.
- Instances of internal implementation of `SendPort`.
- Functions which only capture variables annotated with `@pragma('vm:shared')`
  (this includes function which do not capture any variables e.g. tear-offs of
  static methods).
- Compile time constants (instances produced by evaluation of `const` expressions).
- Instances of `TypedData`.
- Instances of `Pointer` and `Struct`.

> [!WARNING]
>
> Not all _trivially shareable objects_ can be purely distinguished by their
> static type - `SendPort` is an example which requires runtime checking.

> [!IMPORTANT]
>
> **TODO** should we allow sharing of all `TypedData` objects? This seems very
> convenient. There is a consideration here that not all `TypedData` instances
> can be shared on the Web, where there is separation between `ArrayBuffer`
> and `SharedArrayBuffer` exists.
>
> **TODO** should we allow sharing instances of immutable `List`s which only
> contain trivially shareable objects? This in general case requires `O(1)`
> check, but might be very convenient as well.

[deeply immutable]: https://github.com/dart-lang/sdk/blob/bb59b5c72c52369e1b0d21940008c4be7e6d43b3/runtime/docs/deeply_immutable.md

### Shared fields and variables (`@pragma('vm:shared')`).

Static fields and global variables annotated with `@pragma('vm:shared')` are
shared across all isolates in the isolate group - updating a field from one
isolate.

A field or variable annotated with `@pragma('vm:shared')` can only contain
values which are trivially shareable objects.

* It is a compile time error to annotate a field or variable the static type of
  which excludes trivially shareable objects;
* If static type of a field is a super-type for both trivially shareable and
  non-trivially shareable objects then compiler will insert a runtime check
  which ensures that values assigned to such field is trivially shareable.

Shared fields must guarantee atomic initialization: if multiple threads
access the same uninitialized field then only one thread will invoke the
initializer and initialize the field, all other threads will block until
initialization is complete.

Outside of initialization we however do **not** require strong (e.g.
sequentially consistent) atomicity when reading or writing shared fields.
We only require that no thread can ever observe a partially initialized Dart
object. See [Memory Model](#memory-model) for more details.

### `NativeCallable.isolateGroupBound`

Today Dart runtime always executes Dart code within a specific isolate.
`NativeCallable.isolateGroupBound` introduces a way to execute Dart code
within specific _isolate group_ but outside of a specific isolate. When Dart
code is executed in such a way it can only access static state which is shared
between isolates (`@pragma('vm:shared')`) and attempts to access isolated state
will cause `FieldAccessError` to be thrown.

```dart
  /// Constructs a [NativeCallable] that can be invoked from any thread.
  ///
  /// When the native code invokes the function [nativeFunction], 
  /// the [callback] will be executed within the isolate group
  /// of the [Isolate] which originally constructed the callable. 
  /// Specifically, this means that an attempt to access any 
  /// static or global field which is not shared between 
  /// isolates in a group will result in a [FieldAccessError].
  ///
  /// If an exception is thrown by the [callback], the 
  /// native function will return the `exceptionalReturn`, 
  /// which must be assignable to the return type of 
  /// the [callback].
  ///
  /// [callback] and [exceptionalReturn] must be 
  /// _trivially shareable_.
  ///
  /// This callback must be [close]d when it is no longer 
  /// needed. An [Isolate] that created the callback will 
  /// be kept alive until [close] is called.
  ///
  /// After [NativeCallable.close] is called, invoking 
  /// the [nativeFunction] from native code will cause 
  /// undefined behavior.
  factory NativeCallable.isolateGroupBound(
    @DartRepresentationOf("T") Function callback, {
    Object? exceptionalReturn,
  }) {
    throw UnsupportedError("NativeCallable cannot be constructed dynamically.");
  }
```

#### Core library API behavior 

All APIs that directly or indirectly depend on microtask queue and event loop
should throw easy to understand errors when invoked from `isolateGroupBound`
callable, e.g. an attempt to instantiate `Completer`, `Future`, `Stream`,
`Timer`, `Zone` should throw an appropriately worded exception that these
APIs can only be used when there is a current `Isolate`.

Conversely we expect most (if not all) synchronous APIs in `dart:*` libraries
to simply work when invoked from `isolateGroupBound`.

Specifically for core libraries:

* `dart:async` - does not work, constructors and static methods should throw
appropriate errors.
* `dart:core`, `dart:collection`, `dart:convert`, `dart:math`,
  `dart:typed_data`, `dart:ffi` - are expected to fully work
* `dart:io` - all synchronous APIs should work, all async APIs should throw.
* `dart:isolate` - synchronous APIs should work.
* `dart:mirrors` - is allowed to not work

**TODO**: do we need a blocking version of `ReceivePort` which could be used
from `isolateGroupBound` context?

### Additional Isolate APIs

We should facilitate synchronously entering `Isolate` when necessary. 

```dart
class Isolate {
  // Execute the given function in the context of the given isolate.
  // 
  // [f] must be trivially shareable. Result
  // returned by [f] must be trivially shareable.
  R runSync<R>(R Function() f);
}
```

Note that `runSync` can only enter an `Isolate` when it is not used by
another thread.

**TODO**: Furthermore we might want to facilitate integration with third-party
event-loops: e.g. allow to create isolate without scheduling its event loop on
our own thread pool and provide equivalents of `Dart_SetMessageNotifyCallback`
and `Dart_HandleMessage`. Though maybe we should not bundle this all together
into one update.

**TODO**: Should we facilitate execution of asynchronous code inside a target
isolate e.g. something like `T runAsync<T>(FutureOr<T> Function() f)`. When
you invoke this function `f` will be executed in the context of the given
isolate and then if it produced a `Future` we exit the isolate and block
the current thread, while allowing the event loop for that isolate to run
normally until returned future produces result.


### Scoped thread local values

```dart
@pragma('vm:deeply-immutable')
final class ScopedThreadLocal<T> {
  /// Creates scoped thread local value with the given [initializer] function.
  ///
  /// [initializer] must be trivially shareable.
  external factory ScopedThreadLocal([T Function()? initializer]);

  /// Execute [f] binding this [ScopedThreadLocal] to the given [value] for the duration of the execution.
  external R with<R>(T value, R Function(T) f);
  
  /// Execute [f] initializing this [ScopedThreadLocal] using default initializer if needed.
  /// Throws [NotBoundError] if this [ScopedThreadLocal] does not have an initializer.
  external void withInitialized<R>(R Function(T) f);

	/// Returns the value specified by the closest enclosing invocation of [with] or
	/// throws [NotBoundError] if this [ScopedThreadLocal] is not bound to a value. 
  external T get value;
  
  /// Returns `true` if this [ScopedThreadLocal] is bound to a value.
  external bool get isBound;
}
```

Having access to `ScopedThreadLocal` allows to rewrite code which uses global
variables to keep transient private state. Consider for example
`Iterable.toString` which avoids infinite recursion when visiting
self-referential iterables by tracking seen iterables:

```dart
/// A collection used to identify cyclic lists during `toString` calls.
final List<Object> toStringVisiting = [];

/// Check if we are currently visiting [object] in a `toString` call.
bool isToStringVisiting(Object object) {
  for (int i = 0; i < toStringVisiting.length; i++) {
    if (identical(object, toStringVisiting[i])) return true;
  }
  return false;
}

static String iterableToShortString(
  Iterable iterable, [
  String leftDelimiter = '(',
  String rightDelimiter = ')',
]) {
  if (isToStringVisiting(iterable)) {
    return "$leftDelimiter...$rightDelimiter";
  }
  toStringVisiting.add(iterable);
  try {
    // ... 
  } finally {
    toStringVisiting.removeLast();
  }
  // ...
}
```

This makes `Iterable.toString` unusable outside of an isolate (i.e. within
`isolateGroupBound` callables). However this code can be rewritten like so:

```dart
/// A collection used to identify cyclic lists during `toString` calls.
@pragma('vm:shared')
final ScopedThreadLocal<List<Object>> toStringVisiting = ScopedThreadLocal<List<Object>>(() => <List<Object>>[]);

/// Check if we are currently visiting [object] in a `toString` call.
bool isToStringVisiting(List<Object> toStringVisitingValue, Object object) {
  for (int i = 0; i < toStringVisitingValue.length; i++) {
    if (identical(object, toStringVisiting[i])) return true;
  }
  return false;
}

static String iterableToShortString(
  Iterable iterable, [
  String leftDelimiter = '(',
  String rightDelimiter = ')',
]) {
  return toStringVisiting.use((toStringVisitingValue) {
    if (isToStringVisiting(toStringVisitingValue, iterable)) {
      return "$leftDelimiter...$rightDelimiter";
    }
    toStringVisitingValue.add(iterable);
    try {
      // ... 
    } finally {
      toStringVisitingValue.removeLast();
    }
    // ...
  });
}
```

### Synchronization Primitives

At the bare minimum libraries should provide a non-reentrant `Lock` and a
`Condition`. However we might want to provide more complicated synchronization
primitives like re-entrant or reader-writer locks.

```dart
// dart:concurrent

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

> [!IMPORTANT]
>
> **TODO**: do we actually want to have asynchronous version of locking
> operations? This adds multiple points of complexity:
>
> - We need to reimplement locks using some low-level primitives because
> unlocking mutex on a different thread is often not supported by C level APIs.
>
> - It expands the duration of lock in a complicated unpredictable way
> (if we take lock before dispatching the future completion event). However
> using locks without asynchronous versions might be hard in a language like
> Dart - it would require completely blocking event loop to acquire the lock.

### Atomics

```dart
/// An `int` value which can be updated atomically.
///
/// Underlying storage might be either 32-bit or 64-bit.
abstract final class AtomicInt {
  external void store(int value);
  external int load();
  external (bool, int) compareAndSwap(int expected, int desired);

  external int fetchAdd(int v);
  external int fetchSub(int v);
  external int fetchAnd(int v);
  external int fetchOr(int v);
  external int fetchXor(int v);
}

extension AtomicElement32 on Int32List {
  external AtomicInt atomicAt(int index);
}

extension AtomicElement64 on Int64List {
  external AtomicInt atomicAt(int index);
}

extension AtomicFromPointer32 on Pointer<Int32> {
  external AtomicInt get atomic;
}

extension AtomicFromPointer64 on Pointer<Int64> {
  external AtomicInt get atomic;
}
```

Furthermore we will support the following for `dart:ffi` `Struct` and `Union` types:

```dart
final class Foo implements Struct {
   @Int32()
   external final AtomicInt foo;

   @Int64()
   external final AtomicInt bar;
}
```

> [!IMPORTANT] 
> 
> We expect compiler to optimize temporary intermediary `AtomicInt` objects away.

> [!IMPORTANT]
>
> **TODO**: should we split `AtomicInt` into `AtomicInt32` and `AtomicInt64`
> or not?
>
> **TODO**: should we provide `AtomicPointer` class?
> 
> **TODO**: should we support _futex_ like API (e.g. provide an operation to
> wait on an address and associated wake-up operation)? JavaScript chooses to
> provide `Atomics.wait` which is effectively futex-like instead of providing
> locks and conditions.

> [!CAUTION]
>
> Support for `AtomicInt` in FFI structs is meant to enable atomic access to
> fields without requiring developers to go through `Pointer` based atomic APIs.
> It is **not** meant as a way to interoperate with structs that contain
> `std::atomic<int32_t>` (C++) or `_Atomic int32_t` (C11) because these types
> don't have a defined ABI.

### Memory Model

Memory model describes the range of possible behaviors of multi-threaded
programs which read and write shared memory. Programmer looks at the memory
model to understand how their program will behave. Compiler writer looks at
the memory model to figure out which code transformations and optimization are
valid.

**TLDR** In the absence of data races with Dart programs are guaranteed to behave
in a sequentially consistent manner (aka _DRF-SC_): any posible execution can be
explained as an interleaving of operations from different isolates. A program
with data races does not necessarily exhibit sequential consistency but is
guaranteed to not crash the runtime or violate heap safety/soundness (i.e.
reads from typed locations will always produce values consistent with location's
type). Unlike C++ (and other programming languages directly inheriting its memory
model like Swift) Dart does not allow implementation to treat data race as a
source of undefined behavior.

> [!NOTE]
>
> For the sake of simplicity we assume that each invocation of `NativeCallable.isolateGroupBound`
> simply creates a fresh temporary isolate. This allows us to specify memory model uniformly in
> terms of isolates rather than talking about threads.

Formalization below is largely based on
[Repairing and Mechanising the JavaScript Relaxed Memory Model](https://www.cl.cam.ac.uk/~jp622/repairing_javascript.pdf),
though with a slightly different formal notation.
It is also worth reading [Go memory model](https://go.dev/ref/mem).

For the purposes of defining memory model we look at the execution of a Dart program as a set of
events $E$. These events can be memory read and/or writes or other important operations like
message sends/receives, mutex operations, etc.

Memory operations can be _atomic_,  _initializing_ or _unordered_ - predicates
$\mathtt{Atomic}(e)$  and $\mathtt{Init}(e)$ are defined to distinguish the first
two cases. Some memory operations are _tear free_ $\mathtt{TearFree}(e)$.

Each memory operation acts on a specific _address_ ($\texttt{Addr} \colon E \rightharpoonup \mathbb{N}$)
and reads and/or writes specific sequence of bytes
$\mathtt{Data_r}, \mathtt{Data_w} \colon E \rightharpoonup \\{0, \dots, 255\\}^\ast$. We also
define a few convenient functions and predicates:

$$
\begin{align*}
Loc_r(r) &\triangleq [\mathtt{Addr}(r), \mathtt{Addr}(r) + |\mathtt{Data_r}(r)|) \\
Loc_w(r) &\triangleq [\mathtt{Addr}(r), \mathtt{Addr}(r) + |\mathtt{Data_w}(r)|) \\
Loc(e) &\triangleq Loc_r(e) \cup Loc_w(e) \\
Overlap(a, b) &\triangleq Loc(a)\cap Loc(b) \neq \emptyset \\
SameLoc_{wr}(w, r) &\triangleq Loc_w(w) = Loc_r(r) \\
SameLoc_{ww}(w, w') &\triangleq Loc_w(w) = Loc_w(w') \\
Write(e) & \triangleq Loc_w(e) \neq \emptyset \\
Unordered(e) & \triangleq \neg(\mathtt{Atomic(e)} \vee \mathtt{Init}(e))
\end{align*}
$$

> [!NOTE]
>
> We are ignoring separation between Dart's object heap and native memory
> for the purposes of memory model. We can simply view GC managed memory
> as an infinite section of addresses above portion $2^{64}$ portion of
> $\mathbb{N}$. It is the responsibility of implementation to maintain
> the illusion of infinite memory while recycling finite native memory.

Program structure together with Dart semantics induce two partial orders on
events:

* _sequenced before_ ($\leq_\mathtt{sb}$) capturing restrictions imposed by Dart
  semantics on the order in which events can occur within each individual
  isolate;
* _additional synchronizes with_ relation ($\leq_{\mathtt{asw}}$) which captures
  cross-isolate ordering constraints induced by actions such as spawning
  isolates, sending and/or receiving messages, locking, etc.

Given the execution $\mathcal{E} = \langle E, \mathtt{Atomic}, \mathtt{Init}, \mathtt{TearFree}, \mathtt{Addr}, \mathtt{Data_r}, \mathtt{Data_w}, \leq_\mathtt{sb}, \leq_\mathtt{asw} \rangle$
we can attempt to construct an _explanation_ for it by providing two additional
relations on $E$:

* _strict total order_ ($\leq$) of all events in $E$ and

* _reads byte from_  $\leadsto_\circ : E \times \mathbb{N} \rightharpoonup E$
mapping explaining each byte read by connecting it to a corresponding write.
We write $w \leadsto_l r$ as a shortcut for $w = \leadsto_\circ(r, l)$ and we
write $w \leadsto r$ as a shortcut for $\exists l .  w \leadsto_l r$. Reads
byte from mapping must be well-formed with respect to concrete values being
read and written by events:

  * $\forall r \forall l \in Range_r(r) \exists ! w . w \leadsto_l r \wedge w \neq r \wedge \mathtt{Data_r}(r)\_{l - Loc(r)} = \mathtt{Data_w}(w)_{l - Loc(w)}$
    each byte read should be connected to precisely one write, that write can't
    be the same event as read and it writes the value which matches the one
    being read;

  * $\forall r \forall l \notin Range_r(r) \nexists w . w \leadsto_l r$ -
    locations not read are not connected to any write.

$\leadsto_\circ$ gives raise to two other derived relations.

We say that event $a$ _synchronizes with_ $b$ iff  $a \leq_\mathtt{asw} b$ or
if $a$ is an atomic write from which atomic read $b$ and they affect exactly the
same memory:

$$
a \leq_\mathtt{sw} b \iff (a \leadsto b \wedge SameLoc_{wr}(a, b) \wedge \texttt{Atomic}(a) \wedge \texttt{Atomic}(b)) \vee a \leq_\mathtt{asw} b
$$

We define _happens before_ relation ($\leq_\mathtt{hb}$) as a transitive closure of the union of _sequenced before_ and  _synchronizes with_ relations extended with additional edges from initializing writes to all overlapping operations.

$$
\leq_\texttt{hb} \triangleq (\leq_\mathtt{sb} \cup \leq_\mathtt{sw}  \cup \{ \langle w, e \rangle | \texttt{Init}(w) \wedge Overlap(w, e)  \})^+
$$

We say that the explanation for the execution
$\langle \mathcal{E}, \leadsto_\circ, \leq \rangle$ is valid under Dart's
memory model if and only if it satisfies the following requirements.

**[Happens-Before Consistency]** Total order must be a superset of
happens-before relation.

$$
\forall ab . a \leq_\texttt{hb} b \longrightarrow a \leq b
$$

If read observes a write then read cannot happen before observed write.

$$
\forall w r . w \leadsto r \longrightarrow \neg(r \leq_{\texttt{hb}}w)
$$

If read observes a write then there cannot be another interfering write which
updates the same memory ordered between write and read according to
happens-before. In other words: read cannot produce stale bytes from an older
write if there is an interfering newer write:

$$
\forall lwr . w \leadsto_l r \rightarrow \nexists w' . w \leq_{\text{hb}} w' \leq_{\texttt{hb}} r \wedge l \in Loc_w(w')
$$

**[Tear-free Reads]** A tear-free read will observe at most one tear-free write
to the same location. In other words: tear free read cannot produce a mixture
of bytes written by two (or more) tear-free writes.

$$
\forall r . \texttt{TearFree}(r) \longrightarrow \left|\left\\{ w \mid w \leadsto r \wedge \texttt{TearFree}(w) \wedge SameLoc_{wr}(w, r) \right\\}\right| \leq 1
$$

**[Sequentially Consistent Atomics]** Given a write and a read observing it,
with write happening before read according to $\leq_\mathtt{hb}$, there can be
no interfering atomic write sequenced between these in total order for which one
 of the following is true:

* Interfering write is writing to exactly the same location which is being read
  and the older write is synchronized with the read.
* Older write is atomic and interfering write is writing to exactly the same
  location, and interfering write happens-before read.
* Interfering write is writing to exactly the same location which is being read,
  it happens-after older write and the read is atomic.

$$
\forall w\,r . w \leadsto r \wedge w \leq_{\mathtt{hb}} r \longrightarrow \\
\nexists w' . \mathtt{Atomic}(w') \wedge w \leq w' \leq r \wedge \left(
\begin{align*}
&(SameLoc_{wr}(w', r) \wedge w \leq_\mathtt{sw} r) \\
\vee& (SameLoc_{ww}(w', w) \wedge \mathtt{Atomic}(w) \wedge w' \leq_{\mathtt{hb}} r) \\
\vee& (SameLoc_{wr}(w', r) \wedge w \leq_{\mathtt{hb}}w'\wedge \mathtt{Atomic}(r))
\end{align*}
\right)
$$

In other words read can't observe stale write if either read or write is atomic
and there is an interfering atomic write to exactly the same location which is
also ordered according to happens-before with that atomic operation.

Dart's memory model is thus formulated as follows: **any concrete execution of
Dart program must have _valid_ explanation.** That is given an execution it
should be possible to construct *total-order* and *reads-bytes-from* relations
on events of the execution which satisfy requirements outlined above
(**happens before consistency**, **tear-free reads** and
**sequentially consistent atomics**).

#### Data-Races

We say that a given explained execution $\langle \mathcal{E}, \leadsto_\circ, \leq \rangle$
of a Dart program contains a data-race if there exists a pair of events $a$ and
 $b$, at least one of which is a write (so it is either a pair of two writes or
 a write-read pair), such that:

* $a$ and $b$ overlap
* either $a$ or $b$ is unordered memory operation (i.e. neither
  $\mathtt{Atomic}$ nor $\mathtt{Init}$) or $a$ and $b$ don't operate on
  exactly the same location.
* $a$ and $b$ are not ordered according to happens-before.

$$
(Unordered(a) \vee Unordered(b) \vee Loc(a)\neq Loc(b)) \wedge \\ Overlap(a, b) \wedge (Write(a) \vee Write(b)) \wedge \neg (a\leq_\texttt{hb} b \vee b\leq_\texttt{hb} a)
$$

**Program is data-race free if all of its possible explained executions are data-race free**.

It can be proven that memory model requirements ensure that data-race free
programs behave in sequentially consistent way.

#### Language and Library Semantics

#### Object Construction

When object is constructed all field initializers (i.e. those provided in the
body of the class or in the initializer list) result in $\mathtt{Init}$
write events. The same applies to initialization of individual elements of
`TypedData` objects with `0`.

#### Isolates

Every `SendPort.send` generates a numbered event $\mathtt{Send}(p, i)$.

Receiving a message (e.g. invoking callback attached to  `ReceivePort`)
generates a corresponding $\mathtt{Recv}(p, i)$ event.

Sends are synchronized with receives:

$$
\forall p\,i . \mathtt{Send}(p, i) \leq_\mathtt{asw}\mathtt{Recv}(p, i)
$$

##### Locks

Every `Lock.acquireSync` and `Lock.releaseSync` call results in a numbered
acquire/release event $\mathtt{Acq}(l, 0), \mathtt{Rel}(l, 0), \mathtt{Acq}(l, 1), \mathtt{Rel}(l, 1), ...$

These events are explicitly ordered:

$$
\forall i\leq j . \mathtt{Rel}(l, i) \leq_\mathtt{asw} \mathtt{Acq}(l, j)
$$

##### Shared fields

There can only be a single initializing store for any shared field. All other
accesses are _not_ required to be atomic. However per definition of
$\leq_\mathtt{hb}$ relation all initializing stores happen-before other accesses
to the overlapping locations. This means that if one thread creates an object
and publishes it to another thread via a shared field - another thread can't
observe object in partially initialized state. Implementations can choose to
guarantee this property by inserting appropriate barriers when creating objects,
however that would be a waste for objects that are mostly used in an
isolate-local manner. Instead, given current restriction that only
trivially-shareable (deeply immutable objects) can be placed into shared-fields
implementations can instead choose to implement shared fields using
_store-release_ and _load-acquire_ atomic operations. This would guarantee
happens-before ordering for initializing stores. We however do not _require_
such implementation and consequently developers can't rely on this in their
programs.

##### Atomics

Atomic APIs defined in the corresponding [section](#atomics) should be
implemented in a way that guarantees sequential consistency.

#### Implementation Constraints

Compiler is not allowed to create data races which were not present in the
original program.

This for example means that compiler can't introduce writes into possibly
shared memory which were not present in the original program.

This also means that compiler can't move reads from possibly shared memory
location past operations that introduce happens-before edges (e.g. non-atomic
reads from shared locations can be hoisted past atomic reads from shared
locations).
