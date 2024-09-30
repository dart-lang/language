# Dart static access shorthand
Author: lrn@google.com<br>Version: 0.2

Pitch: You can write `.foo` instead of `ContextType.foo` when it makes sense.

### Elevator pitch

An expression starting with `.` is an implicit static namespaces/class access on the context type.

The type that the context expects is known, and the expression avoids repeating the type, and gets a value from that type.

This makes immediate sense for accessing enum and enum-like constants or invoking constructors, which will have the desired type. There is no requirement that the expression ends at that member access, it can be followed by non-assignment selectors.

There must be a context type that allows static member access.

We also special-case the `==` and `!=` operators, but nothing else.

### Specification

### Grammar

We introduce grammar productions of the form:

```ebnf
<primary> ::= ...
    | <staticMemberShorthand>
   
<staticMemberShorthand> ::= 
      `const` '.' (<identifier> | 'new') <argumentPart>
    | '.' (<identifier> | 'new') 

<constantPattern> ::=  ...             ;; all the current cases
    | <staticMemberShorthand>
```

and we add `.` to the tokens that an expression statement cannot start with. _(Just to be safe. If we ever allow metadata on statements, we don’t want `@foo . bar - 4 ;` to be ambiguous. If we ever allow metadata on expressions, we have bigger issues.)_

That means you can write things like:

```dart
BigInt b0 = .zero; // Context type BigInt
BigInt b1 = b0 + .one; // BigInt.operator+(BigInt other)
String s = .fromCharCode(42);
List<int> l = .filled(10, 42); // (Will use instantiated type).
```

This is a simple grammatical change.

A primary expression cannot follow any other complete expression, something which would parse as an expression that `e.id` could be a member access on. We know that because a primary expression already contains the production `'(' <expression> ')'` which would cause an ambiguity for `e1(e2)` if `(e2)` could also be parsed as a `<primary>`. 

A primary expression *can* follow a `?` in a conditional expression: `{e1?.id:e2}`. This could be ambiguous, but we handle it at tokenization time by making `?.` a single token, so there is no ambiguity here, just potentially surprising parsing if you omit a space between `?` and `.id`. It’s consistent, and a solved problem.

It avoids being ambiguous with `<postfixExpression> ::= <primary> <selector>*` by only adding the `<argumentPart>` if there is a `const` in front. (As long as we don’t introduce `'const' <expression>` as a general operator, the `const .` sequence is unique.)

### Semantics

Dart semantics, static and dynamic, does not follow the grammar precisely. For example, a static member invocation expression of the form `C.id<T1>(e2)` is treated as an atomic entity for type inference (and runtime semantics), it’s not a combination of doing a `C.id` tear-off, then a `<T1>` instantiation and then an `(e2)` invocation. The context type of that entire expression is used throughout the inference, where `(e1.id<T1>)(e2)` has `(e1.id<T1>)` in a position where it has *no* context type. _(For now, come selector based inference, it may have something, but a selector context is not a type context, and it won’t be the context type of the entire expression)._

Because of that, the specification of the static and runtime semantics of the new constructs need to address all the forms <Code>.*id*</code>, <code>.*id*\<*typeArgs*\></code>, <code>.*id*(*args*)</code>, <code>.*id*\<*typeArgs*\>(*args*)</code>, `.new` or <code>.new(*args*)</code>.

_(It also addresses `.new<typeArgs>` and `.new<typeArgs>(args)`, but those will always be compile-time errors because `.new` denotes a non-generic function, if it denotes anything.)_

The *general rule* is that any of the expression forms above, starting with <code>.id</code>, are treated exactly *as if* they were prefixed by a fresh variable, <code>*X*</code> which denotes an accessible type alias for the greatest closure of the context type scheme of the expression.

#### Type inference

In every place where the current specification specifies type inference for one of the forms <Code>*T*.*id*</code>, <code>*T*.*id*\<*typeArgs*\></code>, <code>*T*.*id*(*args*)</code>, <code>*T*.*id*\<*typeArgs*\>(*args*)</code>, <code>*T*.new</code> or <code>*T*.new(*args*)</code>, where *T* is a type clause or and identifier denoting a type declaration or a type alias declaration, we introduce a parallel “or <code>.id…</code>” clause, and then continue either with the type denoted by *T* as normal, or, for the <code>.*id*</code> clause, with the greatest closure of the context type scheme, and the *`id`* is looked up in that just as one would in the type denoted by *`T`* for *`T.id`*.

That makes it is a compile-time error if the greatest closure of the context type scheme is not a type with a static namespace, so not a type introduced by a `class`, `enum`, `mixin`, or `extension type` declaration. _(There is no way to refer to a static  `extension` namespace this way, since it introduces no type.)_ The same is the case for an explicit static member access like `dynamic.id` or `X.id`.

