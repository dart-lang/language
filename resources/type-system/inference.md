# Top-level and local type inference

Owner: leafp@google.com

Status: Draft

## CHANGELOG

2023.06.24
  - Adjust function literal return type inference to avoid spurious application
    of `flatten`, and make sure return statements do not affect generator
    functions.
  - Specify the value context to use for generator functions for more
    non-trivial return types (not just `Iterable<X>` for some `X`).

2022.05.12
  - Define the notions of "constraint solution for a set of type variables" and
    "Grounded constraint solution for a set of type variables".  These
    definitions capture how type inference handles type variable bounds, as well
    as how inferred types become "frozen" once they are fully known.

2019.09.01
  - Fix incorrect placement of left top rule in constraint solving.

2019.09.01
  - Add left top rule to constraint solving.
  - Specify inference constraint solving.

2020.07.20
  - Clarify that some rules are specific to code without/with null safety.
    'Without null safety, ...' respectively 'with null safety, ...' is used
    to indicate such rules, and the remaining text is applicable in both cases.

2020.07.14:
  - Infer return type `void` from context with function literals.

2020.06.04:
  - Make conflict resolution for override inference explicit.

2020.06.02
  - Account for the special treatment of bottom types during function literal
  inference.

2020.05.27
  - Update function literal return type inference to use
    **futureValueTypeSchema**.

2019.12.03:
  - Update top level inference for non-nullability, function expression
    inference.


## Inference overview

