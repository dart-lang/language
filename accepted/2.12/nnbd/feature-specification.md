# Null safety: Sound non-nullable types by default with incremental migration

Author: leafp@google.com

Status: Draft

## CHANGELOG

2021.07.28
  - Allow a constant factory constructor in a class with a late final instance
    variable.

2020.12.30
  - Remove the warning for overrides with different default values.
  - Specify canonicalization of type literals.
  - Specify the unsound mode legacy rewrite of type arguments to const
    constructors and literals.
  - Specify that constant object canonicalization is done with respect to normal
    forms of generic type arguments.

2020.11.09
  - Change terminology to use sound or unsound null checking rather than
    weak or strong mode.

2020.10.14
  - Include selector `!` among the null-shorting constructs.

2020.10.12
  - Clarify that operators not mentioned explicitly in the rules
    do not participate in the null-shorting transformation.

2020.10.09
  - Clarify that `main` cannot be a getter.

2020.10.05
  - Specify that a null-aware static member access (e.g., `C?.staticMethod()`)
    is a warning.

2020.09.21
  - Specify that when a variable inferred from an initializer with intersection
    type is immediately promoted, the intersection type is a type of interest.

2020.09.10
  - Specify updates to super-bounded type rules for null safety.

2020.08.12
  - Specify constraints on the `main` function.

2020.08.06
  - Specify error for uninitialized final instance variable in class
    with no generative constructors.

2020.07.09
  - Specify combined member signature and spread element typing
    with null safety.

2020.06.02
  - Fix the diff to the spec for potentially constant instance checks
  - Specify that extensions do not apply to values of type `Never`
  - Specify the treatment of typedefs from legacy libraries

2020.05.20
  - Turn new references to `CastError` into being dynamic type errors.

2020.07.21
  - **CHANGE** Changes to definite assignment for local variables.

2020.05.14
  - **CHANGE** Strong mode is auto-opted in when the "main" file is opted in.
  - **CHANGE** Specify weak mode/strong mode flag.
  - **CHANGE** Specify that it is an error to run in strong mode if any library
    is opted out.
  - **CHANGE** Weak mode does not demote static errors to warnings.

2020.04.30
  - **CHANGE** (by overriding rules in the language specification): Change
    static rules for return statements, and dynamic semantics of return in
    asynchronous non-generators.
  - Add rule that the use of expressions of type `void*` is restricted in
    the same way as the use of expressions of type `void`.

2020.04.30
  - Specify static analysis of `e1 == e2`.

2020.04.20
  - **CHANGE** (by adding a rule that overrides an existing rule in the language
    specification). Specify that it is a compile-time error to await an
    expression whose static type is `void`.

2020.04.13
  - **CHANGE** The default type of the error variable in a catch clause is
    `Object`.

2020.04.08
  - **CHANGE** `NNBD_TOP_MERGE` resolves all conflicting top types to `Object?`.

2020.04.07
  - Clarify semantics of boolean conditional checks in strong and weak mode.

2020.04.02
  - Clarify that legacy class override checks are done with respect to the
    direct super-interfaces.

2020.04.01
  - Adjust mixed-mode inheritance rules to express a consolidated model
    where legacy types prevail in some additional cases; also state
    that mitigated interfaces are used for dynamic instance checks as
    well as for static subtype checks.

2020.03.05
  - Update grammar for null aware subscript.
  - Fix reversed subtype order in assignability.
  - Fix inconsistent uses of `null` and `Null` in instance checks.

2020.02.28
  - Specify that a `covariant late final x;` is an allowed instance variable which
    introduces a setter.

2020.01.31
  - Specify that mixins must not have uninitialized potentially non-nullable
    non-late fields, and nor must classes with no generative constructors.
  - Remove reference to `CastError`. A failed `!` check is just a
    "dynamic type error" like the `as` check in the current language specification.

2020.01.29
  - **CHANGE** Relax the exhaustiveness check on switches.
  - Specify the type of throw expressions.
  - Specify the override inference exception for operator==.
  - **CHANGE** Specify that instantiate to bounds uses `Never` instead of `Null`.
  - **CHANGE** Specify that least and greatest closure uses `Never` instead of
    `Null`.
  - Specify that type variable elimination is performed on constants using least
    closure.
  - Clarify extension method resolution on nullable types.
  - **CHANGE** Add missing cases to `NNBD_TOP_MERGE` and specify its behavior
    on `covariant` parameters.
  - Fix the definition of `NORM` for un-promoted type variables
  - Change the notion of type equality for generic function bounds to mutual
    subtyping.
  - **CHANGE** Specify that debug assertions are added to methods in strong
    mode.

2020.01.27
  - **CHANGE** Change to specification of weak and strong mode instance checks
    to make them behave uniformly across legacy and opted-in libraries.

2020.01.21
  - Clarify that method inheritance checking is done relative to the
    consolidated super-interface signature.

2019.12.27
  - Update errors for switch statements.
  - Make it an error entirely to use the default `List` constructor in opted-in
    code.
  - Clarify that setter/getter assignability uses subtyping instead of
    assignability.

2019.12.17
  - Specify errors around definitely (un)assigned late variables.

2019.12.08
  - Allow elision of default value in abstract methods
  - **CHANGE** Allow operations on `Never` and specify the typing
  - Specify the type signature for calling Object methods on nullable types
  - Specify implicit conversion behavior
  - Allow potentially constant type variables in instance checks and casts
  - Specify the error thrown by the null check operator
  - Specify `fromEnvironment` and `Iterator.current` library breaking changes
  - Fix definition of strictly non-nullable

2019.12.03:
  - Change warnings around null aware operators to account for legacy types.

2019.11.25:
  - Specified implicitly induced getters/setters for late variables.

2019.11.22
  - Additional errors and warnings around late variables

