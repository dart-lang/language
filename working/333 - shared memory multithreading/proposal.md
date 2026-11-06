# Shared Memory Multithreading for Dart

Dart's concurrency model is based on _isolates_. Each isolate has its own memory and a thread of control. Isolates communicate via message passing and do not share any mutable state. See [Isolates](./isolates.md) for a high-level overview of the existing model, [Map of the Territory](./map_of_the_territory.md) gives an overview of concurrency models used by other popular programming languages.

We propose to allow sharing mutable Dart objects between isolates within isolate groups while keeping the rest of isolate model without changes: isolates will continue to have independent static state, message queue and event loops.

There is no accidental sharing in this proposal - a programmer makes a conscious decision to share a mutable object between isolates and as such programmer is responsible for the consequences of their actions. 

## Motivation

This proposal tries to address two long standing gaps which separate Dart from
other more low-level languages:

- Dart developers should be able to utilize multicore capabilities without
  hitting limitations of the isolate model. (See [Parallelizing work-loads using isolates](./isolates#parallelizing-work-loads-using-isolates))
- Interoperability between Dart and native platforms (C/C++, Objective-C/Swift,
  Java/Kotlin) requires aligning concurrency models between Dart world and
  native world. The misalignment is not an issue when invoking simple native
  synchronous APIs from Dart, but it becomes a complication when native code wants to call back into Dart on an arbitrary thread.

Preliminary experiments validate our assumptions by showing that it is possible to significantly improve performance of Dart's own tools like analyzer by allowing them to shard their work across multiple cores while keeping a single (mutable) copy of various data structures.  This sort of scaling is impossible to achieve otherwise.

This proposal does not directly address interoperability use case (see [Isolates and Interoperability](./isolates.md#isolates-and-interoperability) for additional details), but we believe it is an important first step towards simplifying our interoperability story as it enables direct, synchronous-if-needed, guaranteed zero-copy communication between concurrent isolates.

## Web compatibility

Dart currently does not support `dart:isolate` APIs on the Web neither when compiling to JavaScript nor when targeting Wasm and there are no active plans to support these APIs. Thus this proposal does not directly affect Dart-for-Web implementations in any way today. 

If Dart-for-Web were to support `dart:isolate` APIs we would not be able to support non-copying versions of message passing - beyond sharing `SharedArrayBuffer` backed typed lists.

Wasm GC has a [shared-everything-threads](https://github.com/WebAssembly/shared-everything-threads/pull/23)
proposal under design and prototype of it exists in V8. This extension is expressive enough to allow implementing everything described in our proposal - which means that Dart-to-Wasm compiler could target it.

Additionally there is a Stage 2 TC-39 proposal
[JavaScript Structs: Fixed Layout Objects and Some Synchronization Primitives](https://github.com/tc39/proposal-structs)
which introduces the concept of _struct_ - fixed shape mutable object which can
be shared between different workers. Unfortunately structs can't have any methods associated
with them, which makes structs unsuitable for representing arbitrary Dart
classes. This proposal seems to have stalled and seen no updates for 2 years.

## Safety Guarantees

Allowing developers to mutate Dart objects concurrently means allowing them to create _data-races_. Informally, speaking data-race is a situation when a write into some location executes concurrently with another access to the same location and there is no inherent ordering between these two operations created by synchronizing operations in the program.  

Dart will provide the following guarantees:

1. No pure Dart program (e.g. no `dart:ffi`) can violate heap soundness or crash runtime. Even in a program
   with data races reads from typed locations must always produce values
   consistent with location's static type.
   1. Isolates are not allowed to observe a partially constructed objects. If a freshly constructed object is accessed concurrently from another isolate then that isolate should at minimum observe result of all field initializers. 
2. Accessing Dart fields or list elements is _tear-free_ even in the presence of data-races - that is any read observes result of a single specific write -  with the following exception on 32-bit platforms[^32bit-tears]: on 32-bit platforms non-atomic operations with `int` and `double` values can tear under concurrency, and a read can return an _out-of-thin-air_ value produced by mixing bytes from different writes.
3. Any possible execution of a data-race free Dart program can be explained as an interleaving of operations from different isolates. In other words, data-race free Dart programs have sequentially consistent behavior.

See [memory model](./memory_model.md) for formal description of the memory model and guarantees.

[^32bit-tears]: Ensuring tear-free operations on all non-atomic 64-bit values on 32-bit platforms is prohibitively expensive.

## Core Libraries

Explicitly mutable core classes are not guaranteed to have a well-defined
behavior when used in program without explicit synchronization, unless otherwise
specified in their documentation. Concurrently mutating instances of these classes can leave them in a invalid state. Examples of such classes include
built-in collections like `Map` and `List` or helper classes like
`StringBuffer`. It is a programmer's error to share them between
isolates without proper synchronization. Note that even if a core class ends
up in an invalid state that state should not lead to violations of heap safety:
e.g. evaluating `List<E> l = ...; l[i]` should either produce an exception or
a value which is a subtype of `E` and was previously stored into `l`.

Core classes which look immutable to the developer, but contain mutable
state inside as an implementation detail will be updated to make it safe to
share them. An example of such class is a `Uri` which looks immutable to the
developer but contains a shared state inside.

The following libraries have no API changes: `dart:collection`, `dart:convert`,
`dart:developer`, `dart:math`.

### `dart:async`

Callbacks registered on `Future` or `Stream` will be called in the isolate
which registered them.

Built-in `Future` and `Completer` should be safe to use concurrently from
different isolates without additional locking.

The same does not apply to `Stream` and `StreamController`s because of their complexity.

### `dart:concurrent`

New library for synchronization primitives and atomics.

```dart
// dart:concurrent

/// Non-reentrant lock.
final class Lock {
  external void acquire();
  external bool tryAcquire({Duration? timeout});

  external void release();
}

final class Condition {
  external bool wait(Lock lock, {Duration? timeout});
  external void notify();
  external void notifyAll();
}

/// A reference to a value which can be accessed atomically.
///
/// Atomic operations can be used for low-level synchronization between
/// concurrently executing isolates as they form synchronization edges between
/// events occuring in the program.
///
/// `AtomicRef` can't be used with instances of [int], [double] or record values
/// because these do not have well-defined identity. Any attempts to pass
/// one of those to any `AtomicRef` methods will cause an [ArgumentError].
/// 
/// For [int] and [double] values use [AtomicInt64], [AtomicInt32] or [AtomicDouble]
/// instead.
final class AtomicRef<T> {
  external factory AtomicRef(T initialValue);

  /// Atomically updates the current value to `newValue`.
  external void store(T newValue);
  
  /// Atomically loads the current value.
  external T load();

  /// Atomically swaps the current value with `desired` if it is identical to `expected`.
  /// 
  /// Returns `(true, expected)` if the swap happened and `(false, currentValue)`
  /// otherwise.
  external (bool, T) compareAndSwap(T expected, T desired);
}

/// A 64-bit integer value which can be accessed atomically.
final class AtomicInt64 {
  external factory AtomicInt64([int initialValue = 0]);  
  
  /// Same as [Atomic.store]
  external void store(int newValue);

  /// Same as [Atomic.load]
  external T load();
  
  /// Same as [Atomic.compareAndSwap]
  external (bool, int) compareAndSwap(int expected, int desired);
  
  /// Performs an atomic addition.
  /// 
  /// Returns the value before modification.
  external int add(int v);

  /// Performs an atomic subtraction.
  /// 
  /// Returns the value before modification.
  external int sub(int v);
 
  /// Performs an atomic bitwise and.
  /// 
  /// Returns the value before modification.
  external int bitwiseAnd(int v);

  /// Performs an atomic bitwise or.
  /// 
  /// Returns the value before modification.
  external int bitwiseOr(int v);

  /// Performs an atomic bitwise xor.
  /// 
  /// Returns the value before modification.
  external int bitwiseXor(int v);
}

/// A 32-bit integer value which can be accessed atomically.
final class AtomicInt32 {
  external factory AtomicInt32([int initialValue = 0]);  

  /// Same as [Atomic.store]
  external void store(int newValue);

  /// Same as [Atomic.load]
  external T load();
  
  /// Same as [Atomic.compareAndSwap]
  external (bool, int) compareAndSwap(int expected, int desired);
  
  /// Performs an atomic addition.
  /// 
  /// Returns the value before modification.
  external int add(int v);

  /// Performs an atomic subtraction.
  /// 
  /// Returns the value before modification.
  external int sub(int v);
 
  /// Performs an atomic bitwise and.
  /// 
  /// Returns the value before modification.
  external int bitwiseAnd(int v);

  /// Performs an atomic bitwise or.
  /// 
  /// Returns the value before modification.
  external int bitwiseOr(int v);

  /// Performs an atomic bitwise xor.
  /// 
  /// Returns the value before modification.
  external int bitwiseXor(int v);
}

/// A [double] value which can be accessed atomically.
final class AtomicDouble {
  external factory AtomicDouble([double initialValue = 0.0]);  
  
  /// Same as [Atomic.store]
  external void store(double newValue);

  /// Same as [Atomic.store]
  external double load();
  
  /// Atomically swaps the current value with `desired` if it is bitwise identical to `expected`.
  /// 
  /// Returns `(true, expected)` if the swap happened and `(false, currentValue)`
  /// otherwise.
  external (bool, double) compareAndSwap(double expected, double desired); 
}

extension AtomicListElement<T> on List<T> {
  /// Obtain an atomic view of a specific element in a fixed-length [List].
  ///
  /// Throws [ArgumentError] if `this` not a fixed-length built-in [List] instance.
  Atomic<T> atomicAt(int index);
}
```

> [!IMPORTANT]
>
> If a final `Atomic<T>` field never leaks its identity (e.g. it is initialized
> to a fresh instance of `Atomic` in constructor all accesses to the field
> are in the form of `a.atomicField.atomicMethod(...)`) then it is
> reasonable to expect that `atomicField` will be unboxed in the object.
> Unfortunately the language does not currently provide us with tools to
> express this sort of a guarantee.

### `dart:core`

Default implementation of `List`, `Map`, `Set`, `Finalizer` and `Expando`
are updated to remove any optimizations which are unsafe in a racy program
and can lead to a violation of heap safety.

`RegExp`, `Uri` and `DateTime` are made safe to share between isolates.

`Finalizer` class will be updated to execute `callback` in the isolate which
attached finalizer to the object.

### `dart:ffi`

API surface should be expanded to expose atomics read and writes via pointers
and fields of structs.

```dart
// Added to dart:ffi
extension AtomicFromPointer32 on Pointer<Int32> {
  /// Obtain an atomic view of the value.
  external AtomicInt32 get atomic;
}

extension AtomicFromPointer64 on Pointer<Int64> {
  /// Obtain an atomic view of the value.
  external AtomicInt64 get atomic;
}

extension AtomicFromPointerPointer<T> on Pointer<Pointer<T>> {
  /// Obtain an atomic view of the value.
  ///
  /// Returned [Atomic] does not preserve identity of the `Pointer` objects
  /// and looks at their addresses instead.
  external Atomic<Pointer<T>> get atomic;
}

// The following becomes valid.
final class Foo implements Struct {
   @Int32()
   external final AtomicInt32 foo;

   @Int64()
   external final AtomicInt64 bar;

   external final Atomic<Pointer<X>> baz;
}
```

### `dart:io`

It should be safe to pass any `dart:io` objects between isolates (e.g. allocate
socket in one isolate and give it to another isolate). This means native
objects do not get disposed automatically when isolate that created them
shuts down.

### `dart:isolate`

We will update `dart:isolate` documentation to introduce the concept of an
_isolate group_ and make it clear when isolates belong to the same group
and when they do not.

`SendPort` API will be updated to allow sending an object without copying it:

```dart
class SendPort {
  /// ...
  /// If `copy` is `false` and the sender and the receiver isolates belong to the
  /// same group then `message` is sent to the receiver as a reference without
  /// copying.
  ///
  /// If `copy` is `false` and the sender and the receiver isolates belong to
  /// different groups then an [ArgumentError] exception is thrown.
  /// ...
  void send(Object? message, {bool copy = true});
}
```

Similar update will be done for `Isolate.spawn` and `Isolate.run` APIs:

```dart
class Isolate {
  /// ...
  /// If `copy` is `false` then `entryPoint` and `message` are shared with the
  /// spawned isolate without copying.
  /// ...
  static Future<Isolate> void spawn<T>(
    void entryPoint( T message ),
    T message, {
    // ...
    @Since.new("...") bool copy = true,
    // ...
  });

  /// ...
  /// If `copy` is `false` then `computation` is shared with the spawned
  /// spawned isolate without copying and its result is passed back to
  /// the current isolate without copying.
  /// ...
  static Future<R> run<R>(
    FutureOr<R> computation(), {
    String? debugName,
    @Since.new("...") bool copy = true,
  });
}
```

### `dart:typed_data`

API surface is expanded to support atomic operations on elements of type data.

```dart
// Added to dart:typed_data or dart:concurrent

extension AtomicElement32 on Int32List {
  /// Obtain an atomic view of a specific element in [Int32List].
  external AtomicInt32 atomicAt(int index);
}

extension AtomicElement64 on Int64List {
  /// Obtain an atomic view of a specific element in [Int32List].
  external AtomicInt64 atomicAt(int index);
}
```
