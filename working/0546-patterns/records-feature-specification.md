# Records Feature Specification

Author: Bob Nystrom
Status: Draft

## Summary

This proposal is one piece of the larger "tuples, records, and pattern matching"
family of features.

Records are an anonymous aggregate type. Like lists and maps, they let you
combine several values into a single new object. Unlike other collection types,
records are fixed-sized, heterogeneous, and typed. Each element in a record may
have a different type and the static type system tracks them separately.

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

A built-in class whose signature is:

```dart
abstract class Record {
  static Iterable<Object?> positionalFields(Record record);
  static Map<Symbol, Object?> namedFields(Record record);
}
```

This type cannot be constructed, extended, mixed in, or implemented by
user-defined classes.

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
literal           ::= record
                    | // Existing literal productions...

record            ::= '(' recordBody ')'

recordBody        ::= recordField ',' ( recordFields ','? )?
                    | ( recordFields ',' )? recordNamedFields ','?

recordFields      ::= recordField ( ',' recordField )*

recordField       ::= expression

recordNamedFields ::= recordNamedField ( ',' recordNamedField )*

recordNamedField  ::= identifier ':' expression
```

This is roughly like the grammar for a function call argument list, except that
a completely empty field list is not allowed and if there is only a single
positional field, it *must* have a trailing comma. This is similar to tuples in
Python and avoids the ambiguity between parenthesized expressions and single
positional element records.

It is a compile-time error if a record has the same field name more than once or
if the name of a named field collides with the implicit name defined for a
positional field (see below). It is a compile-time error if a record has a field
named `hashCode`, `runtimeType`, `noSuchMethod`, or `toString`.

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

If there are only named fields, you are also allowed to omit the surrounding
parentheses:

```dart
{int n, String s} pair;
```

Like record expressions, a record type must have at least one field.

Unlike expressions a trailing comma is not required in the single positional
field case. `(int)` is valid record type and is distinct from the type `int`.
This is different from functional languages where tuples are a *concatenation*
of elements. Dart records are *containers* for elements.

## Static semantics

We define **shape** the mean the number of positional fields (the record's
**arity**) and the set of names of its named fields. Record types are
structural, not nominal. Records produced in unrelated libraries have the exact
same static type if they have the same shape and their corresponding fields have
the same types.

### Members

A record type declares all of the members defined on Object. It also exposes
getters for each named field where the name of the getter is the field's name
and the getter's type is the field's type.

In addition, for each position field, the record type declares a getter named
`field<n>` where `<n>` is the zero-based index of the field's position and where
the getter's type is the field's type.

For example, the record expression `(1, true, s: "string")` has a record type
whose signature is like:

```dart
class {
  int get field0;
  bool get field1;
  String get s;
}
```

### Subtyping

The class `Record` is a subtype of `Object` and `dynamic` and a supertype of
`Never`. All record types are subtypes of `Record`, and supertypes of `Never`.

A record type `A` is a subtype of record type `B` iff they have same shape and
types of all fields of `A` are subtypes of corresponding field types of `B`. In
type system lingo, this means record types are "covariant" or have "depth
subtyping. Record types with different shapes are not subtypes. There is no "row
polymorphism" or "width subtyping".

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

### Equality

Records behave similar to other primitive types in Dart with regards two
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

### Identity

We expect records to often be used for multiple return values. In that case, and
in others, we would like compilers to be able to easily optimize away the heap
allocation and initialization of the record object. Dart's rules around
`identical()` can make that more difficult. If a record must have a persistent,
observable identity, it is harder for a compiler to optimize it away.

At the same time, `identical()` is *useful* for performance because it can be a
fast path to tell if references to two objects must be equivalent because they
point to the *same* object.

To balance those, the rules for `identical()` on records are:

*   Two *constant* records with the same shape and identical corresponding
    pairs of fields are identical. This is the usual rule that constants are
    canonicalized.

*   Two non-constant records that are not equal according to `==` must not be
    identical. In other words, there are not "false positives" where
    `identical()` returns `true` for two records where `==` would return
    `false`. This implies that records with different shapes are never
    identical.

*   Non-constant records with the same shape and equal corresponding fields *may
    or may not* be identical. This means false negatives are allowed. It is
    possible to create a single record, have two different references to it
    flow through the program and then have `identical()` on them return *false*
    because the compiler happened to optimize away one or the other's
    representation such that they are no longer references to the same object
    in memory.

The latter sounds alarming, but in practice it does not appear to be harmful.
The language's rules around when string operations are canonicalized and when
they are not are also somewhat subtle in ways that make using strings in an
IdentityHashMap brittle, but it doesn't seem cause problems. Users don't seem
to rely on `identical()` for anything more than a fast early check for equality.
