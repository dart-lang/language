# Records Feature Specification

Author: Bob Nystrom

Status: In progress

Version 1.2 (see [CHANGELOG](#CHANGELOG) at end)

## Motivation

When you want to bundle multiple objects into a single value, Dart gives you a
couple of options. You can define a class with fields for the values. This works
well when you also have meaningful behavior to attach to the data. But it's
quite verbose and it means any other code using this bundle of data is now also
coupled to that particular class definition.

You can wrap them in a collection like a list, map, or set. This is lightweight
and avoids bringing in any coupling other than the Dart core library. But it
does not work well with the static type system. If you want to bundle a number
and a string together, the best you can do is a `List<Object>` and then the type
system has lost track of how many elements there are and what their individual
types are.

You've probably noticed this if you've ever used `Future.wait()` to wait on a
couple of futures of different types. You end up having to cast the results back
out since the type system no longer knows which element in the returned list has
which type.

This proposal, part of the larger "tuples, records, and pattern matching" family
of features, adds **records** to Dart. Records are an anonymous immutable
aggregate type. Like lists and maps, they let you combine several values into a
single new object. Unlike other collection types, records are fixed-sized,
heterogeneous, and typed. Each element in a record may have a different type and
the static type system tracks them separately.

Unlike classes, records are *structurally* typed. You do not have to declare a
record type and give it a name. If two unrelated libraries create records with
the same set of fields, the type system understands that those records are the
same type even though the libraries are not coupled to each other.

## Introduction

Many languages, especially those with a static functional heritage, have
**[tuple][]** or **product** types:

[tuple]: https://en.wikipedia.org/wiki/Product_type

```dart
var tuple = ("first", 2, true);
```

A tuple is an ordered list of unnamed positional fields. These languages also
often have **record** types. In a record, the fields are unordered, but named:

```dart
var record = (number: 123, name: "Main", type: "Street");
```

In Dart, we merge both of these into a single construct, called a **record**. A
record has a series of positional fields, and a collection of named fields:

```dart
var record = (1, 2, a: 3, b: 4);
```

Very much like an argument list to a function call both in syntax and semantics.
A given record may have no positional fields or no named fields, but cannot be
totally empty. (There is no "unit type".)

A record expression like the above examples produces a record value. This is a
first-class object, literally a subtype of Object. Its fields cannot be
modified, but may contain references to mutable objects. It implements
`hashCode` and `==` structurally based on its fields to provide value-type
semantics.

## Core library

These primitive types are added to `dart:core`:

### The `Record` class

A built-in class `Record` with no members except those inherited from `Object`.
This type cannot be constructed, extended, mixed in, or implemented by
user-defined classes. *It's similar to how the `Function` class is the
superclass for function types.*

### The `Destructure<n>` types

A number of destructuring interfaces are added, whose definitions look like:

```dart
abstract class Destructure1<T0> {
  T0 get field0;
}

abstract class Destructure2<T0, T1> {
  T0 get field0;
  T1 get field1;
}

abstract class Destructure3<T0, T1, T2> {
  T0 get field0;
  T1 get field1;
  T2 get field2;
}

...

abstract class Destructure16<T0, T1, T2, ..., T15> {
  T0 get field0;
  T1 get field1;
  T2 get field2;
  ...
  T15 get field15;
}
```

These classes cannot be extended or mixed in, but can be implemented.

## Syntax

### Record expressions

A record is created using a record expression, like the examples above. The
grammar is:

```
// Existing rule:
literal      ::= record
                 | // Existing literal productions...
record       ::= '(' recordField ( ',' recordField )* ','? ')'
recordField  ::= (identifier ':' )? expression
```

This is identical to the grammar for a function call argument list. There are a
couple of syntactic restrictions not captured by the grammar. A parenthesized
expression without a trailing comma is ambiguously either a record or grouping
expression. To resolve the ambiguity, it is always treated as a grouping
expression.

It is a compile-time error if a record has any of:

*   the same field name more than once.

*   a field name that collides with the implicit name defined for a
    positional field (see below).

*   a field named `hashCode`, `runtimeType`, `noSuchMethod`, or `toString`.

**TODO: Can field names be private? If so, are they actually private?**

### Record type annotations

In the type system, each record has a corresponding record type. The grammar for
record type annotations is:

```
// Existing rule:
typeNotVoidNotFunction ::= typeName typeArguments? '?'?
                         | 'Function' '?'?
                         | recordType // New production.

recordType             ::= '(' recordTypeFields ','? ')'
                         | '(' ( recordTypeFields ',' )?
                               recordTypeNamedFields ')'
                         | recordTypeNamedFields

recordTypeFields       ::= type ( ',' type )*

recordTypeNamedFields  ::= '{' recordTypeNamedField
                           ( ',' recordTypeNamedField )* ','? '}'
recordTypeNamedField   ::= type identifier
```

This is somewhat similar to a parameter list. You have zero or more positional
fields where each field is a type annotation:

```dart
(int, String, bool) triple;
```

Then an optional brace-delimited section for named fields. Each named field is
a type and name pair:

```dart
({int n, String s}) pair;
```

A record type can have both positional and named fields:

```dart
(bool, num, {int n, String s}) quad;
```

If there are only named fields, you are allowed to omit the surrounding
parentheses:

```dart
{int n, String s} pair;
```

Like record expressions, a record type must have at least one field.

Unlike expressions, a trailing comma is not required in the single positional
field case. `(int)` is a valid record type and is distinct from the type `int`.

It is a compile-time error if two record type fields have the same name or if
a named field collides with the implicit name of a positional field.

## Static semantics

We define **shape** to mean the number of positional fields (the record's
**arity**) and the set of names of its named fields. Record types are
structural, not nominal. Records produced in unrelated libraries have the exact
same static type if they have the same shape and their corresponding fields have
the same types.

The order of named fields is not significant. The record types `{int a, int b}`
and `{int b, int a}` are identical to the type system and the runtime. (Tools
may or may not display them to users in a canonical form similar to how they
handle function typedefs.)

### Members

A record type declares all of the members defined on `Object`. It also exposes
getters for each named field where the name of the getter is the field's name
and the getter's type is the field's type.

In addition, for each positional field, the record type declares a getter named
`field<n>` where `<n>` is the number of preceding positional fields and where
the getter's type is the field's type.

For example, the record expression `(1, s: "string", true)` has a record type
whose signature is like:

```dart
class {
  int get field0;
  String get s;
  bool get field1;
}
```

### Subtyping

The class `Record` is a subtype of `Object` and `dynamic` and a supertype of
`Never`. All record types are subtypes of `Record`, and supertypes of `Never`.

A record type `A` is a subtype of record type `B` iff they have same shape and
the types of all fields of `A` are subtypes of the corresponding field types of
`B`. *In type system lingo, this means record types are "covariant" or have
"depth subtyping". Record types with different shapes are not subtypes. There is
no "row polymorphism" or "width subtyping".*

If a record type has positional fields, then it is a subtype of the
`Destructure` interface with the same number of fields and with type arguments
that match the type of each field. If the record type has more than 16 fields,
it does not implement `Destructure`.

### Upper and lower bounds

If two record types have the same shape, their least upper bound is a new
record type of the same shape where each field's type is the least upper bound
of the corresponding field in the original types.

```dart
(num, String) a = (1.2, "s");
(int, Object) b = (2, true);
var c = cond ? a : b; // (num, Object)
```

Likewise, the greatest lower bound of two record types with the same shape is
the greatest lower bound of their component fields:

```dart
a((num, String)) {}
b((int, Object)) {}
var c = cond ? a : b; // Function((int, String))
```

The least upper bound of two record types with different shapes is `Record`.

```dart
(num, String) a = (1.2, "s");
(num, String, bool) b = (2, "s", true);
var c = cond ? a : b; // Record
```

The greatest lower bound of records with different shapes is `Never`.

### Type inference and promotion

Type inference and promotion flows through records in much the same way it does
for instances of generic classes (which are covariant in Dart just like record
fields are) and collection literals.

**TODO: Specify this more precisely.**

## Runtime semantics

### The `Record` type

The `positionalFields()` method takes a record and returns an `Iterable` of all
of the record's positional fields in order.

The `namedFields()` method takes a record and returns a Map with entries for
each named field in the record where each key is the field's name and the
corresponding value is the value of that field. (The methods are static to avoid
colliding with fields in an actual record object.)

### The `Destructure<n>` types

These are pure interfaces and have no runtime behavior.

### Records

#### Members

Each field in the record's shape exposes a corresponding getter. Invoking that
getter returns the value provided for that field when the record was created.
Record fields are immutable and do not have setters.

The `toString()` method's behavior is unspecified.

#### Equality

Records behave similar to other primitive types in Dart with regards to
equality. They implement `==` such that two records are equal iff they have the
same shape and all corresponding pairs of fields are equal (determined using
`==`).

```dart
var a = (1, 2);
var b = (1, 2);
print(a == b); // true.
```

The implementation of `hashCode` follows this. Two records that are equal have
the same hash code.

#### Identity

We expect records to often be used for multiple return values. In that case, and
in others, we would like compilers to be able to easily optimize away the heap
allocation and initialization of the record object. If we require each record
to have a persistent identity that is tied to its creation and user visible
through calls to `identical()`, then optimizing away the creation of these
objects is harder.

Semantically, we do not want records to have unique identities distinct from
their contents. A record *is* its contents in the same way that every value 3
in a program is the "same" 3 whether it came from the number literal `3` or the
result of `1 + 2`.

This is why `==` for records is defined in terms of their shape and fields. Two
records with the same shape and fields are equivalent. Identity follows similar
rules. Calling `identical()` with a record argument returns:

*   `false`, if the other argument is not a record.
*   `false`, if the records do not have the same shape. *Since named field
    order is not part of a record's shape, this implies that named field order
    does not affect identity either. `(a: 1, b: 2)` and `(b: 2, a: 1)` are
    identical.*
*   `false`, if any pair of corresponding fields are not identical.
*   Otherwise `true`.

This means `identical()` on records is structural and recursive. However, since
records are immutable and `identical()` on other aggregate types does not
recurse into fields, it cannot be *cyclic.*

An important use case for `identical()` is as a fast path check for equality.
It's common to use `identical()` to quickly see if two objects are "the same",
and if so avoid the potentially slower call to `==`. We have some concern that
structural rules for `identical()` of records could be slow.

We will coordinate with the implementation teams and if they are not confident
that they can get reasonable performance out of it, we may change these rules
before accepting the proposal. "Reasonable" here means fast enough that users
won't find themselves wishing for some other specialized `reallyIdentical()`
function that avoids the cost of structural `identical()` checks on records.

**TODO: Discuss with implementation teams.**

#### Expandos

Like numbers, records do not have a well-defined persistent identity. That means
[Expandos][] can not be attached to them.

[expandos]: https://api.dart.dev/stable/2.10.4/dart-core/Expando-class.html

#### Runtime type

The runtime type of a record is determined from the runtime types of
its fields. There is no notion of a separate, explicitly reified type. So, here:

```dart
(num, Object) pair = (1, 2.3);
print(pair is (int, double)); // "true".
```

The runtime type of `pair` is `(int, double)`, not `(num, Object)`, However, the
variable declaration is still valid and sound because records are naturally
covariant in their field types.

## CHANGELOG

### 1.2

- Remove the static methods on `Record` (#2127).

### 1.1

- Minor copy editing and clean up.
