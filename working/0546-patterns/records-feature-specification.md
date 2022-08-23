# Records Feature Specification

Author: Bob Nystrom

Status: In progress

Version 1.5 (see [CHANGELOG](#CHANGELOG) at end)

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
often have **record** types. In a record, the fields are unordered and
identified by name instead:

```dart
var record = (number: 123, name: "Main", type: "Street");
```

In Dart, we merge both of these into a single construct, called a **record**. A
record has a series of positional fields, and a collection of named fields:

```dart
var record = (1, 2, a: 3, b: 4);
```

The expression syntax looks much like an argument list to a function call. A
record expression like the above examples produces a record value. This is a
first-class object, literally a subtype of Object. Its fields cannot be
modified, but may contain references to mutable objects. It implements
`hashCode` and `==` structurally based on its fields to provide value-type
semantics.

A record may have only positional fields or only named fields, but cannot be
totally empty. *There is no "unit type".* A record with no named fields must
have at least two positional fields. *This prevents confusion around whether a
single positional element record is equivalent to its underlying value, and
avoids a syntactic ambiguity with parenthesized expressions.*

## Core library

These primitive types are added to `dart:core`:

### The `Record` class

A built-in class `Record` with no members except those inherited from `Object`.
All record types are a subtype of this class. This type cannot be constructed,
extended, mixed in, or implemented by user-defined classes. *This is similar to
how the `Function` class is the superclass for all function types.*

## Syntax

### Record expressions

A record is created using a record expression, like the examples above. The
grammar is:

```
literal      ::= record
               | // Existing literal productions...
record       ::= '(' recordField ( ',' recordField )* ','? ')'
recordField  ::= (identifier ':' )? expression
```

This is identical to the grammar for a function call argument list. There are a
couple of syntactic restrictions not captured by the grammar. It is a
compile-time error if a record has any of:

*   The same field name more than once.

*   No named fields and only one positional field. *This avoids ambiguity with
    parenthesized expressions.*

*   A field named `hashCode`, `runtimeType`, `noSuchMethod`, or `toString`.

*   A field name that starts with an underscore. *If we allow a record to have
    private field names, then those fields would not be visible outside of the
    library where the record was declared. That would lead to a record that has
    hidden state. Two such records might unexpectedly compare unequal even
    though all of the fields the user can see are equal.*

### Record type annotations

In the type system, each record has a corresponding record type. A record type
looks similar to a function type's parameter list. The type is surrounded by
parentheses and may contain comma-separated positional fields:

```dart
(int, String name, bool) triple;
```

Each field is a type annotation and an optional name which isn't meaningful but
is useful for documentation purposes.

Named fields go inside a brace-delimited section of type and name pairs:

```dart
({int n, String s}) pair;
```

A record type may have both positional and named fields:

```dart
(bool, num, {int n, String s}) quad;
```

The grammar is:

```
// Existing rules:
type                   ::= functionType '?'?      // Existing production.
                         | recordType             // New production.
                         | typeNotFunction        // Existing production.

typeNotFunction        ::= 'void'                 // Existing production.
                         | recordType             // New production.
                         | typeNotVoidNotFunction // Existing production.

// New rules:
recordType             ::= '(' recordTypeFields ',' recordTypeNamedFields ')'
                         | '(' recordTypeFields ','? ')'
                         | '(' recordTypeNamedFields ')'

recordTypeFields       ::= recordTypeField ( ',' recordTypeField )*
recordTypeField        ::= metadata type identifier?

recordTypeNamedFields  ::= '{' recordTypeNamedField
                           ( ',' recordTypeNamedField )* ','? '}'
recordTypeNamedField   ::= type identifier
recordTypeNamedField   ::= metadata typedIdentifier
```

*The grammar is exactly the same as `parameterTypeList` in function types but
without `()`, `required`, and optional positional parameters since those don't
apply to record types. A record type can't appear in an `extends`, `implements`,
`with`, or mixin `on` clause, which is enforced by being a production in `type`
and not `typeNotVoid`.*

It is a compile-time error if a record type has any of:

*   The same field name more than once.

*   No named fields and only one positional field. *This isn't ambiguous, since
    there are no parenthesized type expressions in Dart. But there is no reason
    to allow single positional element record types when the corresponding
    record values are prohibited.*

*   A field named `hashCode`, `runtimeType`, `noSuchMethod`, or `toString`.

*   A field name that starts with an underscore.

### No record type literals

There is no record type literal syntax that can be used as an expression, since
it would be ambiguous with other existing syntax:

```dart
var t = (int, String);
```

This is a record expression containing two type literals, `int` and `String`,
not a type literal for a record type.

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

Positional fields are not exposed as getters. *Record patterns in pattern
matching can be used to access a record's positional fields.*

For example, the record expression `(1.2, name: 's', true, count: 3)` has a
record type whose signature is like:

```dart
class extends Record {
  String get name;
  int get count;
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

### Upper and lower bounds

If two record types have the same shape, their least upper bound is a new
record type of the same shape where each field's type is the least upper bound
of the corresponding field in the original types.

```dart
(num, String) a = (1.2, "s");
(int, Object) b = (2, true);
var c = cond ? a : b; // c has type `(num, Object)`.
```

Likewise, the greatest lower bound of two record types with the same shape is
the greatest lower bound of their component fields:

```dart
a((num, String)) {}
b((int, Object)) {}
var c = cond ? a : b; // c has type `Function((int, String))`.
```

The least upper bound of two record types with different shapes is `Record`.

```dart
(num, String) a = (1.2, "s");
(num, String, bool) b = (2, "s", true);
var c = cond ? a : b; // c has type `Record`.
```

The greatest lower bound of records with different shapes is `Never`.

### Type inference and promotion

Type inference and promotion flows through records in much the same way it does
for instances of generic classes (which are covariant in Dart just like record
fields are) and collection literals.

**TODO: Specify this more precisely.**

### Constants

_Record expressions can be constant and potentially constant expressions._

A record expression is a compile-time constant expression
if and only if all its record field expressions are compile-time constant expressions. 

_This is true whether the expression occurs in a constant context or not,
which means that a record expression can be used directly as a parameter default value 
if its record field expressions are constant expressions.
Example: `f({(int, int) x = (1, 2)}) => ...`._

A record expression is a potentially constant expression 
if and only iff all its record field expressions are potentially constant or constant expressions.

_This means that a record expression can be used in the initializer list
of a constant non-redirecting generative constructor, 
and can depend on constructor parameters._

_Constant *object* instantiations create deeply immutable and canonicalied objects.
Records are always unmodifiable, and if their field values are deeply immutable,
like constants values, the records are also deeply immutable.
It's meaningless to consider whether record constants are canonicalized,
since records do not have a persistent identity._

_Because of that, there is no need for a `const (1, 2)` syntax to force a record 
to be a constant, like there is for object creation expressions. 
A record expression with field values that are constant-created values, 
will be indistinguishable from a similar expression created in a constant 
context, since identity cannot be used as a distinguishing trait._

_(We could choose to promise that a compile-time constant `identical(c1, c2)`,
where the expression occurs in a constant context and `c1` and `c2` are records, 
will evaluate to `true` iff a runtime evaluation of `identical` 
*can* return `true` for the same values. 
That is, records would be canonicalized during compile-time constant evealuation,
but may lose their identity at runtime. We will not make such a promise.)_

For canonoicalization purposes, we update the definition of when to canonicalize
the result of a constant object creation expression to not be dependent on 
the `identical` function, since it does not behave predictably (or usefully)
for records.

We define two Dart values, *a* and *b*, to be _structurally equivalent_ as follows:
* If *a* and *b* are both records, and they have the same shape, 
  and for each field *f* of that shape, the records' values of that field, 
  *a*<sub>*f*</sub> and *b*<sub>*f*</sub> are structurally equivalent, 
  then *a* and *b* are structurally equivalent.
* If *a* and *b* are non-record object references, 
  and they refer to the same object, then *a* and *b* are structurally equivalent.
  _So structural equivalence agrees with `identical` for non-records._
* Otherwise *a* and *b* are not structurally equivalent.

With that definition, the rules for object and collection canonicalization is changed
from requiring that instance variable, list/set element and map key/value values are
`identical` between the instances, to them being _structurally equivalent_.

_This change allows a class like_
```dart
class C {
  final (int, int) pair;
  const C(int x, int y) : pair = (x, y);
}
```
_to be properly canonicalized for objects with the same effective state, 
independentlty of whether `identical` returns `true` or `false` on the `pair` value._

_Notice that if the `identical`returns `true` on two records, they must be structurally equivalent,
but unlike for non-records, the `identical` function can also return `false`
for structurally equivalent records._

## Runtime semantics

### Records

#### Members

Each field in the record's shape exposes a corresponding getter. Invoking that
getter returns the value provided for that field when the record was created.
Record fields are immutable and do not have setters.

The `toString()` method's behavior is unspecified.

#### Equality

Records behave similar to other primitive types in Dart with regards to
equality. They implement `==` such that two records are equal iff they have the
same shape and all corresponding pairs of fields are equal. Fields are compared
for equality by calling `==` on the corresponding field values in the same
order that `==` was called on the records.

```dart
var a = (x: 1, 2);
var b = (2, x: 1);
print(a == b); // true.
```

The implementation of `hashCode` follows this. Two records that are equal must
have the same hash code.

#### Identity

We expect records to often be used for multiple return values. In that case, and
in others, we would like compilers to be able to easily optimize away the heap
allocation and initialization of the record object. If we require each record
to have a persistent identity that is tied to its creation and user visible
through calls to `identical()`, then optimizing away the creation of these
objects is harder.

Semantically, we do not want records to have unique identities distinct from
their contents. A record *is* its contents in the same way that every value 3 in
a program is the "same" 3 whether it came from the number literal `3` or the
result of `1 + 2`. This is why `==` for records is defined in terms of their
shape and fields. Two records with the same shape and equal fields are equal
values.

At the same time, we want `identical()` to be fast because one of its primary
uses is as a fast-path check for equality. An `identical()` that is obliged to
iterate over the record's fields (transitively in the case where some fields
are themselves records) might nullify the benefits of using `identical()` as a
fast-path check before calling `==`.

To balance those opposing goals, `identical()` on records is defined to only
offer loose guarantees. Calling `identical()` with a record argument returns:

*   `false`, if the other argument is not a record.
*   `false`, if the records do not have the same shape. *Since named field
    order is not part of a record's shape, this implies that named field order
    does not affect identity either. `identical((a: 1, b: 2), (b: 2, a: 1))` is
    not required to return false.*
*   `false`, if any pair of corresponding fields are not identical.
*   Otherwise it *may* return `true`, but is not required to.

*If an implementation can easily determine that two record arguments to
`identical()` have the same shape and identical fields, then it should return
`true`. Typically, this is because the two arguments to `identical()` are
pointers with the same address to the same heap-allocated record object. But if
an implementation would have to do a slower field-wise comparison to determine
identity, it's probably better to return `false` quickly.*

*In other words, if `identical()` returns `true`, then the records are
definitely indistinguishable. But if it returns `false`, they may or may not
be.*

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

### 1.5

- Make the grammar for record types closer to function type parameter lists.
  Allow metadata before fields and optional names for positional fields.

- Weave `recordType` into the grammar better. Don't allow it in inheritance
  clauses, but do allow it as the return type of function types.

- Remove shorthand syntax that elides parentheses when there are no positional
  fields since that's ambiguous inside a function type (#2302).

- Clarify that there is no record type literal syntax (#2304).

### 1.4

- Remove the reflective static members on `Record`. Like other reflective
  features, supporting these operations may incur a global cost in generated
  code size for unknown benefit (#1275, #1277).

- Remove support for single positional element records. They don't have any
  current use and are a syntactic wart. If we later add support for spreading
  argument lists and single element positional records become useful, we can
  re-add them then.

- Remove synthesized getters for positional fields. This avoids problems if a
  positional field's synthesized getter collides with an explicit named field
  (#1291).

### 1.3

- Remove the `Destructure_n_` interfaces.

### 1.2

- Remove the static methods on `Record` (#2127).

### 1.1

- Minor copy editing and clean up.
