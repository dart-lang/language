# Enhanced Constructors Feature Specification

Author: Paul Berry

Status: Under review

## Summary

This proposal extends the set of actions that can be performed in the body of a
non-redirecting generative constructor to include writing to non-late final
fields and explicitly invoking super constructors.

This makes constructors more flexible, avoids the need for constructor
initializer lists, and allows constructor augmentations to behave more
consistently with function augmentations.

To preserve soundness, flow analysis is enhanced to ensure that a reference to
`this` cannot escape from a constructor body before the object has been
completely constructed.

## Background

Dart follows the tradition of C++ and similar languages in requiring super
constructor invocations and final field assignments to occur prior to the
constructor body, in a so-called "initializer list". For example, in the code
below, the constructor for class `C` performs three actions: the assignment `j =
x + 1`, the super constructor invocation `super(x * 2)`, and the ordinary method
invocation `m()`. The first two of those actions are done using initializer list
syntax, prior to the `{` that begins the constructor body, and the third action
is an ordinary statement, inside the constructor body.

```dart
class B {
  final int i;
  B(this.i);
  void m() { ... }
}

class C extends B {
  final int j;
  C(int x)
      : j = x + 1,
        super(x * 2) {
    m();
  }
}
```

Programmers unfamiliar with initializer lists might wonder why it's not possible
to write `j = x + 1` and `super(x * 2)` as ordinary statements, like this:

```dart
class C extends B {
  final int j;
  C(int x) {
    j = x + 1;
    super(x * 2);
    m();
  }
}
```

In addition to making the language more approachable for programmers unfamiliar
with initializer lists, allowing field initialization and super constructor
invocation to be ordinary statements would make constructors a lot more
flexible, allowing the user to perform arbitrary manipulation of the constructor
arguments prior to initializing fields and calling the super-constructor.

However, with this extra flexibility comes the need to preserve soundness. In
particular, we must statically ensure that the user cannot:

- Read from a field before its initial value has been written.

- Call a superclass method, getter, or setter before calling a super constructor
  (this could break soundness by causing the superclass to read from a field
  before its initial value has been written).

- Write to a non-late final field more than once.

- Call a super constructor more than once on the same object (this could break
  soundness by causing the base class to write to a non-late final field more
  than once).

In today's Dart, these soundness requirements are met automatically by virtue of
the rigid structure and limited capabilities of initializer lists. In this
proposal, they are met using flow analysis.

## Proposal

The following kinds of expressions will become legal within the body of a
non-redirecting generative constructor:

- A write to a non-late final field, either via an explicit `this` reference
  (`this.FIELDNAME = VALUE`) or an implicit `this` reference (`FIELDNAME =
  VALUE`). _Note that in this document, all-caps names are metasyntactic
  variables._

  - These are the only two syntaxes for writing to a field that are given
    special treatment by this proposal. _For example, `(this).FIELDNAME = VALUE`
    cannot be used to initialize a final field; it would be treated as a setter
    invocation applied to an ordinary `this` expression, and the ordinary `this`
    expression would be forbidden by flow analysis if the field has not yet been
    initialized._

- A call to a super constructor, using the syntax `super(ARGUMENTS)` (for an
  unnamed constructor) or `super.NAME(ARGUMENTS)` (for a named constructor). For
  the rest of this document, such an expression is called a "`super` constructor
  invocation expression".

