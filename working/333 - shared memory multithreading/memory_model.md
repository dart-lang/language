# Memory Model

> [!NOTE]
>
> We largely follow a mix of 
> [Repairing and Mechanising the JavaScript Relaxed Memory Model](https://www.cl.cam.ac.uk/~jp622/repairing_javascript.pdf) and [Go memory model](https://go.dev/ref/mem).

For the purposes of defining memory model we look at the execution of a Dart
program as a set of events. These events have the following attributes:

* its _kind_: read, write, read-write, message send/receive, lock
operations, isolate spawn.
* _location_ affected by the operation, if any
* _values_ read or written by the operation
* whether operation is _atomic_, _initializing_ and _tear-free_.

Operations which are neither atomic nor initializing are considered _unordered_.

Dart's memory model demands that **any concrete execution of
Dart program must have a valid explanation **:

* All events happen in some specific order.
* All read operations are connected to specific writes, which wrote the value the read is reading.
* The order of events and connections between reads and writes satisfy restrictions imposed by program structure as well as synchronizing and atomic operations (**happens before consistency**, **tear-free reads**, 
  **sequentially consistent atomics**).

Formally speaking the _explanation_ of an execution is a pair of relations on the set of events:

* _strict total order_ of all events
* _reads byte from_  mapping explaining each byte read by connecting it to a corresponding write. Reads byte from mapping must be well-formed with
  respect to concrete values being read and written by events:
  * each byte read should be connected to precisely one write, that write can't
    be the same event as read and it writes the value which matches the one
    being read;
  * locations not read are not connected to any write.

To determine whether explanation is _valid_ we need to examine whether it aligns with the semantics of Dart and the program being executed. We do that by defining a _happens-before_ partial order on events as a transitive closure of the following relations:

- **[program order]** If events **a** and **b** occur in the same isolate and **a** precedes **b** in _program order_ then **a** _happens-before_ **b**.  
- **[atomics]** If an atomic read **read** and atomic write **write**  act on _exactly_ the same location and **read** _reads-from_ **write** then **write** _happens-before_ **read**;
- **[message sends]** If **send** corresponds to `SendPort.send` invocation and  **receive**  corresponds to invocation of `ReceivePort` callback with that message - **send** _happens-before_  **receive**;
- **[spawns]** If **spawn** corresponds to spawning an isolate and **e** is an arbitrary event happening inside that isolate, then **spawn** _happens-before_ **e**;
- **[locks]** If **release** is an event corresponding to `Lock.release` and **acquire** is an event corresponding to subsequent `Lock.acquire` on the same lock then **release** _happens-before_ **acquire**.
- **[initialization]** If **init** is an initializing write to some location and **access** is a subsequent read or write to an overlapping location then **init** _happens-before_ **access**.

We say that the explanation for the execution is _valid_ if and only if it satisfies the following requirements:

- **[Happens-Before Consistency]**:
  
  - _Total order_ of events must be a superset of _happens-before_ relation.
  - If a **read** _reads-from_ a **write** then **read** cannot _happen-before_ **write**.
  - If a **read** _reads-from_ a **write** then there cannot be an **interfering write**
  which updates the same memory and _happens-between_  **write** and **read**. In other words: no read can produce stale bytes from an
  older write if there is an interfering newer write.
  
- **[Tear-free Reads]**: a _tear-free_ **read** will observe at most one _tear-free_ **write** to the same location. In other words: a tear free **read** cannot produce a mixture of bytes written by two (or more) tear-free **write**s.

- **[Sequentially Consistent Atomics]**: If a **read** _reads-from_ a **write**, and **write** _happens-before_ **read**, there can be no **interfering _atomic_ write** sequenced between these in _total order_ for which one of the following is true:

  * Both **read** and **write** are atomic, and all operations are accessing exactly the same location.
  * **write** is _atomic_, **interfering _atomic_ write** is writing to exactly the same
  location, and **interfering write** _happens-before_ **read**.
  * **read** is _atomic_, **interfering _atomic_ write** is writing to exactly the same location, and
  **interfering write** _happens-after_ **write**.
  
  In other words a **read** can't observe stale **write** if either **read** or **write** are
  _atomic_ and there is an **interfering _atomic_ write** to exactly the same location which is also ordered according to happens-before with that atomic operation.

**Any execution of a Dart program must have a _valid_ explanation.**

## Data-Races

We say that an explained execution of a Dart program contains a _data-race_
if there exists a pair of events **a** and **b** such that:

* Either **a** or **b** or both are a _write_ operation
* **a** and **b** act on overlapping locations
* Either **a** or **b** is _unordered_ memory operation (neither  _atomic_
  nor _initializing_) or **a** and **b** don't operate on exactly the
  same location.
* **a** and **b** are not ordered according to _happens-before_.

**Program is said to be data-race free iff all of its possible explained executions are data-race free**.

It can be proven that memory model requirements ensure that data-race free
programs behave in a sequentially consistent way.

## Tearing

In general, **all** reads and writes of fields inside Dart objects are _tear-free_ and thus subject to **Tear-free Reads** restriction given above:  each field
read can only observe a single field write.

There is exception from this requirement: on 32-bit systems (ARM32) _non-atomic_
reads and writes of `int` and `double` values are not guaranteed to be
tear-free. This means that reading an `int` or `double` value
_can_ produce an _out-of-thin-air_ value - a mixture of bytes from several writes. This exception is introduced to avoid performance penalty which would be incurred to ensure tear-free writes of unboxed `int` and `double` values. 

#### Object Construction

When instance of a class is constructed field initializers provided in the
body of the class and in the initializer list result in _initializing writes_.

Constructing a built-in `List` via any of its constructors or via a list
literal syntax results in _initializing writes_ for individual list elements.

The same applies to `TypeData` lists.

#### Implementation Constraints

Compiler is not allowed to create data races which were not present in the
original program.

This for example means that compiler can't introduce writes into possibly
shared memory which were not present in the original program.

This also means that compiler can't move reads from possibly shared memory
location past operations that introduce happens-before edges (e.g. non-atomic
reads from shared locations can be hoisted past atomic reads from shared
locations).

## Other languages

The table below provides an overview of memory models for some widely used
languages.

| Language | Memory Model |
| -------- | ------------ |
| C# | Language specification itself (ECMA-334) does not describe any memory mode. Instead the memory model is given in Common Language Infrastructure (ECMA-335, section _I.12.6 Memory model and optimizations_). ECMA-335 memory model is relatively weak and CLR provides stronger guarantees documented [here](https://github.com/dotnet/runtime/blob/main/docs/design/specs/Memory-model.md). See [dotnet/runtime#63474](https://github.com/dotnet/runtime/issues/63474) and [dotnet/runtime#75790](https://github.com/dotnet/runtime/pull/75790) for some additional context. |
| JavaScript | Memory model is documented in [ECMA-262 section 13.0 _Memory Model_](https://262.ecma-international.org/13.0/#sec-memory-model). This memory model is fairly straightforward: it guarantees sequential consistency for atomic operations, while leaving other operations unordered. |
| Java | Given in [Java Language Specification (JLS) section 17.4](https://docs.oracle.com/javase/specs/jls/se19/html/jls-17.html#jls-17.4) |
| Kotlin | Not documented. Kotlin/JVM effectively inherits Java's memory model. Kotlin/Native - does not have a specified memory model, but likely follows JVM's one as well. |
| C++ | Given in the section [Multi-threaded executions and data races](https://eel.is/c++draft/intro.multithread) of the standard (since C++11). Notably very fine grained |
| Rust | No official memory model according to [reference](https://doc.rust-lang.org/reference/memory-model.html), however it is documented to "[blatantly inherit C++20 memory model](https://doc.rust-lang.org/nomicon/atomics.html)" |
| Swift | Defined to be consistent with C/C++. See [SE-0282](https://github.com/apple/swift-evolution/blob/main/proposals/0282-atomics.md) |
| Go | Given [here](https://go.dev/ref/mem): race free programs have sequential consistency, programs with races still have some non-deterministic but well-defined behavior. |
