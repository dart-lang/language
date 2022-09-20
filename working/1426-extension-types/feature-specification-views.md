# Views

Author: eernst@google.com

Status: Draft


## Change Log

2022.08.30
  - Used inspiration from the [extension struct][1] proposal and
    various discussions to simplify and improve this proposal.

2021.05.12
  - Initial version.

[1]: https://github.com/dart-lang/language/blob/master/working/extension_structs/overview.md


## Summary

This document specifies a language feature that we call "views".

The feature introduces _view types_, which are a new kind of type
declared by a new `view` declaration. A view type provides a
replacement or modification of the members available on instances of
existing types: when the static type of the instance is a view type
_V_, the available instance members are exactly the ones provided by
_V_ (noting that there may of course also be some accessible and
applicable extension members).

In contrast, when the static type of an instance is not a view type,
it is (by soundness) always the run-time type of the instance, or a
supertype thereof. This means that the available instance members are
the members of the run-time type of the instance, or a subset thereof
(again: there may also be some extension methods).

Hence, using a supertype as the static type allows us to see only a
subset of the members. Using a view type allows us to _replace_ the
set of members, with subsetting as a special case.

This functionality is entirely static. Invocation of a view member is
resolved at compile-time, based on the static type of the receiver.

A view may be considered to be a zero-cost abstraction in the sense
that it works similarly to a wrapper object that holds the wrapped
object in a final instance variable. The view thus provides an
interface which is chosen independently of the interface of the
wrapped object, and it provides implementations of the members of the
interface of the view, and those implementations can use the members
of the wrapped object as needed.

However, even though a view behaves like a wrapping, the wrapper
object will never exist at run time, and a reference whose type is the
view will actually refer directly to the underlying wrapped
object. Every member access (e.g., an invocation of a method or a
getter) on an expression whose static type is a view will invoke a
member of the view (with some exceptions, as explained below), but
this occurs because those member accesses are resolved statically,
which means that the wrapper object is not actually needed.

Given that there is no wrapper object, we will refer to the "wrapped"
object as the _representation object_ of the view, or just the
_representation_.

