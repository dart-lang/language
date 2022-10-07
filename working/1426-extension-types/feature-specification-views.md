# Views

Author: eernst@google.com

Status: Draft


## Change Log

2022.10.07
  - Made a view class whose representation type is a top type a proper
    subtype of `Object?`.
  - Changed subtyping inside a view class `V` such that the
    representation type is a subtype of the enclosing view type.

2022.09.22
  - Removed support for `export`, changed `view` to `view class`.

2022.09.20
  - Updated the inheritance mechanism to fit in with a potential non-virtual
    method mechanism for classes: Use `implements`, remove show/hide.

2022.08.30
  - Used inspiration from the [extension struct][1] proposal and
    various discussions to simplify and improve this proposal.

2021.05.12
  - Initial version.

[1]: https://github.com/dart-lang/language/blob/master/working/extension_structs/overview.md


## Summary

This document specifies a language feature that we call "view classes".

The feature introduces _view types_, which are a new kind of type
declared by a new `view class` declaration. A view type provides a
replacement of the members available on instances of existing types:
when the static type of the instance is a view type _V_, the available
instance members are exactly the ones provided by _V_ (noting that
there may also be some accessible and applicable extension members).

In contrast, when the static type of an instance is not a view type,
it is (by soundness) always the run-time type of the instance, or a
supertype thereof. This means that the available instance members are
the members of the run-time type of the instance, or a subset thereof
(again: there may also be some extension members).

Hence, using a supertype as the static type allows us to see only a
subset of the members. Using a view type allows us to _replace_ the
set of members, with subsetting as a special case.

This functionality is entirely static. Invocation of a view member is
resolved at compile-time, based on the static type of the receiver.

A view class may be considered to be a zero-cost abstraction in the
sense that it works similarly to a wrapper object that holds the
wrapped object in a final instance variable. The view class thus
provides an interface which is chosen independently of the interface
of the wrapped object, and it provides implementations of the members
of the interface of the view class, and those implementations can use
the members of the wrapped object as needed.

However, even though a view class behaves like a wrapping, the wrapper
object will never exist at run time, and a reference whose type is the
view class will actually refer directly to the underlying wrapped
object. Every member access (e.g., an invocation of a method or a
getter) on an expression whose static type is a view type will invoke
a member of the view class (with some exceptions, as explained below),
but this occurs because those member accesses are resolved statically,
which means that the wrapper object is not actually needed.

Given that there is no wrapper object, we will refer to the "wrapped"
object as the _representation object_ of the view class, or just the
_representation_.

Inside the view class declaration, the keyword `this` is a reference
to the representation whose static type is the enclosing view class. A
member access to a member of the enclosing view class may rely on
`this` being induced implicitly (for example, `foo()` means
`this.foo()` if the view class contains a method declaration named
`foo`). A reference to the representation typed by its run-time type
or a supertype thereof (that is, typed by a "normal" type for the
representation) is available as a declared name, which is introduced
by a new syntax similar to a parameter list declaration (for example
`(int i)`) which follows the name of the view class. (This syntax is
intended to be a special case of an upcoming mechanism known as
_primary constructors_.) The representation type of the view class
(with `(int i)` that's `int`) is similar to the on-type of an
extension declaration.

All in all, a view class allows us to replace the interface of a given
representation object and specify how to implement the new interface
in terms of the interface of the representation object.

This is something that we could obviously do with a wrapper, but when
it is done with a view class there is no wrapper object, and hence
there is no run-time performance cost. In particular, in the case
where we have a view type `V` with representation type `R` we may be
able to refer to a `List<R>` using the type `List<V>`
(using `theRList as List<V>`), and this corresponds to "wrapping every
element in the list", but it only takes time _O(1)_ and no space, no
matter how many elements the list contains.


## Motivation

A _view class_ is a zero-cost abstraction mechanism that allows
developers to replace the set of available operations on a given object
(that is, the instance members of its type) by a different set of
operations (the members declared by the given view type).

It is zero-cost in the sense that the value denoted by an expression
whose type is a view type is an object of a different type (known as
the _representation type_ of the view type), and there is no wrapper
object, in spite of the fact that the view class behaves similarly to
a wrapping.

The point is that the view type allows for a convenient and safe treatment
of a given object `o` (and objects reachable from `o`) for a specialized
purpose. It is in particular aimed at the situation where that purpose
requires a certain discipline in the use of `o`'s instance methods: We may
call certain methods, but only in specific ways, and other methods should
not be called at all. This kind of added discipline can be enforced by
accessing `o` typed as a view type, rather than typed as its run-time
type `R` or some supertype of `R` (which is what we normally do). For
example:

```dart
view class IdNumber(int i) {
  // Declare a few members.

  // Assume that it makes sense to compare ID numbers
  // because they are allocated with increasing values,
  // so "smaller" means "older".
  operator <(IdNumber other) => i < other.i;

  // Assume that we can verify an ID number relative to
  // `Some parameters`, filtering out some fake ID numbers.
  bool verify(Some parameters) => ...;

  ... // Some other members, whatever is needed.

  // We do not declare, e.g., an operator +, because addition
  // does not make sense for ID numbers.
}

void main() {
  int myUnsafeId = 42424242;
  myUnsafeId = myUnsafeId + 10; // No complaints.

  var safeId = IdNumber(42424242);

  safeId.verify(); // OK, could be true.
  safeId + 10; // Compile-time error, no operator `+`.
  10 + safeId; // Compile-time error, wrong argument type.
  myUnsafeId = safeId; // Compile-time error, wrong type.
  myUnsafeId = safeId as int; // OK, we can force it.
  myUnsafeId = safeId.i; // OK, and safer than a cast.
}
```

In short, we want an `int` representation, but we want to make sure
that we don't accidentally add ID numbers or multiply them, and we
don't want to silently pass an ID number (e.g., as actual arguments or
in assignments) where an `int` is expected. The view class `IdNumber`
will do all these things.

