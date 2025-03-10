# Dart static access shorthand

Author: lrn@google.com<br>Version: 1.4 (2025-01-08)

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
<postfixExpression> ::= ...            -- all current productions
    | <staticMemberShorthand>          -- added production

<constantPattern> ::=  ...             -- all current productions
    | <staticMemberShorthandValue>     -- No selectors, no `.new`.

<staticMemberShorthand> ::= <staticMemberShorthandHead> <selector>*

<staticMemberShorthandHead> ::=
      <staticMemberShorthandValue>
    | '.' 'new'                                       -- shorthand unnamed constructor

<staticMemberShorthandValue> ::=                      -- something that can potentially create a value.
    | '.' <identifier>                                -- shorthand for qualified name
    | 'const' '.' (<identifier> | 'new') <arguments>  -- shorthand for constant object creation
```

We also add `.` to the tokens that an expression statement cannot start with. This doesn't
affect starting with a double literal like `.42`, since that's a different token than a single `.`.
_(Not sure this is *necessary*, but it will possibly make parser recovery easier/
So mainly disallow this as an abundance of caution.)_

That means you can write things like the following (with the intended meaning as 
comments, specification to achieve that below):

```dart
// -> HttpClientResponseCompressionState.compressed (enum value)
HttpClientResponseCompressionState state = .compressed;