Inside the view declaration, the keyword `this` is a reference to the
representation whose static type is the enclosing view. A member
access to a member of the enclosing view may rely on `this` being
induced implicitly (for example, `foo()` means `this.foo()` if the
view contains a method declaration named `foo`). A reference to the
representation typed by its run-time type or a supertype thereof (that
is, typed by a "normal" type for the representation) is available as a
declared name, which is introduced by a new syntax similar to a
parameter list declaration (for example `(int i)`) which follows the
name of the view. (This syntax is intended to be a special case of an
upcoming mechanism known as _primary constructors_.) The
representation type of the view (with `(int i)` that's `int`) is
similar to the on-type of an extension declaration.

All in all, a view allows us to replace the interface of a given
representation object and specify how to implement the new interface
in terms of the interface of the representation object.

This is something that we could obviously do with a wrapper, but when
it is done with a view there is no wrapper object, and hence there is
no run-time performance cost. In particular, in the case where we have
a view `V` with representation type `T` we may be able to refer to a
`List<T>` using the type `List<V>`, and this corresponds to "wrapping
every element in the list", but it only takes time _O(1)_ and no
space, no matter how many elements the list contains.


## Motivation

A _view_ is a zero-cost abstraction mechanism that allows
developers to replace the set of available operations on a given object
(that is, the instance members of its type) by a different set of
operations (the members declared by the given view type).

It is zero-cost in the sense that the value denoted by an expression whose
type is a view type is an object of a different type (known as the
_representation type_ of the view type), and there is no wrapper
object, in spite of the fact that the view behaves similarly to a
wrapping.

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
view IdNumber(int i) {
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
in assignments) where an `int` is expected. The view `IdNumber` will
do all these things.

We can actually cast away the view type and hence get access to the
interface of the representation, but we assume that the developer
wishes to maintain this extra discipline, and won't cast away the
view type onless there is a good reason to do so. Similarly, we can
access the representation using the representation name as a getter.
There is no reason to consider the latter to be a violation of any
kind of encapsulation or protection barrier, it's just like any other
getter invocation. If desired, the author of the view can choose to
use a private representation name, to obtain a small amount of extra
encapsulation.

The extra discipline is enforced because the view member
implementations will only treat the representation object in ways that
are written with the purpose of conforming to this particular
discipline (and thereby defines what this discipline is). For example,
if the discipline includes the rule that you should never call a
method `foo` on the representation, then the author of the view will
simply need to make sure that none of the view member declarations
ever calls `foo`.

Another example would be that we're using interop with JavaScript, and
we wish to work on a given `JSObject` representing a button, using a
`Button` interface which is meaningful for buttons. In this case the
implementation of the members of `Button` will call some low-level
functions like `js_util.getProperty`, but a client who uses the view
will have a full implementation of the `Button` interface, and will
hence never need to call `js_util.getProperty`.

(We _can_ just call `js_util.getProperty` anyway, because it accepts
two arguments of type `Object`. But we assume that the developer will
be happy about sticking to the rule that the low-level functions
aren't invoked in application code, and they can do that by using
views like `Button`. It is then easy to `grep` your application code
and verify that it never calls `js_util.getProperty`.)

Another potential application would be to generate view declarations
handling the navigation of dynamic object trees that are known to
satisfy some sort of schema outside the Dart type system. For
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

If views are available then we can declare a set of view types with
operations that are tailored to work correctly with the given schema
and its subschemas. This is less error-prone and more maintainable
than the approach where the tree is handled with static type `dynamic`
everywhere.

Here's an example that shows the core of that scenario. The schema that
we're assuming allows for nested `List<dynamic>` with numbers at the
leaves, and nothing else.

```dart
view TinyJson(Object it) {
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

The syntax `(Object it)` in the declaration of the view causes the
view to have a constructor and a final instance variable `it` of type
`Object`, and it can be used to obtain a value of the view type from a
given instance of the representation type. This syntax is known as a
_primary constructor_.

It is possible to declare other constructors as well; details are
given in the proposal. A constructor body may be declared. It could be
used, e.g., to verify that the given representation object satisfies
some constraints.

In any case, an instance creation of a view type, `View<T>(o)`, will
evaluate to a reference to the value of the final instance variable
of the view, with the static type `View<T>` (and there is no object
at run time that represents the view itself).

The name `TinyJson` can be used as a type, and a reference with that
type can refer to an instance of the underlying representation type
`Object`. In the example, the inferred type of `tiny` is `TinyJson`.

We can now impose an enhanced discipline on the use of `tiny`, because
the view type allows for invocations of the members of the view, which
enables a specific treatment of the underlying instance of `Object`,
consistent with the assumed schema.

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
// Emulate the view using a class.

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

In contrast, the view is zero-cost, in the sense that it does _not_ use a
wrapper object, it enforces the desired discipline statically. In the
view, the invocation of `TinyJson(element)` in the body of `leaves`
can be eliminated entirely by inlining.

Views are static in nature, like extension methods: A view declaration may
declare some type parameters. The type parameters will be bound to types
which are determined by the static type of the receiver. Similarly, members
of a view type are resolved statically, i.e., if `tiny.leaves` is an
invocation of a view getter `leaves`, then the declaration named `leaves`
whose body is executed is determined at compile-time. There is no support
for late binding of a view member, and hence there is no notion of
overriding. In return for this lack of expressive power, we get improved
performance.

Here is another example. It illustrates the fact that a view with
representation type `T` may introduce a view type `V` which is a
supertype of `T`, in the case where the view has the modifier
`implicit`.

This makes it possible to assign an expression of type `T` to a
variable of type `V` (in other words, we do not need to call the
constructor). This corresponds to "entering" the view type (accepting
the specific discipline associated with `V`). Conversely, a cast from
`V` to `T` is a downcast, and hence it must be written explicitly.
This cast corresponds to "exiting" the view type (allowing for
violations of the discipline associated with `V`), and the fact that
the cast must be written explicitly helps developers maintaining the
discipline as intended, rather than dropping out of the view type by
accident.

```dart
implicit view ListSize<X>(List<X> it) {
  int get size => it.length;
  X front() => it[0];
}

void main() {
  ListSize<String> xs = <String>['Hello']; // OK, upcast.
  print(xs); // OK, `toString()` available on `Object`.
  print("Size: ${xs.size}. Front: ${xs.front()}"); // OK.
  xs[0]; // Error, `operator []` is not a member of `ListSize`.

  List<ListSize<String>> ys = [xs]; // OK.
  List<List<String>> ys2 = ys; // Error, downcast.
  ListSize<ListSize<Object>> ys3 = ys; // OK.
  ys[0].front(); // OK.
  ys3.front().front(); // OK.
  ys as List<List<String>>; // `ys` is promoted, succeeds at run time.
}
```


## Syntax

A rule for `<viewDeclaration>` is added to the grammar, along with some
rules for elements used in view declarations:

```ebnf
<viewDeclaration> ::=
  'implicit'? 'view' <typeIdentifier> <typeParameters>?
      <viewPrimaryConstructor>?
      <viewExtendsPart>?
  '{'
    (<metadata> <viewMemberDeclaration>)*
  '}'

<viewPrimaryConstructor> ::=
  '(' <type> <identifier> ')'

<viewExtendsPart> ::=
  'extends' <viewExtendsList>

<viewExtendsList> ::=
  <viewExtendsElement> (',' <viewExtendsElement>)*

<viewExtendsElement> ::= <type> <viewShowHidePart>

<viewShowHidePart> ::=
  <viewShowClause>? <viewHideClause>?

<viewShowClause> ::= 'show' <viewShowHideList>

<viewHideClause> ::= 'hide' <viewShowHideList>

<viewShowHideList> ::=
  <viewShowHideElement> (',' <viewShowHideElement>)*

<viewShowHideElement> ::=
  <type> |
  <identifier> |
  'operator' <operator> |
  ('get'|'set') <identifier>

<viewMemberDeclaration> ::=
  <classMemberDefinition> |
  <memberExportDeclaration>

<memberExportDeclaration> ::=
  'export' <identifier> <viewShowHidePart> ';'

<viewExtensionDeclaration> ::=
  'view' 'extension' (<typeIdentifier> '.')? <typeIdentifier> <typeParameters>?
      <viewNamespaceClause>
      <viewPrimaryConstructor>?
  '{'
    (<metadata> <viewMemberDeclaration>)*
  '}'

<viewNamespaceClause> ::=
  'namespace' <identifierList>

<viewNamespaceDirective> ::=
  'view' 'namespace' <viewShowClause>? <viewHideClause>? ';'

<viewShowClause> ::=
  'show' <viewNamespaceList>

<viewHideClause> ::=
  'hide' <viewNamespaceList>

<viewNamespaceList> ::=
  <viewNamespaceElement> (',' <viewNamespaceElement>)*

<viewNamespaceElement> ::=
  ((<typeIdentifier> '.')? <typeIdentifier> '.')? <identifier>
```

The token `view` is made a built-in identifier.

*In the rule `<viewShowHideElement>`, note that `<type>` derives
`<typeIdentifier>`, which makes `<identifier>` nearly redundant. However,
`<identifier>` is still needed because it includes some strings that cannot
be the name of a type but can be the basename of a member, e.g., the
built-in identifiers.*

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
view V1(T it) {}

// Same thing, using a normal constructor.
view V2 {
  final T it;
  V2(this.it);
}
```

*There are no special rules for static members in views. They can be
declared and called or torn off as usual, e.g.,
`View.myStaticMethod(42)`. *


## Primitives

This document needs to refer to explicit view method invocations, so we
will add a special primitive, `invokeViewMethod`, to denote invocations of
view methods.

`invokeViewMethod` is used as a specification device and it cannot occur in
Dart source code. (*As a reminder of this fact, it uses syntax which is not
derivable in the Dart grammar.*)


### Static Analysis of invokeViewMethod

We use
<code>invokeViewMethod(V, &lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;, o).m(args)</code>
where `V` is a view to denote the invocation of the view method `m` on `o`
with arguments `args` and view type arguments
<code>T<sub>1</sub>, .. T<sub>k</sub></code>.
Similar
constructs exist for invocation of getters, setters, and operators.

*For instance, `invokeViewMethod(V, <int>, o).myGetter` and
`invokeViewMethod(V, <int>, o) + rightOperand`.*

*We need special syntax because there is no syntax which will unambiguously
denote a view member invocation. We could consider the syntax of explicit
extension member invocations, e.g.,
<code>V&lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;(o).m(args)</code>,
but this is ambiguous since
<code>V&lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;(o)</code>
can be a view constructor invocation.  Similarly,
<code>V&lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;.m(o, args)</code>
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
member of the declaration denoted by `View`, or an associated member
of a superview of that view declaration, or a member added by a view
extension.

*Superviews and associated members are specified in the section 'Composing
view types'. View extensions are specified in the section 'View
extensions'.*

If the member access is a method invocation (including an invocation of an
operator that takes at least one argument), it is allowed to pass an actual
argument list, and the static analysis of the actual arguments proceeds as
with other function calls, using a signature where the formal type
parameters of `V` are replaced by
<code>T<sub>1</sub>, .. T<sub>k</sub></code>.
The type of the entire member access is the return type of said member if
it is a member invocation, and the function type of the method if it is a
view member tear-off, again substituting
<code>T<sub>1</sub>, .. T<sub>k</sub></code>
for the formal type parameters.


### Dynamic Semantics of invokeViewMethod

Let `e0` be an expression of the form
<code>invokeViewMethod(View, &lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;, e).m(args)</code>.

Evaluation of `e0` proceeds by evaluating `e` to an object `o` and
evaluating `args` to an actual argument list `args1`, and then
executing the body of `View.m` in an environment where `this` and the
name of the representation are bound to `o`, the type variables of
`View` are bound to the actual values of
<code>S<sub>1</sub>, .. S<sub>k</sub></code>,
and the formal parameters of `m` are bound to `args1` in the same way
that they would be bound for a normal function call. If the body completes
returning an object `o2`, then `e0` completes with the object `o2`; if the
body throws then the evaluation of `e0` throws the same object with the
same stack trace.

*Getters, setters, and operators behave in the same way, with the
obvious small adjustments.*


## Static Analysis of Views

Assume that _V_ is a view declaration of the following form:

```dart
view V<X1 extends B1, .. Xk extends Bk>(T id) ... {
  ... // Members
}
```

It is then allowed to use `V<S1, .. Sk>` as a type.

*For example, it can occur as the declared type of a variable or
parameter, as the return type of a function or getter, as a type
argument in a type, as the representation type of an extension or
view, as the type in the `onPart` of a try/catch statement, or in a
type test `o is V` or a type cast `o as V`, or as the body of a type
alias. It is also allowed to create a new instance where one or more
view types occur as type arguments.*

A compile-time error occurs if the type `V<S1, .. Sk>` is not
regular-bounded.

*In other words, such types can not be super-bounded. The reason for this
restriction is that it is unsound to execute code in the body of `V` in
the case where the values of the type variables do not satisfy their
declared bounds, and those values will be obtained directly from the static
type of the receiver in each member invocation on `V`.*

When `k` is zero, `V<S1, .. Sk>` simply stands for `V`, a non-generic view.
When `k` is greater than zero, a raw occurrence `V` is treated like a raw
type: Instantiation to bound is used to obtain the omitted type arguments.
*Note that this may yield a super-bounded type, which is then a
compile-time error.*

We say that the static type of said variable, parameter, etc. _is the
view type_ `V<S1, .. Sk>`, and that its static type _is a view type_.

A compile-time error occurs if a view type is used as a superinterface of a
class or a mixin, or if a view type is used to derive a mixin.

If `e` is an expression whose static type `V` is the view type
<code>View&lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;</code>
and the name of `m` is the name of a member declared by `V`,
then a member access like `e.m(args)` is treated as
<code>invokeViewMethod(View, &lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;, e).m(args)</code>,
and similarly for instance getters, setters, and operators.

*In the body of a view declaration _DV_ with name `View` and type parameters
<code>X<sub>1</sub>, .. X<sub>k</sub></code>, for an invocation like
`m(args)`, if a declaration named `m` is found in the body of _DV_
then that invocation is treated as
<code>invokeViewMethod(View, &lt;X<sub>1</sub>, .. X<sub>k</sub>&gt;, this).m(args)</code>.
This is just the same treatment of `this` as in the body of a class.*

*For example:*

```dart
extension E1 on int {
  void foo() { print('E1.foo'); }
}

view V1(int it) {
  void foo() { print('V1.foo'); }
  void baz() { print('V1.baz'); }
  void qux() { print('V1.qux'); }
}

void qux() { print('qux'); }

view V2(V1 it) {
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
with representation type `T`, each method invocation on that
expression will invoke an instance method declared by `V` or exported
by `V` or inherited from a superview or added by an extension view (or
it could be an extension method with on-type `V`). Similarly for other
member accesses.*

Let _DV_ be a view declaration named `View` with type parameters
<code>X<sub>1</sub> extends B<sub>1</sub>, .. X<sub>k</sub> extends B<sub>k</sub></code>
and primary constructor `(T id)`.
Alternatively, assume that _DV_ does not declare a primary
constructor, but _DV_ declares a unique, final instance variable named
`id` with declared type `T`.

In both cases we say that the _declared representation type_ of `View`
is `T`, and the _instantiated representation type_ corresponding to
<code>View&lt;S<sub>1</sub>,.. S<sub>k</sub>&gt;</code> is
<code>[S<sub>1</sub>/X<sub>1</sub>, .. S<sub>k</sub>/X<sub>k</sub>]T</code>.

We will omit 'declared' and 'instantiated' from the phrase when it is
clear from the context whether we are talking about the view itself or
a particular instantiation of a generic view. For non-generic views,
the representation type is the same in either case.

We say that _DV_ is an _implicit_ view if its declaration starts with
the keyword `implicit`. Otherwise, we say that _DV_ is a _plain_
view. Similarly, we say that a view type
<code>View&lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;</code>
where `View` denotes _DV_ is _implicit_ respectively _plain_.

Let `V` be a view type of the form
<code>View&lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;</code>,
and let `T` be the corresponding instantiated representation type.
When `T` is a top type, `V` is also a top type.
Otherwise the following applies:

`V` is a proper subtype of `Object?`. If `T` is non-nullable then `V`
is a proper subtype of `Object` as well.

Moreover, if `V` is an implicit view type then `V` is a proper
supertype of `T`. 


*That is, an expression of a view type can be assigned to a top type
(like all other expressions), and if the representation type is
non-nullable then it can also be assigned to `Object`.  Moreover, an
expression whose type is a subtype of the representation type can be
assigned to an implicit view type (but not to a plain view type). This
means that plain view types enforce the use of constructor invocations
(or casts), whereas the constructor invocations can be omitted for an
implicit view type.*

In the body of a member of a view declaration _DV_ named `View`
and declaring the type parameters `X1 .. Xk`, the static type of
`this` is `View<X1 .. Xk>`. The static type of the name of the
representation name is the representation type.

*For example, in `view V(T id) {...}`, `id` has type `T` and `this`
has type `V`.*

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

A primary constructor `(T id)` in _DV_ is a concise notation that
gives rise to a constructor named `View` (that is, it is not "named")
that accepts one parameter of the form `this.id` and has no body.
Moreover, the primary constructor induces an instance variable
declaration of the form `final T id;`.

A compile-time error occurs if a view constructor includes a
superinitializer. *That is, a term of the form `super(...)` or
`super.id(...)` as the last element of the initializer list.

*In the body of a generative view constructor, the static type of
`this` is the same as it is in any instance member of the view, that
is, `View<X1 .. Xk>`, where `X1 .. Xk` are the type parameters
declared by `View`.*

An instance creation expression of the form
<code>View&lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;(...)</code>
or
<code>View&lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;.name(...)</code>
is used to invoke these constructors, and the type of such an expression is
<code>View&lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;</code>.

*In short, view constructors appear to be very similar to constructors
in classes, and they correspond to the situation where the enclosing
class has a single non-late final instance variable which is initialized
according to the normal rules for constructors (in particular, it must
occur by means of `this.id` or in an initializer list).*


### Allow instance member access using `export`

This section specifies the effect of including a
`<memberExportDeclaration>` in a view declaration, and it specifies the
member export declaration which is implicitly induced if none are
given explicitly.

*A member export declaration is used to provide access to the members
of the interface of the representation type (or a subset thereof). For
instance, if the intended purpose of the view type is to maintain a
certain set of invariants about the state of the underlying
representation type instance, it is no problem to let clients invoke
any methods that do not change the state. We could write forwarding
members in the view body to enable those methods, but using an export
declaration can have the same effect, and it is much more concise.*

A term derived from `<viewShowHideElement>` may occur in several
locations in a member export declaration. We define the set of member
names specified by this construct relative to a given representation
type `T` as follows: Let _SH_ be a term derived from
`<viewShowHideElement>`. Let _M<sub>SH</sub>_ be the set of member
names specified by _SH_ relative to `T`. Then:

- If _SH_ is of the form `id` which is an `<identifier>` and `id` does
  not denote a type then _M<sub>SH</sub>_ is the set containing the
  member name `id` if `T` has a member named `id`, and the member name
  `id=` if `T` has a setter named `id=` (*and both if `T` has both*).
- Otherwise, if _SH_ is of the form `<type>` and denotes a type `S` then
  _M<sub>SH</sub>_ is the set of member names in the interface of `S`
  except the member names in the interface of `Object`.
- If _SH_ is of the form `operator <operator>` then _M<sub>SH</sub>_
  is the singleton set containing that operator.
- If _SH_ is of the form `get <identifier>` then _M<sub>SH</sub>_ is the
  singleton set containing that identifier.
- If _SH_ is of the form `set <identifier>` then _M<sub>SH</sub>_ is the
  singleton set containing that identifier concatenated with `=`.

We use the notation <code>members(_SH_, T)</code> to denote the set of
member names specified by _SH_ relative to `T`.
*That is, <code>members(_SH_, T) = _M<sub>SH</sub>_</code>.*

*If _SH_ is an identifier that denotes a type in scope, it will denote
that type. This is a conflict if the identifier is intended to denote
a member name. In order to avoid this conflict it may be necessary to
import said type with a prefix, such that the identifier will denote a
member name. However, this kind of conflict is very unlikely to occur
in practice, because member names usually start with a lowercase
letter, and type names usually start with an uppercase letter, and the
few expections (like `int` and `dynamic`) are unlikely to be used as
names of members.*

Consider a view declaration _DV_ named `View` whose representation
name is `id` and representation type is `T`. Assume that _DV_ contains
a member export declaration _DX_ of the form `export id S H;` where `S`
is derived from `<viewShowClause>?` and `H` is derived from
`<viewHideClause>?`.

The set of _member names exported_ by _DX_ is computed as follows.

If `S` and `H` are empty then the set of member names exported by _DX_
is the set of member names in the interface of `T`.

If `S` is empty and `H` is
<code>hide H<sub>1</sub>, .. H<sub>k</sub></code>
then let _M<sub>0</sub>_
be the set of member names in the interface of `T`.
For _j_ in _0 .. k-1_, let _M<sub>j+1</sub>_ be
_M<sub>j</sub> &setminus; members(H<sub>j+1</sub>, T)_.
The set of member names exported by _DX_ is then _M<sub>k</sub>_.

If `H` is empty and `S` is
<code>show S<sub>1</sub>, .. S<sub>k</sub></code> then let
_M<sub>0</sub>_ be the set of member names in the interface of
`Object`. For _j_ in _0 .. k-1_, let _M<sub>j+1</sub>_ be
_M<sub>j</sub> &cup; members(S<sub>j+1</sub>, T)_.
The set of member names exported by _DX_ is then _M<sub>k</sub>_.

If both `H` and `S` are non-empty then let
_M<sub>0</sub>_ be the set of member names exported by
`export id S`.
For _j_ in _0 .. k-1_, let _M<sub>j+1</sub>_ be
_M<sub>j</sub> &setminus; members(H<sub>j+1</sub>, T)_.
The set of member names exported by _DX_ is then _M<sub>k</sub>_.

*Note that each member name in the interface of `Object` is included
except if they are explicitly and individually hidden.*

Assume that _DX_ exports a member name _m_.

A compile-time error occurs unless the representation type of _DV_
has a member named _m_.

A compile-time error occurs if _DV_ contains a declaration named _m_,
or _DV_ extends a view type _W_, and _W_ has a declaration named _m_
that is present after processing of any `show` or `hide` clauses on
_W_.

A compile-time error occurs if `H` is of the form `hide H1, .. Hk` and
`Hj` denotes a type `S`, and `S` is not a
superinterface of `T`, and not a denotation of a generic class `G`
such that there exist types `U1 .. Un` such that `G<U1, .. Un>` is a
superinterface of `T`. Similarly for `S` of the form `show S1, .. Sk`.

*That is, an exported name cannot clash with a declared or inherited
name, such conflicts must be resolved using show/hide. Also, we can
only show or hide a type if it is a superinterface of the
representation type, or the raw version of such a type.*

We use the phrase _view show/hide part_, or just _show/hide part_ when
no doubt can arise, to denote a phrase derived from
`<viewShowHidePart>`. Similarly, a `<viewShowClause>` is known
as a _view show clause_, and a `<viewHideClause>` is known as
a _view hide clause_, similarly abbreviated to _show clause_ and
_hide clause_.

Consider a member access (*e.g., a method call or tear-off, or a
getter/setter/operator invocation*) with receiver type `W` which is a
parameterized type of the form `View<T1, .. Tk>` where `View` is the
name of _DV_ (where the non-generic case is covered by _k = 0_).
Assume that the member access invokes or tears off a member named `m`,
where `m` is exported by an export clause of the form `export id S H`
in _DV_, where `id` is the representation name of _DV_. In this case,
the member access is treated as if the receiver has the
representation type `T`.

*For example:*

```dart
view V(int it) {
  export it show num, isEven hide hashCode;
  int get twice => it * 2;
  void hashCode(String silly) {} // OK.
}

void main() {
  var v = V(42);
  v.isEven; // OK, `v` is treated as having type `int`.
  v.isOdd; // Compile-time error, not exported.
  v.twice; // OK, declared by `V`.
  v.toString(); // OK, `Object` is exported by default.
  v.hashCode('Silly indeed!'); // OK.
}
```

If _DV_ does not include any member export declarations exporting the
representation name `id`, it is treated as if it had declared
`export id show Object;`.

*In short, if a view on a type `T` is like a veil hiding `T` and
showing something else, then the exported members of the
representation are like a hole in the veil: We get to see the
underlying representation type, with exactly the same semantics as an
invocation where the receiver type is the representation type,
including OO dispatch and the treatment of default values of optional
parameters.*

It is a compile time error if _DV_ contains a member export declaration
of the form `export m S H` where `m` is not the representation name.

*We may wish to generalize the export mechanism to allow such cases
later on. See the discussion section for further details.*


### Composing view types

This section describes the effect of including a clause derived from
`<viewExtendsPart>` in a view declaration. We use the phrase
_the view extends clause_ to refer to this clause, or just
_the extends clause_ when no ambiguity can arise.

*The rationale is that the set of members and member implementations of a
given view may need to overlap with that of other views. The extends clause
allows for implementation reuse by putting shared members in a "super-view"
`V0` and putting `V0` in the extends clause of several view declarations
<code>V<sub>1</sub> .. V<sub>k</sub></code>,
thus "inheriting" the members of `V0` into all of
<code>V<sub>1</sub> .. V<sub>k</sub></code>
without code duplication.*

Assume that _DV_ is a view declaration named `View`, and `V0` occurs as
the `<type>` in a `<viewExtendsElement>` in the extends clause of
_DV_. In this case we say that `V0` is a superview of _DV_.

A compile-time error occurs if `V0` is a type name or a parameterized type
which occurs as a superview in a view declaration _DV_, but `V0` does not
denote a view type.

Assume that a view declaration _DV_ named `View` has representation
type `T`, and that the view type `V0` with declaration _DV2_ is a
superview of _DV_ (*note that `V0` may have some actual type
arguments*).  Assume that `S` is the instantiated representation type
corresponding to `V0`. A compile-time error occurs unless `T` is a
subtype of `S`.

*This ensures that it is sound to bind the value of `id` in _DV_ to `id0`
in `V0` when invoking members of `V0`, where `id` is the representation
name of _DV_ and `id0` is the representation name of _DV2_.*

Assume that _DV_ declares a view named `View` with type parameters
<code>X<sub>1</sub> .. X<sub>k</sub></code> and `V0` is a superview of
_DV_. Then
<code>View&lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;</code> is a subtype of
<code>[S<sub>1</sub>/X<sub>1</sub> .. S<sub>k</sub>/X<sub>k</sub>]V0</code>
for all <code>S<sub>1</sub>, .. S<sub>k</sub></code>
where these types are regular-bounded.

*If they aren't regular-bounded then the type is a compile-time error
in itself. In short, if `V0` is a superview of `V` then `V0` is also
a supertype of `V`.*

Consider a `<viewExtendsElement>` of the form `V0 <viewShowHidePart>`.
The _associated members_ of said extends element are computed from the
members that `V0` has in the same way as we compute the included
instance members of the representation type based on a member export
declaration.

*Assume that _DV_ is a view declaration named `View` and that the view
type `V0`, declared by _DV0_, is a superview of _DV_. Let `m` be the
name of an associated member of `V0`. If _DV_ also declares a member
named `m` then the latter may be considered similar to a declaration
that "overrides" the former.  However, it should be noted that view
method invocation is resolved statically, and hence there is no
override relationship among the two (that is, it will never occur that
the statically known declaration is the member of `V0`, and the member
invoked at run time is the one in _DV_). Still, a receiver with static
type `V0` will invoke the declaration in _DV0_, and a receiver with
static type `View` will invoke the one in _DV_.*

Assume that _DV_ is a view declaration and that the view types `V0a` and
`V0b` are superviews of _DV_. Let `Ma` be the associated members of `V0a`,
and `Mb` the associated members of `V0b`. A compile-time error occurs
if there is a member name `m` such that `V0a` as well as `V0b` has a
member named `m`, and _DV_ does not declare a member named `m`.
*In other words, a name clash among "inherited" members is an error.*

*It is allowed for _DV_ to select a getter from `V0a` and the
corresponding setter from `V0b`, even though Dart generally treats a
getter/setter pair as a single unit. However, a show/hide part
explicitly supports the separation of a getter/setter pair using
`get m` respectively `set m`. The rationale is that a view type may
well be used to provide a read-only interface for an object whose
members do otherwise allow for mutation, and this requires that the
getter is included and the setter is not.*

*Conflicts between superviews are not allowed, they must be resolved
explicitly (using show/hide). The rationale is that the extends clause of
a view is concerned with code reuse, not modeling, and there is no
reason to believe that any implicit conflict resolution will consistently
do the right thing.*

The effect of having a view declaration _DV_ with superviews
`V1, .. Vk` is that the union of the members declared by _DV_ and
associated members of `V1, .. Vk` can be invoked on a receiver of the
type introduced by _DV_.

In the body of _DV_, a superinvocation syntax similar to an explicit
extension method invocation can be used to invoke a member of a superview
which is hidden: The invocation starts with `super.` followed by the name
of the given superview, followed by the member access. The superview may be
omitted in the case where there is no ambiguity.

*For instance, `super.V3.foo()` can be used to call the `foo` of `V3`
in the case where the extends clause has `extends ... V3 hide foo, ...`.
If no other superview has a member with basename `foo`, it is
also possible to call it using `super.foo()`.*


## View Extensions

A _view extension_ is a declaration that adds members to an existing
view which is in scope.

*The rule of thumb about this mechanism is that it is similar to
extension methods, but they are 'sticky' in the sense that they are
associated with a given view type, and they do not require the
declaration of the view extension to be imported directly.*

*Name clashes are handled by associating each view extension with a
particular set of namespaces, which is named by an identifier list in
the view extension declaration. Clients may then enable or disable
each namespace using show and hide clauses.*

A view extension declaration is derived from
`<viewExtensionDeclaration>`. A compile-time error occurs if a view
extension declaration contains a member export declaration.

Assume that _DX_ is a view extension declaration named `prefix.View`.
A compile-time error occurs unless there is a unique view declaration
named `View` which is imported into the current library with the
import prefix `prefix`.

Assume that _DX_ is a view extension declaration named `View`.  A
compile-time error occurs unless there is a unique view declaration
named `View` which is imported into the current library without an
import prefix.

Let _DV_ denote the above mentioned unique view declaration, whether
or not it is imported with a prefix (so _DX_ may or may not have that
prefix in the following paragraphs).

We say that _DX_ provides an _extension of the view_ declared by _DV_,
and we say that _DX_ _belongs to_ _DV_.

A compile-time error occurs unless _DX_ and _DV_ have exactly the same
type parameters with exactly the same bounds, up to consistent
renaming. A compile-time error occurs unless the representation type of
_DX_ and the representation type of _DV_ are mutual subtypes.

Consider a member access _a_ (*e.g., `v.foo()`*), in a library _L_,
where the receiver type is `View<T1, .. Tk>` where `View` denotes _DV_.

Assume that _L_ contains a view namespace directive derived from
`<viewNamespaceDirective>` of the form `view namespace S H`.

Assume that _E_ is a `<viewNamespaceElement>` of the form
`<identifier>`. _E_ then denotes the set of all view extensions whose
`<viewNamespaceClause>` includes said identifier. If _E_ is of the
form `<typeIdentifier> '.' <identifier>` where the type identifier is
an import prefix then _E_ denotes the set of view extensions exported
by the library which is imported with said prefix, where each view
extension has said identifier in its view namespace clause.

The set of _enabled_ view extensions in _L_ is the set of view
extensions exported by a library which is directly or indirectly
imported by _L_, and which is denoted by an element in `S`, and not
denoted by any element in `H`.

Let _VX<sub>1</sub> .. VX<sub>n</sub>_ be the set of enabled view
extensions belonging to _DV_ which are declared in libraries
_L<sub>1</sub> .. L<sub>n</sub>_ (*not necessarily distinct*)
that are imported directly or indirectly by _L_.

For the given member name (*in the example above: `foo`*), let
_VX<sub>1</sub> .. VX<sub>m</sub>_ be the subset of
_VX<sub>1</sub> .. VX<sub>n</sub>_ that declare a member with that
name (*we can assume that we have chosen a numbering that makes this
possible*).

A compile-time error occurs if _m_ is zero, or _m_ is larger than 1.
Otherwise, the member access _a_ is resolved to denote the declaration
with that name in _VX<sub>1</sub>_.

*In other words, when we are invoking an extension view member, we
only consider the declarations that are enabled by the view namespace
directive of the current library.*

The treatment described above is also used in order to determine the
set of members in the interface of each view that is used as
superviews, directly or indirectly, of the target view _DV_.

*In other words, view extensions can add new members to the target
view as well as any of its superviews, and "inheritance" proceeds as
usual as if the added members were written in those views directly,
rather than being added by view extensions.*

An error occurs if two enabled view extensions both add a member named
`m` to the same view, or if an enabled view extension adds a member
named `m` to a view that already declares a member named `m`.

*These rules ensure that it is possible to extend the set of members
available for a given view in different ways, depending on the import
graph. For example:*

```dart
// Library 'base.dart'.
view V(int it) {
  bool isThree => it == 3;
}

// Library 'extension1.dart'.
view extension V(int it) namespace One {
  void foo() {
    print('Whether I am three: $isThree!');
  }
  void bar() {}
}

// Library 'extension2.dart'.
view Extension V(int it) namespace Two, AlternativeTwo {
  int get foo => 3; // Unrelated to `foo` in extension1.
  set baz(String s) {}
}

// Library 'main1.dart'.
import 'base.dart';
import 'extension1.dart';
import 'extension2.dart';
view namespace show One, Two;

void main() {
  var v = V(3);
  v.isThree; // OK, available from view.
  v.bar(); // OK, from One.
  v.baz = 'Hello'; // OK, from Two.
  v.foo; // Compile-time error, ambiguous.
}

// Library 'main2.dart'.
import 'base.dart';
import 'extension1.dart';
import 'extension2.dart'; // Imported or not, makes no difference.
view namespace show One;

void main() {
  var v = V(3);
  v.isThree; // OK, from view.
  v.bar(); // OK, from One.
  v.baz = 'Hello'; // Compile-time error, no such member.
  v.foo(); // OK, from One.
}
```


### View namespace usage

*This section is a non-normative discussion about some ways that view
namespaces could be managed.*

*If view extensions are used to handle an API migration then a useful
approach could be to have a view namespace indicating the topic (e.g.,
`html`) and a namespace indicating the version (e.g., `legacy` and
`v3_0_0`). Developers would then enable the particular version of a
set of views by means of `view namespace show <topic>, <version>`, for
example: `view namespace show html, v3_0_0;`.*

*Namespaces used as "topics" in this sense could be managed by the
community. For instance, a convention could be applied where large
companies or organizations could use specific suffixes (for example,
view namespaces managed by the Dart team could have the form
`..._core`, e.g., `html_core`; a company ACME could use `..._acme`,
and so on).*

*It would then typically be the case that `..._acme` view namespaces
would contain view extensions on views provided by ACME, and ACME
would take responsibility for avoiding (or eliminating) name clashes
among members added by view extensions, for any given version. So
you're never supposed to enable multiple versions of the same topic in
the same library, and when exactly one version of a given topic is
enabled then it can be expected that there are no name clashes.*


## Dynamic Semantics of Views

The dynamic semantics of view member invocation follows from the code
transformation specified in the section about the static analysis.

*In short, with `e` of type
<code>View&lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;</code>,
`e.m(args)` is treated as
<code>invokeViewMethod(View, &lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;, e).m(args)</code>.
Similarly for getters, setters, and operators.*

The dynamic semantics of an invocation or tear-off of an instance
member of the representation type which is enabled in a view type by a
member export declaration is the same as invoking/tearing-off the same
member on the representation object typed as the representation type.

Consider a view declaration _DV_ named `View` with representation name
`id` and representation type `T`.  Invocation of a non-redirecting
generative view constructor proceeds as follows: A fresh, non-late,
final, local variable `v` is created. An initializing formal `this.id`
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

*This treatment may appear to be unsound for implicit view
types. However, it is in fact sound: Let `V` be a view type with
representation type `T`. This implies that `void Function(V)` is
represented as `void Function(T)` at run-time. In other words, it is
possible to have a variable of type `void Function(V)` that refers to
a function object of type `void Function(T)`. This seems to be a
soundness violation because `T <: V` and not vice versa,
statically. However, we consider such types to be the same type at run
time, which is in any case the finest distinction that we can maintain
because there is no representation of `V` at run time. There is no
soundness issue, because the added discipline of a view type is
voluntary.*

A type test, `o is U` or `o is! U`, and a type cast, `o as U`, where `U` is
or contains a view type, is performed at run time as a type test and type
cast on the run-time representation of the view type as described above.


## Discussion

This section mentions a few topics that have given rise to
discussions.


### Support "private inheritance"?

In the current proposal there is a subtype relationship between every
view and each of its superviews. So if we have 
`view V(...) extends V1, V2 ...` then `V <: V1` and `V <: V2`. This is
true even in the case where the superviews use `show` or `hide` to
inherit just some of the members that the given superview has.

In some cases it might be preferable to omit the subtype relationship,
even though there is a code reuse element (because `V1` is a superview
of `V`, we just don't need or want `V <: V1`).

A possible workaround would be to write forwarding methods manually:

```dart
view V1(T it) {
  void foo() {...}
}

// `V` can reuse code from `V1` by using `extends`. Note that
// `S <: T`, because otherwise it is a compile-time error.
view V(S it) extends V1 {}

// Alternatively, we can write a forwarder, in order to avoid
// having the subtype relationship `V <: V1`.
view V(S it) {
  void foo() => V1(it).foo();
}
```


### Exporting other things than the representation

As stated, this proposal only allows member export statements where
the representation object exports some members from its statically
known interface.

However, this mechanism could very well be generalized to allow export
declarations where any property or path of properties is
exported. Here is an example.

Let _D_ be a view declaration named `V`. Assume that _D_ includes a
member export declaration _DX2_ exporting a getter `g`. In this case
the set of exported member names of _DX2_ is computed in the same way
as the set of exported member names of the representation object,
based on the interface of the return type of `g`. For example:

```dart
view V2(int it) {
  export it hide int, runtimeType, noSuchMethod;
  export predecessor hide num, toString, hashCode, operator ==;
  int get predecessor => it - 1;
}

void main() {
  var v = V2(42);
  v == 42; // OK, returns true.
  v.predecessor; // OK, returns 41.
  v.isEven; // OK, returns false, same as `m.predecessor.isEven`.
  v.isNegative; // Error, not exported, not declared.
  v.toString(); // OK, returns '42'.
}
```

Obviously, a generalized member export feature would need to handle


### Support member export declarations in view extensions?

This would presumably be possible, and might be worthwhile. It would
be used to add more members from the representation type to the
interface of the view, and it would cause a compile-time error in the
case where there is a name clash with a declaration in the target
view.

The proposal currently does not allow this, but the fact that it is an
comile-time error to have `export` in a view extension now means that
we can add it later on, and it will not be a breaking change.


### Allow view extensions to override members?

The current proposal insists that name clashes must be handled
explicitly, by way of show/hide clauses in a member export declaration
or in an extends clause.

The rationale for this choice is that it will be explicit whenever
there is an "override-ish" relation between a view member and an
inherited/exported member. This is important semantically, because a
change from one to the other type (e.g., `V0 v0 = v1;` where the
static type of `v1` is a subview of `V0`) will then invoke a different
implementation when we invoke the same member name, which may give
rise to subtle bugs.

Presumably we could even have lints on assignments where this kind of
"change of semantics" based on the _static type_ used to access an
object will occur, and some developers might want to avoid them
entirely. We could also have lints to flag that kind of override-ish
relationship between view members in the first place.

Members added to a view by a view extension are subject to the same
name clash checks, and this means that they can introduce fresh member
names (members with names that are different from the declared names
in the target view, different from the names of members exported from
the representation type, and different from the names of members
inherited from superviews), but they can't introduce any declarations
with the same name as any member of the interface of the target view.

It would also be possible to allow such name clashes, e.g., by
allowing a view extension to add a member named `m` to a target view
`V` even though `V` inherits a member named `m`, possibly by adding a
hide/show clause on the view extension (so we're adding new members to
the target view, and also editing it's show/hide clauses).
