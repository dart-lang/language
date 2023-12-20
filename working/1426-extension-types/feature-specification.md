# Extension Types

Author: eernst@google.com

Status: Obsolete

**This proposal is now obsolete. The mechanism has been renamed multiple times, and the
current name is again _extension types_. Please see the new 
[extension types specification][] for the accepted specification proposal.**

[extension types specification]: https://github.com/dart-lang/language/blob/main/accepted/future-releases/extension-types/feature-specification.md


## Change Log

2021.04.09
  - Initial version, based on
    [language issue 1426](https://github.com/dart-lang/language/issues/1426).


## Summary

This document specifies a language feature that we call "extension types".

The feature introduces extension types, which are a new kind of type
declared by a new extension type declaration. An extension type provides a
replacement or modification of the members available on instances of
existing types: when the static type of the instance is an extension type $E$,
the available members are exactly the ones provided by $E$
(plus the accessible and applicable extension methods declared
by other extensions, if any).

In contrast, when the static type of an instance is not an extension type,
it is always the run-time type of the instance or a supertype. This means
that the available members are the members of the run-time type of the
instance or a subset thereof (again: plus extension methods, if
any). Hence, using a supertype as the static type allows us to see only a
subset of the members, but using an extension type allows us to _replace_
the set of members.

The functionality is entirely static. Extension types is an enhancement of
the extension methods feature which was added to Dart in version 2.7. In
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
extension declarations). The type parameters will be bound to types which
are determined by the static type of the receiver. Similarly, like extension
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

The rule for `<extensionDeclaration>` in the grammar is replaced by the
following:

```ebnf
<extensionDeclaration> ::=
  'extension' 
      (<typeIdentifier>? | 'type' <typeIdentifier>) <typeParameters>?
      <extensionExtendsPart>?
      'on' <type>
      <extensionShowHidePart>
      <interfaces>?
  '{'
    (<metadata> <extensionMemberDefinition>)*
  '}'

<extensionExtendsPart> ::=
  'extends' <extensionExtendsList>

<extensionExtendsList> ::=
  <extensionExtendsElement> (',' <extensionExtendsList>)?

<extensionExtendsElement> ::=
  <type> <extensionShowHidePart>

<extensionShowHidePart> ::=
  <extensionShowClause>? <extensionHideClause>?

<extensionShowClause> ::= 'show' <extensionShowHideList>

<extensionHideClause> ::= 'hide' <extensionShowHideList>

<extensionShowHideList> ::=
  <extensionShowHideElement> (',' <extensionShowHideElement>)*

<extensionShowHideElement> ::=
  <type> |
  <identifier> |
  'operator' <operator> |
  ('get'|'set') <identifier>
```

*In the rule `<extensionShowHideElement>`, note that `<type>` derives
`<typeIdentifier>`, which makes `<identifier>` nearly redundant. However,
`<identifier>` is still needed because it includes some strings that cannot
be the name of a type but can be the basename of a member, e.g., the
built-in identifiers.*


## Static Analysis

This document needs to refer to explicit extension method invocations. With
the existing extension method declarations, `E<T1, .. Tk>(o).m()` denotes
an explicit invocation of the extension member named `m` declared by `E`,
with `o` bound to `this` and the type parameters bound to `T1, .. Tk`.

This document uses `invokeExtensionMethod(E<T1, .. Tk>, o).m()` to denote
the same extension method invocation. Note that `invokeExtensionMethod` is
used as a specification device, it cannot occur in Dart source code.

*This is needed because `E<T1, .. Tk>(o)` can be an extension type
constructor invocation, which makes `E<T1, .. Tk>(o).m()` ambiguous when
specifying extensions that may or may not have a constructor. The use of
`invokeExtensionMethod` makes it explicit and unambiguous that we are
talking about an extension method invocation.*