We can actually cast away the view type and hence get access to the
interface of the representation, but we assume that the developer
wishes to maintain this extra discipline, and won't cast away the view
type onless there is a good reason to do so. Similarly, we can access
the representation using the representation name as a getter.  There
is no reason to consider the latter to be a violation of any kind of
encapsulation or protection barrier, it's just like any other getter
invocation. If desired, the author of the view class can choose to use
a private representation name, to obtain a small amount of extra
encapsulation.

The extra discipline is enforced because the view member
implementations will only treat the representation object in ways that
are written with the purpose of conforming to this particular
discipline (and thereby defines what this discipline is). For example,
if the discipline includes the rule that you should never call a
method `foo` on the representation, then the author of the view class
will simply need to make sure that none of the view member
declarations ever calls `foo`.

Another example would be that we're using interop with JavaScript, and
we wish to work on a given `JSObject` representing a button, using a
`Button` interface which is meaningful for buttons. In this case the
implementation of the members of `Button` will call some low-level
functions like `js_util.getProperty`, but a client who uses the view
class will have a full implementation of the `Button` interface, and
will hence never need to call `js_util.getProperty`.

(We _can_ just call `js_util.getProperty` anyway, because it accepts
two arguments of type `Object`. But we assume that the developer will
be happy about sticking to the rule that the low-level functions
aren't invoked in application code, and they can do that by using view
classes like `Button`. It is then easy to `grep` your application code
and verify that it never calls `js_util.getProperty`.)

Another potential application would be to generate view class
declarations handling the navigation of dynamic object trees that are
known to satisfy some sort of schema outside the Dart type system. For
instance, they could be JSON values, modeled using `num`, `bool`,
`String`, `List<dynamic>`, and `Map<String, dynamic>`, and those JSON
values might again be structured according to some schema.

Without view types, the JSON value would most likely be handled with
static type `dynamic`, and all operations on it would be unsafe. If the
JSON value is assumed to satisfy a specific schema, then it would be
possible to reason about this dynamic code and navigate the tree correctly
according to the schema. However, the code where this kind of careful
reasoning is required may be fragmented into many different locations, and
there is no help detecting that some of those locations are treating the
tree incorrectly according to the schema.

If view classes are available then we can declare a set of view types
with operations that are tailored to work correctly with the given
schema and its subschemas. This is less error-prone and more
maintainable than the approach where the tree is handled with static
type `dynamic` everywhere.

Here's an example that shows the core of that scenario. The schema that
we're assuming allows for nested `List<dynamic>` with numbers at the
leaves, and nothing else.

```dart
view class TinyJson(Object it) {
  Iterable<num> get leaves sync* {
    if (it is num) {
      yield it;
    } else if (it is List<dynamic>) {
      for (var element in it) {
        yield* TinyJson(element).leaves;
      }
    } else {
      throw "Unexpected object encountered in TinyJson value";
    }
  }
}

void main() {
  var tiny = TinyJson(<dynamic>[<dynamic>[1, 2], 3, <dynamic>[]]);
  print(tiny.leaves);
  tiny.add("Hello!"); // Error.
}
```