Type inference in Dart takes three different forms.  The first is mixin
inference, which is
specified
[elsewhere](https://github.com/dart-lang/language/blob/master/accepted/2.1/super-mixins/mixin-inference.md).
The second and third forms are local type inference and top-level inference.
These two forms of inference are mutually interdependent, and are specified
here.

Top-level inference is the process by which the types of top-level variables and
several kinds of class members are inferred when type annotations are omitted,
based on the types of overridden members and initializing expressions.  Since
some top-level declarations have their types inferred from initializing
expressions, top-level inference involves local type inference as a
sub-procedure.

Local type inference is the process by which the types of local variables and
closure parameters declared without a type annotation are inferred; and by which
missing type arguments to list literals, map literals, set literals, constructor
invocations, and generic method invocations are inferred.


## Top-level inference

Top-level inference derives the type of declarations based on two sources of
information: the types of overridden declarations, and the types of initializing
expressions.  In particular:

1. **Method override inference**
    * If you omit a return type or parameter type from an overridden or
    implemented method, inference will try to fill in the missing type using the
    signature of the methods you are overriding.
2. **Static variable and field inference**
    * If you omit the type of a field, setter, or getter, which overrides a
   corresponding member of a superclass, then inference will try to fill in the
   missing type using the type of the corresponding member of the superclass.
    * Otherwise, declarations of static variables and fields that omit a type
   will be inferred from their initializer if present.

As a general principle, when inference fails it is an error.  Tools are free to
behave in implementation specific ways to provide a graceful user experience,
but with respect to the language and its semantics, programs for which inference
fails are unspecified.

Some broad principles for type inference that the language team has agreed to,
and which this proposal is designed to satisfy:
* Type inference should be free to fail with an error, rather than being
  required to always produce some answer.
* It should not be possible for a programmer to observe a declaration as having
  two different types at difference points in the program (e.g. dynamic for
  recursive uses, but subsequently int).  Some consistent answer (or an error)
  should always be produced.  See the example below for an approach that
  violates this principle.
* The inference for local variables, top-level variables, and fields, should
  either agree or error out.  The same expression should not be inferred
  differently at different syntactic positions.  It’s ok for an expression to be
  inferrable at one level but not at another.
* Obvious types should be inferred.
* Inferred and annotated types should be treated the same.
* As much as possible, there should be a simple intuition for users as to how
  inference proceeds.
* Inference should be as efficient to implement as possible.
* Type arguments should be mostly inferred.

### Top-level inference procedure

For simplicity of specification, inference of method signatures and inference of
signatures of other declaration forms are specified uniformly.  Note however
that method inference never depends on inference for any other form of
declaration, and hence can validly be performed independently before inferring
other declarations.

Because of the possibility of inference dependency cycles between top-level
declarations, the inference procedure relies on the set of *available* variables
(*which are the variables for which a type is known*).  A variable is
*available* iff:
  - The variable was explicitly annotated with a type by the programmer.
  - A type for the variable was previously inferred.

Any variable which is not *available* is said to be *unavailable*.  If the
inference process requires the type of an *unavailable* variable in order to
proceed, it is an error.  **If there is any order of inference of declarations
which avoids such an error, the inference procedure is required to find it**.  A
valid implementation strategy for finding such an order is to explicitly
maintain the set of variables which are in the process of being inferred, and to
then recursively infer the types of any variables which are: required for
inference to proceed, but are not *available*, but are also not in the process
of being inferred.  To see this, note that if the type of a variable `x` which
is in the process of being inferred is required during the process of inferring
the type of a variable `y`, then inferring the type of `x` must have directly or
indirectly required inferring the type of `y`.  Any order of inference of
declarations must either have chosen to infer `x` or `y` first, and in either
case, the type of the other is both required, and *unavailable*, and hence will
be an error.

#### General top-level inference

The general inference procedure is as follows.

- Mark every top level, static or instance declaration (fields, setters,
  getters, constructors, methods) which is completely type annotated (that is,
  which has all parameters, return types and field types explicitly annotated)
  as *available*.
- For each declaration `D` which is not *available*:
  - If `D` is a method, setter or getter declaration with name `x`:
    - If `D` overrides another method, field, setter, or getter
        - Perform override inference on `D`.
        - Record the type of `x` and mark `x` as *available*.
    - Otherwise record the type of `x` as the type obtained by replacing an
      omitted setter return type with `void` and replacing any other omitted
      types with `dynamic`, and mark `x` as *available*.
  - If `D` is a declaration of a top-level variable or a static field
    declaration or an instance field declaration, declaring the name `x`:
    - if `D` overrides another field, setter, or getter
        - Perform override inference on `D`.
        - Record the type of `x` and mark `x` as *available*.
    - Otherwise, if `D` has an initializing expression `e`:
      - Perform local type inference on `e`.
      - Let `T` be the inferred type of `e`, or `dynamic` if the inferred type
        of `e` is a subtype of `Null`.  Record the type of `x` to be `T` and
        mark `x` as *available*.
    - Otherwise record the type of `x` to be `dynamic` and mark `x` as
      *available*.
  - If `D` is a constructor declaration `C(...)` for which one or more of the
    parameters is declared as an initializing formal without an explicit type:
    - Perform top-level inference on each of the fields used as an initializing
      formal for `C`.
    - Record the inferred type of `C`, and mark it as *available*.


#### Override inference

If override inference is performed on a declaration `D`, and any member which is
directly overridden by `D` is not *available*, it is an error.  As noted above,
the inference algorithm is required to find an ordering which avoids such an
error if there is such an ordering.  Note that method override inference is
independent of non-override inference, and hence can be completed prior to the
rest of top level inference if desired.


##### Method override inference

A method `m` of a class `C` is subject to override inference if it is
missing one or more component types of its signature, and one or more of
the direct superinterfaces of `C` has a member named `m` (*that is, `C.m`
overrides one or more declarations*).  Each missing type is filled in with
the corresponding type from the combined member signature `s` of `m` in the
direct superinterfaces of `C`.

A compile-time error occurs if `s` does not exist.  *E.g., one
superinterface could have signature `void m([int])` and another one could
have signature `void m(num)`, such that none of them is most specific.
There may still exist a valid override of both (e.g., `void m([num])`).  In
this situation `C.m` can be declared with a complete signature, it just
cannot use override inference.*

If there is no corresponding parameter in `s` for a parameter of the
declaration of `m` in `C`, it is treated as `dynamic` (*e.g., this occurs
when overriding a one parameter method with a method that takes a second
optional parameter*).

*Note that override inference does not provide other properties of a
parameter than the type. E.g., it does not make a parameter `required`
based on overridden declarations. This property must then be specified
explicitly if needed.*


##### Instance field, getter, and setter override inference

The inferred type of a getter, setter, or field is computed as follows.  Note
that we say that a setter overrides a getter if there is a getter of the same
name in some superclass or interface (explicitly declared or induced by an
instance variable declaration), and similarly for getters overriding setters,
fields, etc.

The return type of a getter, parameter type of a setter or type of a field
which overrides/implements only one or more getters is inferred to be the
return type of the combined member signature of said getter in the direct
superinterfaces.

The return type of a getter, parameter type of a setter or type of a field
which overrides/implements only one or more setters is inferred to be the
parameter type of the combined member signature of said setter in the
direct superinterfaces.

The return type of a getter which overrides/implements both a setter and a
getter is inferred to be the return type of the combined member signature
of said getter in the direct superinterfaces.

The parameter type of a setter which overrides/implements both a setter and
a getter is inferred to be the parameter type of the combined member
signature of said setter in the direct superinterfaces.

The type of a final field which overrides/implements both a setter and a
getter is inferred to be the return type of the combined member signature
of said getter in the direct superinterfaces.

The type of a non-final field which overrides/implements both a setter and
a getter is inferred to be the parameter type of the combined member
signature of said setter in the direct superinterfaces, if this type is the
same as the return type of the combined member signature of said getter in
the direct superinterfaces. If the types are not the same then inference
fails with an error.

Note that overriding a field is addressed via the implicit induced getter/setter
pair (or just getter in the case of a final field).

Note that `late` fields are inferred exactly as non-`late` fields.  However,
unlike normal fields, the initializer for a `late` field may reference `this`.


## Function literal return type inference.

Function literals which are inferred in an empty typing context (see below) are
inferred using the declared type for all of their parameters.  If a parameter
has no declared type, it is treated as if it was declared with type `dynamic`.
Inference for each returned or yielded expression in the body of the function
literal is done with an empty _value context_ scheme (see below).

Function literals which are inferred in an non-empty typing context where the
context type is a function type are inferred as described here.

Each parameter is assumed to have its declared type if present.  If no type is
declared for a parameter and there is a corresponding parameter in the context
type schema with type schema `K`, the parameter is given an inferred type `T`
where `T` is derived from `K` as follows.  If the greatest closure of `K` is `S`
and `S` is a subtype of `Null`, then without null safety `T` is `dynamic`, and
with null safety `T` is `Object?`. Otherwise, `T` is `S`. If there is no
corresponding parameter in the context type schema, the variable is treated as
having type `dynamic`.

The return type of the context function type is used at several points during
inference. We refer to this type as the **imposed return type schema**.

Inference for each returned or yielded expression in the body of the
function literal is done using a **value context** type scheme derived from the
imposed return type schema `S` as follows:
  - If function is declared `async`, then without null safety,
    the value context scheme is **flatten**(`S`);
    with null safety the value context scheme is
    **futureValueTypeSchema**(`S`), as defined below.
  - If the function expression is declared `async*` then the value context
    scheme is **streamElementTypeSchema**(`S`), as defined below.
  - If the function expression is declared `sync*` then the value context
    scheme is **iterableElementTypeSchema**(`S`), as defined below.
  - If the function expression is neither `async` nor a generator, then the
    value context scheme is `S`.

The function **futureValueTypeSchema** is defined as follows:

- **futureValueTypeSchema**(`S?`) = **futureValueTypeSchema**(`S`), for all `S`.
- **futureValueTypeSchema**(`S*`) = **futureValueTypeSchema**(`S`), for all `S`.
- **futureValueTypeSchema**(`Future<S>`) = `S`, for all `S`.
- **futureValueTypeSchema**(`FutureOr<S>`) = `S`, for all `S`.
- **futureValueTypeSchema**(`void`) = `void`.
- **futureValueTypeSchema**(`dynamic`) = `dynamic`.
- **futureValueTypeSchema**(`_`) = `_`.
- Otherwise, for all other `S`, **futureValueTypeSchema**(`S`) = `Object?`.

The function **streamElementTypeSchema** is defined as follow:

- **streamElementTypeSchema**(`S?`) = **streamElementTypeSchema**(`S`),
    for all `S`.
- **streamElementTypeSchema**(`S*`) = **streamElementTypeSchema**(`S`),
    for all `S`.
- **streamElementTypeSchema**(`FutureOr<S>`) = **streamElementTypeSchema**(`S`),
    for all `S`.
- **streamElementTypeSchema**(`Stream<S>`) = `S`, for all `S`.
- **streamElementTypeSchema**(`void`) = `void`
- **streamElementTypeSchema**(`dynamic`) = `dynamic`
- **streamElementTypeSchema**(`_`) = `_`
- Otherwise, for all other `S`, **streamElementTypeSchema**(`S`) = `Object?`.

The function **iterableElementTypeSchema** is defined as follow:

- **iterableElementTypeSchema**(`S?`) = **iterableElementTypeSchema**(`S`),
    for all `S`.
- **iterableElementTypeSchema**(`S*`) = **iterableElementTypeSchema**(`S`),
    for all `S`.
- **iterableElementTypeSchema**(`FutureOr<S>`) =
    **iterableElementTypeSchema**(`S`), for all `S`.
- **iterableElementTypeSchema**(`Iterable<S>`) = `S`, for all `S`.
- **iterableElementTypeSchema**(`void`) = `void`
- **iterableElementTypeSchema**(`dynamic`) = `dynamic`
- **iterableElementTypeSchema**(`_`) = `_`
- Otherwise, for all other `S`, **iterableElementTypeSchema**(`S`) = `Object?`.

_Note that it is a compile-time error unless the return type of an
asynchronous non-generator function is a supertype of `Future<Never>`,
which means that the last case of **futureValueTypeScheme** will only
be applied when `S` is `Object`.
Similarly for `async*` and `sync*` functions whose return types
must be a supertypes of `Stream<Never>` and `Iterable<Never>`._

In order to infer the return type of a function literal, we first infer the
**actual value type** of the function literal. _The actual value type
represents the types of the actual values returned by non-generator functions,
and the values emitted by generator functions._

Let `K` be the value context schema for the function body as computed above
from the imposed return type schema.
_When we refer to the _inferred type_ of an expression with a typing context,
it is the type inferred using the local type inference algorithm
described below._

The actual value type of a function literal with an expression body, `=> e`,
_(which cannot be a generator function)_ is computed as follows:
  - If the enclosing function is marked `async`,
    let `T` be the inferred type of the returned expession with `FutureOr<K>`
    as typing context.
    The actual value type is **flatten**(`T`).
  - If the enclosing function is not marked `async`, let `T` be the inferred
    type of the returned expression with typing context `K`.
    The actually value type is `T`.

The actual value type of a function literal with a block body is computed as
follows.
Let `T` be `Never` if the function is a generator function,
or if every control path through the block exits the block without
reaching the end of the block, as computed by the **definite completion**
analysis specified elsewhere.
Otherwise _(the function is a non-generator function and at least
one control path reaches the end of the block)_ let `T` be `null`.

Then process relevant statements of the block, one by one in source order,
to find a value type `V` for that statement.

  - If the enclosing function is a non-`async` non-generator function,
    the relevant statements are `return;` or `return e;` statements.
    -   For a `return;` statement, let `V` be `Null`.
    -   For a `return e;` statement, let `V` be the inferred type of `e` with
        `K` as context type scheme, using the local type inference algorithm
        described below.

  - If the enclosing function is marked `async`, the relevant statements
     are `return;` and `return e;` statements.
    * For a `return;` statement, let `V` be `Null`.
    * For a `return e;` statement, let `S` be the inferred type of `e`
      with typing context `_` if `K` is `_`,
      and with typing context `FutureOr<K>` if `K` is not `_`,
      Let `V` be **flatten**(`S`).

  - If the enclosing function is marked `sync*`, the relevant statements
    are `yield e;` or `yield* e;` statement.
    * For a `yield e;` statement, let `V` be the inferred type of `e` with
      typing context `K`.
    * For a `yield* e;` statement, let `S` be the inferred type of `e` with
      typing context `Iterable<K>`.
      If `S` implements `Iterable<R>` for some `R`, let `V` be `R`.
      Otherwise let `V` be `S`.
      _It is a compile-time error if `S` is not a assignable to
      `Iterable<Object?>`, so either `S` implements `Iterable`,
      or it is one of `dynamic` or `Never`._

  - If the enclosing function is marked `async*`, the relevant statements are
    `yield e;` or `yield* e;` statements.
    * For a `yield e;` statement, let `V` be the inferred type of `e` with
      typing context `K`.
    * For a `yield* e;` statement, let `S` be the inferred type of `e` with
      typing context `Stream<K>`.
      If `S` implements `Stream<R>` for some `R`, let `V` be `R`.
      Otherwise let `V` be `S`.
      _It is a compile-time error if `S` is not a assignable to
      `Stream<Object?>`, so either `S` implements `Stream`,
      or it is one of `dynamic` or `Never`._

After processing each relevant statement, update `T` to be **UP**(`T`, `V`).

The **actual value type** of the function literal is the value of `T` after
all relevant `return` and `yield` statements in the block body have been
processed.

Let `T` be the **actual value type** of a function literal as computed above.
Let `R` be the greatest closure of the typing context `K` as computed above.

With null safety, if `R` is `void`, let `S` be `void`
_(without null-safety: no special treatment is applicable to `void`)_.

Otherwise (_without null safety or if `R` is not `void`_),
if `T <: R` then let `S` be `T`, else let `S` be `R`.  The
inferred return type of the function literal is then defined as follows:

  - If the function literal is marked `async` then the inferred return type is
    `Future<S>`.
  - If the function literal is marked `async*` then the inferred return type is
    `Stream<S>`.
  - If the function literal is marked `sync*` then the inferred return type is
    `Iterable<S>`.
  - Otherwise, the inferred return type is `S`.

## Local return type inference.

Without null safety, a local function definition which has no explicit return
type is subject to the same return type inference as a function expression with
no typing context.  During inference of the function body, any recursive calls
to the function are treated as having return type `dynamic`.

With null safety, local function body inference is changed so that the local
function name is not considered *available* for inference while performing
inference on the body.  As a result, any recursive calls to the function for
which the result type is required for inference to complete will no longer be
treated as having return type `dynamic`, but will instead result in an inference
failure.

## Local type inference

When type annotations are omitted on local variable declarations and function
literals, or when type arguments are omitted from literal expressions,
constructor invocations, or generic function invocations, then local type
inference is used to fill in the missing type information.  Local type inference
is also used as part of top-level inference as described above, in order to
infer types for initializer expressions.  In order to uniformly treat use of
local type inference in top-level inference and in method body inference, it is
defined with respect to a set of *available* variables as defined above.  Note
however that top-level inference never depends on method body inference, and so
method body inference can be performed as a subsequent step.  If this order of
inference is followed, then method body inference should never fail due to a
reference to an *unavailable* variable, since local variable declarations can
always be traversed in an appropriate statically pre-determined order.

### Types

We define inference using types as defined in
the
[informal specification of subtyping](https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md),
with the same meta-variable conventions.  Specifically:

The meta-variables `X`, `Y`, and `Z` range over type variables.

The meta-variable `L` ranges over lists or sets of type variables.

The meta-variables `T`, `S`, `U`, and `V` range over types.

The meta-variable `C` ranges over classes.

The meta-variable `B` ranges over types used as bounds for type variables.

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

### Type schemas

Local type inference uses a notion of `type schema`, which is a slight
generalization of the normal Dart type syntax.  The grammar of Dart types is
extended with an additional construct `_` which can appear anywhere that a type
is expected.  The intent is that `_` represents a component of a type which has
not yet been fixed by inference.  Type schemas cannot appear in programs or in
final inferred types: they are purely part of the specification of the local
inference process.  In this document, we sometimes refer to `_` as "the unknown
type".

It is an invariant that a type schema will never appear as the right hand
component of a promoted type variable `X & T`.

The meta-variables `P` and `Q` range over type schemas.

### Variance

We define the notion of the covariant, contravariance, and invariant occurrences
of a type `T` in another type `S` inductively as follows.  Note that this
definition of variance treats type aliases transparently: that is, the variance
of a type which is used as an argument to a type alias is computed by first
expanding the type alias (substituting actuals for formals) and then computing
variance on the result.  This means that the only invariant positions in any
type (given the current Dart type system) are in the bounds of generic function
types.

The covariant occurrences of a type (schema) `T` in another type (schema) `S` are:
  - if `S` and `T` are the same type,
    - `S` is a covariant occurrence of `T`.
  - if `S` is `Future<U>`
    - the covariant occurrences of `T` in `U`
  - if `S` is `FutureOr<U>`
    - the covariant occurrencs of `T` in `U`
  - if `S` is an interface type `C<T0, ..., Tk>`
    - the union of the covariant occurrences of `T` in `Ti` for `i` in `0, ..., k`
  - if `S` is `U Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn, [Tn+1 xn+1, ..., Tm xm])`,
      the union of:
    - the covariant occurrences of `T` in `U`
    - the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
  - if `S` is `U Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the covariant occurrences of `T` in `U`
    - the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
  - if `S` is `(T0, ..., Tn, {Tn+1 xn+1, ..., Tm xm})`,
    - the covariant occurrences of `T` in `Ti` for `i` in `0, ..., m`

The contravariant occurrences of a type `T` in another type `S` are:
  - if `S` is `Future<U>`
    - the contravariant occurrences of `T` in `U`
  - if `S` is `FutureOr<U>`
    - the contravariant occurrencs of `T` in `U`
  - if `S` is an interface type `C<T0, ..., Tk>`
    - the union of the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., k`
  - if `S` is `U Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn, [Tn+1 xn+1, ..., Tm xm])`,
      the union of:
    - the contravariant occurrences of `T` in `U`
    - the covariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
  - if `S` is `U Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the contravariant occurrences of `T` in `U`
    - the covariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
  - if `S` is `(T0, ..., Tn, {Tn+1 xn+1, ..., Tm xm})`,
    - the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., m`

The invariant occurrences of a type `T` in another type `S` are:
  - if `S` is `Future<U>`
    - the invariant occurrences of `T` in `U`
  - if `S` is `FutureOr<U>`
    - the invariant occurrencs of `T` in `U`
  - if `S` is an interface type `C<T0, ..., Tk>`
    - the union of the invariant occurrences of `T` in `Ti` for `i` in `0, ..., k`
  - if `S` is `U Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn, [Tn+1 xn+1, ..., Tm xm])`,
      the union of:
    - the invariant occurrences of `T` in `U`
    - the invariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
    - all occurrences of `T` in `Bi` for `i` in `0, ..., k`
  - if `S` is `U Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the invariant occurrences of `T` in `U`
    - the invariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
    - all occurrences of `T` in `Bi` for `i` in `0, ..., k`
  - if `S` is `(T0, ..., Tn, {Tn+1 xn+1, ..., Tm xm})`,
    - the invariant occurrences of `T` in `Ti` for `i` in `0, ..., m`

### Type variable elimination (least and greatest closure of a type)

Given a type `S` and a set of type variables `L` consisting of the variables
`X0, ..., Xn`, we define the least and greatest closure of `S` with respect to
`L` as follows.

We define the least closure of a type `M` with respect to a set of type
variables `X0, ..., Xn` to be `M` with every covariant occurrence of `Xi`
replaced with `Never`, and every contravariant occurrence of `Xi` replaced with
`Object?`.  The invariant occurrences are treated as described explicitly below.

We define the greatest closure of a type `M` with respect to a set of type
variables `X0, ..., Xn` to be `M` with every contravariant occurrence of `Xi`
replaced with `Never`, and every covariant occurrence of `Xi` replaced with
`Object?`. The invariant occurrences are treated as described explicitly below.

- If `S` is `X` where `X` is in `L`
  - The least closure of `S` with respect to `L` is `Never`
  - The greatest closure of `S` with respect to `L` is `Object?`
- If `S` is a base type (or in general, if it does not contain any variable from
  `L`)
  - The least closure of `S` is `S`
  - The greatest closure of `S` is `S`
- if `S` is `T?`
  - The least closure of `S` with respect to `L` is `U?` where `U` is the
    least closure of `T` with respect to `L`
  - The greatest closure of `S` with respect to `L` is `U?` where `U` is
    the greatest closure of `T` with respect to `L`
- if `S` is `Future<T>`
  - The least closure of `S` with respect to `L` is `Future<U>` where `U` is the
    least closure of `T` with respect to `L`
  - The greatest closure of `S` with respect to `L` is `Future<U>` where `U` is
    the greatest closure of `T` with respect to `L`
- if `S` is `FutureOr<T>`
  - The least closure of `S` with respect to `L` is `FutureOr<U>` where `U` is the
    least closure of `T` with respect to `L`
  - The greatest closure of `S` with respect to `L` is `FutureOr<U>` where `U` is
    the greatest closure of `T` with respect to `L`
- if `S` is an interface type `C<T0, ..., Tk>`
  - The least closure of `S` with respect to `L` is `C<U0, ..., Uk>` where `Ui`
    is the least closure of `Ti` with respect to `L`
  - The greatest closure of `S` with respect to `L` is `C<U0, ..., Uk>` where
    `Ui` is the greatest closure of `Ti` with respect to `L`
- if `S` is `T Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn,
  [Tn+1 xn+1, ..., Tm xm])` and no type variable in `L` occurs in any of the `Bi`:
  - The least closure of `S` with respect to `L` is `U Function<X0 extends B0,
  ..., Xk extends Bk>(U0 x0, ..., Un1 xn, [Un+1 xn+1, ..., Um xm])` where:
    - `U` is the least closure of `T` with respect to `L`
    - `Ui` is the greatest closure of `Ti` with respect to `L`
    - with the usual capture avoiding requirement that the `Xi` do not appear in
  `L`.
  - The greatest closure of `S` with respect to `L` is `U Function<X0 extends B0,
  ..., Xk extends Bk>(U0 x0, ..., Un1 xn, [Un+1 xn+1, ..., Um xm])` where:
    - `U` is the greatest closure of `T` with respect to `L`
    - `Ui` is the least closure of `Ti` with respect to `L`
    - with the usual capture avoiding requirement that the `Xi` do not appear in
  `L`.
- if `S` is `T Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn,
  {Tn+1 xn+1, ..., Tm xm})` and no type variable in `L` occurs in any of the `Bi`:
  - The least closure of `S` with respect to `L` is `U Function<X0 extends B0,
  ..., Xk extends Bk>(U0 x0, ..., Un1 xn, {Un+1 xn+1, ..., Um xm})` where:
    - `U` is the least closure of `T` with respect to `L`
    - `Ui` is the greatest closure of `Ti` with respect to `L`
    - with the usual capture avoiding requirement that the `Xi` do not appear in
  `L`.
  - The greatest closure of `S` with respect to `L` is `U Function<X0 extends B0,
  ..., Xk extends Bk>(U0 x0, ..., Un1 xn, {Un+1 xn+1, ..., Um xm})` where:
    - `U` is the greatest closure of `T` with respect to `L`
    - `Ui` is the least closure of `Ti` with respect to `L`
    - with the usual capture avoiding requirement that the `Xi` do not appear in
  `L`.
- if `S` is `T Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn,
    [Tn+1 xn+1, ..., Tm xm])` or `T Function<X0 extends B0, ..., Xk extends Bk>(T0 x0, ..., Tn xn,
{Tn+1 xn+1, ..., Tm xm})`and `L` contains any free type variables
  from any of the `Bi`:
  - The least closure of `S` with respect to `L` is `Never`
  - The greatest closure of `S` with respect to `L` is `Function`
- if `S` is `(T0 x0, ..., Tn xn,  {Tn+1 xn+1, ..., Tm xm})`:
  - The least closure of `S` with respect to `L` is `(U0 x0, ..., Un1 xn, {Un+1
    xn+1, ..., Um xm})` where:
    - `Ui` is the least closure of `Ti` with respect to `L`
  - The greatest closure of `S` with respect to `L` is `(U0 x0, ..., Un1 xn,
    {Un+1 xn+1, ..., Um xm})` where:
    - `Ui` is the greatest closure of `Ti` with respect to `L`


### Type schema elimination (least and greatest closure of a type schema)

We define the greatest and least closure of a type schema `P` with respect to
`_` in the same way as we define the greatest and least closure with respect to
a type variable `X` above, where `_` is treated as a type variable in the set
`L`.

Note that the least closure of a type schema is always a subtype of any type
which matches the schema, and the greatest closure of a type schema is always a
supertype of any type which matches the schema.


## Upper bound

We write `UP(T0, T1)` for the upper bound of `T0` and `T1`and `DOWN(T0, T1)` for
the lower bound of `T0` and `T1`.  This extends to type schema as follows:
  - We add the axiom that `UP(T, _) == T` and the symmetric version.
  - We replace all uses of `T1 <: T2` in the `UP` algorithm by `S1 <: S2` where
  `Si` is the least closure of `Ti` with respect to `_`.
  - We add the axiom that `DOWN(T, _) == T` and the symmetric version.
  - We replace all uses of `T1 <: T2` in the `DOWN` algorithm by `S1 <: S2` where
  `Si` is the greatest closure of `Ti` with respect to `_`.

The following example illustrates the effect of taking the least/greatest
closure in the subtyping algorithm.

```
class C<X> {
  C(void Function(X) x);
}
T check<T>(C<List<T>> f) {
  return null as T;
}
void test() {
  var x = check(C((List<int> x) {})); // Should infer `int` for `T`
  String s = x; // Should be an error, `T` should be int.
}
```

## Type constraints

Type constraints take the form `Pb <: X <: Pt` for type schemas `Pb` and `Pt`
and type variables `X`.  Constraints of that form indicate a requirement that
any choice that inference makes for `X` must satisfy both `Tb <: X` and `X <:
Tt` for some type `Tb` which satisfies schema `Pb`, and some type `Tt` which
satisfies schema `Pt`.  Constraints in which `X` appears free in either `Pb` or
`Pt` are ill-formed.


### Closure of type constraints

The closure of a type constraint `Pb <: X <: Pt` with respect to a set of type
variables `L` is the subtype constraint `Qb <: X :< Qt` where `Qb` is the
greatest closure of `Pb` with respect to `L`, and `Qt` is the least closure of
`Pt` with respect to `L`.

Note that the closure of a type constraint implies the original constraint: that
is, any solution to the original constraint that is closed with respect to `L`,
is a solution to the new constraint.

The motivation for these operations is that constraint generation may produce a
constraint on a type variable from an outer scope (say `S`) that refers to a
type variable from an inner scope (say `T`).  For example, ` <T>(T) -> List<T> <:
<T>(T) -> S ` constrains `List<T>` to be a subtype of `S`.  But this
constraint is ill-formed outside of the scope of `T`, and hence if inference
requires this constraint to be generated and moved out of the scope of `T`, we
must approximate the constraint to the nearest constraint which does not mention
`T`, but which still implies the original constraint.  Choosing the greatest
closure of `List<T>` (i.e. `List<Object?>`) as the new supertype constraint on
`S` results in the constraint `List<Object?> <: S`, which implies the original
constraint.

Example:
```dart
class C<T> {
  C(T Function<X>(X x));
}

