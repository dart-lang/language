# Views

Author: eernst@google.com

Status: Draft


## Change Log

2021.05.12
  - Initial version.


## Summary

This document specifies a language feature that we call "views".

The feature introduces _view types_, which are a new kind of type
declared by a new `view` declaration. A view type provides a
replacement or modification of the members available on instances of
existing types: when the static type of the instance is a view type _V_,
the available members are exactly the ones provided by _V_
(plus the accessible and applicable extension methods, if any).

In contrast, when the static type of an instance is not a view type,
it is always the run-time type of the instance or a supertype. This means
that the available members are the members of the run-time type of the
instance or a subset thereof (again: plus extension methods, if
any). Hence, using a supertype as the static type allows us to see only a
subset of the members, but using a view type allows us to _replace_
the set of members, with subsetting as a special case.

The functionality is entirely static. Invocation of a view member is
resolved at compile-time, based on the static type of the receiver.  Inside
the view declaration, the scoping and the type and meaning of `this` is the
same as for extension methods (a feature which was added to Dart in version
2.6). This is important because it implies that the language Dart has a
single and consistent semantics for all statically resolved member
invocations, rather than having one set of rules for extension methods, and
a different set of rules for view members.


## Motivation

A _view_ is a zero-cost abstraction mechanism that allows
developers to replace the set of available operations on a given object
(that is, the instance members of its type) by a different set of
operations (the members declared by the given view type).

It is zero-cost in the sense that the value denoted by an expression whose
type is a view type is an object of a different type (known as the
on-type of the view type), there is no wrapper object.

The point is that the view type allows for a convenient and safe treatment
of a given object `o` (and objects reachable from `o`) for a specialized
purpose. It is in particular aimed at the situation where that purpose
requires a certain discipline in the use of `o`'s instance methods: We may
call certain methods, but only in specific ways, and other methods should
not be called at all. This kind of added discipline can be enforced by
accessing `o` typed as a view type, rather than typed as its run-time
type `R` or some supertype of `R` (which is what we normally do).

A potential application would be generated view declarations handling the
navigation of dynamic object trees. For instance, they could be JSON
values, modeled using `num`, `bool`, `String`, `List<dynamic>`, and
`Map<String, dynamic>`.

Without view types, the JSON value would most likely be handled with
static type `dynamic`, and all operations on it would be unsafe. If the
JSON value is assumed to satisfy a specific schema, then it would be
possible to reason about this dynamic code and navigate the tree correctly
according to the schema. However, the code where this kind of careful
reasoning is required may be fragmented into many different locations, and
there is no help detecting that some of those locations are treating the
tree incorrectly according to the schema.

If views are supported, we can declare a set of view types with
operations that are tailored to work correctly with the given schema and
its subschemas. This is less error-prone and more maintainable than the
approach where the tree is handled with static type `dynamic` everywhere.

Here's an example that shows the core of that scenario. The schema that
we're assuming allows for nested `List<dynamic>` with numbers at the
leaves, and nothing else.

```dart
view TinyJson on Object {
  Iterable<num> get leaves sync* {
    var self = this;
    if (self is num) {
      yield self;
    } else if (self is List<dynamic>) {
      for (var element in self) {
        yield* element.leaves;
      }
    } else {
      throw "Unexpected object encountered in TinyJson value";
    }
  }
}

void main() {
  TinyJson tiny = <dynamic>[<dynamic>[1, 2], 3, <dynamic>[]];
  print(tiny.leaves);
  tiny.add("Hello!"); // Error.
}
```

The name `TinyJson` can be used as a type, and a reference with that type
can refer to an instance of the underlying on-type `Object`. We use this
feature to declare a variable `tiny` in the main function whose type is
`TinyJson`. The point is that we can now impose an enhanced discipline on
the use of `tiny`, because the view type allows for invocations of the
members of the view, which enables a specific treatment of the underlying
instance of `Object`, consistent with the intended schema.