Note that `it` is subject to promotion in the above example. This is safe
because there is no way to override this would-be final instance variable.

The syntax `(Object it)` in the declaration of the view class causes
the view class to have a constructor and a final instance variable
`it` of type `Object`, and it can be used to obtain a value of the
view type from a given instance of the representation type. This
syntax is known as a _primary constructor_.

It is possible to declare other constructors as well; details are
given in the proposal. A constructor body may be declared. It could be
used, e.g., to verify that the given representation object satisfies
some constraints.

In any case, an instance creation of a view type, `View<T>(o)`, will
evaluate to a reference to the value of the final instance variable of
the view class, with the static type `View<T>` (and there is no object
at run time that represents the view class itself).

The name `TinyJson` can be used as a type, and a reference with that
type can refer to an instance of the underlying representation type
`Object`. In the example, the inferred type of `tiny` is `TinyJson`.

We can now impose an enhanced discipline on the use of `tiny`, because
the view type allows for invocations of the members of the view class,
which enables a specific treatment of the underlying instance of
`Object`, consistent with the assumed schema.

The getter `leaves` is an example of a disciplined use of the given object
structure. The run-time type may be a `List<dynamic>`, but the schema which
is assumed allows only for certain elements in this list (that is, nested
lists or numbers), and in particular it should never be a `String`. The use
of the `add` method on `tiny` would have been allowed if we had used the
type `List<dynamic>` (or `dynamic`) for `tiny`, and that could break the
schema.

When the type of the receiver is the view type `TinyJson`, it is a
compile-time error to invoke any members that are not in the interface of
the view type (in this case that means: the members declared in the
body of `TinyJson`). So it is an error to call `add` on `tiny`, and that
protects us from this kind of schema violations.

In general, the use of a view type allows us to centralize some unsafe
operations. We can then reason carefully about each operation once and
for all. Clients use the view type to access objects conforming to the
given schema, and that gives them access to a set of known-safe
operations, making all other operations in the interface of the
representation type a compile-time error.

One possible perspective is that a view type corresponds to an abstract
data type: There is an underlying representation, but we wish to restrict
the access to that representation to a set of operations that are
independent of the operations available on the representation. In other
words, the view type ensures that we only work with the representation in
specific ways, even though the representation itself has an interface that
allows us to do many other (wrong) things.

It would be straightforward to enforce an added discipline like this by
writing a wrapper class with the allowed operations as members, and
working on a wrapper object rather than accessing `o` and its methods
directly:

```dart
// Emulate the view class using a class.

class TinyJson {
  // `representation` is assumed to be a nested list of numbers.
  final Object it;

  TinyJson(this.it);

  Iterable<num> get leaves sync* {
    var localIt = it; // To get promotion.
    if (localIt is num) {
      yield localIt;
    } else if (localIt is List<dynamic>) {
      for (var element in localIt) {
        yield* TinyJson(element).leaves;
      }
    } else {
      throw "Unexpected object encountered in TinyJson value";
    }
  }
}

void main() {
  var tiny = TinyJson(<dynamic>[<dynamic>[1, 2], 3, <dynamic>[]]);
  print(tiny.leaves);
  tiny.add("Hello!"); // Error.
}
```

This is similar to the view type in that it enforces the use of specific
operations (here we only have one: `leaves`) and in general makes it an
error to use instance methods of the representation (e.g., `add`).

Creation of wrapper objects takes time and space, and in the case where we
wish to work on an entire data structure we'd need to wrap each object as
we navigate the data structure. For instance, we need to create a wrapper
`TinyJson(element)` in order to invoke `leaves` recursively.

In contrast, the view class is zero-cost, in the sense that it does
_not_ use a wrapper object, it enforces the desired discipline
statically. In the view class, the invocation of `TinyJson(element)`
in the body of `leaves` can be eliminated entirely by inlining.

View classes are static in nature, like extension members: A view
class declaration may declare some type parameters. The type
parameters will be bound to types which are determined by the static
type of the receiver. Similarly, members of a view type are resolved
statically, i.e., if `tiny.leaves` is an invocation of a view getter
`leaves`, then the declaration named `leaves` whose body is executed
is determined at compile-time. There is no support for late binding of
a view member, and hence there is no notion of overriding. In return
for this lack of expressive power, we get improved performance.


## Syntax

A rule for `<viewDeclaration>` is added to the grammar, along with some
rules for elements used in view declarations:

```ebnf
<viewDeclaration> ::=
  'view' 'class' <typeIdentifier> <typeParameters>?
      <viewPrimaryConstructor>?
      <interfaces>?
  '{'
    (<metadata> <viewMemberDeclaration>)*
  '}'

<viewPrimaryConstructor> ::=
  '(' <type> <identifier> ')'

<viewMemberDeclaration> ::=
  <classMemberDefinition>
```

The token `view` is made a built-in identifier.

A few errors can be detected immediately from the syntax:

If a view declaration named `View` includes a
`<viewPrimaryConstructor>` then it is a compile-time error if the
declaration includes a constructor declaration named `View`. (*But it
can still contain other constructors.*)

If a view declaration named `View` does not include a
`<viewPrimaryConstructor>` then an error occurs unless the view declares
exactly one instance variable `v`. An error occurs unless the declaration of `v`
is final. An error occurs if the declaration of `v` is late.

The _name of the representation_ in a view declaration that includes a
`<viewPrimaryConstructor>` is the identifier `id` specified in there, and
the _type of the representation_ is the declared type of `id`.

In a view declaration named `View` that does not include a
`<viewPrimaryConstructor>`, the _name of the representation_ is the name
`id` of the unique final instance variable that it declares, and the
_type of the representation_ is the declared type of `id`.

A compile-time error occurs if a view declaration declares an abstract
member. A compile-time error occurs if a view declaration has a
`<viewPrimaryConstructor>` and declares an instance variable. Finally,
a compile-time error occurs if a view does not have a
`<viewPrimaryConstructor>`, and it does not declare an instance
variable, or it declares more than one instance variable.

*That is, every view declares exactly one instance variable, and it is
final. A primary constructor (as defined in this document) is just an
abbreviated syntax whose desugaring includes a declaration of exactly
one final instance variable.*

```dart
// Using a primary constructor.
view class V1(R it) {}

// Same thing, using a normal constructor.
view class V2 {
  final R it;
  V2(this.it);
}
```

*There are no special rules for static members in views. They can be
declared and called or torn off as usual, e.g.,
`View.myStaticMethod(42)`.*


## Primitives

This document needs to refer to explicit view method invocations, so we
will add a special primitive, `invokeViewMethod`, to denote invocations of
view methods.

`invokeViewMethod` is used as a specification device and it cannot occur in
Dart source code. (*As a reminder of this fact, it uses syntax which is not
derivable in the Dart grammar.*)


### Static Analysis of invokeViewMethod

We use
<code>invokeViewMethod(V, &lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;, o).m(args)</code>
where `V` is a type name denoting a view to denote the invocation of
the view method `m` on `o` with arguments `args` and view type
arguments
<code>T<sub>1</sub>, .. T<sub>s</sub></code>.
Similar constructs exist for invocation of getters, setters, and
operators.

*For instance, `invokeViewMethod(V, <int>, o).myGetter` and
`invokeViewMethod(V, <int>, o) + rightOperand`.*

*We need special syntax because there is no syntax which will unambiguously
denote a view member invocation. We could consider the syntax of explicit
extension member invocations, e.g.,
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;(o).m(args)</code>,
but this is ambiguous since
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;(o)</code>
can be a view constructor invocation.  Similarly,
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;.m(o, args)</code>
is similar to a named constructor invocation, but that is also
confusing because it looks like actual source code, but it couldn't be
used in an actual program.*

The static analysis of `invokeViewMethod` is that it takes exactly
three positional arguments and must be the receiver in a member
access. The first argument must be a type name `View` that denotes a
view declaration, the next argument must be a type argument list, together
yielding a view type _V_ (*the type argument list may be empty, to
handle the non-generic case*). The third argument must be an expression
whose static type is _V_ or the corresponding instantiated
representation type (defined below). The member access must access a
member of the declaration denoted by `View`, or a member of a
superview of that view declaration.

*Superviews are specified in the section 'Composing view types'.*

If the member access is a method invocation (including an invocation of an
operator that takes at least one argument), it is allowed to pass an actual
argument list, and the static analysis of the actual arguments proceeds as
with other function calls, using a signature where the formal type
parameters of `V` are replaced by
<code>T<sub>1</sub>, .. T<sub>s</sub></code>.
The type of the entire member access is the return type of said member if
it is a member invocation, and the function type of the method if it is a
view member tear-off, again substituting
<code>T<sub>1</sub>, .. T<sub>s</sub></code>
for the formal type parameters.


### Dynamic Semantics of invokeViewMethod

Let `e0` be an expression of the form
<code>invokeViewMethod(View, &lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;, e).m(args)</code>.