The static analysis of `invokeExtensionMethod` is that it takes exactly two
positional arguments and must be the receiver in a member access. The first
argument must be a `<type>`, denoting an extension type _T_, and the second
argument must be an expression whose static type is _T_ or the
corresponding instantiated on-type. The member access must be a member of
`E`. If the member access is a method invocation (including an invocation
of an operator that takes at least one argument), it is allowed to pass an
actual argument list, and the static analysis of the actual arguments
proceeds as with other function calls, using a signature where the formal
type parameters of `E` are replaced by `T1, .. Tk`. The type of the entire
member access is the return type of said member if it is a member
invocation, and the function type of the method if it is an extension
member tear-off, again substituting `T1, .. Tk` for the formal type
parameters.

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

It is then allowed to use `Ext<S1, .. Sk>` as a type.

*For example, it can occur as the declared type of a variable or parameter,
as the return type of a function or getter, as a type argument in a type,
as the on-type of an extension, as the type in the `onPart` of a
try/catch statement, or in a type test `o is E` or a type cast `o as E`, or
as the body of a type alias. It is also allowed to create a new instance
where one or more extension types occur as type arguments.*

A compile-time error occurs if the type `Ext<S1, .. Sk>` is not
regular-bounded.

*In other words, such types can not be super-bounded. The reason for this
restriction is that it is unsound to execute code in the body of `Ext` in
the case where the values of the type variables do not satisfy their
declared bounds, and those values will be obtained directly from the static
type of the receiver in each member invocation on `Ext`.*

When `k` is zero, `Ext<S1, .. Sk>` simply stands for `Ext`, a non-generic
extension. When `k` is greater than zero, a raw occurrence `Ext` is treated
like a raw type: Instantiation to bound is used to obtain the omitted type
arguments. *Note that this may yield a super-bounded type, which is then a
compile-time error.*

We say that the static type of said variable, parameter, etc. _is the
extension type_ `Ext<S1, .. Sk>`, and that its static type _is an extension
type_.

A compile-time error occurs if an extension type is used as a
superinterface of a class or mixin, or if an extension type is used to
derive a mixin.

*So `class C extends E1 with E2 implements E3 {}` has three errors if `E1`,
`E2`, and `E3` are extension types, and `mixin M on E1 implements E2 {}`
has two errors.*

If `e` is an expression whose static type is the extension type
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>></code>
and the basename of `m` is the basename of a member declared by `Ext`,
then a member access like `e.m(args)` is treated as
<code>invokeExtensionMethod(Ext<S<sub>1</sub>, .. S<sub>k</sub>>, e).m(args)</code>,
and similarly for instance getters and operators.

Lexical lookup for identifier references and unqualified function
invocations in the body of an extension declaration work the same as today:
In the body of an extension declaration `Ext` with type parameters
<code>X<sub>1</sub>, .. X<sub>k</sub></code>, for an invocation like
`m(args)`, if a declaration named `m` is found in the body of `Ext` 
then that invocation is treated as
<code>invokeExtensionMethod(Ext<X<sub>1</sub>, .. X<sub>k</sub>>, this).m(args)</code>.
If there is no declaration in scope whose basename is the basename of `m`,
`m(args)` is treated as `this.m(args)`.

*For example:*

```dart
extension Ext1 on int {
  void foo() { print('Ext1.foo'); }
  void baz() { print('Ext1.baz'); }
  void qux() { print('Ext1.qux'); }
}

void qux() { print('qux'); }

extension Ext2 on Ext1 {
  void foo() { print('Ext2.foo); }
  void bar() { 
    foo(); // Prints 'Ext2.foo'.
    this.foo(); // Prints 'Ext1.foo'.
    1.foo(); // Prints 'Ext1.foo'.
    baz(); // Prints 'Ext1.baz'.
    qux(); // Prints 'qux'.
  }
}
```

*That is, when the type of an expression is an extension type `E` with
on-type `T`, all method invocations on that expression will invoke an
instance method declared by `E`, and similarly for other member accesses
(or it is an extension method invocation on some other extension `E1` with
on-type `T1` such that `T` matches `T1`). In particular, we cannot invoke
an instance member of the on-type when the receiver type is an extension
type (unless the extension type enables them explicitly, cf. the show/hide
part specified in a later section).*

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

Let `E` be an extension type of the form
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>></code>,
and let `T` be the corresponding instantiated on-type.
When `T` is a top type, `E` is also a top type.
Otherwise, `E` is a proper subtype of `Object?`, and a proper supertype of
`T`.