Endian littleEndian = .little; // -> Endian.little (static constant)
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
Future<String> futures = .wait([lazyString(), lazyString()]).then((list) => list.join());
```

This is a simple grammatical change. It allows new constructs in any place where
we currently allow primary expressions followed by selector chains
through the `<postfixExpression>` production `<primary> <selector>*`,
and now also `<staticMemberShorthandHead> <selector>*`.

The new grammar is added as a separate production, rather than making
 `<staticMemberShorthandHead>` a `<primary>`, and sharing the `<selector>*`
between all `<primary>`s, because the context type of the entire
 `<staticMemberShorthand>` is relevant and will be captured when processing
that production.

#### Non-ambiguity

A `<postfixExpression>` cannot immediately follow any other complete expression.
We trust that because a primary expression already contains the production
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
_(It's an unlikely expression that can start with a static member, it requires something
that adds a context type on the left, `.parse(userInput) || (throw "Not true!")`
or similar, which isn't particularly *useful*._
_If we ever allow metadata on statements, we don’t want `@foo . bar(4);`
to be ambiguous. If we ever allow metadata on expressions, we have bigger issues.)_

A postfix expression expression *can* follow a `?` in a conditional expression, as in
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
<code>.id</code>, are treated exactly *as if* they were preceded by a fresh
prefixed identifier <code>*_p.C*</code> which denotes the declaration of the type of the
context type scheme of the entire `<staticMemberShorthand>`.

#### Type inference

First, when inferring types for a `<postfixExpression>` of the form
`<staticMemberShorthand>` with context type scheme *C*, then assign *C* as
the shorthand context of the leading `<staticMemberShorthandHead>`.
Then continue inferring a type for the entire `<staticMemberShorthand>`
recursively on the chain of selectors of the `<selector>*`,
in the same way as for a `<primary> <selector>*`. _This assigns the
context type scheme of the entire, maximal selector chain to the static member
shorthand head, moving it past any intermediate `<selector>`s._

_The intended effect will be that `.id…` will behave exactly like `T.id…` where `T`
is an identifier (or qualified identifier) which denotes the declaration of the
context type._

A context type scheme is a semantic type (plus `_`). That means that it will
not refer to any type aliases that may have been used to denote that type
in the source code. Type aliases are expanded no later than when a type *term*
of the source program is interpreted to find the type or type scheme that
it denotes.

**Definition: Declaration denoted by a type scheme** 
A context type scheme is said to _denote a declaration_ in some cases.
Not all context type schemes denote a declaration.

If a type scheme *S*:
* has the form `C` or `C<typeArgs>` where `C` is a type introduced by a
  declaration *D* _which must therefore be a type-introducing declaration,
  which currently means a `class`, `mixin`, `enum` or `extension type` declaration_,
  then *S* denotes the declaration *D*.
* has the form `S?` or `FutureOr<S>`, and the type scheme `S` denotes
  a declaration *D*, then so does `S?`/`FutureOr<S>`.
  _Only the "base type" of the union type is considered, ensuring that
  a type scheme denotes at most one declaration or static namespace._
* has *any other* form, including type variables, promoted type variables and `_`,
  then the type scheme does not denote any declaration or namespace.

_Platform library declared types can be exempt from rules that apply to user
declarations. For example, the `Object` and `Null` classes appear to be `class`
declarations in the library source code, but their types do not have a superclass,
which any user-written `class` declaration must have.
That makes it unclear/under-specified whether these types are actually `class`
declarations, or if they merely count as such in some ways, and if so,
what they really are._
_Rather than try to answer that question here, this specification will just
ensure that any platform type that currently allow accessing static members
as `TypeName.id` will also work with static member shorthands. And rather
than enumerating the declarations that are special, yet class-like, it instead
enumerates the types that do not denote a declaration with a static scope:_
Any named type exported by the platform libraries, which is not `dynamic`, `void`,
`Never`, a record type, a function type or a union type (of the form `T?` or
`FutureOr<T>`), is _considered as being introduced by a type declaration_,
which static members can be looked up in, independently of how it's represented
in the public platform library source code.
_For example, the `Function` type has a declaration with a static function
declaration, and should be treated as having that declaration,
and the same for `Null` which has no static members at all,
whereas `FutureOr` is (currently) represented in the source code by a `class`
declaration mainly as a way to carry documentation, and does not actually have
a declaration, or any scope for static members._

With this definition, the semantics of a `<staticMemberShorthand>` can derive
a single declaration, with possible static declarations, from its 
context type scheme.
A nullable context type denotes the same as its non-`Null` type,
so that you can use a static member shorthand as an argument for optional parameters,
or in other contexts where we change a type to nullable just to allow omitting things,
and a `FutureOr<T>` denotes the same declarations as `T`
_mainly to allow static shorthands in return statements of `async` functions_.

**Constant shorthand**: When inferring types for a `const .id(arguments)` or
`const .new(arguments)` with context type scheme *C*, let *D* be the declaration
denoted by the _shorthand context_ assigned to the `<staticMemberShorthand>`,
which may differ from *C*. Then proceed with type inference in the same way as
if `.id`/`.new` was preceded by an identifier `D` denoting the declaration *D*.
It’s a compile-time error if the shorthand context does not denote a declaration.
It's a compile-time error if a static member lookup with base name `id`/`new` on
this declaration does not find a constant constructor.
_If the shorthand is preceded by `const`, it must be a constant constructor invocation._

**Non-constant shorthand**: When inferring types for constructs containing the
non-`const` production, in every place where the current specification specifies
type inference for one of the forms <Code>*T*.*id*</code>,
<code>*T*.*id*\<*typeArgs*\></code>, <code>*T*.*id*(*args*)</code>,
<code>*T*.*id*\<*typeArgs*\>(*args*)</code>, <code>*T*.new</code>, or
<code>*T*.new(*args*)</code>, where *T* is a type literal, we introduce a
parallel “or <code>.id…</code>” clause for a similarly shaped
`<staticMemberShorthand>`, proceeding to look up `id`/unnamed constructor in
the class denoted by the shorthand context assigned to the leading 
`<staticMemberShorthandHead`>, just as we would have if `.id`/`.new` was preceded by
an identifier (or qualified identifier) denoting that declaration.
It's a compile-time error if the shorthand context does not denote a declaration
and static namespace.
It's a compile-time error if a static member lookup with base name `id`/`new`
on that declaration does not find a static member. 
It's a compile-time error if that declaration does not have a static member
with base name `id`, or an unnamed constructor for `.new`.
Otherwise the `.id`/`.new` is treated as denoting that member and works just like
a `T.id`/`T.new` would when `T` denotes the type declaration.
_(If/when Dart gets a static extensions feature, the declaration found by static
member lookup on a type declaration need not be a declaration of that type declaration
itself, it could be a static extension declaration.)_

_If no selectors were recursed past getting to this point, or only `!` selectors, then
this expression may have an actual context type. If it was followed by "real" selectors,
like `.parse(input).abs()`, then the recognized expression, `.parse(input)`
in this example, likely has no context type._

Expressions of the forms <code>.new\<*typeArgs*\></code> or 
<code>.new\<*typeArgs*\>(*args*)</code> (as a prefix of a `<staticMemberShorthand> <selector>*`
production, or the entire chain) are compile-time errors, just like
the corresponding <code>*T*.new\<*typeArgs*\></code>
and <code>*T*.new\<*typeArgs*\>(*args*)</code> already are, whether used as
instantiated tear-off or invoked.
_(The grammar allows them, because `C.new` is a `<primary>` expression, but
a `C.new`, or a `C.id` denoting a constructor, followed by type arguments is 
recognized and made an error to avoid it being interpreted as `(C.new)<int>`.)_

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
whether it’s a constructor or a static member, it’s always implicitly preceded by
the raw name of the declaration denoted by the context, and any instantiation
in the context is ignored._

The following uses are *not* allowed because they have no shorthand context that
denotes an allowed type declaration:

```dart
// NOT ALLOWED, ALL `.id`S ARE ERRORS!
int v1 = .parse("42") + 1; // Context `_`.
int v2 = (.parse("42")).abs(); // Context `_`.
dynamic v3 = .parse("42"); // Context `_`.
```

Since `!` does propagate a context, `int x = (.tryParse(input))!;` does work,
with a context type scheme of `int?`, which is enough to allow `.tryParse`.
Same for `int x = .tryParse(input) ?? 0;` which gives the first operand
the context type `int?`.

#### Special case for `==`

For `==`, we special-case when the right operand is (precisely!) a static 
member shorthand.

If an expression has the form `e1 == e2` or `e1 != e2`, or a pattern has the
form `== e2` or `!= e2`, where the static type of `e1`, or the matched value type of the
pattern, is *S1*, and *e2* is precisely a `<staticMemberShorthand>` expression,
then assign the type *S1* as the shorthand context of the `<staticMemberShorthandHead>`
of *e2* before inferring its static type the same way as above.

This special-casing is only against an immediate static member shorthand.
It does not change the *context type* of the second operand, so it would not
work with, for example, `Endian.host == wantBig ? .big : .little`.
Here the second operand is not a `<staticMemberShorthand>`,
so it won't have a shorthand context set, and the context type of the
second operand of `==` is the empty context `_`. (It's neither the static type of
the first operand, nor the parameter type of the first operand's `operator==`.)

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
if ((Endian.host as Object) == .little) notOk!; // Assigned shorthand context type `Object`.
```
_We can consider generally changing the context type of the second operand to
the static type of the LHS, as an aspirational context type, if the parameter type
is not useful, or use the parameter type. For now, that's kept as a possible
future improvement._