The getter `leaves` is an example of a disciplined use of the given object
structure. The run-time type may be a `List<dynamic>`, but the schema which
is assumed allows only for certain elements in this list (that is, nested
lists or numbers), and in particular it should never be a `String`. The use
of the `add` method on `tiny` would have been allowed if we had used the
type `List<dynamic>` (or `dynamic`) for `tiny`, and that would break the
schema.

When the type of the receiver is the view type `TinyJson`, it is a
compile-time error to invoke any members that are not in the interface of
the view type (in this case that means: the members declared in the
body of `TinyJson`). So it is an error to call `add` on `tiny`, and that
protects us from violations of the scheme.

In general, the use of a view type allows us to centralize some unsafe
operations. We can then reason carefully about each operation once and for
all. Clients use the view type to access objects conforming to the given
schema, and that gives them access to a set of known-safe operations,
making all other operations in the interface of the on-type a compile-time
error.

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
// Attempt to emulate the view using a class.

class TinyJson {
  // `representation` is assumed to be a nested list of numbers.
  final Object representation;

  TinyJson(this.representation);

  Iterable<num> get leaves sync* {
    var self = representation;
    if (self is num) {
      yield self;
    } else if (self is List<dynamic>) {
      for (var element in self) {
        yield* TinyJson(element).leaves;
      }
    } else {
      throw "Unexpected object encountered in TinyJson value";
    }
  }
}

