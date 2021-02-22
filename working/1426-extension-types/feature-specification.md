# Extension Types

Author: eernst@google.com

Status: Draft


## Change Log

2021.02.15
  - Initial version, based on
    [language issue 1426](https://github.com/dart-lang/language/issues/1426).


## Summary

This document specifies a language feature that we call "extension types".

The feature introduces extension types, which are a new kind of type
declared by a new extension type declaration. An extension type provides a
replacement or modification of the members available on instances of
existing types: when the static type of the instance is the extension type,
the available members are exactly the ones provided by the extension type.

In contrast, when the static type of an instance is not an extension type,
it is always the run-time type of the instance or a supertype. This means
that the available members are the members of the run-time type of the
instance or a subset thereof. Hence, using a supertype as the static type
allows us to see only a subset of the members, but using an extension type
allows us to _replace_ the set of members.

The functionality is entirely static. Extension types is an enhancement of
the extension methods feature which was added to Dart in version 2.6. In
particular, the semantics of extension method invocation is also the
semantics of invocations of a member of an extension type. By allowing a
developer to work with objects where an extension type is the static type,
the developer gets more fine-grained control over when the extension type
members apply, and the extension type can remove or override the object's
interface methods without extra syntactic overhead. This is only possible
with extension methods if the given member is invoked in an explicit
extension invocation (`Ext(o).foo()` rather than `o.foo()`).


## Motivation

An _extension type_ is a zero-cost abstraction mechanism that allows
developers to replace the set of available operations on a given object
(that is, the instance members of its type) by a different set of
operations (the members declared by the given extension type).

It is zero-cost in the sense that the value denoted by an expression whose
type is an extension type is an object of a different type (known as the
on-type of the extension type), there is no wrapper object.

The point is that the extension type allows for a convenient and safe
treatment of a given object `o` (and objects reachable from `o`) for a
specialized purpose or view. It is in particular aimed at the situation
where that purpose or view requires a certain discipline in the use of
`o`'s instance methods: We may call certain methods, but only in specific
ways, and other methods should not be called at all. This kind of added
discipline can be enforced by accessing `o` typed as an extension type,
rather than typed as its run-time type `R` or some supertype of `R` (which
is what we normally do).

A potential application would be generated extension types handling the
navigation of dynamic object trees. For instance, they could be JSON
values, modeled using `num`, `bool`, `String`, `List<dynamic>`, and
`Map<String, dynamic>`.

Without extension types, the JSON value would most likely be handled with
static type `dynamic`, and all operations on it would be unsafe. If the
JSON value is assumed to satisfy a specific schema, then it would be
possible to reason about this dynamic code and navigate the tree correctly
according to the schema. However, the code where this kind of careful
reasoning is required may be fragmented into many different locations, and
there is no help detecting that some of those locations are treating the
tree incorrectly according to the schema.

If we have extension types, we can declare a set of extension types with
operations that are tailored to work correctly with the given schema and
its subschemas. This is less error-prone and more maintainable than the
approach where the tree is handled with static type `dynamic` everywhere.

Here's an example that shows the core of that scenario. The schema that
we're assuming allows for nested `List<dynamic>` with numbers at the
leaves, and nothing else.

```dart
extension TinyJson on Object {
  Iterable<num> get leaves sync* {
    var self = this;
    if (self is num) {
      yield self;
    } else if (self is List<dynamic>) {
      for (Object element in self) {
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

The only novelty in this example, compared to the existing mechanism
called extension methods, is that the name `TinyJson` can be used as a
type. It is used as the declared type of `tiny` in the `main` function. The
point is that we can now impose an enhanced discipline on the use of
`tiny`, because the extension type only allows invocations of extension
members.

The getter `leaves` is an example of a disciplined use of the given object
structure. The run-time type may be a `List<dynamic>`, but the schema which
is assumed allows only for certain elements in this list (that is, nested
lists or numbers), and in particular it should never be a `String`. The use
of the `add` method on `tiny` would have been allowed if we had used the
type `List<dynamic>` (or `dynamic`) for `tiny`, and that would break the
schema.

When the type of the receiver is the extension type, it is a compile-time
error to invoke any members that are not in the interface of the extension
type (in this case that means: the members declared in the body of
`TinyJson`). So it is an error to call `add` on `tiny`, and that protects
us from violations of the scheme.

In general, the use of an extension type allows us to centralize some
unsafe operations. We can then reason carefully about each operation once
and for all. Clients use the extension type to access objects conforming to
the given schema, and that gives them access to a set of known-safe
operations, making all other operations a compile-time error.

One possible perspective is that an extension type corresponds to an
abstract data type: There is an underlying representation, but we wish to
restrict the access to that representation to a set of operations that are
independent of the operations available on the representation. In other
words, the extension type ensures that we only work with the representation
in specific ways, even though the representation itself has an interface
that allows us to do many other (wrong) things.

It would be straightforward to enforce an added discipline like this by
writing a wrapper class with the allowed operations as members, and
working on a wrapper object rather than accessing `o` and its methods
directly:

```dart
// Attempt to emulate the extension type using a class.

class TinyJson {
  // `representation` is assumed to be a nested list of numbers.
  final Object representation;

  TinyJson(this.representation);

  Iterable<num> get leaves sync* {
    var self = representation;
    if (self is num) {
      yield self;
    } else if (self is List<dynamic>) {
      for (Object element in self) {
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

This is similar to the extension type in that it enforces the use of
specific operations (here we only have one: `leaves`) and in general makes
it an error to use instance methods of the representation (e.g., `add`).

Creation of wrapper objects takes time and space, and in the case where we
wish to work on an entire data structure we'd need to wrap each object as
we navigate the data structure. For instance, we need to create a wrapper
`TinyJson(element)` in order to invoke `leaves` recursively.

In contrast, the extension type mechanism is zero-cost, in the sense that
it does _not_ use a wrapper object, it enforces the desired discipline
statically.

Like extension methods, extension types are static in nature: An extension
type declaration may declare some type parameters (just like the current
extension declarations). The type parameters will be bound to a type which
is determined by the static type of the receiver. Similarly, like extension
methods, members of an extension type are resolved statically, i.e., if
`tiny.leaves` is an invocation of an extension type getter `leaves`, then
the declaration named `leaves` whose body is executed is determined at
compile-time. There is no support for late binding of an extension method,
and hence there is no notion of overriding. In return for this lack of
expressive power, we get improved performance.

Here is another example. It illustrates the fact that an extension type `E`
with on-type `T` introduces a type `E` which is a supertype of `T`. This
makes it possible to assign an expression of type `T` to a variable of type
`E`. This corresponds to "entering" the extension type (accepting the
specific discipline associated with `E`). Conversely, a cast from `E` to
`T` is a downcast, and hence it must be written explicitly. This cast
corresponds to "exiting" the extension type (allowing for violations of the
discipline associated with `E`), and the fact that the cast must be written
explicitly helps developers maintaining the discipline as intended, rather
than dropping out of it by accident, silently.

```dart
extension type ListSize<X> on List<X> {
  int get size => length;
  X front() => this[0];
}

void main() {
  ListSize<String> xs = <String>['Hello']; // OK, upcast.
  print(xs); // OK, `toString()` available on Object?.
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

The rule for `<extensionDeclaration>` in the grammar is replaced by the
following:

```ebnf
<extensionDeclaration> ::=
  'protected'? 'extension' ('type'? <typeIdentifier> <typeParameters>?)?
      <extensionShowHidePart> 'on' <type> <interfaces>? '{'
    (<metadata> <extensionMemberDefinition>)*
  '}'

<extensionShowHidePart> ::=
  <extensionShowClause>? <extensionHideClause>?

<extensionShowClause> ::= 'show' <extensionShowHideList>

<extensionHideClause> ::= 'hide' <extensionShowHideList>

<extensionShowHideList> ::=
  <extensionShowHideElement> (',' <extensionShowHideElement>)*

<extensionShowHideElement> ::=
  <type> | <identifier> | 'operator' <operator>
```

*In the rule `<extensionShowHideElement>`, note that `<type>` derives
`<typeIdentifier>`, which makes `<identifier>` nearly redundant. However,
`<identifier>` is still needed because it includes some strings that cannot
be the name of a type but can be the basename of a member, e.g., the
built-in identifiers.*


## Static Analysis

Assume that _E_ is an extension declaration of the following form:

```dart
extension Ext<X1 extends B1, .. Xk extends Bk> on T {
  ... // Members
}
```

*Note that `extension type` declarations and other enhanced forms are
discussed in later sections. The properties specified here are valid for
those forms as well, except for the differences which are specified
explicitly.*

It is then allowed to use `Ext<S1, .. Sk>` as a type: It can occur as the
declared type of a variable or parameter, as the return type of a function
or getter, as a type argument in a type, or as the on-type of an extension.

*In particular, it is allowed to create a new instance where one or more
extension types occur as type arguments.*

When `k` is zero, `Ext<S1, .. Sk>` simply stands for `Ext`, a non-generic
extension. When `k` is greater than zero, a raw occurrence `Ext` is treated
like a raw type: Instantiation to bound is used to obtain the omitted type
arguments.

We say that the static type of said variable, parameter, etc. _is the
extension type_ `Ext<S1, .. Sk>`, and that its static type _is an extension
type_.

If `e` is an expression whose static type is the extension type
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>></code>,
then a member access like `e.m(args)` is treated as
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>>(v).m(args)</code>
where `v` is a fresh variable whose declared type
is the on-type corresponding to `Ext<S1, .. Sm>`, and similarly for
instance getters and operators. This rule also applies when a member access
implicitly has the receiver `this`, and the static type of `this` is an
extension type (*which can only occur in an extension type member
declaration*).

*That is, when the type of an expression is an extension type, all method
invocations on that expression will invoke an extension method declared by
that extension, and similarly for other member accesses. In particular, we
cannot invoke an instance member when the receiver type is an extension
type (unless the the extension type enables them explicitly, cf. the
show/hide part specified in a later section).*

Let `E` be an extension declaration named `Ext` with type parameters
<code>X<sub>1</sub> extends B<sub>1</sub>, .. X<sub>k</sub> extends B<sub>k</sub></code>
and on-type clause `on T`. Then we say that the _declared on-type_ of `Ext`
is `T`, and the _instantiated on-type_ of
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>></code>
is
<code>[S<sub>1</sub>/X<sub>1</sub>, .. S<sub>k</sub>/X<sub>k</sub>]T</code>.
We will omit 'declared' and 'instantiated' from the phrase when it is clear
from the context whether we are talking about the extension itself or a
particular instantiation of a generic extension. For non-generic
extensions, the on-type is the same in either case.

An extension type `E` of the form
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>></code>
is a subtype of `Object?`, and a proper supertype of the
instantiated on-type of `E`. In the case where the instantiated on-type of
`E` is not a top type, `E` is also a proper subtype of `Object?`.

*That is, the underlying on-type can only be recovered by an explicit cast
(except when the on-type is a top type). So an expression whose type is an
extension type is in a sense "in prison", and we can only obtain a
different type for it by forgetting everything (going to a top type), or by
means of an explicit cast, typically a downcast to the on-type.*

*There is one exception where an extension type has a supertype which is
not a top type: If `Ext1` is an extension type with on-type `Ext2` which is
also an extension type, the former is a supertype of the latter, `Ext2 <:
Ext1`. However the underlying representation is still "in prison" if we
perform an upcast from `Ext2` to `Ext1`, because the implementation of
`Ext1` will treat the underlying object according to the discipline
enforced by `Ext2`, and then add its own layer of extra discipline.*

When `E` is a non-protected extension type, a type test `o is E` and a type
check `o as E` can be performed. Such checks performed on a local variable
can promote the variable to the extension type using the normal rules for
type promotion.

*Protected extension types are introduced in a section below, and they have
a more strict rule for type tests and type casts.*

*Compared to the existing extension methods feature, there is no change to
the type of `this` in the body of an extension type _E_: It is the on-type
of _E_. Similarly, extension methods of _E_ invoked in the body of _E_ are
subject to the same treatment as previously, which means that extension
methods of the enclosing extension type can be invoked implicitly, and
extension methods are given higher priority than instance methods on `this`
when `this` is implicit.*


### Prevent implicit invocations: Keyword 'type'

This section specifies the effect of including the keyword `type` in the
declaration of an extension type.

*A reminder, to set the scene: An implicit extension member invocation is
an invocation of the form `e.m()` (or similar for getter/setter/operator
invocations) which invokes a member of an extension `E`, but where the
static type of `e` is a type `T` that matches the on-type of `E`. This is
the typical usage for the extension methods mechanism that Dart has had
since version 2.6, and it is available with no changes for an extension
declaration that does not include the keyword `type`. The other kinds of
invocations of extension members are explicit extension member invocations
(assuming that `E` is an extension type, an example would be
`E(e).m()`) and typed extension member invocation (like `e.m()` where the
static type of `e` is an extension type).*

Let `E` be an extension declaration such that the keyword `extension` is
followed by `type`. We say that `E` is an _explicit_ extension type
declaration, and that it introduces an _explicit_ extension type.

An explicit extension type is not applicable for an implicit extension
method invocation.

*In other words, methods of an explicit extension type cannot be called on
the on-type, only on the extension type. Otherwise, it works the same as an
extension without the `type` modifier. For example:*

```dart
extension type Age on int {
  Age get next => this + 1;
}

void main() {
  int i = 42;
  i.next; // Error, no such method.
  Age age = 42;
  age.next; // OK.
}
```

*The terminology using the word 'explicit' is motivated by two things: (1)
The extension type "is not implicit", because it doesn't allow for implicit
extension member invocations, hence it "is explicit". (2) The extension
type explicitly says `type`, and the extension type must be the static type
of a receiver in order to invoke any members of the extension type, which
is achieved by explicitly declaring it as a variable type, a return type,
etc.*

Let `E` be an explicit extension type declaration, and consider an
occurrence of an identifier expression `id` in the body of an instance
member of `E`. If a lexical lookup of `id` yields a declaration of a
member of `E`, the expression is treated as `let v = this in v.id`
where the static type of `v` is the enclosing extension type `E`.
A similar rule holds for function invocations of the form `id(args)`, and
for operator invocations of the form `this OP arg` or `OP arg`.

*This means that members of `E` can be invoked implicitly on `this` inside
`E`, just like the members in a non-explicit extension declaration. Another
way to describe this rule is that it makes `E` non-explicit inside the body
of `E`, but only when the receiver is `this`.*

An explicit extension declaration may declare one or more non-redirecting
factory constructors. A factory constructor which is declared in an
extension declaration is also known as an _extension type constructor_.

*The purpose of having an extension type constructor is that it bundles an
approach for building an instance of the on-type of an extension type `E`
with `E` itself, which makes it easy to recognize that this is a way to
obtain a value of type `E`. It can also be used to verify that an existing
object (provided as an actual argument to the constructor) satisfies the
requirements for having the type `E`. Protected extension types, described
below, provide support for enforcing this kind of verification.*

An instance creation expression of the form
<code>E<T<sub>1</sub>, .. T<sub>k</sub>>(...)</code>
or
<code>E<T<sub>1</sub>, .. T<sub>k</sub>>.name(...)</code>
is used to invoke these constructors, and the type of such an expression is
<code>E<T<sub>1</sub>, .. T<sub>k</sub>></code>.

During static analysis of the body of an extension type constructor, the
return type is considered to be the on-type of the enclosing extension type
declaration.

It is a compile-time error if it is possible to reach the end of an
extension type constructor without returning anything. *Even in the case
where the on-type is nullable and the intended representation is the null
object, an explicit `return null;` is required.*

Let `E` be an explicit extension type declaration. It is not an error to
declare a member in `E` which is also a member of `Object?`.

*This differs from a non-explicit extension type declaration (which
includes all existing declarations of extension methods), where such a
member is a compile-time error. The rationale is that an extension method
like `toString()` on an extension type `E` can be invoked on a receiver
whose static type is `E`. It should be noted that the extension method
named `toString` will only be invoked when the static receiver type is `E`,
and, e.g., `(o as Object?).toString()` will invoke the implementation of
`toString()` in the run-time class of `o`.*

*The members of `Object?` are part of the interface of every extension
type, and this means that it is a compile-time error if said member
declaration is not a correct override of the declaration in `Object?`. For
instance, `bool toString(int arg) => true;` is an error.*

*It may not be obvious why we would want to prevent implicit invocations of
the members of any given extension type. Here is a rationale:*

*Consider the type `int`. This type is likely to be used as the on-type of
many different extension types, because it allows a very lightweight object
to play the role as a value with a specific interpretation (say, an `Age`
in years or a `Width` in pixels). Different extension types are not
assignable to each other, so we'll offer a certain protection against
inconsistent interpretations.*

*However, if we have many different extension types with the same or
overlapping on-types, then it may be impractical to work with: Lots of
extension methods are applicable to any given expression of that on-type,
and they are not intended to be used at all, each of them should only be
used when the associated interpretation is valid, that is, when the static
type of the receiver is the extension type that declares said member.*

*Hence, we want to support the notion of an extension type whose methods
are never invoked implicitly. An explicit extension type will do this.*


### Allow instance member access using `show` and `hide`

This section specifies the effect of including a non-empty
`<extensionShowHidePart>` in an extension declaration.

*The show/hide part provides access to a subset of the members of the
interface of the on-type. For instance, there may be some read-only methods
that we can safely call on the on-type, because they won't violate any
invariants associated with the extension type. We could write forwarding
members in the extension body, but using show/hide can have the same
effect, and it is much more concise and convenient.*

We use the phrase _extension show/hide part_, or just _show/hide part_ when
no doubt can arise, to denote a phrase derived from
`<extensionShowHidePart>`. Similarly, an `<extensionShowClause>` is known
as an _extension show clause_, and an `<extensionHideClause>` is known as
an _extension hide clause_, similarly abbreviated to _show clause_ and
_hide clause_.

The show/hide part specifies which instance members of the on-type are
available for invocation on a receiver whose type is the given extension
type.

If the show/hide part is empty, no instance members except the ones
declared for `Object?` can be invoked on a receiver whose static type is
the given extension type.

If the show/hide part is a show clause listing some identifiers and types,
invocation of an instance member is allowed if its basename is one of the
given identifiers, or it is the name of a member of the interface of one of
the types. Instance members declared for `Object?` can also be invoked.

If the show/hide part is a hide clause listing some identifiers and types,
invocation of an instance member is allowed if it is in the interface of
the on-type and _not_ among the given identifiers, nor in the interface of
the specified types.

If the show/hide part is a show clause followed by a hide clause, then the
available instance members is computed by first computing the set of
included instance members specified by the show clause as described above,
and then removing instance members from that set according to the hide
clause, as described above.

In a show or hide clause, it is possible that an
`<extensionShowHideElement>` is an identifier that is the basename of a
member of the interface of the on-type, and it is also the name of a type
in scope. In this case, the name shall refer to the member.

*A conflict is unlikely because type names in general are capitalized, and
member names start with a lower-case letter. Some type names start with a
lower-case letter, too (e.g., `int` and `dynamic`), but those names do not
occur frequently as member names. Should a conflict arise anyway, a
work-around is to import the shadowed type `T` with a prefix `p` and put
`p.T` in the show or hide clause.*

A compile-time error occurs if a hide or show clause contains an identifier
which is not the basename of an instance member of the on-type. A
compile-time error occurs if a hide or show clause contains a type which is
not among the types that are implemented by the on-type of the extension.

A compile-time error occurs if a member included by the show/hide part has
a basename which is also the basename of a member declaration in the
extension type.

*For instance, if an extension `E` contains a declaration of a method named
`toString`, the hide clause must include `toString` (or a class type,
because they all include `toString`). Otherwise, the member declaration
named `toString` would be an error.*

Let `E` be an extension type with a show/hide part such that a member `m`
is included in the interface of `E`. The member signature of `m` is the
member signature of `m` in the on-type of `E`.

A type in a hide or show clause may be raw (*that is, an identifier or
qualified identifier denoting a generic type, but no actual type
arguments*). In this case the omitted type arguments are determined by the
corresponding superinterface of the on-type.

*For example:*

```dart
extension type MyInt on int show num, isEven hide floor {
  int get twice => 2 * this;
}

void main() {
  MyInt m = 42;
  m.twice; // OK, in the extension type.
  m.isEven; // OK, a shown instance member.
  m.ceil(); // OK, a shown instance member.
  m.toString(); // OK, an `Object?` member.
  m.floor(); // Error, hidden.
}
```


### Implementing superinterfaces

This section specifies the effect of having an `<interfaces>` part in an
extension declaration.

Let `E` be an extension declaration where `<interfaces>?` is of the form
`implements T1, .. Tm`. We say that `E` has `T1` .. `Tm` as its direct
superinterfaces.

A compile-time error occurs if a direct superinterface does not denote a
class, or if it denotes a class which cannot be a superinterface of a
class.

*For instance, `implements int` is an error.*

If the `<interfaces>?` part of `E` is empty, it is treated as
`implements Object`.

For each member `m` named `n` in each direct superinterface of `E`, an
error occurs unless `E` declares a member `m1` named `n` which is a correct
override of `m`, or the show/hide part of `E` enables an instance member of
the on-type which is a correct override of `m`.

No subtype relationship exists between `E` and `T1, .. Tm`.

*This means that when an extension type implements a set of interfaces, it
is enforced that all the specified members are available, and that they
have a signature which is compatible with the ones in `T1, .. Tm`, but
there is no assignability from an expression of type `E` to a variable
whose declared type is `Tj` for some `j` in 1..m. For that, it is necessary
to use `box`, as described below.*


### Gaining control over the instances: Protected extension types

This section specifies the effect of including the keyword `protected` as
the first token in an extension declaration.

*The core idea is that no object can have a protected extension type as its
static type unless it has been returned by an extension type constructor.
This allows developers to gain control over which instances get to have
that type.*

Let `D` be an explicit extension type declaration named `E` which is
prefixed by `protected`. We say that it is a _protected extension type
declaration_, and that it introduces a _protected extension type_.

Let `E` be the name of a protected extension type declaration.
The type `E` (or
<code>E<T<sub>1</sub>, .. T<sub>k</sub>></code>
if `E` is generic) is a proper subtype of `Object?` and a proper supertype
of `Never`.

*In contrast to non-protected extension types, the extension type has no
subtype relationship with its on-type.*

It is a compile-time error if a protected extension type `E` is the
target type in a type test (`o is E` respectively
<code>o is E<T<sub>1</sub>, .. T<sub>k</sub>></code>)
or a type cast (`o as E` respectively
<code>o as E<T<sub>1</sub>, .. T<sub>k</sub>></code>).
The type `dynamic` is not assignable to any protected extension type.

*The subtype relationships and the type test/cast errors ensure that an
instance creation expression is the only way to create values of a
protected extension type `E`: There is no assignability from the on-type to
`E`, and it is an error to cast or promote an expression to `E`.*

*This is a crucial property, because it ensures that the value of an
expression with static type `E` has been obtained as the return value of an
extension type constructor, and that allows us to write arbitrary code that
ensures that an object typed as `E` satisfies certain constraints. For
instance, if all constructors of `E` ensure that a given invariant holds,
and if every member of `E` preserves that invariant, and if there are no
aliases to the underlying instance of the on-type of `E` typed as any other
type than `E`, then the invariant is guaranteed to be preserved.*

It is a compile-time error for an extension declaration to start with the
keyword `protected`, unless it is explicit (*that is, unless it also has
the keyword `type`*).

*A protected extension type should not allow for implicit extension method
invocations, because they are inherently not guarded by the execution of an
extension type constructor.*

*For example:*

```dart
protected extension type nat on int {
  factory nat(int value) =>
      value >= 0 ? value : throw "Attempt to create an invalid nat";
}

void main() {
  nat n1 = 42; // Error.
  var n2 = nat(42); // OK at compile time, and at run time.
  var n3 = nat(-1); // OK at compile time, throws at run time.
}
```

*The following example illustrates the subtyping relationships; it
illustrates the use of a constructor to enforce an invariant (that the
`int` in the `IntBox` is even); and it illustrates that the available
methods (there is just one: `next()`) all preserve that invariant.*

```dart
class IntBox {
  int i;
  IntBox(this.i);
}

protected extension type EvenIntBox on IntBox {
  factory EvenIntBox(int i) =>
      i.isEven ? IntBox(i) : throw "Invalid EvenIntBox";
  factory EvenIntBox.fromIntBox(IntBox intBox) =>
      intBox.i.isEven ? intBox : throw "Invalid EvenIntBox";
  void next() => this.i += 2;
}

void main() {
  var evenIntBox = EvenIntBox(42);
  evenIntBox.next(); // Methods of `EvenIntBox` maintain the invariant.
  evenIntBox = intBox; // Compile-time error, types not assignable.
  evenIntBox = intBox as EvenIntBox; // Compile-time error, can't cast.

  // We cannot escape by a cast when the protected extension type is
  // a type argument (or a return/parameter type in a function type).
  var evenIntBoxes = [evenIntBox]; // Type `List<EvenIntBox>`.
  evenIntBoxes[0].next(); // Elements typed as `EvenIntBox`.
  List<IntBox> intBoxes = evenIntBoxes; // Compile-time error.
  intBoxes = evenIntBoxes as dynamic; // Run-time error.

  // We _can_ escape the protected extension type by an explicit cast.
  var intBox = evenIntBox as IntBox; // OK statically and dynamically.
  intBox.i++; // Invariant of `evenIntBox` violated!
}
```

*Note that an explicit cast can be used to escape the protected extension
type and obtain a reference to the underlying object under some other type,
e.g., the on-type. This means that we can break the invariant, because the
object is no longer handled with the discipline that the extension type
members apply.*

*Hence, the protection offered by a protected extension type is easy to
violate, but the point is that it is reasonably easy to avoid violating
this protection, and hence the mechanism can be used by developers who wish
to maintain that specific discipline.*

*A harder protection can be achieved by boxing the extension type, as
described in the next section.*


### Boxing

This section describes the implicitly induced `box` getter of an explicit
extension type.

*It may be helpful to equip each explicit extension type with a companion
class whose instances have a single field holding an instance of the
on-type. So it's a wrapper with the same interface as the extension type.*

Let `E` be an explicit extension type. The declaration of `E` implicitly
induces a declaration of a class `E.class`, with the same type parameters
and members as `E`. It is a subclass of `Object`, with the same direct
superinterfaces as `E`, with a final field whose type is the on-type of
`E`, and with an unnamed single argument constructor setting that field to
the argument. A getter `E.class get box` is implicitly induced in `E`, and
it returns an object that wraps `this`.

`E.class` also implicitly induces a getter `E get unbox` which returns the
value of the final field mentioned above, typed as the associated extension
type.

*In the case where the extension type is protected, the `unbox` getter
cannot be written in Dart (because a cast to `E` is then a compile-time
error), so `unbox` must be a language feature in this case. For
convenience, it is induced implicitly for all extension types.*

In the case where it would be a compile-time error to declare such a member
named `box` or `unbox`, said member is not induced.

*The latter rule helps avoiding conflicts in situations where `box` or
`unbox` is a non-hidden instance member, and it allows developers to write
their own implementations if needed.*

*The rationale for having this mechanism is that the wrapper object is a
full-fledged object: It is a subtype of all the direct superinterfaces of
`E`, so it can be used in code where `E` is not in scope. Moreover, it
supports late binding of the extension methods, and even dynamic
invocations. It is costly (it takes space and time to allocate and
initialize the wrapper object), but it is more robust than the extension
type, which will only work in a manner which is resolved statically.*


## Dynamic Semantics

The dynamic semantics of extension method invocation is very similar to
the semantics of invocations of the existing extension methods:

If `e` is an expression whose static type is the extension type
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>></code>,
then a member access like `e.m(args)` is executed by evaluating `e` to an
object which is bound to a fresh variable `v`, and then evaluating
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>>(v).m(args)</code>,
and similarly for instance getters and operators.

The dynamic semantics of an invocation of an instance method of the on-type
which is enabled in an explicit extension type by the show/hide part is as
if a forwarder were implicitly induced in the extension, with the same
signature as that of the on-type. *For example:*

```dart
// Extension type using show/hide:
extension type MyNum on num show floor {}

// Works like the following:
extension type MyNum on num {
  int floor() => this.floor();
}
```

*Note that this implies that the extension method `floor` never overrides
the instance member `floor`, but the extension method `floor` will be
executed at a call site `myNum.floor()` based on a compile-time decision
when the receiver `myNum` has static type `MyNum`. In particular, the
extension method `floor` will never be executed when the receiver has type
`dynamic`. The forwarding expression `this.floor()` in the implicitly
induced getter will invoke the instance method, which is subject to late
binding (so we may end up running `int.floor()` or `double.floor()`,
depending on the dynamic type of `this`).*

At run time, for a given instance `o` typed as an extension type `E`, there
is _no_ reification of `E` associated with `o`.

*This means that, at run time, an object never "knows" that it is being
viewed as having an extension type. By soundness, the run-time type of `o`
will be a subtype of the on-type of `E`.*

The run-time representation of a type argument which is a non-protected
extension type `E` (respectively 
<code>E<T<sub>1</sub>, .. T<sub>k</sub>></code>) 
is the corresponding instantiated on-type.

*This means that a non-protected extension type and the underlying on-type
are considered as being the same type at run time. So we can freely use a
cast to introduce or discard the extension type, as the static type of an
instance, or as a type argument in the static type of a data structure or
function involving the extension type.*

The run-time representation of a type argument which is a protected
extension type `E` (respectively 
<code>E<T<sub>1</sub>, .. T<sub>k</sub>></code>) 
is an identification of `E` (respectively 
<code>E<T<sub>1</sub>, .. T<sub>k</sub>></code>).

*In particular, it is not the same as the run-time representation of the
corresponding on-type. This is necessary in order to maintain that the
on-type and the protected extension type are unrelated.*

*For a protected extension type `E`, with a data structure or function where
`E` occurs as a subterm in the type (that is, as a type argument, a return
type, or a parameter type), a cast that tries to introduce or discard the
protected extension type will fail at run time.*

*In the non-protected case this treatment may appear to be
unsound. However, it is in fact sound: Let `E` be a non-protected
extension type with on-type `T`. This implies that `void Function(E)` is
represented as `void Function(T)` at run-time. In other words, it is
possible to have a variable of type `void Function(T)` that refers to a
function object of type `void Function(E)`. This seems to be a soundness
violation because `T <: E` and not vice versa, statically. However, we
consider such types to be the same type at run time, which is in any case
the finest distinction that we can maintain because there is no
representation of `E` at run time. There is no soundness issue, because
the added discipline of a non-protected extension type is voluntary.*

A type test, `o is U`, and a type cast, `o as U`, where `U` is or contains
an extension type, is performed at run time as a type test and type cast on
the run-time representation of the extension type as described above.

*Note that `U` cannot be a protected extension type, because the expression
would then be a compile-time error, but it could contain a protected
extension type, e.g., `myList is List<nat>`.*


## Discussion


### Casting to a protected extension type

We could use the following mechanism to enable casts to a protected
extension type to succeed at run time:

Assume that `E` is a protected extension type that declares a `bool get
verifyThis` getter.

If such a getter exists, then the execution of a type cast `c` of the form
`o as E` proceeds as follows: First, a cast `o as T` is executed, where `T`
is the instantiated on-type corresponding to `E`. If this cast succeeds
then `o.verifyThis` is evaluated to an object `o1`. If `o1` is the true
object then `c` completes normally and yields `o`; otherwise `c` encounters
a dynamic type error.

A cast of the form `o as X` where `X` is a type variable bound to `E`
proceeds in the same way.

This mechanism could be an optional extension of the currently specified
rule (where any type cast to `E` is an error, statically or dynamically):
If `E` does not declare a getter `bool get verifyThis` then every cast to
`E` will fail at run time.


### Non-object entities

If we introduce any non-object entities in Dart (that is, entities that
cannot be assigned to a variable of type `Object?`, e.g., external C /
JavaScript / ... entities, or non-boxed tuples, etc), then we may wish to
allow for extension types whose on-type is a non-object type.

This should not cause any particular problems: If the on-type is a
non-object type, then the extension type will not be a subtype of `Object`.


### Defining void

We may be able to use extension types to define `void`:

```dart
extension type void on Object? hide Object? {}
```

This approach does not admit any member accesses for a receiver of type
`void`.

It shouldn't be assignable to anything other type than `dynamic` without a
cast, and that is not a property which is achieved with this proposal. It
is actually assignable to any top type.

However, if we can restrict the assignability as desired then, compared to
the treatment of today, we would get support for voidness preservation.
That is, it would no longer be possible to forget voidness without a cast
in a number of higher order situations:

```dart
List<Object?> objects = <void>[]; // Error.

void f(Object? o) { print(o); }
Object? Function(void) g = f; // Error, for both types in the signature.
```
