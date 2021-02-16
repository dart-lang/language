# Extension Types

Author: eernst@google.com

Status: Draft

## Change Log

2021.02.15
  - Initial version, based on 
    [language issue 1426](https://github.com/dart-lang/language/issues/1426).

## Introduction

This document specifies support for a feature known as extension types,
which is an enhancement of the extension methods mechanism that Dart has
supported since version 2.6.

An _extension type_ is a zero-cost abstraction mechanism that allows
developers to replace the set of available operations on a given object
(that is, the instance members of its type) by a different set of
operations (the members declared by the given extension type).

The point is that the extension type allows for a convenient and safe
treatment of a given object `o` (and objects reachable from `o`) for a
specialized purpose or view. It is in particular aimed at the situation
where that purpose or view requires a certain discipline in the use of
`o`'s instance methods: We may call certain methods, but only in specific
ways, and other methods should not be called at all. This kind of added
discipline can be enforced by accessing `o` typed as an extension type,
rather than typed as its run-time type `R` or some supertype of `R` (which
is what we normally do).

An important application would be generated extension types, handling the
navigation of dynamic object trees. For instance, they could be JSON
values, modeled using `num`, `bool`, `String`, `List<dynamic>`, and
`Map<String, dynamic>`.

Without extension types, the JSON value would most likely be handled with
static type `dynamic`, and all operations on it would be unsafe. If the
JSON value is assumed to satisfy a specific schema then it would be
possible to reason about this dynamic code and navigate the tree correctly
according to the schema. But there is no encapsulation, and the code where
this kind of careful reasoning is required may be fragmented into many
different locations.

However, if we declare a set of extension types with operations that are
tailored to work correctly with the given schema then we can centralize the
unsafe operations and reason carefully about them once and for all. Clients
would use those extension types to access objects conforming to that
schema. That would give access to a set of known-safe operations, and it
would make all other operations a compile-time error.

Here's a tiny core of that scenario. The schema allows for nested
`List<dynamic>` with numbers at the leaves, and nothing else:

```dart
extension TinyJson on Object {
  Iterable<num> get leaves sync* {
    var self = this;
    if (self is num) {
      yield self;
    } else if (self is List<dynamic>) {
      for (Object? element in self) {
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

The only novelty in this example, compared to the well-known mechanism
called extension methods, is that the name `TinyJson` can be used as a
type. It is used as the declared type of `tiny` in the `main` function. The
point is that we can now impose an enhanced discipline on the use of
`tiny`, because the extension type only allows invocations of extension
members.

The method `leaves` is an example of a disciplined use of the given object
structure. The run-time type may be a `List<dynamic>`, but the schema which
is assumed for the given value allows only for certain elements in this
list (that is, nested lists or numbers), and in particular it should never
be a `String`. The use of the `add` method on `tiny` would have been
allowed if we had used the type `List<dynamic>` (or `dynamic`) for `tiny`,
and that would break the schema. When the type of the receiver is the
extension type, it is a compile-time error to invoke any members that are
not in the interface of the extension type (in this case that means: the
members declared in the body of `TinyJson`). So it is an error to call
`add` on `tiny`, and that protects us from violations of the scheme.

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

However, creation of wrapper objects takes time and space, and in the case
where we wish to work on an entire data structure we'd need to wrap each
object as we navigate the data structure. For instance, we need to create a
wrapper `TinyJson(element)` in order to invoke `leaves` recursively.

In contrast, the extension type mechanism is zero-cost, in the sense that
it does _not_ use a wrapper object, it enforces the desired discipline
statically.

Like extension methods, extension types are static in nature: An extension
type declaration may declare some type parameters (just like the current
extension declarations), and they will have a value which is determined by
the static type of the receiver. Similarly, like extension methods, members
of an extension type are resolved statically, i.e., if `tiny.leaves` is an
invocation of an extension type getter `leaves` then the declaration named
`leaves` whose body is executed is determined at compile-time. There is no
support for late binding of an extension method, and hence there is no
notion of overriding. In return for this lack of expressive power, we get
improved performance.

Here is another example, giving some hints about the subtype relationships
and other rules about extension types. It uses 

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
  'protected'? 'extension' 'type'? <identifier>? <typeParameters>?
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

*Note that `<type>` derives `<typeIdentifier>`, which makes `<identifier>`
nearly redundant. However, `<identifier>` is still needed because it
includes some strings that cannot be the name of a type, e.g., the built-in
identifiers.*


## Static Analysis

Assume that _E_ is an extension declaration of the following form:

```dart
extension Ext<X1 extends B1, .. Xm extends Bm> on T {
  ... // Members
}
```

It is then allowed to use `Ext<S1, .. Sm>` as a type: It can occur as the
declared type of a variable or parameter, as the return type of a function
or getter, as a type argument in a type, or as the on-type of an extension.

*In particular, it is allowed to create a new instance where one or more
extension types occur as type arguments.*

When `m` is zero, `Ext<S1, .. Sm>` simply stands for `Ext`, a non-generic
extension. When `m` is greater than zero, a raw occurrence `Ext` is treated
like a raw type: Instantiation to bound is used to obtain the omitted type
arguments.

We say that the static type of said variable, parameter, etc. _is the
extension type_ `Ext<S1, .. Sm>`, and that its static type _is an extension
type_.

If `e` is an expression whose static type is the extension type 
`Ext<S1, .. Sm>` then a member access like `e.m()` is treated as 
`Ext<S1, .. Sm>(e as T).m()` where `T` is the on-type corresponding to
`Ext<S1, .. Sm>`, and similarly for instance getters and operators. This
rule also applies when a member access implicitly has the receiver `this`.

*That is, when the type of an expression is an extension type, all method
invocations on that expression will invoke an extension method declared by
that extension, and similarly for other member accesses. In particular, we
can not invoke an instance member when the receiver type is an extension
type.*

For the purpose of checking assignability and type parameter bounds, an
extension type `Ext<S1, .. Sm>` with type parameters `X1 .. Xm` and on-type
`T` is considered to be a proper subtype of `Object?`, and a proper
supertype of `[S1/X1, .. Sm/Xm]T`.

*That is, the underlying on-type can only be recovered by an explicit cast,
and there are no non-trivial supertypes. So an expression whose type is an
extension type is in a sense "in prison", and we can only obtain a
different type for it by forgetting everything (going to a top type), or by
means of an explicit cast.*

When `U` is a non-protected extension type, it is allowed to perform a type
test, `o is U`, and a type check, `o as U`. Promotion of a local variable
`x` based on such type tests or type checks shall promote `x` to the
extension type.

*Protected extension types are introduced below, and they have a more
strict rule for type tests and type casts.*

*Note that promotion only occurs when the type of `o` is a top type. If `o`
already has a non-top type which is a subtype of the on-type of `U` then
we'd use a fresh variable `U o2 = o;` and work with `o2`.*

*There is no change to the type of `this` in the body of an extension _E_:
It is the on-type of _E_. Similarly, extension methods of _E_ invoked in
the body of _E_ are subject to the same treatment as previously, which
means that extension methods of the enclosing extension can be invoked
implicitly, and extension methods are given higher priority than instance
methods on `this` when `this` is implicit.*


### Prevent implicit invocations: Keyword 'type'

This section specifies the effect of including the keyword `type` in the
declaration of an extension type.

*Consider the type `int`. This type is likely to be used as the on-type of
many different extension types, because it allows a very lightweight object
to play the role as a value with a specific interpretation (say, an `Age`
in years or a `Width` in pixels). Different extension types are not
assignable to each other, so we'll offer a certain protection against
inconsistent interpretations.*

*However, if we have many different extension types with the same or
overlapping on-types then it may be impractical to work with: Lots of
extension methods are applicable to any given expression of that on-type,
and they are not intended to be used at all, each of them should only be
used when the associated interpretation is valid, that is, when the static
type of the receiver is the extension type that declares said member.*

*So we need to support the notion of an extension type whose methods are
never invoked implicitly. The keyword `type` has this effect. The intuition
is that an 'extension type' is only useful as a declared type, and it has
no effect on an expression whose static type matches the on-type. Here's
the rule:*

Let `E` be an extension declaration such that `extension` is followed by
`type`. In this case, `E` is not applicable for an implicit extension
method invocation.

*For example:*

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

When `extension` is followed by `type` in an extension declaration, we say
that it introduces an _explicit_ extension type.

*This terminology is motivated by two things: (1) The extension type "is
not implicit", because it doesn't allow for implicit extension method
invocations. (2) The extension type explicitly says `type`, and it must
also be used explicitly as a type.*


### Allow instance member access using `show` and `hide`

This section specifies the effect of including a non-empty
`<extensionShowHidePart>` in an extension declaration.

*It may be useful to support invocation of some or all instance members on
a receiver whose type is an extension type. For instance, there may be some
read-only methods that we can safely call on the on-type, because they
won't violate any invariants associated with the extension type. We address
this need by introducing hide and show clauses on extension types.*

We use the phrase _extension show/hide part_, or just _show/hide part_ when
no doubt can arise, to denote a phrase derived from
`<extensionShowHidePart>`. Similarly, an `<extensionShowClause>` is known
as an _extension show clause_, and an `<extensionHideClause>` is known as
an _extension hide clause_, similarly abbreviated to _show clause_ and
_hide clause_.

The show/hide part specifies which instance members of the on-type are
available for invocation on a receiver whose type is the given extension
type.

A compile-time error occurs if an extension declaration has a non-empty
show/hide part, unless it is explicit.

*That is, if it has `show` or `hide` then it must also have `type`. It
would not make sense to show or hide any instance members when there is no
`type` keyword, because the extension declaration will then allow for
implicit invocations, and they can of course invoke any instance member.*

If the show/hide part is empty, no instance members except the ones
declared for `Object?` can be invoked on a receiver whose static type is
the given extension type.

If the show/hide part is a show clause listing some identifiers and types,
invocation of an instance member is allowed if its basename is one of the
given identifiers, or it is the name of a member of the interface of one of
the types. Instance members declared for object can also be invoked.

If the show/hide part is a hide clause listing some identifiers and types,
invocation of an instance member is allowed if it is in the interface of
the on-type and _not_ among the given identifiers, nor in the interface of
the specified types.

If the show/hide part is a show clause followed by a hide clause then the
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


### Invariant enforcement through introduction: Protected extension types

This section specifies the effect of including the keyword `protected` as
the first token in an extension declaration.

*It may be helpful to constrain the introduction of objects of a given
extension type `U`, such that it is known from the outset that if an
expression has a type `U` then it was guaranteed to have been given that
type in a situation where it satisfied some invariants. If the underlying
representation object (structure) is mutable, the extension type members
should be written in such a way that they preserve the given invariants.
With that, we can trust an object with static type `U` to satisfy those
invariants.*

*First we note that the invariants cannot be protected if implicit
extension method invocations are possible, so we make that an error:*

It is a compile-time error for an extension declaration to start with the
keyword `protected`, unless it is explicit (*that is, unless it also has
the keyword `type`*).

*We introduce the notion of extension type constructors to allow developers
to enforce such invariants.*

When an extension declaration starts with the keyword `protected`, we say
that it is a _protected_ extension type. A protected extension type can
declare one or more non-redirecting factory constructors. We use the phrase
_extension type constructor_ to denote such constructors.

An instance creation expression of the form `Ext<T1, .. Tk>(...)` or
`Ext<T1, .. Tk>.name(...)` is used to invoke these constructors, and the
type of such an expression is `Ext<T1, .. Tk>`.

During static analysis of the body of an extension type constructor, the
return type is considered to be the on-type of the enclosing extension type
declaration.

It is a compile-time error if it is possible to reach the
end of an extension type constructor without returning anything. 

*Even in the case where the on-type is nullable and the intended
representation is the null object, an explicit `return null;` is required.*

A protected extension type is a proper subtype of the top types, and a
proper supertype of `Never`.

*In particular, there is no subtype relationship between a protected
extension type and the corresponding on-type.*

When `E` (respectively `E<X1, .. Xk>`) is a protected extension type, and
`e` is an expression with static type `E` (respectively `E<X1, .. Xk>`), 
it is a compile-time error to perform a type test (`e is T`) or type cast
(`e as T`) when the target type `T` is `E` (respectively `E<T1, .. Tk>`).

*The rationale is that an extension type that justifies _any_ constructors
will need to maintain some invariants, and hence it is not helpful to allow
implicit introduction of any value of that type with a complete lack of
enforcement of the invariants.*

*For example:*

```dart
protected extension type nat on int {
  factory nat(int value) =>
      value >= 0 ? value : throw "Attempt to create an invalid nat";
}

void main() {
  nat n1 = 42; // Error.
  var n2 = nat(42); // OK at compile time, and at run time.
}
```

*The subtyping relationships are illustrated in the following example:*

```dart
class IntBox {
  int i;
  IntBox(this.i);
}

protected extension type EvenIntBox on IntBox {
  factory EvenIntBox(int i) =>
      i % 2 == 0 ? IntBox(i) : throw "Invalid EvenIntBox";
  factory EvenIntBox.fromIntBox(IntBox intBox) =>
      intBox.i % 2 == 0 ? intBox : throw "Invalid EvenIntBox";
  void next() => this.i += 2;
}

void main() {
  var evenIntBox = EvenIntBox(42);
  evenIntBox.next(); // Methods of `EvenIntBox` maintain the invariant.
  var intBox = evenIntBox as IntBox; // OK statically and dynamically.
  intBox.i++; // Invariant of `evenIntBox` violated!
  evenIntBox = intBox as EvenIntBox; // Error, can't cast to EvenIntBox.

  var evenIntBoxes = [evenIntBox]; // Type `List<EvenIntBox>`.
  evenIntBoxes[0].next(); // Elements typed as `EvenIntBox`, maintain invariant.
  List<IntBox> intBoxes = evenIntBoxes; // Compile-time error.
  intBoxes = evenIntBoxes as dynamic; // Run-time error.
}
```


### Boxing

This section describes the implicitly induced `box` getter of an explicit
extension type.

*It may be helpful to equip each explicit extension type with a companion
class whose instances have a single field holding an instance of the
on-type. So it's a wrapper with the same interface as the extension type.*

Let _E_ be an explicit extension type. The declaration of _E_ implicitly
induces a declaration of a class `E.class` with the same type parameters
and members as _E_, subclass of `Object`, with the same direct
superinterfaces as `E`, with a final field whose type is the on-type of
_E_, and with a single argument constructor setting that field to the
argument. A getter `E.class get box` is implicitly induced in _E_, and it
returns an object that wraps `this`.

`E.class` also implicitly induces a getter `E get unbox` which returns the
value of the final field mentioned above.

*In the case where the extension type is protected, the `unbox` getter
cannot be written in Dart (because a cast to `E` is then a compile-time
error), so `unbox` must be a language feature in this case. For
convenience, it is induced implicitly for all extension types.*

In the case where it would be a compile-time error to declare such a member
named `box` or `unbox`, said member is not induced.

*The latter rule helps avoiding conflicts in situations where `box` or
`unbox` is a non-hidden instance member, and it allows developers to write
their own implementations if needed.*


## Dynamic Semantics

The dynamic semantics of extension method invocation is the same as what is
specified for the existing extension declarations, based on the desugaring
which is specified in the section about the static analysis.

*A reminder: If `e` is an expression whose static type is the extension
type `Ext` then a member access like `e.m()` is treated as 
`Ext(e as T).m()`, where `T` is the on-type.*

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

At run time, for a given instance `o` typed as an extension type `U`, there
is _no_ reification of `U` associated with `o`.

*This means that, at run time, an object never "knows" that it is being
viewed as having an extension type. By soundness, the run-time type of `o`
will be a subtype of the on-type of `U`.*

The run-time representation of a type argument which is a non-protected
extension type `E` (respectively `E<T1, .. Tk>`) is the corresponding
on-type.

*This means that a non-protected extension type and the underlying on-type
are considered as being the same type at run time. So we can freely use a
cast to introduce or discard the extension type, as the static type of an
instance, or as a type argument in the static type of a data structure or
function involving the extension type.*

The run-time representation of a type argument which is a protected
extension type `E` (respectively `E<T1, .. Tk>`) is an identification of
`E` (respectively `E<T1, .. Tk>`).

*In particular, it is not the same as the run-time representation of the
corresponding on-type. This is necessary in order to maintain that the
on-type and the protected extension type are unrelated.*

*For a protected extension type `U`, with a data structure or function where
`U` occurs as a subterm in the type (that is, as a type argument, a return
type, or a parameter type), a cast that tries to introduce or discard the
protected extension type will fail at run time.*

*In the non-protected case this treatment may appear to be
unsound. However, it is in fact sound: Let `Ext` be a non-protected
extension type with on-type `T`. This implies that `void Function(Ext)` is
represented as `void Function(T)` at run-time. In other words, it is
possible to have a variable of type `void Function(T)` that refers to a
function object of type `void Function(Ext)`. This seems to be a soundness
violation because `T <: Ext` and not vice versa, statically. However, we
consider such types to be the same type at run time, which is in any case
the finest distinction that we can maintain because there is no
representation of `Ext` at run time. There is no soundness issue, because
the added discipline of a non-protected extension type is voluntary.*

A type test, `o is U`, and a type cast, `o as U`, where `U` is or contains
an extension type, is performed at run time as a type test and type cast on
the run-time representation of the extension type as described above.


## Enhancements


### Non-object entities

If we introduce any non-object entities in Dart (that is, entities that
cannot be assigned to a variable of type `Object?`, e.g., external C /
JavaScript / ... entities, or non-boxed tuples, etc), then we may wish to
allow for extension types whose on-type is a non-object type.

This should not cause any particular problems: If the on-type is a
non-object type then the extension type will not be a subtype of `Object`.


## Discussion

It would be possible to reify extension types when they occur as type
arguments of a generic type.

This might help ensuring that the associated discipline of the extension
type is applied to the elements in, say, a list, even in the case where
that list is obtained under the type `dynamic`, and a type test or type
cast is used to confirm that it is a `List<U>` where `U` is an extension
type.

However, this presumably implies that the cast to a plain `List<T>` where
`T` is the on-type corresponding to `U` should fail; otherwise the
protection against accessing the elements using the underlying on-type will
easily be violated. Moreover, even if we do make this cast fail then we
could cast each element in the list to `T`, thus still accessing the
elements using the on-type rather than the more disciplined extension type
`U`.

We cannot avoid the latter if there is no run-time representation of the
extension type in the elements in the list, and that is assumed here: For
example, if we have an instance of `int`, and it is accessed as `extension
MyInt on int`, the dynamic representation will be a plain `int`, and not
some wrapped entity that contains information that this particular `int` is
viewed as a `MyInt`. It seems somewhat inconsistent if we maintain that a
`List<MyInt>` cannot be viewed as a `List<int>`, but a `MyInt` can be
viewed as an `int`.

As for promotion, we could consider "promoting to a supertype" when that
type is an extension type: Assume that `U` is an extension type with
on-type `T`, and the type of a promotable local variable `x` is `T` or a
subtype thereof; `x is U` could then _demote_ `x` to have type `U`, even
though `is` tests normally do not demote. The rationale would be that the
treatment of `x` as a `U` is conceptually more "informative" and "strict"
than the treatment of `x` as a `T`, which makes it somewhat similar to a
downcast.

Note that we can use extension types to handle `void`:

```dart
extension void on Object? {}
```

This means that `void` is an "epsilon-supertype" of all top types (it's a
proper supertype, but just a little bit). It is also a subtype of
`Object?`, of course, so that creates an equivalence class of "equal" types
spelled differently. That's a well-known concept today, so we can handle
that (and it corresponds to the dynamic semantics).

This approach does not admit any member accesses for a receiver of type
`void`, and it isn't assignable to anything else without a cast. Just like
`void` of today.

However, compared to the treatment of today, we would get support for
voidness preservation, i.e., it would no longer be possible to forget
voidness without a cast in a number of higher order situations:

```dart
List<Object?> objects = <void>[]; // Error.

void f(Object? o) { print(o); }
Object? Function(void) g = f; // Error, for both types in the signature.
```
