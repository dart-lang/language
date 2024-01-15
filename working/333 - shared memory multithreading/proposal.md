# Shared Memory Multithreading for Dart

This proposal tries to address two long standing gaps which separate Dart from other more low-level languages:

* Dart developers should be able to utilize multicore capabilities without hitting limitations of the isolate model.

* Interoperability between Dart and native platforms (C/C++, Objective-C/Swift, Java/Kotlin) requires aligning concurrency models between Dart world and native world. The misalignment is not an issue when invoking simple native synchronous APIs from Dart, but it becomes a blocker when:

  * working with APIs pinned to a specific thread (e.g. `@MainActor` APIs in Swift or UI thread APIs on Android)

  * dealing with APIs which want to call _back_ from native into Dart on an arbitrary thread.

  * using Dart as a container for shared business logic - which can be invoked on an arbitrary thread by surrounding native application.

  Native code does not _understand_ the concept of isolates.

The biggest challenge with introducing shared memory multithreading into Dart is avoiding breaking existing code, which is written under the assumption of single-threaded access. We would like to avoid just outright breaking existing code in subtle ways. Consider for a moment a library which is maintains a global cache internally:

```dart
class C {
  final id;
  C(this.id);
}

int _nextId = 0;
final _cache = <int, C>{};

C makeObject() {
  _cache[nextId] = C(nextId);
  nextId++;
  return _cache[nextId - 1];
}
```

This was a valid way to structure this code in single-threaded Dart, but the same code becomes thread _unsafe_ in the presence of shared memory multithreading.

## Shareable Data

We propose to extend Dart with a shared memory multithreading but provide a clear type-based delineation between two concurrency worlds. **Only instances of classes implementing `Shareable` interface can be concurrently mutated by another thread.** There is no requirement of transitive immutability imposed on shareable classes. However we restrict the kind of data that a shareable class can contain: **fields of sharable classes can only contain references to instances of sharable classes.** This requirement is enforced at compile time by requiring that static types of all fields are shareable.

```dart
// dart:core

/// [Shareable] instances can be shared between isolates and mutated concurrently.
///
/// A class implementing [Shareable] can only declare fields
/// which have a static type that is a subtype of [Shareable].
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
> I choose marker interface rather than dedicated syntax (e.g. `shareable class`) because marker interface comes handy when declaring type bounds for generics and allows to perform runtime checking if needed.

References to shareable instances can be passed between isolates within an isolate group directly: for example sending a shareable instance through `SendPort` will not copy it.

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

To make state sharing between isolates simpler we also allow to declare static fields which are shared between all isolates in the isolate group. `shared` global fields are required to have shareable static type.

```dart
// All isolates within an isolate group share this variable.
shared int v = 0;
```

### Shareable Types

> Type is _shareable_ if and only if one of the following applies:
>
> * It is `Null` or `Never`.
> * It is an interface type which is subtype of `Shareable`.
> * It is a record type where all field types are shareable.
> * It is a nullable type `T?` where `T` is shareable type.

### Generics

When declaring a generic type the developer will have to use type parameter bounds to ensure that resulting class conforms to restrictions imposed by `Shareable`:

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
> We could really benefit from the ability to use intersection types here, which would allow to specify complicated bounds like `T extends Shareable & I`. In the absence of intersections types developers would be forced to declare intermediate interfaces which implement all required interfaces (e.g. `abstract interface ShareableI implements Shareable, I {}`) and require users to implement those by specifying `T extends ShareableI`.

### Functions

Shareability of a function depends on the values that it captures. We could define that any **function is shareable iff it captures only variables of shareable type**. Incorporating this property into the type system naturally leads to the desire to use _intersection types_ to express the property that some value is both a function of a specific type _and_ shareable:

```  dart
class A implements Shareable {
  void Function() f;  // compile time error
  void Function() & Shareable f;  // ok
}
```

Introducing intersection types into type system might be a huge undertaking. For the purposes of developing an MVP we can choose one of the two approaches:

* Ignore functions entirely: consider functions un-shareable. It becomes a compile time error to have a function type field inside a shareable class. 
* Allow function type fields inside a shareable class, but enforce shareability in runtime on assignment to the field.   

### Collections (`Iterable`, `List`, `Set`, `Map`)

If `S` shareable then `Iterable<S>`, `List<S>` and `Set<S>` are shareable. If `SK` and `SV` are sharable then `Map<SK, SV>` is shareable. This imposes additional requirements on classes implementing these interfaces: whether some container is shareable depends on concrete type parameters of an instance. If class `C<T1, ..., Tn>` implements `List<F(T1, ..., Tn)>` then constructing an instance of `C<X1, ..., Xn>` , such that `F(X1, ..., Xn)` is shareable, should only be possible if `C<X1, ..., Xn>` satisfies restrictions imposed on shareable classes i.e. static type of each of its fields should be a subtype of `Shareable`.

```dart
class C1<T> implements List<T> {
  final List<T> v;
}

