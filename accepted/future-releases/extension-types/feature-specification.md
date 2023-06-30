# Extension Types

Author: eernst@google.com

Status: Accepted.


## Change Log

This document is built on several earlier proposals of a similar feature
(with different terminology and syntax). The most recent version of the
[views][1] proposal as well as the [extension struct][2] proposal provide
information about the process, including in their change logs.

[1]: https://github.com/dart-lang/language/blob/master/working/1426-extension-types/feature-specification-views.md
[2]: https://github.com/dart-lang/language/blob/master/working/extension_structs/overview.md

2023.06.30
  - Change the feature name and keywords to `extension type`, adjust
    representation type and name declaration to be similar to a primary
    constructor.

2022.12.20
  - Add rule about type modifiers.

2022.11.11
  - Initial version, which is a copy of the views proposal, renaming 'view'
    to 'inline', and adjusting the text accordingly. Also remove support for
    primary constructors.


## Summary

This document specifies a language feature that we call "extension types".

The feature introduces the _extension type_ feature. Is feature introduces a new
kind of type which is declared by a new `extension type` declaration. An
extension type provides a replacement of the members available on instances
of an existing type: when the static type of the instance is an extension
type _V_, the available instance members are exactly the ones provided by
_V_ (noting that there may also be some accessible and applicable extension
members).

In contrast, when the static type of an instance is not an extension type,
it is (by soundness) always the run-time type of the instance or a
supertype thereof. This means that the available instance members are the
members of the run-time type of the instance, or a subset thereof (and
there may also be some extension members).

Hence, using a supertype as the static type allows us to see only a
subset of the members, possibly with a more general member signature. Using
an extension type allows us to _replace_ the set of members, with
subsetting as a special case.

This functionality is entirely static. Invocation of an extension type
member is resolved at compile-time, based on the static type of the
receiver.

An extension type may be considered to be a zero-cost abstraction in the
sense that it works similarly to a wrapper object that holds the wrapped
object in a final instance variable. The extension type thus provides an
interface which is chosen independently of the interface of the wrapped
object, and it provides implementations of the members of the interface of
the extension type, and those implementations can use the members of the
wrapped object as needed.

However, even though an extension type behaves like a wrapping, the wrapper
object will never exist at run time, and a reference whose type is the
extension type will actually refer directly to the underlying wrapped
object.

Consider a member access (e.g., a method call like `e.m(2)`)
where the static type of the receiver (`e`) is an extension type `V`.
In general, the member (`m`) will be a member of `V`, not a member of
the static type of the wrapped object, and the invocation of that
member will be resolved statically (just like extension methods).

Given that there is no wrapper object, we will refer to the "wrapped"
object as the _representation object_ of the extension type, or just the
_representation_.

The mechanism has many traits in common with classes, and many traits in
common with regular `extension` declarations (aka extension methods).  The
fact that it is called `extension type` serves as a reminder that member
invocations are similar to extension methods, which is a property that has
so deep implications that it should be kept in mind at all times when
creating or using an extension type: There is never a dynamic dispatch
step, an extension type member invocation is resolved at compile time, and
the dynamic type of the underlying representation object makes no
difference at all. On the other hand, an extension type is similar to a
class in that it has constructors, and in the treatment of `this`.

Inside the extension type declaration, the keyword `this` is a reference to
the representation whose static type is the enclosing extension type. A
member access to a member of the enclosing extension type may rely on `this`
being induced implicitly (for example, `foo()` means `this.foo()` if the
extension type contains a method declaration named `foo`, or it has a
superinterface that has a `foo`, and no `foo` exists in the enclosing
top-level scope). In other words, scopes and `this` have exactly the same
interaction as in a regular class.

A reference to the representation object typed by its run-time type or a
supertype thereof (that is, typed by a "normal" type for the
representation) is available as a declared name: The extension type
declares the name and type of the representation in a way which is a
special case of the [primary constructor proposal][].
In the body of the extension type the representation object is in scope,
with the declared name and type, as if it had been a final instance
variable in a class.

[primary constructor proposal]: https://github.com/dart-lang/language/pull/3023

All in all, an extension type allows us to replace the interface of a given
representation object and specify how to implement the new interface in
terms of the interface of the representation object.

This is something that we could obviously do with a regular class used
as a wrapper, but when it is done with an extension type there is no
wrapper object, and hence there is no run-time performance cost. In
particular, in the case where we have an extension type `V` with
representation type `R`, we can refer to an object `theRList` of type
`List<R>` using the type `List<V>` (e.g., we could use the cast
`theRList as List<V>`), and this corresponds to "wrapping every
element in the list", but it only takes time _O(1)_ and no space, no
matter how many elements the list contains.


## Motivation

An _extension type_ declaration is a zero-cost abstraction mechanism that
allows developers to replace the set of available operations on a given
object (that is, the instance members of its type) by a different set of
operations (the members declared by the given extension type declaration).