List<Y> foo<Y>(Y y) => [y];

void main() {
  var x = C(foo); // Should infer C<List<Object?>>
}
```

### Constraint solving

Inference works by collecting lists of type constraints for type variables of
interest.  We write a list of constraints using the meta-variable `C`, and use
the meta-variable `c` for a single constraint.  Inference relies on various
operations on constraint sets.

#### Merge of a constraint set

The merge of constraint set `C` for a type variable `X` is a type constraint `Mb
<: X <: Mt` defined as follows:
  - let `Mt` be the lower bound of the `Mti` such that `Mbi <: X <: Mti` is in
      `C` (and `_` if there are no constraints for `X` in `C`)
  - let `Mb` be the upper bound of the `Mbi` such that `Mbi <: X <: Mti` is in
      `C` (and `_` if there are no constraints for `X` in `C`)

Note that the merge of a constraint set `C` summarizes all of the constraints in
the set in the sense that any solution for the merge is a solution for each
constraint individually.

#### Constraint solution for a type variable

The constraint solution for a type variable `X` with respect to a constraint set
`C` is the type schema defined as follows:
  - let `Mb <: X <: Mt` be the merge of `C` with respect to `X`.
  - If `Mb` is known (that is, it does not contain `_`) then the solution is
    `Mb`
  - Otherwise, if `Mt` is known (that is, it does not contain `_`) then the
    solution is `Mt`
  - Otherwise, if `Mb` is not `_` then the solution is `Mb`
  - Otherwise the solution is `Mt`

Note that the constraint solution is a type schema, and hence may contain
occurences of the unknown type.

#### Constraint solution for a set of type variables

The constraint solution for a set of type variables `{X0, ..., Xn}` with respect
to a constraint set `C` and partial solution `{T0, ..., Tn}`, is defined to be
the set of type schemas `{U0, ..., Un}` such that:
  - If `Ti` is known (that is, does not contain `_`), then `Ui = Ti`.  _(Note
    that the upcoming "variance" feature will relax this rule so that it only
    applies to type variables without an explicitly declared variance.)_
  - Otherwise, let `Vi` be the constraint solution for the type variable `Xi`
    with respect to the constraint set `C`.
  - If `Vi` is not known (that is, it contains `_`), then `Ui = Vi`.
  - Otherwise, if `Xi` does not have an explicit bound, then `Ui = Vi`.
  - Otherwise, let `Bi` be the bound of `Xi`.  Then, let `Bi'` be the type
    schema formed by substituting type schemas `{U0, ..., Ui-1, Ti, ..., Tn}` in
    place of the type variables `{X0, ..., Xn}` in `Bi`.  _(That is, we
    substitute `Uj` for `Xj` when `j < i` and `Tj` for `Xj` when `j >= i`)._
    Then `Ui` is the constraint solution for the type variable `Xi` with respect
    to the constraint set `C + (X <: Bi')`.

