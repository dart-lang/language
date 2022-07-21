# Overview of a proposal for structs

Author: Leaf Petersen

Status: In progress

Version 1.0 (see [CHANGELOG](#CHANGELOG) at end)

## Summary

This document is an overview of an approach to solving the following problems:
  - The desire for a zero cost wrapper type (motivated largely by interop
   concerns), described briefly
   [here](https://github.com/dart-lang/language/issues/1474)
  - The desire to have compact syntax for so called "data classes" or "value
types", discussed among other places
[here](https://github.com/dart-lang/language/issues/314)
  - The desire to have an accounting for data structures without identity as
    described [here](https://github.com/dart-lang/language/issues/2246).

The proposal here takes two steps.  The first is to add a restricted kind of
class (provisionally describe as a "struct" here), which gives up some of the
affordances of general Dart classes in exchange for compact syntax and automatic
generation of useful methods.  These restricted classes provide data class like
functionality.  The second step is to support a further restriction on structs
with a single field which eliminates the wrapper object, representing the struct
entirely as the underlying object (at the cost of making the abstraction
entirely static).

This proposal builds on previous proposals in this space, including:
  - [Views](https://github.com/dart-lang/language/blob/master/working/1426-extension-types/feature-specification-views.md)
  - [Extension types](https://github.com/dart-lang/language/blob/master/working/1426-extension-types/feature-specification.md)


This overview is not intended to be a feature specification: it is designed to
give a brief overview of the core proposal and set out some design points for
discussion.  If there is buy-in on these ideas, we may choose to incorporate
them into an existing proposal, or add a new feature specification.


## Design principles

We aim to minimize the differences between structs and classes.  As much as
possible, structs should behave as restrictions of classes.  We specifically aim
to avoid as much as possible having different behaviors for the same concept
(e.g. differences in scoping).

We also aim to minimize the amount of new syntax required, and to maximize the
amount of new functionality that we can provide relative to the syntactic real
estate consumed, and the new cognitive load imposed on users.

## Roadmap

The first section describes the full struct feature.  The second section
describes the restriction of the full struct to support static wrappers.

## Structs

This section describes how structs look and behave, largely by example.  In many
cases, alternatives or extensions to the core proposal are described in line.
Larger extensions are postponed to a later section.

### Introduction form

We add a new keyword "struct", which is used in place of "class".  The class
name (plus generics if applicable) must be followed by a parenthesized list of
field declarations (more on this below). There may optionally be an "extends"
clause, and an "implements" list.  No mixins are permitted.  After the header,
the usual brace delimited list of members may be provided subject to
restrictions described below.  An empty set of members may be elided in favor of
a semi-colon.  The simplest possible struct definitions then would look like:

```dart
struct Data();
struct GenericData<T>();
```

#### Alternatives


##### Re-use the class keyword

An alternative is to continue to use "class" and to use some other piece of
syntax to indicate that the object in question is not a general class.  For
example, the parenthesized list might be enough:


```dart
class Data();
class GenericData<T>();
```

Alternatively, an additional keyword could be used:

```dart
class Data wraps ();
class GenericData<T> wraps ();
```

Other keywords could be considered.

##### Choose a different leading keyword

Instead of "struct", we could use "view", or some other choice:

```dart
view Data();
view GenericData<T>();
```

##### Use a modifier on classes

We could, for example, use "data class":

```dart
data class Data();
data class GenericData<T>();
```

Another option would be "view class".


### Fields and primary constructors

The only new piece of syntax in this section of the proposal (other than the
"struct" keyword) is the primary constructor which follows immediately after the
class name + generics.  The primary constructor serves both to define the
fields, and to define the signature of the default generated constructor.

The primary constructor consists of a parenthesized list of comma separated
`<type> <identifier> (= <expression>)?` entries.  That is, a list of variable
declarations: with no modifiers; with types required; and with optional
initializer values.

Each entry in the list is a field in the struct.  Every field is implicitly
final.  They may not be late, and a type must be provided.

If an initializer is provided for an entry, all subsequent entries must also
have an initializer provided (see generated members below).

It is an error if two entries have the same name, and it is an error if one
entry consists of the name of another entry except prefixed with `_`.  That is,
all entries must be uniquely named after ignoring privacy.

Examples:

```dart
struct Data(int x, List<int> l = [3]);
struct GenericData<T>(T x, T y);
```

Ignoring generated members, these two structs are roughly equivalent to the
following classes:

```dart
class Data {
  int x;
  List<int> l = [3]
 }
class GenericData<T> {
 T x;
 T y;
 }

```

#### Alternative: Split into positional and named

We could choose to make this look more directly like a constructor argument list
by allowing "named" parameters inside of a brace delimited set.  These could
then become named parameters in the default constructor.

### Members of structs

A struct may contain static and instance member definitions in the same way as a
class, with exactly the same syntactic resolution.

For scope resolution purposes, entries in the primary constructor list are
treated exactly as if they were defined as instance members on the struct.

It is an error for a struct to define a field as a member.


### Abstract structs

Structs may be marked abstract, in which case no primary constructor may be
provided.  This is supported to allow families of structs sharing a common
super-interface which provides clean support for algebraic data types (see the
section on extension below).

### Extending structs

A struct may extend another struct from the same library.  It is an error if the
super-struct is not abstract.

```dart
abstract struct Foo {
  int foo() => 3;
}
struct Data(int x, List<int> l = [3]) extends Foo ;
struct GenericData<T>(T x, T y) extends Foo;
```

Members are inherited from super-structs as usual.

It is an error for a struct to extend a class.

It is an error for a struct to be extended outside of the defining library.

Extension is supported primarily to allow compact definition of algebraic
datatypes.  We expect that structs would be incorporated into switches with
extended exhaustiveness checking as proposed in the patterns proposal in the
obvious way.

### Implementing structs

It is an error to implement a struct.  Structs do not define interfaces.

### Structs implementing interfaces

Structs may implement interfaces, subject to the usual member conformance
checks.

### Semantics of structs

Modulo generated members (see below) and identity (see below), structs behave
semantically exactly as if they were de-sugared into classes in the obvious way.

### Identity of structs

The identity operator on structs *may* return `true` for structs which:
  - Have the same runtime type
  - Are pointwise identical on the fields in the primary constructor.

The identiity operator on structs may always return false.

In other words, the identity operator may be used as a "fast" cut-off for
equality, but compilers are free to box and unbox structs at will without
preserving identity.

The intention is that the identity operator should simply serve as a fast check
whether the two objects in question are "pointer equal", but it is valid for
compilers to make other choices based on implementation concerns, pragmas, etc.


### Generated members

An abstract struct has no generated members.  For non-abstract structs, the
following members are automatically derived by the compiler.

#### Default constructor

Every non-abstract struct defines a new private constructor with a hidden
compiler generated name.  We refer to this constructor as the *generated primary
constructor*.

The generated primary constructor has a single positional parameter for every
entry in the primary constructor list, each with the obvious type.

If any entry has an initializer value provided, then every entry after (and
including) that entry is an optional parameter with no default.

For every entry with an initializer value, if no argument is passed for that
parameter, the initializer value is assigned to that parameter in the
initializer list of the constructor.  Note that this requires the ability to
detect whether or not a parameter was passed, which is not expressible strictly
as a de-sugaring.

If no default constructor is defined in the class, a default constructor is
generated which forwards to the generated primary constructor.


##### Alternative: named parameters

These could be made named parameters.  This feels heavyweight, but has some
advantages.  The restriction on names in the primary constructor would allow us
to use the non-private versions of the field names as the parameter names.

#### Equality

If no equality method is defined in or inherited by the struct (except from
Object), then an equality method will be defined which checks that its argument
has the same runtime type as the receiver (actual runtime type, not the result
of calling "runtimeType"), and that the fields of the two objects are pointwise
equal.

#### hashCode

If no hashCode getter is defined in or inherited by the struct (except from
Object), then a hashCode getter will be defined which hashes the runtime type
(again, actual type) together with the hashes of each of the fields.

#### toString

If no toString method is defined in or inherited by the struct (except from
Object), then a toString method will be defined which returns "struct".

#### debugToString

If no debugToString method is defined in or inherited by the struct, then a
debugToString method will be defined which returns a formatted description of
the receiver, of the form `<type>(<f0>, ..., <f1>)` where `<type>` is the
runtime type of the receiver, and the `fi` are the result of calling
"debugToString" on the `i`th field if that field is (dynamically) a struct, and
otherwise the result of calling "toString".

#### copyWith

If no copyWith method is defined in or inherited by the struct, then a copyWith
method will be defined with named parameters for every entry in the primary
constructor.  For every entry, if the field name is not private, then the
parameter name is the field name.  If the field name is private, then the
parameter name is the field name with all leading `_`s removed.

The body of the method calls the generated primary constructor.  For every
argument which is explicitly passed to the copyWith method invocation, the
corresponding parameter is passed on as the argument to the corresponding
parameter of the generated primary constructor.  For every argument which is not
passed to the copyWith method invocation, the value of the corresponding field
from the current instance is passed on as the argument to the corresponding
parameter of the generated primary constructor.

#### Additional generated members

We may wish to also define additional generated members.  For example, we may
wish to have `parse` and `unParse` methods.  TODO(leafp): consider fleshing
something out here.


#### Restrictions

It is an error to override the "runtimeType" method of a struct.

It is an error to override the "noSuchMethod" method of a struct.


## Extension Structs

Extension structs are restrictions of the core struct feature, designed to
support wrapper-less views on an object.  This section describes how extension
structs look and behave, largely by example.  In many cases, alternatives or
extensions to the core proposal are described in line.


### Introduction form

Extension structs are defined by adding the keyword "extension" before a struct
definition.  The syntax for extension structs is otherwise exactly identical to
that of general structs.  However, extension structs are subject to additional
restrictions.  The most important of these is that extension structs may only
contain a single entry in their primary constructor.


```dart
extension struct Data(int x);
extension struct GenericData<T>(T y);
```


#### Alternatives

There are various alternatives for the core "struct" feature described in the
previous section, and any alternative choice made there would impact this
feature correspondingly.  Ignoring that, several alternative syntaxes for
extension structs are on the table.

##### Alternative modifiers

The choice of the keyword "extension" is intended to leverage users existing
intuitions about how extension methods work: that is, that they are largely
statically dispatched.  It's not clear to me that this intuition actually
carries over, however. There are various alternatives to "extension".

We could use "static", reflecting the static nature of the dispatch. 

```dart
static struct Data(int x);
static struct GenericData<T>(T y);
```

We could use "view" reflecting the fact that we are presenting a "view" on an object.

```dart
view struct Data(int x);
view struct GenericData<T>(T y);
```

We could use "typedef" reflecting the fact that we are largely defining a static
construct:

```dart
typedef struct Data(int x);
typedef struct GenericData<T>(T y);
```

We could use "type", or "new type".


### Fields and primary constructors

Primary constructor lists for extension structs are exactly identical to those
of normal structs, with the restriction that they may contain only one entry.

Examples:

```dart
extension struct Data(int x);
extension struct GenericData<T>(T y);
```

### Members of extension structs

An extension struct may contain static and instance member definitions in the
same way as a class, with exactly the same syntactic resolution.

For scope resolution purposes, entries in the primary constructor list are
treated exactly as if they were defined as instance members on the extension
struct.

It is an error for an extension struct to define a field as a member.

It is an error if an extension struct declares an abstract member, unless a
member of the same name and kind is available on the unique field of the
extension struct, and the type of the abstract member is a supertype of the type
of the corresponding member in the unique field.

### Abstract extension structs

Extension structs may not be be marked abstract.

### Extending extension structs

An extension struct may not be extended.

### Implementing extension structs

It is an error to implement an extension struct.  Extension structs do not
define interfaces.

### Using extension structs as a bound

It is an error to use the type defined by an extension struct as a bound on a
generic type parameter.

### Extension structs implementing interfaces

Extension structs may implement interfaces if and only if each implemented
interface type is a subtype of the type of the unique field in the primary
constructor list.  That is, implemented interfaces must be implemented *by the
field*, which will serve as the underlying object representation.

An extension struct is a subtype of each of its implemented super-interfaces.

An extension struct implements Object.

It is an error if any member of an implemented interface has a non-abstract
definition in the body of the extension struct.  (This is to avoid the confusing
behavior that would result from different dispatch behavior depending on whether
the member is accessed via the extension struct interface, or via the
implemented super-interface).



### Semantics of extension structs

Extension structs have no representation at runtime.  The values of an extension
struct type are the values of the single unique field in the extension struct.
We refer to this unique field in the following section as the "underlying
representation" of the extension struct.

### Identity of extension structs

The identity operator on an instance of an extension struct is defined to return
the same value as applying the identity operator to the underlying
representation of the extension struct.

### Semantics of members of extension structs

Members of extension structs are statically dispatched.  That is, any member
defined in the body of the extension is only reachable via invoking the member
name on a value of the static type of the extension struct, and the member which
is invoked is always exactly that which is defined in the extension struct.

Abstract members of extension structs delegate directly to member on the
underlying representation.

For every member in the combined super-interface of an extension struct, the
extension struct is treated as defining a member whose signature is given by the
combined super-interface, and which delegates to the underlying representation.


### Reification

The type introduced by an extension struct is entirely static, and is replaced
at runtime by the type of the unique field in the extension struct.  All
runtime instance tests and casts are done using the resulting erased type.

### Generated members

For extension structs, the following members are automatically derived by the
compiler.

#### Default constructor

The default generated constructor for an extension struct is simply a degenerate
single field version of the standard default generated constructor defined for a
normal struct.


#### Equality

Equality delegates to the underlying representation.

#### hashCode

The hashCode getter delegates to the underlying representation.

#### toString

The toString method delegates to the underlying representation.

#### debugToString

If no debugToString method is defined in the extension struct, then a
debugToString method will be defined which returns a formatted description of
the receiver, of the form `<type>(<f0>, ..., <f1>)` where `<type>` is the
extension struct type via which the receiver is called, and the `fi` are the
result of calling "debugToString" on the `i`th field if that field is
(dynamically) a struct, and otherwise the result of calling "toString".

#### copyWith

No copyWith method is generated for an extension struct.

#### Restrictions

It is an error to define any of the object members in the extension struct.





## Changelog
