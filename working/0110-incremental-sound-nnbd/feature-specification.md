# Sound non-nullable (by default) types with incremental migration 

Author: leafp@google.com

Status: Draft

This is the proposed specification for [sound non-nullable by default types](http://github.com/dart-lang/language/issues/110).
Discussion of this proposal should take place in [Issue 110](http://github.com/dart-lang/language/issues/100).

Discussion issues on specific topics related to this proposal are [here](https://github.com/dart-lang/language/issues?utf8=%E2%9C%93&q=is%3Aissue+label%3Annbd+)

The motivations for the feature along with the migration plan and strategy are
discussed in more detail in
the
[roadmap](https://github.com/dart-lang/language/blob/master/working/0110-incremental-sound-nnbd/roadmap.md).

This proposal draws on the proposal that Patrice Chalin wrote
up [here](https://github.com/dart-archive/dart_enhancement_proposals/issues/30),
and on the proposal that Bob Nystrom wrote
up
[here](https://github.com/dart-lang/language/blob/master/resources/old-non-nullable-types.md).


## Syntax

The grammar of types is extended to allow any type to be suffixed with a `?`
(e.g. `int ?`) indicating the nullable version of that type.

A new primitive type `Never`.  This type is denoted by the built-in type
declaration `Never`, with the same syntactic and scoping treatment as with other
built-in types such as `dynamic`.

The grammer of expressions is extended to allow any expression to be suffixed
with a `!`.

The grammer of static and instance fields and static and local variables is
extended to allow any declaration to include the modifer `lazy`.

The grammar of function types is extended to allow an additional group of named
parameters prefaced with the word `required` (e.g. `int Function(int, {int?
y}, required {int z})`.

The grammar of function/method/closure declarations is extended to allow an
additional group of named parameters prefaced with the word `required`
(e.g. `int f(int x, {int?  y}, required {int z})`.


### Grammatical ambiguities and clarifications.

#### Nested nullable types

The grammar for types does not allow multiple successive `?` operators on a
type.  That is, the grammar for types is

```
type' ::= functionType
          | qualified typeArguments? 

type ::= type' `?`?
```

#### Conditional expression ambiguities

Conditional expressions inside of braces are ambiguous between sets and maps.
That is, `{ a as int ? - 3 : 3 }` can be parsed as a set literal `{ (a as int)
? - 3 : 3 }` or as a map literal `{ (a as int ?) - 3 : 3 }`.  Parsers will
prefer the former parse over the latter.

The same is true for `{ a is int ? - 3 : 3 }`.

The same is true for `{ int ? - 3 : 3 }` if we allow this.


## Static semantics


### Static errors

We say that a type `T` is **nullable** if `Null <: T`.  This is equivalent to
the syntactic criterion that `T` is any of:
  - `Null`
  - `S?` for some `S`
  - `FutureOr<S>` for some `S` where `S` is nullable
  - `dynamic`
  - `void`
  - `X extends Null`

We say that a type `T` is **non-nullable** if `T <: Object`.  This is equivalent
to the syntactic criterion that `T` is any of:
  - `Object`, `int`, `bool`, `Never`
  - Any class type or generic class type
  - `FutureOr<S>` where `S` is non-nullable
  - `X extends S` where `S` is non-nullable
  - `X & S` where `S` is non-nullable

Note that there are types which are neither nullable nor non-nullable.  For
example `X extends T` where `T` is nullable is neither nullable nor
non-nullable.

We say that a type `T` is **potentially nullable** if `T` is not non-nullable.
Note that this is different from saying that `T` is nullable.  For example, a
type variable `X extends Object?` is a type which is potentially nullable but
not nullable.

We say that a type `T` is **potentially non-nullable** if `T` is not nullable.
Note that this is different from saying that `T` is non-nullable.  For example,
a type variable `X extends Object?` is a type which is potentially non-nullable
but not non-nullable.

It is an error to call a method, setter, getter or operator on an expression
whose type is potentially nullable and not `dynamic`, except for the methods,
setters, getters, and operators on `Object`.

It is an error to read a field or tear off a method from an expression whose
type is potentially nullable and not `dynamic`, except for the methods and
fields on `Object`.

It is an error to call an expression whose type is potentially nullable and not
`dynamic`.

It is an error for a top level variable, static field, or instance field with no
static initializer to have a potentially nullable type unless the variable or
field is marked with the `lazy` modifier.

It is an error if a local variable that is potentially non-nullable and is not
marked `lazy` is used before it is definitely assigned (see Definite Assignment
below).

It is an error if a method, function, getter, or closure with a potentially
non-nullable return type does not definitely complete (see Definite Completion
below).

It is an error if an optional parameter (named or otherwise) with no default
value has a potentially non-nullable type.

It is an error if a required named parameter has a default value.

It is an error if a named parameter that is part of a `required` group is not
bound to an argument at a call site.

It is an error to call the default `List` constructor with a length argument and
a type argument which is potentially non-nullable.

For the purposes of errors and warnings, the null aware operators `?.` and `?..`
are checked as if the receiver of the operator had non-nullable type.

It is an error for a class to extend, implement, or mixin a type of the form
`T?` for any `T`.

It is an error for a class to extend, implement, or mixin the type `Never`.

It is an error to call a method, setter, or getter on a receiver of static type
`Never` (including via a null aware operator).

It is an error to apply an expression of `Never` in the function position in a
function call.

It is an error if the static type of `e` in the expression `throw e` is
potentially nullable.

It is not an error for the body of a `lazy` field to reference `this`.

It is an error for a formal parameter to be declared `lazy`.

It is an error if the type `T` in the **on-catch** clause `on T catch` is
potentially nullable.

### Assignability

The definition of assignability is changed as follows.  

A type `T` is **assignable** to a type `S` if `T` is `dynamic`, or if `S` is a
subtype of `T`.

### Generics

The default bound of generic type parameters is treated as `Object?`.

### Type promotion, Definite Assignment, and Definite Completion

### Null promotion

The machinery of type promotion is extended to promote the type of variables
based on nullability checks subject to the same set of restrictions as normal
promotion.  The relevant checks and the types they are considered to promote to
are as follows.

A check of the form `e == null` or of the form `e is Null` where `e` has static
type `T` promotes the type of `e` to `Null` in the `true` continuation, and to
**NonNull**(`T`) in the
`false` continuation.

A check of the form `e != null` or of the form `e is T` where `e` has static
type `T?` promotes the type of `e` to `T` in the `true` continuation, and to
`Null` in the `false` continuation.


The **NonNull** function defines the null-promoted version of a type, and is defined as follows.

- **NonNull**(Null) = Never
- **NonNull**(_C_<_T_<sub>1</sub>, ... , _T_<sub>_n_</sub>>) = _C_<_T_<sub>1</sub>, ... , _T_<sub>_n_</sub>>  for class *C* other than Null
- **NonNull**(FutureOr<_T_>) = FutureOr<_T_>   
- **NonNull**(_T_<sub>0</sub> Function(...)) = _T_<sub>0</sub> Function(...)
- **NonNull**(_Function) = Function
- **NonNull**(Never) = Never
- **NonNull**(dynamic) = dynamic
- **NonNull**(void) = void   
- **NonNull**(_X_) = X & **NonNull**(B), where B is the bound of X.
- **NonNull**(_X_ & T) = X & **NonNull**(T)
- **NonNull**(_T_?) = **NonNull**(_T_)
- **NonNull**(_T_\*) = **NonNull**(_T_)

#### Type promotion, Definite Assignment, and Definite Completion

These are extended as per separate proposal.

### Runtime semantics

#### Null assertion operator

An expression of the form `e!` evaluates `e` to a value `v`, throws a runtime
error if `v` is `null`, and otherwise evaluates to `v`.

#### Null aware operator

An expression of the form `e?.<tail>` where `<tail>` is any sequence of
selectors evaluates to `null` if `e` evaluates to `null`, and otherwise
evaluates to the same value as `e.<tail>`.

An expression of the form `e?..<tail>` where `<tail>` is any sequence of
selectors evaluates to `null` if `e` evaluates to `null`, and otherwise
evaluates to the same value as `e..<tail>`.

**TODO** Define exactly how a valid `<tail>` is delimited.

#### Lazy fields and variables

A read of a field or variable which is marked as `lazy` which has not yet been
written to causes the initializer expression of the variable to be evaluated to
a value, assigned to the variable or field, and returned as the value of the
read.
  - If there is no initializer expression, the read causes a runtime error.
  - Evaluating the initializer expression may validly cause a write to the field
    or variable, assuming that the field or variable is not final.  In this
    case, the variable assumes the written value for the duration of the
    evaluation of the initializer expression, whereupon the final value of the
    initializer expression overwrites the intermediate written value.
  - Evaluating the initializer expression may cause an exception to be thrown.
    If the variable was written to before the exception was thrown, the value of
    the variable on subsequent reads is the written value.  If the variable was
    not written before the exception was thrown, then the next read attempts to
    evaluate the initializer expression again.
  - If a variable or field is read from during the process of evaluating its own
    initializer expression, and no write to the variable has occurred, the read
    is treated as a first read and the initializer expression is evaluated
    again.

A toplevel variable with an initializer is evaluated as if it was marked `lazy`.
Note that this is a change from pre-NNBD semantics in that:
  - Throwing an exception during initializer evaluation no longer sets the
    variable to `null`
  - Reading the variable during initializer evaluation is no longer a

## Core library changes

Calling the `.length` setter on a `List` of non-nullable element type with an
argument greater than the current length of the list is a runtime error.

## Migration features

For migration, we support incremental adoption of non-nullability as described
in
the
[roadmap](https://github.com/dart-lang/language/blob/master/working/0110-incremental-sound-nnbd/roadmap.md).

### Opted in libraries.

Libraries and packages must opt into the feature as described elsewhere.  An
opted-in library may depend on un-opted-in libraries, and vice versa.

### Errors as warnings

When weak null checking is enabled, all errors specified this proposal (that is,
all errors that arise only out of the new features of this proposal) shall be
treated as warnings.

When strong null checking is enabled, errors specified in this proposal shall be
treated as errors.

### Legacy libraries

Static checking for a library which has not opted into this feature (a *legacy*
library) is done using the semantics as of the last version of the language
before this feature ships (or the last version to which it has opted in, if that
is different).  All opted-in libraries upstream from the legacy library are
viewed by the legacy library with nullability related features erased from their
APIs.  In particular:
  - All types of the form `T?` in the opted-in API are treated as `T`.
  - All required named parameters are treated as optional named parameters.
  - The type `Never` is treated as the type `Null`

In a legacy library, none of the new syntax introduced by this proposal is
available, and it is a static error if it is used.


### Importing legacy libraries from opted-in libraries

The type system is extended with a notion of a legacy type operator.  For every
type `T`, there is an additional type `T*` which is the legacy version of the
type.  There is no surface syntax for legacy types, and implementations should
display the legacy type `T*` in the same way that they would display the type
`T`, except in so far as it is useful to communicate to programmers for the
purposes of error messages that the type originates in unmigrated code.

When static checking is done in a migrated library, types which are imported
from unmigrated libraries are seen as legacy types.  However, for the purposes
of type inference in migrated libraries, types imported from unmigrated
libraries shall be treated as non-nullable.  As a result, legacy types will
never appear as type annotations in migrated libraries, nor will they appear in
reified positions.

### Exports

If an unmigrated library re-exports a migrated library, the re-exported symbols
retain their migrated status (that is, downstream migrated libraries will see
their migrated types).

It is an error for a migrated library to re-export symbols from an unmigrated
library.

### Override checking

In an unmigrated library, override checking is done using legacy types.  This
means that an unmigrated library can bring together otherwise incompatible
methods.  When choosing the most specific signature during interface
computation, all nullability and requiredness annotations are ignored, and the
`Never` type is treated as `Null`.

In a migrated library, override checking must check that an override is
consistent with all overridden methods from other migrated libraries in the
super-interface chain, since a legacy library is permitted to override otherwise
incompatible signatures for a method.

## Subtyping

We modify the subtyping rules to account for nullability and legacy types as
specified
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md).

## Upper and lower bounds

**TODO** This is work in progress
