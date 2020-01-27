# Top-level and local type inference

Owner: leafp@google.com

Status: Draft

## CHANGELOG

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
    signature of the method you are overriding.
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
      - Record the type of `x` to be the inferred type of `e`, and mark `x` as
        *available*.
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

A method which is subject to override inference is missing one or more component
types of its signature, and it overrides one or more declarations. Each missing
type is filled in with the corresponding type from the overridden or implemented
method.  If there are multiple overridden/implemented methods, and any two of
them have non-equal types (declared or inferred) for a parameter position which
is being inferred for the overriding method, it is an error.  If there is no
corresponding parameter position in the overridden method to infer from and the
signatures are compatible, it is treated as dynamic (e.g. overriding a one
parameter method with a method that takes a second optional parameter).  Note:
if there is no corresponding parameter position in the overridden method to
infer from and the signatures are incompatible (e.g. overriding a one parameter
method with a method that takes a second non-optional parameter), the inference
result is not defined and tools are free to either emit an error, or to defer
the error to override checking.


##### Instance field, getter, and setter override inference

The inferred type of a getter, setter, or field is computed as follows.  Note
that we say that a setter overrides a getter if there is a getter of the same
name in some superclass or interface (explicitly declared or induced by an
instance variable declaration), and similarly for setters overriding getters,
fields, etc.

The return type of a getter, parameter type of a setter or type of a field which
overrides/implements only a getter is inferred to be the result type of the
overridden getter.

The return type of a getter, parameter type of a setter or type of a field which
overrides/implements only a setter is inferred to be the parameter type of the
overridden setter.

The return type of a getter which overrides/implements both a setter and a
getter is inferred to be the result type of the overridden getter.

The parameter type of a setter which overrides/implements both a setter and a
getter is inferred to be the parameter type of the overridden setter.

The type of a final field which overrides/implements both a setter and a getter
is inferred to be the result type of the overridden getter.

The type of a non-final field which overrides/implements both a setter and a
getter is inferred to be the parameter type of the overridden setter if this
type is the same as the return type of the overridden getter (if the types are
not the same then inference fails with an error).

Note that overriding a field is addressed via the implicit induced getter/setter
pair (or just getter in the case of a final field).

Note that `late` fields are inferred exactly as non-`late` fields.  However,
unlike normal fields, the initializer for a `late` field may reference `this`.

## Function literal return type inference.

Function literals which are inferred in an empty typing context (see below) are
inferred using the declared type for all of their parameters.  If a parameter
has no declared type, it is treated as if it was declared with type `dynamic`.
Inference for each returned expression in the body of the function literal is
done in an empty typing context (see below).

Function literals which are inferred in an non-empty typing context where the
context type is a function type are inferred as follows.  Each parameter is
assumed to have its declared type if present, or the type taken from the
corresponding parameter (if any) from the typing context if not present.  The
return type of the context function type is used at several points during
inference.  We refer to this type as the **imposed return type
schema**. Inference for each returned or yielded expression in the body of the
function literal is done using a context type derived from the imposed return
type schema as follows:
  - If the function expression is neither `async` nor a generator, then the
    context type is the imposed return type.
  - If the function expression is declared `async*` and the imposed return type
    is of the form `Stream<S>` for some `S`, then the context type is `S`.
  - If the function expression is declared `sync*` and the imposed return type
    is of the form `Iterable<S>` for some `S`, then the context type is `S`.
  - Otherwise the context type is `FutureOr<flatten(T)>` where `T` is the
    imposed return type.

In order to infer the return type of a function literal, we first infer the
**actual returned type** of the function literal.

The actual returned type of a function literal with an expression body is the
inferred type of the expression body, using the local type inference algorithm
described below with a typing context as computed above.

