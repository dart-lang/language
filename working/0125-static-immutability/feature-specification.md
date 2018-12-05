# Shared immutable objects

leafp@google.com

Status: Draft

This describes a possible solution for:
 - [Communication between isolates](https://github.com/dart-lang/language/issues/124)
 - [Building immutable collections](https://github.com/dart-lang/language/issues/117)
 - [Unwanted mutation of lists in Flutter](https://github.com/dart-lang/sdk/issues/27755)

## Summary

This describes a way to declare classes that produce deeply immutable object
graphs that are shared across isolates. 

## Syntax

We add a section to class headers for expressing class and generic constraints,
along with an "immutable" constraint.

```dart
class Value<T> extends Scalar<T> implements Constant is immutable
  where T is immutable {
}
```

Mixin declarations may also be marked `immutable`.

Generic method headers may also express generic constraints.

```
foo<S, T, where T is immutable>(Value<T> v) {

}
```

### Alternative syntax

Instead of adding constraints, a simpler approach is to add a marker interface
`Immutable`.  The property expressed by the constraint `T is immutable` then
becomes expressed by `implements Immutable` in the case of a class, or `T
extends Immutable` in the case of a type variable `T`.

## Static checking
A class marked with `immutable` is subject to the following additional static
checks.

- Every field in an immutable class (including any superclass fields) must be
  final.
- Every field in an immutable class (including any superclass fields) must have
  a static type which is immutable.
- Every other class which implements the interface of an immutable class
  (including via extension or mixing in) must also be immutable.

The types `int`, `double`, `bool`, `String`, `Type`, and `Symbol` are considered
immutable.

## Allocation of immutable objects

Immutable objects are allocated as usual in an isolate local
nursery. (Alternatively, it might be preferable to maintain a separate isolate
local shared object nursery for allocating only shared objects). However, when
they are tenured, they are tenured to a global heap which is shared by all
isolates in the process, and which is inhabited solely by immutable shared
objects.

The shared object heap cannot have pointers into the isolate local heaps, and so
garbage collection of an isolate local heap does not require coordination with
other isolates.

The isolate local heap can have pointers into the shared global heap, and so
either these must be tracked via write barriers and treated as roots when
collecting the shared global heap, or else collection of the shared global heap
might require cross-isolate coordination.

Tenuring objects into the shared global heap requires locking or pausing
isolates.  Bulk reservation of allocation regions could potentially be used to
mitigate this.

Issue: It is possible that a large object may need to be tenured before it has
been fully initialized.  This would allow writes into the shared heap.  This
should not be problematic semantically since the object cannot be visible in
other isolates prior to initialization, but it may complicate the GC model.
This does not seem deeply problematic - a number of solutions seem plausible.

## Sharing of immutable objects

The SendPort class is extended with a new method `void share<T, where T is
immutable>(T message)` which given a reference to an immutable object graph,
shares that reference with all receivers of the SentPort.  Note that the object
is not copied since it and all sub-components of it are in the shared heap.

An object which is shared before it has been tenured will likely need to be
tenured when it is shared.

It should be the case that every object is fully initialized before it can be
shared.  The intent of the static checks specified above are to guarantee this.

It should be the case that no object that has been shared can be mutated.  The
intent of the static checks specified above are to guarantee this.

## Immutable collections

The following additional immutable classes are added to the core libraries:
`ImmutableList` which implements `List`, `ImmutableMap` which implements `Map`,
and `ImmutableSet` which implements `Set`.

### Collection initialization
Instances of these collections may be allocated and assigned to local variables
in a modifiable state.  Mutation operations may be performed on such an instance
up until the first point at which the instance escapes (that is, is captured by
a closure, is assigned to another variable or setter, or is passed as a
parameter).  It is a static error if a mutation operation is performed on an
instance of one of these classes:
  - at any point not intra-procedurally dominated by the allocation point of the
    instance
  - at any point where the instance escapes along any path from the allocation
    point to the mutation operation.

Instances that are allocated to initialize fields or top level variables are
always initialized in an umodifiable state.

### Runtime immutability
As with the result of the current `List.unmodifiable` constructor, mutation
operations on an instance of an immutable collection shall throw (except in the
limited cases described in the initialization section above).  Note that the
static checks described above prevent mutation operations from being accessed on
an instance of immutable type.  However, the immutable collections implement
their mutable interfaces, and hence the mutation operations may be reached by
subsuming into the mutable type.

### Literals

A collection literal which appears in a context where the static type required
by the context is an immutable collection type shall be allocated as an
immutable collection.

```
ImmutableList<int> l = [ 3 ];
```
Question: Do we need additional syntax for the case where a static type context
is not required?

```
 var l = ^[3];
```

## Immutable functions

There is no way to describe the type of an immutable function.  If important, we
could add a type for immutable closures. A function is immutable if every free
variable of the function is immutable. 

## Immutable top type

There is no top type for immutable types.  It might be useful to have a type
`Immutable`, to express the type of fields of immutable objects which are
intended to hold instances of multiple types which do not otherwise share a
common super-interface.

## Javascript

Currently, isolates are not supported in Javascript.  If we revisit that, we are
unlikely to be able to support this in full on the web.  It is possible that we
may be able to define a subset of immutable objects which can be implemented as
a layer over shared typed data buffers.