class C2<T> implements List<T> {
  final List<Object> v;
}

C1<Shareable>(); // ok
C2<Shareable>(); // runtime error: static type of C2.v is not shareable
```

A simpler alternative would be to introduce a set of shareable collection types: `ShareableList<T>`, `ShareableSet<T>`,  `ShareableMap<K, V>`, all with appropriate type parameter bounds restricting elements to subtypes of `Shareable?`. Builtin implementation of `List<T>` will also implement `ShareableList<T>` when `T` is shareable, but there would be no implicit expectation of shareability built into `List<T>` itself.

### Shareable core types

The following types will become shareable:

* `num` (`int` and `double`), `String`, `bool`, `Null`
* `Enum` - meaning that all enums will be shareable, this is fine because enums are deeply immutable.
* `RegExp`, `DateTime`, `Uri` - these might require work to be shareable, but it makes sense to allow sharing them.
* `TypedData` - which makes all typed data types shareable.
  * **BREAKING CHANGE**: making `TypedData` shareable changes the behaviour of `SendPort` which will stop copying it. It's unclear if we want to maintain old behaviour for compatibility reasons. One option here is to say that `TypedData` is only shared when sending through `SendPort` iff it is a member of another explicitly `Shareable` type.
* `Pointer`

#### Collections

Core collection interfaces (`Iterable<E>`, `List<E>`, `Map<K, V>` and `Set<E>`) and their default implementations are not going to be shareable. Instead we will provide `ShareableList`, `ShareableMap` and `ShareableSet` variants. 

### Controlling `SendPort` behavior

**TODO**: Allow overriding copying / direct passing behavior 

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

Stripped to the bare minimum the example does not seem to behave in a confusing way: it seems obvious that each isolate has its own version of `global` variable and mutations of `global` are not visible across isolates. However, in the real world code such behavior might be hidden deep inside a third party dependency and thus much harder to detect and understand. This behavior also makes interoperability with native code more awkward than it ought to be: calling Dart requires an isolate, something that native code does not really know or care about.

```dart
int global;