The actual returned type of a function literal with a block body is computed as
follows.  Let `T` be `Never` if every control path through the block exits the
block without reaching the end of the block, as computed by the **definite
completion** analysis specified elsewhere.  Let `T` be `Null` if any control
path reaches the end of the block without exiting the block, as computed by the
**definite completion** analysis specified elsewhere.  Let `K` be the typing
context for the function body as computed above from the imposed return type
schema.
  - For each `return e;` statement in the block, let `S` be the inferred type of
    `e`, using the local type inference algorithm described below with typing
    context `K`, and update `T` to be `UP(flatten(S), T)` if the enclosing
    function is `async`, or `UP(S, T)` otherwise.
  - For each `return;` statement in the block, update `T` to be `UP(Null, T)`.
  - For each `yield e;` statement in the block, let `S` be the inferred type of
    `e`, using the local type inference algorithm described below with typing
    context `K`, and update `T` to be `UP(S, T)`.
  - If the enclosing function is marked `sync*`, then for each `yield* e;`
    statement in the block, let `S` be the inferred type of `e`, using the
    local type inference algorithm described below with a typing context of
    `Iterable<K>`; let `E` be the type such that `Iterable<E>` is a
    super-interface of `S`; and update `T` to be `UP(E, T)`.
  - If the enclosing function is marked `async*`, then for each `yield* e;`
    statement in the block, let `S` be the inferred type of `e`, using the
    local type inference algorithm described below with a typing context of
    `Stream<K>`; let `E` be the type such that `Stream<E>` is a super-interface
    of `S`; and update `T` to be `UP(E, T)`.

The **actual returned type** of the function literal is the value of `T` after
all `return` and `yield` statements in the block body have been considered.

Let `T` be the **actual returned type** of a function literal as computed above.
Let `R` be the greatest closure of the typing context `K` as computed above.  If
`T <: R` then let `S` be `T`.  Otherwise, let `S` be `R`.  The inferred return
type of the function literal is then defined as follows:
  - If the function literal is marked `async` then the inferred return type is
    `Future<flatten(S)>`.
  - If the function literal is marked `async*` then the inferred return type is
    `Stream<S>`.
  - If the function literal is marked `sync*` then the inferred return type is
    `Iterable<S>`.
  - Otherwise, the inferred return type is `S`.

## Local return type inference.

A local function definition which has no explicit return type is subject to the
same return type inference as a function expression with no typing context.
During inference of the function body, any recursive calls to the function are
treated as having return type `dynamic`.

In Dart code which has opted into the NNBD semantics, local function body
inference is changed so that the local function name is not considered
*available* for inference while performing inference on the body.  As a result,
any recursive calls to the function for which the result type is required for
inference to complete will no longer be treated as having return type `dynamic`,
but will instead result in an inference failure.

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



### Type schemas

Local type inference uses a notion of `type schema`, which is a slight
generalization of the normal Dart type syntax.  The grammar of Dart types is
extended with an additional construct `?` which can appear anywhere that a type
is expected.  The intent is that `?` represents a component of a type which has
not yet been fixed by inference.  Type schemas cannot appear in programs or in
final inferred types: they are purely part of the specification of the local
inference process.  In this document, we sometimes refer to `?` as "the unknown
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
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])`, 
      the union of:
    - the covariant occurrences of `T` in `U`
    - the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the covariant occurrences of `T` in `U`
    - the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., m`