#### Runtime semantics

In every place in type inference where we used the assigned shorthand context to
decide which static namespace to look-up the name in, we remember the result of
that lookup, and at runtime we invoke that static member/constructor. 
_Like we may infer type arguments to constructors, and use those as runtime
type arguments to the class, we infer the entire target of the member access
and use that at runtime._

In every case where type inference succeeded for a static member shorthand
it resolved the reference to a static member or constructor declaration
in order to use that declaration's signature for static type inference
of the static member access.
The runtime semantics then that member found, ensuring that static analysis
is a valid approximation of runtime behavior.

#### Constant expressions

A static member access expression is a constant expression if the equivalent
explicit static member access expression would have been. 

For each of the cases where this feature added a case to type inference,
it also a adds a case to the rules for being constant. 

Given an expression that is a prefix of `<staticMemberShorthandHead> <selector>*`,
whose assigned shorthand context denotes a declaration *D*, and where
the identifier or `new` of the `<staticMemberShorthandHead>` denotes
a static declaration or constructor declaration *S* when looked up on *D*.

* An expression of the form `const .id(arguments)` or `const .new(arguments)`
  is a constant expression. It's a compile-time error if *S* does not
  declare a corresponding constant constructor, and if any expression
  in `arguments`, which are all in a constant context, 
  is not a constant expression.
