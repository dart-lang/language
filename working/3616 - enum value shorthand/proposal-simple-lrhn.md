# Dart static access shorthand

Author: lrn@google.com<br>Version: 1.1

You can write `.foo` instead of `ContextType.foo` when it makes sense. The rules
are fairly simple and easy to explain.

### Elevator pitch

An expression starting with `.` is an implicit static namespace access on the
*apparent context type*.

Since the type that the context expects is known, the shorthand expression
avoids repeating the type, and starts by doing a static access on that type.

This makes immediate sense for accessing enum and enum-like constants or
invoking constructors, which will have the desired type. There is no requirement
that the expression ends at that member access or invocation, it can be followed
by non-assignment selectors, and the result just has to have the correct type in
the end. The context type used is the one for the entire selector chain.

There must be a context type that allows static member access, similar to when
we allow static access through a type alias.

We also special-case the `==` and `!=` operators, but nothing else.

## Specification

### Grammar

We introduce grammar productions of the form:

```ebnf
<primary> ::= ...                      -- all current productions
    | <staticMemberShorthand>

<constantPattern> ::=  ...             -- all current productions
    | <staticMemberShorthand>

<staticMemberShorthand> ::=
      '.' (<identifier> | 'new')                      -- shorthand qualified name
    | 'const' '.' (<identifier> | 'new') <arguments>  -- shorthand object creation
```

We also add `.` to the tokens that an expression statement cannot start with.

That means you can write things like the following (with the intended meaning as
comments, specification to achieve that below):

```dart
Endian littleEndian = .little; // -> Endian.little (enum value)
Endian hostEndian = .host; // -> Endian.host (getter)
// -> Endian.little, Endian.big, Endian.host
Endian endian = firstWord == 0xFEFF ? .little : firstWord = 0xFFFE ? .big : .host;

BigInt b0 = .zero; // -> BigInt.zero (getter)
BigInt b1 = b0 + .one; // -> BigInt.one (getter)

String s = .fromCharCode(42); // -> String.fromCharCode(42) (constructor)

List<Endian> l = .filled(10, .big); // -> List<Endian>.filled(10, Endian.big)

int value = .parse(input); // -> int.parse(input) (static function)

Zone zone = .current.errorZone; /// -> Zone.current.errorZone
int posNum = .parse(userInput).abs(); // -> int.parse(userInput).abs()

// -> Future.wait<int>([Future<int>.value(1), Future<int>.value(2)])
// (static function and constructors)
Future<List<int>> futures = .wait([.value(1), .value(2)]);
// -> Future.wait<int>([Future<int>.value(1), Future<int>.value(2)])
// (static function and constructors)
Future futures = .wait<int>([.value(1), .value(2)]);

// -> Future<List<String>>.wait([lazyString(), lazyString()]).then<String>((list) => list.join())
Future<String> = .wait([lazyString(), lazyString()]).then((list) => list.join());
```

This is a simple grammatical change. It allows new constructs in any place where
we currently allow primary expressions, which can be followed by selector chains
through the `<postfixExpression>` production `<primary> <selector>*`.

#### Non-ambiguity

A `<primary>` cannot immediately follow any other complete expression. We trust
that because a primary expression already contains the production
`'(' <expression> ')'` which would cause an ambiguity for `e1(e2)` since `(e2)`
can also be parsed as a `<primary>`. The existing places where a `.` token
occurs in the grammar are all in positions where they follow another expression
(or qualified identifier), which a primary expression cannot follow.

The `.` token is already a continuation token in the disambiguation rules
introduced with the constructor-tear-off feature, which also introduced a single
type arguments clause as a selector. That means that `A<B, C>.id` will always
parse `.id` as a selector in that context, and not allow a primary to follow. No
new rules are needed.

Therefore the new productions introduces no new grammatical ambiguities.

We prevent expression statements from starting with `.` mainly out of caution.
_(It’s very unlikely that an expression statement starting with static member
shorthand can compile at all. If we ever allow metadata on statements, we don’t
want `@foo . bar(4) ;` to be ambiguous. If we ever allow metadata on
expressions, we have bigger issues.)_

A primary expression *can* follow a `?` in a conditional expression, as in
`{e1 ? . id : e2}`. This is not ambiguous with `e1?.id` since we parse `?.` as a
single token, and will keep doing so. It does mean that `{e1?.id:e2}` and
`{e1? .id:e2}` will now both be valid and have different meanings, where the
existing grammar didn’t allow the `?` token to be followed by `.` anywhere.