Evaluation of `e0` proceeds by evaluating `e` to an object `o` and
evaluating `args` to an actual argument list `args1`, and then
executing the body of `View.m` in an environment where `this` and the
name of the representation are bound to `o`, the type variables of
`View` are bound to the actual values of
<code>T<sub>1</sub>, .. T<sub>s</sub></code>,
and the formal parameters of `m` are bound to `args1` in the same way
that they would be bound for a normal function call. If the body completes
returning an object `o2`, then `e0` completes with the object `o2`; if the
body throws then the evaluation of `e0` throws the same object with the
same stack trace.

*Getters, setters, and operators behave in the same way, with the
obvious small adjustments.*


## Static Analysis of Views

Assume that
<code>T<sub>1</sub>, .. T<sub>s</sub></code>
are types and `V` resolves to a view declaration of the
following form:

```dart
view class V<X1 extends B1, .. Xs extends Bs>(T id) ... {
  ... // Members
}
```

It is then allowed to use
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
as a type.

*For example, it can occur as the declared type of a variable or
parameter, as the return type of a function or getter, as a type
argument in a type, as the representation type of a view, as the
on-type of an extension, as the type in the `onPart` of a try/catch
statement, in a type test `o is V<...>`, in a type cast `o as V<...>`,
or as the body of a type alias. It is also allowed to create a new
instance where one or more view types occur as type arguments.*

A compile-time error occurs if the type
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
is not regular-bounded.

*In other words, such types can not be super-bounded. The reason for this
restriction is that it is unsound to execute code in the body of `V` in
the case where the values of the type variables do not satisfy their
declared bounds, and those values will be obtained directly from the static
type of the receiver in each member invocation on `V`.*

When `s` is zero,
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
simply stands for `V`, a non-generic view.
When `s` is greater than zero, a raw occurrence `V` is treated like a raw
type: Instantiation to bound is used to obtain the omitted type arguments.
*Note that this may yield a super-bounded type, which is then a
compile-time error.*

We say that the static type of said variable, parameter, etc. _is the
view type_
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>,
and that its static type _is a view type_.

A compile-time error occurs if a view type is used as a superinterface of a
class or a mixin, or if a view type is used to derive a mixin.

*In other words, a view type cannot occur as a superinterface in an `extends`,
`with`, `implements`, or `on` clause of a class or mixin. On the other hand,
it can occur in other ways, e.g., as a type argument of a superinterface.*

If `e` is an expression whose static type `V` is the view type
<code>View&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
and `m` is the name of a member declared by `V`, then a member access
like `e.m(args)` is treated as
<code>invokeViewMethod(View, &lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;, e).m(args)</code>,
and similarly for instance getters, setters, and operators.

*In the body of a view declaration _DV_ with name `View` and type parameters
<code>X<sub>1</sub>, .. X<sub>s</sub></code>, for an invocation like
`m(args)`, if a declaration named `m` is found in the body of _DV_
then that invocation is treated as
<code>invokeViewMethod(View, &lt;X<sub>1</sub>, .. X<sub>s</sub>&gt;, this).m(args)</code>.
This is just the same treatment of `this` as in the body of a class.*

*For example:*

```dart
extension E1 on int {
  void foo() { print('E1.foo'); }
}

view class V1(int it) {
  void foo() { print('V1.foo'); }
  void baz() { print('V1.baz'); }
  void qux() { print('V1.qux'); }
}

void qux() { print('qux'); }

view class V2(V1 it) {
  void foo() { print('V2.foo); }
  void bar() {
    foo(); // Prints 'V2.foo'.
    it.foo(); // Prints 'V1.foo'.
    it.baz(); // Prints 'V1.baz'.
    1.foo(); // Prints 'E1.foo'.
    1.baz(); // Compile-time error.
    qux(); // Prints 'qux'.
  }
}
```

*That is, when the static type of an expression is a view type `V`
with representation type `R`, each method invocation on that
expression will invoke an instance method declared by `V` or inherited
from a superview (or it could be an extension method with on-type `V`).
Similarly for other member accesses.*

Let _DV_ be a view declaration named `View` with type parameters
<code>X<sub>1</sub> extends B<sub>1</sub>, .. X<sub>s</sub> extends B<sub>s</sub></code>
and primary constructor `(R id)`.
Alternatively, assume that _DV_ does not declare a primary
constructor, but _DV_ declares a unique, final instance variable named
`id` with declared type `R`.