* An expression of the form `.<identifier>` is a constant expression if
  *S* declares a corresponding static constant getter.
* An expression of the form `.<identifier>` that is not followed by an
  `<argumentPart>`, is a constant expression if *S* declares
  a static method or constructor with base name `<identifier>`,
  and either type inference has not added type arguments as a
  generic function instantiation coercion to the method,
  or to the target class for a constructor,
  or the added type arguments are constant types.
  _Static tear-offs are constant. Instantiated static tear-offs
  are constant if the inferred type arguments are. Constructor
  tear-offs of generic classes are always on instantiated classes._
* An expression of the form `.new` which is not followed by the
  selectors of an `<argumentPart>`, is a constant expression if
  *S* declares an unnamed constructor, and either the target
  class is not generic, or type inference has inferred
  constant type arguments for the target class.
  _It's unlikely that such a tear-off can occur in a constant
  context and be type-valid for the context type, but
  `const Object o = .new;` is technically valid._
* An expression of the form `.id<typeArguments>` not followed by
  an `<arguments>` selector is a constant expression if the type
  argument clauses are all constant type expressions, and
  *S* declares a corresponding static function. _(It's still a
  compile-time error if *S* declares a constructor with the base
  name `id`, constructors are not generic.)_
* _(An expression of the form `.new` followed by a `<typeArguments>` is
  still a compile-time error.)_
* An expression of `.id(arguments)` or `.new(arguments)` is a
  constant expression if (and only if) it occurs in a constant context,
  *S* declares a corresponding constant constructor, every expression
  in `arguments` (which then occurs in a constant context too)
  is a constant expression, and inferred type arguments to the
  target class, if any, are all constant types.
* An expression of `.id(arguments)` or `.id<typeArguments>(arguments)`
  where *S* declares a corresponding getter or static function is
  never a constant expression.
  _There are no `static` functions whose invocation is constant,
  the only non-instance function which can be invoked as
  a constant expression is `identical`, which is not inside a static
  namespace._

Whether such an expression followed by more selectors is a constant
expression depends on the concrete selectors and types, but can use
the current rules which recursively asks about the receiver being 
a constant function.

_The only `.id` selector which can come after a constant expression
and still be constant is `String.length`, and it's very hard to
make that integer satisfy a context type of `String`._

A static member shorthand expression should be a _potentially constant_
expression if the corresponding explicit static member plus 
selectors expression would be, which currently means that 
it's a potentially constant expression if and only if
it's a constant expression.
_There is no current way for an explicit static member access 
followed by zero or more selectors to be a potentially constant expression
if it contains a constructor parameter anywhere. That "anywhere"
is necessarily in a parameter expression, and the only invocation with
parameters that are allowed in a potentially constant expression is 
a *constant* constructor invocation, and that requires constant parameters._

```dart
Symbol symbol = const .new("orange"); // => const Symbol.new("Orange")
const Endian endian = .big; // => Endian.big.
```

#### Patterns

A *constant pattern* `<staticMemberShorthandValue>` is treated the same
as that static member shorthand as an expression that has no following selectors,
except with the _matched value type_ is set as the shorthand context
of the `<staticMemberShorthandHead>`.

The restriction to `<staticMemberShorthandValue>` is intended to match
the existing allowed constant patterns, `<qualifiedIdentifier>` and
`<constObjectExpression>`, and nothing more, which is why it omits the
`.new` which is *guaranteed* to be a constructor tear-off.
The shorthand constant pattern `'.' <identifier>` must satisfy the same
restrictions as the `<qualifiedIdentifier>` constant pattern, mainly 
that it must denote a constant getter.

If a static member shorthand expression occurs elsewhere in a pattern
where a constant expression is generally allowed, 
like `const (big ? .big : .little)` or `< .one`, except for the 
relational pattern `== e`, it's treated as a normal constant expression,
using the context type it's given. 
The expression of `const (...)` will have the matched value type
as context type. The relational pattern expressions, other than
for `==` and `!=`, will have the parameter type of the corresponding
operator of the matched value type as context type.

Since a constant pattern cannot occur in a declaration pattern,
there is no need to assign an initial type scheme
to the pattern in the first phase of the three-step inference.
_If there were, the type scheme would be `_`._