The contravariant occurrences of a type `T` in another type `S` are:
  - if `S` is `Future<U>`
    - the contravariant occurrences of `T` in `U`
  - if `S` is `FutureOr<U>`
    - the contravariant occurrencs of `T` in `U`
  - if `S` is an interface type `C<T0, ..., Tk>`
    - the union of the contravariant occurrences of `T` in `Ti` for `i` in `0, ..., k`
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])`, 
      the union of:
    - the contravariant occurrences of `T` in `U`
    - the covariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the contravariant occurrences of `T` in `U`
    - the covariant occurrences of `T` in `Ti` for `i` in `0, ..., m`

The invariant occurrences of a type `T` in another type `S` are:
  - if `S` is `Future<U>`
    - the invariant occurrences of `T` in `U`
  - if `S` is `FutureOr<U>`
    - the invariant occurrencs of `T` in `U`
  - if `S` is an interface type `C<T0, ..., Tk>`
    - the union of the invariant occurrences of `T` in `Ti` for `i` in `0, ..., k`
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, [Tn+1 xn+1, ..., Tm xm])`, 
      the union of:
    - the invariant occurrences of `T` in `U`
    - the invariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
    - all occurrences of `T` in `Bi` for `i` in `0, ..., k`
  - if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn, {Tn+1 xn+1, ..., Tm xm})`
      the union of:
    - the invariant occurrences of `T` in `U`
    - the invariant occurrences of `T` in `Ti` for `i` in `0, ..., m`
    - all occurrences of `T` in `Bi` for `i` in `0, ..., k`

### Type schema elimination (least and greatest closure of a type schema)

We define the least closure of a type schema `P` with respect to `?` to be `P`
with every covariant occurrence of `?` replaced with `Null`, and every invariant
or contravariant occurrence of `?` replaced with `Object`.

We define the greatest closure of a type schema `P` with respect to `?` to be
`P` with every invariant and covariant occurrence of `?` replaced with `Object`,
and every contravariant occurrence of `?` replaced with `Null`.

Note that the closure of a type schema is a proper type.

Note that the least closure of a type schema is always a subtype of any type
which matches the schema, and the greatest closure of a type schema is always a
supertype of any type which matches the schema.  **This is not true for invariant
types.**

TODO: decide what to do about invariant types.

### Type variable elimination (least and greatest closure of a type)

Given a type `S` and a set of type variables `L` consisting of the variables
`X0, ..., Xn`, we define the least and greatest closure of `S` with respect to
`L` as follows.

We define the least closure of a type `M` with respect to a set of type
variables `T0, ..., Tn` to be `M` with every covariant occurrence of `Ti`
replaced with `Null`, and every contravariant occurrence of `Ti` replaced with
`Object`.

We define the greatest closure of a type `M` with respect to a set of type
variables `T0, ..., Tn` to be `M` with every contravariant occurrence of `Ti`
replaced with `Null`, and every covariant occurrence of `Ti` replaced with
`Object`.

- If `S` is `X` where `X` is in `L`
  - The least closure of `S` with respect to `L` is `Null`
  - The greatest closure of `S` with respect to `L` is `Object`
- If `S` is a base type (or in general, if it does not contain any variable from
  `L`)
  - The least closure of `S` is `S`
  - The greatest closure of `S` is `S`
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
- if `S` is `U Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn,
  [Tn+1 xn+1, ..., Tm xm])` and `L` contains any free type variables from any of
  the `Bi`:
  - The least closure of `S` with respect to `L` is `Null`
  - The greatest closure of `S` with respect to `L` is `Object`
- if `S` is `T Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn,
  [Tn+1 xn+1, ..., Tm xm])` and `L` does not contain any free type variables
  from any of the `Bi`:
  - The least closure of `S` with respect to `L` is `U Function<X0 extends B0,
  ...., Xk extends Bk>(U0 x0, ...., Un1 xn, [Un+1 xn+1, ..., Um xm])` where:
    - `U` is the least closure of `T` with respect to `L` 
    - `Ui` is the greatest closure of `Ti` with respect to `L` 
    - with the usual capture avoiding requirement that the `Xi` do not appear in
  `L`.
  - The greatest closure of `S` with respect to `L` is `U Function<X0 extends B0,
  ...., Xk extends Bk>(U0 x0, ...., Un1 xn, [Un+1 xn+1, ..., Um xm])` where:
    - `U` is the greatest closure of `T` with respect to `L` 
    - `Ui` is the least closure of `Ti` with respect to `L` 
    - with the usual capture avoiding requirement that the `Xi` do not appear in
  `L`.
- if `S` is `T Function<X0 extends B0, ...., Xk extends Bk>(T0 x0, ...., Tn xn,
  {Tn+1 xn+1, ..., Tm xm})` and `L` does not contain any free type variables
  from any of the `Bi`:
  - The least closure of `S` with respect to `L` is `U Function<X0 extends B0,
  ...., Xk extends Bk>(U0 x0, ...., Un1 xn, {Un+1 xn+1, ..., Um xm})` where:
    - `U` is the least closure of `T` with respect to `L` 
    - `Ui` is the greatest closure of `Ti` with respect to `L` 
    - with the usual capture avoiding requirement that the `Xi` do not appear in
  `L`.
  - The greatest closure of `S` with respect to `L` is `U Function<X0 extends B0,
  ...., Xk extends Bk>(U0 x0, ...., Un1 xn, {Un+1 xn+1, ..., Um xm})` where:
    - `U` is the greatest closure of `T` with respect to `L` 
    - `Ui` is the least closure of `Ti` with respect to `L` 
    - with the usual capture avoiding requirement that the `Xi` do not appear in
  `L`.


# MATERIAL BELOW HERE HAS NOT BEEN UPDATED #

<!--

## Upper bound

We write `UP(T0, T1)` for the upper bound of `T0` and `T1`and `DOWN(T0, T1)` for
the lower bound of `T0` and `T1`.  This extends to type schema by taking `UP(T,
?) == T` and `DOWN(T, ?) == T` and symmetrically.

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

XXX this is wrong, fix

Note that the closure of a type constraint implies the original constraint: that
is, any solution to the original constraint that is closed with respect to `L`,
is a solution to the new constraint.

The motivation for these operations is that constraint generation may produce a
constraint on a type variable from an outer scope (say `S`) that refers to a
type variable from an inner scope (say `T`).  For example, ` <T>(S) -> int <:
<T>(List<T> -> int ` constrains `List<T>` to be a subtype of `S`.  But this
constraint is ill-formed outside of the scope of `T`, and hence if inference
requires this constraint to be generated and moved out of the scope of `T`, we
must approximate the constraint to the nearest constraint which does not mention
`T`, but which still implies the original constraint.  Choosing the greatest
closure of `List<T>` (i.e. `List<Object>`) as the new supertype constraint on
`S` results in the constraint `List<Object> <: S`, which implies the original
constraint.

### Constraint solving

Inference works by collecting lists of type constraints for type variables of
interest.  We write a list of constraints using the meta-variable `C`, and use
the meta-variable `c` for a single constraint.  Inference relies on various
operations on constraint sets.

#### Merge of a constraint set

The merge of constraint set `C` for a type variable `X` is a type constraint `Mb
<: X <: Mt` defined as follows:
  - let `Mt` be the lower bound of the `Mti` such that `Mbi <: X <: Mti` is in
      `C` (and `?` if there are no constraints for `X` in `C`)
  - let `Mb` be the upper bound of the `Mbi` such that `Mbi <: X <: Mti` is in
      `C` (and `?` if there are no constraints for `X` in `C`)

#### Constraint solution for a type variable

The constraint solution for a type variable `X` with respect to a constraint set
`C` is defined as follows:
  - let `Mb <: X <: Mt` be the merge of `C` with respect to `X`.
  - If `Mb` is known (that is, it does not contain `?`) then the solution is
    `Mb`
  - Otherwise, if `Mt` is known (that is, it does not contain `?`) then the
    solution is `Mt`
  - Otherwise, if `Mb` is not `?` then the solution is `Mb`
  - Otherwise the solution is `Mt`

#### Grounded constraint solution for a type variable

The grounded constraint solution for a type variable `X` with respect to a
constraint set `C` is define as follows:
  - let `Mb <: X <: Mt` be the merge of `C` with respect to `X`.
  - If `Mb` is known (that is, it does not contain `?`) then the solution is
    `Mb`
  - Otherwise, if `Mt` is known (that is, it does not contain `?`) then the
    solution is `Mt`
  - Otherwise, if `Mb` is not `?` then the solution is the least closure of
    `Mb` with respect to `?`
  - Otherwise the solution is the greatest closure of `Mt` with respect to `?`.

#### Constrained type variables

A constraint set `C` constrains a type variable `X` if there exists a `c` in `C`
of the form `Pb <: X <: Pt` where either `Pb` or `Pt` is not `?`.

A constraint set `C` partially constrains a type variable `X` if the constraint
solution for `X` with respect to `C` is a type schema (that is, it contains
`?`).

A constraint set `C` fully constrains a type variable `X` if the constraint
solution for `X` with respect to `C` is a proper type (that is, it does not
contain `?`).


## Subtype constraint generation

Subtype constraint generation is an operation on two type schemas `P` and `Q`
and a list of type variables `L`, producing a list of subtype
constraints `C`.

We write this operation as a relation as follows:

```
P <: Q [L] -> C
```

where `P` and `Q` are type schemas, `L` is a list of type variables `X0, ...,
Xn`, and `C` is a list of subtype and supertype constraints on the `Xi`.

This relation can be read as "`P` is a subtype match for `Q` with respect to the
list of type variables `L` under constraints `C`".


By invariant, at any point in constraint generation, only one of `P` and `Q` may
be a type schema (that is, contain `?`), only one of `P` and `Q` may contain any
of the `Xi`, and neither may contain both.  That is, constraint generation is a
relation on type-schema/type pairs and type/type-schema pairs, only the type
element of which may refer to the `Xi`.

### Notes:

- For convenience, ordering matters in this presentation: where any two clauses
  overlap syntactically, the first match is preferred.
- This presentation is assuming appropriate well-formedness conditions on the
  input types (e.g. non-cyclic class hierarchies)

### Syntactic notes:

- `C0 + C1` is the concatenation of constraint lists `C0` and `C1`.

### Rules

- The unknown type `?` is a subtype match for any type `Q` with no constraints.
- Any type `P` is a subtype match for the unknown type `?` with no constraints.
- A type variable `X` in `L` is a subtype match for any type schema `Q`:
  - Under constraint `? <: X <: Q`.
- A type schema `Q` is a subtype match for a type variable `X` in `L`:
  - Under constraint `Q <: X <: ?`.
- Any two equal types `P` and `Q` are subtype matches under no constraints.
- Any type `P` is a subtype match for `dynamic`, `Object`, or `void` under no
  constraints.
- `Null` is a subtype match for any type `Q` under no constraints.
- `FutureOr<P>` is a subtype match for `FutureOr<Q>` with respect to `L` under
  constraints `C`:
  - If `P` is a subtype match for `Q` with respect to `L` under constraints `C`.
- `FutureOr<P>` is a subtype match for `Q` with respect to `L` under
constraints `C0 + C1`.
  - If `Future<P>` is a subtype match for `Q` with respect to `L` under
    constraints `C0`.
  - And `P` is a subtype match for `Q` with respect to `L` under constraints
    `C1`.
- `P` is a subtype match for `FutureOr<Q>` with respect to `L` under constraints
  `C`:
  - If `P` is a subtype match for `Future<Q>` with respect to `L` under
    constraints `C`.
  - Or `P` is not a subtype match for `Future<Q>` with respect to `L` under
    constraints `C`
    - And `P` is a subtype match for `Q` with respect to `L` under constraints
      `C`
- A type variable `X` not in `L` with bound `P` is a subtype match for the same
type variable `X` with bound `Q` with respect to `L` under constraints `C`:
  - If `P` is a subtype match for `Q` with respect to `L` under constraints `C`.
- A type variable `X` not in `L` with bound `P` is a subtype match for a type
`Q` with respect to `L` under constraints `C`:
  - If `P` is a subtype match for `Q` with respect to `L` under constraints `C`.
- A type `P<M0, ..., Mk>` is a subtype match for `P<N0, ..., Nk>` with respect
to `L` under constraints `C0 + ... + Ck`:
  - If `Mi` is a subtype match for `Ni` with respect to `L` under constraints
    `C`.
- A type `P<M0, ..., Mk>` is a subtype match for `Q<N0, ..., Nj>` with respect
to `L` under constraints `C`:
  - If `R<B0, ..., Bj>` is the superclass of `P<M0, ..., Mk>` and `R<B0, ...,
Bj>` is a subtype match for `Q<N0, ..., Nj>` with respect to `L` under
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
- A generic function type `<T0 extends B0, ..., Tn extends Bn>F0` is a subtype
match for a generic function type `<S0 extends B0, ..., Sn extends Bn>F1` with
respect to `L` under constraints `Cl`:
  - If `F0[Z0/T0, ..., Zn/Tn]` is a subtype match for `F0[Z0/S0, ..., Zn/Sn]`
with respect to `L` under constraints `C`, where each `Zi` is a fresh type
variable with bound `Bi`.
  - And `Cl` is `C` with each constraint replaced with its closure with respect
    to `[Z0, ..., Zn]`.

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
    is not compatible, this this should always be a type error anyway, so
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