In both cases we say that the _declared representation type_ of `View`
is `R`, and the _instantiated representation type_ corresponding to
<code>View&lt;T<sub>1</sub>,.. T<sub>s</sub>&gt;</code> is
<code>[T<sub>1</sub>/X<sub>1</sub>, .. T<sub>s</sub>/X<sub>s</sub>]R</code>.

We will omit 'declared' and 'instantiated' from the phrase when it is
clear from the context whether we are talking about the view itself or
a particular instantiation of a generic view. *For non-generic views,
the representation type is the same in either case.*

Let `V` be a view type of the form
<code>View&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>,
and let `R` be the corresponding instantiated representation type.
`V` is a proper subtype of `Object?`. If `R` is non-nullable then `V`
is a proper subtype of `Object` as well.

*That is, an expression of a view type can be assigned to a top type
(like all other expressions), and if the representation type is
non-nullable then it can also be assigned to `Object`. Non-view types
(except bottom types) cannot be assigned to view types without a cast,
except in the case mentioned below.*

Let _DV_ be a view class declaration named `View` with type parameters
<code>X<sub>1</sub>, .. X<sub>s</sub></code>.
In the body of each view member declaration in _DV_, the
representation type is a subtype of the view type
<code>View&lt;X<sub>1</sub>, .. X<sub>s</sub>&gt;</code>.

*This means that the body of the view class itself has an extra power,
compared to code outside the view class: It can assign values of the
representation type `R` to a variable of the view type `V` without a
cast. "Lifted" versions of this power follow from the normal subtype
rules, e.g., it can also assign a value whose type is `List<R>` to a
variable of type `List<V>`. In other words, the body of the view class
declaration has the ability to "wrap the entire list in the view" in
time O(1) and without a cast. It is up to the maintainers of the view
class to make sure that this is an appropriate thing to do.*

In the body of a member of _DV_, the static type of `this` is
<code>View&lt;X<sub>1</sub> .. X<sub>s</sub>&gt;</code>.
The static type of the name of the representation name is the
representation type.

*For example, in `view class V(R id) {...}`, `id` has type `R`, and
`this` has type `V`.*

Again, let `V` be a view type of the form
<code>View&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>,
and let `R` be the corresponding instantiated representation type.
If `R` is not a view type then we say that `V` is a view type
at level zero. If `R` is a view type at level _k_ then we say that
`V` is a view type at level _k + 1_.
A compile-time error occurs if the level of `V` is undefined.

*In other words, cycles are not allowed.*

A view declaration _DV_ named `View` may declare one or more
constructors. A constructor which is declared in a view declaration is
also known as a _view constructor_.

*The purpose of having a view constructor is that it bundles an
approach for building an instance of the representation type of a view
declaration _DV_ with _DV_ itself, which makes it easy to recognize
that this is a way to obtain a value of that view type. It can also be
used to verify that an existing object (provided as an actual argument
to the constructor) satisfies the requirements for having that view
type.*

A primary constructor `(R id)` in _DV_ is a concise notation that
gives rise to a constructor named `View` (that is, it is not "named")
that accepts one parameter of the form `this.id` and has no body.
Moreover, the primary constructor induces an instance variable
declaration of the form `final R id;`.

A compile-time error occurs if a view constructor includes a
superinitializer. *That is, a term of the form `super(...)` or
`super.id(...)` as the last element of the initializer list.*

*In the body of a generative view constructor, the static type of
`this` is the same as it is in any instance member of the view, that
is, `View<X1 .. Xk>`, where `X1 .. Xk` are the type parameters
declared by `View`.*

An instance creation expression of the form
<code>View&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;(...)</code>
or
<code>View&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;.name(...)</code>
is used to invoke these constructors, and the type of such an expression is
<code>View&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>.

*In short, view constructors appear to be very similar to constructors
in classes, and they correspond to the situation where the enclosing
class has a single non-late final instance variable which is initialized
according to the normal rules for constructors (in particular, it must
occur by means of `this.id` or in an initializer list).*


### Composing view types

This section describes the effect of including a clause derived from
`<interfaces>` in a view declaration. We use the phrase
_the view implements clause_ to refer to this clause, or just
_the implements clause_ when no ambiguity can arise.

*The rationale is that the set of members and member implementations
of a given view may need to overlap with that of other views. The
implements clause allows for implementation reuse by putting shared
members in a "super-view" `V1` and putting `V1` in the implements
clause of several view declarations <code>V<sub>1</sub>
.. V<sub>k</sub></code>, thus "inheriting" the members of `V1` into
all of <code>V<sub>1</sub> .. V<sub>k</sub></code> without code
duplication.*