_This definition can perhaps be better understood in terms of the practical
consequences it has on type inference:_
  - _Once type inference has determined a known type for a type variable (that
    is, a type that does not contain `_`), that choice is frozen and is not
    affected by later type inference steps.  (Type inference accomplishes this
    by passing in any frozen choices as part of the partial solution)._
  - _The bound of a type variable is only included as a constraint when the
    choice of type for that type variable is about to be frozen._
  - _During each round of type inference, type variables are inferred left to
    right.  If the bound of one type variable refers to one or more type
    variables, then at the time the bound is included as a constraint, the type
    variables it refers to are assumed to take on the type schemas most recently
    assigned to them by type inference._

#### Grounded constraint solution for a type variable

The grounded constraint solution for a type variable `X` with respect to a
constraint set `C` is define as follows:
  - let `Mb <: X <: Mt` be the merge of `C` with respect to `X`.
  - If `Mb` is known (that is, it does not contain `_`) then the solution is
    `Mb`
  - Otherwise, if `Mt` is known (that is, it does not contain `_`) then the
    solution is `Mt`
  - Otherwise, if `Mb` is not `_` then the solution is the least closure of
    `Mb` with respect to `_`
  - Otherwise the solution is the greatest closure of `Mt` with respect to `_`.

Note that the grounded constraint solution is a type, and hence may not contain
occurences of the unknown type.