Whichever static member or constructor the *`.id`* denotes, it is remembered for the runtime semantics.

#### Special case for `==`

For `==`, we special case the context type that is applied to a `.id`.

If an expression has the form `e1 == e2` or `e1 != e2` , then

* If `e1` starts with an implicit static access then:
  * Let *S2* be the static type of `e2` with context type scheme `_`.
  * Let *S1* be the static type of `e1` with context type *S2*.
  * Let <code>*R* Function(*T*)</code> be the function signature of `operator==` of *S1*.
* Otherwise:
  * Let *S1* be the static type of `e1` with context type scheme `_`.
  * Let <code>*R* Function(*T*)</code> be the function signature of `operator==` of *S1*.
  * If `e2` *starts with an implicit static access*, and *T* is a supertype of `Object`, then let *S2* be the static type of `e2` with context type *S1*.
  * Otherwise let *S2* be the static type of `e2` with context type *T*.
* It’s a compile-time error if *S2* is not assignable to <code>*T*?</code>.
* The static type of the expression is *R*.

An expression *starts with an implicit static access* if and only if one of the following:

* The expression is an `<implicitStaticAccess>.`
* The expression is `(e)` and `e` starts with an implicit static access.
* The expression is `e..<cascadeSelector>` or `e?..<cascadeSelector>` and `e` starts with an implicit static access.
* The expression is `e1 ? e2 : e3` and at least one of `e2` or `e3` starts with an implicit static access.
* The expression is `e <selector>*` and `e` starts with an implicit static access.

#### Runtime semantics

Similar to type inference, in every place where we specify an explicit static member access or invocation, we introduce a clause including the <Code>.*id*…</code> variant too, the “implicit static access”, and refer to type inference for “the declaration denoted by <code>*id*</code> as determined during type inference”, then invoke it the same way an explicit static access would.

#### Patterns

A constant pattern is treated the same as the expression, with the matched value type used as typing context, and then the expression must be a constant expression. Since a constant pattern cannot occur in a declaration pattern, there is no need to assign an initial type scheme to the pattern in the first phase of the three-step inference. _If there were, the type scheme would be `_`._

#### Constant expressions

The form starting with `const` is inferred in the same way, and then the identifier must denote a constant constructor, and the expression is then a constant constructor invocation of that constructor.

An expression without a leading `const` is a potential constant and constant expression if the corresponding explicit static access would be one.

## New complications and concerns

The `.id` access is a static member access which cannot be resolved before type inference.

Prior to this feature, static member accesses could always be resolved using only the lexical scopes and declaration namespaces, which does not require type inference.

Similarly, it’s not known whether `.id` is a valid potentially constant or constant expression until it’s resolved what it refers to. This may delay some errors until after type inference.

It’s not clear that this causes any problems, but it may need implementations to adapt, if they assumed that all static member accesses could be known (and the rest tree-shaken) before type inference.

## Possible variations

### Grammar

Instead of introducing a new primary, we can make it a `<postfixExpression>`:

```ebnf
<postfixExpression> ::= <assignableExpression> <postfixOperator>
  | <primary> <selector>*
  | <staticMemberShorthand <selector>*
  
<staticMemberShorthand> ::= 
     `const` '.' (<identifier> | 'new') <argumentPart>
   | '.' (<identifier> | 'new') 

<constantPattern> ::=  ...             ;; all the current cases
   | <staticMemberShorthand>
```

where we recognize a `<staticMemberShorthand> <selector*>` and use the context type of the entire selector chain as the lookup type for the `.id`, and it can then continue doing things after than, like:

```dart
Range range = .new(0, 100).translate(userDelta);
BigInt p64 = .two.pow(64);
```

Here the `.new(0, 100)` itself has no context type, but the entire selector chain does, and that is the type used for resolving `.new`.

This should allow more expressions to use the context. It may make it easier to get a *wrong* result, but you can do that in the first step if `.foo()` returns something of a wrong type.

It does *not* allow other operators, so the following are invalid:

```dart
BigInt m2 = -.two; // INVALID (No context type for operand of unary `-`)
BigInt m2 = .two + .one; // INVALID (No context type for first operand of `+`)
```

_(We could go further and look at the syntactically first *primary expression* in the entire expression, and apply the full context type to that, if it gets no context type otherwise. Something like `!e` gives `e` a real context type of `bool`, but `.foo + 2` and `-.foo` do not. It’s much more complicated, though.)_