*The reason why this mechanism uses the keyword `implements` rather
than `extends` to declare a relation that involves inheritance is that
it has the same semantics as that of class extension members (a
mechanism which is currently being considered), and view members are
similar to class extension members in that they are statically
resolved.*

Assume that _DV_ is a view declaration named `View`, and `V1` occurs as
one of the `<type>`s in the `<interfaces>` of _DV_. In this case we
say that `V1` is a superview of _DV_.

A compile-time error occurs if `V1` is a type name or a parameterized type
which occurs as a superview in a view declaration _DV_, but `V1` does not
denote a view type.

A compile-time error occurs if any direct or indirect superview of _DV_
is the type `View` or a type of the form `View<...>`. *As usual,
subtype cycles are not allowed.*

Assume that _DV_ has two direct or indirect superviews of the form
<code>W&lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;</code>
respectively
<code>W&lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;</code>.
A compile-time error
occurs unless
<code>T<sub>j</sub></code>
is equal to
<code>S<sub>j</sub></code>
for each _j_ in _1 .. k_. The notion of equality used here is the same
as with the corresponding rule about superinterfaces of classes.

Assume that a view declaration _DV_ named `View` has representation
type `R`, and that the view type `V1` with declaration _DV1_ is a
superview of _DV_ (*note that `V1` may have some actual type
arguments*).  Assume that `S` is the instantiated representation type
corresponding to `V1`. A compile-time error occurs unless `R` is a
subtype of `S`.

*This ensures that it is sound to bind the value of `id` in _DV_ to `id1`
in `V1` when invoking members of `V1`, where `id` is the representation
name of _DV_ and `id1` is the representation name of _DV1_.*

Assume that _DV_ declares a view named `View` with type parameters
<code>X<sub>1</sub> .. X<sub>s</sub></code> and `V1` is a superview of
_DV_. Then
<code>View&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code> is a subtype of
<code>[T<sub>1</sub>/X<sub>1</sub> .. T<sub>s</sub>/X<sub>s</sub>]V1</code>
for all <code>T<sub>1</sub>, .. T<sub>s</sub></code>
where these types are regular-bounded.

*If they aren't regular-bounded then the type is a compile-time error
in itself. In short, if `V1` is a superview of `V` then `V1` is also
a supertype of `V`.*

A compile-time error occurs if a view _DV_ has two superviews `V1` and
`V2`, where both `V1` and `V2` has a member named _m_ with distinct
declarations, and _DV_ does not declare a member named _m_.

*In other words, if two different declarations of _m_ are inherited
from two superviews then the subview must resolve the conflict. The
so-called diamond inheritance pattern can create the case where two
superviews have an _m_, but they are both declared by the same
declaration (so `V` is a subview of `V1` and `V2`, and both `V1` and
`V2` are subviews of `V3`, and `V3` declares _m_, in which case there
is no conflict in `V`).*

*Assume that _DV_ is a view declaration named `View` and that the view
type `V1`, declared by _DV1_, is a superview of _DV_. Let `m` be the
name of a member of `V1`. If _DV_ also declares a member named `m`
then the latter may be considered similar to a declaration that
"overrides" the former.  However, it should be noted that view method
invocation is resolved statically, and hence there is no override
relationship among the two in the traditional object-oriented sense
(that is, it will never occur that the statically known declaration is
the member of `V1`, and the member invoked at run time is the one in
_DV_). Still, a receiver with static type `V1` will invoke the
declaration in _DV1_, and a receiver with static type `View` (or
`View<...>`) will invoke the one in _DV_.*

Hence, we use a different word to describe the relationship between a
member named _m_ of a superview, and a member named _m_ which is
declared by the subview: We say that the latter _redeclares_ the
former.

*In particular, if two different declarations of _m_ is inherited
from two superviews then the subview can resolve the conflict by
redeclaring _m_.*

*Note that there is no notion of having a 'correct override relation'
here. With views, any member signature can redeclare any other member
signature with the same name, including the case where a method is
overridden by a getter or vice versa. The reason for this is that no
call site will resolve to one of several declarations at run time,
each invocation will statically resolve to one particular declaration,
and this makes it possible to ensure that the invocation is type
correct.*

Assume that _DV_ is a view declaration and that the view types `V1`
and `V2` are superviews of _DV_. Let `M1` be the members of `V1`, and
`M2` the members of `V2`. A compile-time error occurs if there is a
member name `m` such that `V1` as well as `V2` has a member named `m`,
and they are distinct declarations, and _DV_ does not declare a member
named `m`.  *In other words, a name clash among distinct "inherited"
members is an error, but it can be eliminated by redeclaring the
clashing name.*