2019.11.21
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
[roadmap](https://github.com/dart-lang/language/blob/master/accepted/2.12/nnbd/roadmap.md).

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

The modifier `required` is added as a built-in identifier.  The grammar of
function types is extended to allow any named parameter declaration to be
prefixed by the `required` modifier (e.g. `int Function(int, {int?  y, required
int z})`.

The grammar of selectors is extended to allow null-aware subscripting using the
syntax `e1?[e2]` which evaluates to `null` if `e1` evaluates to `null` and
otherwise evaluates as `e1[e2]`.

The grammar of cascade sequences is extended to allow the first cascade of a
sequence to be written as `?..` indicating that the cascade is null-shorting.

All of the syntax changes for this feature have been incorporated into
the
[formal grammar](https://github.com/dart-lang/language/blob/master/specification/dartLangSpec.tex),
which serves as the canonical reference for the grammatical changes.

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

#### Null aware subscript

Certain uses of null aware subscripts in conditional expressions are ambiguous.
For example, `{ a?[b]:c }` can be parsed either as a set literal or a map
literal, depending on whether the `?` is interpreted as part of a null aware
subscript or as part of a conditional expression.  Whenever there is a sequence
of tokens which may be parsed either as a conditional expression or as two
expressions separated by a colon, the first of which is a null aware
subscript, parsers shall choose to parse as a conditional expression.


## Static semantics

### Legacy types

The internal representation of types is extended with a type `T*` for every type
`T` to represent legacy pre-NNBD types.  This is discussed further in the legacy
library section below.

### Subtyping

We modify the subtyping rules to account for nullability and legacy types as
specified
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/subtyping.md).
We write `S <: T` to mean that the type `S` is a subtype of `T` according to the
rules specified there.


We define `LEGACY_SUBTYPE(S, T)` to be true iff `S` would be a subtype of `T`
in a modification of the rules above in which all `?` on types were ignored, `*`
was added to each type, and `required` parameters were treated as optional.
This has the effect of treating `Never` as equivalent to `Null`, restoring
`Null` to the bottom of the type hierarchy, treating `Object` as nullable, and
ignoring `required` on named parameters.  This is intended to provide the same
subtyping results as pre-nnbd Dart.

Where potentially ambiguous, we sometimes write `NNBD_SUBTYPE(S, T)` to mean
the full subtyping relation without the legacy exceptions defined in the
previous paragraph.

### Upper and lower bounds

We modify the upper and lower bound rules to account for nullability and legacy
types as
specified
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/upper-lower-bounds.md).

### Type normalization

We define a normalization procedure on types which defines a canonical
representation for otherwise equivalent
types
[here](https://github.com/dart-lang/language/blob/master/resources/type-system/normalization.md).
This defines a procedure **NORM(`T`)** such that **NORM(`T`)** is syntactically
equal to **NORM(`S`)** modulo replacement of primitive top types iff `S <: T`
and `T <: S`.

### Future flattening

The **flatten** function is modified as follows:

**flatten**(`T`) is defined by cases on `T`:
  - if `T` is `S?` then **flatten**(`T`) = **flatten**(`S`)`?`
  - otherwise if `T` is `S*` then **flatten**(`T`) = **flatten**(`S`)`*`
  - otherwise if `T` is `FutureOr<S>` then **flatten**(`T`) = `S`
  - otherwise if `T <: Future` then let `S` be a type such that `T <: Future<S>`
and for all `R`, if `T <: Future<R>` then `S <: R`; then **flatten**(`T`) = `S`
  - otherwise **flatten**(`T`) = `T`

### The future value type of an asynchronous non-generator function

_We specify a concept which corresponds to the static type of objects which may
be contained in the Future object returned by an async function with a given
declared return type._

Let _f_ be an asynchronous non-generator function with declared return type
`T`. Then the **future value type** of _f_ is **futureValueType**(`T`).
The function **futureValueType** is defined as follows:

- **futureValueType**(`S?`) = **futureValueType**(`S`), for all `S`.
- **futureValueType**(`S*`) = **futureValueType**(`S`), for all `S`.
- **futureValueType**(`Future<S>`) = `S`, for all `S`.
- **futureValueType**(`FutureOr<S>`) = `S`, for all `S`.
- **futureValueType**(`void`) = `void`.
- **futureValueType**(`dynamic`) = `dynamic`.
- Otherwise, for all `S`, **futureValueType**(`S`) = `Object?`.

_Note that it is a compile-time error unless the return type of an asynchronous
non-generator function is a supertype of `Future<Never>`, which means that
the last case will only be applied when `S` is `Object` or a top type._

### Return statements

The static analysis of return statements is changed in the following
way, where `$T$` is the declared return type and `$S$` is the static type of
the expression `e`.

At [this location](https://github.com/dart-lang/language/blob/65b8267be0ebb9b3f0849e2061e6132021a4827d/specification/dartLangSpec.tex#L15477)
about synchronous non-generator functions, the text is changed as follows:

```
It is a compile-time error if $s$ is \code{\RETURN{} $e$;},
$T$ is neither \VOID{} nor \DYNAMIC,
and $S$ is \VOID.
```

_Comparing to Dart before null-safety, this means that it is no longer allowed
to return a void expression in a regular function if the return type is
`Null`._

At [this location](https://github.com/dart-lang/language/blob/65b8267be0ebb9b3f0849e2061e6132021a4827d/specification/dartLangSpec.tex#L15507)
about an asynchronous non-generator function with future value type `$T_v$`,
the text is changed as follows:

```
It is a compile-time error if $s$ is \code{\RETURN{};},
unless $T_v$
is \VOID, \DYNAMIC, or \code{Null}.
%
It is a compile-time error if $s$ is \code{\RETURN{} $e$;},
$T_v$ is \VOID,
and \flatten{S} is neither \VOID, \DYNAMIC, \code{Null}.
%
It is a compile-time error if $s$ is \code{\RETURN{} $e$;},
$T_v$ is neither \VOID{} nor \DYNAMIC,
and \flatten{S} is \VOID.
%
It is a compile-time error if $s$ is \code{\RETURN{} $e$;},
\flatten{S} is not \VOID,
$S$ is not assignable to $T_v$,
and flatten{S} is not a subtype of $T_v$.
```

_Comparing to Dart before null-safety, this means that it is no longer allowed
to return an expression whose flattened static type is `void` in an `async`
function with future value type `Null`; nor is it allowed, in an `async`
function with future value type `void`, to return an expression whose flattened
static type is not `void`, `void*`, `dynamic`, or `Null`. Conversely, it is
allowed to return a future when the future value type is a suitable future;
for instance, we can have `return Future<int>.value(42)` in an `async` function
with declared return type `Future<Future<int>>`. Finally, let `S` be
`Future<dynamic>` or `FutureOr<dynamic>`; it is then no longer allowed to
return an expression with static type `S`, unless the future value type is a
supertype of `S`. This differs from Dart before null-safety in that it was
allowed to return an expression of these types with a declared return type
of the form `Future<T>` for any `T`._

The dynamic semantics specified at
[this location](https://github.com/dart-lang/language/blob/65b8267be0ebb9b3f0849e2061e6132021a4827d/specification/dartLangSpec.tex#L15597)
is changed as follows, where `$f$` is the enclosing function with declared
return type `$T$`, and `$e$` is the returned expression:

```
When $f$ is a synchronous non-generator, evaluation proceeds as follows:
The expression $e$ is evaluated to an object $o$.
A dynamic error occurs unless the dynamic type of $o$ is a subtype of
the actual return type of $f$
(\ref{actualTypes}).
Then the return statement $s$ completes returning $o$
(\ref{statementCompletion}).

\commentary{%
The case where the evaluation of $e$ throws is covered by the general rule
which propagates the throwing completion from $e$ to $s$ to the function body.%
}

When $f$ is an asynchronous non-generator with future value type $T_v$
(\ref{functions}), evaluation proceeds as follows:
The expression $e$ is evaluated to an object $o$.
If the run-time type of $o$ is a subtype of \code{Future<$T_v$>},
let \code{v} be a fresh variable bound to $o$ and
evaluate \code{\AWAIT{} v} to an object $r$;
otherwise let $r$ be $o$.
A dynamic error occurs unless the dynamic type of $r$
is a subtype of the actual value of $T_v$
(\ref{actualTypes}).
Then the return statement $s$ completes returning $r$
(\ref{statementCompletion}).

\commentary{%
The cases where $f$ is a generator cannot occur,
because in that case $s$ is a compile-time error.%
}
```

### Static errors
#### Nullability definitions

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

We say that a type `T` is **strictly non-nullable** if `T <: Object` and not
`Null <: T`.  This is equivalent to the syntactic criterion that `T` is any of:
  - `Never`
  - Any function type (including `Function`)
  - Any interface type except `Null`.
  - `FutureOr<S>` where `S` is strictly non-nullable
  - `X extends S` where `S` is strictly non-nullable
  - `X & S` where `S` is strictly non-nullable

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
but not non-nullable.  Note that `T*` is potentially non-nullable by this
definition if `T` is potentially non-nullable.


#### Reachability

A number of errors and warnings are updated to take reachability of statements
into account.  Computation of code reachability
is
[specified separately](https://github.com/dart-lang/language/blob/master/resources/type-system/flow-analysis.md).

We say that a statement **may complete normally** if the specified control flow
analysis determines that any control flow path may reach the end of the
statement without returning, throwing an exception not caught within the
statement, breaking to a location outside of the statement, or continuing to a
location outside of the statement.

#### Errors and Warnings

It is an error to call a method, setter, getter or operator on an expression
whose type is potentially nullable and not `dynamic`, except for the methods,
setters, getters, and operators on `Object`.

It is an error to read a field or tear off a method from an expression whose
type is potentially nullable and not `dynamic`, except for the methods and
fields on `Object`.

It is an error to call an expression whose type is potentially nullable and not
`dynamic`.

It is an error if a top level variable or static variable with a non-nullable
type has no initializer expression unless the variable is marked with a `late`
or `external` modifier.

It is an error if a class declaration declares an instance variable with a
potentially non-nullable type and no initializer expression, and the class has a
generative constructor where the variable is not initialized via an initializing
formal or an initializer list entry, unless the variable is marked with a
`late`, `abstract`, or `external` modifier.

It is an error if a mixin declaration or a class declaration with no generative
constructors declares an instance variable without an initializing expression
which is final or whose type is potentially non-nullable, unless the variable is
marked with a `late`, `abstract`, or `external` modifier.

It is an error to derive a mixin from a class declaration which contains an
instance variable with a potentially non-nullable type and no initializer
expression unless the variable is marked with the `late` modifier.

It is an error if the body of a method, function, getter, or function expression
with a potentially non-nullable return type **may complete normally**.

It is an error if an optional parameter (named or otherwise) with no default
value has a potentially non-nullable type **except** in the parameter list of an
abstract method declaration.

It is an error if a required named parameter has a default value.

It is an error if a required named parameter is not bound to an argument at a
call site.

It is an error to call the default `List` constructor.

For the purposes of errors and warnings, the null aware operators `?.`, `?..`,
and `?[]` are checked as if the receiver of the operator had non-nullable type.
More specifically, if the type of the receiver of a null aware operator is `T`,
then the operator is checked as if the receiver had type **NonNull**(`T`) (see
definition below).

It is an error for a class to extend, implement, or mixin a type of the form
`T?` for any `T`.

It is an error for a class to extend, implement, or mixin the type `Never`.

It is not an error to call or tear-off a method, setter, or getter, or to read
or write a field, on a receiver of static type `Never`.  Implementations that
provide feedback about dead or unreachable code are encouraged to indicate that
any arguments to the invocation are unreachable.

It is not an error to apply an expression of type `Never` in the function
position of a function call. Implementations that provide feedback about dead or
unreachable code are encouraged to indicate that any arguments to the call are
unreachable.

It is an error if the static type of `e` in the expression `throw e` is not
assignable to `Object`.

It is not an error for the body of a `late` field to reference `this`.

It is an error for a variable to be declared as `late` in any of the following
positions: in a formal parameter list of any kind; in a catch clause; in the
variable binding section of a c-style `for` loop, a `for in` loop, an `await
for` loop, or a `for element` in a collection literal.

It is an error for the initializer expression of a `late` local variable to use
a prefix `await` expression that is not nested inside of another function
expression.

It is an error for a class with a generative `const` constructor to have a 
`late final` instance variable.

It is not a compile time error to write to a `final` non-local or instance
variable if that variable is declared `late` and does not have an initializer.
For local variables, see the section below.

It is an error if the object being iterated over by a `for-in` loop has a static
type which is not `dynamic`, and is not a subtype of `Iterable<dynamic>`.

It is an error if the type of the value returned from a factory constructor is
not a subtype of the class type associated with the class in which it is defined
(specifically, it is an error to return a nullable type from a factory
constructor for any class other than `Null`).

It is an error if any case of a switch statement except the last case (the
default case if present) **may complete normally**.  The previous syntactic
restriction requiring the last statement of each case to be one of an enumerated
list of statements (break, continue, return, throw, or rethrow) is removed.

Given a switch statement which switches over an expression `e` of type `T`,
where the cases are dispatched based on expressions `e0`...`ek`:
  - It is no longer required that the `ei` evaluate to instances of the same
    class.
  - It is an error if any of the `ei` evaluate to a value whose static type is
    not a subtype of `T`.
  - It is an error if any of the `ei` evaluate to constants for which equality
    is not primitive.
  - If `T` is an enum type, it is a warning if the switch does not handle all
    enum cases, either explicitly or via a default.
  - If `T` is `Q?` where `Q` is an enum type, it is a warning if the switch does
    not handle all enum cases and `null`, either explicitly or via a default.

It is an error if a class has a setter and a getter with the same basename where
the return type of the getter is not a subtype of the argument type of the
setter.  Note that this error specifically requires subtyping and not
assignability and hence makes no exception for `dynamic`.

If the static type of `e` is `void`, the expression `await e` is a compile-time
error. *This implies that
[this](https://github.com/dart-lang/language/blob/780cd5a8be92e88e8c2c74ed282785a2e8eda393/specification/dartLangSpec.tex#L18281)
list item will be removed from the language specification.*

A compile-time error occurs if an expression has static type `void*`, and it
does not occur in any of the ways specified in
[this list](https://github.com/dart-lang/language/blob/780cd5a8be92e88e8c2c74ed282785a2e8eda393/specification/dartLangSpec.tex#L18238).
*This implies that `void*` is treated the same as `void`.*

Let `C` be a type literal denoting a class, mixin, or extension. It is a warning
to use a null aware member access with receiver `C`. *E.g., `C?.staticMethod()`
is a warning.*

It is a warning to use a null aware operator (`?.`, `?[]`, `?..`, `??`, `??=`, or
`...?`) on an expression of type `T` if `T` is **strictly non-nullable**.

It is a warning to use the null check operator (`!`) on an expression of type
`T` if `T` is **strictly non-nullable** .

It is no longer a warning to override a method which has a default value for a
parameter with a method with a different default value for the corresponding
parameter.

### Local variables and definite (un)assignment.

As part of the null safety release, errors for local variables are specified to
take into account **definite assignment** and **definite unassignment** (see the
section on Definite Assignment below).  We say that a variable is **potentially
assigned** if it is not **definitely unassigned**, and that a variable is
**potentially unassigned** if it is not **definitely assigned**.

In all cases in this section, errors that are described as occurring on reads of
a variable are intended to apply to all form of reads, including indirectly as
part of compound assignment operators, as well as via pre and post-fix
operators.  Similarly, errors that are described as occurring on writes of a
variable are intended to apply to all form of writes.

It is a compile time error to assign a value to a `final`, non-`late` local
variable which is **potentially assigned**.  Thus, it is *not* a compile time
error to assign to a **definitely unassigned** `final` local variable.

It is a compile time error to assign a value to a `final`, `late` local variable
if it is **definitely assigned**. Thus, it is *not* a compile time error to
assign to a **potentially unassigned** `final`, `late` local variable.

*Note that a variable is always considered **definitely assigned** and not
**definitely unassigned** if it has an explicit initializer, or an implicit
initializer as part of a larger construct (e.g. the loop variable in a `for in`
construct).*

It is a compile time error to read a local variable when the variable is
**definitely unassigned** unless the variable is non-`final`, and non-`late`,
and has nullable type.

It is a compile time error to read a local variable when the variable is
**potentially unassigned** unless the variable is non-`final` and has nullable
type, or is `late`.

The errors specified above are summarized in the following table, where `int` is
used as an example of an arbitrary **potentially non-nullable** type, `int?` is
used as an example of an arbitrary **nullable** type, and `T` is used to stand
for a type of any nullability.  A variable which has an initializer (explicit or
implicit) is always considered definitely assigned, and is never considered
definitely unassigned.


Read Behavior:

| Declaration form  | Def. Assigned | Neither           | Def. Unassigned |
| ----------------- | ------------- | ----------------- | --------------- |
| var x;            | Ok            | Ok                | Ok              |
| final x;          | Ok            | Error             | Error           |
| int x;            | Ok            | Error             | Error           |
| int? x;           | Ok            | Ok                | Ok              |
| final T x;        | Ok            | Error             | Error           |
| late var x;       | Ok            | Ok                | Error           |
| late final x;     | Ok            | Ok                | Error           |
| late T x;         | Ok            | Ok                | Error           |
| late final T x;   | Ok            | Ok                | Error           |

Write Behavior:

| Declaration form  | Def. Assigned | Neither             | Def. Unassigned |
| ----------------- | ------------- | ------------------- | --------------- |
| var x;            | Ok            | Ok                  | Ok              |
| final x;          | Error         | Error               | Ok              |
| int x;            | Ok            | Ok                  | Ok              |
| int? x;           | Ok            | Ok                  | Ok              |
| final T x;        | Error         | Error               | Ok              |
| late var x;       | Ok            | Ok                  | Ok              |
| late final x;     | Error         | Ok                  | Ok              |
| late T x;         | Ok            | Ok                  | Ok              |
| late final T x;   | Error         | Ok                  | Ok              |

### Local variables and inference

Local variables with explicitly written types are given the declared types as
written.  The declared type of the variable is considered a "type of interest"
in the sense defined in the flow analysis specification.  If the variable has an
initializer (explicit or implicit) and is not `final`, then the declaration is
treated as an assignment for the purposes of promotion.

*Treating the declared type of the variable as a "type of interest" implies that
if the variable has a nullable type, then the non-nullable version of that type
is also a type of interest.  Treating the initialization as an assignment for
the purposes of promotion means that initializing a mutable variable declared at
type `T?` with a value of non-nullable type `T` immediately promotes the
variable to the non-nullable type.*

```dart
void test() {
  int? x = 3; // x is declared at `int?`
  x.isEven; // Valid, x has been promoted to `int`
  x = null; // Valid, demotes to the declared type.
}
```

Local variables with no explicitly written type but with an initializer are
given an inferred type equal to the type of their initializer, unless that type
is `Null`, in which case the inferred type of the variable shall be `dynamic`.
The inferred type of the variable is considered a "type of interest" in the
sense defined in the flow analysis specification.  In the case that the type of
the initializer is a promoted type variable `X & T`, the inferred type of the
variable shall be `X`, but `X & T` shall be considered as a type of interest and
the initialization treated as an assignment for the purposes of promotion.
Consequently, such a variable shall be treated as immediately promoted to `X &
T`.

### Expression typing

It is permitted to invoke or tear-off a method, setter, getter, or operator that
is defined on `Object` on potentially nullable type.  The type used for static
analysis of such an invocation or tear-off shall be the type declared on the
relevant member on `Object`.  For example, given a receiver `o` of type `T?`,
invoking an `Object` member on `o` shall use the type of the member as declared
on `Object`, regardless of the type of the member as declared on `T` (note that
the type as declared on `T` must be a subtype of the type on `Object`, and so
choosing the `Object` type is a sound choice.  The opposite choice is not
sound).

_Note that evaluation of an expression `e` of the form `e1 == e2` is not an
invocation of `operator ==`, it includes special treatment of null. The
precise rules are specified later in this section._

Calling a method (including an operator) or getter on a receiver of static type
`Never` is treated by static analysis as producing a result of type `Never`.
Tearing off a method from a receiver of static type `Never` produces a value of
type `Never`.  Applying an expression of type `Never` in the function position
of a function call produces a result of type `Never`.

The static type of a `throw e` expression is `Never`.

Consider an expression `e` of the form `e1 == e2` where the static type of
`e1` is `T1` and the static type of `e2` is `T2`. Let `S` be the type of the
formal parameter of `operator ==` in the interface of **NonNull**(`T1`).
It is a compile-time error unless `T2` is assignable to `S?`.

Similarly, consider an expression `e` of the form `super == e2` that occurs in a
class whose superclass is `C`, where the static type of `e2` is `T2`. Let `S` be
the formal parameter type of the concrete declaration of `operator ==` found by
method lookup in `C` (_if that search succeeds, otherwise it is a compile-time
error_).  It is a compile-time error unless `T2` is assignable to `S?`.

_Even if the static type of `e1` is potentially nullable, the parameter type
of the `operator ==` of the corresponding non-null type is taken into account,
because that instance method will not be invoked when `e1` is null. Similarly,
it is not a compile-time error for the static type of `e2` to be potentially
nullable, even when the parameter type of said `operator ==` is non-nullable.
This is again safe, because the instance method will not be invoked when `e2`
is null._

In legacy mode, an override of `operator ==` with no explicit parameter type
inherits the parameter type of the overridden method if any override of
`operator ==` between the overriding method and `Object.==` has an explicit
parameter type.  Otherwise, the parameter type of the overriding method is
`dynamic`.

Top level variable and local function inference is performed
as
[specified separately](https://github.com/dart-lang/language/blob/master/resources/type-system/inference.md).
Method body inference is not yet specified.

If no type is specified in a catch clause, then the default type of the error
variable is `Object`, instead of `dynamic` as was the case in pre-null safe
Dart.

#### Spread element typing

In a collection literal in Dart before null-safety, the inferred element
type of a spread element of the form `...?e` where `e` has static type
`Null` is `Null`, and so are the inferred key type and value type.

With null-safety, when the static type of `e` is `Null` or a potentially
nullable subtype thereof, the inferred element, key, and value type
of `...?e` is `Never`.

Similarly, when the static type of `e` is a subtype of `Never`,
the element, key, and value type of `...e` and `...?e` is `Never`.

*When the static type _S_ of `e` is strictly non-nullable, such as when _S_
is `Never`, `...?e` is a warning, but it may still occur.*

### Instantiation to bound

The computation of instantiation to bound is changed to substitute `Never` for
type variables appearing in contravariant positions instead of `Null`.

### Super-bounded types

Null safety requires three changes to the section 'Super-Bounded Types' in
the language specification.

The definition of a top type is changed: _T_ is a top type if and only if
`Object?` is a subtype of _T_. Note that the helper predicate **TOP**
provides a syntactic characterization of the same concept.

The definition of a super-bounded type is changed such that occurrences of
`Null` are replaced by types involving `Never`, and `Object` is replaced by
`Object?`. Moreover, top types in invariant positions and in positions that
have no variance (*unused type parameters in a type alias*) are given the
same treatment as top types in covariant positions. This causes one
sentence to change, with the following result:

Let _T'_ be the result of replacing every occurrence in _T_ of a type _S_
in a contravariant position where _S <: Never_ by `Object?`, and every
occurrence in _T_ of a top type in a position which is not contravariant by
`Never`.

### Least and greatest closure

The definitions of least and greatest closure are changed in null safe libraries
to substitute `Never` in positions where previously `Null` would have been
substituted, and `Object?` in positions where previously `Object` or `dynamic`
would have been substituted.

### Const type variable elimination

If performing inference on a const value of a generic class results in
inferred type arguments to the generic class which contain free type variables
from an enclosing generic class or method, the free type variables shall be
eliminated by taking the least closure of the inferred type with respect to the
free type variables.  Note that free type variables which are explicitly used as
type arguments in const generic instances are still considered erroneous.

```dart
class G<T> {
  void foo() {
    const List<T> c = <T>[]; // Error
    const List<T> d = [];    // The list literal is inferred as <Never>[]
  }
}
```

### Extension method resolution

For the purposes of extension method resolution, there is no special treatment
of nullable types with respect to what members are considered accessible.  That
is, the only members of a nullable type that are considered accessible
(and hence which take precedence over extensions) are the members on `Object`.

For the purposes of extension method resolution, the type `Never` is considered
to implement all members, and hence no extension may apply to an expression of
type `Never`.

### Assignability

The definition of assignability is changed as follows.

A type `T` is **assignable** to a type `S` if `T` is `dynamic`, or if `T` is a
subtype of `S`.

### Generics

The default bound of generic type parameters is treated as `Object?`.

### Combined member signatures

[This section](https://github.com/dart-lang/language/blob/9e12517922c1f0021aead2af163c3b502497f312/specification/dartLangSpec.tex#L4241)
in the language specification defines the notion of a _combined member
signature_. In Dart before null-safety it is based on the textually first
superinterface that has a most specific signature. With null-safety it
is changed such that the all the most specific signatures are merged.

This is achieved by changing
[this paragraph](https://github.com/dart-lang/language/blob/9e12517922c1f0021aead2af163c3b502497f312/specification/dartLangSpec.tex#L4373)
to the following:

"Let _m<sub>all</sub>_ be the result of applying `NNBD_TOP_MERGE` to
the elements in _M<sub>all</sub>_, ordered according to the interface
_I<sub>1</sub> .. I<sub>k</sub>_ that each signature came from."

Moreover, the occurrence of _m<sub>i</sub>_ in the next paragraph is
changed to _m<sub>all</sub>_.

### Implicit conversions

The implicit conversion of integer literals to double literals is performed when
the context type is `double` or `double?`.

The implicit tear-off conversion which converts uses of instances of classes
with call methods to the tear-off of their `.call` method is performed when the
context type is a function type, or the nullable version of a function type.

Implicit tear-off conversion is *not* performed on objects of nullable type,
regardless of the context type.  For example:

```dart
class C {
  int call() {}
}
void main() {
  int Function()? c0 = new C(); // Ok
  int Function()? c0 = (null as C?); // static error
  int Function()  c1 = (null as C?); // static error
}
```

### Const objects

The definition of potentially constant expressions is extended to include type
casts and instance checks on potentially constant types, as follows.

We change the following specification text:

```
\item An expression of the form \code{$e$\,\,as\,\,$T$} is potentially constant
  if $e$ is a potentially constant expression
  and $T$ is a constant type expression,
  and it is further constant if $e$ is constant.
```

to

```
\item An expression of the form \code{$e$\,\,as\,\,$T$} or
  \code{$e$\,\,is\,\,$T$} is potentially constant
  if $e$ is a potentially constant expression
  and $T$ is a potentially constant type expression,
  and it is further constant if $e$ is constant.
```

where the definition of a "potentially constant type expression" is the same as
the current definition for a "constant type expression" with the addition that a
type variable is allowed as a "potentially constant type expression".

This is motivated by the requirement to make downcasts explicit as part of the
NNBD release.  Current constant evaluation is permitted to evaluate implicit
downcasts involving type variables.  Without this change, it is difficult to
change such implicit downcasts to an explicit form.  For example this class is
currently valid Dart code, but is invalid after the NNBD restriction on implicit
downcasts because of the implied downcast on the initialization of `w`:


```dart
const num three = 3;

class ConstantClass<T extends num> {
  final T w;
  const ConstantClass() : w = three /* as T */;
}

void main() {
  print(const ConstantClass<int>());
}
```

With this change, the following is a valid migration of this code:

```dart
const num three = 3;

class ConstantClass<T extends num> {
  final T w;
  const ConstantClass() : w = three as T;
}

void main() {
  print(const ConstantClass<int>());
}
```

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

#### Extended Type promotion, Definite Assignment, and Reachability

These are extended as
per
[separate proposal](https://github.com/dart-lang/language/blob/master/resources/type-system/flow-analysis.md).

## Helper predicates

The following helper predicates are used to classify types. They are syntactic
in nature such that termination is obvious. In particular, they do not rely on
subtyping.

The **TOP** predicate is true for any type which is in the equivalence class of
top types.

- **TOP**(`T?`) is true iff **TOP**(`T`) or **OBJECT**(`T`)
- **TOP**(`T*`) is true iff **TOP**(`T`) or **OBJECT**(`T`)
- **TOP**(`dynamic`) is true
- **TOP**(`void`) is true
- **TOP**(`FutureOr<T>`) is **TOP**(T)
- **TOP**(T) is false otherwise

**TOP**(`T`) is true if and only if `T` is a supertype of `Object?`.

The **OBJECT** predicate is true for any type which is in the equivalence class
of `Object`.

- **OBJECT**(`Object`) is true
- **OBJECT**(`FutureOr<T>`) is **OBJECT**(T)
- **OBJECT**(`T`) is false otherwise

**OBJECT**(`T`) is true if and only if `T` is a subtype and a supertype of
`Object`.

The **BOTTOM** predicate is true for things in the equivalence class of `Never`.

- **BOTTOM**(`Never`) is true
- **BOTTOM**(`X&T`) is true iff **BOTTOM**(`T`)
- **BOTTOM**(`X extends T`) is true iff **BOTTOM**(`T`)
- **BOTTOM**(`T`) is false otherwise

**BOTTOM**(`T`) is true if and only if `T` is a subtype of `Never`.

The **NULL** predicate is true for things in the equivalence class of `Null`

- **NULL**(`Null`) is true
- **NULL**(`T?`) is true iff **NULL**(`T`) or **BOTTOM**(`T`)
- **NULL**(`T*`) is true iff **NULL**(`T`) or **BOTTOM**(`T`)
- **NULL**(`T`) is false otherwise

**NULL**(`T`) is true if and only if `T` is a subtype and a supertype of `Null`.

The **MORETOP** predicate defines a total order on top and `Object` types.

- **MORETOP**(`void`, `T`) = true
- **MORETOP**(`T`, `void`) = false
- **MORETOP**(`dynamic`, `T`) = true
- **MORETOP**(`T`, `dynamic`) = false
- **MORETOP**(`Object`, `T`) = true
- **MORETOP**(`T`, `Object`) = false
- **MORETOP**(`T*`, `S*`) = **MORETOP**(`T`, `S`)
- **MORETOP**(`T`, `S*`) = true
- **MORETOP**(`T*`, `S`) = false
- **MORETOP**(`T?`, `S?`) = **MORETOP**(`T`, `S`)
- **MORETOP**(`T`, `S?`) = true
- **MORETOP**(`T?`, `S`) = false
- **MORETOP**(`FutureOr<T>`, `FutureOr<S>`) = **MORETOP**(T, S)

The **MOREBOTTOM** predicate defines an (almost) total order on bottom and
`Null` types.  This does not currently consistently order two different type
variables with the same bound.

- **MOREBOTTOM**(`Never`, `T`) = true
- **MOREBOTTOM**(`T`, `Never`) = false
- **MOREBOTTOM**(`Null`, `T`) = true
- **MOREBOTTOM**(`T`, `Null`) = false
- **MOREBOTTOM**(`T?`, `S?`) = **MOREBOTTOM**(`T`, `S`)
- **MOREBOTTOM**(`T`, `S?`) = true
- **MOREBOTTOM**(`T?`, `S`) = false
- **MOREBOTTOM**(`T*`, `S*`) = **MOREBOTTOM**(`T`, `S`)
- **MOREBOTTOM**(`T`, `S*`) = true
- **MOREBOTTOM**(`T*`, `S`) = false
- **MOREBOTTOM**(`X&T`, `Y&S`) = **MOREBOTTOM**(`T`, `S`)
- **MOREBOTTOM**(`X&T`, `S`) = true
- **MOREBOTTOM**(`S`, `X&T`) = false
- **MOREBOTTOM**(`X extends T`, `Y extends S`) = **MOREBOTTOM**(`T`, `S`)

The **ERASEINTERSECTION** function maps `X&T` to `X` and every other type to
itself.

- **ERASEINTERSECTION**(`X&T`) = `X`
- **ERASEINTERSECTION**(`T`) = `T`

### The main function

The section 'Scripts' in the language specification is replaced by the
following:

Let _L_ be a library that exports a declaration _D_ named `main`.  It is a
compile-time error unless _D_ is a non-getter function declaration.  It is a
compile-time error if _D_ declares more than two required positional
parameters, or if there are any required named parameters.  It is a
compile-time error if _D_ declares at least one positional parameter, and
the first positional parameter has a type which is not a supertype of
`List<String>`.

Implementations are free to impose any additional restrictions on the
signature of `main`.

A _script_ is a library that exports a declaration named `main`.
A script _L_ is executed as follows:

First, _L_ is compiled as a library as specified above.
Then, the top-level function defined by `main`
in the exported namespace of _L_ is invoked as follows:

If `main` can be called with two positional arguments,
it is invoked with the following two actual arguments:

- An object whose run-time type implements `List<String>`.
- An object specified when the current isolate _i_ was created,
  for example through the invocation of `Isolate.spawnUri` that spawned _i_,
  or the null object if no such object was supplied.
  A dynamic error occurs if the run-time type of this object is not a
  subtype of the declared type of the corresponding parameter of `main`.

If `main` cannot be called with two positional arguments, but it can be
called with one positional argument, it is invoked with an object whose
run-time type implements `List<String>` as the only argument.

If `main` cannot be called with one or two positional arguments, it is
invoked with no arguments.

In each of the above three cases, an implementation is free to provide
additional arguments allowed by the signature of `main` (*the above rules
ensure that the corresponding parameters are optional*).  But the
implementation must ensure that a dynamic error occurs if an actual
argument does not have a run-time type which is a subtype of the declared
type of the parameter.

A Dart program will typically be executed by executing a script.  The
procedure whereby this script is chosen is implementation specific.

## Runtime semantics

### Unsound and sound semantics

To allow the null safety feature to be rolled out incrementally, we define two
modes of compilation and execution.

**Unsound null checking** mode largely ignores the nullability of types at
runtime, as defined below.  Unmigrated programs or programs consisting of a
mix of migrated and unmigrated code are expected to run without encountering
new nullability related errors at runtime.  **This mode is unsound** in the
sense that variables marked as non-nullable may still be null at runtime.

**Sound null checking** mode respects the nullability of types at runtime in
casts and instance checks, as defined below.  Unmigrated programs or programs
consisting of a mix of migrated and unmigrated code may not be compiled or run
with sound null checking, and it is a compile time error if unmigrated
code is attempted to be compiled with sound null checking enabled.

Unsound vs sound null checking can be controlled at runtime via the
`--[no-]sound-null-safety` flag, where the negated version of the flag implies
unsound null checking and the unnegated version implies sound null checking.

In the absence of an explicit value for the flag, the mode of execution depends
on migrated status of the program entry point.  If the entry point of the
program (`main`) is in an opted-in library, then the program is compiled and run
as if `--sound-null-safety` were specified on the command line.  Otherwise,
the program is run as if `--no-sound-null-safety` were specified on the
command line.

Compilers may (and are encouraged to) print a warning indicating that sound null
checking has been disabled when compiling a program that contains migrated
libraries with unsound null checking.

### Runtime type equality operator

Two objects `T1` and `T2` which are instances of `Type` (that is, runtime type
objects) are considered equal if and only if the runtime type objects `T1` and
`T2` corresponds to the types `S1` and `S2` respectively, and the normal forms
**NORM(`S1`)** and **NORM(`S2`)** are syntactically equal up to equivalence of
bound variables and **ignoring `*` modifiers on types**.  So for example, the
runtime type objects corresponding to `List<int>` and `List<int*>` are
considered equal.  Note that we do not equate primitive top types.  `List<void>`
and `List<dynamic>` are still considered distinct runtime type objects.  Note
that we also do not equate `Never` and `Null`, and we do not equate function
types which differ in the placement of `required` on parameter types.  Because
of this, the equality described here is not equivalent to syntactic equality on
the `LEGACY_ERASURE` of the types.


### Const evaluation and canonicalization

Const evaluation is modified so that both type literals and legacy and opted-in
instances canonicalize more consistently as defined below.

#### Type literals

Two constant type literals `T1` and `T2` compare as identical if they
are equal using the definition of runtime type equality specified above.

The effect of this definition is to ensure that constant type literals which
look identical in the source syntax but which may differ by the presence of
legacy type modifiers are canonicalized consistently in the sense that any two
type literals which would compare equal via the definition of runtime type
equality given above will compare as identical.  For runtime implementations
which implement identity by choosing a canonical representative for the
equivalence class of equal instances, the choice of what type object to
canonicalize to is arbitrary in that placement of legacy modifiers in type
literals is not otherwise observable in the language.

Note that the choice of canonicalization for type literals does not depend
directly on whether sound or unsound null checking is in use.

#### Constant instances

In both sound and unsound null checking, and in both opted in and opted out
code, comparison of constant instances for identity is defined such that any two
instances which are otherwise identical except for their generic type arguments
shall be considered identical if those generic type arguments compare equal
using the definition of runtime type object equality defined above.  That is,
comparison (or canonicalization) of constant instances of generic classes is
performed relative to the normal forms of their generic type arguments, and
ignoring legacy type annotations as described above.  Hence, an instance of
`C<T0>` compares identical to `C<T1>` if `T0` and `T1` have the same normal form
(up to the identity of bound variables), and the objects are otherwise
identical.

Implementations of the Dart runtime semantics rely on canonicalization of
constant objects to allow the identity semantics specified above to be
implemented as fast pointer equality checks on the reference to the canonical
form.  The definition above defines equivalence classes of constant objects for
which we must choose the canonical representative.  The choice of this
representative is observable in mixed mode programs, since instances with
different degrees of "legacy-ness" in their type arguments are considered
identical, but may contain operations which perform casts and instance checks
which will evaluate differently depending on whether a legacy type or a
non-legacy type is used in the canonical representative.  For example:

```dart
// null safe code.
class C<T> {
  final T x;
  void test(Object? o) {
    o as T;
  }
  const C(Object? o) : x = o as T;
}

// If the canonical instance uses `int`, this is a compile time error
// If the canonical instance uses `int*`, this is not a compile time error
const c1 = C<int>(null);

// If the canonical instance uses `int`, this throws
// If the canonical instance uses `int*`, this does not throw
void test1() => c1.test(null);


// Opted out code

// If the canonical instance uses `int`, this is a compile time error
// If the canonical instance uses `int*`, this is not a compile time error
const c2 = C<int>(null);

// If the canonical instance uses `int`, this throws
// If the canonical instance uses `int*`, this does not throw
void test1() => c2.test(null);
```

We therefore define the choice of the canonical instance representing an
equivalence class of constant objects as follows.

With sound null checking, all generic const constructors and generic const
literals are evaluated using the type arguments provided, and canonicalization
is performed with respect to the normal form of the type arguments.  This
ensures that with sound null checking, the final consistent semantics are
obeyed, since it is not observable which instance is chosen as the canonical
representative in sound mode.

With unsound null checking, all generic constant object expressions are
additionally treated as if all type arguments passed to them were legacy types
regardless of whether the constructed class was defined in a legacy library or
not, and regardless of whether the constructor invocation or literal occured in
a legacy library or not.  Specifically, a constant object expression with
generic type parameters `Ti` is treated as if the parameters were
**CONST_CANONICAL_TYPE**('Ti') as defined below.  This ensures that const
objects which appear identical in the syntax continue to canonicalize
consistently across legacy and opted-in libraries.

The Dart static analysis tool does not distinguish between sound and unsound
checking mode, and hence it is expected that there will be some small level of
infidelity in the constant evaluation semantics in the analyzer.  Identity
semantics for constant objects can be faithfully modeled in the analyzer using
the existing strategy of implementing identity directly, rather than via
choosing a canonical representative for each equivalence class.  However, the
lack of a canonical representative is observable at compile time in rare cases,
such as the example shown above.  We propose that the analyzer should choose to
evaluate those constants in opted in libraries using sound mode semantics, and
to evaluate those in opted out libraries using unsound mode semantics.  Hence in
the example above, the definition of `c1` would be a compile time error, but the
definition of `c2` would not.

The **CONST_CANONICAL_TYPE**(`T`) erasure operation on types `T` used above is
defined as follows.

- **CONST_CANONICAL_TYPE**(`T`) = `T` if `T` is `dynamic`, `void`, `Null`
- **CONST_CANONICAL_TYPE**(`T`) = `T*` if `T` is `Never` or `Object`
- **CONST_CANONICAL_TYPE**(`FutureOr<T>`) = `FutureOr<S>*`
  - where `S` is **CONST_CANONICAL_TYPE**(`T`)
- **CONST_CANONICAL_TYPE**(`T?`) =
  - let `S` be **CONST_CANONICAL_TYPE**(`T`)
  - if `S` is `R*` then `R?`
  - else `S?`
- **CONST_CANONICAL_TYPE**(`T*`) = **CONST_CANONICAL_TYPE**(`T`)
- **CONST_CANONICAL_TYPE**(`X extends T`) = `X*`
- **CONST_CANONICAL_TYPE**(`X & T`) =
  - This case should not occur, since intersection types are not permitted as
    generic arguments.
- **CONST_CANONICAL_TYPE**(`C<T0, ..., Tn>`) = `C<R0, ..., Rn>*`
  - where `Ri` is **CONST_CANONICAL_TYPE**(`Ti`)
  - Note this includes the case of an interface type with no generic parameters
    (e.g `int`).
- **CONST_CANONICAL_TYPE**(`R Function<X extends B>(S)`) = `F*`
  - where `F = R1 Function<X extends B1>(S1)`
  - and `R1` = **CONST_CANONICAL_TYPE**(`R`)
  - and `B1` = **CONST_CANONICAL_TYPE**(`B`)
  - and `S1` = **CONST_CANONICAL_TYPE**(`S`)
  - Note, this generalizes to arbitrary number of type and term parameters.

Note that if `T` is a normal form type, then **CONST_CANONICAL_TYPE**(`T`) is
also a normal form type.


### Null check operator

When evaluating an expression of the form `e!`,
where `e` evaluates to a value `v`,
a dynamic type error occurs if `v` is `null`,
and otherwise the expression evaluates to `v`.

### Null aware operator

The semantics of the null aware operator `?.` are defined via a source to source
translation of expressions into Dart code extended with a let binding construct.
The translation is defined using meta-level functions over syntax.  We use the
notation `fn[x : Exp] : Exp => E` to define a meta-level function of type `Exp
-> Exp` (that is, a function from expressions to expressions), and similarly
`fn[k : Exp -> Exp] : Exp => E` to define a meta-level function of type `Exp ->
Exp -> Exp`.  Where obvious from context, we elide the parameter and return
types on the meta-level functions.  The meta-variables `F` and `G` are used to
range over meta-level functions.  Application of a meta-level function is
written as `F[p]` where `p` is the argument.

The null-shorting translation of an expression `e` is meta-level function `F` of
type `(Exp -> Exp) -> Exp` which takes as an argument the continuation of `e` and
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
  PASSTHRU = fn[F : (Exp -> Exp) -> Exp, c : Exp -> Exp] =>
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
- If `e1` translates to `F` then `e1?[e2]` translates to:
  - `SHORT[EXP(e1), fn[x] => x[EXP(e2)]]`
- If `e1` translates to `F` then `e1[e2]` translates to:
  - `PASSTHRU[F, fn[x] => x[EXP(e2)]]`
- If `e` translates to `F` then `e!` translates to:
  - `PASSTHRU[F, fn[x] => x!]`
- The assignment `e1?.f = e2` translates to:
  - `SHORT[EXP(e1), fn[x] => x.f = EXP(e2)]`
- The other assignment operators are handled equivalently.
- If `e1` translates to `F` then `e1.f = e2` translates to:
  - `PASSTHRU[F, fn[x] => x.f = EXP(e2)]`
- The other assignment operators are handled equivalently.
- If `e1` translates to `F` then `e1?[e2] = e3` translates to:
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

The language specification specifies that an invocation of any of several
operators is considered equivalent to a member access (this applies to
relational expressions, bitwise expressions, shift expressions, additive
expressions, multiplicative expressions, and unary expressions).

*For example, `a + b` is specified as equivalent to `a.plus(b)`,
where `plus` is assumed to be a method with the same behavior as `+`.
Similarly, `-e` is equivalent to `e.unaryMinus()`.*

This equivalence is not applicable in the above rules, so operators not
mentioned specifically in a rule are handled in the case for 'other'
expressions, not in the case for `e.m(args)`.

*This means that the null-shorting transformation stops at operators. For
instance, `e?.f + b` is a compile-time error because `e?.f` can be null, it is
not an expression where both `.f` and `+ b` will be skipped if `e` is null.
Similarly, both `-a?.f` and `~a?.f` are errors, and do not null-short like
`a?.f.op()`.*

### Late fields and variables

A non-local `late` variable declaration _D_ implicitly induces a getter
into the enclosing scope.  It also induces an implicit setter iff one of the
following conditions is satisfied:

  - _D_ is non-final.
  - _D_ is late, final, and has no initializing expression.

The late final variable declaration with no initializer is permitted, and
introduces a variable which may be assigned to so long as the variable is not
known to be definitely assigned.  The property that the variable is never
mutated after initialization is enforced dynamically rather than statically.

An instance variable declaration may be declared `covariant` iff it introduces
an implicit setter.

A read of a field or variable which is marked as `late` which has not yet been
written to causes the initializer expression of the variable to be evaluated to
a value, assigned to the variable or field, and returned as the value of the
read.
  - If there is no initializer expression, the read causes a runtime error to be
    thrown.
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

Let _D_ be a `late` and `final` non-local variable declaration named `v`
without an initializing expression.  
It is a run-time error, to invoke the setter `v=` which is
implicitly induced by _D_ if a value has previously been assigned to `v`
(which could be due to an initializing formal or a constructor initializer
list, or due to an invocation of the setter).

Let _D_ be a `late` and `final` local variable declaration named `v`.  It is a
run-time error, to assign a value to `v` if a value has previously
been assigned to `v`.

Note that this includes the implicit initializing writes induced by
evaluating the initializer during a read.  Hence, the following program
terminates with an error.

```dart
int i = 0;
late final int x = i++ == 0 ? x + 1 : 0;
void main() {
  print(x);
}
```

A toplevel or static variable with an initializer is evaluated as if it
was marked `late`.  Note that this is a change from pre-NNBD semantics in that:
  - Throwing an exception during initializer evaluation no longer sets the
    variable to `null`
  - Reading the variable during initializer evaluation is no longer checked for,
    and does not cause an error.

### Boolean conditional evaluation.

The requirement that the condition in a boolean conditional control expression
(e.g. the a conditional statement, conditional element, `while` loop, etc) be
assignable to `bool` is unchanged from pre null-safe Dart.  The change in
assignability means that the static type of the condition may only be `dynamic`,
`Never`, or `bool`.  In full null-safe Dart, an expression of type `Never` will
always diverge and an expression of type `bool` will never evaluate to a value
other than `true` or `false`, and hence no conversion is required in these
cases.  A conditional expression of type `dynamic` may evaluated to any value,
and hence must be implicitly downcast to `bool`, after which no further check is
required.

During unsound null checking execution, values of type `Never` and `bool` may
evaluate to `null`, and so a boolean conversion check must be performed in
addition to any implicit downcasts implied.  The full semantics then are given
as follows.

Given a boolean conditional expression `e` where `e` has type `S`, it is a
static error if `S` is not assignable to `bool`.  Otherwise:

With sound null checking, evaluation proceeds as follows:
  - First `e` is implicitly cast to `bool` if required.
    - This cast may fail, and if so it is a TypeError.
  - If the cast does not fail, then the result is known to be a non-null
    boolean, and evaluation of the enclosing conditional proceeds as usual.

With unsound null checking, evaluation proceeds as follows:
  - First `e` is implicitly cast to `bool` if required (using
    `LEGACY_SUBTYPE(e.runtimeType, bool)`)
    - This cast may fail, and if so it is a TypeError.
  - If the cast does not fail, then the result may still be `null`, and so the
  result must be checked against `null`.
    - If the `null` check fails, it is an AssertionError, otherwise evaluation
      of the enclosing conditional proceeds as usual.


## Core library changes

Certain core libraries APIs will have a change in specified behavior only when
interacting with opted in code.  These changes are as follows.

Calling the `.length` setter on a `List` with element type `E` with an argument
greater than the current length of the list is a runtime error unless `Null <:
E`.

The `Iterator.current` getter is given an non-nullable return type, and is
changed such that the behavior if it is called before calling
`Iterator.moveNext` or after `Iterator.moveNext` has returned `false` is
unspecified and implementation defined.  In most core library implementations,
the implemented behavior will to return `null` if the element type is
`nullable`, and otherwise to throw an error.

### Legacy breaking changes

We will make a small set of minimally breaking changes to the core library APIs
that apply to legacy code as well.  These changes are as follows.

The `String.fromEnvironment` and `int.fromEnvironment` contructors have default
values for their optional parameters.

## Migration features

For migration, we support incremental adoption of non-nullability as described
at a high level in
the
[roadmap](https://github.com/dart-lang/language/blob/master/accepted/2.12/nnbd/roadmap.md).

### Opted in libraries.

Libraries and packages must opt into the feature as described elsewhere.  An
opted-in library may depend on un-opted-in libraries, and vice versa.

### Errors as warnings

An earlier version of this proposal specified that null safety related static
errors in opted-in code should be demoted to warnings when running with
unsound null checking.  This behavior has been eliminated based on early
feedback.  Null safety related errors in opted-in code behave as usual
independently of the compilation mode, subject to differences in const
evaluation and the usual suppression of errors when interacting with legacy
(opted-out) code (see below).

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
purposes of error messages that the type originates in legacy code.

When static checking is done in an opted-in library, types which are imported
from legacy libraries are seen as legacy types.  However, type inference in
the opted-in library "erases" legacy types.  That is, if a missing type
parameter, local variable type, or closure type is inferred to be a type `T`,
all occurrences of `S*` in `T` shall be replaced with `S`.  As a result, legacy
types will never appear as type annotations in opted-in libraries, nor will they
appear in reified positions.

### Typedefs defined in legacy libraries used in opted-in libraries

A typedef which is define in a legacy library and used in an opted-in library is
treated as defining a function type, all of the components of which are
legacy. The function type itself is treated as non-nullable (and not legacy) at
the top level.  Hence given the following program, it is an error to assign a
nullable value to a variable of type `F` in an opted-in library, but any
function which is compatible with a legacy function of type `int*
Function(int*)` may be assigned to such a variable.

```dart
// Opted-out library "opted_out.dart".
typedef F = int Function(int);

// Opted-in library "main.dart"
import "opted_out.dart";

int? f1(int x) => x;

void test() {
    F f = null; // Static error
    f = f1;  // No error
}
```

### Exports

If a legacy library re-exports an opted-in library, the re-exported symbols
retain their opted-in status (that is, downstream migrated libraries will see
their nnbd-aware types).

It is an error for an opted-in library to re-export symbols which are defined in
a legacy library (note that a symbol which is defined in an opted-in library and
then exported from a legacy library is accepted for re-export from a third
opted-in library since the symbol is not **defined** in the legacy library which
first exports it).

### Super-interface and member type computation with legacy types.

A class defined in a legacy library may have in its set of super-interfaces both
legacy and opted-in interfaces, and hence may have members which are derived
from either, or both.  Similarly, a class defined in an opted-in library may
have in its set of super-interfaces both legacy and opted-in interfaces, and
hence may have members which are derived from either, or both.  We define the
super-interface and member signature computation for such classes as follows.

#### Classes defined in legacy libraries

The legacy erasure of a type `T` denoted `LEGACY_ERASURE(T)` is `T` with all
occurrences of `?` removed, `Never` replaced with `Null`, `required` removed
from all parameters, and all types marked as legacy types.

A direct super-interface of a class defined in a legacy library (that is, an
interface which is listed in the `extends`, `implements` or `with` clauses of
the class) has all generic arguments (and all sub-components of the generic
arguments) marked as legacy types.

If a class `C` in a legacy library implements the same generic class `I` more
than once, it is an error if the `LEGACY_ERASURE` of all such super-interfaces
are not all syntactically equal.

When `C` implements `I` once, and also when `C` implements `I` more than once
without error, `C` is considered to implement the canonical signature given by
`LEGACY_ERASURE` of the super-interfaces in question. This determines the
outcome of dynamic instance checks applied to instances of `C`, as well as
static subtype checks on expressions of type `C`.

A member which is defined in a class in a legacy library (whether concrete or
abstract), is given a signature in which every type is a legacy type.  It is an
error if the signature of a member is not a correct override of all members of
the same name in the direct super-interfaces of the class, using the legacy
subtyping rules.

Using the legacy erasure for checking super-interfaces accounts for opted-out
classes which depend on both opted-in and opted-out versions of the same generic
interface. For example:

```dart
//opted in
class I<T> {}

// opted in
class A implements I<int?> {}

// opted out
class B implements I<int> {}

// opted out
class C extends A implements B {}
```

The class `C` is not considered erroneous, despite implementing both `I<int?>`
and `I<int*>`, since legacy erasure makes both of those interfaces equal.  The
interface which `C` is considered to implement is `I<int*>`.


#### Classes defined in legacy libraries as seen from opted-in libraries

Members inherited in a class in an opted-in library, which are inherited via a
class or mixin defined in a legacy library are viewed with their erased legacy
signature, even if they were original defined in an opted-in library.  Note that
if a class which is defined in a legacy library inherits a member with the same
name from multiple super-interfaces, then error checking is done as usual using
the legacy typing rules which ignore nullability.  This means that it is valid
for a legacy class to inherit the same member signature with contradictory
nullability information. For the purposes of member lookup within a legacy
library, nullability information is ignored, and so it is valid to simply erase
the nullability information within the legacy library. When referenced from an
opted-in library, the same erasure is performed, and the member is seen at its
legacy type.

We use legacy subtyping when checking inherited member signature coherence in
classes because opted out libraries may bring together otherwise incompatible
member signatures without causing an error.

```dart
// opted_in.dart
class A {
  int? foo(int? x) {}
}
class B {
  int foo(int x) {}
}
```
```dart
// opted_out.dart
// @dart = 2.6
import 'opted_in.dart';

class C extends A implements B {}
```

The class `C` is accepted, since the versions of `foo` inherited from `A` and
`B` are compatible.

If the class `C` is now used within an opted-in library, we must decide what
signature to ascribe to `foo`.  The `LEGACY_ERASURE` function computes a legacy
signature for `foo` which drops the nullability information producing a single
signature, in this case `int* Function(int*)`.  Consequently, the following code
is accepted:

```dart
//opted in
import 'opted_out.dart';
void test() {
  new C().foo(null).isEven;
}
```

#### Classes defined in opted-in libraries

The `NNBD_TOP_MERGE` of two types `T` and `S` is the unique type `R` defined
as:
 - `NNBD_TOP_MERGE(Object?, Object?)  = Object?`
 - `NNBD_TOP_MERGE(dynamic, dynamic)  = dynamic`
 - `NNBD_TOP_MERGE(void, void)  = void`
 - `NNBD_TOP_MERGE(Object?, void)  = Object?`
   - And the reverse
 - `NNBD_TOP_MERGE(dynamic, void)  = Object?`
   - And the reverse
 - `NNBD_TOP_MERGE(Object?, dynamic)  = Object?`
   - And the reverse
 - `NNBD_TOP_MERGE(Object*, void)  = Object?`
   - And the reverse
 - `NNBD_TOP_MERGE(Object*, dynamic)  = Object?`
   - And the reverse
 - `NNBD_TOP_MERGE(Never*, Null)  = Null`
   - And the reverse
 - `NNBD_TOP_MERGE(T?, S?) = NNBD_TOP_MERGE(T, S)?`
 - `NNBD_TOP_MERGE(T?, S*) = NNBD_TOP_MERGE(T, S)?`
 - `NNBD_TOP_MERGE(T*, S?) = NNBD_TOP_MERGE(T, S)?`
 - `NNBD_TOP_MERGE(T*, S*) = NNBD_TOP_MERGE(T, S)*`
 - `NNBD_TOP_MERGE(T*, S)  = NNBD_TOP_MERGE(T, S)`
 - `NNBD_TOP_MERGE(T, S*)  = NNBD_TOP_MERGE(T, S)`

 - And for all other types, recursively applying the transformation over the
   structure of the type
   - e.g. `NNBD_TOP_MERGE(C<T>, C<S>)  = C<NNBD_TOP_MERGE(T, S)>`

 - When computing the `NNBD_TOP_MERGE` of two method parameters at least one of
   which is marked as covariant, the following algorithm is used to compute the
   canonical parameter type.
   - Given two corresponding parameters of type `T1` and `T2` where at least
      one of the parameters has a `covariant` declaration:
     - if `T1 <: T2` and `T2 <: T1` then the result is `NNBD_TOP_MERGE(T1, T2)`,
     and it is covariant.
     - otherwise, if `T1 <: T2` then the result is `T2` and it is covariant
     - otherwise the result is `T1` and it is covariant

In other words, `NNBD_TOP_MERGE` takes two types which are structurally equal
except for the placement `*` types, and the particular choice of top types, and
finds a single canonical type to represent them by replacing `?` with `*` or
adding `*` as required.. The `NNBD_TOP_MERGE` of two types is not defined for
types which are not otherwise structurally equal.

The `NNBD_TOP_MERGE` of more than two types is defined by taking the
`NNBD_TOP_MERGE` of the first two, and then recursively taking the
`NNBD_TOP_MERGE` of the rest.

A direct super-interface of a class defined in an opted-in library (that is, an
interface which is listed in the `extends`, `implements` or `with` clauses of
the class) has all generic arguments (and all sub-components of the generic
arguments) marked as nullable or non-nullable as written.

If a class `C` in an opted-in library implements the same generic class `I` more
than once as `I0, .., In`, and at least one of the `Ii` is not syntactically
equal to the others, then it is an error if `NNBD_TOP_MERGE(S0, ..., Sn)` is not
defined where `Si` is **NORM(`Ii`)**.  Otherwise, `C` is considered to
implement the canonical interface given by `NNBD_TOP_MERGE(S0, ..., Sn)`.  This
determines the outcome of dynamic instance checks applied to instances of `C`,
as well as static subtype checks on expressions of type `C`.

If a class `C` in an opted-in library overrides a member, it is an error if its
signature is not a subtype of the types of all overriden members from all
direct super-interfaces (whether legacy or opted-in).  This implies that
override checks for a member `m` may succeed due to a legacy member signature
for `m` in a direct super-interface, even in the case where an indirect
super-interface has a member signature for `m` where the override would be a
compile-time error. For example:

```dart
// opted_in.dart
class A {
  int foo(int? x) {}
}
```
```dart
// opted_out.dart
// @dart = 2.6
import 'opted_in.dart';

class B extends A {}
```

```dart
// opted_in.dart
class C extends B {
  // Override checking is done against the legacy signature of B.foo.
  int? foo(int x) {}
}
```

It is difficult to predict the outcome of migrating `B` in such situations, but
lints or hints may be used by tools to communicate to developers that `C` may
need to be changed again when `B` is migrated.

If a class `C` in an opted-in library inherits a member `m` with the same name
from multiple direct super-interfaces (whether legacy or opted-in), let `T0,
..., Tn` be the signatures of the inherited members.  If there is exactly one
`Ti` such that `NNBD_SUBTYPE(Ti, Tk)` for all `k` in `0...n`, then the signature
of `m` is considered to be `Ti`.  If there are more than one such `Ti`, then it
is an error if the `NNBD_TOP_MERGE` of `S0, ..., Sn` does not exist, where `Si`
is **NORM(`Ti`)**.  Otherwise, the signature of `m` for the purposes of member
lookup is the `NNBD_TOP_MERGE` of the `Si`.

Note that when a member `m` is inherited from multiple indirect super-interfaces
**via** a single direct super-interface, override checking is only performed
against the signature of the direct super-interface which mediates the
inheritance as described above.  Hence the following example is not an error,
since the direct super-interface `C` of `D` mediates the conflicting inherited
signatures of `foo` as `C.foo` with signature `int* Function(int*)`.

```dart
// opted_in.dart
class A {
  int? foo(int? x) {}
}
class B {
  int foo(int x) {}
}
```
```dart
// opted_out.dart
// @dart = 2.6
import 'opted_in.dart';

class C extends A implements B {}

```
```dart
//opted in
import 'opted_out.dart';
class D extends C {}
void test() {
  new D().foo(null).isEven;
}
```

### Type reification

All types reified in legacy libraries are reified as legacy types.  Runtime
subtyping checks treat them according to the subtyping rules specified
separately.

### Runtime checks and unsound null checking

With unsound null checking, runtime type tests (including explicit and
implicit casts) shall succeed whenever the runtime type test would have
succeeded if all `?` on types were ignored, `*` was added to each type, and
`required` parameters were treated as optional.  This has the effect of treating
`Never` as equivalent to `Null`, restoring `Null` to the bottom of the type
hierarchy, treating `Object` as nullable, and ignoring `required` on named
parameters.  This is intended to provide the same subtyping results as pre-nnbd
Dart.

Instance checks (`e is T`) and casts (`e as T`) behave differently when run
with sound vs unsound null checking.


We define the instance tests with unsound null checking and sound null
checking as follows:

**With unsound null checking**: if `e` evaluates to a value `v` and `v` has runtime
type `S`, an instance check `e is T` occurring in a **legacy library** or an
**opted-in library** is evaluated as follows:
  - If `v` is `null` and `T` is a legacy type, return `LEGACY_SUBTYPE(T, Null)
    || LEGACY_SUBTYPE(Object, T)`
  - If `v` is `null` and `T` is not a legacy type, return `NNBD_SUBTYPE(Null,
    T)`
  - Otherwise return `LEGACY_SUBTYPE(S, T)`

A type is a legacy type if it is of the form `R*` for some `R` after normalizing
away nested nullability annotations - e.g. `int*` is a legacy type, but `int?*`
is not, since the normal form of the latter is `int?`.

Note that except in the case that `T` is of the form `X` or `X*` for some type
variable `X`, it is statically decidable which of the first two clauses apply in
the case that `v` is `null`.

**With sound null checking**: if `e` evaluates to a value `v` and `v` has
runtime type `S`, an instance check `e is T` occurring in an **opted-in
library** is evaluated as follows:
  - Return `NNBD_SUBTYPE(S, T)`

Note that it is an error to run a program containing legacy libraries with
sound null checking.

Note that given the definitions above, the result of an instance check may vary
depending on whether it is run with sound or unsound null checking.  However,
in the specific case that the value being checked is `null`, instance checks
will always return the same result regardless of mode, and regardless of
whether the check occurs in an opted in or opted out library.

| T            | Any mode |
| -------- | ------------- |
| Never     |  false               |
| Never*     |  true               |
| Never?     |  true               |
| Null         | true                |
| int           | false               |
| int*         | false                |
| int?         | true                |
| Object    | false                 |
| Object*  | true                 |
| Object?  | true                 |
| dynamic | true                 |


We define casts with unsound null checking and sound null checking as follows:

**With unsound null checking**: if `e` evaluates to a value `v` and `v` has
runtime type `S`, a cast `e as T` **whether textually occurring in a legacy or
opted-in library** is evaluated as follows:
  - if `LEGACY_SUBTYPE(S, T)` then `e as T` evaluates to `v`.  Otherwise a
    dynamic type error occurs.

**With sound null checking**: if `e` evaluates to a value `v` and `v` has
runtime type `S`, a cast `e as T` **whether textually occurring in a legacy or
opted-in library** is evaluated as follows:
  - if `NNBD_SUBTYPE(S, T)` then `e as T` evaluates to `v`.  Otherwise a
    dynamic type error occurs.

With unsound null checking, we ensure that opted-in libraries do not break
downstream clients by continuing to evaluate instance checks and casts with
the same semantics as in pre-nnbd Dart.  All runtime subtype checks are done
using the legacy subtyping, and instance checks maintain the pre-nnbd behavior
on `null` instances.  With sound null checking, we use the specified nnbd
subtyping for all instance checks and casts.

When developers enable sound null checking in their tests and applications, new
runtime cast failures may arise.  The process of migrating libraries and
applications will require users to track down these changes in behavior.
Development platforms are encouraged to provide facilities to help users
understand these changes: for example, by providing a debugging option in which
instance checks or casts which would result in a different outcome if run with
sound null checking vs unsound null checking are flagged for the developer by
logging a warning or breaking to the debugger.

### Automatic debug assertion insertion

When running with unsound null checking, implementations may insert code
equivalent to `assert(x != null)` in the prelude of every method or function
defined in an opted-in library for each parameter `x` which has a non-nullable
type.  When compiling a program with sound null checking, these assertions will
never fire and should be elided, but during the migration when mixed mode code
is being executed it is possible for opted-out libraries to cause the
invariants of the null safety checking to be violated.