#### Grounded constraint solution for a set of type variables

The grounded constraint solution for a set of type variables `{X0, ..., Xn}`
with respect to a constraint set `C`, with partial solution `{T0, ..., Tn}`, is
defined to be the set of types `{U0, ..., Un}` such that:
  - If `Ti` is known (that is, does not contain `_`), then `Ui = Ti`.  _(Note
    that the upcoming "variance" feature will relax this rule so that it only
    applies to type variables without an explicitly declared variance.)_
  - Otherwise, if `Xi` does not have an explicit bound, then `Ui` is the
    grounded constraint solution for the type variable `Xi` with respect to the
    constraint set `C`.
  - Otherwise, let `Bi` be the bound of `Xi`.  Then, let `Bi'` be the type
    schema formed by substituting type schemas `{U0, ..., Ui-1, Ti, ..., Tn}` in
    place of the type variables `{X0, ..., Xn}` in `Bi`.  _(That is, we
    substitute `Uj` for `Xj` when `j < i` and `Tj` for `Xj` when `j >= i`)._
    Then `Ui` is the grounded constraint solution for the type variable `Xi`
    with respect to the constraint set `C + (X <: Bi')`.

_This definition parallels the definition of the (non-grounded) constraint
solution for a set of type variables._

#### Constrained type variables

