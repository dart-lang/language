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

2023.08.17
  - Add covariance subtype rule for extension types. Add rule that it is an
    error for an extension type member to be abstract. Mention that it is
    allowed for extension type members to be external. Adjust the notion of
    the 'depth' of a type such that `UP` can be used with extension types.

2023.07.13
  - Revise many details, in particular the management of ambiguities
    involving extension type members and non-extension type members.

2023.07.06
  - Remove the support for `final` extension types.

2023.06.30
  - Change the feature name and keywords to `extension type`, adjust
    representation type and name declaration to be similar to a primary
    constructor. Allow non-extension type superinterfaces.

2022.12.20
  - Add rule about type modifiers.

2022.11.11
  - Initial version, which is a copy of the views proposal, renaming 'view'
    to 'inline', and adjusting the text accordingly. Also remove support for
    primary constructors.


## Summary

This document specifies a language feature that we call "extension types".

The feature introduces the _extension type_ feature. This feature
introduces a new kind of type which is declared by a new `extension type`
declaration. An extension type provides a replacement of the members
available on instances of an existing type: when the static type of the
instance is an extension type _V_, the available instance members are
exactly the ones provided by _V_. There may also be some accessible and
applicable extension members (that is, from the existing feature expressed
as an `extension` declaration, not an `extension type` declaration).

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
receiver, and the actual type arguments (if any) are obtained directly from
the static type of the receiver.

An extension type may be considered to be a zero-cost abstraction in the
sense that it works similarly to a wrapper object that holds the wrapped
object in a final instance variable. The extension type thus provides an
interface which is chosen independently of the interface of the wrapped
object, and it provides implementations of the members of the interface of
the extension type, and those implementations can use the members of the
wrapped object as needed.

However, even though an extension type behaves like a wrapping, the wrapper
object will never exist at run time, and a reference whose type is the
extension type will actually refer directly to the underlying "wrapped"
object. This fact also determines the behavior of `as` and `is`: Those
operations will refer to the run-time type of the "wrapped" object,
and the extension type is just an alias for the declared type of the
"wrapped" object at run time.

Consider a member access (e.g., a method call like `e.m(2)`)
where the static type of the receiver (`e`) is an extension type `V`.
In general, the member (`m`) will be a member of `V`, not a member of
the static type of the "wrapped" object, and the invocation of that
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
interaction as in a class.

A reference to the representation object typed by its run-time type or a
supertype thereof (that is, typed by a "normal" type for the
representation) is available as a declared name: The extension type
declares the name and type of the representation in a way which is a
special case of the [primary constructor proposal][].
In the body of the extension type the representation object is in scope,
with the declared name and type, as if it had been a final instance
variable in a class. Similarly, if the representation name is `id` then the
representation object can be accessed using `this.id` in the body or `e.id`
anywhere, as long as the static type of `e` is that extension type.

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

Finally, it is also possible to declare a non-extension type as a
superinterface in an extension type declaration, if certain conditions are
satisfied. This can be viewed as a partial unveiling of the representation
object, in the sense that it enables some members of the representation
type to be invoked on the extension type, and it makes the extension type a
subtype of that non-extension type.


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

  // Assume that we can validate an ID number relative to
  // `Some parameters`, filtering out some fake ID numbers.
  bool isValid(Some parameters) => ...;

  ... // Some other members, whatever is needed.

  // We do not declare, e.g., an operator +, because addition
  // does not make sense for ID numbers.
}

