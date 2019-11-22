# Sound non-nullable (by default) types with incremental migration

Author: leafp@google.com

Status: Draft

## CHANGELOG

2019.11.1
  - Clarify runtime instance checks and casts.

2019.10.08
  - Warning to call null check operator on non-nullable expression
  - Factory constructors may not return null
  - Fix discussion of legacy `is` check
  - Specify flatten
2019.04.23:
  - Added specification of short-circuiting null
  - Added `e1?.[e2]` operator syntax

## Summary

This is the proposed specification for [sound non-nullable by default types](http://github.com/dart-lang/language/issues/110).
Discussion of this proposal should take place in [Issue 110](http://github.com/dart-lang/language/issues/110).

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

The precise changes to the syntax are given in an accompanying set of
modifications to the grammar in the formal specification.  This section
summarizes in prose the grammar changes associated with this feature.

The grammar of types is extended to allow any type to be suffixed with a `?`
(e.g. `int?`) indicating the nullable version of that type.

A new primitive type `Never`.  This type is denoted by the built-in type
declaration `Never` declared in `dart:core`.

The grammar of expressions is extended to allow any expression to be suffixed
with a `!`.

The modifier `late` is added as a built-in identifier.  The grammar of top level
variables, static fields, instance fields, and local variables is extended to
allow any declaration to include the modifer `late`.

The modifier `required` is added as a built-in identifier. The grammar of
function types is extended to allow any named parameter declaration to be
prefixed by the `required` modifier (e.g. `int Function(int, {int?  y, required
int z})`. 

The grammar of selectors is extended to allow null-aware subscripting using the
syntax `e1?.[e2]` which evaluates to `null` if `e1` evaluates to `null` and
otherwise evaluates as `e1[e2]`.


### Grammatical ambiguities and clarifications.

#### Nested nullable types

The grammar for types does not allow multiple successive `?` operators on a
type.  That is, the grammar for types is nominally equivalent to:

```
type' ::= functionType
          | qualified typeArguments? 

type ::= type' `?`?
```

#### Conditional expression ambiguities

Conditional expressions inside of braces are ambiguous between sets and maps.
That is, `{ a as bool ? - 3 : 3 }` can be parsed as a set literal `{ (a as bool)
? - 3 : 3 }` or as a map literal `{ (a as bool ?) - 3 : 3 }`.  Parsers will
prefer the former parse over the latter.

The same is true for `{ a is int ? - 3 : 3 }`.

The same is true for `{ int ? - 3 : 3 }` if we allow this.


## Static semantics

### Legacy types

The internal representation of types is extended with a type `T*` for every type
`T` to represent legacy pre-NNBD types.  This is discussed further in the legacy
library section below.

### Future flattening

The **flatten** function is modified as follows:

**flatten**(`T`) is defined by cases on `T`:
  - if `T` is `S?` then **flatten**(`T`) = **flatten**(`S`)`?`
  - otherwise if `T` is `S*` then **flatten**(`T`) = **flatten**(`S`)`*`
  - otherwise if `T` is `FutureOr<S>` then **flatten**(`T`) = `S`
  - otherwise if `T <: Future` then let `S` be a type such that `T <: Future<S>`
and for all `R`, if `T <: Future<R>` then `S <: R`; then **flatten**('T') = `S`
  - otherwise **flatten**('T') = `T`

### Static errors

We say that a type `T` is **nullable** if `Null <: T` and not `T <: Object`.
This is equivalent to the syntactic criterion that `T` is any of:
  - `Null`
  - `S?` for some `S`
  - `S*` for some `S` where `S` is nullable
  - `FutureOr<S>` for some `S` where `S` is nullable
  - `dynamic`
  - `void`

Nullable types are types which are definitively known to be nullable, regardless
of instantiation of type variables, and regardless of any choice of replacement
for the `*` positions (with `?` or nothing).

We say that a type `T` is **non-nullable** if `T <: Object`.
This is equivalent to the syntactic criterion that `T` is any of:
  - `Never`
  - Any function type (including `Function`)
  - Any interface type except `Null`.
  - `S*` for some `S` where `S` is non-nullable
  - `FutureOr<S>` where `S` is non-nullable
  - `X extends S` where `S` is non-nullable
  - `X & S` where `S` is non-nullable

Non-nullable types are types which are either definitively known to be
non-nullable regardless of instantiation of type variables, or for which
replacing the `*` positions with nothing will result in a non-nullable type.

Note that there are types which are neither nullable nor non-nullable.  For
example `X extends T` where `T` is nullable is neither nullable nor
non-nullable.

We say that a type `T` is **potentially nullable** if `T` is not non-nullable.
Note that this is different from saying that `T` is nullable.  For example, a
type variable `X extends Object?` is a type which is potentially nullable but
not nullable.  Note that `T*` is potentially nullable by this definition if `T`
is potentially nullable - so `int*` is not potentially nullable, but `X*` where
`X extends int?` is.  The potentially nullable types include all of the types
which are either definitely nullable, potentially instantiable to a nullable
type, or for which any migration results in a potentially nullable type.

We say that a type `T` is **potentially non-nullable** if `T` is not nullable.
Note that this is different from saying that `T` is non-nullable.  For example,
a type variable `X extends Object?` is a type which is potentially non-nullable
but not non-nullable. Note that `T*` is potentially non-nullable by this
definition if `T` is potentially non-nullable.

It is an error to call a method, setter, getter or operator on an expression
whose type is potentially nullable and not `dynamic`, except for the methods,
setters, getters, and operators on `Object`.

It is an error to read a field or tear off a method from an expression whose
type is potentially nullable and not `dynamic`, except for the methods and
fields on `Object`.

It is an error to call an expression whose type is potentially nullable and not
`dynamic`.

It is an error if a top level variable, static variable, or instance field with
potentially non-nullable type has no initializer expression and is not
initialized in a constructor via an initializing formal or an initializer list
entry, unless the variable or field is marked with the `late` modifier.

It is an error if a potentially non-nullable local variable which has no
initializer expression and is not marked `late` is used before it is definitely
assigned (see Definite Assignment below).

It is an error if a method, function, getter, or function expression with a
potentially non-nullable return type does not definitely complete (see Definite
Completion below).

It is an error if an optional parameter (named or otherwise) with no default
value has a potentially non-nullable type.

It is an error if a required named parameter has a default value.

It is an error if a named parameter that is part of a `required` group is not
bound to an argument at a call site.

It is an error to call the default `List` constructor with a length argument and
a type argument which is potentially non-nullable.

For the purposes of errors and warnings, the null aware operators `?.`, `?..`,
and `?.[]` are checked as if the receiver of the operator had non-nullable type.
More specifically, if the type of the receiver of a null aware operator is `T`,
then the operator is checked as if the receiver had type **NonNull**(`T`) (see
definition below).

It is an error for a class to extend, implement, or mixin a type of the form
`T?` for any `T`.

It is an error for a class to extend, implement, or mixin the type `Never`.

It is an error to call a method, setter, or getter on a receiver of static type
`Never` (including via a null aware operator).

It is an error to apply an expression of type `Never` in the function position
of a function call.

It is an error if the static type of `e` in the expression `throw e` is not
assignable to `Object`.

It is not an error for the body of a `late` field to reference `this`.

It is an error for a formal parameter to be declared `late`.

It is not a compile time error to write to a `final` variable if that variable
is declared `late` and does not have an initializer.

It is an error if the object being iterated over by a `for-in` loop has a static
type which is not `dynamic`, and is not a subtype of `Iterable<dynamic>`.

It is an error if the type of the value returned from a factory constructor is
not a subtype of the class type associated with the class in which it is defined
(specifically, it is an error to return a nullable type from a factory
constructor for any class other than `Null`).

It is a warning to use a null aware operator (`?.`, `?..`, `??`, `??=`, or
`...?`) on a non-nullable value.

It is a warning to use the null check operator (`!`) on a non-nullable
expression.

### Assignability

The definition of assignability is changed as follows.  

A type `T` is **assignable** to a type `S` if `T` is `dynamic`, or if `S` is a
subtype of `T`.

### Generics

The default bound of generic type parameters is treated as `Object?`.

### Type promotion, Definite Assignment, and Definite Completion

**TODO** Fill this out.

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

The static type of an expression `e!` is **NonNull**(`T`) where `T` is the
static type of `e`.

The **NonNull** function defines the null-promoted version of a type, and is
defined as follows.

- **NonNull**(Null) = Never
- **NonNull**(_C_<_T_<sub>1</sub>, ... , _T_<sub>_n_</sub>>) = _C_<_T_<sub>1</sub>, ... , _T_<sub>_n_</sub>>  for class *C* other than Null (including Object).
- **NonNull**(FutureOr<_T_>) = FutureOr<_T_>   
- **NonNull**(_T_<sub>0</sub> Function(...)) = _T_<sub>0</sub> Function(...)
- **NonNull**(Function) = Function
- **NonNull**(Never) = Never
- **NonNull**(dynamic) = dynamic
- **NonNull**(void) = void   
- **NonNull**(_X_) = X & **NonNull**(B), where B is the bound of X.
- **NonNull**(_X_ & T) = X & **NonNull**(T)
- **NonNull**(_T_?) = **NonNull**(_T_)
- **NonNull**(_T_\*) = **NonNull**(_T_)

#### Extended Type promotion, Definite Assignment, and Definite Completion

These are extended as per separate proposal.

### Runtime semantics

#### Null check operator

An expression of the form `e!` evaluates `e` to a value `v`, throws a runtime
error if `v` is `null`, and otherwise evaluates to `v`.

#### Null aware operator

The semantics of the null aware operator `?.` are defined via a source to source
translation of expressions into Dart code extended with a let binding construct.
The translation is defined using meta-level functions over syntax.  We use the
notation `fn[x : Exp] : Exp => E` to define a meta-level function of type `Exp
-> Exp` (that is, a function from expressions to expressions), and similarly
`fn[k : Exp -> Exp] : Exp => E` to define a meta-level function of type `Exp ->
Exp -> Exp`.  Where obvious from context, we elide the parameter and return
types on the meta-level functions.  The meta-variables `F` and `G` are used to
range over meta-level functions. Application of a meta-level function is written
as `F[p]` where `p` is the argument.

The null-shorting translation of an expression `e` is meta-level function `F` of
type `Exp -> Exp -> Exp` which takes as an argument the continuation of `e` and
produces an expression semantically equivalent to `e` with all occurrences of
`?.` eliminated in favor of explicit sequencing using a `let` construct.

Let `ID` be the identity function `fn[x : Exp] : Exp => x`.

The expression translation of an expression `e` is the result of applying the
null-shorting translation of `e` to `ID`.  That is, if `e` translates to `F`,
then `F[ID]` is the expression translation of `e`.

We use `EXP(e)` as a shorthand for the expression translation of `e`.  That is,
if the null-shorting translation of `e` is `F`, then `EXP(e)` is `F[ID]`.

We extend the expression translation to argument lists in the obvious way, using
`ARGS(args)` to denote the result of applying the expression translation
pointwise to the arguments in the argument list `args`.

We use three combinators to express the translation.

The null-aware shorting combinator `SHORT` is defined as:
```
  SHORT = fn[r : Exp, c : Exp -> Exp] =>
              fn[k : Exp -> Exp] : Exp =>
                let x = r in x == null ? null : k[c[x]]
```

where `x` is a fresh object level variable.  The `SHORT` combinator is used to
give semantics to uses of the `?.` operator.  It is parameterized over the
receiver of the conditional property access (`r`) and a meta-level function
(`c`) which given an object-level variable (`x`) bound to the result of
evaluating the receiver, produces the final expression.  The result is
parameterized over the continuation of the expression being translated.  The
continuation is only called in the case that the result of evaluating the
receiver is non-null.

The shorting propagation combinator `PASSTHRU` is defined as:
```
  PASSTHRU = fn[F : Exp -> Exp -> Exp, c : Exp -> Exp] =>
               fn[k : Exp -> Exp] : Exp => F[fn[x] => k[c[x]]]
```

The `PASSTHRU` combinator is used to give semantics to expression forms which
propagate null-shorting behavior.  It is parameterized over the translation `F`
of the potentially null-shorting expression, and over a meta-level function `c`
which given an expression which denotes the value of the translated
null-shorting expression produces the final expression being translated.  The
result is parameterized over the continuation of the expression being
translated, which is called unconditionally.

The null-shorting termination combinator TERM is defined as:
```
  TERM = fn[r : Exp] => fn[k : Exp -> Exp] : Exp => k[r]
```

The `TERM` combinator is used to give semantics to expressions which neither
short-circuit nor propagate null-shorting behavior.  It is parameterized over
the translated expression, and simply passes on the expression to its
continuation.

- A property access `e?.f` translates to:
  - `SHORT[EXP(e), fn[x] => x.f]`
- If `e` translates to `F` then `e.f` translates to:
  - `PASSTHRU[F, fn[x] => x.f]`
- A null aware method call `e?.m(args)` translates to:
  - `SHORT[EXP(e), fn[x] => x.m(ARGS(args))]`
- If `e` translates to `F` then `e.m(args)` translates to:
  - `PASSTHRU[F, fn[x] => x.m(ARGS(args))]`
- If `e` translates to `F` then `e(args)` translates to:
  - `PASSTHRU[F, fn[x] => x(ARGS(args))]`
- If `e1` translates to `F` then `e1?.[e2]` translates to:
  - `SHORT[EXP(e1), fn[x] => x[EXP(e2)]]`
- If `e1` translates to `F` then `e1[e2]` translates to:
  - `PASSTHRU[F, fn[x] => x[EXP(e2)]]`
- The assignment `e1?.f = e2` translates to:
  - `SHORT[EXP(e1), fn[x] => x.f = EXP(e2)]`
- The other assignment operators are handled equivalently.
- If `e1` translates to `F` then `e1.f = e2` translates to:
  - `PASSTHRU[F, fn[x] => x.f = EXP(e2)]`
- The other assignment operators are handled equivalently.
- If `e1` translates to `F` then `e1?.[e2] = e3` translates to:
  - `SHORT[EXP(e1), fn[x] => x[EXP(e2)] = EXP(e3)]`
- The other assignment operators are handled equivalently.
- If `e1` translates to `F` then `e1[e2] = e3` translates to:
  - `PASSTHRU[F, fn[x] => x[EXP(e2)] = EXP(e3)]`
- The other assignment operators are handled equivalently.
- A cascade expression `e..s` translates as follows, where `F` is the
    translation of `e` and  `x` and `y` are fresh object level variables:
    ```
        fn[k : Exp -> Exp] : Exp =>
           F[fn[r : Exp] : Exp => let x = r in
                                  let y = EXP(x.s)
                                  in k[x]
           ]
    ```
- A null-shorting cascade expression `e?..s` translates as follows, where `x`
    and `y` are fresh object level variables.
    ```
       fn[k : Exp -> Exp] : Exp =>
           let x = EXP(e) in x == null ? null : let y = EXP(x.s) in k(x)
    ```
- All other expressions are translated compositionally using the `TERM`
  combinator.  Examples:
  - An identifier `x` translates to `TERM[x]`
  - A list literal `[e1, ..., en]` translates to `TERM[ [EXP(e1), ..., EXP(en)] ]`
  - A parenthesized expression `(e)` translates to `TERM[(EXP(e))]`

#### Late fields and variables

A read of a field or variable which is marked as `late` which has not yet been
written to causes the initializer expression of the variable to be evaluated to
a value, assigned to the variable or field, and returned as the value of the
read.
  - If there is no initializer expression, the read causes a runtime error.
  - Evaluating the initializer expression may validly cause a write to the field
    or variable, assuming that the field or variable is not final.  In this
    case, the variable assumes the written value.  The final value of the
    initializer expression overwrites any intermediate written values.
  - Evaluating the initializer expression may cause an exception to be thrown.
    If the variable was written to before the exception was thrown, the value of
    the variable on subsequent reads is the last written value.  If the variable
    was not written before the exception was thrown, then the next read attempts
    to evaluate the initializer expression again.
  - If a variable or field is read from during the process of evaluating its own
    initializer expression, and no write to the variable has occurred, the read
    is treated as a first read and the initializer expression is evaluated
    again.

A write to a field or variable which is marked `final` and `late` is a runtime
error unless the field or variable was declared with no initializer expression,
and there have been no previous writes to the field or variable (including via
an initializing formal or an initializer list entry).

Overriding a field which is marked both `final` and `late` with a member which
does not otherwise introduce a setter introduces an implicit setter which
throws.  For example:

```
class A {
  late final int x;
}
class B extends A {
  int get x => 3;
}
class C extends A {
  late final int x = 3;
}
void test() {
   Expect.throws(() => new B().x = 3);
   Expect.throws(() => new C().x = 3);
}
```

A toplevel or static variable with an initializer is evaluated as if it
was marked `late`.  Note that this is a change from pre-NNBD semantics in that:
  - Throwing an exception during initializer evaluation no longer sets the
    variable to `null`
  - Reading the variable during initializer evaluation is no longer checked for,
    and does not cause an error.


## Core library changes

Calling the `.length` setter on a `List` of non-nullable element type with an
argument greater than the current length of the list is a runtime error.

## Migration features

For migration, we support incremental adoption of non-nullability as described
at a high level in
the
[roadmap](https://github.com/dart-lang/language/blob/master/accepted/future-releases/nnbd/roadmap.md).

### Opted in libraries.

Libraries and packages must opt into the feature as described elsewhere.  An
opted-in library may depend on un-opted-in libraries, and vice versa.

### Errors as warnings

Weak null checking is enabled as soon as a package or library opts into this
feature. When weak null checking is enabled, all errors specified this proposal
(that is, all errors that arise only out of the new features of this proposal)
shall be treated as warnings.

Strong null checking is enabled by running the compilation or execution
environment with the appropriate flags.  When strong null checking is enabled,
errors specified in this proposal shall be treated as errors.

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
from unmigrated libraries are seen as legacy types.  However, type inference in
the migrated library "erases" legacy types.  That is, if a missing type
parameter, local variable type, or closure type is inferred to be a type `T`,
all occurrences of `S*` in `T` shall be replaced with `S`.  As a result, legacy
types will never appear as type annotations in migrated libraries, nor will they
appear in reified positions.

### Type reification

All types reified in legacy libraries are reified as legacy types.  Runtime
subtyping checks treat them according to the subtyping rules specified
separately.

### Runtime checks and weak checking

When weak checking is enabled, runtime type tests (including explicit and
implicit casts) shall succeed whenever the runtime type test would have
succeeded if all `?` on types were ignored, `*` was added to each type, and
`required` parameters were treated as optional.  This has the effect of treating
`Never` as equivalent to `Null`, restoring `Null` to the bottom of the type
hierarchy, treating `Object` as nullable, and ignoring `required` on named
parameters.  This is intended to provide the same subtyping results as pre-nnbd
Dart.

Instance checks (`e is T`) and casts (`e as T`) behave differently when run in
strong vs weak checking mode.

Let `LEGACY_SUBTYPE(S, T)` be true iff `S` is a subtype of `T` in the modified
semantics as described above: that is, with all `?` on types ignored, `*` added
to each type, and `required` parameters treated as optional.

Let `NNBD_SUBTYPE(S, T)` be true iff `S` is a subtype of `T` as specified in the
[NNBD subtyping rules](https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md).

We define the weak checking and strong checking mode instance tests as follows:

**In weak checking mode**: if `e` evaluates to a value `v` and `v` has runtime
type `S`, an instance check `e is T` occurring in a **legacy library** is
evaluated as follows:
  - If `S` is `Null` return `LEGACY_SUBTYPE(T, NULL) || LEGACY_SUBTYPE(Object,
    T)`
  - Otherwise return `LEGACY_SUBTYPE(S, T)`

**In weak checking mode**: if `e` evaluates to a value `v` and `v` has runtime
type `S`, an instance check `e is T` occurring in an **opted-in library** is
evaluated as follows:
  - If `S` is `Null` return `NNBD_SUBTYPE(NULL, T)`
  - Otherwise return `LEGACY_SUBTYPE(S, T)`

**In strong checking mode**: if `e` evaluates to a value `v` and `v` has runtime
type `S`, an instance check `e is T` textually occurring in a **legacy library**
is evaluated as follows:
  - If `S` is `Null` return `NNBD_SUBTYPE(T, NULL) || NNBD_SUBTYPE(Object, T)`
  - Otherwise return `NNBD_SUBTYPE(S, T)`

**In strong checking mode**: if `e` evaluates to a value `v` and `v` has runtime
type `S`, an instance check `e is T` textually occurring in an **opted-in
library** is evaluated as follows:
  - return `NNBD_SUBTYPE(S, T)`

We define the weak checking and strong checking mode casts as follows:

**In weak checking mode**: if `e` evaluates to a value `v` and `v` has runtime
type `S`, a cast `e as T` **whether textually occurring in a legacy or opted-in
library** is evaluated as follows:
  - if `LEGACY_SUBTYPE(S, T)` then `e as T` evaluates to `v`.  Otherwise a
    `CastError` is thrown.

**In strong checking mode**: if `e` evaluates to a value `v` and `v` has runtime
type `S`, a cast `e as T` **whether textually occurring in a legacy or opted-in
library** is evaluated as follows:
  - if `NNBD_SUBTYPE(S, T)` then `e as T` evaluates to `v`.  Otherwise a
    `CastError` is thrown.


In weak checking mode, we ensure that opted-in libraries do not break downstream
clients by continuing to evaluate instance checks and casts with the same
semantics as in pre-nnbd Dart.  All runtime subtype checks are done using the
legacy subtyping, and instance checks maintain the pre-nnbd behavior on `null`
instances.  In strong checking mode, we use the specified nnbd subtyping for all
instance checks and casts.  However, in legacy libraries, we continue to
specifically reject instance tests on `null` instances unless the tested type is
a bottom or top type.  The rationale for this is that type tests performed in a
legacy library will generally be performed with a legacy type as the tested
type.  Without specifically rejecting `null` instances, successful instance
checks in legacy libraries would no longer guarantee that the tested object is
not `null` - a regression relative to the weak checking.

When developers enable strong checking in their tests and applications, new
runtime cast failures may arise.  The process of migrating libraries and
applications will require users to track down these changes in behavior.
Development platforms are encouraged to provide facilities to help users
understand these changes: for example, by providing a debugging option in which
instance checks or casts which would result in a different outcome if run in
strong checking mode vs weak checking mode are flagged for the developer by
logging a warning or breaking to the debugger.

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