### Semantics

Dart semantics, static and dynamic, do not follow the grammar precisely. For
example, a static member invocation expression of the form `C.id<T1>(e2)` is
treated as an atomic entity for type inference (and runtime semantics). It’s not
a combination of doing a `C.id` tear-off, then a `<T1>` instantiation and then
an `(e2)` invocation. The context type of that entire expression is used
throughout the inference, where `(e1.id<T1>)(e2)` has `(e1.id<T1>)` in a
position where it has *no* context type. _(For now, come selector based
inference, it may have something, but a selector context is not a type context,
and it won’t be the context type of the entire expression)._

Because of that, the specification of the static and runtime semantics of the
new constructs needs to address all the forms <code>.*id*</code>,
<code>.*id*\<*typeArgs*\></code>, <code>.*id*(*args*)</code>,
<code>.*id*\<*typeArgs*\>(*args*)</code>, `.new` or <code>.new(*args*)</code>.

_(The proposal also addresses `.new<typeArgs>` and `.new<typeArgs>(args)`, but
those will always be compile-time errors because `.new` denotes a constructor
which is not generic. We do not want this to be treated as
`(.new)<typeArgs>(args)` which creates and calls a generic tear-off of the
constructor.)_

The *general rule* is that any of the expression forms above, starting with
<code>.id</code>, are treated exactly *as if* they were prefixed by a fresh
identifier <code>*X*</code> which denotes an accessible type alias for the
greatest closure of the context type scheme of the following primary and
selector chain.

#### Type inference

First, when inferring types for a `<postfixExpression>` of the form
`<staticMemberShorthand> <selector>*` with context type scheme *C*, then, if the
`<staticMemberShorthand>` has not yet been assigned a *shorthand context*,
assign *C* as its shorthand context. Then continue as normal. _This assigns the
context type scheme of the entire, maximal selector chain to the static member
shorthand, and does not change that when recursing on shorter prefixes._

_The effect will be that `.id…` will behave exactly like `T.id…` where `T`
denotes the declaration of the context type._

**Definition:** If a shorthand context type schema has the form `C` or `C<...>`,
and `C` is a type introduced by the type declaration *D*, then the shorthand
context *denotes the type declaration* *D*. If a shorthand context `S` denotes a
type declaration *D*, then so does a shorthand context `S?`. Otherwise, a
shorthand context does not denote any declaration.

_This effectively derives a *declaration* from the context type scheme of the
surrounding `<postfixExpression>`. It allows a nullable context type to denote
the same as its non-`Null` type, so that you can use a static member shorthand
as an argument for optional parameters, or in other contexts where we change a
type to nullable just to allow omitting things ._

**Constant shorthand**: When inferring types for a `const .id(arguments)` or
`const .new(arguments)` with context type schema *C*, let *D* be the declaration
denoted by the shorthand context assigned to the `<staticMemberShorthand>`. Then
proceed with type inference as if `.id`/`.new` was preceded by an identifier
denoting the declaration *D*. It’s a compile-time error if the shorthand context
does not denote a class, mixin, enum or extension type declaration.

**Non-constant shorthand**: When inferring types for constructs containing the
non-`const` production, in every place where the current specification specifies
type inference for one of the forms <Code>*T*.*id*</code>,
<code>*T*.*id*\<*typeArgs*\></code>, <code>*T*.*id*(*args*)</code>,
<code>*T*.*id*\<*typeArgs*\>(*args*)</code>, <code>*T*.new</code>,
<code>*T*.new(*args*)</code>, <code>*T*.new\<*typeArgs*\></code> or
<code>*T*.new\<*typeArgs*\></code>, where *T* is a type literal, we introduce a
parallel “or <code>.id…</code>” clause for a similarly shaped
`<staticMemberShorthand>`, proceeding as if `.id`/`.new` was preceded by an
identifier denoting the declaration that is denoted by the shorthand context
assigned to the leading `<staticMemberShorthand>`. It’s a compile-time error if
the shorthand context does not denote a class, mixin, enum or extension type
declaration.

Expression forms `.new<typeArgs>` or `.new<typeArgs>(args)` will always be
compile-time errors. (The grammar allows them, because it allows any selector to
follow a static member shorthand, but that static member shorthand must denote a
constructor invocation, and constructors cannot, currently, be generic.)