void main() {
  int myUnsafeId = 42424242;
  myUnsafeId = myUnsafeId + 10; // No complaints.

  var safeId = IdNumber(42424242);

  if (!safeId.isValid(someArguments)) throw "Bad IdNumber!"; // OK.
  safeId + 10; // Compile-time error, no operator `+`.
  10 + safeId; // Compile-time error, wrong argument type.
  myUnsafeId = safeId; // Compile-time error, wrong type.
  myUnsafeId = safeId as int; // OK, we can force it.
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
representation using the representation name as a getter, inside or outside
the body of the extension type declaration.

The extra discipline is enforced in the sense that the extension type
member implementations will only treat the representation object in ways
that conform to this particular discipline (and thereby defines what this
discipline is). For example, if the discipline includes the rule that you
should never call a method `foo` on the representation, then the author of
the extension type will simply need to make sure that none of the extension
type member declarations ever calls `foo`.

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

In general, the use of an extension type allows us to keep invocations of
certain unsafe operations in a specific location (namely inside the
extension type declaration, or inside one of a set of collaborating
extension type declarations). We can then reason carefully about each
operation once and for all. Clients use the extension type to access
objects conforming to the given schema, and that gives them access to a set
of known-safe operations, making all other operations in the interface of
the representation type a compile-time error.

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
  'extension' 'type' 'const'? <typeIdentifier> <typeParameters>?
  <representationDeclaration> <interfaces>?
  '{'
    (<metadata> <extensionTypeMemberDeclaration>)*
  '}'

<representationDeclaration> ::=
  ('.' <identifierOrNew>)? '(' <metadata> <type> <identifier> ')'

<identifierOrNew> ::= <identifier> | 'new'

<extensionTypeMemberDeclaration> ::= <classMemberDefinition>
```

*The token `type` is not made a built-in identifier: the built-in
identifier `extension` that occurs right before `type` serves to
disambiguate the extension type declaration with a fixed lookahead.*

Some errors can be detected immediately from the syntax:

A compile-time error occurs if the extension type declaration declares any
instance variables.

The _name of the representation_ in an extension type declaration with a
representation declaration of the form `(T id)` is the identifier `id`, and
the _type of the representation_ is `T`.

*There are no special rules for static members in extension types. They can
be declared and called or torn off as usual, e.g.,
`AnExtensionType.myStaticMethod(42)`.*


## Extension Type Member Invocations

This document needs to refer to extension type method invocations including
each part that determines the static analysis and semantics of this
invocation, so we will use a standardized phrase and talk about: An
invocation of the extension type member `m` on the receiver expression `e`
according to the extension type declaration `V` with the actual type
arguments <code>T<sub>1</sub>, ..., T<sub>s</sub></code>.

In the case where `m` is a method, the invocation could be an extension
type member property extraction (*a getter invocation or a tear-off*) or a
method invocation, and in the latter case there will also be an
`<argumentPart>`, optionally passing some actual type arguments, and
(non-optionally) passing an actual argument list. Finally, it may be a
property extraction followed by a term derived from `<typeArguments>`, in
which case it denotes a generic function instantiation of the function
object yielded by the property extraction.

*These constructs are standard, but they have different semantics when `m`
is an extension type member, so we need to state their static analysis and
dynamic semantics separately.*

The case where `m` is a setter is syntactically different, but the
treatment is the same as with a method accepting a single argument
(*so we will not specify that case explicitly*). Similarly for operator
invocations.

*We need to mention all these elements together, because each of them plays
a role in the static analysis and the dynamic semantics of the invocation.
There is no syntactic representation in the language for this concept,
because the same extension type method invocation can have different
syntactic forms, and both `V` and
<code>T<sub>1</sub>, ..., T<sub>s</sub></code> are implicit in the actual
syntax.*


### Static Analysis of an Extension Type Member Invocation

This section specifies the static analysis of an extension type member
invocation. Note that this is the meta-syntactic concept which was
introduced in the previous section, and the underlying concrete syntax does
not explicitly include all elements needed to give this specification. The
subsequent sections will specify all the elements ("an invocation of the
extension type member `m` ...") based on specific syntax, and then rely an
this section to specify the static analysis of the given situation.

*Note that some compile-time errors may seem relevant in this section, but
they are actually specified in the section about the static analysis of
extension types. This is because said errors are errors in an extension
type declaration, but this section is concerned with invocations of
extension type members.*

We need to introduce a concept that is similar to existing concepts
for regular classes.

We say that an extension type declaration _DV_ _has_ an extension type
member named `n` in the case where _DV_ declares a member named `n`, and in
the case where _DV_ has no such declaration, but _DV_ has a direct
extension type superinterface `V` that has an extension type member named
`n`. In both cases, when this is unique, _the extension type member
declaration named `n` that DV has_ is said declaration.

The type (function type for a method, return type for a getter) of this
declaration relative to this invocation is determined by repeatedly
computing the instantiated type of the superinterface during the traversal
of the superinterface graph to the superinterface declaration that contains
this member daclaration, and then substituting the actual values of the
type parameters of the extension type into the type of that declaration.

Similarly, we say that an extension type declaration _DV_ _has_ a
non-extension type member named `n` in the case where _DV_ does not declare
a member named `n`, but _DV_ has a direct extension type superinterface `V`
that has a non-extension type member named `n`, or _DV_ has a direct
non-extension type superinterface `T` whose interface contains a member
signature named `n`.

The member signature of such a member is the combined member signature of
all non-extension type members named `n` that _DV_ has, again using a
repeated computation of the instantiated type of each superinterface on the
path to the given non-extension type superinterface.

*In this section it is assumed that _DV_ does not have any compile-time
errors, which ensures that this combined member signature exists.*

Now we are ready to specify the invocation itself.

Consider an invocation of the extension type member `m` on the receiver
expression `e` according to the extension type declaration `V` with the
actual type arguments <code>T<sub>1</sub>, ..., T<sub>s</sub></code>. If
the invocation includes an actual argument part (possibly including some
actual type arguments) then call it `args`. If the invocation does not
include an actual argument part, but it does include a list of actual type
arguments, call it `typeArgs`. Finally, assume that `V` declares the type
variables <code>X<sub>1</sub>, ..., X<sub>s</sub></code>.

*Note that in this section it is known that
<code>V\<T<sub>1</sub>, ..., T<sub>s</sub>&gt;</code>
has no compile-time errors. In particular, the number of actual type
arguments is correct, and it is a regular-bounded type,
and the static type of `e` is a subtype of
<code>V\<T<sub>1</sub>, ..., T<sub>s</sub>&gt;</code>,
or a subtype of the corresponding instantiated representation type
(defined below). This is required when we decide that a given
expression is an extension type member invocation, but it is already
ensured by normal static analysis of subexpressions like `e`.*

If the name of `m` is a name in the interface of `Object` (that is,
`toString`, `==`, `hashCode`, `runtimeType`, or `noSuchMethod`), the static
analysis of the invocation is treated as an ordinary instance member
invocation on a receiver of type `Object?` and with the same `args` or
`typeArgs`, if any.

Otherwise, a compile-time error occurs if `V` does not have a member
named `m`.

Otherwise, `V` has a member named `m`. *It is provided by a unique
declaration which is an extension type member, or it is provided by a set
of members of the interfaces of non-extension types, as described in the
following.*

*Note that it is a compile-time error for the extension type declaration if
`V` has an extension type member named `m` as well as a non-extension type
member named `m`. So there's no need to consider that case here.*

Consider the case where `V` has a non-extension type member named `m`. In
this case the invocation is treated as an invocation of the instance member
`m` on the given receiver, using the member signature for `m` as specified
earlier in this section.

*In other words, members "inherited" from non-extension type
superinterfaces, directly or indirectly, are invoked as normal class
instance members, as if we could "see through the veil" that is the
extension type, and call members of the representation type which have been
unveiled by including certain non-extension types as superinterfaces.*

Otherwise, `V` has an extension type member `m` with a uniquely determined
declaration _Dm_ *(whose type is obtained by substitutions along the
superinterface path as specified above)*.

If _Dm_ is a getter declaration with return type `R` then the static
type of the invocation is `R`.

If _Dm_ is a method with function type `F`, and `args` is omitted, the
invocation has static type `F`.
*This is an extension type method tear-off.*

Assume that _Dm_ is a method with function type `F`, and `typeArgs` is
provided. A compile-time error occurs if `F` is not a generic function type
where `typeArgs` is a list of actual type arguments that conform to the
declared bounds. If no error occurred, the invocation has the static type
which is a non-generic function type where `typeArgs` are substituted into
the function type. *This is a generic function instantiation of an
extension type method tear-off.*

If _Dm_ is a method with function type `F`, and `args` exists, the static
analysis of the extension type member invocation is the same as that of an
invocation with argument part `args` of a function with the given type.


### Dynamic Semantics of an Extension Type Member Invocation

Consider an invocation of the extension type member `m` on the receiver
expression `e` according to the extension type declaration `V` with actual
type arguments <code>T<sub>1</sub>, ..., T<sub>s</sub></code>. If the
invocation includes an actual argument part (possibly including some actual
type arguments) then call it `args`. If the invocation omits `args`, but
includes a list of actual type arguments then call them `typeArgs`. Assume
that `V` declares the type variables
<code>X<sub>1</sub>, ..., X<sub>s</sub></code>.

The dynamic semantics of an invocation or tear-off or generic function
instantiation of a non-extension type member has the same dynamic semantics
as an instance member invocation on the representation object, using the
member signature.

*For instance, a dynamic type check according to this member signature may
be applied to an actual argument whose static type is `dynamic`.*

Otherwise, `m` is an extension type member. Let _Dm_ be the unique
declaration named `m` that `V` has.

*The declaration is known to be unique because the program would otherwise
have a compile-time error.*

Evaluation of this invocation proceeds by evaluating `e` to an object
`o`.

Then, if `args` is omitted and _Dm_ is a getter, execute the body of
said getter in an environment where `this` is bound to `o` and the
representation name denotes a getter that returns `o`, and the type
variables of `V` are bound to the actual values of
<code>T<sub>1</sub>, .. T<sub>s</sub></code>.
If the body completes returning an object `o2` then the invocation
evaluates to `o2`. If the body throws an object and a stack trace
then the invocation completes throwing the same object and stack
trace.

Otherwise, if `args` is omitted and _Dm_ is a method, the invocation
evaluates to a closurization of _Dm_ where
`this` and the name of the representation are bound as with the getter
invocation, and the type variables of `V` are bound to the actual values of
<code>T<sub>1</sub>, .. T<sub>s</sub></code>.
The operator `==` of the closurization returns true if and only if the
operand is the same object.

*Loosely said, these function objects simply use the equality inherited
from `Object`, there are no special exceptions. Note that we can tear off
the same method from the same extension type with the same representation
object twice, and still get different behavior, because the extension type
had different actual type arguments. Hence, we can not consider two
extension type method tear-offs of the same method equal just because they
have the same receiver. Optimizations whereby separately torn-off methods
are represented by the same object are allowed, as long as they behave as
specified. So there is no guarantee that two torn-off methods are unequal,
unless they must behave differently.*

The closurization is subject to generic function instantiation in the case
where `args` is omitted and `typeArgs` provided, using the same semantics
as usual for a given function object.

Otherwise, the following is known: `args` is included, and _Dm_ is a
method. The invocation proceeds to evaluate `args` to an actual
argument list `args1`. Then it executes the body of _Dm_ in an
environment where `this` and the name of the representation are bound
in the same way as in the getter invocation, the type variables of `V` are
bound to the actual values of
<code>T<sub>1</sub>, .. T<sub>s</sub></code>,
and the formal parameters of `m` are bound to `args1` in the same way
that they would be bound for a normal function call.
If the body completes returning an object `o2` then the invocation
evaluates to `o2`. If the body throws an object and a stack trace
then the invocation completes throwing the same object and stack
trace.


## Static Analysis of Extension Types

For the purpose of the static analysis, the extension type is considered to
have a final instance variable whose name is the representation name and
whose declared type is the representation type.

Compile-time errors associated with constructors occur accordingly.

*For example, any non-primary constructor must initialize said instance
variable in their initializer list, or using an initializing formal
parameter (`this.id`).*

All name conflicts specified in the language specification section 'Class
Member Conflicts' occur as well in an extension type declaration.

*For example, it is a compile-time error if an extension type has name `V`
and has an instance member named `V`, and it is a compile-time error if it
has a type parameter named `X` and it has an instance member named `X`.*

It is a compile-time error if a member declaration in an extension type
declaration is abstract.

*Extension type member invocations and tear-offs are always statically
resolved, and abstract members only make sense in the case where the given
member is resolved at run time.*

*It is not an error for an extension type member to have the modifier
`external`. As usual, an implementation can report a compile-time error for
external declarations, e.g., if they are not bound to an implementation,
and the method by which they are bound to an implementation is tool
specific.*

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
<code>V\<T<sub>1</sub>, .. T<sub>k</sub>&gt;</code> as a type.
A compile-time error occurs if the type
<code>V\<T<sub>1</sub>, .. T<sub>k</sub>&gt;</code>
provides a wrong number of type arguments to `V` (when `k` is different
from `s`), and if it is not regular-bounded.

*In other words, such types cannot be super-bounded. The reason for this
restriction is that it is unsound to execute code in the body of `V` in
the case where the values of the type variables do not satisfy their
declared bounds, and those values will be obtained directly from the static
type of the receiver in each member invocation on `V`.*

*Such types can occur as the declared type of a variable or parameter,
as the return type of a function or getter, as a type argument in a type,
as the representation type of an extension type declaration, as the on-type
of an extension declaration, as the type in the `onPart` of a try/catch
statement, in a type test `o is V<...>`, in a type cast `o as V<...>`, or
as the body of a type alias. It is also allowed to create a new instance
where one or more extension types occur as type arguments (e.g.,
`List<V>.empty()`).*

An extension type `V` (which may include actual type arguments) can be used
in an object pattern *(e.g., `case V(): ...` where `V` is an extension
type)*.  Exhaustiveness analysis will treat such patterns as if they had
been an object pattern matching the extension type erasure of `V` (defined
below).

*In other words, we make no attempt to hide the representation type during
the exhaustiveness analysis. The usage of such patterns is very similar to
a cast into the extension type in the sense that it provides a reference of
type `V` to an object without running any constructors of `V`. We will rely
on lints in order to inform developers about such situations, similarly to
the treatment of expressions like `e as V`.*

A compile-time error occurs if a type parameter of an extension type
declaration occurs in a non-covariant position in the representation type.

When `s` is zero *(that is, the declaration of `V` is not generic)*,
<code>V\<T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
simply stands for `V`, a non-generic extension type.
When `s` is greater than zero, a raw occurrence `V` is treated like a raw
type: Instantiation to bound is used to obtain the omitted type arguments.
*Note that this may yield a super-bounded type, which is then a
compile-time error.*

If such a type <code>V\<T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
is used as the type of a declared name
*(of a variable, parameter, etc)*,
we say that the static type of the declared name
_is the extension type_
<code>V\<T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>,
and that its static type _is an extension type_.

It is a compile-time error if `await e` occurs, and the static type of
`e` is an extension type which is not a subtype of `Future<T>` for any
`T`.

A compile-time error occurs if an extension type declares a member whose
basename is the basename of an instance member declared by `Object` as
well.

*Given that the static analysis considers the representation as a final
instance variable, it follows that it is an error to use these names as the
representation name as well.*

*For example, an extension type declaration cannot declare an operator `==`
or a member named `noSuchMethod` or `toString`. The rationale is that these
extension type methods would be highly confusing and error prone. For
example, collections would still call the instance operator `==`, not the
extension type operator, and string interpolation would call the instance
method `toString`, not the extension type method. Also, when we make this an
error for now, we have the option to allow it, perhaps with some
restrictions, in a future version of Dart.*

A compile-time error occurs if an extension type has a non-extension
superinterface whose transitive alias expansion is a type variable, a
deferred type, any top type *(including `dynamic` and `void`)*, the type
`Null`, any function type, the type `Function`, any record type, the type
`Record`, or any type of the form `T?` or `FutureOr<T>` for any type `T`.

*Note that it is not an error to have `implements int` and similar platform
types, and it is not an error to have `implements T` where `T` is a type
that denotes a `sealed`, `final`, or `base` class in a different library,
or `T` is an enumerated type.*

A compile-time error occurs if an extension type is used as a
superinterface of a class, mixin, or enum declaration, or if an extension
type is used in a mixin application as a superclass or as a mixin.

*In other words, an extension type cannot occur as a superinterface in an
`extends`, `with`, `implements`, or `on` clause of a class, mixin, or enum.
On the other hand, it can occur in other ways, e.g., as a type argument of
a superinterface of a class.*

It is a compile-time error if _DV_ is an extension type declaration, and
_DV_ has a non-extension type member named `m` as well as an extension type
member named `m`, for any `m`. *In case of conflicts, _DV_ must declare a
member named `m` to resolve the conflict.*

It is a compile-time error if _DV_ is an extension type declaration, and
_DV_ has a non-extension type member named `m`, and the computation of a
combined member signature for all non-extension type members named `m`
fails. *_DV_ must again declare a member named `m` to resolve the
conflict.*

A compile-time error occurs if an extension type declaration _DV_ has
two extension type superinterfaces `V1` and `V2`, and both `V1` and `V2`
has an extension type member named `m`, and the two members have distinct
declarations.

*In other words, an extension type member conflict is always an error, even
in the case where they agree perfectly on the types. _DV_ must override the
given name to eliminate the error. Note that it is not an error if both
`V1` and `V2` have the member named `m` because they both get it from a
common extension type superinterface, such that it is the same
declaration (which is also known as "diamond" inheritance).*

If `e` is an expression whose static type `V` is the extension type
<code>Name\<T<sub>1</sub>, .. T<sub>s</sub>&gt;</code> and `m` is the
name of a member that `V` has, a member access like `e.m(args)` is treated
as an invocation of the extension type member `m` on the receiver `e`
according to the extension type declaration `Name` with the actual type
arguments <code>T<sub>1</sub>, ..., T<sub>s</sub></code>, with the actual
argument part `args`.

Similarly, `e.m` is treated an invocation of the extension type member `m`
on the receiver `e` according to the extension type declaration `Name`
with the actual type arguments <code>T<sub>1</sub>, ...,
T<sub>s</sub></code> and no actual argument part.

Similarly, `e.m<typeArgs>` is treated the same, but omits
`args`, and includes `<typeArgs>`.

*Setter invocations are treated as invocations of methods with a single
argument. Similarly, operator invocations are treated as method invocations
with unusual member names.*

If `e` is an expression whose static type `V` is the extension type
<code>Name\<T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
and `V` has no member whose basename is the basename of `m`, a member
access like `e.m(args)` may be an extension member access, following
the normal rules about applicability and accessibility of extensions,
in particular that `V` must match the on-type of the extension
*(again, this is an `extension` declaration that we have today, not an
`extension type` declaration)*.

*In the body of an extension type declaration _DV_ with name `Name`
and type parameters
<code>X<sub>1</sub>, .. X<sub>s</sub></code>, for an invocation like
`m(args)`, if a declaration named `m` is found in the body of _DV_
then that invocation is treated as an invocation of the extension type
member `m` on the receiver `this` according to the extension type
declaration `Name` with the actual type arguments
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
<code>Name\<T<sub>1</sub>,.. T<sub>s</sub>&gt;</code> is
<code>[T<sub>1</sub>/X<sub>1</sub>, .. T<sub>s</sub>/X<sub>s</sub>]R</code>.

We will omit 'declared' and 'instantiated' from the phrase when it is clear
from the context whether we are talking about the extension type
declaration itself, or we're talking about a particular generic
instantiation of an extension type. *For non-generic extension type
declarations, the representation type is the same in either case.*

Let `V` be an extension type of the form
<code>Name\<T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>, and let
`R` be the corresponding instantiated representation type.  If `R` is
non-nullable then `V` is a proper subtype of `Object`, and `V` is
non-nullable.  Otherwise, `V` is a proper subtype of `Object?`, and
`V` is potentially nullable.

*That is, an expression of an extension type can be assigned to a top type
(like all other expressions), and if the representation type is
non-nullable then it can also be assigned to `Object`. Non-extension types
(except bottom types and `dynamic`) cannot be assigned to extension types
without an explicit cast. Similarly, null cannot be assigned to an
extension type without an explicit cast, even in the case where the
representation type is nullable (even better: don't use a cast, call a
constructor instead). Another consequence of the fact that the extension
type is potentially non-nullable is that it is an error to have an instance
variable whose type is an extension type, and then relying on implicit
initialization to null.*

In the body of a member of an extension type declaration _DV_ named
`Name` and declaring the type parameters
<code>X<sub>1</sub>, .. X<sub>s</sub></code>,
the static type of `this` is
<code>Name\<X<sub>1</sub> .. X<sub>s</sub>&gt;</code>.
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
representation type of the given extension type.*

The *extension type erasure* of an extension type `V` is obtained by
recursively replacing every subterm of `V` which is an extension type by
the corresponding representation type.

*Note that the extension type erasure always exists, because it is a
compile-time error to have a dependency cycle among extension type
declarations.*

Let
<code>X<sub>1</sub> extends B<sub>1</sub>, .. X<sub>s</sub> extends B<sub>s</sub></code>
be a declaration of the type parameters of a generic entity (*it could
be a generic class, extension type, mixin, typedef, or function*).
Let <code>BB<sub>j</sub></code> be the extension type erasure of
<code>B<sub>j</sub></code>, for _j_ in _1 .. s_.
It is a compile-time error if
<code>X<sub>1</sub> extends BB<sub>1</sub>, .. X<sub>s</sub> extends BB<sub>s</sub></code>
has any compile-time errors.

*For example, the extension type erasure could map
<code>X extends C\<Y>, Y extends X</code> to
<code>X extends Y, Y extends X</code>,
which is an error.*


#### Extension Type Constructors and Their Static Analysis

An extension type declaration _DV_ named `Name` may declare one or
more constructors. A constructor which is declared in an extension type
declaration is also known as an _extension type constructor_.

*The purpose of having an extension type constructor is that it bundles an
approach for receiving or building an instance of the representation type
of an extension type declaration _DV_ with _DV_ itself, and creating an
expression whose static type is the extension type and whose value at run
time is said representation object. Extension type constructor bodies can
also be used to verify that the representation object satisfies the
requirements for having that extension type.*

The `<representationDeclaration>` works as a constructor. The optional
`('.' <identifierOrNew>)` in the grammar is used to declare this
constructor with a name of the form `<identifier> '.' <identifier>` *(at
times described as a "named constructor")*, or `<identifier> '.' 'new'`. It
is a constant constructor if and only if the reserved word `const` occurs
just after `extension type` in the header of the declaration. Other
constructors may be declared `const` or not, following the normal rules for
constant constructors.

A compile-time error occurs if an extension type constructor includes a
superinitializer. *That is, a term of the form `super(...)` or
`super.id(...)` as the last element of the initializer list.*

A compile-time error occurs if an extension type constructor declares a
super parameter. *For instance, `Name(super.x);`.*

In the body of a non-redirecting generative extension type constructor, the
static type of `this` is the same as it is in any instance member of the
extension type declaration. *That is, the type is `Name<X1 .. Xk>`, in an
extension type declaration named `Name` where `X1 .. Xk` are the type
parameters declared by `Name`.*

An instance creation expression of the form
<code>Name\<T<sub>1</sub>, .. T<sub>s</sub>&gt;(...)</code>
or
<code>Name\<T<sub>1</sub>, .. T<sub>s</sub>&gt;.name(...)</code>
is used to invoke these constructors, and the type of such an expression is
<code>Name\<T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>.

*In short, extension type constructors appear to be very similar to
constructors in classes, and they correspond to the situation where the
enclosing class has a single, non-late, final instance variable, which is
initialized according to the normal rules for constructors (in particular,
it can occur by means of `this.id`, or in an initializer list, but it is an
error if the initialization does not occur at all).*

An extension type `V` used as an expression (*a type literal*) is allowed,
and it has static type `Type`.

*Class modifiers can not be used with extension types. As the grammar
shows, any occurrence of the keywords `abstract`, `final`, `base`,
`interface`, `sealed`, or `mixin` in an extension type declaration header
is a syntax error.*


### Declaring Superinterfaces of an Extension Type

This section describes the effect of including a clause derived from
`<interfaces>` in an extension type declaration. We use the phrase
_the implements clause_ to refer to this clause.

*One part of the rationale is that the set of members and member
implementations of a given extension type may need to overlap with that of
other extension type declarations. The implements clause allows for
implementation reuse by putting some shared members in an extension type
`V`, and including `V` in the implements clause of several extension type
declarations <code>V<sub>1</sub> .. V<sub>k</sub></code>, thus "inheriting"
the members of `V` into all of <code>V<sub>1</sub> .. V<sub>k</sub></code>
without code duplication.*

*Another part of the rationale is that it is possible to declare that a
given extension type declaration _DV_ can have `implements ... T ...` where
`T` is a non-extension type. This is used to unveil part of the
representation type, in the sense that it creates a subtype relation to `T`
(such that the extension type is assignable to targets of type `T`), and it
allows members of type `T` to be invoked on a receiver whose static type is
the extension type.*

*The reason why this mechanism uses the keyword `implements` rather
than `extends` to declare a relation that involves "inheritance" is
that it has a similar semantics as that of extension members (in that
they are statically resolved, and each member is applicable to every
subtype).*

Assume that _DV_ is an extension type declaration named `Name`, and
`V1` occurs as one of the `<type>`s in the `<interfaces>` of _DV_. In
this case we say that `V1` is a _superinterface_ of _DV_.

If _DV_ does not include an `<interfaces>` clause then _DV_ has
`Object?` or `Object` as a direct superinterface, according to the subtype
relation which was specified earlier.

A compile-time error occurs if `V1` is a type name or a parameterized type
which occurs as a superinterface in an extension type declaration _DV_, and
`V1` denotes a non-extension type which is not a supertype of the
representation type of _DV_.

*In particular, in order to have `implements T` where `T` is a
non-extension type, it must be sound to consider the representation object
as having type `T`.*

A compile-time error occurs if any direct or indirect superinterface of
_DV_ denotes the declaration _DV_. *As usual, subtype cycles are not
allowed.*

Assume that _DV_ has two direct or indirect superinterfaces of the form
<code>W\<T<sub>1</sub>, .. T<sub>k</sub>&gt;</code>
respectively
<code>W\<S<sub>1</sub>, .. S<sub>k</sub>&gt;</code>.
A compile-time error
occurs if
<code>T<sub>j</sub></code>
is not equal to
<code>S<sub>j</sub></code>
for any _j_ in _1 .. k_. The notion of equality used here is the same
as with the corresponding rule about superinterfaces of classes.

*Note that this is required for extension type superinterfaces as well as
non-extension type superinterfaces.*

Assume that an extension type declaration _DV_ named `Name` has
representation type `R`, and that the extension type `V1` with
declaration _DV1_ is a superinterface of _DV_ (*note that `V1` may
have some actual type arguments*).  Assume that `S` is the
instantiated representation type corresponding to `V1`. A compile-time
error occurs if `R` is not a subtype of `S`.

*This ensures that it is sound to bind the value of `id` in _DV_ to `id1`
in `V1` when invoking members of `V1`, where `id` is the representation
name of _DV_ and `id1` is the representation name of _DV1_.*

*Note that we require `R <: S`, not just that the extension type erasure of
`R` is a subtype of the extension type erasure of `S`. It would have been
sound, and more flexible, to allow the latter. However, when `R <: S` does
not hold, even though the extension type erasures do have the subtype
relation, the author of _DV1_ has chosen to view the representation object
using a representation type `S` that does not "announce its representation
type publicly". Arguably, it is then indicated that _DV_ should not rely on
_DV1_ using that particular representation type.*

Assume that _DV_ declares an extension type declaration named `Name` with
type parameters <code>X<sub>1</sub> .. X<sub>s</sub></code>,
and `V1` is a superinterface of _DV_. Then
<code>Name\<T<sub>1</sub>, .. T<sub>s</sub>&gt;</code>
is a subtype of
<code>[T<sub>1</sub>/X<sub>1</sub> .. T<sub>s</sub>/X<sub>s</sub>]V1</code>
for all <code>T<sub>1</sub>, .. T<sub>s</sub></code>.

*In short, if `V1` is a superinterface of `V` then `V1` is also a supertype
of `V`. This is true for extension type superinterfaces as well as
non-extension type superinterfaces.*

*Assume that _DV_ is an extension type declaration named `Name`, and the
type `V1`, declared by _DV1_, is a superinterface of _DV_ (`V1` could
be an extension type or a non-extension type). Let `m` be the name of a
member of `V1`. If _DV_ also declares a member named `m` then the latter
may be considered similar to a declaration that "overrides" the former.
However, it should be noted that extension type method invocation is
resolved statically, and hence there is no override relationship among the
two in the traditional object-oriented sense (that is, it will never occur
that the statically known declaration is the member of `V1`, and the member
invoked at run time is the one in _DV_). A receiver with static type `V1`
will invoke the declaration in _DV1_, and a receiver with a static type
which is a reference to _DV_ (like `Name` or `Name<...>`) will invoke the
one in _DV_.*

Hence, we use a different word to describe the relationship between a
member named _m_ of a superinterface, and a member named _m_ which is
declared by the subinterface: We say that the latter _redeclares_ the
former.

*In particular, if two different declarations of _m_ are inherited
from two superinterfaces then the subinterface can resolve the conflict
by redeclaring _m_.*

*There is no notion of having a 'correct override relation' here. With
extension types, any member signature can redeclare any other member
signature with the same name, including the case where a method is
redeclared by a getter, or vice versa. The reason for this is that no call
site will resolve to one of several declarations at run time. Each
invocation will statically resolve to one particular declaration, and this
makes it possible to ensure that the invocation is type correct.*

*Extension methods (in a regular `extension` declaration, not an
`extension type`) have a similar nature: An extension declaration `E1` on
`T1` and another extension declaration `E2` on `T2` where `T1 <: T2` behave
in a way which is similar to overriding in that a more special receiver can
invoke `T1.foo` at a call site like `e.foo()`, whereas it would have
invoked `T2.foo` if the static type of `e` had been more general (if that
type would then match `T2`, but not `T1`). In this case there is also no
override relationship between `T1.foo` and `T2.foo`, they are just
independent member signatures.*

*In summary, the effect of having an extension type declaration _DV_ with
superinterfaces `V1, .. Vk` is that the members declared by _DV_ as well as
all members of `V1, .. Vk` that are not redeclared by a declaration in _DV_
can be invoked on a receiver of the type introduced by _DV_.*


### Changes to other types and subtyping

The previous sections have introduced some subtype relationships involving
extension types. This section adds further relationships where extension
types occur more indirectly.

*For instance, earlier sections stated that every extension type is a
subtype of the top types (like `Object?`), and that `implements` introduces
a subtype relationship for extension types. Moreover:*

Assume that `E` denotes an extension type that takes `k` type arguments.
Corresponding to the subtype rule about covariance for classes, a rule is
introduced which makes <code>E\<S<sub>1</sub> .. S<sub>k</sub>></code> a
subtype of <code>E\<T<sub>1</sub> .. T<sub>k</sub>></code> if
<code>S<sub>j</sub></code> is a subtype of <code>T<sub>j</sub></code> for
each `j` in 1 .. k.

*For example, `E<int>` is a subtype of `E<Object>` because `int` is a
subtype of `Object`, also in the case where `E` is an extension type.*

The Dart 1 algorithm which is used to compute the standard upper bound of
two distinct interface types will work in the same way as it does today,
albeit on a slightly different superinterface graph:

For the purpose of this algorithm, we consider `Object?` to be a
superinterface of `Null` and `Object`, and the path lengths mentioned in
the algorithm will increase by one *(because they start from `Object?`
rather than from `Object`)*.

*This change is needed because some extension types are subtypes of
`Object?` and not subtypes of `Object`, and they need to have a
well-defined depth. Note that the depth of an extension type can be
determined by its actual type arguments, if any, because type parameters of
the extension type may occur in its representation type. In particular, the
depth of an extension type is a property of the type itself, and it is not
always possible to determine the depth from the associated extension type
declaration.*


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

The dynamic semantics of an instance creation that references the
`<representationDeclaration>` follows the semantics of primary
constructors: Consider the representation declaration as a primary
constructor, then consider the corresponding non-primary constructor _k_.
The execution of the representation declaration as a constructor has the
same semantics as an execution of _k_.

At run time, for a given instance `o` typed as an extension type `V`, there
is _no_ reification of `V` associated with `o`.

*This means that, at run time, an object never "knows" that it is being
viewed as having an extension type. By soundness, the run-time type of `o`
will be a subtype of the representation type of `V`.*

The run-time representation of a type argument which is an extension type
`V` is the run-time representation of the corresponding instantiated
representation type.

*This wording ensures that we unfold the instantiated representation type
recursively, until it is a non-extension type that does not contain any
subterms which are extension types.*

*Moreover, this means that an extension type and the underlying
representation type are considered as being the same type at run time. So
we can freely use a cast to introduce or discard the extension type, as the
static type of an instance, or as a type argument in the static type of a
data structure or function involving the extension type.*

A type test, `o is U` or `o is! U`, and a type cast, `o as U`, where
`U` is or contains an extension type, is performed at run time as a type
test and type cast on the run-time representation of the extension type
as described above.

*These type casts and type tests where the target type is an extension type
may be considered to "bypass" the constructors of the extension type. This
proposal makes no attempt to prevent this. However, support for detecting
and thus avoiding that this occurs may be provided via lints or similar
mechanisms.*

An extension type `V` used as an expression (*a type literal*) evaluates
to the value of the extension type erasure of the representation type
used as an expression *(also known as the ultimate representation type)*.


### Summary of Typing Relationships

*Here is an overview of the subtype relationships of an extension type `V0`
with instantiated representation type `R` and instantiated superinterface
types `V1 .. Vk`, as well as other typing relationships involving `V0`:*

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


### Is the Primary Constructor Constant?

This proposal specifies that the primary constructor is always
constant. The point is that this is possible, because a primary constructor
and the unique `final` pretend instance variable will always satisfy the
requirements.

We may then allow `const` to be specified explicitly on the primary
constructor later on, in case the developer wishes to make that explicit.

We could also require `const` in the future and simply say that the primary
constructor of an extension type cannot be constant at this time.

Finally, we could require `const` explicitly on the primary constructor
already now, if it should be a constant constructor.

In any case, every non-primary constructor in an extension type would
potentially have properties that would make `const` an error, so they must
specify `const` explicitly as usual.

Update: As of July 19 2023, the reserved word `const` must be specified
explicitly, which will make the primary constructor a constant
constructor.


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


### Allow Implementing a `final` Extension Type?

Note that this section is about the use of a `final` modifier on an
extension type declaration (similar to a class modifier), but that
mechanism has been removed entirely as of July 6 2023. This makes the
current section rather hypothetical; we're just keeping it to document some
discussions along the way.

Consider the following program:

```dart
final class F {} // A regular class. Could also use `int`.
extension type V1(F f) implements F; // OK.

final extension type V2(num n);
extension type V3(int i) implements V2; // Error when `V2` is final.
extension type V4(V2 v2) implements V2; // Error or not?
```

The declaration of `V1` introduces a subtype of the final class `F`, even
though the purpose of `final` on a class is otherwise to prevent the
declaration of such subtypes (at least outside the current library).

This is accepted because an extension type does not introduce subsumption
relative to the `final` class like a subclass would. If we allow a
declaration like `class G implements F {...}` in some other library then we
could have a reference of type `F` and it could be an instance of `G`, and
this means that we do not have any guarantees about which implementation of
any member we would execute. (So `G` destroys a lot of optimizations.) From
a software engineering point of view, we don't want to allow `G` because a
new instance member added to `F` could break `G`. (So `G` turns a lot of
otherwise safe updates in `F` into breaking changes.)

In contrast, the declaration of `V` does not turn addition of members of
`F` into a breaking change, because `V` is allowed to redeclare any member
with any signature. So callers of `V.someMember()` will still run the same
code based on the same signature. It might be seen as a problem that `V`
redeclares a member of `F`, but that can be changed in a major update of
`V`.

`V3` is an error because `V2` declares that it is `final`, which is taken
to indicate that the maintainers of `V2` do not want to have a large number
of dependent declarations "out there", such that they can't change anything
at all about the implementation of `V2` because some of those dependent
declarations will break. It's exactly the same kind of reasoning that we'd
use for a `final` class: I do this in order to reserve some freedom to
change my implementation.

The discussion in this section is concerned with `V4`. Do we want to make
that declaration a compile-time error?

An argument in favor of making it an error would be that `V2` is declared
to be `final`, and this implies that `implements V2` is an error. No
exceptions.

An argument in the opposite direction is that `V4` does not actually depend
on the representation type of `V2` (because it uses `V2` as its
representation type, not `num` or a subtype thereof), and this makes the
relationship between `V4` and `V2` similar to the relationship between `V1`
and `F`.

In general, it is confusing that we accept `implements F`, but `implements
V2` is an error, and in both cases the would-be superinterface has the
modifier `final`. So developers would need to learn a rule along the lines
of "an extension type ignores `final` on a regular class, but it respects
`final` on an extension type, unless it is a supertype of a representation
type".

If we stick to the rules as proposed in this feature specification then
we'll have something slightly simpler: "an extension type ignores `final`
on a regular class, but it respects `final` on an extension type".

However, I don't think we should go all the way to "`implements T` is
always an error when `T` is `final`" (`T` could be an extension type or
a non-extension type, that doesn't matter). The reason is that the ability
to create an extension type whose representation type is a `final` type (in
general: any type that can't have non-bottom subtypes) is crucial: The
performance benefits (size and speed) of using an `int` rather than using a
wrapper class is so huge that it is likely to be a major use case for
extension types that they can allow us to use a built-in class as the
representation, and still have a specialized interface&mdash;that is, an
extension type.