*That is, the underlying on-type can only be recovered by an explicit cast
(except when the on-type is a top type). So an expression whose type is an
extension type is in a sense "in prison", and we can only obtain a
different type for it by forgetting everything (going to a top type), or by
means of an explicit cast, typically a downcast to the on-type.*

When `E` is an extension type, a type test `o is E` or `o is! E` and a type
check `o as E` can be performed. Such checks performed on a local variable
can promote the variable to the extension type using the normal rules for
type promotion.

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
We say that an extension type declaration or extension type is _implicit_
in the case where it is not explicit.

*In particular, every extension declaration in current Dart code is
implicit, and if it has a name then it introduces an implicit extension
type.*

An explicit extension type declaration is not applicable for an implicit
extension method invocation.

*In other words, methods of an explicit extension type `E` cannot be called
on the on-type, only on the extension type (except in the body of `E` where
the members of `E` are in scope). Otherwise, it works the same as an
extension without the `type` modifier. For example:*

```dart
extension type Age on int {
  Age get next => this + 1;
}

void main() {
  int i = 42;
  i.next; // Compile-time error, no such member.
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
member of `E`, the expression is treated as `let v = this as E in v.id`.
A similar rule holds for function invocations of the form `id(args)`.

*This means that members of `E` can be invoked implicitly on `this` inside
`E`, just like the members in an implicit extension declaration.*

An explicit extension declaration may declare one or more non-redirecting
factory constructors. A factory constructor which is declared in an
extension declaration is also known as an _extension type constructor_.

*The purpose of having an extension type constructor is that it bundles an
approach for building an instance of the on-type of an extension type `E`
with `E` itself, which makes it easy to recognize that this is a way to
obtain a value of type `E`. It can also be used to verify that an existing
object (provided as an actual argument to the constructor) satisfies the
requirements for having the type `E`.*

An instance creation expression of the form
<code>E<T<sub>1</sub>, .. T<sub>k</sub>>(...)</code>
or
<code>E<T<sub>1</sub>, .. T<sub>k</sub>>.name(...)</code>
is used to invoke these constructors, and the type of such an expression is
<code>E<T<sub>1</sub>, .. T<sub>k</sub>></code>.

During static analysis of the body of an extension type constructor, the
return type is considered to be the extension type declared by the
enclosing declaration.

*This means that the constructor can return an expression whose static type
is the on-type, as well as an expression whose static type is the extension
type.*

It is a compile-time error if it is possible to reach the end of an
extension type constructor without returning anything. *Even in the case
where the on-type is nullable and the intended representation is the null
object, an explicit `return null;` is required.*

Let `E` be an explicit extension type declaration. It is an error to
declare a member in `E` which is also a member of `Object`.

*This is because the members of `Object` are by default shown, as
specified below in the section about the show/hide part. It is possible to
use `hide` to omit some or all of these members, in which case it is
possible to declare members in `E` with those names.*

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
interface of the on-type. For instance, if the intended purpose of the
extension type is to maintain a certain set of invariants about the state
of the on-type instance, it is no problem to let clients invoke any methods
that do not change the state. We could write forwarding members in the
extension body to enable those methods, but using show/hide can have the
same effect, and it is much more concise and convenient.*

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
declared for `Object` can be invoked on a receiver whose static type is
the given extension type.

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

An `<extensionShowHideElement>` can be of the form `get <id>` or `set <id>`
or `operator <operator>` where `<operator>` must be an operator which can
be declared as an instance member of a class. These forms are used to
specify a getter (without the setter), a setter (without the getter), or an
operator.

*If the interface contains a getter `x` and a setter `x=` then `show x`
will enable both, but `show get x` or `show set x` can be used to enable
only one of them, and similarly for `hide`.*

In a show or hide clause, it is possible that an
`<extensionShowHideElement>` is an identifier that is the basename of a
member of the interface of the on-type, and it is also the name of a type
in scope. In this case, the name shall refer to the member.

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
implemented by the on-type of the extension.

A compile-time error occurs if a member included by the show/hide part has
a name which is also the name of a member declaration in the extension
type.

*For instance, if an extension `E` with a hide clause contains a
declaration of a method named `toString`, the hide clause must include
`toString` (or a class type, because they all include
`toString`). Otherwise, the member declaration named `toString` would be an
error.*

Let `E` be an extension type with a show/hide part such that a member `m`
is included in the interface of `E`. The member signature of `m` is the
member signature of `m` in the on-type of `E`.

A type in a hide or show clause may be raw (*that is, an identifier or
qualified identifier denoting a generic type, but no actual type
arguments*). In this case the omitted type arguments are determined by the
corresponding superinterface of the on-type.

*Here is an example using a show/hide part:*

```dart
extension type MyInt on int show num, isEven hide floor {
  int get twice => 2 * this;
}

