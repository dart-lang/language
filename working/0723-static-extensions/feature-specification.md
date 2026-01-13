# Extensions with Static Capabilities

Authors: Erik Ernst, Leaf Petersen

Status: Draft

Version: 1.3

Experiment flag: static-extensions

This document specifies extensions with static capabilities. This is a
feature that supports the addition of static members and/or constructors to
an existing declaration that can have such members, based on a
generalization of the features offered by extension declarations.

## Introduction

An extension declaration in Dart can already (before the addition of
the feature specified here) declare static members, but not
constructors.  Members so declared are only accessible via prefixing
with the extension name.

```dart
extension Numbers on int {
  static int one = 1;
  static int two = 2;
}
void main() {
  // Static members declared in an extension can be accessed by prefixing
  // with the extension name.
  print(Numbers.one);
  print(Numbers.two);
}
```

Developers have requested (e.g. [language issue #723][issue 723]) the
capability of using extension declarations to declare static members
(including constructors) which are accessible via the name of an
existing class, mixin, enum, or extension type declaration.

[issue 723]: https://github.com/dart-lang/language/issues/723


This would allow static members and constructors to be added to
existing declarations after the fact, including in situations where
the user does not have ability to directly edit the source code of
said declaration.

The feature proposed here allows static members and constructors
declared in an extension on a given class/mixin/etc. declaration _D_
to be invoked as if they were static members (respectively
constructors) declared by _D_.  In the case where the on-type of an
extension declaration satisfies certain constraints defined below, we
say that the class/mixin/etc. which is referred to in the on-type is
the _on-declaration_ of the extension, and in the case that an
extension has an on-declaration, static members and constructors
declared in the extension become accessible via its on-declaration
name.  So for example, in the extension `Numbers` defined above, the
on-declaration of the extension is `int`, and the static members
declared in the extension become accessible as if they were static
members declared on the `int` class.

```dart
void main() {
   // Static members on an extension are available via the on-declaration
   // name
   print(int.one + int.two);

   // Static members on an extension continue to be available via the 
   // extension name.
   print(Numbers.one + Numbers.two);
}
```

The enhancements specified for extension declarations in this
document are only applicable to extensions that have an
on-declaration, all other extensions will continue to work exactly as
they do today. Moreover, even in the case that an extension
declaration has an on-declaration, static members declared in the
extension continue to be accessible via the extension name, just as
before this feature.

In addition to static members, this feature also adds the ability to
use an extension to add constructors to the on-declaration (if any) of
the extension.  For example:

```dart
class Distance {
  final int value;
  const Distance(this.value);
}

extension E1 on Distance {
  factory Distance.fromHalf(int half) => Distance(2 * half);
}

void walk(Distance d) {...}

```

In this example, a new constructor is made accessible on the
`Distance` class using an extension.  This constructor becomes
accessible via the `Distance` class name as if declared directly on
the class.

```dart
void test() {
  // Constructors declared in extensions may be invoked via the on-declaration
  // name.
  walk(Distance.fromHalf(10));

  // Constructors declared in extensions may be torn-off via the on-declaration
  // name.
  Distance Function(int) fromHalf = Distance.fromHalf;
  walk(fromHalf);
}
```

As with static members, constructors declared on an extension may also
be invoked or torn off via the extension name.  So given the
declarations of `Distance` and `E1` in the example above, all of the
following are also valid uses of the new constructor.

```dart
void test() {
  // Constructors declared in extensions may be invoked via the extension
  // name.
  walk(E1.fromHalf(10));

  // Constructors declared in extensions may be torn-off via the extension
  // name.
  Distance Function(int) fromHalf = E1.fromHalf;
  walk(fromHalf);
}
```

Extensions can be defined with generic classes as their
on-declaration, and may themselves be generic.

For static members, the genericity of the extension and of the
underlying on-declaration are irrelevant.  Static members do not have
access to the type parameters of the extension, and are invoked
without type arguments as with a normal static member invocation.

Constructors may be declared in generic extensions, and may be
declared in extensions (generic or not) for which the on-declaration
is generic.  The type parameters of a generic extension are in scope
in the declaration of a constructor declared in the extension.  For
example, the following code adds a new constructor to a generic
`Pair` type using an extension.

```dart
class Pair<S, T> {
  Pair(this.fst, this.snd);
  S fst;
  T snd;
}

extension FromList<T> on Pair<T, T> {
  Pair.fromList(List<T> l) => 
    switch(l) {
	   [var a, var b] => Pair(a, b),
       _              => throw "Expected a list of length 2"
	 }
}
```

Constructors defined on generic on-declarations may be invoked or torn
off using the on-declaration name, with or without providing type
arguments.  The number of type arguments if provided must match the
expected arity of the on-declaration, and if elided are reconstructed
using a type inference process described further below.

```dart
void test() {
  // A constructor provided by an extension may be invoked using the
  // on-declaration name and explicit type arguments.
  var p1 = Pair<int, int>.fromList([3, 4]);

  // A constructor provided by an extension may be torn off using the
  // on-declaration name and explicit type arguments.
  var f1 = Pair<int, int>.fromList;

  // A constructor provided by an extension may be invoked using the
  // on-declaration name with type arguments provided by inference.
  var p2 = Pair.fromList([3, 4]);
  
  // A constructor provided by an extension may be torn off using the
  // on-declaration name with type arguments provided explicitly.
  Pair<int, int> Function(List<int>) f2 = Pair<int, int>.fromList;

  // A constructor provided by an extension may be torn off using the
  // on-declaration name with type arguments provided by inference.
  Pair<int, int> Function(List<int>) f3 = Pair.fromList;

  // A constructor provided by an extension may be torn off using the
  // on-declaration name as a generic function.  Note that the type
  // arity of the generic function matches that of the extension,
  // not of the on-declaration
  Pair<T, T> Function<T>(List<T>) f4 = Pair.fromList;
}
```

Constructors defined in generic extensions may also be invoked using
the extension name, with or without providing type arguments.  The
number of type arguments if provided must match the expected arity of
the extension, and if elided are reconstructed using a type inference
process described further below.

```dart
void test() {
  // A constructor provided by an extension may be invoked using the
  // extension name and explicit type arguments.
  var p1 = FromList<int>.fromList([3, 4]);

  // A constructor provided by an extension may be torn off using the
  // on-declaration name and explicit type arguments.
  var f1 = FromList<int>.fromList;

  // A constructor provided by an extension may be invoked using the
  // on-declaration name with type arguments provided by inference.
  var p2 = FromList.fromList([3, 4]);
  
  // A constructor provided by an extension may be torn off using the
  // extension name with type arguments provided explicitly.
  Pair<int, int> Function(List<int>) f2 = FromList<int>.fromList;

  // A constructor provided by an extension may be torn off using the
  // extension name with type arguments provided by inference.
  Pair<int, int> Function(List<int>) f3 = FromList.fromList;

  // A constructor provided by an extension may be torn off using the
  // extension name as a generic function.  Note that the type
  // arity of the generic function matches that of the extension,
  // not of the on-declaration
  Pair<T, T> Function<T>(List<T>) f4 = FromList.fromList;
}
```

Semantically, a generic extension constructor can be thought of as a
generic method whose return type is given by the `on` type of the
extension and whose generic parameters are the generic parameters of
the extension declaration.  The `fromList` constructor defined above
is semantically equivalent to the following generic static method:
```dart
static Pair<T, T> fromList<T>(List<T> l) => 
  switch(l) {
    [var a, var b] => Pair(a, b),
    _              => throw "Expected a list of length 2"
  };
```

This correspondence is observable when the constructor is torn off
instead of invoked: the generic arity of the torn off function is the
arity of the extension, not the arity of the underlying
on-declaration.

Generic parameters on an extension can be used to define constructors
on generic classes which impose additional constraints beyond those
imposed by the original on-declaration.  For example, we might have a
class `SortedList<X>` where the regular constructors (in the class
itself) require an argument of type `Comparator<X>`, but an extension
provides an extra constructor that does not require the
`Comparator<X>` argument. This extra constructor would have a
constraint on the actual type argument, namely that it is an `X` such
that `X extends Comparable<X>`.

```dart
class SortedList<X> {
  final Comparator<X> _comparator;
  SortedList(Comparator<X> this._comparator);
  // ... lots of stuff that doesn't matter here ...
}

extension<X extends Comparable<X>> on SortedList<X> {
  SortedList.ofComparable(): this((X a, X b) => a.compareTo(b));
}
```

An extension can declare factories and redirecting generative
constructors, but it cannot declare a non-redirecting generative
constructor.

Constructors declared in extensions may not be used as
super-initializers, nor as targets of redirecting generative
constructors.


## Specification

### Definitions

In an extension declaration of the form `extension E<S1 .. Sj> on C
{...}` where `C` is an identifier (or an identifier with an import
prefix) that denotes a class, mixin, enum, or extension type
declaration, we say that the _on-declaration_ of the extension is `C`.
Here (and throughout) we includes the case that `j` is 0,
corresponding to an extension with no generic parameters.


If `C` denotes a generic class then `E` is treated as `extension E<S1
.. Sj> on C<T1 .. Tk> {...}` where `T1 .. Tk` are obtained by
instantiation to bound.

In an extension of the form `extension E<S1 .. Sj> on C<T1 .. Tk>
{...}`  where `C` is an identifier or prefixed identifier that denotes
a class, mixin, enum, or extension type declaration, we say that the
_on-declaration_ of `E` is `C`.

In an extension of the form `extension E<S1 .. Sj> on F<T1 .. Tk>
{...}` where `F` is a type alias whose transitive alias expansion
denotes a class, mixin, enum, or extension type `C`, we say that the
_on-declaration_ of `E` is `C`, and the declaration is treated as if
`F<T1 .. Tk>` were replaced by its transitive alias expansion.

In all other cases, an extension declaration does not have an
on-declaration.

For the purpose of identifying the on-declaration of a given
extension, the types `void`, `dynamic`, and `Never` are not considered
to be classes, and neither are record types or function types, with
the exception of the types `Record` and `Function`, which are
considered to be classes.

*Also note that none of the following types are classes:*

- *A type of the form `T?` or `FutureOr<T>`, for any type `T`.*
- *A type variable.*
- *An intersection type*.

*It may well be possible to allow record types and function types to be
extended with constructors that are declared in an extension, but this is
left as a potential future enhancement. It could be useful to be able to
denote a set of specific functions of a given type by declaring them as
static members of an extension on that function type.*


### Syntax

The grammar remains unchanged.

However, it is no longer an error to declare a factory constructor,
redirecting or not, or a redirecting generative constructor in an
extension declaration that has an on-declaration and both kinds can be
constant or not.

*Such declarations may of course give rise to errors as usual, e.g., if a
redirecting factory constructor redirects to a constructor that does not
exist, or there is a redirection cycle.*


### Static Analysis

The following sections specify the static analysis of static members
and constructors declared in extensions, along with their invocation
and the treatment of inference.

In addition to errors specified below, tools may choose to report
diagnostic messages like warnings or lints in certain situations. This
is not part of the specification, but here is one recommended message:

A compile-time diagnostic is emitted if an extension _D_ declares a
constructor or a static member with the same basename as a constructor or a
static member in the on-declaration of _D_.

*In other words, an extension should not have name clashes with its
on-declaration. The warning above is aimed at static members and
constructors, but a similar warning would probably be useful for name
clashes with instance members as well.*

#### Invocation of a static member

*The language specification defines the notion of a _member invocation_ in
the section [Member Invocations][], which is used below. This concept
includes method invocations like `e.aMethod<int>(24)`, property extractions
like `e.aGetter` or `e.aMethod` (tear-offs), operator invocations like
`e1 + e2` or `aListOrNull?[1] = e`, and function invocations like `f()`.
Each of these expressions has a _syntactic receiver_ and an _associated
member name_.  With `e.aMethod<int>(24)`, the receiver is `e` and the
associated member name is `aMethod`, with `e1 + e2` the receiver is `e1`
and the member name is `+`, and with `f()` the receiver is `f` and the
member name is `call`. Note that the syntactic receiver is a type literal
in the case where the member invocation invokes a static member. In the
following we will specify invocations of static members using this
concept.*

[Member Invocations]: https://github.com/dart-lang/language/blob/94194cee07d7deadf098b1f1e0475cb424f3d4be/specification/dartLangSpec.tex#L13903

Consider an expression `e` which is a member invocation with syntactic
receiver `E` and associated member name `m`, where `E` denotes an extension
in scope and `m` is a static member declared by `E`. We say that `e` is an
_explicitly resolved invocation_ of said static member of `E`.

*This can be used to invoke a static member of a specific extension in
order to manually resolve a name clash. At the same time, in Dart without
the feature which is specified in this document, this is the only way we
can invoke a static member of an extension (except when it is in scope, see
below), so it can also be useful because it avoids breaking existing code.*

In the following, we assume that `C` denotes a type introducing membered
declaration _D_ (that is, a class, a mixin class, a mixin, an enum, or an
extension type declaration). `C` may be a type identifier, or it may be of
the form `prefix.id` where `prefix` and `id` are type identifiers, `prefix`
denotes an import prefix, and `id` denotes said type introducing membered
declaration in the namespace of that prefix.

Consider an expression `e` which is a member invocation with syntactic
receiver `C` and an associated member name `m`. Assume that `m` is a static
member declared by _D_. The static analysis and dynamic semantics of this
expression is the same as in Dart before the introduction of this feature.

*In other words, existing invocations of static members will continue to
have the same meaning as they had before this feature was introduced.*

When _D_ declares a static member whose basename is the basename of `m`,
but _D_ does not declare a static member named `m` or a constructor named
`C.m`, a compile-time error occurs. *This is the same behavior as in
pre-feature Dart. It's about "near name clashes" involving a setter.*

In the case where _D_ does not declare any static members whose basename is
the basename of `m`, and _D_ does not declare any constructors named `C.m2`
where `m2` is the basename of `m`, let _M_ be the set containing each
accessible extension whose on-declaration is _D_, and whose static members
include one with the name `m`, or which declares a constructor named `C.m`.

*If _D_ does declare a constructor with such a name `C.m2` then the given
expression is not a static member invocation. This case is described in a
section below.*

Otherwise *(when _D_ does not declare such a constructor)*, an error occurs
if _M_ is empty, or _M_ contains more than one member.

*In other words, no attempt is made to disambiguate static member
invocations based on their signature or the on-type of the enclosing
extension declaration.*

Otherwise *(when no error occurred)* _M_ contains exactly one element.
Assume that it is an extension `E` that declares a static member named
`m`. The invocation is then treated as `E.m()` *(this is an explicitly
resolved invocation, which is specified above)*.

Otherwise *(when `E` does not declare such a static member)*, _M_ will
contain exactly one element which is a constructor named `C.m`. This is not
a static member invocation, and it is specified in a section below.

In addition to the member invocations specified above, it is also possible
to invoke a static member of the enclosing declaration based on lexical
lookup. This case is applicable when an expression in an extension
declaration resolves to an invocation of a static member of the enclosing
extension.

*There is nothing new in this treatment of lexically resolved invocations.*

#### Declarations of constructors in extensions

With this proposal, it is now supported to declare a constructor in an
extension, with the same syntax as in a class and in other type
introducing membered declarations.

*The semantic interpretation of constructors declared in extensions
follows closely from the informal interpretation given above in which
the constructor is viewed as a static method whose type parameters are
the type parameters of the extension in which it is declared
(including their bounds) and whose return type is the on-type of the
extension (which may contain references to said type parameters).*

It is a compile-time error to declare a constructor with no type
parameters in an extension whose on-type is not regular-bounded,
assuming that the type parameters declared by the extension satisfy
their bounds.

*There is nothing semantically problematic with such a constructor.
The semantic generic method to which it corresponds is well-defined
and statically valid.  However, constructors on classes can be assumed
to produce regular-bounded types, and so it seems reasonable to impose
the same discipline on constructors added via extensions.*

It is a compile-time error if an extension declares a generic constructor
which is non-redirecting and generative. *These constructors are only
supported inside the type introducing membered declaration of whose type
they are creating instances.*

It is a compile-time error to use a constructor declared in an
extension as the super-initializer of another constructor.

It is a compile-time error to use a constructor declared in an
extension as a the target of a redirecting generative constructor.

*A generative constructor declared in an extension must be
redirecting, and hence must eventually bottom out on a non-redirecting
generative contructor.  However, unlike in the case of a normal
redirecting constructor, the instance returned by a redirecting
constructor added in an extension may be more precise than the static
type given by the return type of the constructor.*

It is a compile-time error if an extension declaration _D_ declares a
generic constructor whose name is `C` (which includes declarations using
`C.new`) or `C.name` for some identifier `name`, if _D_ does not have an
on-declaration, or the name of the on-declaration is not `C`. Note that `C`
may be an identifier, or an identifier which is prefixed by an import
prefix.

If an extension declaration is generic, the type parameters declared
by the extension are in scope in any constructors declared in the
extension (just as with a constructor declared in a generic class).

If an extension declaration declares a factory constructor, then the
downwards context for the purposes of inference of the body of the
constructor (or for inferring the arguments to the redirectee in the
case of a redirecting factory constructor) is the on-type of the
extension.

*The on-type is well-formed within the scope of the body, since the
generic type parameters of the extension are in scope in the
constructor.*

If an extension declaration declares a redirecting generative
constructor, then the type arguments which are passed to the target of
the redirection are the type arguments of the on-type of the
extension.

*Unlike a redirecting generative constructor declared in a class, such
a constructor declared in an extension may impose additional
requirements on the actual type arguments provided to the target of
the redirection.*

It is a compile-time error if a redirecting factory constructor
declared in an extension has a redirection target which is not
assignable to the on-type of the extension (after inference has been
performed).

In addition, all of the usual compile-time errors associated with
declarations of redirecting factory constructors continue to apply.

*Inference is performed to reconstruct the type arguments, if any, for
the target of the redirecting factory constructor, and the target of
the redirection is checked for errors as usual.  In addition, the
post-inference return type of the target of the redirection must be a
type which is compatible with the return type of the constructor being
declared, which is given by the on-type of the extension.*

It is a compile-time error if a redirecting factory constructor
declared in an extension has a redirection target which is not
assignable to the on-type of the extension (after inference has been
performed).

*Inference is performed on the body of the factory constructor, and
the constructor is checked for errors as usual.  In addition, the
post-inference type inferred for the body of the constructor must be
compatible with the return type of the constructor being declared,
which is given by the on-type of the extension.*

#### On unnamed constructors.

For simplicity, and without loss of generality, the subsequent
sections assume that all constructor declarations, invocations and
references which use the unnamed syntax `C` have been replaced with
the canonical named form `C.new`.  That is, a declaration of a
constructor named `C` is treated as a declaration of a constructor
named `C.new` and an invocation `C(arguments)` or
`C<Types>(arguments)` is treated as an invocation of
`C.new(arguments)` or `C<Types>.new(arguments)` respectively.
Consequently in the sections below, we treat all constructors as
named, with the treatment of the unamed constructor falling out from
the treatment of the named constructor `C.new`.

Note however that explicit invocations of **extensions** do not admit
this treatment.  An instance extension `m` declared on an extension
`E` may be invoked explicitly on a receiver `o` using the syntax
`E(o).m`, which is not equivalent to `E.new(o).m` since the latter
denotes an invocation of a constructor declared on `E`, rather than an
explicit resolution of the instance member invocation of `m`.

#### Fully resolved invocations and references

Assume that `E` denotes an extension declaration _D_ with
on-declaration _D1_ named `C`, and assume that _D_ declares a
constructor whose name is `C.name`.

In that case an invocation of the form
`E<TypeArguments>.name(arguments)` or `E.name(arguments)` is a fully
resolved invocation of said constructor declaration, and a reference
of the form `E<TypeArguments>.name` or `E.name` is a fully resolved
reference of said constructor declaration.

*This just means that there is no doubt about which constructor declaration
named `C` respectively `C.name` is denoted by this invocation or reference.*

As usual, it is an error if type arguments are passed to an extension
and the extension either declares no type parameters, or if the number
of type parameters declared does not match the number of type
arguments, or if the type arguments do not match the declared bounds
of the type parameters.

If this invocation does not include actual type arguments and the
extension declares one or more type parameters then the invocation is
subjected to type inference to reconstruct the type arguments.

*Fully resolved invocations of and references to constructors declared
in extensions are not expected to be common in actual source
code. However, such invocations and references can be used in order to
resolve name clashes when multiple extensions are accessible and two
or more of them declare a constructor with the same name, or one
declares a constructor named `C.name` and another declares a static
member named `name`. Also, they define the semantics of extension
declared constructors with other forms, because those other forms are
reduced to the fully resolved form.*

#### Finding the fully resolved form of an invocation or reference.

Consider an instance creation expression of the form
`C<TypeArguments>.name(arguments)`, where `<TypeArguments>` may be
absent.  Or similarly, consider a constructor reference ("tearoff")
`C<TypeArguments>.name`, where `<TypeArguments>` may again be absent.
In either case, assume that `C` denotes a type introducing membered
declaration _D_ (where `C` may include an import prefix). Assume that
_D_ does not declare a constructor named `C.name`.

Let _M_ be the set of accessible extensions with on-declaration _D_
that declare a constructor named `C.name` or a static member named
`name`.

A compile-time error occurs if _M_ includes extensions with constructors as
well as static members.

Otherwise, if _M_ only includes static members then this is not an
instance creation expression, it is a static member invocation or
reference and it is specified in an earlier section.

Otherwise, _M_ only includes extensions containing constructors with
the requested name. A compile-time error occurs if _M_ is empty, or
_M_ contains two or more elements. Otherwise, the invocation or
reference denotes an invocation of or reference to the constructor
named `C.name` which is declared by the extension declaration that _M_
contains.

*Note that no attempt is made to determine that some constructors are "more
specific" or "less specific", it is simply a conflict if there are multiple
constructors with the requested name in the accessible extensions.*

Let `E` be the unique extension declaration that _M_ contains.  The
fully resolved form of the original invocation or reference is then
`E.name(arguments)` or `E.name`, respectively.

#### Type inference for constructor invocations with no provided type arguments.

Consider an instance creation expression of the form
`C.name(arguments)`, where `E.name(arguments)` is the fully resolved
invocation of the constructor.

*In the case that the invocation does not correspond to the invocation
of a constructor declared in an extension, there is no fully resolved
invocation and this section does not apply.*

Type inference for such an invocation is done by performing inference
on the fully resolved invocation `E.name(arguments)` as defined in the
subsequent section, using the same downwards context as the original
expression.

*Inference serves to find the type arguments (if any) that are missing
from the fully resolved invocation.  These arguments are what are
needed for subsequent static checking and for the dynamic
semantics. However, for the purposes of error reporting, it may be
useful to the user to report errors in terms of the original
syntactic form.  If `C` is a generic type, then the corresponding type
arguments for `C` can be obtained simply by substituting the inferred
type arguments to `E` for the type parameters of `E` in the on-type of
`E` (which by construction is an instantation of `C`).*

The static type of the constructor invocation in this case is the
fully instantiated on-type of `E` - that is, the on-type of `E` with
the inferred type arguments of the fully resolved invocation
substituted for the type parameters of `E`.

#### Type inference for constructor invocations with explicitly provided type arguments.

Consider an instance creation expression of the form
`C<TypeArguments>.name(arguments)`, where `E.name(arguments)` is the
fully resolved invocation of the constructor.

Type inference for such an invocation is done by performing inference
on the fully resolved invocation `E.name(arguments)` as defined in the
subsequent section, using `C<TypeArguments>` as the downwards context.

*As above, inference serves to find the type arguments that are
missing from the fully resolved invocation.  For the purposes of error
reporting, it may be more useful to the user to report errors in terms
of the invocation form using `C<TypeArguments>` as given in the
original program.*

The static type of the constructor invocation in this case is
`C<TypeArguments>`.

It is a static error if the fully instantiated on-type of `E` - that
is, the on-type of `E` with the inferred type arguments of the fully
resolved invocation substituted for the type parameters of `E` - is
not a subtype of `C<TypeArguments>`.

#### Type inference for fully resolved constructor invocations.

A fully resolved invocation of a constructor declared in an extension
where either the extension declares no type parameters, or where the
invocation has type arguments explicitly provided, is subject to no
further inference to reconstruct the type arguments.  Inference is
performed as usual on any arguments to the constructor with the
explicit type arguments used to instantiate the type parameters of the
extension.

If an extension declares type parameters and no type arguments are
provided to a fully resolved invocation, then inference is performed
as follows.  Let `K` be the downwards context of the invocation, and
let `R` be the on-type of the extension.  Inference is then performed
in exactly the same manner as an invocation of a static generic method
in context `K`, the type parameters of which are the type parameters of
the extension; the return type of which is `R`; and the parameter
types of which are the declared parameter types of the constructor.

*The treatment above follows directly from the semantic interpretation
of constructors declared in extensions as static members the generic
type parameters of which are those of the extension and the return
type of which is the on-type of the extension*.

The static type of the constructor invocation in this case is the
fully instantiated on-type of `E` - that is, the on-type of `E` with
the type arguments (inferred or provided) of the fully resolved
invocation substituted for the type parameters of `E`.

#### Type inference for constructor references with no provided type arguments.

Consider a constructor reference of the form `C.name`, where `E.name`
is the fully resolved reference to the constructor.

*In the case that the reference does not correspond to a reference to
a constructor declared in an extension, there is no fully resolved
reference and this section does not apply.*

Type inference for such a reference is done by performing inference on
the fully resolved reference `E.name` as defined in a subsequent
section, using the same downwards context as the original expression.

*Inference serves to find the type arguments (if any) that are missing
from the fully resolved reference.  These arguments are what are
needed for subsequent static checking and for the dynamic
semantics. However, for the purposes of error reporting, it may be
useful to the user to report errors in terms of the original syntactic
form.  If `C` is a generic type, then the corresponding type arguments
for `C` can be obtained simply by substituting the inferred type
arguments to `E` for the type parameters of `E` in the on-type of `E`
(which by construction is an instantation of `C`).*

The static type of the constructor reference in this case is the
static type of the fully resolved reference as determined a subsequent
section.

#### Type inference for constructor references with explicitly provided type arguments.

Consider a constructor reference of the form `C<TypeArguments>.name`,
where `E.name` is the fully resolved reference to the constructor.
Let `M` be the un-instantiated on-type of `E` and let `Signature` be
the parameter signature of E.name.

If `E` declares no type parameters, then no further inference is
required, and the static type of the reference is `C<TypeArguments>
Function(Signature)`.

It is a static error if `M` is not a subtype of `C<TypeArguments>`.

*In this case, there are no type parameters to solve for.  The type
through which the reference performed is used as the static return
type of the reference, and is required to be a supertype of the
on-type of the extension.*

Otherwise, let `TypeParameters1` be the type parameters declared by
`E`.  Type inference for the reference is performed by subtyping
matching `M <# C<TypeArguments>` solving for `TypeParameters1`.

*Inference use the explicitly given `TypeArguments` to constrain the
(possibly larger set of) type parameters of `E`, ignoring the
downwards context.  An equivalent but less direct formulation can be
obtained by performing downwards inference on the fully resolved
reference (as defined below) using a downwards context of `M
Function(Schema)` where `Schema` is the parameter signature of
`E.name` with all types replaced with `_`.*

Let `TypeArguments1` be the solution for `TypeParameters1` derived
above, let `M1` be `M` with `TypeArguments1` substituted for
`TypeParameters1` and let `Signature1` be `Signature` with
`TypeArguments1` substituted for `TypeParameters1`.

The static type of the constructor reference is `C<TypeArguments> Function(Signature1)`.

It is a static error if `M1` is not a subtype of `C<TypeArguments>`.

*In this case, we solve for the type parameters of `E` using only the
constraints induced by the explicitly provided type through which the
reference is performed.  The type through which the reference is
performed is used as the static return type of the reference, and is
required to be a supertype of the on-type of the extension after
substitution of the full set of derived arguments.*


#### Type inference for fully resolved constructor references.

Consider a fully resolved reference ("tearoff") of a constructor
declared in an extension.  We say that the "un-instantiated function
type" of the constructor reference is `M Function(Signature)` where
`M` is the un-instantiated on-type of the extension, and `Signature`
is the parameter signature of the constructor (that is, the types of
the positional parameters, and the types and names of the named
parameters).  Note that any type parameters declared by the extension
occur free in the un-instantiated function type of the constructor.
In the case that the extension declares type parameters
`TypeParameters`, we further say that the "fully generic function
type" of the constructor reference is `M
Function<TypeParameters>(Signature)`.

A fully resolved reference ("tearoff") with no type arguments
(`E.name`) to a constructor declared in an extension where the
extension declares no type parameters, is subject to no further
inference to reconstruct the type arguments.

The static type of such a reference is the un-instantiated function
type of the constructor reference.

*Constructors defined in non-generic extensions are treated as
non-generic functions when torn off.  Note that in this case, there
are no free type variables in the un-instantiated function type*

A fully resolved reference ("tearoff") with explicitly provided type
arguments (`E<TypeArguments>.name`) to a constructor declared in an
extension with type parameters `TypeParameters`, is subject to no
further inference to reconstruct the type arguments.

The static type of such a reference is the un-instantiated function
type of the constructor reference with `TypeArguments` substituted
throughout for `TypeParameters`.

*Constructors defined in generic extensions where explicit type
parameters are provided to the extension ("a partial instantiation")
are treated as non-generic functions when torn off, with the type
given by substituting in the provided type arguments for the type
parameters of the extension.*

If an extension declares type parameters `TypeParameters` and no type
arguments are provided to a fully resolved reference, then the context
type, if any, may induce implicitly provided type arguments as with
references to normal constructors ("an implicit partial
instantiation").  Coercion inference is performed using the downwards
context `K`, exactly as if the reference were to a function whose type
were the generic function type of the constructor reference (as
defined above).

If this coercion inference process results in type arguments being
inferred for the extension, then the static type of the reference is
the un-instantiated function type of the constructor reference with
`TypeArguments` substituted throughout for `TypeParameters`.

If this coercion inference process results in no type arguments being
inferred for the extension, then the static type of the reference is
the fully generic function type of the constructor reference.

*The treatment above follows directly from the semantic interpretation
of constructors declared in extensions as static members the generic
type parameters of which are those of the extension and the return
type of which is the on-type of the extension.  In the case that the
extension declares type parameters, the reference is subject to
coercion ("partial instantiation") as usual with a reference to a
generic function or constructor.*


## Dynamic Semantics

### Dynamic Semantics of static members of an extension

The dynamic semantics of static members of an extension is the same
as the dynamic semantics of other static functions.

### Dynamic Semantics of constructors defined in extensions

Declarations of constructors defined in extensions are semantically
treated as declarations of static methods with return type given by
the on-type of the extension; type parameters (if any) given by the
type parameters of the extension (including bounds); and parameter
signature as given in the declaration.

*That is, we treat a constructor declaration in an extension as an
ordinary static member of the extension by treating it as if both the
type parameters and the on-type of the extension were copied down onto
the declaration of the constructor to serve as the type parameters and
return type of the static member*

### Dynamic Semantics of constructor invocations and references

Every invocation and reference to a constructor defined in an
extension has a corresponding fully resolved form with all type
arguments (if any) fully determined as described in the static
semantics above.  The dynamic semantics of invocations and references
which are not originally provided in fully resolved form are entirely
defined by the dynamic semantics of the corresponding fully resolved
form.

#### Dynamic Semantics of fully resolved constructors

Invocations of fully resolved constructors are treated as invocations
of a static member as defined above.  If the extension (and hence the
induced static member representing the constructor) is generic, then
type arguments to the invocation are either taken from the original
invocation if provided explicitly (`E<Types>.name(arguments)`) or as
reconstructed via inference in the manner described above if not
provided explicitly (`E.name(arguments)`).

References to ("tearoffs") of fully resolved constructors are treated
as references to a static member as defined above.  If the extension
(and hence the induced static member representing the constructor) is
generic, then type arguments to the reference may be present coercing
it from a generic member to a non-generic member in the usual manner.
These type arguments may be taken from the original invocation if
provided explicitly (`E<Types>.name`) or as reconstructed via
inference in the manner described above if not provided explicitly
(`E.name`).  If the constructor is generic and no such coercion is
present, then the reference evaluates to a reference to a generic
static member as described above.


### Changelog

1.3 - Oct 15, 2025

* Specify constructors directly, without the extension to generic
  constructors

1.2 - Mar 5, 2025

* Change the text to rely on generic constructor declarations, rather
  than introducing a new mechanism which is only used with extensions.

1.1 - Aug 21, 2024

* Extensive revision of this document based on thorough review.

1.0 - May 31, 2024

* First version of this document released.