void main() {
  TinyJson tiny = TinyJson(<dynamic>[<dynamic>[1, 2], 3, <dynamic>[]]);
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
wrapper object, it enforces the desired discipline statically.

Views are static in nature, like extension methods: A view declaration may
declare some type parameters. The type parameters will be bound to types
which are determined by the static type of the receiver. Similarly, members
of a view type are resolved statically, i.e., if `tiny.leaves` is an
invocation of a view getter `leaves`, then the declaration named `leaves`
whose body is executed is determined at compile-time. There is no support
for late binding of a view member, and hence there is no notion of
overriding. In return for this lack of expressive power, we get improved
performance.

Here is another example. It illustrates the fact that a plain view with
on-type `T` introduces a view type `V` which is a supertype of `T`. (There
are two other kinds, `open` and `closed` views, with different subtyping
relationships.) This makes it possible to assign an expression of type `T`
to a variable of type `V`. This corresponds to "entering" the view type
(accepting the specific discipline associated with `V`). Conversely, a cast
from `V` to `T` is a downcast, and hence it must be written explicitly.
This cast corresponds to "exiting" the view type (allowing for violations
of the discipline associated with `V`), and the fact that the cast must be
written explicitly helps developers maintaining the discipline as intended,
rather than dropping out of the view type by accident, silently.

```dart
view ListSize<X> on List<X> {
  int get size => length;
  X front() => this[0];
}

void main() {
  ListSize<String> xs = <String>['Hello']; // OK, upcast.
  print(xs); // OK, `toString()` available on `Object`.
  print("Size: ${xs.size}. Front: ${xs.front()}"); // OK.
  xs[0]; // Error, `operator []` not a member of `ListSize`.

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
  ('open' | 'closed')? 'view' <typeIdentifier> <typeParameters>?
      <viewExtendsPart>?
      'on' <type>
      <viewShowHidePart>
      <interfaces>?
      ('box' 'as' <typeName>)?
  '{'
    (<metadata> <viewMemberDefinition>)*
  '}'

<viewExtendsPart> ::=
  'extends' <viewExtendsList>

<viewExtendsList> ::=
  <viewExtendsElement> (',' <viewExtendsList>)?

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

<viewMemberDefinition> ::= <classMemberDefinition>
```

The token `view` is made a built-in identifier.

*In the rule `<viewShowHideElement>`, note that `<type>` derives
`<typeIdentifier>`, which makes `<identifier>` nearly redundant. However,
`<identifier>` is still needed because it includes some strings that cannot
be the name of a type but can be the basename of a member, e.g., the
built-in identifiers.*


## Primitives

This document needs to refer to explicit view method invocations, so we
will add a special primitive, `invokeViewMethod`, to denote invocations of
view methods.

`invokeViewMethod` is used as a specification device and it cannot occur in
Dart source code. (*As a reminder of this fact, it uses syntax which is not
derivable in the Dart grammar.*)


### Static Analysis of invokeViewMethod

We use
<code>invokeViewMethod(V, <T<sub>1</sub>, .. T<sub>k</sub>>, o).m(args)</code>
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
<code>V<T<sub>1</sub>, .. T<sub>k</sub>>(o).m(args)</code>,
but this is ambiguous since
<code>V<T<sub>1</sub>, .. T<sub>k</sub>>(o)</code>
can be a view constructor invocation.  Similarly,
<code>V<T<sub>1</sub>, .. T<sub>k</sub>>.m(o, args)</code>
is similar to a static method invocation and it may match the semantics
quite well, but that is also confusing because it looks like actual source
code, but it couldn't be used in an actual program.*

*Let us compare view methods to extension methods, noting that they are
similar in many ways. With an extension declaration `E`,
<code>E<T<sub>1</sub>, .. T<sub>k</sub>>(o).m(args)</code>
denotes an explicit invocation of the extension member
named `m` declared by the extension `E`, with `o` bound to `this`, the type
parameters bound to <code>T<sub>1</sub>, .. T<sub>k</sub></code>,
and value parameters bound to the values of `args`.  If `V` is a view with
the same on-type, type parameters, and same declaration of a member `m`,
<code>invokeViewMethod(V, <T<sub>1</sub>, .. T<sub>k</sub>>, o).m(args)</code>
denotes an invocation of the view method `m` with the same bindings.*

The static analysis of `invokeViewMethod` is that it takes exactly three
positional arguments and must be the receiver in a member access. The first
argument must be a type name that denotes a view declaration, the next
argument must be a type argument list, together yielding a view type
_V_. The third argument must be an expression whose static type is _V_ or
the corresponding instantiated on-type (defined below). The member access
must be a member of `V` or an associated member of a superview of `V`.

*Superviews and associated members are specified in the section 'Composing
view types'.*

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
<code>invokeViewMethod(View, <S<sub>1</sub>, .. S<sub>k</sub>>, e).m(args)</code>
Evaluation of `e0` proceeds by evaluating `e` to an object `o` and
evaluating `args` to an actual argument list `args1`, and then executing
the body of `View.m` in an environment where `this` is bound to `o`,
the type variables of `View` are bound to the actual values of
<code>S<sub>1</sub>, .. S<sub>k</sub></code>,
and the formal parameters of `m` are bound to `args1` in the same way
that they would be bound for a normal function call. If the body completes
returning an object `o2`, then `e0` completes with the object `o2`; if the
body throws then the evaluation of `e0` throws the same object with the
same stack trace.


## Static Analysis of Views

Assume that _V_ is a view declaration of the following form:

```dart
view V<X1 extends B1, .. Xk extends Bk> on T {
  ... // Members
}
```

It is then allowed to use `V<S1, .. Sk>` as a type.

*For example, it can occur as the declared type of a variable or parameter,
as the return type of a function or getter, as a type argument in a type,
as the on-type of an extension or view, as the type in the `onPart` of a
try/catch statement, or in a type test `o is V` or a type cast `o as V`, or
as the body of a type alias. It is also allowed to create a new instance
where one or more view types occur as type arguments.*

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
class or mixin, or if a view type is used to derive a mixin.

*So `class C extends V1 with V2 implements V3 {}` has three errors if `V1`,
`V2`, and `V3` are view types, and `mixin M on V1 implements V2 {}`
has two errors.*

If `e` is an expression whose static type `V` is the view type
<code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>
and the basename of `m` is the basename of a member declared by `V`,
then a member access like `e.m(args)` is treated as
<code>invokeViewMethod(View, <S<sub>1</sub>, .. S<sub>k</sub>>, e).m(args)</code>,
and similarly for instance getters and operators.

Lexical lookup for identifier references and unqualified function
invocations in the body of a view declaration work the same as the same
lookup in an extension declaration with the same type parameters and
on-type and members:
In the body of a view declaration `V` with name `View` and type parameters
<code>X<sub>1</sub>, .. X<sub>k</sub></code>, for an invocation like
`m(args)`, if a declaration named `m` is found in the body of `V`
then that invocation is treated as
<code>invokeViewMethod(View, <X<sub>1</sub>, .. X<sub>k</sub>>, this).m(args)</code>.
If there is no declaration in scope whose basename is the basename of `m`,
`m(args)` is treated as `this.m(args)`. *See a later section for the lookup
rule when an `extends` clause is present.*

*For example:*

```dart
extension E1 on int {
  void foo() { print('E1.foo'); }
}

view V1 on int {
  void foo() { print('V1.foo'); }
  void baz() { print('V1.baz'); }
  void qux() { print('V1.qux'); }
}

void qux() { print('qux'); }

view V2 on V1 {
  void foo() { print('V2.foo); }
  void bar() {
    foo(); // Prints 'V2.foo'.
    this.foo(); // Prints 'V1.foo'.
    1.foo(); // Prints 'E1.foo'.
    1.baz(); // Compile-time error.
    baz(); // Prints 'V1.baz'.
    qux(); // Prints 'qux'.
  }
}
```

*That is, when the type of an expression is a view type `V` with on-type
`T`, all method invocations on that expression will invoke an instance
method declared by `V`, and similarly for other member accesses (or it is
an extension method invocation on some extension `E1` with on-type `T1`
such that `T` matches `T1`). In particular, we cannot invoke an instance
member of the on-type when the receiver type is a view type (unless the
view type enables them explicitly, cf. the show/hide part specified in a
later section).*

Let `D` be a view declaration named `View` with type parameters
<code>X<sub>1</sub> extends B<sub>1</sub>, .. X<sub>k</sub> extends B<sub>k</sub></code>
and on-type clause `on T`. Then we say that the _declared on-type_ of `View`
is `T`, and the _instantiated on-type_ corresponding to
<code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>
is
<code>[S<sub>1</sub>/X<sub>1</sub>, .. S<sub>k</sub>/X<sub>k</sub>]T</code>.
We will omit 'declared' and 'instantiated' from the phrase when it is clear
from the context whether we are talking about the view itself or a
particular instantiation of a generic view. For non-generic views, the
on-type is the same in either case.

We say that `D` is _open_ respectively _closed_ if its declaration
starts with the keyword `open` respectively `closed`, and similarly we
say that a view type <code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>
where `View` denotes `D` is _open_ respectively _closed_.
If `D` starts with the keyword `view` we say that `D` is _plain_
and that corresponding view types are _plain_.

Let `V` be a view type of the form
<code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>,
and let `T` be the corresponding instantiated on-type.
When `T` is a top type, `V` is also a top type.
Otherwise the following applies:

- If `V` is a plain view type then `V` is a proper subtype of `Object?`,
and a proper supertype of `T`. *That is, an expression of the on-type can
freely be assigned to a variable of the view type, but in the opposite
direction there must be an explicit cast.*
- If `V` is a closed view type then `V` is a proper subtype of `Object?`.
*So the on-type and the view type are unrelated, and there is no
assignability in either direction. In this case a view constructor may be
used to obtain a value of the view type (see below).*
- If `V` is an open view type then `V` is an alias for `T`. *So the on-type
and the view type are freely assignable to each other.*

When `V` is a view type which is not closed, a type test `o is V`
or `o is! V` and a type check `o as V` can be performed. Such checks
performed on a local variable can promote the variable to the view type
using the normal rules for type promotion.

In the body of a member of a view `V`, the static type of `this` is the
on-type of `V`.

*Compared to the extension methods feature, there is no difference wrt the
type of `this` in the body of a view type _V_. Similarly, members of _V_
invoked in the body of _V_ are subject to the same treatment as members of
an extension, which means that view members of the enclosing view can be
invoked implicitly, and view members are given higher priority than
instance methods on `this`, when `this` is implicit. Note that 
associated members of superviews can be invoked implicitly as well, as
specified in section 'Composing view types'.*

A view declaration may declare one or more non-redirecting
factory constructors. A factory constructor which is declared in a
view declaration is also known as a _view constructor_.

*The purpose of having a view constructor is that it bundles an
approach for building an instance of the on-type of a view type `V`
with `V` itself, which makes it easy to recognize that this is a way to
obtain a value of type `V`. It can also be used to verify that an existing
object (provided as an actual argument to the constructor) satisfies the
requirements for having the type `V`.*

An instance creation expression of the form
<code>V<T<sub>1</sub>, .. T<sub>k</sub>>(...)</code>
or
<code>V<T<sub>1</sub>, .. T<sub>k</sub>>.name(...)</code>
is used to invoke these constructors, and the type of such an expression is
<code>V<T<sub>1</sub>, .. T<sub>k</sub>></code>.

During static analysis of the body of a view constructor of a view which is
not closed, the return type is considered to be the view type declared by
the enclosing declaration.

*This means that the constructor can return an expression whose static type
is the on-type, as well as an expression whose static type is the view
type.*

During static analysis of the body of a view constructor of a view which is
closed, the return type is considered to be the on-type of the enclosing
declaration.

*So these constuctors can only return an expression of the on-type, not an
expression of the view type, but an explicit cast to the on-type can be
used if needed.*

It is a compile-time error if it is possible to reach the end of a view
constructor without returning anything. *Even in the case where the on-type
is nullable and the intended representation is the null object, an explicit
`return null;` is required.*

Let `V` be a view declaration. It is an error to declare a member in
`V` which is also a member of `Object`.

*This is because the members of `Object` are by default shown, as
specified below in the section about the show/hide part. It is possible to
use `hide` to omit some or all of these members, in which case it is
possible to declare members in `V` with those names.*


### Allow instance member access using `show` and `hide`

This section specifies the effect of including a non-empty
`<viewShowHidePart>` in a view declaration.

*The show/hide part provides access to a subset of the members of the
interface of the on-type. For instance, if the intended purpose of the
view type is to maintain a certain set of invariants about the state
of the on-type instance, it is no problem to let clients invoke any methods
that do not change the state. We could write forwarding members in the
view body to enable those methods, but using show/hide can have the
same effect, and it is much more concise and convenient.*

We use the phrase _view show/hide part_, or just _show/hide part_ when
no doubt can arise, to denote a phrase derived from
`<viewShowHidePart>`. Similarly, a `<viewShowClause>` is known
as a _view show clause_, and a `<viewHideClause>` is known as
a _view hide clause_, similarly abbreviated to _show clause_ and
_hide clause_.

The show/hide part specifies which instance members of the on-type are
available for invocation on a receiver whose type is the given view type.

If the show/hide part is empty, no instance members except the ones
declared for `Object` can be invoked on a receiver whose static type is
the given view type.

*That is, an empty show/hide part works like `show Object`.*

If the show/hide part is a show clause listing some identifiers and types,
invocation of an instance member is allowed if its basename is one of the
given identifiers, or it is the name of a member of the interface of one of
the types. Instance members declared for `Object` can also be invoked.

*That is, a lone show clause enables the specified members plus the ones
declared for `Object` (if not already included).*

If the show/hide part is a hide clause listing some identifiers and types,
invocation of an instance member is allowed if it is in the interface of
the on-type and _not_ among the given identifiers, nor in the interface of
the specified types.

*That is, a lone hide clause `hide t1, .. tk` works like
`show T hide t1, .. tk` where `T` is the on-type.*

If the show/hide part is a show clause followed by a hide clause, then the
available instance members is computed by first computing the set of
included instance members specified by the show clause as described above,
and then removing instance members from that set according to the hide
clause, as described above.

A `<viewShowHideElement>` can be of the form `get <id>` or `set <id>`
or `operator <operator>` where `<operator>` must be an operator which can
be declared as an instance member of a class. These forms are used to
specify a getter (without the setter), a setter (without the getter), or an
operator.

*If the interface contains a getter `x` and a setter `x=` then `show x`
will enable both, but `show get x` or `show set x` can be used to enable
only one of them, and similarly for `hide`.*

In a show or hide clause, it is possible that a `<viewShowHideElement>` is
an identifier that is the basename of a member of the interface of the
on-type, and it is also the name of a type in scope. In this case, the name
shall refer to the member.

*A conflict is unlikely because type names in general are capitalized, and
member names start with a lower-case letter. Some type names start with a
lower-case letter, too (e.g., `int` and `dynamic`), but those names do not
occur frequently as member names. Should a conflict arise anyway, a
work-around is to use a type alias declaration to obtain a fresh name for
the shadowed type name.*

A compile-time error occurs if a hide or show clause contains an identifier
which is not the basename of an instance member of the on-type, and also
not the name of a type in scope. A compile-time error occurs if a hide or
show clause contains a type which is not among the types that are
implemented by the on-type of the view.

A compile-time error occurs if a member included by the show/hide part has
a name which is also the name of a member declaration in the view type.

*For instance, if a view `V` with a hide clause contains a declaration of a
method named `toString`, the hide clause must include `toString` (or a
class type, because they all include `toString`). Otherwise, the member
declaration named `toString` would be an error.*

Let `V` be a view type with a show/hide part such that a member `m` is
included in the interface of `V`. The member signature of `m` is the member
signature of `m` in the on-type of `V`.

A type in a hide or show clause may be raw (*that is, an identifier or
qualified identifier denoting a generic type, but no actual type
arguments*). In this case the omitted type arguments are determined by the
corresponding superinterface of the on-type.

*Here is an example using a show/hide part:*

```dart
view MyInt on int show num, isEven hide floor {
  int get twice => 2 * this;
}

void main() {
  MyInt m = 42;
  m.twice; // OK, is in the view type.
  m.isEven; // OK, a shown instance member.
  m.ceil(); // OK, a shown instance member.
  m.toString(); // OK, an `Object` member.
  m.floor(); // Error, now shown.
}
```


### Implementing superinterfaces

This section specifies the effect of having an `<interfaces>` part in a
view declaration.

Let `V` be a view declaration where `<interfaces>?` is of the form
`implements T1, .. Tm`. We say that `V` has `T1` .. `Tm` as its direct
superinterfaces.

A compile-time error occurs if a direct superinterface does not denote a
class, or if it denotes a class which cannot be a superinterface of a
class.

*For instance, `implements int` is an error.*

For each member `m` named `n` in each direct superinterface of `V`, an
error occurs unless `V` declares a member `m1` named `n` which is a correct
override of `m`, or the show/hide part of `V` enables an instance member of
the on-type which is a correct override of `m`.

No subtype relationship exists between `V` and `T1, .. Tm`.

*This means that when a view type implements a set of interfaces, it
is enforced that all the specified members are available, and that they
have a signature which is compatible with the ones in `T1, .. Tm`. But
there is no assignability from an expression of type `V` to a variable
whose declared type is `Tj` for some `j` in 1..m. For that, it is necessary
to use `box`, as described below.*

If the `<interfaces>?` part of `V` is empty, the errors specified in this
section can not occur. *In particular, even `toString` and other members of
`Object` can be declared with signatures that are not correct overrides of
the correspsonding member signature in `Object`. Note, however, that a
different error occurs for a declaration named, say, `toString`, unless
there is a clause like `hide toString` in the show/hide part (because of
the name clash).*


### Boxing

This section describes the `box` getter of a view type, which is implicitly
induced when the clause `'box' 'as' <typeName>` is included.

*It may be helpful to equip each view with a companion class whose
instances have a single field holding an instance of the on-type. So it's a
wrapper with the same interface as the view type, except that the view type
may have an implicitly induced getter named `box` and the companion class
may have an implicitly induced getter named `unbox`.*

Let `V` be a view whose declaration includes the clause `box as typeName`.

In the case where `typeName` denotes an existing class, it is a
compile-time error unless it has members with signatures as described
below. In the case where `typeName` denotes any other declaration, a
compile-time error occurs.

In the case where `typeName` does not resolve to a declaration, a
compile-time error occurs unless `typeName` is a `<typeIdentifier>`.
If no error occurred, a new class named `typeName` is implicitly induced
into the same scope as the view declaration as follows:

The class `typeName` has the same type parameters and members as `V`. It is
a subclass of `Object`, with the same direct superinterfaces as `V`, with a
final private field whose type is the on-type of `V`, and with an unnamed
single argument constructor setting that field to the argument. A getter
`Name get box` is implicitly induced in `V`, and it returns an object that
wraps `this`.

`Name` also implicitly induces a getter `V get unbox` which returns the
value of the final field mentioned above, typed as the associated view
type.

In the case where it would be a compile-time error to declare such a member
named `box` or `unbox`, said member is not induced.

*The latter rule helps avoiding conflicts in situations where `box` or
`unbox` is a non-hidden instance member, and it allows developers to write
their own implementations if needed.*

*The rationale for having this mechanism is that the wrapper object is a
full-fledged object: It is a subtype of all the direct superinterfaces of
`V`, so it can be used in code where `V` is not in scope. Moreover, it
supports late binding of the view methods, and even dynamic invocations. It
is costly (it takes space and time to allocate and initialize the wrapper
object), but it is more robust than the view type, which will only work in
a manner which is resolved statically.*


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

*Note that there is no subtype relationship between `V0` and
<code>V<sub>j</sub></code>
in this scenario, only code reuse. This also implies that there is no need
to require anything that resembles a correct override relationship.*

Assume that `V` is a view declaration, and `V0` occurs as the `<type>`
in a `<viewExtendsElement>` in the extends clause of `V`. In this
case we say that `V0` is a superview of `V`.

A compile-time error occurs if `V0` is a type name or a parameterized type
which occurs as a superview in a view declaration `V`, but `V0` does not
denote a view type nor an extension.

Assume that a view declaration `V` has on-type `T`, and that the view type
`V0` is a superview of `V` (*note that `V0` may have some actual type
arguments*).  Assume that `S` is the instantiated on-type corresponding to
`V0`. A compile-time error occurs unless `T` is a subtype of `S`.

*This ensures that it is sound to bind the value of `this` in `V` to `this`
in `V0` when invoking members of `V0`.*

Consider a `<viewExtendsElement>` of the form `V0 <viewShowHidePart>`.  The
_associated members_ of said extends element are computed from the instance
members of `V0` in the same way as we compute the included instance members
of the on-type using the `<viewShowHidePart>` that follows the on-type in
the declaration.

Assume that `V` is a view declaration and that the view type `V0` is a
superview of `V`. Let `m` be the name of an associated member of `V0`. A
compile-time error occurs if `V` also declares a member named `m`.

Assume that `V` is a view declaration and that the view types `V0a` and
`V0b` are superviews of `V`. Let `Ma` be the associated members of `V0a`,
and `Mb` the associated members of `V0b`. A compile-time error occurs
unless the member names of `Ma` and the member names of `Mb` are disjoint
sets.

*It is allowed for `V` to select a getter from `V0a` and the corresponding
setter from `V0b`, even though Dart generally treats a getter/setter pair
as a unit. However, a show/hide part explicitly supports the separation of
a getter/setter pair using `get m` respectively `set m`. The rationale is
that a view type may well be used to provide a read-only interface for an
object whose members do otherwise allow for mutation, and this requires
that the getter is included and the setter is not.*

*Conflicts between superviews are not allowed, they must be resolved
explicitly (using show/hide). The rationale is that the extends clause of
a view is concerned with code reuse, not modeling, and there is no
reason to believe that any implicit conflict resolution will consistently
do the right thing.*

The effect of having a view type `V` with superviews `V1, .. Vk` is that
the union of the members declared by `V` and associated members of `V1,
.. Vk` can be invoked on a receiver of type `V`.

In the body of `V`, the specification of lexical lookup is changed to
include an additional case: If a lexical lookup is performed for a name
`n`, and no declarations whose basename is the basename of `n` is found in
the enclosing scopes, and a member declaration named `n` exists in the sets
of associated members of superviews, then that member declaration is
the result of the lookup; if the lookup is for a setter and a getter is
found or vice versa, then a compile-time error occurs. Otherwise, if the
set of associated members does not contain a member whose basename is the
basename of `n`, the lexical lookup yields nothing (*which implies that
`this.` will be prepended to the expression, following the existing
rules*).

In the body of `V`, a superinvocation syntax similar to an explicit
extension method invocation can be used to invoke a member of a superview
which is hidden: The invocation starts with `super.` followed by the name
of the given superview, followed by the member access. The superview may be
omitted in the case where there is no ambiguity.

*For instance, `super.V3.foo()` can be used to call the `foo` of `V3` on
`this` in the case where the extends clause has `extends ... V3 hide
foo, ...`. If no other superview has a member with basename `foo` it is
also possible to call it using `super.foo()`.*

*This means that the declarations that occur in the enclosing syntax, i.e.,
in an enclosing lexical scope, get the highest priority, as always in
Dart. Those declarations may be top-level declarations, or they may be
members of the enclosing view declaration (in which case an invocation
involves `this` when it is an instance member). The second highest priority
is given to instance members of superviews. The next priority is given to
instance members of the on-type.  Finally we can have an implicit
invocation of a member of an extension `E1` in some cases where the type of
`this` matches the on-type of `E1`.*


## Dynamic Semantics of Views

The dynamic semantics of view member invocation follows from the code
transformation specified in the section about the static analysis.

*In short, with `e` of type
<code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>,
`e.m(args)` is treated as
<code>invokeViewMethod(View, <S<sub>1</sub>, .. S<sub>k</sub>>, e).m(args)</code>.*

The dynamic semantics of an invocation of an instance method of the on-type
which is enabled in a view type by the show/hide part is as if a forwarder
were implicitly induced in the view, with the same signature as that of the
on-type. *For example:*

```dart
view MyNum on num show floor {}

void main() {
  MyNum myNum = 1;
  myNum.floor(); // Call instance method as if myNum had had type `int`.
}
```

At run time, for a given instance `o` typed as a view type `V`, there
is _no_ reification of `V` associated with `o`.

*This means that, at run time, an object never "knows" that it is being
viewed as having a view type. By soundness, the run-time type of `o`
will be a subtype of the on-type of `V`.*

The run-time representation of a type argument which is a view type
`V` (respectively
<code>V<T<sub>1</sub>, .. T<sub>k</sub>></code>)
is the corresponding instantiated on-type.

*This means that a view type and the underlying on-type are considered as
being the same type at run time. So we can freely use a cast to introduce
or discard the view type, as the static type of an instance, or as a type
argument in the static type of a data structure or function involving the
view type.*

*This treatment may appear to be unsound. However, it is in fact sound: Let
`E` be a view type with on-type `T`. This implies that `void Function(E)`
is represented as `void Function(T)` at run-time. In other words, it is
possible to have a variable of type `void Function(E)` that refers to a
function object of type `void Function(T)`. This seems to be a soundness
violation because `T <: E` and not vice versa, statically. However, we
consider such types to be the same type at run time, which is in any case
the finest distinction that we can maintain because there is no
representation of `E` at run time. There is no soundness issue, because the
added discipline of a view type is voluntary.*

A type test, `o is U` or `o is! U`, and a type cast, `o as U`, where `U` is
or contains a view type, is performed at run time as a type test and type
cast on the run-time representation of the view type as described above.


## Discussion

### Non-object types

If we introduce any non-object entities in Dart (that is, entities that
cannot be assigned to a variable of type `Object?`, e.g., external C /
JavaScript / ... entities, or non-boxed tuples, etc), then we may wish to
allow for view types whose on-type is a non-object type.

In this case we may be able to consider a view type `V` on a
non-object type `T` to be a supertype of `T`, but unrelated to all subtypes
of `Object?`.

### Protection

The ability to "enter" a view type implicitly may be considered to be
too permissive.

If we wish to uphold the property that every instance typed as a given view
type `V` has been "vetted" by a particular piece of user-written code then
we may use a protected view. This concept is described in a separate
document.