An expression of the form `.foo.bar.baz` might not be considered an *assignable* expression, so you can’t do `SomeType v = .current = SomeType();`. An expression of the form `.something` should *produce* the value of the context type, that’s why it’s based on the context type, and an assignment produces the value of its right-hand side, not of the assignable expression.

On the other hand, an assignable expression being assigned to gets no context type, so that would automatically not work, and we may not need to make an exception.

And for `.current ??= []`, which *sometimes* does and sometimes doesn’t produce the value, it might be convenient. However, the context type of `.current` in `Something something = .current ??= Something(0);` will be `Something?`, a union type which does not denote a type declaration, so it wouldn’t work either. For `Something something = .current += 1;`, the context type of `.current` needs to be defined. It probably has none today because assignable expressions cannot use a context type for anything.

All in all, it doesn’t seem like an implicit static member access can be assigned to and have a useful context type at the same time, so effectively they are not assignable.

#### Nullable types

Should a nullable context type, `Foo?` look for members in `Foo`. Or in `Foo` *and* `Null`. (Which will make more sense when we get static extensions which can add members on `Null`.)

It would allow `Foo x = .current ?? Foo(0);` to work, which it doesn’t today when the context type of `.current` is `Foo?`, and a union type doesn’t denote a static namespace otherwise.

If we don’t allow it, it then makes a difference whether you declare your method as:

```dart
void foo([Foo? foo]) {
  foo ??= const Foo(null);
  // ...
}
```

or

```dart
void foo([Foo foo = const Foo(null)]) {
  // ...
}
```

which are both completely valid ways to write essentially the same function. It makes a difference because the latter can be called as `foo(.someFoo)` and the former cannot, and the former can be called with `null`, which is why you might want it. If we don’t allow shorthands with nullable context types, we effectively encourage people to write in the latter style, and it’s a usability pitfall to use the former with an enum type. I’m not sure we *want* to cause that kind of forced choices on API design. The shorthand shouldn’t punish you for an otherwise reasonable choice. 

So leaning on allowing.

#### Asynchrony and other element types

The nullable type is a union type. So is `FutureOr<Foo>`.

If we allow the nullable context to access members on the type (and on `Null`), should we allow static members of `Foo` (and `Future`) to be accessed with that as context type?

It’s useful. Until [#870](https://dartbug.com/language/870) gets done, the return type of a return expression in an `async` function is `FutureOr<F>` where `F` is the future-value-type of the function. If we don’t allow access, then changing `Foo foo() => .value;` to `Future<Foo> foo() async => .value;` will not work. That’s definitely going to be a surprise to users, and it’s a usability cliff. And telling them to do `Foo result = .value; return result;` instead of `return .value;` goes against everything we have so far tried to teach.

Same applies to `Future<SomeEnum> f = Future.value(.someValue);` where `Future.value` which also takes `FutureOr<SomeEnum>` as argument. That would be an argument for having a *real* `Future.valueOnly(T value) : …`, and it’s too bad the good name is taken.

If we say that a type is the authority on creating instances of itself, it *might* also be an authority on creating those instances *asynchronously*. With a context type of `Future<Foo>`, should we check the `Foo` declaration for a `Future<Foo>`-returning function, or just the `Future` class? If do we check `Foo`, we should probably check be both. 

If we allow a static member of `Foo` to be accessed on `FutureOr<Foo>`, and to return a `Future<Foo>`, but do not allow that with a context type of `Future<Foo>`, it punishes people for being specific. It would *encourage* using `FutureOr<Foo>` as type instead of `Future<Foo>`, to make the API more user friendly. So, if we allow shorthand `Foo` member access on `FutureOr<Foo>`, we *may* want to allow it on `Future<Foo>` too. (But not on more specialized subtype of `Future<Foo>`, like `class MyFuture<T> implements Future<T> …`.)

This gets even further away from being simple, and it special cases the `Future` type, which isn’t *that* special as a type. (It’s not a union type. It is very special *semantically*, an asynchronous function is a completely different kind of function than a synchronous one, and `Future<Foo>` is really a way of saying “`Foo`, but later”. But the type is just another type.)

If we don’t consider `Future` to be special in the language, then allowing shorthand access to `Foo` members on `Future<Foo>` can also be used, using the same arguments, for allowing it on `List<Foo>`.

For enums, that’s even useful: `var fooSet = EnumSet<Foo>(.values)` which expects a `List<Foo>` as argument.

So probably a “no” to `Future<Foo>` and therefore `FutureOr<Foo>`. But it is annoying because of the implicit `FutureOr` context types. (Maybe we can special case `.foo` in returns of `async` functions only.)
## Versions
0.2: Updated with more examples and more arguments (in both directions) in the union type sections.
0.1: First version, for initial comments.