With the restriction that `super` constructor invocation expressions may only
appear as the top level expression within an expression statement. _Rationale:
this simplifies [ambiguity
resolution](#disambiguation-of-super-constructor-invocations-from-super-method-invocations),
and doesn't significantly reduce expressive power. It may also simplify the
implementation._

To ensure soundness, flow analysis will be modified to ensure, at compile time,
that all reachable control flow paths through a non-redirecting generative
constructor:

- Contain exactly one invocation of a super constructor.

- Write to every non-late final field exactly once prior to invoking a super
  constructor.

- Do not write to any non-late final field after invoking a super constructor.

- Do not explicitly or implicitly access `this` in any way prior to invoking a
  super constructor, except:

  - To perform the required writes to non-late final fields prior to invoking a
    super constructor.

  - To read from fields that have already been written to.

_The current Dart spec contains several exceptions for the built-in class
`Object`, which doesn't have a supertype, and therefore can't have a super
constructor. Keeping track of these exceptions is cumbersome, so for
simplicitly, in this proposal, we simply consider the invocation of a super
constructor from the constructor of `Object` to be a no-op; this way we can
treat the built-in class `Object` as non-exceptional._

This allows the vast majority of constructor initializer lists to be rewritten
as ordinary statements in the constructor body. For example, this constructor
from the analyzer's `VariableDeclarationImpl` class:

```dart
  VariableDeclarationImpl({
    required this.name,
    required this.equals,
    required ExpressionImpl? initializer,
  })  : _initializer = initializer,
        super(comment: null, metadata: null) {
    _becomeParentOf(_initializer);
  }
```

can now be rewritten to:

```dart
  VariableDeclarationImpl({
    required this.name,
    required this.equals,
    required ExpressionImpl? initializer,
  }) {
    _initializer = initializer;
    super(comment: null, metadata: null);
    _becomeParentOf(_initializer);
  }
```

### Mixed style

To avoid a "syntactic cliff" between the old and new styles of coding
non-redirecting generative constructors, it is allowed to mix the two
styles. That is, even in a non-redirecting generative constructor that has an
initializer list, the body is allowed to contain writes to non-late final
fields, or `super` constructor invocation expressions.

For example, here is the same `VariableDeclarationImpl` constructor again,
written in a mixed style:

```dart
  VariableDeclarationImpl({
    required this.name,
    required this.equals,
    required ExpressionImpl? initializer,
  })  : _initializer = initializer {
    super(comment: null, metadata: null);
    _becomeParentOf(_initializer);
  }
```

The same flow analysis logic that ensures soundness in fully new style
constructors also ensures soundness in mixed style constructors.

### Implicit super invocation

Today, Dart allows an implicit `super()` to be elided from an initializer list
of a non-redirecting generative constructor (and allows for the entire
initializer list to be elided, if it contains nothing else). To preserve
backwards compatibility, and to avoid making new style constructors more verbose
than old style ones, enhanced constructors support the same feature. The precise
rules are specified
[below](#insertion-of-implicit-super-constructor-invocations), but in a
nutshell, if neither the body nor the initializer list of a non-redirecting
generative constructor contains an explicit `super` constructor invocation
expression, then an implicit call to `super()` is considered to occur at the
earliest point in the constructor body at which it would be sound to do so.

For example, this constructor from the analyzer's `AwaitExpressionImpl` class:

```dart
  AwaitExpressionImpl({
    required this.awaitKeyword,
    required ExpressionImpl expression,
  }) : _expression = expression {
    _becomeParentOf(_expression);
  }
```

could be rewritten to:

```dart
  AwaitExpressionImpl({
    required this.awaitKeyword,
    required ExpressionImpl expression,
  }) {
    _expression = expression;
    _becomeParentOf(_expression);
  }
```

With the implicit call to `super()` occurring right after the assignment
`_expression = expression;`.

### Interaction with `this.` and `super.` parameters

Today, Dart allows a constructor parameter to use the syntax `this.NAME` to
implicitly initialize a field, and the syntax `super.NAME` to implicitly pass a
parameter to the super constructor.

These features are fully supported by enhanced constructors. For example, the
following code is valid:

```dart
class B {
  final int i;
  B({required this.i});
}

class C extends B {
  final int j;
  C({required super.i, required this.j}) {
    // this.j has been initialized here
    super(); // Implicitly passes `i`
  }
}
```

### Scoping differences with `this.`

Today, Dart allows an initializer list to refer to a `this.NAME` parameter,
through some special scoping magic: A `this.NAME` parameter is considered to
introduce a final variable named `NAME` into the formal parameter initializer
scope, but not into the constructor body. Most of the time this leads to
intuitive behaviors, for example:

```dart
class C {
  final int i;
  final int j;
  C(this.i)
    : j = i // `i` refers to the parameter passed to `C()`
  {
    print(i); // `i` refers to `this.i`, which has the same value.
  }
}
```

But occasionally the difference can show up in surprising ways:

```dart
class C {
  int i;
  final void Function() f;
  late final void Function() g;
  C(this.i)
    : f = (() { print(i); }) // prints the value passed to `C()`
  {
    g = () { print(i); }; // prints the current value of `this.i`
  }
}

main() {
  var c = C(1);
  c.i = 2;
  c.f(); // prints `1`
  c.g(); // prints `2`
}
```

If the constructor for `C` is converted into an enhanced constructor in the
obvious way, `i` will refer to `this.i`, so the behavior will change:

```dart
class C {
  int i;
  final void Function() f;
  late final void Function() g;
  C(this.i)
  {
    f = () { print(i); }; // prints the current value of `this.i`
    g = () { print(i); }; // prints the current vlaue of `this.i`
  }
}

main() {
  var c = C(1);
  c.i = 2;
  c.f(); // prints `2`
  c.g(); // prints `2`
}
```

### Scoping differences with `super.`

As with `this.NAME`, a `super.NAME` parameter is considered to introduce a final
variable named `NAME` into the formal parameter initializer scope, but not into
the constructor body. This leads to a somewhat counterintuitive situation: a
super parameter can be referred to from an initializer list, but can't be
referred to from a constructor body. For example:

```dart
class B {
  final int x;
  B(this.x)
}

class C extends B {
  final int j;
  late final int k;
  C(super.i)
    : j = i // `i` refers to the parameter passed to `C()`
  {
    k = i; // ERROR: `i` is not defined
  }
}
```

As a consequence of this, a user trying to rewrite a constructor from old style
to new style may need to reduce their use of the `super.` parameter feature. For
example, consider this code:

```dart
class B {
  final int i;
  B({required this.i});
}

class C extends B {
  final int j;
  C({required super.i}) : j = i; // ok; `i` is in scope
}
```

To change the constructor for `C` into the new style, the `super.i` parameter
needs to be changed into an ordinary parameter:

```dart
class B {
  final int i;
  B({required this.i});
}

class C extends B {
  final int j;
  C({required int i}) {
    j = i; // ok; `i` is in scope
    super(i);
  }
}
```

## Details

### Parser support

No additional parser support is needed to support this feature, since the two
new pieces of syntax (writes to final fields and super/this constructor
invocations) are already accepted by the parser.

### Flow analysis enhancements

#### New boolean state

When flow analysis is used on a non-redirecting generative constructor, it
tracks the following additional pieces of boolean state, for every control flow
path:

- For each non-late field in the containing class, an `assigned` boolean that, if true,
  indicates that the field is definitely assigned.

- For each non-late final field in the containing class, an `unassigned` boolean
  that, if true, indicates that the field is definitely unassigned.

- A single `constructed` boolean that, if true, indicates that a constructor
  invocation has definitely occurred.

- A single `unconstructed` boolean that, if true, indicates that a constructor
  invocation has definitely _not_ occurred.

The behavior of all these boolean variables in the presence of a flow analysis
`join` operation is the same as it is for the other boolean variables tracked by
flow analysis. _These rules are:_

- _When joining two reachable control flow paths `A` and `B` to form a joined
  control flow path `C`, any given boolean variable is true in `C` if and only
  if it is true in both `A` and `B`._

- _When joining a reachable control flow path `A` with an unreachable control
  flow path `B` to form a joined control flow path `C`, all boolean variables
  take on the same values in `C` as they do in `A`. (And vice versa with the
  roles of `A` and `B` reversed.)_

- _When joining two unreachable control flow paths `A` and `B` to form a joined
  control flow path `C`, if there exists a split point from which `A` is
  reachable but `B` is not, all boolean variables take on the same values in `C`
  as they do in `A`. (And vice versa with the roles of `A` and `B` reversed.)_

- _When joining two unreachable control flow paths `A` and `B` to form a joined
  control flow path `C`, if there is no difference in the reachability of `A`
  and `B` from prior split points, then any given boolean variable is true in
  `C` if and only if it is true in both `A` and `B`._

_Note that it's possible for a field's `unassigned` and `assigned` booleans to
both be `false`; this indicates that control flow has reached a point where flow
analysis cannot tell whether the field has been assigned. This is no different
from how local variables are handled. Similarly, it's possible for the
`constructed` and `unconstructed` booleans to both be `false`; this indicates
that control flow has reached a point where flow analysis cannot tell whether a
constructor invocation has occurred._

#### New state initialization

At the start of analyzing a constructor (prior to analyzing the initializer
list, if there is one), these new state variables are initialized as follows:

- `constructed` is initialized to `false`.

- `unconstructed` is initialized to `true`.

- For each non-late field in the class:

  - If the field's declaration has an initializer, then the field's `assigned`
    boolean is initialized to `true` and its `unassigned` boolean is initialized
    to `false`.

  - Otherwise, if the constructor has a `this.NAME` parameter corresponding to
    the field, then the field's `assigned` boolean is initialized to `true` and
    its `unassigned` boolean is initialized to `false`.

  - Otherwise, if the field is non-final and has a nullable type, then the
    field's `assigned` boolean is initialized to `true` and its `unassigned`
    boolean is initialized to `false`, and the field is considered to take on an
    initial value of `null`.

  - Otherwise, the field's `assigned` boolean is initialized to `false` and its
    `unassigned` boolean is initialized to `true`.

#### New state updates

When flow analysis encounters a write to a non-final field (either in an
initializer or in the constructor body), it updates the field's `assigned`
boolean to `true` and its `unassigned` boolean to `false`.

When flow analysis encounters a `super` initializer or a `super` constructor
invocation expression, or it
[inserts](#insertion-of-implicit-super-constructor-invocations) an implicit
`super` constructor invocation expression, after processing the arguments, it
updates the `constructed` boolean to `true` and the `unconstructed` boolean to
`false`.

#### New flow analysis errors

If a write to a non-late final field occurs at a point in control flow where the
field's `unassigned` boolean is `false`, there is a compile-time error (_final
field possibly initialized twice_).

If a write to a non-late final field occurs inside a nested function or closure,
there is a compile-time error (_final field cannot be initialized inside a
nested function or closure_).

If a read of a non-late field occurs at a point in control flow where the
field's `assigned` boolean is `false`, there is a compile-time error (_read of
possibly uninitialized field_).

If a `super` constructor invocation expression occurs at a point in control flow
where any non-late field's `assigned` boolean is `false`, there is a
compile-time error (_field uninitialized at time of super call_).

If a `super` constructor invocation expression occurs at a point in control flow
where the `unconstructed` boolean is `false`, there is a compile-time error
(_super constructor possibly called twice_).

If a `super` constructor invocation expression occurs inside a nested function
or closure, there is a compile-time error (_super constructor invocation
expression cannot occur inside a nested function or closure_).

If the `constructed` boolean is `false` at the point where control flow reaches
a `return` statement, or the end of the constructor body, then there is a
compile-time error (_a control path failed to invoke a super constructor_).

If any explicit or implicit use of `this` is made that is not a read or write of
a field declared in the class itself, at a point in control flow where the
`constructed` boolean is `false`, then there is a compile-time error (_instance
may not be fully constructed yet_). _Examples include:_

- _A method or operator invocation on `this`._

- _A call to an explicitly declared getter, setter, or method (possibly
  abstract) either in the class or one of its superclasses._

- _A read or write of a field declared in a superclass._

- _A read or write of an abstract field._

- _A call to a setter, getter, or method that is part of the class's interface
  due to the presence of an `implements` clause, and not backed by a field
  declared in the class (the class might be abstract, or the call might forward
  to `noSuchMethod`)._

- _Any other use of `this` that is not syntactically part of a read or write of
  a field._

If any explicit or implicit use of `this` is made that does not resolve to an
invocation of a super constructor, at a point in control flow where the
`constructed` boolean is `false`, then there is a compile-time error (_instance
may not be fully constructed yet_).

_Implementation note: the fact that we have separate `assigned` and `unassigned`
booleans makes it possible to distinguish three states for any given non-late
field: definitely assigned, definitely unassigned, and indeterminate. We might
want to consider having separate error messages for the definite and
indeterminate cases. For example, if the code tries to write to a non-late final
field at a point where the `unassigned` boolean is `false`, we could choose to
issue either the error "final field initialized twice" or "final field
**possibly** initialized twice" based on the state of the `assigned`
boolean. The same goes for the `constructed` and `unconstructed` booleans._

### Disambiguation of super constructor invocations from super method invocations

In a non-redirecting generative constructor, the following expressions are now
potentially ambiguous:

- `super(ARGUMENTS)` could be either an invocation of an unnamed constructor in
  the superclass, or the invocation of an instance method `call` in the
  superclass or one of its ancestors.

- `super.NAME(ARGUMENTS)` could be either an invocation of an accessible
  constructor named `NAME` in the superclass, or the invocation of an instance
  method or getter named `NAME` in the superclass or one of its ancestors.

These forms are disambiguated as follows:

- If the expression is the top level expression in an expression statement, and
  the `constructed` boolean maintained by flow analysis is `false` at the point
  in control flow where the expression appears, it is treated as a constructor
  invocation.

- Otherwise it is treated as a method or getter invocation.

_To see why this disambiguation rule makes sense, consider the fact that a
`super` constructor invocation expression can only legally occur when the
`constructed` boolean is `false`, whereas an invocation of an instance method or
getter in the superclass can only legally occur when the `constructed` boolean
is `true`. Therefore, if there is an interpretation in which the program is
legal, this disambiguation rule is sufficient to find it._

_Implementation note: it is likely that we will want to adopt a more complex
disambiguation rule in the case of erroneous code, so that the resulting error
messages are more meaningful. For example, if `NAME` is the name of a superclass
constructor, and not the name of a superclass getter or method, then it would be
beneficial for the analyzer to interpret `super.NAME(ARGUMENTS)` as a
super-constructor invocation even if the `constructed` boolean is `true`; that
way, the error message will be "super constructor called twice" rather than "no
such method"._

_Note that this disambiguation process needs to occur before any of the
`ARGUMENTS` are visited, since the type of the constructor, method, or function
object being invoked affects the downward inference contexts that will be
supplied when analyzing `ARGUMENTS`. But the point at which the "super
constructor called twice" error is detected is after visiting `ARGUMENTS`. This
is the reason for the restriction that `super` and `this` constructor invocation
expressions may only appear as the top level expression within an expression
statement; it ensures that the `constructed` and `unconstructed` booleans won't
change state between the point of disambiguation and the point of error
reporting, which could create a lot of user confusion._

### Insertion of implicit super constructor invocations

Prior to type inference of a constructor, the constructor's initializer list and
body are scanned to determine whether they already contain an initializer or an
expression statement of the form `super(ARGUMENTS)` or `super.NAME(ARGUMENTS)`.

If neither of these forms is found, an implicit super constructor invocation
will be inserted at the first statement boundary within the block that
constitutes the constructor body, such that the `assigned` booleans for all
non-late fields are `true`. (_This is the earliest point within the constructor
body block at which the user could have written the super constructor invocation
explicitly._)

_Note that it's possible for this heuristic to go wrong; see the [backward
compatibility](#backward-compatibility) section._

_Note that expressions of the above forms that do not constitute a complete
initializer or the top level expression in an expression statement are not
counted by the heuristic, because they cannot represent super constructor
invocations. For example, this is valid:_

```dart
class B {
  int call() => 0;
}
class C extends B {
  C() {
    // Implicit super constructor invocation inserted here.
    print(super()); // `super()` is not the top level expression in an
                    // expression statement, so it is understood to be an
                    // invocation of `super.call()`; therefore it doesn't block
                    // implicit insertion of a super constructor invocation.
  }
```

_The rationale for always inserting the implicit super constructor invocation
within the block that constitutes the constructor body is that this avoids the
danger of trying to insert it inside the body of a loop, which would be
unsound._

### Runtime semantics

In today's Dart, the sequence of operations performed by a non-redirecting
generative constructor is as follows (see the "Execution of Generative
Constructors" heading in the spec, in the "Generative Constructors" section):

- The field declarations are visited in the order in which they appear in
  program text; each initializer is evaluated and the resulting value is bound
  to the corresponding field in the instance being initailized.

- Next, any initializing formals (_`this.` parameters_) are executed, causing
  additional values to be bound to their corresponding fields.

- Then, the initializers in the constructor's initializer list are executed in
  the order in which they appear in program text; each initializer is evaluated
  and the resulting value is bound to the corresponding field.

- Then, any fields that are not yet bound to an object are initialized to
  `null`.

- Then, unless the enclosing class is `Object`, the super-constructor is
  executed to further initialize the instance.

- Finally, the body of the constructor is executed in a scope where `this` is
  bound to the new instance.

_Note that since recursion to the superclass happens in the second-to-last step,
just before execution of the body of the constructor, the consequence is that
all the initializers will be executed first, starting with those declared at the
bottom of the class hierarchy and moving up, before any code can access
`this`. Then, the constructor bodies will all be executed, starting at the top
of the class hierarchy and moving down._

With enhanced constructors, the sequence changes to this (differences in **bold**):

- The field declarations are visited in the order in which they appear in
  program text; each initializer is evaluated and the resulting value is bound
  to the corresponding field in the instance being initailized.

- Next, any initializing formals (_`this.` parameters_) are executed, causing
  additional values to be bound to their corresponding fields.

- Then, the initializers in the constructor's initializer list are executed in
  the order in which they appear in program text; each initializer is evaluated
  and the resulting value is bound to the corresponding field.

- Then, any fields **whose static type is nullable**, that are not yet bound to
  an object, are initialized to `null`.

- Finally, the body of the constructor is executed in a scope where `this` is
  bound to the new instance. **Unless the enclosing class is `Object`, the
  super-constructor is executed at the point where it appears (or was implicitly
  added) within the body of the constructor.**

_Since the recursive step now happens within the body of the constructor, it is
no longer guaranteed that all initializers will run before any constructor
bodies. However, it is still the case that all fields will be initialized,
starting with those declared at the bottom of the class hierarchy and moving up,
before any code can access `this`. Then, the **remainder** of all constructor
bodies will all be executed, starting at the top of the class hierarchy and
moving down._

_Note that for constructors written in the old style, these semantics are 100%
equivalent._

## Const constructors

To allow const constructors to be written in the new style, the restriction that
a const constructor must not have a body is dropped. Instead, a const
constructor is allowed to have a block body, but all statements in the block
must take one of the following forms, or there is a compile-time error:

- A write to a non-late final field (`this.FIELDNAME = VALUE` or `FIELDNAME =
  VALUE`), where `VALUE` is a potentially constant expression.

- A call to a super constructor (`super(ARGUMENTS)` or `super.NAME(ARGUMENTS)`),
  where all the expressions in `ARGUMENTS` are potentially constant expressions.

- An assert statement (`assert(CONDITION)` or `assert(CONDITION, MESSAGE)`),
  where `CONDITION` and `MESSAGE` are potentially constant expressions.

These conditions ensure that it will still be tractable for the constant
evaluator to analyze constants that invoke const constructors.

## Backward compatibility

### Incompatibility due to incorrect disambiguation

Any constructor accepted by the current Dart compiler and analyzer should be
accepted as an enhanced constructor, and should behave the same way at runtime,
with one exception: if the constructor's initializer list doesn't contain an
explicit invocation of a `super` constructor, and the constructor body contains
an
[ambiguous](#disambiguation-of-super-constructor-invocations-from-super-method-invocations)
use of `super`, then with enhanced constructors enabled, the compiler will
disambiguate the first such ambiguity as a `super` constructor invocation
expression, even though the user intended it to be a super method invocation.

The fix is to add an explicit `super()`, either at the top of the constructor
body or at the end of the initializer list.

Most of the time this should lead to a compile-time error (_no such super
constructor_), so the risk of this incompatibility leading to unexpected runtime
behavior should be low. _Note that we should try to craft error messages that
will be helpful to users who run into this situation. We might even consider
adding an analysis server "quick fix" that corrects the problem by adding the
appropriate explicit `super()` invocation._

There are two circumstances in which there won't be a "no such super
constructor" error:

- If the superclass contains an unnamed constructor **and** its interface
  contains a `call` method, then misinterpreting `super(ARGUMENTS)` as a `super`
  constructor invocation expression might lead to some other compile-time error,
  or possibly to no error at all.

- If the superclass contains both an unnamed constructor and a named
  constructor, **and** its interface contains a method with the same name as the
  named constructor, then misinterpreting `super.NAME(ARGUMENTS)` as a `super`
  constructor invocation expression might lead to some other compile-time error,
  or possibly to no error at all.

These circumstances should be pretty rare, especially considering that they will
only constitute a problem if they arise in a constructor that does not
explicitly invoke `super` in its initializer list. However, if we're worried
about this, we could add a lint that detects the upcoming incompatibility and
encourages users to add a `super` invocation to their initializer lists to avoid
it.

### Other incompatibilities

Provided that the ambiguity issue discussed above does not arise, it is fairly
straightforward to show that an old style constructor will not trigger any of
the new flow analysis errors. So there should be no other incompatibilities.

## Back-end consequences

### Super-constructor calls can occur in the middle of flow control

With today's Dart, it is impossible for the call to a super constructor will
never occur inside of a flow control construct (e.g., a loop, `if` statement,
`try` statement, etc.). With enhanced constructors, it will be possible to call
a super constructor inside of a control flow construct, subject to the
constraint that flow analysis needs to be able to prove that the super
constructor call occurs exactly once in all code paths.

If enhanced constructors are implemented today, with no further changes to flow
analysis, it will become possible to call a super constructor from inside an
`if`, `try`, or `switch` statement, but not from inside a loop (because flow
analysis isn't sophisticated enough to recognize parts of loops that are
guaranteed to only execute once). But it's possible that future improvements to
flow analysis will make it possible for a super constructor call to occur inside
a loop (e.g. right before a `break` statement). So back-ends should be prepared
for this possibility.

### Constructors are less tightly bound to super constructors

With today's Dart, each non-redirecting generative constructor is statically
bound to a single super constructor. With enhanced constructors, it is possible
for a constructor to choose at runtime which super constructor to invoke. For
example:

```dart
class C {
  C(bool b) {
    if (b) {
      super.foo();
    } else {
      super.bar();
    }
  }
}
```

### Closures may need to access partially initialized instances

With today's Dart, any closure that accesses a field of `this` is guaranteed to
be operating on an instance that is fully initialized. With enhanced
constructors, a closure could access in an instance that may or may not have
been fully initialized. (Flow analysis still guarantees, however, that the
closure will only access _fields_ that have been fully initialized). For
example:

```dart
f(String Function(String) callback) {
  print(callback('foo'));
  print(callback('bar'));
}

class C {
  String accumulatedMessage;
  final String Function(String) callback;
  C() {
    accumulatedMessage = '';
    String appendMessage(String message) {
      // Even though `this` might not be fully initialized yet, flow analysis
      // permits the `accumulatedMessage` field to be accessed, because that
      // field is already initialized.
      accumulatedMessage += message;
      return accumulatedMessage;
    }
    f(appendMessage);
    callback = appendMessage;
    // `this` is fully initialized now.
  }
}

main() {
  var c = C(); // Prints `foo`, then `foobar`.
  print(c.callback('baz')); // Prints `foobarbaz`.
}
```

Note that in the above example, the first two uses of `callback` access an
incompletely initialized instance of `C`, whereas the third use accesses the
same instance of `C` after it's been completely initialized.

_The reason I'm calling out this example in particular is that it might be
tempting to try to implement this feature as a kernel transformation that
rewrites new style constructors into old style equivalents, storing
field values in hidden local variables until the `super` constructor invocation
expression is encountered. If this implementation strategy is chosen, we would
have to take special care with closures like the one above._

## Interaction with augmentations

The current [augmentation
libraries](https://github.com/dart-lang/language/blob/main/working/augmentation-libraries/feature-specification.md)
proposal specifies that the `augmented` keyword has no special meaning in
non-redirecting generative constructors. This means that unlike function
augmentations, constructor augmentations can't run arbitrary code before the
augmented code, and they can't change the values of arguments. They can only add
initializers and/or asserts, a `super` call (if one is not already present), and
additional code to be run _after_ the augmented constructor. Then everything is
run in a prescribed order that preserves the appropriate soundness guarantees.

If we decide to go ahead with enhanced constructors _before_ adding support for
augmenting constructors, then we will have the opportunity to revisit how
augmentation applies to non-redirecting generative constructors, making them
work a lot more like function augmentations. In particular, we should be able to
allow a constructor augmentation to either contain an `augmented(ARGUMENTS)`
expression instead of a `super` constructor invocation expression, or to simply
invoke the `super` constructor directly. This will allow constructor
augmentations to run arbitrary code before, after, or instead of the augmented
code, and the order in which code executes will be straightforward, since it
will follow the same pattern that function augmentations follow.

Not all of the complexity of constructor augmentations would go away, though. We
would probably need some extra flow analysis rules to ensure that the augmenting
constructor initializes any new fields that have been introduced through the
augmentation process, but doesn't try to initialize any fields that the
augmented constructor initializes.

## Open questions

### Should super invocations be confined to top level?

We might consider restricting `super` constructor invocation expressions so that
they can only appear in a top level statement (i.e., a direct descendant of the
constructor body block).

This change would have the following consequences.

- Flow analysis would be slightly simpler, because it would not be necessary to
  track separate `constructed` and `unconstructed` booleans.

- Some error messages might be easier for the user to understand (e.g., without
  this change, placing a `super` constructor invocation expression inside a loop
  would yield an error explaining that the `super` constructor invocation might
  have already executed; with the change, the error would simply say that
  `super` constructor invocation expressions must go at top level).

- It's possible that this might simplify back-end implementations, since it
  would no longer be possible for a constructor to decide which
  super-constructor to invoke using an `if` or `switch` statement. It's possible
  that this might simplify back-end implementations.

- Some users might find the restriction limiting or surprising.

### Should field writes be confined to top level prior to super invocation?

We might consider restricting field writes so that they can only occur as the
top-level expression in an expression statement which is itself a direct
descendant of the constructor body block.

This change would have the following consequences.

- Flow analysis would be slightly simpler, because it would not be necessary to
  track separate `assigned` and `unassigned` booleans for each field. (Note,
  however, that flow analysis already tracks separate `assigned` and
  `unassigned` booleans for each local variable, and the complexity burden of
  doing so is not very high.)

- Some error messages might be easier for the user to understand (e.g., without
  this change, assigning to a final field inside a loop would yield an error
  explaining that the field might already be assigned; with the change, the
  error would simply say that prior to invoking `super`, field writes must go at
  top level).

- It's possible that this might simplify back-end implementations.

- Some users might find the restriction limiting or surprising.

### Should field reads be prohibited inside closures created prior to super invocation?

We might consider restricting field reads so that they can't occur inside
closures until after invoking `super`.

This change would have the following consequences.

- It's possible that this might simplify back-end implementations, since it
  would mean that closures created prior to super invocation would not need to
  be able to access fields of a partially initialized object.

- Some users might find the restriction limiting or surprising.
