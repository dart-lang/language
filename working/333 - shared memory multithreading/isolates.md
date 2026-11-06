# Isolates

Dart specification says the following about its concurrency model:

> Dart code is always single threaded. There is no shared-state concurrency
> in Dart. Concurrency is supported via actor-like entities called isolates.
>
> An isolate is a unit of concurrency. It has its own memory and its own
> thread of control. Isolates communicate by message passing. No state
> is ever shared between isolates. Isolates are created by spawning.

Dart code always executes within some _isolate_, which is an entity comprised of:

- _program_ being executed by the isolate
- _static state_ of that program, that is value binding for all static and top-level variables in the program
- A garbage collector managed _heap_.
- An _message queue_ for receiving messages directed to `ReceivePort`s open
by this isolate.
- An _event loop_ which drains the message queue and dispatches messages to
handlers attached to corresponding `ReceivePort`s.

New isolates can be spawned from Dart using `Isolate.run`, `Isolate.spawn` and `Isolate.spawnUri` APIs or be created by the _embedder_ which is running Dart, e.g. a C++ program which embeds Dart VM.

The program below illustrates important properties of isolates:

```dart
import 'dart:isolate';
import 'dart:math';

final String topLevel = Random().nextInt(1000).toString();

void main(List<String> args) async {
  String local = args[0];
  await Isolate.run(() {
    print('child: $topLevel $local');
    local = '<?>';
  });
  print('main: $topLevel $local');
}
```

Executing `dart test.dart smth` will print

```
child: 786 smth
main: 313 smth
```

- _No shared mutable state._ Spawned isolate got a copy of the closure so assignment `localName = <?>` does not affect the main isolate.
- _Each isolate gets its own fresh static state_. That's why `topLevel` is different between two isolates.

To make isolates more effecient Dart VM introduced a concept of an _isolate group_. Isolate group owns the _GC heap_ and the _program_ and all isolates belonging to the same group share them, while maintaining independent _static state_, _message queue_ and _event loop_. This reduces time and space overhead of spawning a new isolate within a group by orders of magnitude and allows to optimize message transfer between isolates by avoiding copying of deeply immutable instances (e.g. compile time constants or objects like `String`). 

`Isolate.run` and `Isolate.spawn` create new isolates within the group of the spawning isolate. While `Isolate.spawnUri` creates an isolate in a new group.

Whether or not two isolates belong to the same group is mostly unobservable from Dart. The only API which is affected by this is `SendPort.send`. Only instances of certain built-in classes (`Null`, `int`, `double`, `String`, `List`, `Map`, `Set` and few others) can cross the boundary between groups. However within the same group isolates can exchange messages containing pretty much arbitrary objects with few restrictions. 

## Isolates and OS threads 

Dart being single-threaded means that at most one OS thread can be executing Dart code inside a specific isolate at the same time.

Event loops for isolates created from Dart using `dart:isolate` APIs execute in the thread pool provided by the VM. There is no 1-1 mapping between an isolate and a specific thread. Isolate's event loop stays on the same thread while it is draining the message queue. However if there is a large gap between messages the underlying thread could be reused by the VM for another task and the event loop might end up running on a different thread when it resumes.

Embedder's have control over event loops of isolates that they create and can decide to run these on a dedicated thread. For example, Flutter always runs the event loop for the main (UI) isolate on the OS-specific platform thread. Standalone[^1] Dart on the other hand runs the main isolate in the VM's thread pool.

An isolate being associated with a specific thread (like UI isolates in Flutter) is a convention - there is no Dart API to determine whether the current isolate is pinned to a specific OS thread or spawn an isolate in a way that pins it to a specific thread. It is only possible to achieve such pinning via Dart VM C API (aka embedding API) and that API is effectively only available if you are writing your own embedder[^2].

## Parallelizing work-loads using isolates

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

Another example is maintaining a persistent connection to some server and receiving data which should be inflated into mutable Dart-based data structures.  It is impossible to have a background isolate handle connection and parsing because it can't mutate data structures used by the main isolate.

[`Isolate.run`]: https://api.dart.dev/stable/3.2.6/dart-isolate/Isolate/run.html

## Isolates and Interoperability

_Dart-to-Native_ interoperability is largely a solved problem these days. However an inverse direction of _Native-calling-Dart_ still has some open questions created by the misalignment between thread based and isolate based concurrency models. 

The main challenge here is that Native code might decide to call Dart code from an arbitrary thread. Dart would need to have an isolate which is ready to accept such call e.g. a temporary isolate or an isolate created specifically to receive calls from arbitrary threads. That isolate then usually needs an efficient, possibly synchronous way to communicate with the main isolate - and without shared memory multithreading such way does not exist.

Consider the following C code using a miniaudio library:

```cpp
static void DataCallback(
   ma_device* device, void* out, const void* in, ma_uint32 frame_count) {
  // Synchronously produce up to |frame_count| frames into |out|.
}

ma_device_config config = ma_device_config_init(ma_device_type_playback);
// This function will be called when miniaudio needs more data.
// The call will happend on a backend specific thread dedicated to
// audio playback.
config.dataCallback      = &DataCallback;
// ...
```

Wrapping this API in pure Dart using `dart:ffi` is currently impossible. There is simply no [`NativeCallable`][] variant that would allow you to create a `DataCallback` which can be invoked on an arbitrary thread. Lets however imagine that there _were_ such an API, i.e. `NativeCallable.isolateLocal(..., acquire: true)` actually waited to acquire exclusive access to the target isolate and then executed a callback within that isolate.

When you look at an _isolate_ as _a bag of state guarded by a mutex_, you
eventually realize that this bag is simply way too big - it encompasses the
static state of the whole program - and this is what makes isolates unhandy to
use. The rule of thumb is that _coarse locks lead to scalability problems_. To avoid these problems we need to _spawn isolate which perform small specific task_.

For example, in `miniaudio` case we can structure the solution in the following way:

- One isolate (_consumer_) is spawned to do nothing but synchronously handle
  `DataCallback` calls, using an extension of `isolateLocal` which enters and
  leaves isolate is required.
- Another isolate (_producer_) is responsible for generating the data which is
  fed to the audio-library. The data is allocated in the native heap and
  directly _shared_ with _consumer_.

Note that this required us to share mutable data between two isolates. It is only possible to achieve in today's Dart because this data is effectively raw bytes representing audio streams. Which makes similar decomposition impossible if the data _producer_ and _consumer_ share is made of structured Dart objects. Which is a strong signal in favor of more shared
memory support in the language.

[^1]:  the `dart` CLI binary
[^2]: Flutter hides Dart VM C API from developers`

[`NativeCallable`]: https://api.dart.dev/dart-ffi/NativeCallable-class.html