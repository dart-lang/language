# A Non-Covariant Type Variable in a Superinterface is an Error.

Author: eernst@google.com (@eernstg)

Version: 0.1.

## Motivation and Scope

The ability to use a type variable contravariantly in a superinterface of a
generic class creates an "anti-parallel" subtype relationship for a given
class and a direct superinterface thereof, and the same thing can happen
indirectly in many ways. This creates various complications for the static
analysis and the enforcement of the heap invariant (aka soundness), as
illustrated below. Similar complications arise in the invariant
case. Hence, this feature makes all non-covariant usages of a type variable
in a superinterface a compile-time error.

Here is an example:

```dart
class A<X> {
  X x;
  A(this.x);
}

class B<X> extends A<void Function(X)> {
  B(void Function(X) f): super(f);
}

main() {
  // Upcast: `B<int> <: B<num>` by class covariance.
  B<num> b = B<int>((int i) => print(i.runtimeType));
  // Upcast: `B<num> <: A<void Function(num)>` by `extends` clause.
  A<void Function(num)> a = b;
  // Upcast: `A<void Function(num)> <: A<void Function(double)>`
  // by class covariance, plus `double <: num` and `void <: void`.
  a.x(3.14);
}
```

Every assignment in `main` involves an upcast, so there are no downcasts at
all and the program should be safe. However, execution fails at `a.x(3.14)`
because we are passing an actual argument of type `double` to a function
whose corresponding parameter type is `int`.

Note that the heap invariant is violated during execution at the point
where `a` is initialized, even though the program has no error according
the the existing rules (before the inclusion of this feature).

The underlying issue is that the contravariant usage of a type variable in
a superinterface creates a twisted subtype lattice where `B` "goes in one
direction" (`B<int> <: B<num>`) and the superinterface `A` "goes in the
opposite direction" (`A<void Function(int)>` is a direct superinterface of
`B<int>` and `A<void Function(num)>` is a direct superinterface of
`B<num>`, but we have `A<void Function(num)> <: A<void Function(int)>`
rather than the opposite):

```dart
  A<void Function(int)> :>  A<void Function(num)>
     ^                         ^
     |                         |
     |                         |
  B<int>                <:  B<num>
```

We typically have a "parallel" subtype relationship:

```dart
  Iterable<int>  <:    Iterable<num>
     ^                    ^
     |                    |
     |                    |
  List<int>      <:    List<num>
```

But with the example above we have an "anti-parallel" relationship, and
that creates the opportunity to have a series of upcasts that takes us from
`int` to `double` in part of the type without ever seeing a discrepancy
(because we can just as well go up to `A<void Function(double)>` in the
last step rather than `A<void Function(int)>`).

With such scenarios in mind, this feature amounts to adding a new
compile-time error, as specified below.


## Static Analysis

Let `C` be a generic class that declares a formal type parameter `X`, and
assume that `T` is a direct superinterface of `C`. It is a compile-time
error if `X` occurs contravariantly or invariantly in `T`.


## Dynamic Semantics

There is no dynamic semantics associated with this feature.


## Revisions

*   Version 0.1, Nov 29 2018: Initial version.