Example:

```dart
switch (Endian.host) {
  case .big: // Matched value type = Context type is `Endian` -> `Endian.big`.
  case .little: // => `Endian.little`
}
```

If a relational pattern has the form `'==' <staticMemberShorthand>`, 
then the matched value type is assigned as the shorthand context
of the leading `<staticMemberShorthandHead>`, and then type is inferred
for the `<staticMemberShorthand>` expression as normal.

**Notice** that the patterns specification uses the parameter type of
the `==` operator of the matched value type, made nullable, as 
context type for the expression of the `== e` pattern, where the
`e1 == e2` expression uses `_` as context type. That means that it's
*technically possible* for the matched value type to have an equality
parameter type that is *relevant*, while not being equal to itself.
Actually declaring a non-`Object` parameter type for `operator==`
is so rare that this feature chooses to ignore it, and treat
the pattern check `e1 case == e2` the same as the expression `e1 == e2`.

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

A restriction of “It’s a compile-time error if the shorthand context does not
denote a class, mixin, enum or extension type declaration” would make it a visible
property of a declaration whether it is one of these.

Prior to this feature, there are types where it’s *unspecified* whether they are
introduced by class declarations or not. These are all types that you cannot
extend, implement or mix in, so there is nothing you can *use* them for that
would be enabled or prevented by being or not being, for example, a class.
Some do have static members, like `Function`.

We could require the language to *specify* which platform types are considered
introduced by which kind of declaration, if it would matter.
Or we can do nothing, and pretend there is no issue.
Structural types (nullable, `FutureOr`, function types, record types), 
`dynamic`, `void` and `Never` do not have any static members, so it doesn’t
matter whether you allow a static member shorthand access on them, 
it’ll just fail to find anything.

Basically, we could use a term for “a type (scheme) which denotes a static
namespace”. That is what the shorthand context type scheme must do.

For now, the specification falls back on "do a static lookup for a base name
on a declaration", and if that makes sense, it's allowed. 
Any type from the platform libraries, other than those mentioned above,
are said to denote a declaration (that you can then do static member lookup
on).

## Possible variations and future features

### Static extensions

If/when we add static extensions to the language, they should work with static
member shorthands. After we have decided which namespace to look in, based on
the shorthand context, everything should work exactly as if that namespace had
been written explicitly, including static extension member access.

This should “just work”, and having static extensions would significantly
increase the value of this feature, by allowing users to introduce their own
shorthands for any interface type.

The specification has tried to say "do a static member lookup on the denoted
declaration" to abstract over what that does, so that a later language version
could have a second for that lookup that checked static extensions.

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

We've decided to allow members of `X` to be accessed on `FutureOr<X>`, but
not members of `Future`. Primarily to allow people to return values from
`async` functions, where we don't *want* to encourage returning `Future`s.

## Versions

1.4 (2025-01-08): Update constant rules.

* Doesn't require a constant `.new` tear-off to be a constant constructor.
  That was a typo and was never intended.
* Adds more words to constant section.

1.3 (2024-11-29): Fix constant pattern, clean-up, and expansion 
  of the constant section.

* Changes grammar for constant pattern to not allow full selector chain,
  only shorthands for `T.id` and `const T.(id|new)(args)`.
  so the shorthand doesn't accept more than the existing limited productions.
* No other grammatical or semantic changes intended.
* Expand the "Constants" section.
* Mention explicitly that a context type scheme is a semantic type,
  so it cannot refer to a type alias.

1.2 (2024-11-27): "Final" decisions:

* `==` only special-cases second operand, and only if it's precisely a
  shorthand expression. There is no change to the actual context type,
  and no recognition of nested shorthands. You can do `e == .foo`,
  and that's it. Does not depend on parameter type of LHS's `operator==`.
* The static namespace denoted by `S` is also the namespace denoted
  by `S?` and `FutureOr<S>`, nothing more and nothing less.
* Made grammar be `<postfixExpression>` and not share `<selector>*`
  with `<primary>`s. Shouldn't change anything, but makes it clear at which
  grammar production the context type is captured.

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
