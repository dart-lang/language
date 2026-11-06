# Map of the Territory

This document gives an overview of concurrency models in other popular
and niche languages.

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