void main() {
  MyInt m = 42;
  m.twice; // OK, in the extension type.
  m.isEven; // OK, a shown instance member.
  m.ceil(); // OK, a shown instance member.
  m.toString(); // OK, an `Object` member.
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

For each member `m` named `n` in each direct superinterface of `E`, an
error occurs unless `E` declares a member `m1` named `n` which is a correct
override of `m`, or the show/hide part of `E` enables an instance member of
the on-type which is a correct override of `m`.

No subtype relationship exists between `E` and `T1, .. Tm`.

*This means that when an extension type implements a set of interfaces, it
is enforced that all the specified members are available, and that they
have a signature which is compatible with the ones in `T1, .. Tm`. But
there is no assignability from an expression of type `E` to a variable
whose declared type is `Tj` for some `j` in 1..m. For that, it is necessary
to use `box`, as described below.*

If the `<interfaces>?` part of `E` is empty, the errors specified in this
section can not occur. *In particular, even `toString` and other members of
`Object` can be declared with signatures that are not correct overrides of
the correspsonding member signature in `Object`. Note, however, that a
different error occurs for a declaration named, say, `toString`, unless
there is a clause like `hide toString` in the show/hide part (because of
the name clash).*


### Boxing

This section describes the implicitly induced `box` getter of an explicit
extension type.

*It may be helpful to equip each explicit extension type with a companion
class whose instances have a single field holding an instance of the
on-type. So it's a wrapper with the same interface as the extension type.*

Let `E` be an explicit extension type. The declaration of `E` implicitly
induces a declaration of a class `E.class`, with the same type parameters
and members as `E`. It is a subclass of `Object`, with the same direct
superinterfaces as `E`, with a final private field whose type is the
on-type of `E`, and with an unnamed single argument constructor setting
that field to the argument. A getter `E.class get box` is implicitly
induced in `E`, and it returns an object that wraps `this`.

`E.class` also implicitly induces a getter `E get unbox` which returns the
value of the final field mentioned above, typed as the associated extension
type.

In the case where it would be a compile-time error to declare such a member
named `box` or `unbox`, said member is not induced.

*The latter rule helps avoiding conflicts in situations where `box` or
`unbox` is a non-hidden instance member, and it allows developers to write
their own implementations if needed.*

A compile-time error occurs at any reference to `E.class` or to the `box`
member if the class `E.class` has any compile-time errors.

*For example, with an extension type `E` it is allowed to `hide toString`
and declare a `String toString(int radix)` (which is not a correct override
of `Object.toString`), but it is then an error to invoke `box`, and it is
an error to have any occurrence of `E.class`.*

*The rationale for having this mechanism is that the wrapper object is a
full-fledged object: It is a subtype of all the direct superinterfaces of
`E`, so it can be used in code where `E` is not in scope. Moreover, it
supports late binding of the extension methods, and even dynamic
invocations. It is costly (it takes space and time to allocate and
initialize the wrapper object), but it is more robust than the extension
type, which will only work in a manner which is resolved statically.*


### Composing extension types

This section describes the effect of including a clause derived from
`<extensionExtendsPart>` in an extension declaration. We use the phrase
_the extension extends clause_ to refer to this clause, or just _the
extends clause_ when no ambiguity can arise.

*The rationale is that the set of members and member implementations of a
given extension type may need to overlap with that of other extension
types. The extends clause allows for implementation reuse by putting shared
members in a "super-extension" `E0` and putting `E0` in the extends clause
of several extension type declarations `E1 .. Ek`, thus "inheriting" the
members of `E0` into all of `E1 .. Ek` without code duplication.*

*Note that there is no subtype relationship between `E0` and `Ej` in this
scenario, only code reuse. This also implies that there is no need to
require anything that resembles a correct override relationship

Assume that `E` is an extension declaration, and `E0` occurs as the `<type>`
in an `<extensionExtendsElement>` in the extends clause of `E`. In this
case we say that `E0` is a superextension of `E`.

A compile-time error occurs if `E0` is a type name or a
parameterized type which occurs as a superextension in an extension
declaration `E`, but `E0` does not denote an extension type.

*`E0` can be any kind of extension type. For instance, it can be useful for
an extension type `E` with on-type `T` to extend an extension type `E0`
even in the case where `E0` is an implicit extension type. In that case the
members of `E0` can be invoked on `this` inside `E` anyway, and on any
expression whose static type is `T` outside `E`, but when a receiver has
type `E` then the members of `E0` are not applicable, unless the on-type of
`E0` is a top type. But `E` can enable the `E0` members on such receivers
by extending `E0`.*

Assume that an extension declaration `E` has on-type `T`, and that the
extension type `E0` is a superextension of `E` (*note that `E0` may have
some actual type arguments*).  Assume that `S` is the instantiated on-type
corresponding to `E0`. A compile-time error occurs unless `T` is a subtype
of `S`.

*This ensures that it is sound to bind the value of `this` in `E` to `this`
in `E0` when invoking members of `E0`.*

Consider an `<extensionExtendsElement>` of the form `E0
<extensionShowHidePart>`.  The _associated members_ of said extends element
are computed from the instance members of `E0` in the same way as we
compute the included instance members of the on-type using the 
`<extensionShowHidePart>` that follows the on-type in the declaration.

Assume that `E` is an extension declaration and that the extension type
`E0` is a superextension of `E`. Let `m` be the name of an associated
member of `E0`. A compile-time error occurs if `E` also declares a member
named `m`.

Assume that `E` is an extension declaration and that the extension types
`E0a` and `E0b` are superextensions of `E`. Let `Ma` be the associated
members of `E0a`, and `Mb` the associated members of `E0b`. A compile-time
error occurs unless the member names of `Ma` and the member names of `Mb`
are disjoint sets.

*It is allowed for `E` to select a getter from `E0a` and the corresponding
setter from `E0b`, even though Dart generally treats a getter/setter pair
as a unit. However, a show/hide part explicitly supports separation of a
getter/setter pair using `get m` respectively `set m`. The rationale is
that an extension type may well be used to provide a read-only interface
for an object whose members do otherwise allow for mutation, and this
requires that the getter is included and the setter is not.*

*Conflicts between superextensions are not allowed, they must be resolved
explicitly (using show/hide). The rationale is that the extends clause of
an extension is concerned with code reuse, not modeling, and there is no
reason to believe that any implicit conflict resolution will consistently
do the right thing.*

The effect of having an extension type `E` with superextensions `E1, .. Ek`
is that the union of the members declared by `E` and associated members of
`E1, .. Ek` can be invoked on a receiver of type `E`.

Also, if `E` is an implicit extension type (*hence, implicit invocation of
members of `E` is enabled*) then the same set of members can be invoked
implicitly on a receiver whose type matches the on-type of `E`. There is no
conflict if it is possible to invoke an extension member `Ej.m` both
because `Ej` admits an implicit invocation, and because `E` admits an
implicit invocation and `Ej` is a superextension of `E`.*

In the body of `E`, the specification of lexical lookup is changed to
include an additional case: If a lexical lookup is performed for a name
`n`, and no declarations whose basename is the basename of `n` is found in
the enclosing scopes, and a member declaration named `n` exists in the sets
of associated members of superextensions, then that member declaration is
the result of the lookup; if the lookup is for a setter and a getter is
found or vice versa, then a compile-time error occurs. Otherwise, if the
set of associated members does not contain a member whose basename is the
basename of `n`, the lexical lookup yields nothing (*which implies that
`this.` will be prepended to the expression, following the existing
rules*).

*This means that the declarations that occur in the enclosing syntax, i.e.,
in an enclosing lexical scope, get the highest priority, as always in
Dart. Those declarations may be top-level declarations, or they may be
members of the enclosing extension declaration (in which case an invocation
involves `this` when it is an instance member). The second highest priority
is given to instance members of superextensions (where invocations always
involve `this`). The next priority is given to instance members of the
on-type, and finally we can have an implicit invocation of a member of
some other extension `E1`, as long as `E1` is implicit and the type of
`this` matches the on-type of `E1`.*


## Dynamic Semantics

The dynamic semantics of extension method invocation follows from the code
transformation specified in the section about the static analysis.

*So, if `e` is an expression whose static type `E` is the extension type
<code>Ext<S<sub>1</sub>, .. S<sub>k</sub>></code>,
then a member access like `e.m(args)` is executed as
<code>invokeExtensionMethod(Ext<S<sub>1</sub>, .. S<sub>k</sub>>, e).m(args)</code>
and similarly for instance getters and operators.*

Let `e0` be this `invokeExtensionMethod` expression. The semantics of `e0`
is that `e` is evaluated to an object `o`, the argument list denoted by
`(args)` is evaluated to an actual argument list value `(o1, .. ok, x1:
ok+1, .. xn: ok+n)`, and then the body of `E.m` is executed in an
environment where `this` is bound to `o`, the type variables `X1, .. Xk`
are bound to the actual values of `S1, .. Sk`, and the formal parameters
are bound to the actual arguments. If the body completes returning an
object `o2`, then `e0` completes with the object `o2`; if the body
throws then `e0` throws the same object and stack trace.

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
induced method will invoke the instance method, which is subject to late
binding (so we may end up running `int.floor()` or `double.floor()`,
depending on the dynamic type of `this`).*

At run time, for a given instance `o` typed as an extension type `E`, there
is _no_ reification of `E` associated with `o`.

*This means that, at run time, an object never "knows" that it is being
viewed as having an extension type. By soundness, the run-time type of `o`
will be a subtype of the on-type of `E`.*

The run-time representation of a type argument which is an
extension type `E` (respectively
<code>E<T<sub>1</sub>, .. T<sub>k</sub>></code>)
is the corresponding instantiated on-type.

*This means that an extension type and the underlying on-type are
considered as being the same type at run time. So we can freely use a cast
to introduce or discard the extension type, as the static type of an
instance, or as a type argument in the static type of a data structure or
function involving the extension type.*

*This treatment may appear to be unsound. However, it is in fact sound: Let
`E` be a non-protected extension type with on-type `T`. This implies that
`void Function(E)` is represented as `void Function(T)` at run-time. In
other words, it is possible to have a variable of type `void Function(E)`
that refers to a function object of type `void Function(T)`. This seems to
be a soundness violation because `T <: E` and not vice versa,
statically. However, we consider such types to be the same type at run
time, which is in any case the finest distinction that we can maintain
because there is no representation of `E` at run time. There is no
soundness issue, because the added discipline of a non-protected extension
type is voluntary.*

A type test, `o is U` or `o is! U`, and a type cast, `o as U`, where `U` is
or contains an extension type, is performed at run time as a type test and
type cast on the run-time representation of the extension type as described
above.


## Discussion

### Non-object types

If we introduce any non-object entities in Dart (that is, entities that
cannot be assigned to a variable of type `Object?`, e.g., external C /
JavaScript / ... entities, or non-boxed tuples, etc), then we may wish to
allow for extension types whose on-type is a non-object type.

In this case we may be able to consider an extension type `E` on a
non-object type `T` to be a supertype of `T`, but unrelated to all subtypes
of `Object?`.

### Protection

The ability to "enter" an extension type implicitly may be considered to be
too permissive.

If we wish to uphold the property that every instance typed as a given
extension type `E` has been "vetted" by a particular piece of user-written
code then we may use a protected extension type. This concept is described
in a separate document.