**Notice**: The invocation of a constructor is *not* using an instantiated type,
it’s behaving as if the constructor was preceded by a *raw type*, which type
inference should then infer type arguments for.
Doing `List<int> l = .filled(10, 10);` works like doing
`List<int> l = List.filled(10, 10);`, and it is the following downwards
inference with context type `List<int>` that makes it into
`List<int>.filled(10, 10);`. This distinction matters for something like:

```dart
List<String> l = .generate(10, (int i) => i + 1).map((x) => x.toRadixString(16)).toList();
```

which is equivalent to inserting `List` in front of `.generate`, which will then
be inferred as `List<int>`. In most normal use cases it doesn’t matter, because
the context type will fill in the missing type variables, but if the
construction is followed by more selectors, it loses that context type. _It also
means that the meaning of `.id`/`.new` is *always* the same, it doesn’t matter
whether it’s a constructor or a static member, it’s always preceded by the name
of the declaration denoted by the context.

The following uses are *not* allowed because they have no shorthand context that
denotes an allowed type declaration:

```dart
// NOT ALLOWED, ALL `.id`S ARE ERRORS!
int v1 = .parse("42") + 1; // Context `_`.
int v2 = (.parse("42")).abs(); // Context `_`.
dynamic v3 = .parse("42"); // Context `_`.
FutureOr<int> = .parse("42"); // Context `FutureOr<int>` is structural type.
```

#### Special case for `==`

For `==`, we special-case when the right operand is a static member shorthand.

If an expression has the form `e1 == e2` or `e1 != e2`, or a pattern has the
form `== e2`, where the static type of `e1` is *S1* and the function signature
of `operator ==` of `S1` is <code>*R* Function(*T*)</code>, *then* before doing
type inference of `e2` as part of that expression or pattern:

*   If `e2` has the form `<staticMemberShorthand> <selector>*` and
    <code>*T*</code> is a supertype of `Object`,

*   Then assign *T* as the shorthand context of `e2`.