@pragma('vm:entry-point')
void foo() => global++;
```

`shared` global variables allow developers to tackle this problem - but hidden dependency on global state might introduce hard to diagnose and debug bugs.

We propose to tackle this problem by introducing the concept of _shared isolate_: **code running in a _shared isolate_ can only access `shared` state and not any of isolated state, an attempt to access isolated state results in a dynamic `IsolationError`**.

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

It is tempting to try introducing a compile time separation between functions which only access `shared` state and functions which can access isolated state.

One obvious approach is to introduce a modifier (e.g. `shared`) which can be applied to function declarations and impose a number of restrictions that `shared` functions have to satisfy. These restrictions should guarantee that `shared` functions can only access `shared` state.

```dart
shared void foo() {
  // ...
}
```

* You can only pass subtypes of `Shareable` to `shared` methods and you can only get a `Shareable` result back.

  * Consequently an instance method can only be marked  `shared` if it is declared in a `Shareable` class.

* You can't override non-`shared` method with `shared` method.
* Within a `shared` function
  * If `f(...)` is a static function invocation then `f` must be a `shared` function.
  * If `o.m(...)` is an instance method invocation, then  `o` must be a subtype of `Shareable` and `m` must be `shared` method.
  * If `C(...)` is a constructor invocation then `C` must be a sharable class.
  * If `g` is a reference to a global variable then `g` must be `shared`.

This approach seems promising on the surface, but we quickly hit issues:

* It's unclear how to treat `Object` members like `toString`, `operator ==` and `get hashCode`. These can't be marked as `shared` but should be accessible to both `shared` and non-`shared` code.
* It's unclear how to treat function expression invocations:
  * Function types don't encode necessary separation between `shared` and non-`shared` functions.
  * Methods like `List<T>.forEach` pose challenge because they should be usable in both `shared` and non-`shared` contexts.

This makes us think that language changes required to achieve sound compile time delineation between `shared` and isolate worlds are too complicated to be worth it.

###  Upgrading `dart:ffi`

Introduction of _shared isolate_ allows to finally address the problem of native code invoking Dart callbacks from arbitrary threads. [`NativeCallable`](https://api.dart.dev/dev/3.3.0-246.0.dev/dart-ffi/NativeCallable-class.html) can be extended with the corresponding constructor:

```dart
class NativeCallable<T extends Function> {
  /// Constructs a [NativeCallable] that can be invoked from any thread.
  ///
  /// When the native code invokes the function [nativeFunction], the corresponding
  /// [callback] will be synchronously executed on the same thread within a
  /// shared isolate corresponding to the current isolate group.
  external factory NativeCallable.shared(
    @DartRepresentationOf("T") Function callback,
    {Object? exceptionalReturn});
}
```

Invoking `NativeCallable.shared(...).nativeFunction` does not require exclusive access to a specific isolate - so it will not introduce any busy waiting. It also has a clear semantics with respect to global state: `shared` global state is accessible and independent from the current thread and non-`shared` state will throw an error when accessed.

## Core Library Changes

### Upgrading `dart:async` capabilities

#### `Zone` as the executor

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

What happens when `Future` completes in a shared isolate? Who drives event loop of that isolate? Which thread will callbacks run on?

We propose to tie answers to these questions to the existing concept: `Zone`. Root `Zone` of each isolate will responsible for managing event loop of that isolate. A `Zone` might have a thread pool associated with it or it might be driven externally by the embedder.

Consider for example the code like `fut.then((v) { /* ... */ })`. When `Future` `fut` completes the invocation of the callback is going to be managed by the `Zone` to which it is bound: if `Zone` has thread pool associated with it and we are not on one of the threads associated with that pool then a task will be posted to the pool instead of executing callback on the current thread. This makes it easy to understand and control how asynchronous execution moves between threads.

If you get a hold of `Zone` from another isolate (`Zone` should probably be `Shareable`) then you should be able to inject a callback into the event loop owned by that `Zone`.

#### Shareable `Future` and `Stream` instances

`Future<Shareable>` and `Stream<Shareable>` should be shareable between isolates within the isolate group.

#### Structured Concurrency

_Structured concurrency_ is a way of structuring concurrent code where lifecycle of concurrent tasks has clear relationship to the control-flow structure of the code which spawned those tasks. One of the most important properties of structured concurrency is an ability to cancel pending subtasks and propagate the cancellation recursively.

Consider for example the following code:

```dart
Future<Result> doSomething() async {
    final (a, b) = await (requestA(), computeB()).wait;
    return combineIntoResult(a, b);
}
```

If Dart supported _structured concurrency_, then the following would be guaranteed:

* If either  `requestA`  or `computeB` fails, then the other is _canceled_.
* `doSomething` computation can be _canceled_ by the holder of the `Future<Result>` and this cancellation will be propagated into `requestA` and `computeB`.
* If  `computeB` throws an error before `requestA` is awaited then `requestA` still gets properly canceled.

Upgrading `dart:async` capabilities in the wake of shared-memory multithreading is also a good time to introduce some of the structured concurrency concepts into the language. See [Cancellable Future](https://gist.github.com/mraleph/6daf658c95be249c2f3cbf186a4205b9) proposal for the details of how this could work in Dart.

See also:

* [JEP 453 - Structured Concurrency](https://openjdk.org/jeps/453)
* [Wikipedia - Structured Concurrency](https://en.wikipedia.org/wiki/Structured_concurrency)



### `dart:concurrent`

`dart:concurrent` will serve as a library hosting low-level concurrency primitives.

#### `Thread` and `ThreadPool`

Isolates are *not* threads even though they are often confused with ones. A code running within an isolate might be executing on a dedicated OS thread or it might running on a dedicated pool of threads. When expanding Dart's multithreading capabilities it seems reasonable to introduce more explicit ways to control threads.

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

  external Thread get current;

  Future<void> join();

  void interrupt();

  external set priority(ThreadPriority value);
  ThreadPriority get priority;
}

abstract class ThreadPool implements Shareable {
  external factory ThreadPool({required int concurrency});

  /// Run the given function on this thread pool.
  ///
  /// The [task] is executed in a shared isolate of the current
  /// isolate group.
  ///
  /// The function will be run in a `Zone` which uses this
  /// pool as an executor for all callbacks: this
  /// means the pool will remain alive as long as there is
  /// a callback referencing it.
  void postTask(void Function() task);
}
```

We might also want to provide a way to synchronously execute code in a specific isolate on the _current_ thread:

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

