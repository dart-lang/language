# Records Feature Specification

Author: Bob Nystrom

Status: Accepted

Version 1.15 (see [CHANGELOG](#CHANGELOG) at end)

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
record has a series of fields, which may be named or positional.

```dart
var record = (1, a: 2, 3, b: 4);
```

The expression syntax looks much like an argument list to a function call. A
record expression like the above examples produces a record value. This is a
first-class object, literally a subtype of Object. Its fields cannot be
modified, but may contain references to mutable objects. It implements
`hashCode` and `==` structurally based on its fields to provide value-type
semantics.

A record may have only positional fields, only named fields, both, or none at
all.

Once a record has been created, its fields can be accessed using getters.
Every named field exposes a getter with the same name, and positional fields
expose getters named `$0`, `$1`, etc.:

```dart
var record = (1, a: 2, 3, b: 4);
print(record.$0); // Prints "1".
print(record.a);  // Prints "2".
print(record.$1); // Prints "3".
print(record.b);  // Prints "4".
```

## Core library

These primitive types are added to `dart:core`:

### The `Record` class

The type `Record` refers to a built-in class defined in `dart:core`. It has no
instance members except those inherited from `Object` and exposes no
constructors. It can't be constructed, extended, mixed in, or implemented by
user-defined classes.

All record types are a subtype of this class. *This is similar to how the
`Function` class is the superclass for all function types.*

## Syntax

### Record expressions

A record is created using a record expression, like the examples above. The
grammar is:

```
literal      ::= record
               | // Existing literal productions...
record       ::= 'const'? '(' recordField ( ',' recordField )* ','? ')'
recordField  ::= (identifier ':' )? expression
```

This is identical to the grammar for a function call argument list (with an
optional `const` at the beginning). There are a couple of syntactic restrictions
not captured by the grammar. It is a compile-time error if a record has any of:

*   The same field name more than once.

*   Only one positional field and no trailing comma.

*   No fields and a trailing comma. *The expression `(,)` isn't allowed.*

*   A field named `hashCode`, `runtimeType`, `noSuchMethod`, or `toString`.

*   A field name that starts with an underscore.

*   A field name that collides with the synthesized getter name of a positional
    field. *For example: `('pos', $0: 'named')` since the named field '$0'
    collides with the getter for the first positional field.*

In order to avoid ambiguity with parenthesized expressions, a record with
only a single positional field must have a trailing comma:

```dart
var number = (1);  // The number 1.
var record = (1,); // A record containing the number 1.
```

The expression `()` refers to the constant empty record with no fields.

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
typeNotFunction        ::= 'void'                 // Existing production.
                         | recordType '?'?        // New production.
                         | typeNotVoidNotFunction // Existing production.

typeNotVoid            ::= functionType '?'?      // Existing production.
                         | recordType '?'?        // New production.
                         | typeNotVoidNotFunction // Existing production.

// New rules:
recordType             ::= '(' recordTypeFields ',' recordTypeNamedFields ')'
                         | '(' recordTypeFields ','? ')'
                         | '(' recordTypeNamedFields? ')'

recordTypeFields       ::= recordTypeField ( ',' recordTypeField )*
recordTypeField        ::= metadata type identifier?

recordTypeNamedFields  ::= '{' recordTypeNamedField
                           ( ',' recordTypeNamedField )* ','? '}'
recordTypeNamedField   ::= metadata type identifier
```

*The grammar is exactly the same as `parameterTypeList` in function types but
without `required`, and optional positional parameters since those don't apply
to record types.*

The type `()` is the type of an empty record with no fields.

It is a compile-time error if a record type has any of:

*   The same field name more than once. *This is true even if one or both of the
    colliding fields is positional. We could permit collisions with positional
    field names since they are only used for documentation, but we disallow it
    because it's confusing and not useful.*

*   Only one positional field and no trailing comma. *This isn't ambiguous,
    since there are no parenthesized type expressions in Dart. But prohibiting
    this is symmetric with record expressions and leaves the potential for
    later support for parentheses for grouping in type expressions.*

*   A named field named `hashCode`, `runtimeType`, `noSuchMethod`, or
    `toString`.

*   A field name that starts with an underscore.

*   A field name that collides with the synthesized getter name of a positional
    field. *For example: `(int, $0: int)` since the named field '$0' collides
    with the getter for the first positional field.*

### No record type literals

There is no record type literal syntax that can be used as an expression, since
it would be ambiguous with other existing syntax:

```dart
var t = (int, String);
```

This is a record expression containing two type literals, `int` and `String`,
not a type literal for a record type.

### Ambiguity with `on` clauses

Consider:

```dart
void foo() {
  try {
    ;
  } on Bar {
    ;
  }
  on(a, b) {;} // <--
}
```

Before, the marked line could only be declaring a local function named `on`.
With record types, it could be a second `on` clause for the `try` statement
whose matched type is the record type `(a, b)`. When presented with this
ambiguity, we disambiguate by treating `on` as a clause for `try` and not a
local function. This is technically a breaking change, but is unlikely to affect
any code in the wild.

**TODO: This section should be removed if we change the record type syntax to
avoid this ambiguity ([#2469][]).**

[#2469]: https://github.com/dart-lang/language/issues/2469

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

*Positional fields are not merely syntactic sugar for fields named `$0`, `$1`,
etc. The records `(1, 2)` and `($0: 1, $1: 2)` expose the same *members*, but
have different shapes according to the type system.*

### Members

A record type declares all of the members defined on `Object`. It also exposes
getters for each named field where the name of the getter is the field's name
and the getter's type is the field's type. For each positional field, it exposes
a getter whose name is `$` followed by the number of preceding positional fields
and whose type is the type of the field.

For example, the record expression `(1.2, name: 's', true, count: 3)` has a
record type whose signature is like:

```dart
class extends Record {
  double get $0;
  String get name;
  bool get $1;
  int get count;
}
```

### Subtyping

Subtyping for record types has been incorporated into the main subtyping
specification
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md).
Briefly:

The class `Record` is a subtype of `Object` and `dynamic` and a supertype of
`Never`. All record types are subtypes of `Record`, and supertypes of `Never`.

A record type `A` is a subtype of record type `B` iff they have same shape and
the types of all fields of `A` are subtypes of the corresponding field types of
`B`. *In type system lingo, this means record types are "covariant" or have
"depth subtyping". Record types with different shapes are not subtypes. There is
no "row polymorphism" or "width subtyping".*

### Upper and lower bounds

Bounds computations for record types have been incorporated into the main
specification
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/upper-lower-bounds.md).
Briefly:

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
a((num, String) record) {}
b((int, Object) record) {}
var c = cond ? a : b; // c has type `Function((int, String))`.
```

The least upper bound of two record types with different shapes is `Record`.

```dart
(num, String) a = (1.2, "s");
(num, String, bool) b = (2, "s", true);
var c = cond ? a : b; // c has type `Record`.
```

The greatest lower bound of records with different shapes is `Never`.

### Type inference

Every record literal has a static type, which is associated with it via
inference (there is no syntax for explicitly associating a specific static type
with a record literal).  As with other constructs, we define type inference for
record expressions with respect to a context type schema which is determined by
the surrounding context of the inferred expression.  Unlike nominal classes (but
like function literals) we choose to infer the most specific possible type for
record literals, even if that type is more precise than the type specified by
the context type schema.  This choice (as with function literals) reflects the
fact that record types (like function types in Dart) are soundly variant: that
is, the subtyping is properly covariant and requires no runtime checking.

For convenience, we generally write function types with all named parameters in
an unspecified canonical order, and similarly for the named fields of record
types.  In all cases unless otherwise specifically called out, order of named
parameters and fields is semantically irrelevant: any two types with the same
named parameters (named fields, respectively) are considered the same type.

Similarly, function and method invocations with named arguments and records with
named field entries are written with their named entries in an unspecified
canonical order and position.  Unless otherwise called out, position of named
entries is semantically irrelevant, and all invocations and record literals with
the same named entries (possibly in different orders or locations) and the same
positional entries are considered equivalent.

Given a type schema `K` and a record expression `E` of the general form `(e1,
..., en, d1 : e{n+1}, ..., dm : e{n+m})` inference proceeds as follows.

If `K` is a record type schema of the form `(K1, ..., Kn, {d1 : K{n+1}, ....,
dm : K{n+m}})` then:
  - Each `ei` is inferred with context type schema `Ki` to have type `Si`
    - Let `Ri` be the greatest closure of `Ki`
    - If `Si` is a subtype of `Ri` then let `Ti` be `Si`
    - Otherwise, if `Si` is `dynamic`, then we insert an implicit cast on `ei`
      to `Ri`, and let `Ti` be `Ri`
    - Otherwise, if `Si` is coercible to `Ri` (via some sequence of call method
      tearoff or implicit generic instantiation coercions), then we insert the
      appropriate implicit coercion(s) on `ei`.  Let `Ti` be the type of the
      resulting coerced value (which must be a subtype of `Ri`, possibly
      proper).
    - Otherwise, it is a static error.
  - The type of `E` is `(T1, ..., Tn, {d1 : T{n+1}, ...., dm : T{n+m}})`

If `K` is any other type schema:
  - Each `ei` is inferred with context type schema `_` to have type `Ti`
  - The type of `E` is `(T1, ..., Tn, {d1 : T{n+1}, ...., dm : T{n+m}})`

As noted above, contrary to the practice for runtime checked covariant nominal
types, we do not prefer the context type over the more precise upwards type.
The following example illustrates this:
```dart
  // No static error.
  // Inferred type of the record is (int, double)
  (num, num) r = (3, 3.5)..$0.isEven;
```

Also note that implicit casts and other coercions are considered to be applied
as part of inference, hence:
```dart
  class Callable {
    void call(num x) {}
  }
  T id<T>(T x) => x;
  // No static error.
  // Inferred type of the record is:
  //    (int, double, int Function(int), void Function(num))
  var c = Callable();
  dynamic d = 3;
  (num, double, int Function(int), void Function(int)) r = (d, 3, id, c);
```
and the record initialization in the last line above is implicitly coerced to be
the equivalent of:
```dart
  (num, double, int Function(int), void Function()) r =
     (d as num, 3.0, id<int>, c.call);
```

See issue [2488](https://github.com/dart-lang/language/issues/2488) for some of
the background discussion on the choices specified in this section.

### Constants

Record expressions can be constant and potentially constant expressions. A
record expression is a compile-time constant expression if and only if all of
its field expressions are compile-time constant expressions.

*This is true whether the expression occurs in a constant context or not, which
means that a record expression can be used directly as a parameter default value
if its record field expressions are constant expressions, as in:

```dart
void someFunction({(int, int) x = (1, 2)}) => ...`
```

A record expression is a potentially constant expression if and only if all its
field expressions are potentially constant or constant expressions. *This means
that a record expression can be used in the initializer list of a constant
non-redirecting generative constructor, and can depend on constructor
parameters.*

*Constant object instantiations (i.e. const constructor calls and const
collection literals) create deeply immutable and canonicalized objects. Records
are always unmodifiable. If a record's field values are also deeply immutable
(which all constant values are), then the record is also deeply immutable. It's
meaningless to consider whether record constants are canonicalized, since
records do not have a persistent identity.*

*Therefore, there is no need for a `const (1, 2)` syntax to force a record to be
a constant like there is for constructor calls. Any record expression with field
values that are constant is indistinguishable from a similar expression created
in a constant context, since identity cannot be used as a distinguishing trait.*

#### Canonicalization

The current specification relies on `identical()` to decide when to canonicalize
constant object creation expressions. Since `identical()` is not useful for
records (see below), we update that:

Define two Dart values, *a* and *b*, to be *structurally equivalent* as follows:

*   If *a* and *b* are both records, and they have the same shape, and for each
    field *f* of that shape, the records' values of that field,
    *a*<sub>*f*</sub> and *b*<sub>*f*</sub> are structurally equivalent, then
    *a* and *b* are structurally equivalent.

*   If *a* and *b* are non-record object references, and they refer to the same
    object, then *a* and *b* are structurally equivalent. *So structural
    equivalence agrees with `identical()` for non-records.*

* Otherwise *a* and *b* are not structurally equivalent.

With that definition, the rules for object and collection canonicalization is
changed from requiring that instance variable, list/set element and map
key/value values are `identical()` between the instances, to them being
*structurally equivalent*.

*This change allows a class like:*

```dart
class C {
  final (int, int) pair;
  const C(int x, int y) : pair = (x, y);
}
```

*to be properly canonicalized for objects with the same effective state,
independently of whether `identical()` returns `true` or `false` on the `pair`
value. Notice that if the `identical()` returns `true` on two records, they must
be structurally equivalent, but unlike for non-records, the `identical()`
function can also return `false` for structurally equivalent records.*

### Uses

It is a compile-time error if a record type or a type alias that resolves to a
record type is used in:

*   An `extends` clause.
*   An `implements` clause.
*   A `with` clause.
*   An `on` clause on a mixin declaration. *A record type can be used as the
    `on` type in an extension declaration.*

## Runtime semantics

The fields in a record expression are evaluated left to right. *This is true
even if an implementation chooses to reorder the named fields in order to
canonicalize records with the same set of named fields. For example:*

```dart
int say(int i) {
  print(i);
  return i;
}

var x = (a: say(1), b: say(2));
var y = (b: say(3), a: say(4));
```

*This program *must* print "1", "2", "3", "4", even though `x` and `y` are
records with the same shape.*

### Field getters

Each field in the record's shape exposes a corresponding getter. Invoking that
getter returns the value provided for that field when the record was created.
Record fields are immutable and do not have setters.

### `toString()`

In debug builds, the `toString()` method converts each field to a string by
calling `toString()` on its value and prepending it with the field name followed
by `: ` if the field is named. It concatenates these with `, ` as a separator
and returns the resulted surrounded by parentheses. For example:

```dart
print((1, 2, 3).toString()); // "(1, 2, 3)".
print((a: 'str', 'int').toString()); // "(a: str, int)".
```

The order that named fields appear and how they are interleaved with positional
fields is unspecified. Positional fields must appear in position order. *This
gives implementations freedom to choose a canonical order for named fields
independent of the order that the record was created with.*

In a release or optimized build, the behavior of `toString()` is unspecified.
*This gives implementations freedom to discard the full names of named fields in
order to reduce code size.* Users should only use `toString()` on records for
debugging purposes. They are strongly discouraged from parsing the results of
calling `toString()` or relying on it for end-user visible output.

### Equality

Records have value equality, which means two records are equal if they have the
same shape and the corresponding fields are equal. Since named field order is
*not* part of a record's shape, that implies that the order of named fields
does not affect equality:

```dart
var a = (x: 1, 2);
var b = (2, x: 1);
print(a == b); // true.
```

More precisely, the `==` method on record `r` with right operand `o` is defined
as:

1.  If `o` is not a record with the same shape as `r` then `false`.

1.  For each pair of corresponding fields `rf` and `of` in unspecified order:

    1.  If `rf == of` is `false` then `false`.

1.  Else, `true`.

*The order that fields are iterated is potentially user-visible since
user-defined `==` methods can have side effects. Most well-behaved `==`
implementations are pure. The order that fields are visited is deliberately left
unspecified so that implementations are free to reorder the field comparisons
for performance.*

The implementation of `hashCode` follows this. The hash code returned should
depend on the field values such that two records that compare equal must have
the same hash code.

### Primitive equality

A record object has a primitive `==` operator if all of its field have primitive
`==` operators.

*Note that this is a dynamic property of a record object, not a property of its
static type. Since primitive equality only comes into play in constants, the
compiler can see the actual field values for a relevant record at compile time
because it has the actual constant record value with all of its constant fields.
This means a record can be used in a constant set or as a constant map key, but
only when its field values could be as well.*

### Identity

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

### Expandos

Like numbers, records do not have a well-defined persistent identity. That means
[Expandos][] can not be attached to them.

[expandos]: https://api.dart.dev/stable/2.10.4/dart-core/Expando-class.html

### Runtime type

The runtime type of a record is determined from the runtime types of
its fields. There is no notion of a separate, explicitly reified type. So, here:

```dart
(num, Object) pair = (1, 2.3);
print(pair is (int, double)); // "true".
```

The runtime type of `pair` is `(int, double)`, not `(num, Object)`, However, the
variable declaration is still valid and sound because records are naturally
covariant in their field types.

### Interactions with libraries using older language versions

The records feature is language versioned, as usual with new Dart features.
This means that it will be an error to use the syntax for records in libraries
which do not have a language version greater than or equal to the language
version in which records are released.  More specifically, assuming that `v` is
the language version in which records are released, the following errors apply.

It is an error for the identifier `Record`, denoting the `Record` class from
`dart:core`, where that import scope name is only imported from platform
libraries, to appear in a library whose language version is less than `v`.

It is an error for the record literal syntax (e.g. `(3, 4)`) to be used
syntactically in a library whose language version is less than `v`.

It is an error for the record type syntax (e.g. `(int, int)`) to be used
syntactically in a library whose language version is less than `v`.

*Note that the above errors only apply to direct syntactic uses of the new
record syntax in legacy libraries.  It is not an error for a library whose
language version is less than `v` (a "legacy library") to include types which
denote or include the `Record` class, record types or record expressions when
these terms arise directly or indirectly from references to another library
whose language version is greater than or equal to `v`.  For example, such a
legacy library may reference a typedef name which is bound to a record type in
another library, and the semantic interpretation of the typedef is as the
underlying record type, just as it would be for any other type.  Similarly, type
inference may introduce record types into a legacy library, and such types will
be interpreted by the compiler as record types as usual (that is, there is no
erasure implied to remove these inferred types).  A legacy library may refer to
the `Record` class via a library which has re-exported it.  Record values may
flow into a legacy library via a reference to a member from another library, and
a legacy library may freely call getters on record values (since there is no new
syntax for calling a record getter).  The rationale for the choices described in
this section is that the intent of language versioning (for an additive feature
such as records) is to ensure that users do not accidentally use new features in
a package without specifying an SDK constraint which ensures that their code
will always be run on an SDK which supports the feature.  But in the case of a
legacy library which references record values or types indirectly via another
library, the SDK constraint on the referenced library is sufficient to enforce
this.*


## CHANGELOG

### 1.15

- Specify the interaction between libraries with a language version that
  supports records and libraries with older language versions.

### 1.14

- Specify type inference, add static semantics to resources/type-system

### 1.13

- Introduce `()` syntax for empty record expressions and remove `Record.empty`.

### 1.12

- Include record types in `typeNotVoid`. This allows them to appear in `is` and
  `as` expressions (which was always intended).

- Clarify that record types cannot be used as supertypes or superinterfaces.

### 1.11

- Revert back to disallowing private field names in records.

### 1.10

- Allow private named fields in records (#2387).

- Allow positional fields in record types named `hashCode`, `runtimeType`,
  `noSuchMethod`, or `toString`.

### 1.9

- Specify that a record has a primitive `==` when its fields all do.

### 1.8

- Move to `accepted/`.

### 1.7

- Clarify what kind of type `Record` is and where it's defined (#2442).

### 1.6

- Support constant records (#2337).

- Support empty and one-positional-field records (#2386).

- Re-add support for positional field getters (#2388).

- Specify the behavior of `toString()` (#2389).

- Disambiguate record types in `on` clauses (#2406).

- Clarify the order that fields are evaluated in record expressions.

- Clarify the iteration order of fields in `==`.

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