A constraint set `C` constrains a type variable `X` if there exists a `c` in `C`
of the form `Pb <: X <: Pt` where either `Pb` or `Pt` is not `_`.

A constraint set `C` partially constrains a type variable `X` if the constraint
solution for `X` with respect to `C` is a type schema (that is, it contains
`_`).

A constraint set `C` fully constrains a type variable `X` if the constraint
solution for `X` with respect to `C` is a proper type (that is, it does not
contain `_`).

## Subtype constraint generation

Subtype constraint generation is an operation on two type schemas `P` and `Q`
and a list of type variables `L`, producing a list of subtype
constraints `C`.

We write this operation as a relation as follows:

```
P <# Q [L] -> C
```

where `P` and `Q` are type schemas, `L` is a list of type variables `X0, ...,
Xn`, and `C` is a list of subtype and supertype constraints on the `Xi`.

This relation can be read as "`P` is a subtype match for `Q` with respect to the
list of type variables `L` under constraints `C`".  Not all schemas `P` and `Q`
are in the relation: the relation may fail to hold, which is distinct from the
relation holding but producing no constraints.

By invariant, at any point in constraint generation, only one of `P` and `Q` may
be a type schema (that is, contain `_`), only one of `P` and `Q` may contain any
of the `Xi`, and neither may contain both.  That is, constraint generation is a
relation on type-schema/type pairs and type/type-schema pairs, only the type
element of which may refer to the `Xi`.  The presentation below does not
explicitly track which side of the relation currently contains a schema and
which currently contains the variables being solved for, but it does at one
point rely on being able to recover this information.  This information can be
tracked explicitly in the relation by (for example) adding a boolean to the
relation which is negated at contravariant points.


### Notes:

- For convenience, ordering matters in this presentation: where any two clauses
  overlap syntactically, the first match is preferred.
- This presentation is assuming appropriate well-formedness conditions on the
  input types (e.g. non-cyclic class hierarchies)

### Syntactic notes:

- `C0 + C1` is the concatenation of constraint lists `C0` and `C1`.

### Rules

For two type schemas `P` and `Q`, a set of type variables `L`, and a set of
constraints `C`, we define `P <# Q [L] -> C` via the following algorithm.

Note that the order matters: we consider earlier clauses first.

Note that the rules are written assuming that if the conditions of a particular
case (including the sub-clauses) fail to hold, then they "fall through" to try
subsequent cluases except in the case that a subclause is prefixed with "Only
if", in which case a failure of the prefixed clause implies that no subsequent
clauses need be tried.

- If `P` is `_` then the match holds with no constraints.
- If `Q` is `_` then the match holds with no constraints.
- If `P` is a type variable `X` in `L`, then the match holds:
  - Under constraint `_ <: X <: Q`.
- If `Q` is a type variable `X` in `L`, then the match holds:
  - Under constraint `P <: X <: _`.
- If `P` and `Q` are identical types, then the subtype match holds under no
  constraints.
- If `P` is a legacy type `P0*` then the match holds under constraint set `C`:
  - Only if `P0` is a subtype match for `Q` under constraint set `C`.
- If `Q` is a legacy type `Q0*` then the match holds under constraint set `C`:
  - If `P` is `dynamic` or `void` and `P` is a subtype match for `Q0` under
    constraint set `C`.
  - Or if `P` is a subtype match for `Q0?` under constraint set `C`.
- If `Q` is `FutureOr<Q0>` the match holds under constraint set `C`:
  - If `P` is `FutureOr<P0>` and `P0` is a subtype match for `Q0` under
    constraint set `C`.
  - Or if `P` is a subtype match for `Future<Q0>` under **non-empty** constraint set
    `C`
  - Or if `P` is a subtype match for `Q0` under constraint set `C`
  - Or if `P` is a subtype match for `Future<Q0>` under **empty** constraint set
    `C`
- If `Q` is `Q0?` the match holds under constraint set `C`:
  - If `P` is `P0?` and `P0` is a subtype match for `Q0` under
    constraint set `C`.
  - Or if `P` is `dynamic` or `void` and `Object` is a subtype match for `Q0`
    under constraint set `C`.
  - Or if `P` is a subtype match for `Q0` under **non-empty** constraint set
    `C`.
  - Or if `P` is a subtype match for `Null` under constraint set `C`.
  - Or if `P` is a subtype match for `Q0` under **empty** constraint set
    `C`.
- If `P` is `FutureOr<P0>` the match holds under constraint set `C1 + C2`:
  - If `Future<P0>` is a subtype match for `Q` under constraint set `C1`
  - And if `P0` is a subtype match for `Q` under constraint set `C2`
- If `P` is `P0?` the match holds under constraint set `C1 + C2`:
  - If `P0` is a subtype match for `Q` under constraint set `C1`
  - And if `Null` is a subtype match for `Q` under constraint set `C2`
- If `Q` is `dynamic`, `Object?`, or `void` then the match holds under no
  constraints.
- If `P` is `Never` then the match holds under no constraints.
- If `Q` is `Object`, then the match holds under no constraints:
  - Only if `P` is non-nullable.
- If `P` is `Null`, then the match holds under no constraints:
  - Only if `Q` is nullable.

- If `P` is a type variable `X` with bound `B` (or a promoted type variable `X &
  B`), the match holds with constraint set `C`:
  - If `B` is a subtype match for `Q` with constraint set `C`
    - Note that we have already eliminated the case that `X` is a variable in
      `L`.

- If `P` is `C<M0, ..., Mk>` and `Q` is `C<N0, ..., Nk>`, and the corresponding
  type parameters declared by the class `C` are `T0, ..., Tk`, then the match
  holds under constraints `C0 + ... + Ck`, if for each `i`:
  - If `Ti` is a **covariant** type variable, and `Mi` is a subtype match for
    `Ni` with respect to `L` under constraints `Ci`,
  - Or `Ti` is a **contravariant** type variable, `Ni` is a subtype match for
    `Mi` with respect to `L` under constraints `Ci`,
  - Or `Ti` is an **invariant** type variable, and:
    - `Mi` is a subtype match for `Ni` with respect to `L` under constraints
      `Ci0`,
    - And `Ni` is a subtype match for `Mi` with respect to `L` under constraints
      `Ci1`,
    - And `Ci` is `Ci0 + Ci1`.

- If `P` is `C0<M0, ..., Mk>` and `Q` is `C1<N0, ..., Nj>` then the match holds
with respect to `L` under constraints `C`:
  - If `C1<B0, ..., Bj>` is a superinterface of `C0<M0, ..., Mk>` and `C1<B0,
..., Bj>` is a subtype match for `C1<N0, ..., Nj>` with respect to `L` under
constraints `C`.
  - Or `R<B0, ..., Bj>` is one of the interfaces implemented by `P<M0, ..., Mk>`
