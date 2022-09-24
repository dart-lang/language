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

The proposal here takes two steps.
  - The first is to add a restricted kind of class (provisionally describe as a
"struct" here), which gives up some of the affordances of general Dart classes
in exchange for compact syntax and automatic generation of useful methods.
These restricted classes provide data class like functionality: they are
immutable, they have structural identity, and they get a number of conveniently
auto-generated methods.
  - The second is to support a further restriction on structs with a single
field which eliminates the wrapper object, representing the struct entirely as
the underlying object (at the cost of making the abstraction entirely static).

This proposal builds on previous proposals in this space, including:
  - [Views](https://github.com/dart-lang/language/blob/master/working/1426-extension-types/feature-specification-views.md)
  - [Extension types](https://github.com/dart-lang/language/blob/master/working/1426-extension-types/feature-specification.md)
  - [Protected extension types](https://github.com/dart-lang/language/issues/1467)

This overview is not intended to be a feature specification: it is designed to
give a brief overview of the core proposal and set out some design points for
discussion.  If there is buy-in on these ideas, we may choose to incorporate
them into an existing proposal, or add a new feature specification.


## Design principles

We aim to minimize the differences between structs and classes.  As much as
possible, structs should behave as restrictions of classes, and extension
structs should behave as further restrictions of structs.  We specifically aim
to avoid as much as possible having different behaviors for the same concept
(e.g. differences in scoping).

We also aim to minimize the amount of new syntax required, and to maximize the
amount of new functionality that we can provide relative to the syntactic real
estate consumed, and the new cognitive load imposed on users.

Concretely for the purposes of this proposal, we have started with the following
goals:
  - If a struct or an extension struct `B` says that it `implements` or
    `extends` `A`, then:
    - It should be the case that `B` is a subtype of `A`
    - It should be the case that `B` has a superset of the method
      names/signatures of `A`
    - It should be the case that assigning an instance of `B` to a location of
      type `A`, while it may change the set of members available, should not
      change the dispatch of any members (that is, if `f` is available on `B`,
      then calling `f` through either interface reaches the same code).


It is not clear that all of these goals can be met while meeting requirements.
In particular, the last goal is incompatible with overriding methods, given our
intended semantics, and it is likely that allowing some form of overriding is a
requirement.

## Roadmap

The first section describes the full struct feature.  The second section
describes the restriction of the full struct to support static wrappers.

## Structs

This section describes how structs look and behave, largely by example.  In many
cases, alternatives or extensions to the core proposal are described in line.
Larger extensions are postponed to a later section.

## Structs by example

Structs allow you to define simple classes containing immutable data very
compactly.  For example, we might model a component vector as follows:

```
struct Component(int x, int y, int z, int w = 1);
```

This short definition essentially defines a class `Component`, with four fields,
and provides a number of convenient methods.

```dart
void test() {
  // Call the default constructor, using the default value for w
  var c1 = Component(0, 0, 0);
  // Call the default constructor, explicitly passing w
  var c2 = Component(0, 0, 0, 1);

  assert(c1 == c2); // Equality is defined to be structural
  assert(c1.hashCode == c2.hashCode); // With correspondind hashCode

  print(c1.debugToString()); // Prints "Component(0, 0, 0, 1)"

  print(c1.toString()); // Prints "struct"

  // Generated copy method
  var c2 = c1.copyWith(x : 2);
  assert(c2.x == 2);
}
```

Structs may explicitly define constructors, static members, and normal class
members (except fields), and may implement interfaces.  All fields must be
declared in the header (the "primary constructor"), and are implicitly final
(making all structs shallowly immutable).  Fields may be marked as private as
usual by naming them with a leading `_` in their name.

```dart
struct Component(int _x, int _y, int _z, int _w = 1)
  implements Comparable<Component> {

  double get x => _x/_w;
  double get y => _x/_w;
  double get z => _z/_w;

  int compareTo(Component other) => throw "TODO: Unimplemented";

  Component.zero() : _x = 0, _y = 0, _z = 0;
}
```

With the addition of pattern matching and switches, structs will support closed
families (algebraic datatypes).

```dart
abstract struct Operand;

struct ConstantOperand(Value c) extends Operand;

struct IdentifierOperand(Identifier i) extends Operand;

Operand replaceIn(Operand oper, Identifier t, Value c) {
  return switch (oper) {
    case ConstantOperand(_) : oper;
    case IdentifierOperand(var i) where i == t: ConstantOperand(c);
    case IdentifierOperand(_) : oper;
  }
}
```

## Structs in more detail

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


We could use "data class":

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

**COMMENTARY(leafp):** *The restriction to final fields is both because that's
  the common use case, and because structural identity doesn't make much sense
  if we allow them to be mutable.  We could potentially box each mutable field
  into heap allocated ref cell but that feels very unpleasant, and has perf
  implications that don't match the intended use cases. *

If an initializer is provided for an entry, all subsequent entries must also
have an initializer provided (see generated members below).

**COMMENTARY(leafp):** *This is to allow initializers to double as default
  values for the generated constructor.  This may be too cute.  Alternatively we
  could forbid initializers, or just make fields with initializers not available
  to the constructor (as with a normal class)*

It is an error if two entries have the same name, and it is an error if one
entry consists of the name of another entry except prefixed with `_`.  That is,
all entries must be uniquely named after ignoring privacy.

**COMMENTARY(leafp):** *This is to allow us to use the non-private version of
  the name as a named parameter in methods*

Examples:

```dart
struct Data(int x, List<int> l = [3]);
struct GenericData<T>(T x, T y);
```

Ignoring generated members, these two structs are roughly equivalent to the
following classes:

```dart
class Data {
  final int x;
  final List<int> l = [3]
 }
class GenericData<T> {
 final T x;
 final T y;
 }

```

#### Alternative: Split into positional and named

We could choose to make this look more directly like a constructor argument list
by allowing "named" parameters inside of a brace delimited set.  These could
then become named parameters in the default constructor.  Example:

```
struct Component(int x, int y, int z, {int w = 1});

void test() {
  // Call the default constructor, using the default value for w
  var c1 = Component(0, 0, 0);
  // Call the default constructor, explicitly passing w
  var c2 = Component(1, 1, 1, w: 1);
...
}
```

#### Alternative: no primary constructors

We could choose to make the field declarations look exactly like classes instead
of using a primary constructor syntax.


```
struct Component {
  int x;
  int y;
  int z;
  int w = 1;
}
```

**COMMENTARY(leafp):** *Given the constraint that structs are immutable, I don't
  like that `int x` here means a different thing than it does in a class (since
  it is implicitly final).  We could therefore require each one to be written as
  `final int x` and make it an error to have a non-final variable.  This feels
  very boilerplate-heavy to me relative to the compact one line form.*



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

**COMMENTARY(leafp):** *We could possibly allow hierarchies of abstract
  super-structs.  We could also potentially allow super-structs to define
  fields, which would be treated as abstract fields which the sub-structs must
  provide*


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

It is an error for a struct to extend a class, except Object.

It is an error for a struct to be extended outside of the defining library.

It is an error for a struct to be extended by a class.

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

The identity operator on structs *may* return `true` for structs such that:
  - Both have the same runtime type
  - For every pair of corresponding fields, identical could validly return true
    on that pair.

The identity operator on structs may always return false.

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

**Note that initializers are not required to be constant, so this de facto adds
  non-const default values in a very limited case.**

If no default constructor is defined in the class, a default constructor is
generated which forwards to the generated primary constructor.

**COMMENTARY(leafp):** *The treatment of initializers as default values here is
  appealing, but it may be too cute.  It essentially adds non-const default
  values only for this specific use case.  There's also a question of whether we
  allow user defined constructors on the struct to also override the default
  initializer, and if so via what syntax*.


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

**COMMENTARY(leafp):** *This needs a bit of work.  If we keep the dynamic check
  for "struct-ness", then we need do deal with the case that the user defines a
  debugToString thing with the wrong type*.

**COMMENTARY(leafp):** *If we keep this, we may wish to specify that compilers
  may choose to make it a link time error to have an invocation of debugToString
  in the program outside of asserts, and other debugToString methods*.


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

**COMMENTARY(leafp):** *As with constructors, this method cannot be generated as
  a strict de-sugaring, since the ability to detect whether or not an argument
  has been passed is not available in Dart.  Implementations already support
  this for default values, so it is likely not problematic to implement*.


#### Additional generated members

We may wish to also define additional generated members.  For example, we may
wish to have `parse` and `unParse` methods.  TODO(leafp): consider fleshing
something out here.


#### Restrictions

It is an error to override the "runtimeType" method of a struct.

It is an error to override the "noSuchMethod" method of a struct.

### Const structs

TODO(leafp): This should work, write out the details.

## Extension Structs

Extension structs are restrictions of the core struct feature, designed to
support wrapper-less views on an object.  This section describes how extension
structs look and behave, largely by example.  In many cases, alternatives or
extensions to the core proposal are described in line.

## Extension structs by example

Extension structs are targeted at relatively niche uses where you wish to define
a set of statically dispatched methods layered on top of an underlying
representation, without introducing a wrapper object.  A canonical use case
driving this design is to be able define a Dart typed interface for methods on a
Javascript object, providing a wrapperless interoperation capability.


```dart
extension struct Window(JSObject o) {
  // Signatures provided here for methods to be delegated to the underlying
  // JSObject
  external bool get closed;
  // etc
}

void test(Window w) {
  // Window methods can be called using Dart syntax
  if (w.closed) {...}

  // Windows are represented as the underlying object
  assert(w is JSObject);

  // Windows can be cast to the underlying object
  JSObject o = w as JSObject;

  // Extension struct types are reified as the underlying representation type.
  List<Window> l = [w];
  assert(l is List<JSObject>);
}
```

Extension structs are also useful for providing a lightweight facade over an
existing type.

```dart
// Natural numbers
extension struct Nat(int _x) {
  Nat(int x) : assert(x >= 0), _x = x;
  Nat.zero() : _x = 0;

  Nat get succ => Nat(_x+1);
  Nat plus(Nat other) => Nat._x + other._x;

  // Override the underlying isNegative operation (incorrectly)
  bool get isNegative => true;
}

void test() {
  var n1 = Nat(3);
  var n2 = Nat.zero();
  assert(n2.succ.succ.succ == n2);

  //The underlying representation is still as an int
  assert(n1 is int);

  // The static type is used to dispatch the method calls
  assert(n1.isNegative);

  // If the static type is lost, dispatch goes to the underlying object.
  dynamic d = n1;
  assert(!d.isNegative);
}
```

Extension structs may delegate members to the underlying field.  They may also
implement interfaces, but only if the underlying field implements the interface.

```dart
// Natural numbers
extension struct Nat(int _x) implements Comparable<num> {
  // Constructors etc as above


  bool get isEven;  // Abstract definition delegates to _x.isEven
}

void test() {
  var n = Nat(2);
  // Same as 2.isEven
  assert(n.isEven);
  // Comparable interface allows access to the Comparable methods on int
  assert(n.compareTo(2) == 0);

  // Since Nat implements Comparable<num>, it may be assigned to it
  Comparable<num> c = n;
  // The representation is still as an integer
  assert(c is int);
}
```

Extension structs have no inheritance.

```dart
// Static error
extension struct PositiveNumber(int _x) extends Nat {...}
```

Extension structs do not define a signature, and hence cannot be implemented.

```dart
// Static error
extension struct AlternativeNat(int _x) implements Nat { ...}

// Static error
class MockNat implements Nat {...}
```

Extension structs can define their own constructors as usual, replacing or
adding to the generated constructors.

```dart
extension struct Window(JSObject o) {
  Window.cons() : o = Window(js_util.callConstructor(...));
}
```

## Extension structs in more detail


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

**COMMENTARY(leafp):** *The point here is that the actual runtime representation
  of the extension struct will simply be the value of the single unique field,
  with no wrapper object*.


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

**COMMENTARY(leafp):** *Abstract members here allow delegation of methods
  without having to write an explicit forward.  We could elide this*.


### Abstract extension structs

Extension structs may not be be marked abstract.

### Extending extension structs

An extension struct may not be extended.

**COMMENTARY(leafp):** *This may be contentious.  If we end up needing some form
  of inheritance, either to build up a subtype hierarchy or to allow code
  re-use, there are probably paths we can take here, but it will be important
  for the purposes of this design to keep this consistent with the behavior of
  general structs*.

### Implementing extension structs

It is an error to implement an extension struct.  Extension structs do not
define interfaces.

### Using extension structs as a bound

It is an error to use the type defined by an extension struct as a bound on a
generic type parameter.

**COMMENTARY(leafp):** *This is probably harmless, maybe we should allow it*.

### Extension structs implementing interfaces

Extension structs may implement interfaces if and only if each implemented
interface type is a supertype of the type of the unique field in the primary
constructor list.  That is, implemented interfaces must be implemented *by the
field*, which will serve as the underlying object representation.

**COMMENTARY(leafp):** *The driving motivation for this design choice is keep
  the behavior of extension structs consistent with general structs.  For
  general structs and classes, implementing an interface means that the newly
  defined type is both a subtype of that interface, and supports all of the
  methods of that interface.  If we wish to preserve the former for extension
  structs, then we must ensure that the underlying representation object also
  implements the same interface, so that when we assign it, we do not break
  soundness.  We could give up on fully subtyping and instead only allow
  assignability, with conversion to the implemented interface requiring boxing,
  but I have chosen not to do that, since it still makes subtyping unavailable.
  That is, under this proposal, for an extension struct Foo that implements Bar,
  `Foo` is assignable to `Bar` with no boxing, and `List<Foo>` is assignable to
  `List<Bar>`.  If we auto-boxed on assignment to `Bar`, we could preserve the
  former, but not the latter*.

An extension struct is a subtype of each of its implemented super-interfaces.

An extension struct implements Object.

It is an error if any member of an implemented interface has a non-abstract
definition in the body of the extension struct.

**COMMENTARY(leafp):** *This restriction is to avoid the confusing behavior that
  would result from different dispatch behavior depending on whether the member
  is accessed via the extension struct interface, or via the implemented
  super-interface.  That is `Foo` is an extension struct that implements
  `Comparable<Foo>` and defines its own `compareTo` method, then accessing the
  compareTo method on a value of type `Foo` will call a different method than
  first assigning the value to a variable of type `Comparable<Foo>` and then
  calling the method.  It may be that it is too important to support
  "overriding" here though, and so we may need to relax this restriction.*



### Semantics of extension structs

Extension structs have no representation at runtime.  The values of an extension
struct type are the values of the single unique field in the extension struct.
We refer to this unique field in the following section as the "underlying
representation" of the extension struct.

### Identity of extension structs

The identity operator on an instance of an extension struct is defined to return
the same result as applying the identity operator to the underlying
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
the receiver, of the form `<type>(<f0>)` where `<type>` is the extension struct
type via which the receiver is called, and `<f0>` is the result of calling
"debugToString" on the unique field if that field is (dynamically) a struct, and
otherwise the result of calling "toString".

#### copyWith

No copyWith method is generated for an extension struct.

#### Restrictions

It is an error to define any of the object members in the extension struct.

**COMMENTARY(leafp):** *This restriction is to avoid the same confusing behavior
  described above in the section on implementing interfaces.  Almost all uses of
  `hashCode` will be done via the `Object` interface, and it seems dangerous to
  allow users to define a `hashCode` getter that will be ignored when the value
  is used as (e.g.) a key in a map.*


### Const extension structs

TODO(leafp): This should work, write out the details.

## Extensions to the core proposal

### Allow abstract fields in abstract super-structs

We could choose to allow abstract structs to define a subset of the fields in a
primary constructor, interpreting them as abstract fields.  e.g.

```dart
abstract struct ColorPoint(int color);
struct ColorPoint2D(int color, int x, int y) extends ColorPoint;
```

would be roughly equivalent to:

```dart
abstract class ColorPoint {
  abstract int color;
}

class ColorPoint2D extends ColorPoint{
  final int color;
  final int x;
  final int y;
  ColorPoint2D(this.color, this.x, this.y);
  // More generated methods here
}
```

### Allow concrete super-structs

We could allow extending concrete structs. 

```dart
abstract struct ColorPoint(int color);
struct ColorPoint2D(int color, int x, int y) extends ColorPoint;
struct ColorPoint3D(int z) extends ColorPoint2D;
```

which would be roughly equivalent to:

```dart
abstract class ColorPoint {
  abstract int color;
}

class ColorPoint2D extends ColorPoint{
  final int color;
  final int x;
  final int y;
  ColorPoint2D(this.color, this.x, this.y);
  // More generated methods here
}

class ColorPoint3D extends ColorPoint2D {
  final int z;
  ColorPoint3D(super.color, super.x, super.y, this.z);
  // More generated methods here
}
```

**COMMENTARY(leafp):** *I would prefer, at least as a starting point, to forbid
  overriding of the fields in sub-structs, to make it easier to compile structs
  to something with a predictable memory layout.  For the same reason, I would
  propose to continue to treat these as non-extensible outside of the defining
  library*

### Allow extension structs to extend other extension structs

To support non-trivial subtyping hierarchies using extension structs, we could
choose to allow extension structs to extend other extension structs, subject to
the requirement that the field type remains the same.

```dart
extension struct Nat(int _x) {
  Nat(int x) : assert(x >= 0), _x = x;
  Nat.zero() : _x = 0;

  Nat get succ => Nat(_x+1);
  Nat plus(Nat other) => Nat._x + other._x;

}

extension struct Pos extends Nat {
  Pos(int x) : assert(x >= 1), super(x);
}
```

The semantics of extension would be, as with `implements`, that all methods on
the super-struct type are statically available on the sub-struct, but no
overriding is allowed.

### Allow extension structs to extend other extension structs and refine the
    type.

We could choose to allow extension structs to require a more specific type for
the unique field.

```dart
extension struct Number(num _x);
extension struct Integer(int _x) extends Number;
```

### Allow extension structs to provide overriding implementations of implemented
    or extended members

The core proposal forbids overriding, to avoid the surprising behavior where the
same object resolves methods differently depending on the static type.  We could
choose to relax this, at the cost of some surprising behavior.

```dart
extension struct EvenInteger(int x) {
    bool get isEven => true;
}
// Truly odd integers.
extension struct OddInteger(int x) extends EvenInteger {
    bool get isEven => false;
}

void test() {
  OddInteger i = OddInteger(2);
  assert(!i.isEven); // Dispatch goes to OddInteger.isEven
  EvenInteger e = i; // Ok
  assert(i.isEven); // Dispatch goes to EvenInteger.isEven
}
```

**COMMENTARY(leafp):** *We could in principle not enforce the usual subtyping
  constraints on overriding, but in practice I think this should be done.*

### Define an implicit boxed version of extension structs

The close correspondence between structs and extension structs suggests the
possibility of saying that every `extension struct` declaration implicitly
defines a corresponding `struct` declaration, which behaves exactly as if the
same declaration had been made except with the `extension` prefix removed.  For
an extension struct `Foo`, we might choose to name these implicit types as
`Foo.struct`.

```dart
extension struct Nat(int _x) {
  Nat(int x) : assert(x >= 0), _x = x;
  Nat.zero() : _x = 0;

  Nat get succ => Nat(_x+1);
  Nat plus(Nat other) => Nat._x + other._x;

  // Override the underlying isNegative operation (incorrectly)
  bool get isNegative => true;
}

void test() {
  Nat n = Nat(2);
  n.succ(); // Returns Nat(3)
  // (n as dynamic).succ(); // noSuchMethod
  assert(n.isNegative);

  int i = n as int; // Succeeds
  assert(!i.isNegative); // Dispatch goes to the integer method

  // Nat.struct is the type which would be defined by the same struct
  // definition above, with the extension prefix removed.
  Nat.struct b = n.struct;
  b.succ(); // Returns Nat(3)
  (b as dynamic).succ(); // Returns Nat(3)
  assert(b.isNegative);

  // int i = n as int; // Case fails
}
```


## Changelog