The effect of having a view declaration _DV_ with superviews
`V1, .. Vk` is that the members declared by _DV_ as well as all
members of `V1, .. Vk` that are not redeclared by a declaration in
_DV_ can be invoked on a receiver of the type introduced by _DV_.

In the body of _DV_, a superinvocation syntax similar to an explicit
extension method invocation can be used to invoke a member of a
superview which is redeclared: The invocation starts with `super.`
followed by the name of the given superview, followed by the member
access. The superview may be omitted in the case where there is no
ambiguity.

*For example:*

```dart
view class V2(Object id) {
  void foo() { print('V2.foo()'); }
}

view class V3(Object id) {
  void foo() { print('V3.foo()'); }
}

view class V1(Object id) implements V2, V3 {
  void bar() {
    super.V3.foo(); // Prints "V3.foo()".
  }
}
```


## Dynamic Semantics of Views

The dynamic semantics of view member invocation follows from the code
transformation specified in the section about the static analysis.

*In short, with `e` of type
<code>View&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>,
`e.m(args)` is treated as
<code>invokeViewMethod(View, &lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;, e).m(args)</code>.
Similarly for getters, setters, and operators.*

Consider a view declaration _DV_ named `View` with representation name
`id` and representation type `R`.  Invocation of a non-redirecting
generative view constructor proceeds as follows: A fresh, non-late,
final variable `v` is created. An initializing formal `this.id`
has the side-effect that it initializes `v` to the actual argument
passed to this formal. An initializer list element of the form
`id = e` or `this.id = e` is evaluated by evaluating `e` to an object
`o` and binding `v` to `o`.  During the execution of the constructor
body, `this` and `id` are bound to the value of `v`.  The value of the
instance creation expression that gave rise to this constructor
execution is the value of `this`.

At run time, for a given instance `o` typed as a view type `V`, there
is _no_ reification of `V` associated with `o`.

*This means that, at run time, an object never "knows" that it is being
viewed as having a view type. By soundness, the run-time type of `o`
will be a subtype of the representation type of `V`.*

The run-time representation of a type argument which is a view type
`V` is the corresponding instantiated representation type.

*This means that a view type and the underlying representation type
are considered as being the same type at run time. So we can freely
use a cast to introduce or discard the view type, as the static type
of an instance, or as a type argument in the static type of a data
structure or function involving the view type.*

A type test, `o is U` or `o is! U`, and a type cast, `o as U`, where `U` is
or contains a view type, is performed at run time as a type test and type
cast on the run-time representation of the view type as described above.


### Summary of Typing Relationships

*Here is an overview of the subtype relationships of a view type
`V0` with representation type `R` and superviews `V1 .. Vk`, as well
as other typing relationships involving `V0`:*

- *`V0` is a subtype of `Object?`.*
- *`V0` is a supertype of `Never`.*
- *If `R` is a top type then `V0` is a top type,
  otherwise `V0` is a proper subtype of `Object?`.*
- *If `R` is a non-nullable type then `V0` is a non-nullable type.*
- `V0` is a subtype of each of `V1 .. Vk` (and a proper subtype
  unless `V0` is a top type).*
- *At run time, the type `V0` is identical to the type `R`. In
  particular, `o is V0` and `o as V0` have the same dynamic
  semantics as `o is R` respectively `o as R`, and
  `t1 == t2` evaluates to true if `t1` is a `Type` that reifies
  `V0` and `t2` reifies `R`, and the equality also holds if
  `t1` and `t2` reify types where `V0` and `R` occur as subterms
  (e.g., `List<V0>` is equal to `List<R>`).*


## Discussion

This section mentions a few topics that have given rise to
discussions.


### Support "private inheritance"?

In the current proposal there is a subtype relationship between every
view and each of its superviews. So if we have
`view V(...) extends V1, V2 ...` then `V <: V1` and `V <: V2`.

In some cases it might be preferable to omit the subtype relationship,
even though there is a code reuse element (because `V1` is a superview
of `V`, we just don't need or want `V <: V1`).

A possible workaround would be to write forwarding methods manually:

```dart
view class V1(R it) {
  void foo() {...}
}

// `V` can reuse code from `V1` by using `implements`. Note that
// `S <: R`, because otherwise it is a compile-time error.
view class V(S it) implements V1 {}

// Alternatively, we can write a forwarder, in order to avoid
// having the subtype relationship `V <: V1`.
view class V(S it) {
  void foo() => V1(it).foo();
}
```