(considered in lexical order) and `R<B0, ..., Bj>` is a subtype match for `Q<N0,
..., Nj>` with respect to `L` under constraints `C`.
  - Or `R<B0, ..., Bj>` is a mixin into `P<M0, ..., Mk>` (considered in lexical
order) and `R<B0, ..., Bj>` is a subtype match for `Q<N0, ..., Nj>` with respect
to `L` under constraints `C`.

- A type `P` is a subtype match for `Function` with respect to `L` under no constraints:
  - If `P` is a function type.

- A function type `(M0,..., Mn, [M{n+1}, ..., Mm]) -> R0` is a subtype match for
  a function type `(N0,..., Nk, [N{k+1}, ..., Nr]) -> R1` with respect to `L`
  under constraints `C0 + ... + Cr + C`
  - If `R0` is a subtype match for a type `R1` with respect to `L` under
  constraints `C`:
  - If `n <= k` and `r <= m`.
  - And for `i` in `0...r`, `Ni` is a subtype match for `Mi` with respect to `L`
  under constraints `Ci`.
- Function types with named parameters are treated analogously to the positional
  parameter case above.

- A generic function type `<T0 extends B00, ..., Tn extends B0n>F0` is a subtype
match for a generic function type `<S0 extends B10, ..., Sn extends B1n>F1` with
respect to `L` under constraint set `C2`
  - If `B0i` is a subtype match for `B1i` with constraint set `Ci0`
  - And `B1i` is a subtype match for `B0i` with constraint set `Ci1`
  - And `Ci2` is `Ci0 + Ci1`
  - And `Z0...Zn` are fresh variables with bounds `B20, ..., B2n`
    - Where `B2i` is `B0i[Z0/T0, ..., Zn/Tn]` if `P` is a type schema
    - Or `B2i` is `B1i[Z0/S0, ..., Zn/Sn]` if `Q` is a type schema
      - In other words, we choose the bounds for the fresh variables from
        whichever of the two generic function types is a type schema and does
        not contain any variables from `L`.
  - And `F0[Z0/T0, ..., Zn/Tn]` is a subtype match for `F1[Z0/S0, ..., Zn/Sn]`
with respect to `L` under constraints `C0`
  - And `C1` is  `C02 + ... + Cn2 + C0`
  - And `C2` is `C1` with each constraint replaced with its closure with respect
    to `[Z0, ..., Zn]`.

- A type `P` is a subtype match for `Record` with respect to `L` under no constraints:
  - If `P` is a record type or `Record`.

- A record type `(M0,..., Mk, {M{k+1} d{k+1}, ..., Mm dm])` is a subtype match
  for a record type `(N0,..., Nk, {N{k+1} d{k+1}, ..., Nm dm])` with respect
  to `L` under constraints `C0 + ... + Cm`
  - If for `i` in `0...m`, `Mi` is a subtype match for `Ni` with respect to `L`
  under constraints `Ci`.


<!--


# MATERIAL BELOW HERE HAS NOT BEEN UPDATED #


## Expression inference

Expression inference uses information about what constraints are imposed on the
expression by the context in which the expression occurs.  An expression may
occur in a context which provides no typing expectation, in which case there is
no contextual information.  Otherwise, the contextual information takes the form
of a type schema which describes the structure of the type to which the
expression is required to conform by its context of occurrence.

The primary function of expression inference is to determine the parameter and
return types of closure literals which are not explicitly annotated, and to fill
in elided type variables in constructor calls, generic method calls, and generic
literals.

### Expectation contexts

A typing expectation context (written using the meta-variables `J` or `K`) is
a type schema `P`, or an empty context `_`.

### Constraint set resolution

The full resolution of a constraint set `C` for a list of type parameters `<T0
extends B0, ..., Tn extends Bn>` given an initial partial
solution `[T0 -> P0, ..., Tn -> Pn]` is defined as follows.  The resolution
process computes a sequence of partial solutions before arriving at the final
resolution of the arguments.

Solution 0 is `[T0 -> P00, ..., Tn -> P0n]` where `P0i` is `Pi` if `Ti` is fixed
in the initial partial solution (i.e. `Pi` is a type and not a type schema) and
otherwise `Pi` is `?`.

Solution 1 is `[T0 -> P10, ..., Tn -> P1n]` where:
  - If `Ti` is fixed in Solution 0 then `P1i` is `P0i`'
  - Otherwise, let `Ai` be `Bi[P10/T0, ..., ?/Ti, ...,  ?/Tn]`
  - If `C + Ti <: Ai` over constrains `Ti`, then it is an
    inference failure error
  - If `C + Ti <: Ai` does not constrain `Ti` then `P1i` is `?`
  - Otherwise `Ti` is fixed with `P1i`, where `P1i` is the **grounded**
    constraint solution for `Ti` with respect to `C + Ti <: Ai`.

Solution 2 is `[T0 -> M0, ..., Tn -> Mn]` where:
  - let `A0, ..., An` be derived as
    - let `Ai` be `P1i` if `Ti` is fixed in Solution 1
    - let `Ai` be `Bi` otherwise
  - If `<T0 extends A0, ..., Tn extends An>` has no default bounds then it is
    an inference failure error.
  - Otherwise, let `M0, ..., Mn`be the default bounds for `<T0 extends A0,
      ..., Tn extends An>`

If `[M0, ..., Mn]` do not satisfy the bounds `<T0 extends B0, ..., Tn extends
Bn>` then it is an inference failure error.

Otherwise, the full solution is `[T0 -> M0, ..., Tn -> Mn]`.

### Downwards generic instantiation resolution

Downwards resolution is the process by which the return type of a generic method
(or constructor, etc) is matched against a type expectation context from an
invocation of the method to find a (possibly partial) solution for the missing
type arguments

`[T0 -> P0, ..., Tn -> Pn]` is a partial solution for a set of type variables
`<T0 extends B0, ..., Tn extends Bn>` under constraint set `Cp` given a type
expectation of `R` with respect to a return type `Q` (in which the `Ti` may be
free) where the `Pi` are type schemas (potentially just `?` if unresolved)/

If `R <: Q [T0, ..., Tn] -> C` does not hold, then each `Pi` is `?` and `Cp` is
    empty

Otherwise:
  - `R <: Q [T0, ..., Tn] -> C` and `Cp` is `C`
  - If `C` does not constrain `Ti` then `Pi` is `?`
  - If `C` partially constrains `Ti`
    - If `C` is over constrained, then it is an inference failure error
    - Otherwise `Pi` is the constraint solution for `Ti` with respect to `C`
  - If `C` fully constrains `Ti`, then
    - Let `Ai` be `Bi[R0/T0, ..., ?/Ti, ..., ?/Tn]`
    - If `C + Ti <: Ai` is over constrained, it is an inference failure error.
    - Otherwise, `Ti` is fixed to be `Pi`, where `Pi` is the constraint solution
      for `Ti` with respect to `C + Ti <: Ai`.

### Upwards generic instantiation resolution

Upwards resolution is the process by which the parameter types of a generic
method (or constructor, etc) are matched against the actual argument types from
an invocation of a method to find a solution for the missing type arguments that
have not been fixed by downwards resolution.

`[T0 -> M0, ..., Tn -> Mn]` is the upwards solution for an invocation of a
generic method of type `<T0 extends B0, ..., Tn extends Bn>(P0, ..., Pk) -> Q`
given actual argument types `R0, ..., Rk`, a partial solution `[T0 -> P0, ...,
Tn -> Pn]` and a partial constraint set `Cp`:
  - If `Ri <: Pi [T0, ..., Tn] -> Ci`
  - And the full constraint resolution of `Cp + C0 + ... + Cn` for `<T0 extends
B0, ..., Tn extends Bn>` given the initial partial solution `[T0 -> P0, ..., Tn
-> Pn]` is `[T0 -> M0, ..., Tn -> Mn]`

