# Views

Author: eernst@google.com

Status: Draft


## Change Log

2022.08.30
  - Used inspiration from the [extension struct] proposal to simplify and
    improve this proposal.

2021.05.12
  - Initial version.

[extension struct](https://github.com/dart-lang/language/blob/master/working/extension_structs/overview.md)


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
member of the view (with a few exceptions, as explained below), but
this occurs because those member accesses are resolved statically,
which means that the wrapper object is not actually needed.

In this document, given that there is no wrapper object, we will refer
to the "wrapped" object as the _representation object_ of the view, or
just the _representation_.

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
upcoming mechanism known as _primary constructors_.)

All in all, a view allows us to replace the interface of a given
representation object and specify how to implement the new interface
in terms of the interface of the representation object itself. This is
something that we could obviously do with a wrapper, but when it is
done with a view there is no wrapper object, and hence there is no
run-time performance cost.


## Motivation

A _view_ is a zero-cost abstraction mechanism that allows
developers to replace the set of available operations on a given object
(that is, the instance members of its type) by a different set of
operations (the members declared by the given view type).

It is zero-cost in the sense that the value denoted by an expression whose
type is a view type is an object of a different type (known as the
_representation type_ of the view type), and there is no wrapper object.

The point is that the view type allows for a convenient and safe treatment
of a given object `o` (and objects reachable from `o`) for a specialized
purpose. It is in particular aimed at the situation where that purpose
requires a certain discipline in the use of `o`'s instance methods: We may
call certain methods, but only in specific ways, and other methods should
not be called at all. This kind of added discipline can be enforced by
accessing `o` typed as a view type, rather than typed as its run-time
type `R` or some supertype of `R` (which is what we normally do).

(We can actually cast away the view type and hence get access to the
interface of the representation, but we assume that the developer
_wishes_ to maintain this extra discipline, and won't cast away the
view type onless there is a good reason to do so.)

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

(Again, we can just call `js_util.getProperty` anyway, because it
accepts two arguments of type `Object`, but we assume that the
developer will be happy about sticking to the rule that the low-level
functions aren't invoked in application code, and they can do that by
using views like `Button`.)

Another potential application would be generated view declarations
handling the navigation of dynamic object trees. For instance, they
could be JSON values, modeled using `num`, `bool`, `String`,
`List<dynamic>`, and `Map<String, dynamic>`.

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

The syntax `(Object it)` in the declaration of the view causes the
view to have a constructor, and it can be used to obtain a value of
the view type from a given instance of the representation type.

The constructor is a factory that actually just returns its argument,
but typed as the view type. A constructor body may be declared if we
wish to verify that the given object satisfies some constraints.

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
// Attempt to emulate the view using a class.

class TinyJson {
  // `representation` is assumed to be a nested list of numbers.
  final Object it;