_If the parameter type of the `==` operator of the type of `e1` is,
unexpectedly, a proper subtype of `Object` (so it's declared `covariant`), it's
assumed that that is the kind of object it should be compared to. Otherwise we
assume the right-hand side should have the same type as the left-hand side, most
likely an enum value._

This special-casing is only against an immediate static member shorthand.
It does not change the *context type* of the second operand, so it would not
work with, for example, `Endian.host == wantBig ? .big : .little`.
Here the second operand is not a `<staticMemberShorthand> <selector>*`,
so it won't have a shorthand context set, and the parameter type of
`Endian.operator==` is `Object`, so that is the context type of the
second operand.

Examples of allowed comparisons:

```dart
if (Endian.host == .big) ok!;
if (Endian.host case == .big) ok!;
```

Not allowed:

```dart
// NOT ALLOWED, ALL `.id`S ARE ERRORS
if (.host == Endian.host) notOk!; // Dart `==` is not symmetric.
if (Endian.host == preferLittle ? .little : .big) notOk!; // RHS not shorthand.
if ((Endian.host as Object) == .little) notOk!; // Context type `Object`.
```
_We could consider generally changing the context type of the second operand to
the static type of the LHS, an aspirational context type, if the parameter type
is not useful._

#### Runtime semantics

In every place in type inference where we used the assigned shorthand context to
decide which static namespace to look in, we remember the result of that lookup,
and at runtime we invoke that static member. _Like we may infer type arguments
to constructors, and use those as runtime type arguments to the class, we infer
the entire target of the member access and use that at runtime._

In every case where we inserted a type inference clause, we resolved the
reference to a static member in order to use its type for static type inference.
The runtime semantics then say that it invokes the member found before, and it
works for the `.id…` variant too.

#### Patterns

A *constant pattern* is treated the same as any other constant expression,
with the matched value type used as the context type schema
that is assigned as shorthand context. Since a constant pattern cannot occur
in a declaration pattern, there is no need to assign an initial type scheme
to the pattern in the first phase of the three-step inference.
_If there were, the type scheme would be `_`._

Example:

```dart
switch (Endian.host) {
  case .big: // Matched value type = Context type is `Endian` -> `Endian.big`.
  case .little: // => `Endian.little`
}
```

#### Constant expressions

The form starting with `const` is inferred in the same way, and then the
identifier *must* denote a constant constructor, and the expression is then a
constant constructor invocation of that constructor, which is a constant
expression.

An expression in a `const` context is inferred as normal, then it’s a
compile-time error if it is not a constant expression, which it is if is a
constant getter or constant constructor invocation. _(There is no chance of a
method or constructor tear-off having the correct type for the context, but if
the context type is not enforced for some reason, like being lost in an **Up**
computation, it’s technically possible to tear off a static method as a constant
expression. It’s unlikely to succeed dynamic type tests at runtime.)_

An expression without a leading `const` is a potential constant and constant
expression if the corresponding explicit static access would be one. Being a
potentially constant expression only really works for static constant getters.
A method or constructor tear-off won’t have the context type, a non-`const`
constructor invocation or method invocation is not potentially constant.

```dart
Symbol symbol = const .new("orange"); // => const Symbol.new("Orange")
Endian endian = .big; // => Endian.big.
```

## New complications and concerns

### Delayed resolution

The `.id` access is a static member access which cannot be resolved
before type inference.

Prior to this feature, static member accesses could always be resolved using
only the lexical scopes and declaration namespaces, which does not require type
inference.

Similarly, it’s not known whether `.id` is a valid potentially constant or
constant expression until it’s resolved what it refers to. This may delay some
errors until after type inference that could previously be given earlier.

It’s not clear that this causes any problems, but it may need implementations to
adapt, if they assumed that all static member accesses could be known (and the
rest tree-shaken eagerly) before type inference. With this feature, static
member access, like instance member access, may need types to decide which
static declarations are possible targets.

### Declaration kinds

The restriction “It’s a compile-time error if the shorthand context does not
denote a class, mixin, enum or extension type declaration” makes it a visible
property of a declaration whether it is one of these.

Prior to this feature, there are types where it’s *unspecified* whether they are
introduced by class declarations or not. These are all types that you cannot
extend, implement or mix in, so there is nothing you can *use* them for that
would be enabled or prevented by being or not being, for example, a class.

This may require the language to *specify* which platform types are considered
introduced by which kind of declaration, because it now matters.
Or we can do nothing, and pretend there is no issue.
Structural types (nullable, `FutureOr`, function types), `dynamic`, `void` and
`Never` do not have any static members, so it doesn’t matter whether you allow
a static member shorthand access on them, it’ll just fail to find anything.

Basically, we need a term for “a type (schema) which denotes a static
namespace”. That is what the shorthand context type schema must do.

## Possible variations and future features

### Static extensions

If/when we add static extensions to the language, they should work with static
member shorthands. After we have decided which namespace to look in, based on
the shorthand context, everything should work exactly as if that namespace had
been written explicitly, including static extension member access.

This should “just work”, and having static extensions would significantly
increase the value of this feature, by allowing users to introduce their own
shorthands for any interface type.

#### Nullable types and `Null`

##### Why allow nullable types to begin with

It is a conspicuous special-casing to allow `int?` to denote a static namespace,
but it’s special casing of a type that we otherwise special-case all the time.

It allows `int? v = .tryParse(42);` to work. That’s a *pretty good reason*.
It also allows `int x = .tryParse(input) ?? 0;` to work, which it
wouldn’t otherwise because the context type of `.tryParse(input)` is `int?`.

We generally treat the nullable and non-nullable type as closely related (if one
is a type of interest, so is the other), and we treat `T?` as meaning “optional
`T`”. It makes good sense to supply a `T` where an optional `T` is expected.

If we didn’t allow it, it would make a difference whether you declare your
method as:

```dart
void foo([Foo? foo]) { foo ??= const Foo(null); ... }
```
or
```dart
void foo([Foo foo = const Foo(null)]) { ... }
```

which are both completely valid ways to write essentially the same function. The
latter can be called as `foo(.someFoo)` and the former cannot, but the former
can be called with `null`, which is why you might want it. This way, you can use
the latter and allow both `null` and `.someFoo` as arguments.

##### Statics on `Null`

The type `int?` is a union type, but we only allow members on `int`. Should we
*also* allow static members on `Null`, checking both to see which one has a
member of the given base name, and then resolve to that? (And a compile-time
error in case both has one.)

*Currently* it makes no difference because `Null` has no static members. If/when
we introduce static extensions, that may change.

We should consider, no later than at that time, whether a nullable type should
allow access to members of `Null`.

It’s *probably safe* to do so, and it means that the **Norm**-equivalent
`Never?` and `Null` have the same members (since `Never` doesn’t have any).
_We do *not* want to **Norm**-canonicalize types before doing member lookup.
We generally do not normalize static types, and it may change the meaning
for *some* `FutureOr<...>` types and not for others. If anything, I'd rather
special-case `Never?` to mean `Null`, which our tools will likely do eagerly
anyway._

It’s also unlikely that there will be many methods on `Null`, but allowing
accessing statics on `Null` for nullable types allows things like:

```dart
static extension on Null {
  static T? maybe<T extends Object>(bool test, T value) => test ? value : null;
}
  //...
  String? v = .maybe(someTest, "Bananas");
```

Putting extensions on `Null` makes them shorthands on *every nullable type*.
That might be a little more power than we are intending this feature to have.
Or it might be marvelous.

We *can* choose to only let nullable types provide their non-`Null` statics as
shorthands. That’s the *intent*, to provide an optional value, not as a way to
act on optionality itself.

(For now, it doesn’t matter, so we won't consider members from `Null`.)

#### Asynchrony and other element types

The nullable type is a union type. So is `FutureOr<Foo>`.

Should we allow a context type of `FutureOr<Foo>` to access static members on
`Foo`?

If we allow the nullable context to access static members on `Null`, should we
allow `FutureOr` to access static members of `Future`?

It’d be useful. Until [#870](https://dartbug.com/language/870) gets done, the
context type of a return expression in an `async` function is `FutureOr<F>`
where `F` is the future-value-type of the function. If we don’t allow static
access to `Foo` members, then changing `Foo foo() => .value;` to
`Future<Foo> foo() async => .value;` will not work. That’s definitely going to
be a surprise to users, and it’s a usability cliff. And telling them to do
`Foo result = .value; return result;` instead of `return .value;` goes against
everything we have so far tried to teach. (Or get \#870 fixed).

Same applies to `Future<SomeEnum> f = Future.value(.someValue);` where
`Future.value` which also takes `FutureOr<SomeEnum>` as argument. That would be
an argument for having a *real* `Future.valueOnly(T value) : …`, and it’s too
bad the good name is taken. _(And so is `Future(…)` for a variant that is almost
never used.)_

If we say that a type is the authority on creating instances of itself, which is
why we want to allow calling constructors, it *might* also be an authority on
creating those instances *asynchronously*. With a context type of `Future<Foo>`,
should we check the `Foo` declaration for a `Future<Foo>`-returning function, or
just the `Future` class? If do we check `Foo`, we should probably check be both.

If we allow a static member of `Foo` to be accessed on `FutureOr<Foo>`, and to
return a `Future<Foo>`, but do not allow that with a context type of
`Future<Foo>`, it punishes people for being specific. It would *encourage* using
`FutureOr<Foo>` as type instead of `Future<Foo>`, to make the API more user
friendly. So, if we allow shorthand `Foo` member access on `FutureOr<Foo>`, we
*may* want to allow it on `Future<Foo>` too. (But not on more specialized
subtype of `Future<Foo>`, like `class MyFuture<T> implements Future<T> …`.)

This gets even further away from being simple, and it special cases the `Future`
type, which isn’t *that* special as a type. (It’s not a union type. It is very
special *semantically*, an asynchronous function is a completely different kind
of function than a synchronous one, and `Future<Foo>` is really a way of saying
“`Foo`, but later”. But the type is just another type.)

If we don’t consider `Future` to be special in the language, and we allow
shorthand access to `Foo` members on `Future<Foo>`, any argument for that can
also be used for allowing `Foo` member access on it on `List<Foo>`. For enums,
that’s even useful: `List<SomeEnum> values = .values`.

It’s probably a “no” (bordering on “heck no!”) to `Future<Foo>` and therefore
probably to `FutureOr<Foo>` too. But it is annoying because of the implicit
`FutureOr` context types. (Maybe we can special case `.foo` in returns of
`async` functions only, or change the *context type* of the return to `F`,
while still allowing a `FutureOr<F>` to be returned, as an aspirational
context type.)

## Versions

1.1: Makes `==` only special-case second operand.
*   Keeps context type for second operand, set its shorthand context instead.
*   Remember to mention `== e` pattern.
*   Clean-up and reflow.

1.0: Switches to alternative version, where context type applies to selector
chain.
*   Changes semantics to insert a non-instantiated type as the namespace
    reference. Means `.foo` is always equivalent to `SomeType.foo`, whether it’s
    a constructor or not. Inference will apply constructor type arguments. If
    you write `SomeType<X> v = .id…;` it means `SomeType<X> v = SomeType.id…;`,
    every time.
*   Allows `Foo` static member access on a `Foo?` context type.
    It’s too convenient to ignore.

0.3: More details on type inference and examples.

0.2: Updated with more examples and more arguments (in both directions) in the
union type sections.

0.1: First version, for initial comments.