It is zero-cost in the sense that the value denoted by an expression whose
type is an extension type is an object of a different type (known as the
_representation type_ of the extension type), and there is no wrapper
object, in spite of the fact that the extension type declaration behaves
similarly to a wrapping.

The point is that the extension type allows for a convenient and safe
treatment of a given object `o` (and objects reachable from `o`) for a
specialized purpose. It is in particular aimed at the situation where that
purpose requires a certain discipline in the use of `o`'s instance methods:
We may call certain methods, but only in specific ways, and other methods
should not be called at all. This kind of added discipline can be enforced
by accessing `o` typed as an extension type, rather than typed as its
run-time type `R` or some supertype of `R` (which is what we normally
do). For example:

```dart
extension type IdNumber(int i) {
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
don't want to silently pass an ID number (e.g., as an actual arguments
or in an assignment) where an `int` is expected. The extension type
`IdNumber` will do all these things.

We can actually cast away the extension type and hence get access to the
interface of the representation, but we assume that the developer wishes to
maintain this extra discipline, and won't cast away the extension type
unless there is a good reason to do so. Similarly, we can access the
representation using the representation name as a getter.  There is no
reason to consider the latter to be a violation of any kind of
encapsulation or protection barrier, it's just like any other getter
invocation. If desired, the author of the extension type can choose to use
a private representation name, to obtain a small amount of extra
encapsulation.

The extra discipline is enforced because the extension type member
implementations will only treat the representation object in ways that
are written with the purpose of conforming to this particular
discipline (and thereby defines what this discipline is). For example,
if the discipline includes the rule that you should never call a
method `foo` on the representation, then the author of the extension type
will simply need to make sure that none of the extension type member
declarations ever calls `foo`.

Another example would be that we're using interop with JavaScript, and
we wish to work on a given `JSObject` representing a button, using a
`Button` interface which is meaningful for buttons. In this case the
implementation of the members of `Button` will call some low-level
functions like `js_util.getProperty`, but a client who uses the extension
type will have a full implementation of the `Button` interface, and
will hence never need to call `js_util.getProperty`.

(We _can_ just call `js_util.getProperty` anyway, because it accepts two
arguments of type `Object`. But we assume that the developer will be happy
about sticking to the rule that the low-level functions aren't invoked in
application code, and they can do that by using extension types like
`Button`. It is then easy to `grep` your application code and verify that
it never calls `js_util.getProperty`.)

Another potential application would be to generate extension type
declarations handling the navigation of dynamic object trees that are
known to satisfy some sort of schema outside the Dart type system. For
instance, they could be JSON values, modeled using `num`, `bool`,
`String`, `List<dynamic>`, and `Map<String, dynamic>`, and those JSON
values might again be structured according to some schema.

Without extension types, the JSON value would most likely be handled with
static type `dynamic`, and all operations on it would be unsafe. If the
JSON value is assumed to satisfy a specific schema, then it would be
possible to reason about this dynamic code and navigate the tree correctly
according to the schema. However, the code where this kind of careful
reasoning is required may be fragmented into many different locations, and
there is no help detecting that some of those locations are treating the
tree incorrectly according to the schema.

If extension types are available then we can declare a set of extension
types with operations that are tailored to work correctly with the given
schema and its subschemas. This is less error-prone and more maintainable
than the approach where the tree is handled with static type `dynamic`
everywhere.

Here's an example that shows the core of that scenario. The schema that
we're assuming allows for nested `List<dynamic>` with numbers at the
leaves, and nothing else.

```dart
extension type TinyJson(Object it) {
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

An instance creation of an extension type, `V<T>(o)`, will evaluate to a
reference to the representation object, with the static type `V<T>` (and
there is no object at run time that represents the extension type itself).

Returning to the example, the name `TinyJson` can be used as a type,
and a reference with that type can refer to an instance of the
underlying representation type `Object`. In the example, the inferred
type of `tiny` is `TinyJson`.

We can now impose an enhanced discipline on the use of `tiny`, because the
extension type allows for invocations of the members of the extension type,
which enables a specific treatment of the underlying instance of `Object`,
consistent with the assumed schema.

The getter `leaves` is an example of a disciplined use of the given object
structure. The run-time type may be a `List<dynamic>`, but the schema which
is assumed allows only for certain elements in this list (that is, nested
lists or numbers), and in particular it should never be a `String`. The use
of the `add` method on `tiny` would have been allowed if we had used the
type `List<dynamic>` (or `dynamic`) for `tiny`, and that could break the
schema.

When the type of the receiver is the extension type `TinyJson`, it is a
compile-time error to invoke any members that are not in the interface of
the extension type (in this case that means: the members declared in the
body of `TinyJson`). So it is an error to call `add` on `tiny`, and that
protects us from this kind of schema violations.

In general, the use of an extension type allows us to keep some unsafe
operations in a specific location (namely inside the extension type
declaration, or inside one of a set of collaborating extension type
declarations). We can then reason carefully about each operation once and
for all. Clients use the extension type to access objects conforming to the
given schema, and that gives them access to a set of known-safe operations,
making all other operations in the interface of the representation type a
compile-time error.

One possible perspective is that an extension type corresponds to an
abstract data type: There is an underlying representation, but we wish to
restrict the access to that representation to a set of operations that are
independent of the operations available on the representation. In other
words, the extension type ensures that we only work with the representation
in specific ways, even though the representation itself has an interface
that allows us to do many other (wrong) things.

It would be straightforward to enforce an added discipline like this by
writing a wrapper class with the allowed operations as members, and
working on a wrapper object rather than accessing the representation
object and its methods directly:

```dart
// Emulate the extension type using a class.

class TinyJson {
  // The representation is assumed to be a nested list of numbers.
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

This is similar to the extension type in that it enforces the use of
specific operations only (here we have just one: `leaves`), and it makes it
an error to use instance methods of the representation (e.g., `add`).

Creation of wrapper objects consumes space and time. In the case where
we wish to work on an entire data structure, we'd need to wrap each
object as we navigate the data structure. For instance, we need to
create a wrapper `TinyJson(element)` in order to invoke `leaves`
recursively.

In contrast, the extension type declaration is zero-cost, in the sense that
it does _not_ use a wrapper object, it enforces the desired discipline
statically. In the extension type declaration, the invocation of
`TinyJson(element)` in the body of `leaves` can be eliminated entirely by
inlining.

Extension type declarations are static in nature, like extension members:
an extension type declaration may declare some type parameters. The type
parameters will be bound to types which are determined by the static type
of the receiver. Similarly, members of an extension type declaration are
resolved statically, i.e., if `tiny.leaves` is an invocation of an
extension type getter `leaves`, then the declaration named `leaves` whose
body is executed is determined at compile-time. There is no support for
late binding of an extension type member, and hence there is no notion of
overriding. In return for this lack of expressive power, we get improved
performance.


## Syntax

A rule for `<extensionTypeDeclaration>` is added to the grammar, along
with some rules for elements used in extension type declarations:

```ebnf
<extensionTypeDeclaration> ::=
  'final'? 'extension' 'type' <typeIdentifier> <typeParameters>?
  <representationDeclaration> <interfaces>?
  '{'
    (<metadata> <extensionTypeMemberDeclaration>)*
  '}'

<representationDeclaration> ::= '(' <type> <identifier> ')'

<extensionTypeMemberDeclaration> ::= <classMemberDefinition>
```

*The token `type` is not made a built-in identifier: the built-in
identifier `extension` that occurs right before `type` serves to
disambiguate the extension type declaration with a fixed lookahead.*

Some errors can be detected immediately from the syntax:

A compile-time error occurs if the extension type declaration declares any
instance variables.

The _name of the representation_ in an extension type declaration is the
identifier `id` that occurs in the representation declaration, and the
_type of the representation_ is the declared type of `id`.

*There are no special rules for static members in extension types. They can
be declared and called or torn off as usual, e.g.,
`AnExtensionType.myStaticMethod(42)`.*


## Extension Type Member Invocations

This document needs to refer to extension type method invocations including
each part that determines the static analysis and semantics of this
invocation, so we will use a standardized phrase and talk about: An
invocation of the extension type member `m` on the receiver `e` according
to the extension type `V` and with the actual type arguments
<code>T<sub>1</sub>, ..., T<sub>s</sub></code>.

In the case where `m` is a method, the invocation could be an extension
type member property extraction (*a tear-off*) or a method invocation, and
in the latter case there will also be an `<argumentPart>`, optionally
passing some actual type arguments, and (non-optionally) passing an actual
argument list.

The case where `m` is a setter is syntactically different, but the
treatment is the same as with a method accepting a single argument
(*so we will not specify that case explicitly*).

*We need to mention all these elements together, because each of them plays
a role in the static analysis and the dynamic semantics of the invocation.
There is no syntactic representation in the language for this concept,
because the same extension type method invocation can have many different
syntactic forms, and both `V` and <code>T<sub>1</sub>, ...,
T<sub>s</sub></code> are implicit in the actual syntax.*


### Static Analysis of an Extension Type Member Invocation

We need to introduce a concept that is similar to existing concepts
for regular classes.

We say that an extension type declaration _DV_ _has_ a member named `n`
in the case where _DV_ declares a member named `n`, and in the case
where _DV_ has no such declaration, but _DV_ has a direct
superinterface `V` that has a member named `n`. In both cases,
_the member declaration named `n` that DV has_ is said declaration.

*This definition is unambiguous for an extension type that has no
compile-time errors, because name clashes must be resolved by `V`.*

Consider an invocation of the extension type member `m` on the receiver `e`
according to the extension type declaration `V` and with the actual type
arguments <code>T<sub>1</sub>, ..., T<sub>s</sub></code>. If the invocation
includes an actual argument part (possibly including some actual type
arguments) then call it `args`. Finally, assume that `V` declares the type
variables <code>X<sub>1</sub>, ..., X<sub>s</sub></code>.

*Note that it is known that
<code>V&lt;T<sub>1</sub>, ..., T<sub>s</sub>&gt;</code>
has no compile-time errors. In particular, the number of actual type
arguments is correct, and it is a regular-bounded type,
and the static type of `e` is a subtype of
<code>V&lt;T<sub>1</sub>, ..., T<sub>s</sub>&gt;</code>,
or a subtype of the corresponding instantiated representation type
(defined below). This is required when we decide that a given
expression is an extension type member invocation.*

If the name of `m` is a name in the interface of `Object` (*that is,
`toString`, `==`, etc.*), the static analysis of the invocation is
treated as an ordinary instance member invocation on a receiver of
type `Object` and with the same `args`, if any.

Otherwise, a compile-time error occurs if `V` does not have a member
named `m`.

Otherwise, let _Dm_ be the declaration of `m` that `V` has.

If _Dm_ is a getter declaration with return type `R` then the static
type of the invocation is
<code>[T<sub>1</sub>/X<sub>1</sub> .. T<sub>s</sub>/X<sub>s</sub>]R</code>.

If _Dm_is a method with function type `F`, and `args` is omitted, the
invocation has static type
<code>[T<sub>1</sub>/X<sub>1</sub> .. T<sub>s</sub>/X<sub>s</sub>]F</code>.
*This is an extension type method tear-off.*

If _Dm_ is a method with function type `F`, and `args` exists, the static
analysis of the extension type member invocation is the same as that of an
invocation with argument part `args` of a function with type
<code>[T<sub>1</sub>/X<sub>1</sub> .. T<sub>s</sub>/X<sub>s</sub>]F</code>.
*This determines the compile-time errors, if any, and it determines the
type of the invocation as a whole.*


### Dynamic Semantics of an Extension Type Member Invocation

Consider an invocation of the extension type member `m` on the receiver `e`
according to the extension type declaration `V` and with actual type
arguments <code>T<sub>1</sub>, ..., T<sub>s</sub></code>. If the invocation
includes an actual argument part (possibly including some actual type
arguments) then call it `args`. Assume that `V` declares the type variables
<code>X<sub>1</sub>, ..., X<sub>s</sub></code>.

Let _Dm_ be the declaration named `m` thath `V` has.

Evaluation of this invocation proceeds by evaluating `e` to an object
`o`.

Then, if `args` is omitted and _Dm_ is a getter, execute the body of
said getter in an environment where `this` and the name of the
representation are bound to `o`, and the type variables of `V` are
bound to the actual values of
<code>T<sub>1</sub>, .. T<sub>s</sub></code>.
If the body completes returning an object `o2` then the invocation
evaluates to `o2`. If the body throws an object and a stack trace
then the invocation completes throwing the same object and stack
trace.

Otherwise, if `args` is omitted and _Dm_ is a method, the invocation
evaluates to a closurization of _Dm_ where
`this` and the name of the representation are bound to `o`, and the
type variables of `V` are bound to the actual values of
<code>T<sub>1</sub>, .. T<sub>s</sub></code>.
The operator `==` of the closurization returns true if and only if the
operand is the same object.

*Loosely said, these function objects simply use the equality inherited
from `Object`, there are no special exceptions. Note that we can tear off
the same method from the same extension type with the same representation
object twice, and still get different behavior, because the extension type
had different actual type arguments. Hence, we can not consider two
extension type method tear-offs equal just because they have the same
receiver.*

Otherwise, the following is known: `args` is included, and _Dm_ is a
method. The invocation proceeds to evaluate `args` to an actual
argument list `args1`. Then it executes the body of _Dm_ in an
environment where `this` and the name of the representation are bound
to `o`, the type variables of `V` are bound to the actual values of
<code>T<sub>1</sub>, .. T<sub>s</sub></code>,
and the formal parameters of `m` are bound to `args1` in the same way
that they would be bound for a normal function call.
If the body completes returning an object `o2` then the invocation
evaluates to `o2`. If the body throws an object and a stack trace
then the invocation completes throwing the same object and stack
trace.


## Static Analysis of Extension Types

Assume that
<code>T<sub>1</sub>, .. T<sub>s</sub></code>
are types, and `V` resolves to an extension type declaration of the
following form:

```dart
extension type V<X1 extends B1, .. Xs extends Bs>(T id) ... {
  ... // Members.
}
```

It is then allowed to use
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
as a type.

*For example, it can occur as the declared type of a variable or parameter,
as the return type of a function or getter, as a type argument in a type,
as the representation type of an extension type declaration, as the on-type
of an extension declaration, as the type in the `onPart` of a try/catch
statement, in a type test `o is V<...>`, in a type cast `o as V<...>`, or
as the body of a type alias. It is also allowed to create a new instance
where one or more extension types occur as type arguments (e.g.,
`List<V>.empty()`).*

A compile-time error occurs if the type
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
is not regular-bounded.

*In other words, such types can not be super-bounded. The reason for this
restriction is that it is unsound to execute code in the body of `V` in
the case where the values of the type variables do not satisfy their
declared bounds, and those values will be obtained directly from the static
type of the receiver in each member invocation on `V`.*

A compile-time error occurs if a type parameter of an extension type
declaration occurs in a non-covariant position in the representation type.

When `s` is zero,
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
simply stands for `V`, a non-generic extension type.
When `s` is greater than zero, a raw occurrence `V` is treated like a raw
type: Instantiation to bound is used to obtain the omitted type arguments.
*Note that this may yield a super-bounded type, which is then a
compile-time error.*

We say that the static type of said variable, parameter, etc.
_is the extension type_
<code>V&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>,
and that its static type _is an extension type_.

It is a compile-time error if `await e` occurs, and the static type of
`e` is an extension type which is not a subtype of `Future<T>` or
`FutureOr<T>` for any `T`..

A compile-time error occurs if an extension type declares a member whose
name is declared by `Object` as well.

*For example, an extension type declaration cannot declare an operator `==`
or a member named `noSuchMethod` or `toString`. The rationale is that these
extension type methods would be highly confusing and error prone. For
example, collections would still call the instance operator `==`, not the
extension type operator, and string interpolation would call the instance
method `toString`, not the extension type method. Also, when we make this an
error for now, we have the option to allow it, perhaps with some
restrictions, in a future version of Dart.*

A compile-time error occurs if an extension type is used as a
superinterface of a class or a mixin, or if an extension type is used to
derive a mixin.

*In other words, an extension type cannot occur as a superinterface in an
`extends`, `with`, `implements`, or `on` clause of a class or mixin.  On
the other hand, it can occur in other ways, e.g., as a type argument of a
superinterface of a class.*

If `e` is an expression whose static type `V` is the extension type
<code>Name&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code> and `m` is the
name of a member that `V` has, a member access like `e.m(args)` is treated
as an invocation of the extension type member `m` on the receiver `e`
according to the extension type declaration `Name` and with the actual type
arguments <code>T<sub>1</sub>, ..., T<sub>s</sub></code>, with the actual
argument part `args`.

Similarly, `e.m` is treated an invocation of the extension type member `m`
on the receiver `e` according to the extension type declaration `Name` and
with the actual type arguments <code>T<sub>1</sub>, ...,
T<sub>s</sub></code> and no actual argument part.

*Setter invocations are treated as invocations of methods with a
single argument.*

If `e` is an expression whose static type `V` is the extension type
<code>Name&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
and `V` has no member whose basename is the basename of `m`, a member
access like `e.m(args)` may be an extension member access, following
the normal rules about applicability and accessibility of extensions,
in particular that `V` must match the on-type of the extension.

*In the body of an extension type declaration _DV_ with name `Name`
and type parameters
<code>X<sub>1</sub>, .. X<sub>s</sub></code>, for an invocation like
`m(args)`, if a declaration named `m` is found in the body of _DV_
then that invocation is treated as an invocation of the extension type
member `m` on the receiver `this` according to the extension type
declaraten `Name` and with the actual type arguments
<code>T<sub>1</sub>, ..., T<sub>s</sub></code>, and with the actual
argument part `args`.  This is just the same treatment of `this` as in the
body of a class.*

*For example:*

```dart
extension E1 on int { // NB: Just an extension, not `extension type`.
  void foo() { print('E1.foo'); }
}

extension type V1(int it) {
  void foo() { print('V1.foo'); }
  void baz() { print('V1.baz'); }
  void qux() { print('V1.qux'); }
}

void qux() { print('qux'); }

extension type V2(V1 it) {
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

*That is, when the static type of an expression is an extension type `V`
with representation type `R`, each method invocation on that
expression will invoke an instance method declared by `V` or inherited
from a superinterface (or it could be an extension method with on-type
`V`).  Similarly for other member accesses.*

Let _DV_ be an extension type declaration named `Name` with type
parameters
<code>X<sub>1</sub> extends B<sub>1</sub>, .. X<sub>s</sub> extends B<sub>s</sub></code>.
Assume that the representation declaration of _DV_ is `(R id)`.

We then say that the _declared representation type_ of `Name`
is `R`, and the _instantiated representation type_ corresponding to
<code>Name&lt;T<sub>1</sub>,.. T<sub>s</sub>&gt;</code> is
<code>[T<sub>1</sub>/X<sub>1</sub>, .. T<sub>s</sub>/X<sub>s</sub>]R</code>.

We will omit 'declared' and 'instantiated' from the phrase when it is clear
from the context whether we are talking about the extension type
declaration itself, or we're talking about a particular generic
instantiation of an extension type. *For non-generic extension type
declarations, the representation type is the same in either case.*

Let `V` be an extension type of the form
<code>Name&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>, and let
`R` be the corresponding instantiated representation type.  If `R` is
non-nullable then `V` is a proper subtype of `Object`, and `V` is
non-nullable.  Otherwise, `V` is a proper subtype of `Object?`, and
`V` is potentially nullable.

*That is, an expression of an extension type can be assigned to a top
type (like all other expressions), and if the representation type is
non-nullable then it can also be assigned to `Object`. Non-extension
types (except bottom types) cannot be assigned to extension types without
a cast. Similarly, null cannot be assigned to an extension type without a
cast, even in the case where the representation type is nullable (even
better: don't use a cast, call a constructor instead). Another consequence of
the fact that the extension type is potentially non-nullable is that it
is an error to have an instance variable whose type is an extension type,
and then relying on implicit initialization to null.*

In the body of a member of an extension type declaration _DV_ named
`Name` and declaring the type parameters
<code>X<sub>1</sub>, .. X<sub>s</sub></code>,
the static type of `this` is
<code>Name&lt;X<sub>1</sub> .. X<sub>s</sub>&gt;</code>.
The static type of the representation name is the representation
type.

*For example, in `extension type V(R id) ...`, `id` has type
`R`, and `this` has type `V`.*

Let _DV_ be an extension type declaration named `V` with representation
type `R`. Assuming that all types have been fully alias expanded, we say
that _DV_ has a representation dependency on an extension type declaration
_DV2_ if `R` contains an identifier `id` (possibly qualified) that resolves
to _DV2_, or `id` resolves to an extension type declaration _DV3_ and _DV3_
has a representation dependency on _DV2_.

It is a compile-time error if an extension type declaration has a
representation dependency on itself.

*In other words, cycles are not allowed. This ensures that it is
always possible to find a non-extension type which is the ultimate
representation type of any given extension type.*

The *extension type erasure* of an extension type `V` is obtained by
recursively replacing every subterm of `V` which is an extension type by
the corresponding representation type.

*Note that this extension type erasure exists, because it is a compile-time
error to have a dependency cycle among extension type declarations.*

Let
<code>X<sub>1</sub> extends B<sub>1</sub>, .. X<sub>s</sub> extends B<sub>s</sub></code>
be a declaration of the type parameters of a generic entity (*it could
be a generic class, extension type, or mixin, or typedef, or function*).
Let <code>BB<sub>j</sub></code> be the extension type erasure of
<code>B<sub>j</sub></code>, for _j_ in _1 .. s_.
It is a compile-time error if
<code>X<sub>1</sub> extends BB<sub>1</sub>, .. X<sub>s</sub> extends BB<sub>s</sub></code>
has any compile-time errors.

*For example, the extension type erasure could map
<code>X extends C<Y>, Y extends X</code> to
<code>X extends Y, Y extends X</code>,
which is an error.*

An extension type declaration _DV_ named `Name` may declare one or
more constructors. A constructor which is declared in an extension type
declaration is also known as an _extension type constructor_.

*The purpose of having an extension type constructor is that it bundles
an approach for building an instance of the representation type of an
extension type declaration _DV_ with _DV_ itself, which makes it easy to
recognize that this is a way to obtain a value of that extension type. It
can also be used to verify that an existing object (provided as an
actual argument to the constructor) satisfies the requirements for
having that extension type.*

A compile-time error occurs if an extension type constructor includes a
superinitializer. *That is, a term of the form `super(...)` or
`super.id(...)` as the last element of the initializer list.*

A compile-time error occurs if an extension type constructor declares a
super parameter. *For instance, `Name(super.x);`.*

*In the body of a generative extension type constructor, the static type of
`this` is the same as it is in any instance member of the extension type
declaration, that is, `Name<X1 .. Xk>`, where `X1 .. Xk` are the type
parameters declared by `Name`.*

An instance creation expression of the form
<code>Name&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;(...)</code>
or
<code>Name&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;.name(...)</code>
is used to invoke these constructors, and the type of such an expression is
<code>Name&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>.

*In short, extension type constructors appear to be very similar to
constructors in classes, and they correspond to the situation
where the enclosing class has a single, non-late, final instance
variable, which is initialized according to the normal rules for
constructors (in particular, it can occur by means of `this.id`, or in
an initializer list, or by an initializing expression in the
declaration itself, but it is an error if it does not occur at all).*

An extension type `V` used as an expression (*a type literal*) is allowed
and has static type `Type`.

An extension type declaration _DV_ can have the type modifier
`final`. In this case it is a compile-time error for another extension type
declaration _DV2_ to have _DV_ as a superinterface.

*As the grammar shows, any occurrence of the keywords `abstract`,
`base`, `interface`, `sealed`, or `mixin` in an extension type
declaration is a syntax error.*


### Composing Extension Types

This section describes the effect of including a clause derived from
`<interfaces>` in an extension type declaration. We use the phrase
_the implements clause_ to refer to this clause.

*The rationale is that the set of members and member implementations of a
given extension type may need to overlap with that of other extension type
declarations. The implements clause allows for implementation reuse by
putting some shared members in an extension type `V`, and including `V` in
the implements clause of several extension type declarations
<code>V<sub>1</sub> .. V<sub>k</sub></code>, thus "inheriting" the members
of `V` into all of <code>V<sub>1</sub> .. V<sub>k</sub></code> without code
duplication.*

*The reason why this mechanism uses the keyword `implements` rather
than `extends` to declare a relation that involves "inheritance" is
that it has a similar semantics as that of extension members (in that
they are statically resolved, and each member is applicable to every
subtype).*

Assume that _DV_ is an extension type declaration named `Name`, and
`V1` occurs as one of the `<type>`s in the `<interfaces>` of _DV_. In
this case we say that `V1` is a _superinterface_ of _DV_.

If _DV_ does not include an `<interfaces>` clause then _DV_ has no
superinterfaces. *But note that `Object?` and perhaps `Object` are still
supertypes.*

A compile-time error occurs if `V1` is a type name or a parameterized type
which occurs as a superinterface in an extension type declaration _DV_, but
`V1` does not denote an extension type.

A compile-time error occurs if any direct or indirect superinterface
of _DV_ is the type `Name` or a type of the form `Name<...>`. *As
usual, subtype cycles are not allowed.*

Assume that _DV_ has two direct or indirect superinterfaces of the form
<code>W&lt;T<sub>1</sub>, .. T<sub>k</sub>&gt;</code>
respectively
<code>W&lt;S<sub>1</sub>, .. S<sub>k</sub>&gt;</code>.
A compile-time error
occurs if
<code>T<sub>j</sub></code>
is not equal to
<code>S<sub>j</sub></code>
for any _j_ in _1 .. k_. The notion of equality used here is the same
as with the corresponding rule about superinterfaces of classes.

Assume that an extension type declaration _DV_ named `Name` has
representation type `R`, and that the extension type `V1` with
declaration _DV1_ is a superinterface of _DV_ (*note that `V1` may
have some actual type arguments*).  Assume that `S` is the
instantiated representation type corresponding to `V1`. A compile-time
error occurs if `R` is not a subtype of `S`.

*This ensures that it is sound to bind the value of `id` in _DV_ to `id1`
in `V1` when invoking members of `V1`, where `id` is the representation
name of _DV_ and `id1` is the representation name of _DV1_.*

Assume that _DV_ declares an extension type declaration named `Name` with
type parameters <code>X<sub>1</sub> .. X<sub>s</sub></code>,
and `V1` is a superinterface of _DV_. Then
<code>Name&lt;T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
is a subtype of
<code>[T<sub>1</sub>/X<sub>1</sub> .. T<sub>s</sub>/X<sub>s</sub>]V1</code>
for all <code>T<sub>1</sub>, .. T<sub>s</sub></code>.

*In short, if `V1` is a superinterface of `V` then `V1` is also a
supertype of `V`.*

A compile-time error occurs if an extension type declaration _DV_ has
two superinterfaces `V1` and `V2`, where both `V1` and `V2` have a
member named _m_, and the two declarations of _m_ are distinct
declarations, and _DV_ does not declare a member named _m_.

*In other words, if two different declarations of _m_ are inherited
from two superinterfaces then the subinterface must resolve the
conflict. The so-called diamond inheritance pattern can create the
case where two superinterfaces have an _m_, but they are both declared by
the same declaration (so `V` is a subinterface of `V1` and `V2`, and both
`V1` and `V2` are subinterfaces of `V3`, and only `V3` declares _m_,
in which case there is no conflict in `V`).*

*Assume that _DV_ is an extension type declaration named `Name`, and
the extension type `V1`, declared by _DV1_, is a superinterface of
_DV_. Let `m` be the name of a member of `V1`. If _DV_ also declares a
member named `m` then the latter may be considered similar to a
declaration that "overrides" the former.  However, it should be noted
that extension type method invocation is resolved statically, and hence
there is no override relationship among the two in the traditional
object-oriented sense (that is, it will never occur that the
statically known declaration is the member of `V1`, and the member
invoked at run time is the one in _DV_). A receiver with static
type `V1` will invoke the declaration in _DV1_, and a receiver with
static type `Name` (or `Name<...>`) will invoke the one in _DV_.*

Hence, we use a different word to describe the relationship between a
member named _m_ of a superinterface, and a member named _m_ which is
declared by the subinterface: We say that the latter _redeclares_ the
former.

*In particular, if two different declarations of _m_ are inherited
from two superinterfaces then the subinterface can resolve the conflict
by redeclaring _m_.*

*Note that there is no notion of having a 'correct override relation'
here. With extension types, any member signature can redeclare any
other member signature with the same name, including the case where a
method is redeclared by a getter, or vice versa. The reason for this
is that no call site will resolve to one of several declarations at
run time. Each invocation will statically resolve to one particular
declaration, and this makes it possible to ensure that the invocation
is type correct.*

*Note that extension methods (in a regular `extension` declaration, not an
`extension type`) have a similar nature: An extension declaration `E1` on
`T1` and another extension declaration `E2` on `T2` where `T1 <: T2` behave
in a way which is similar to overriding in that a more special receiver can
invoke `T1.foo` at a call site like `e.foo()`, whereas it would have
invoked `T2.foo` if the static type of `e` had been more general (if
that type would then match `T2`, but not `T1`). In this case there is also
no override relationship between `T1.foo` and `T2.foo`, they are just
independent member signatures.*

Assume that _DV_ is an extension type declaration, and that the extension
types `V1` and `V2` are extension type superinterfaces of _DV_. Let `M1` be
the members of `V1`, and `M2` the members of `V2`. A compile-time error
occurs if there is a member name `m` such that `V1` as well as `V2` has a
member named `m`, and they are distinct declarations, and _DV_ does not
declare a member named `m`.  *In other words, a name clash among distinct
"inherited" members is an error, but it can be eliminated by redeclaring
the clashing name.*

The effect of having an extension type declaration _DV_ with
superinterfaces `V1, .. Vk` is that the members declared by _DV_ as
well as all members of `V1, .. Vk` that are not redeclared by a
declaration in _DV_ can be invoked on a receiver of the type
introduced by _DV_.


## Dynamic Semantics of Extension Types

For any given syntactic construct which has been characterized as an
extension type member invocation during the static analysis, the dynamic
semantics of the construct is the dynamic semantics of said
extension type member invocation.

Consider an extension type declaration _DV_ named `Name` with
representation name `id` and representation type `R`.  Invocation of a
non-redirecting generative extension type constructor proceeds as follows: A
fresh, non-late, final variable `v` is created. An initializing formal
`this.id` has the side-effect that it initializes `v` to the actual
argument passed to this formal. An initializer list element of the
form `id = e` or `this.id = e` is evaluated by evaluating `e` to an
object `o` and binding `v` to `o`.  During the execution of the
constructor body, `this` and `id` are bound to the value of `v`.  The
value of the instance creation expression that gave rise to this
constructor execution is the value of `this`.

At run time, for a given instance `o` typed as an extension type `V`, there
is _no_ reification of `V` associated with `o`.

*This means that, at run time, an object never "knows" that it is being
viewed as having an extension type. By soundness, the run-time type of `o`
will be a subtype of the representation type of `V`.*

The run-time representation of a type argument which is an extension type
`V` is the corresponding instantiated representation type.

*This means that an extension type and the underlying representation type
are considered as being the same type at run time. So we can freely use a
cast to introduce or discard the extension type, as the static type of an
instance, or as a type argument in the static type of a data structure or
function involving the extension type.*

A type test, `o is U` or `o is! U`, and a type cast, `o as U`, where
`U` is or contains an extension type, is performed at run time as a type
test and type cast on the run-time representation of the extension type
as described above.

An extension type `V` used as an expression (*a type literal*) evaluates
to the value of the corresponding instantiated representation type
used as an expression.


### Summary of Typing Relationships

*Here is an overview of the subtype relationships of an extension type
`V0` with instantiated representation type `R` and superinterfaces
`V1 .. Vk`, as well as other typing relationships involving `V0`:*

- *`V0` is a proper subtype of `Object?`.*
- *`V0` is a supertype of `Never`.*
- *If `R` is a non-nullable type then `V0` is a proper subtype of
  `Object`, and a non-nullable type.*
- *`V0` is a proper subtype of each of `V1 .. Vk`.*
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
extension type and each of its superinterfaces. So if we have
`extension V(T id) implements V1, V2 ...` then `V <: V1` and `V <: V2`.

In some cases it might be preferable to omit the subtype relationship,
even though there is a code reuse element (because `V1` is a
superinterface of `V`, we just don't need or want `V <: V1`).

A possible workaround would be to write forwarding methods manually:

```dart
extension type V1(R it) {
  void foo() {...}
}

// `V` can reuse code from `V1` by using `implements`. Note that
// `S <: R`, because otherwise it is a compile-time error.
extension type V(S it) implements V1 {}

// Alternatively, we can write forwarders, in order to avoid
// having the subtype relationship `V <: V1`.
extension type V(S it) {
  void foo() => V1(it).foo();
}
```