  TinyJson(this.it);

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
variable of type `V` (in order words, we do not need to call the
constructor). This corresponds to "entering" the view type (accepting
the specific discipline associated with `V`). Conversely, a cast from
`V` to `T` is a downcast, and hence it must be written explicitly.
This cast corresponds to "exiting" the view type (allowing for
violations of the discipline associated with `V`), and the fact that
the cast must be written explicitly helps developers maintaining the
discipline as intended, rather than dropping out of the view type by
accident, silently.

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
  'export' <identifier> <viewShowHidePart>

<viewExtensionDeclaration> ::=
  'view' 'extension' (<typeIdentifier> '.')? <typeIdentifier> <typeParameters>?
      <viewPrimaryConstructor>?
  '{'
    (<metadata> <viewMemberDeclaration>)*
  '}'
```

The token `view` is made a built-in identifier.

*In the rule `<viewShowHideElement>`, note that `<type>` derives
`<typeIdentifier>`, which makes `<identifier>` nearly redundant. However,
`<identifier>` is still needed because it includes some strings that cannot
be the name of a type but can be the basename of a member, e.g., the
built-in identifiers.*

If a view declaration named `V` includes a `<viewPrimaryConstructor>`
then it is a compile-time error if the declaration includes a
constructor declaration named `V`. (*But it can still contain other
constructors.*)

If a view declaration named `V` does not include a
`<viewPrimaryConstructor>` then an error occurs unless it declares a
factory constructor named `V`, that declares one required, positional
formal parameter, and does not declare any other parameters.

The _name of the representation_ in a view declaration that includes a
`<viewPrimaryConstructor>` is the identifier specified in there. In a
view declaration named `V` that does not include a
`<viewPrimaryConstructor>`, the name of the representation is the name
of the unique formal parameter of the factory constructor named `V`.


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
is similar to a named constructor invocation, but that is also
confusing because it looks like actual source code, but it couldn't be
used in an actual program.*

The static analysis of `invokeViewMethod` is that it takes exactly
three positional arguments and must be the receiver in a member
access. The first argument must be a type name that denotes a view
declaration, the next argument must be a type argument list, together
yielding a view type _V_. The third argument must be an expression
whose static type is _V_ or the corresponding instantiated
representation type (defined below). The member access must be a
member of `V` or an associated member of a superview of `V`.

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
<code>invokeViewMethod(View, <S<sub>1</sub>, .. S<sub>k</sub>>, e).m(args)</code>.

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
class or mixin, or if a view type is used to derive a mixin.

If `e` is an expression whose static type `V` is the view type
<code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>
and the basename of `m` is the basename of a member declared by `V`,
then a member access like `e.m(args)` is treated as
<code>invokeViewMethod(View, <S<sub>1</sub>, .. S<sub>k</sub>>, e).m(args)</code>,
and similarly for instance getters and operators.

In the body of a view declaration `V` with name `View` and type parameters
<code>X<sub>1</sub>, .. X<sub>k</sub></code>, for an invocation like
`m(args)`, if a declaration named `m` is found in the body of `V`
then that invocation is treated as
<code>invokeViewMethod(View, <X<sub>1</sub>, .. X<sub>k</sub>>, this).m(args)</code>.

*For example:*

```dart
extension E1(int it) {
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
with representation type `T`, all method invocations on that
expression will invoke an instance method declared by `V`, and
similarly for other member accesses (or it is an extension method
invocation on some extension `E1` with representation type `T1` such
that `V` matches `T1`). In particular, we cannot invoke an instance
member of the representation type when the receiver type is a view
type (unless the view type enables them explicitly, cf. the show/hide
part specified in a later section).*

Let `D` be a view declaration named `View` with type parameters
<code>X<sub>1</sub> extends B<sub>1</sub>, .. X<sub>k</sub> extends B<sub>k</sub></code>
and primary constructor `(T id)`. Then we say that the _declared
representation type_ of `View` is `T`, and the _instantiated
representation type_ corresponding to <code>View<S<sub>1</sub>,
.. S<sub>k</sub>></code> is
<code>[S<sub>1</sub>/X<sub>1</sub>, .. S<sub>k</sub>/X<sub>k</sub>]T</code>.

We will omit 'declared' and 'instantiated' from the phrase when it is
clear from the context whether we are talking about the view itself or
a particular instantiation of a generic view. For non-generic views,
the representation type is the same in either case.

We say that `D` is _implicit_ respectively _plain_ if its declaration
does respectively does not start with the keyword `implicit`.
Similarly, we say that a view type
<code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>
where `View` denotes `D` is _implicit_ respectively _plain_.

Let `V` be a view type of the form
<code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>,
and let `T` be the corresponding instantiated representation type.
When `T` is a top type, `V` is also a top type.
Otherwise the following applies:

- If `V` is a plain view type then `V` is a proper subtype of
`Object?`.  *So the representation type and the view type are
unrelated, and there is no assignability in either direction. In this
case a view constructor may be used to obtain a value of the view type
(see below).*
- If `V` is an implicit view type then `V` is a proper subtype of
`Object?`, and a proper supertype of `T`. *That is, an expression of
the representation type can freely be assigned to a variable of the
view type, but in the opposite direction there must be an explicit
cast.*

In the body of a member of a view `V`, the static type of `this` is
`V` and the static type of the name of the representation is the
representation type.

A view declaration may declare one or more non-redirecting
factory constructors. A factory constructor which is declared in a
view declaration is also known as a _view constructor_.

*The purpose of having a view constructor is that it bundles an
approach for building an instance of the representation type of a view
type `V` with `V` itself, which makes it easy to recognize that this
is a way to obtain a value of type `V`. It can also be used to verify
that an existing object (provided as an actual argument to the
constructor) satisfies the requirements for having the type `V`.*

A primary constructor is a concise notation that gives rise to a
factory constructor named `V` (that is, it is not "named") that does
nothing other than returning its unique argument, applying a cast to
the view type if the view is not implicit.

An instance creation expression of the form
<code>V<T<sub>1</sub>, .. T<sub>k</sub>>(...)</code>
or
<code>V<T<sub>1</sub>, .. T<sub>k</sub>>.name(...)</code>
is used to invoke these constructors, and the type of such an expression is
<code>V<T<sub>1</sub>, .. T<sub>k</sub>></code>.

During static analysis of the body of a view constructor, the return
type is considered to be the view type declared by the enclosing
declaration.

*This means that the constructor can return an expression whose static type
is the view type, and in an implicit view it can also return an
expression whose static type is the representation type.*

It is a compile-time error if it is possible to reach the end of a
view constructor without returning anything. *Even in the case where
the representation type is nullable and the intended representation is
the null object, an explicit `return null;` is required.*

Let `V` be a view declaration. It is an error to declare a member in
`V` which is also a member of `Object`.

*This is because the members of `Object` are by default exported, as
specified below in the section about the export declaration. It is
possible to use `hide` to omit some or all of these members, in which
case it is possible to declare members in `V` with those names.*


### Allow instance member access using `export`

This section specifies the effect of including a
`<memberExportDeclaration>` in a view declaration.

*A member export declaration is used to provide access to the members
of the interface of the representation type (or a subset thereof). For
instance, if the intended purpose of the view type is to maintain a
certain set of invariants about the state of the underlying
representation type instance, it is no problem to let clients invoke
any methods that do not change the state. We could write forwarding
members in the view body to enable those methods, but using an export
declaration can have the same effect, and it is much more concise and
convenient.*

*A member export delaration can also be used to provide access to
members of other objects reachable from the representation object,
by exporting any getter of the view. An example is shown below.*

A term derived from `<viewShowHideElement>` may occur in several
locations in a member export declaration. We define the set of member
names specified by this construct as follows: Let _SH_ be a term derived
from `<viewShowHideElement>`. Let _M<sub>SH</sub>_ be the set of
member names specified by _SH_. Then:

- If _SH_ is of the form `<identifier>` and it does not denote a type
  then _M<sub>SH</sub>_ is the set containing the single member name
  which is that identifier.
- Otherwise, if _SH_ is of the form `<type>` and denotes a type `T` then
  _M<sub>SH</sub>_ is the set of member names in the interface of `T`
  except the member names in the interface of `Object`
  (*but including both `g` and `g=` in the case where said
  interface contains both a setter and a getter with basename `g`*).
- If _SH_ is of the form `operator <operator>` then _M<sub>SH</sub>_ 
  is the singleton set containing that operator.
- If _SH_ is of the form `get <identifier>` then _M<sub>SH</sub>_ is the
  singleton set containing that identifier.
- If _SH_ is of the form `set <identifier>` then _M<sub>SH</sub>_ is the
  singleton set containing that identifier concatenated with `=`.

*If _SH_ is an identifier that denotes a type, and it is intended to
denote a member name, it will denote the type. In order to avoid this
conflict it may be necessary to import said type with a prefix, such
that the identifier will denote a member name. However, this kind of
conflict is very unlikely to occur in practice, because member names
usually start with a lowercase letter, and type names usually start
with an uppercase letter, and the few expections (like `int` and
`dynamic`) are unlikely to be used as names of members.*

We use the notation <code>members(_SH_)</code> to denote the set of
member names specified by _SH_.

Consider a view declaration _D_ named `V` whose representation object
has the name `n` and the declared type `T`. Assume that _D_ contains a member
export declaration _DX_ of the form `export n S H;` where `S` is
derived from `<viewShowClause>?` and `H` is derived from
`<viewHideClause>?`.

The set of _member names exported_ by _DX_ is computed as follows. 

If `S` and `H` are empty then the set of member names exported by _DX_
is the set of member names in the interface of `T`.

If `S` is empty and `H` is
<code>hide H<sub>1</sub>, .. H<sub>k</sub></code>
then let _M<sub>0</sub>_
be the set of member names in the interface of `T`.
For _j_ in _0 .. k-1_, let _M<sub>j+1</sub>_ be
_M<sub>j</sub> \ members(H<sub>j+1</sub>)_.
The set of member names exported by _DX_ is then _M<sub>k</sub>_.

If `H` is empty and `S` is
<code>show S<sub>1</sub>, .. S<sub>k</sub></code>
then let _M<sub>0</sub>_ be the set of member names in the interface
of `Object`.
For _j_ in _0 .. k-1_, let _M<sub>j+1</sub>_ be
_M<sub>j</sub> &cup; members(S<sub>j+1</sub>)_.
The set of member names exported by _DX_ is then _M<sub>k</sub>_.

If both `H` and `S` are non-empty then let
_M<sub>0</sub>_ be the set of member names exported by 
`export n S`.
For _j_ in _0 .. k-1_, let _M<sub>j+1</sub>_ be
_M<sub>j</sub> \ members(H<sub>j+1</sub>)_.
The set of member names exported by _DX_ is then _M<sub>k</sub>_.

*Note that each member name in the interface of `Object` is included
except if they are explicitly and individually hidden.*

Assume that _DX_ exports a member name _m_.
A compile-time error occurs unless the representation type of _D_
has a member named _m_.

A compile-time error occurs if _D_ contains a declaration named _m_,
or _D_ extends a view _W_, and _W_ has a declaration named _m_.

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
parameterized type of the form `V<T1, .. Tk>` where `V` is the name of
_D_. Assume that the member access invokes or tears off a member
named `m`, where `m` is exported by an export clause of the form
`export n S H` in _D_, where `n` is the representation name of _D_. In
this case, the member access is treated as if the receiver had had the
representation type `T`.

*For example:*

```dart
view V(int it) {
  export n show num, isEven hide hashCode;
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

If _D_ does not include any member export declarations exporting the
representation name `n`, it is treated as if it had declared
`export n show Object;`.

*In short, if a view on a type `T` is like a veil hiding `T` and
showing something else, then the exported members of the
representation are like a hole in the veil: We get to see the
underlying representation type, with exactly the same semantics as an
invocation where the receiver type is the representation type,
including OO dispatch and the treatment of default values of optional
parameters.*

It is a compile time error if _D_ contains a member export declaration
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

Assume that _D_ is a view declaration named `V`, and `V0` occurs as
the `<type>` in a `<viewExtendsElement>` in the extends clause of
`V`. In this case we say that `V0` is a superview of `V`.

A compile-time error occurs if `V0` is a type name or a parameterized type
which occurs as a superview in a view declaration `V`, but `V0` does not
denote a view type.

Assume that a view declaration `V` has representation type `T`, and
that the view type `V0` is a superview of `V` (*note that `V0` may
have some actual type arguments*).  Assume that `S` is the
instantiated representation type corresponding to `V0`. A compile-time
error occurs unless `T` is a subtype of `S`.

*This ensures that it is sound to bind the value of `this` in `V` to `this`
in `V0` when invoking members of `V0`.*

If `V0` is a superview of `V` then `V` is a subtype of `V0`.

Consider a `<viewExtendsElement>` of the form `V0 <viewShowHidePart>`.  The
_associated members_ of said extends element are computed from the instance
members of `V0` in the same way as we compute the included instance members
of the representation type based on a member export declaration.

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

In the body of `V`, a superinvocation syntax similar to an explicit
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

*The quick intuitive perspective on this mechanism is that it is
similar to extension methods, but they are 'sticky' in the sense that
they are associated with a given view type and they do not require the
declaration of the view extension to be imported directly.*

A view extension declaration is derived from
`<viewExtensionDeclaration>`. A compile-time error occurs if a view
extension declaration contains a member export declaration.

Assume that _DX_ is a view extension declaration named `prefix.V`.
A compile-time error occurs unless there is a unique view declaration
named `V` which is imported into the current library with the import
prefix `prefix`.

Assume that _DX_ is a view extension declaration named `V`.
A compile-time error occurs unless there is a unique view declaration
named `V` which is imported into the current library without an import
prefix.

Whether or not `V` is imported with a prefix, let _DV_ be that unique
view declaration.

We say that _DX_ provides an _extension of the view_ declared by _DV_,
and we say that _DX_ _belongs to_ _DV_.

A compile-time error occurs unless _DX_ and _DV_ have exactly the same
type parameters with exactly the same bounds up to consistent
renaming. A compile-time error occurs unless the representation type of
_DX_ is equal to the representation type of _DV_.

Consider a member access _a_ (*e.g., `v.foo()`*), in a library _L_,
where the receiver type is `V<T1, .. Tk>` where `V` denotes _DV_.

Let _VX<sub>1</sub> .. VX<sub>n</sub>_ be the set of view extensions
specifying extensions of _DV_ which are declared in libraries
_L<sub>1</sub> .. L<sub>n</sub>_ (*not necessarily distinct*).

We say that a library _L1_ is _dominated by_ a library _L0_ iff _L1_
is in the transitive closure of imports from _L0_. *In other words,
each library dominates every library to which it has an import path.*

Similarly, a view extension declaration _DX1_ in a library _L1_ is
dominated by a view extension declaration _DX0_ in a library _L0_ iff
_L1_ is dominated by _L0_.

For the given member name (*in the example: `foo`*), let
_VX<sub>1</sub> .. VX<sub>m</sub>_ be the subset of view extension
declarations belonging to _DV_ that declare a member with that name
(*we're just lucky to have chosen a numbering that makes this
possible*) and let _VX<sub>1</sub> .. VX<sub>p</sub>_ be the subset of
_VX<sub>1</sub> .. VX<sub>m</sub>_ which are not dominated by any
other member of _VX<sub>1</sub> .. VX<sub>m</sub>_.

A compile-time error occurs if _p_ is zero or larger than 1.
Otherwise, the member access _a_ is resolved to denote the declaration
with that name in _VX<sub>1</sub>_.

*This means that it is possible to extend the set of members available
for a given view `V` in different ways, depending on the import
graph. For example:*

```dart
// Library 'base.dart'.
view V(int it) {
  bool isThree => it == 3;
}

// Library 'extension1.dart'.
view extension V(int it) {
  void foo() {
    print('Whether I am three: $isThree!');
  }
  void bar() {}
}

// Library 'extension2.dart'.
view Extension V(int it) {
  int get foo => 3;
  set baz(String s) {}
}

// Library 'main1.dart'.
import 'base.dart';
import 'extension1.dart';
import 'extension2.dart';

void main() {
  var v = V(3);
  v.isThree; // OK, available from view.
  v.bar(); // OK, from extension 1.
  v.baz = 'Hello'; // OK, from extension 2.
  v.foo; // Compile-time error, conflict.
}

// Library 'main2.dart'.
import 'base.dart';
import 'extension1.dart';

void main() {
  var v = V(3);
  v.isThree; // OK, from view.
  v.foo(); // OK, from extension 1.
  v.bar(); // OK, from extension 1.
  v.baz; // Compile-time error, no such member.
}
```


## Dynamic Semantics of Views

The dynamic semantics of view member invocation follows from the code
transformation specified in the section about the static analysis.

*In short, with `e` of type
<code>View<S<sub>1</sub>, .. S<sub>k</sub>></code>,
`e.m(args)` is treated as
<code>invokeViewMethod(View, <S<sub>1</sub>, .. S<sub>k</sub>>, e).m(args)</code>.*

The dynamic semantics of an invocation or tear-off of an instance
member of the representation type which is enabled in a view type by a
member export declaration is the same as invoking/tearing-off the same
member on the representation object typed as the representation type.

At run time, for a given instance `o` typed as a view type `V`, there
is _no_ reification of `V` associated with `o`.

*This means that, at run time, an object never "knows" that it is being
viewed as having a view type. By soundness, the run-time type of `o`
will be a subtype of the representation type of `V`.*

The run-time representation of a type argument which is a view type
`V` (respectively
<code>V<T<sub>1</sub>, .. T<sub>k</sub>></code>)
is the corresponding instantiated representation type.

*This means that a view type and the underlying representation type
are considered as being the same type at run time. So we can freely
use a cast to introduce or discard the view type, as the static type
of an instance, or as a type argument in the static type of a data
structure or function involving the view type.*

*This treatment may appear to be unsound. However, it is in fact
sound: Let `V` be a view type with representation type `T`. This
implies that `void Function(V)` is represented as `void Function(T)`
at run-time. In other words, it is possible to have a variable of type
`void Function(V)` that refers to a function object of type `void
Function(T)`. This seems to be a soundness violation because `T <: V`
and not vice versa, statically. However, we consider such types to be
the same type at run time, which is in any case the finest distinction
that we can maintain because there is no representation of `V` at run
time. There is no soundness issue, because the added discipline of a
view type is voluntary.*

A type test, `o is U` or `o is! U`, and a type cast, `o as U`, where `U` is
or contains a view type, is performed at run time as a type test and type
cast on the run-time representation of the view type as described above.


## Discussion

This section mentions a few topics that have given rise to
discussions.


### Non-object types

If we introduce any non-object entities in Dart (that is, entities
that cannot be assigned to a variable of type `Object?`, e.g.,
external C / JavaScript / ... entities, or non-boxed tuples, etc),
then we may wish to allow for view types whose representation type is
a non-object type.

In this case we may be able to consider a view type `V` on a
non-object type `T` to be a supertype of `T`, but unrelated to all
subtypes of `Object?`.


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