Connecting execution / scheduling behavior to `Zone` allows us to give a clear semantics to this code: this code will run on a specific (newly spawned) thread and will not change threads between suspending and resumptions.

#### Atomic operations

`Atomic<T>` is a wrapper around a value of type `T` which can be updated atomically. It can only be used with true reference types - an attempt to create an `AtomicRef<int>`, `AtomicRef<double>` , `AtomicRef<(T1, ..., Tn)>` will throw.

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

class AtomicInt32 {
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

```dart
// dart:concurrent

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

For convenience reasons we might also consider making the following
work:

```dart
final class MyStruct extends Struct {
  @Int32()
  external final AtomicInt value;
}
```

The user is expected to use `a.value.store(...)` and `a.value.load(...` to access the value.

# Appendix

## Memory Models

Memory model describes the range of possible behaviors of multi-threaded programs which read and write shared memory. Programmer looks at the memory model to understand how their program will behave. Compiler engineer looks at the memory model to figure out which code transformations and optimization are valid. The table below provides an overview of memory models for some widely used languages.

It is too early in the design process to propose a concrete memory model - but I am inclined towards following JavaScript steps here, because Web is one of our targets.

| Language   | Memory Model                                                 |
| ---------- | ------------------------------------------------------------ |
| C#         | Language specification itself (ECMA-334) does not describe any memory mode. Instead the memory model is given in Common Language Infrastructure (ECMA-335, section *I.12.6 Memory model and optimizations*). ECMA-335 memory model is relatively weak and CLR provides stronger guarantees documented [here](https://github.com/dotnet/runtime/blob/main/docs/design/specs/Memory-model.md). See [dotnet/runtime#63474](https://github.com/dotnet/runtime/issues/63474) and [dotnet/runtime#75790](https://github.com/dotnet/runtime/pull/75790) for some additional context. |
| JavaScript | Memory model is documented in [ECMA-262 section 13.0 *Memory Model*](https://262.ecma-international.org/13.0/#sec-memory-model)*.* This memory model is fairly straightforward: it guarantees sequential consistency for atomic operations, while leaving other operations unordered. |
| Java       | Given in [Java Language Specification (JLS) section 17.4](https://docs.oracle.com/javase/specs/jls/se19/html/jls-17.html#jls-17.4) |
| Kotlin     | Not documented. Kotlin/JVM effectively inherits Java's memory model. Kotlin/Native - does not have a specified memory model, but likely follows JVM's one as well. |
| C++        | Given in the section [Multi-threaded executions and data races](https://eel.is/c++draft/intro.multithread) of the standard (since C++11). Notably very fine grained |
| Rust       | No official memory model according to [reference](https://doc.rust-lang.org/reference/memory-model.html), however it is documented to "[blatantly inherit C++20 memory model](https://doc.rust-lang.org/nomicon/atomics.html)" |
| Swift      | Defined to be consistent with C/C++. See [SE-0282](https://github.com/apple/swift-evolution/blob/main/proposals/0282-atomics.md) |
| Go         | Given [here](https://go.dev/ref/mem): race free programs have sequential consistency, programs with races still have some non-deterministic but well-defined behavior. |

## Platform capabilities

When expanding Dart's capabilities we need to consider if this semantic can be implemented across the platforms that Dart runs on.

### Native

No blockers to implement any multithreading behavior. VM already has a concept of _isolate groups_: multiple isolates concurrently sharing the same heap and runtime infrastructure (GC, program structure, debugger, etc).

### Web (JS and Wasm)

No shared memory multithreading currently (beyond unstructured binary data shared via `SharedArrayBuffer`). However there is a Strage 1 TC-39 proposal [JavaScript Structs: Fixed Layout Objects and Some Synchronization Primitives](https://github.com/tc39/proposal-structs) which introduces the concept of _struct_ - fixed shape mutable object which can be shared between different workers. Structs are very similar to `Shareable` objects we propose, however they can't have any methods associated with them. This makes structs unsuitable for representing arbitrary Dart classes - which usually have methods associated with them.

Wasm GC does not have a well defined concurrency story, but a [shared-everything-threads](https://github.com/WebAssembly/shared-everything-threads/pull/23) proposal is under design. This proposal seems expressive enough for us to be able to implement proposed semantics on top of it.

## `dart:*` race safety

When implementing `dart:*` libraries we should keep racy access in mind. Consider for example the following code:

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

This code is absolutely correct in single-threaded environment, but can cause heap-safety violation in  a racy program: if `operator[]` races with `removeLast` then `storage[index]` might return `null` even though `checkValidIndex` succeeded.