### Discussion

The incorporation of the type bounds information is asymmetric and procedural:
it iterates through the bounds in order (`Bi[R0/T0, ..., ?/Ti, ..., ?/Tn]`).  Is
there a better formulation of this that is symmetric but still allows some
propagation?

### Inference rules

- The expression `e as T` is inferred as `m as T` of type `T` in context `K`:
  - If `e` is inferred as `m` in an empty context
- The expression `x = e` is inferred as `x = m` of type `T` in context `K`:
  - If `e` is inferred as `m` of type `T` in context `M` where `x` has type `M`.
- The expression `x ??= e` is inferred as `x ??= m` of type `UP(T, M)` in
  context `K`:
  - If `e` is inferred as `m` of type `T` in context `M` where `x` has type `M`.
- The expression `await e` is inferred as `await m` of type `T` in context `K`:
  - If `e` is inferred as `m` of type `T` in context `J` where:
    - `J` is `FutureOr<K>` if `K` is not `_`, and is `_` otherwise
- The expression `e0 ?? e1` is inferred as `m0 ?? m1` of type `T` in
  context `K`:
  - If `e0` is inferred as `m0` of type `T0` in context `K`
  - And `e1` is inferred as `m1` of type `T1` in context `J`
  - Where `J` is `T0` if `K` is `_` and otherwise `K`
  - Where `T` is the greatest closure of `K` with respect to `?` if `K` is not
    `_` and otherwise `UP(T0, T1)`
- The expression `e0..e1` is inferred as `m0..m1` of type `T` in context `K`
  - If `e0` is inferred as `m0` of type `T` in context `K`
  - And `e1` is inferred as `m1` of type `P` in context `_`
- The expression `e0 ? e1 : e2` is inferred as `m0 ? m1 : m2` of type `T` in
  context `K`
  - If `e0` is inferred as `m0` of any type in context `bool`
  - And `e1` is inferred as `m1` of type `T0` in context `K`
  - And `e2` is inferred as `m2` of type `T1` in context `K`
  - Where `T` is the greatest closure of `K` with respect to `?` if `K` is not
    `_` and otherwise `UP(T0, T1)`
- TODO(leafp): Generalize the following closure cases to the full function
  signature.
  - In general, if the function signature is compatible with the context type,
    take any available information from the context.  If the function signature
    is not compatible, this should always be a type error anyway, so
    implementations should be free to choose the best error recovery path.
  - The monomorphic case can be treated as a degenerate case of the polymorphic
    rule
- The expression `<T>(P x) => e` is inferred as `<T>(P x) => m` of type `<T>(P)
  -> M` in context `_`
  - If `e` is inferred as `m` of type `M` in context `_`
- The expression `<T>(P x) => e` is inferred as `<T>(P x) => m` of type `<T>(P)
  -> M` in context `<S>(Q) -> N`
  - If `e` is inferred as `m` of type `M` in context `N[T/S]`
  - Note: `x` is resolved as having type `P`  for inference in `e`
- The expression `<T>(x) => e` is inferred as `<T>(dynamic x) => m` of type
  `<T>(dynamic) -> M` in context `_`
  - If `e` is inferred as `m` of type `M` in context `_`
- The expression `<T>(x) => e` is inferred as `<T>(Q[T/S] x) => m` of type
  `<T>(Q[T/S]) -> M` in context `<S>(Q) -> N`
  - If `e` is inferred as `m` of type `M` in context `N[T/S]`
  - Note: `x` is resolved as having type `Q[T/S]` for inference in `e`
- Block bodied lamdas are treated essentially the same as expression bodied
  lambdas above, except that:
  - The final inferred return type is `UP(T0, ..., Tn)`, where the `Ti` are the
    inferred types of the return expressions (`void` if no returns).
  - The returned expression from each `return` in the body of the lamda uses the
    same type expectation context as described above.
  - TODO(leafp): flesh this out.
- For async and generator functions, the downwards context type is computed as
  above, except that the propagated downwards type is taken from the type
  argument to the `Future` or `Iterable` or `Stream` constructor as appropriate.
  If the return type is not the appropriate constructor type for the function,
  then the downwards context is empty.  Note that subtypes of these types are
  not considered (this is a strong mode error).
- The expression `e(e0, .., ek)` is inferred as `m<M0, ..., Mn>(m0, ..., mk)` of
  type `N` in context `_`:
  - If `e` is inferred as `m` of type `<T0 extends B0, ..., Tn extends Bn>(P0,
    ..., Pk) -> Q` in context `_`
  - And the initial downwards solution is `[T0 -> Q0, ..., Tn -> Qn]` with
    partial constraint set `Cp` where:
    - If `K` is `_`, then the `Qi` are `?` and `Cp` is empty
    - If `K` is `Q <> _` then `[T0 -> Q0, ..., Tn -> Qn]` is the partial
solution for `<T0 extends B0, ..., Tn extends Bn>` under constraint set `Cp` in
downwards context `P` with respect to return type `Q`.
  - And `ei` is inferred as `mi` of type `Ri` in context `Pi[?/T0, ..., ?/Tn]`
  - And `<T0 extends B0, ..., Tn extends Bn>(P0, ..., Pk) -> Q` resolves via
upwards resolution to a full solution `[T0 -> M0, ..., Tn -> Mn]`
    - Given partial solution `[T0 -> Q0, ..., Tn -> Qn]`
    - And partial constraint set `Cp`
    - And actual argument types `R0, ..., Rk`
  - And `N` is `Q[M0/T0, ..., Mn/Tn]`
- A constructor invocation is inferred exactly as if it were a static generic
  method invocation of the appropriate type as in the previous case.
- A list or map literal is inferred analagously to a constructor invocation or
  generic method call (but with a variadic number of arguments)
- A (possibly generic) method invocation is inferred using the same process as
  for function invocation.
- A named expression is inferred to have the same type as the sub-expression
- A parenthesized expression is inferred to have the same type as the
  sub-expression
- A tear-off of a generic method, static class method, or top level function `f`
  is inferred as `f<M0, ..., Mn>` of type `(R0, ..., Rm) -> R` in context `K`:
  - If `f` has type `A``T0 extends extends B0, ..., Tn extends Bn>(P0, ..., Pk) ->
    Q`
  - And `K` is `N` where `N` is a monomorphic function type
  - And `(P0, ..., Pk) -> Q <: N [T0, ..., Tn] -> C`
  - And the full resolution of `C` for `<T0 extends B0, ..., Tn extends Bn>`
given an initial partial solution `[T0 -> ?, ..., Tn -> ?]` and empty constraint
set is `[T0 -> M0, ..., Tn -> Mn]`



TODO(leafp): Specify the various typing contexts associated with specific binary
operators.


## Method and function inference.

TODO(leafp)


Constructor declaration (field initializers)
Default parameters

## Statement inference.

TODO(leafp)

Return statements pull the return type from the enclosing function for downwards
inference, and compute the upper bound of all returned values for upwards
inference.  Appropriate adjustments for asynchronous and generator functions.

Do statements
For each statement

-->
