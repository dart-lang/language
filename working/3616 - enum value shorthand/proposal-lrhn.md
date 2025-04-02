# Dart enum value shorthand

(This is not the version being implemented. See the [simpler proposal](proposal-simple-lrhn.md).

Pitch: Write `.foo` instead of `EnumName.foo` when possible.

There are multiple levels of complexity possible for this functionality. This will start with the most basic version.

### Elevator pitch

* For `.id`, if the context type suggests a type declaration `D`,  such that `D.id` is a static getter, which has a return type that is a `D`, then `.id` works just like `D.id`. Otherwise it’s a compile-time error (which includes when there is no context type).
* As a special case for `e == .id` *and* `.id == e`, we use the static type of `e`, inferred with no context type, as context type for `.id`. Even if it means inferring the type of the second operand first. Works for `!=` too, and no other operators, `.id == .id` is just an error.
* In a switch case, the matched value type counts as a context type, so `case .id:` and `case == .id:` works as expected.

* Stretch goal: Allow `.id(args)` and `.id<typeArgs>(args)`, maybe even `const .id(args)` for constructors, if the suggested type has a static function or constructor which returns a type that fits the context type, with a semantics equivalent to `const D.id(args)`, etc., including being an error if if the arguments don’t match, or using `const` with a non-constructor.

### Longer summary

When we see `.id`, we try to figure out which declaration *D* it means to be <code>*D*.id</code> of.

The candidates declarations are: 

* The declarations of the context type itself. 
  * If that’s a union type, then the declaration of the base type, as well as the one, or both, of `Null` and `Future` that the type is unioned with.
  * If the base type is not a class/mixin/enum/extension type, then it has no corresponding declaration.
* Add any subtype of any of these types that are *successfully imported* into the current library.
  * Imported by at least one `import` where it’s not hidden by `show`/`hide`, and is not conflicted.
  * Or an has a successfully imported alias.
* Add the immediate subtypes of any of those declarations that are `sealed`. _A sealed subtype defines its immediate subtypes as its implementations._ Repeat if this adds more sealed declarations.

Then we check if any of these declarations, *D*, has a static getter member named `id` which returns a value implementing *D*. That is, the declaration *D* can provide an instance of *itself*. 

_The `.id` syntax is asking for a type which provides an `id` instance of itself._

For `==`, we have no context type for the first operand, and likely a useless context type (`Object?`) for the second operand. If that is the case, and one of the operands is a `.id` expression,
we use the other operand’s static type as an the “context type” for finding a declaration. This, and the derived `!=`, are the only special-cased operators.

_Switch cases `case .foo` and `case == .foo` have a context type, so they just work._

This should allow the following uses:

```dart
byteData.setUint32(4, value, endian: .little);
if (Endian.host == .little) { ... }
if (.little == Endian.host) { ... }
switch (Endian.host) {
  case .little: print("little");
  case == .big: print("big");
}
```

**Hopefully** we also allow `.id(args)` which is resolve in the same way, but looks for static functions or constructors to invoke, also with a return type of that implements the containing declaration. That will allow uses like:

```dart
Padding(
  padding: const .all(8.0),  // const EdgeInsets.all(8.0) // constructor
  child: ...
)    
 
int x = .parse(input);  // Static method.

const String option = .fromEnvironment("my_option"); // Constructor
```

and it will have a *good chance* of allowing any subclass of the context type, that you’d reasonably want to write, to be omitted. As long as there is no doubt about where the name comes from.

## Base design (getters only)

### Syntax

Allow an expression to be `.foo`. More precisely, add a production for that to `<primary>` and `<constantPattern>`:

```ebnf
<primary> ::= ...
   | <staticMemberShorthand>
   
<staticMemberShorthand> ::= '.' <identifier> 

<constantPattern> ::=  ...
    | <staticMemberShorthand>
```

An expression or pattern can otherwise not start with `.`, and cannot directly follow another expression or pattern without some punctuation between them, so that should not be a parsing problem.
(It will put yet another stake into the idea of making semicolons optional. And it might have not-so-useful recovery if someone mistakenly omits a prior punctuation.)

### Static Semantics

#### Base case

Type inference will infer an *inferred target* for the <code>.*id*</code>, a static getter *D* named *`id`* of a type declaration *T*, 
so that the meaning of `.id` becomes the meaning of <code>*T*.*id*</code>. It’s a compile-time error if no such declaration is found.

Type inference of an expression `e` of the form <Code>.*id*</code> with typing context *C* proceeds as follows:

* Perform *inferred target* inference on *e* with target typing context *C*.
* If successful, let *D* be the inferred target getter declaration of *e*.
* The static type of *e* is the return type of *D*.

Inferred target inference on e with target typing context *C* proceeds as follows:

* Let *S* be the set of *declarations denoted by C*, as defined below. _(May be empty, which will quickly lead to an error below.)_

* Let *G* be an empty set of candidate getters.

* For each declaration *T* in *S*. If

  * *T* has a static member *D* with name <code>*id*</code>,

  * _(or else, if we add extension static members, and there is a unique applicable extension static member *D* for the declaration *T*,)_

  * then if 

    * *D* is a getter _(whether declared as a getter, or implicitly introduced by a static variable, which can be mutable, final or `const`)_, and

    * the return type of *D* implements *T*,

  * then add *D* to *G*.

* It’s a compile-time error if *G* has no elements.

* If *G* has precisely one element, let *D* be that getter.

* **Simple version:**

  * Otherwise it’s a compile-time error. _Tools can use any of the information in *S* and *G* for giving useful error messages._

* **More complicated version**:

  * Otherwise prioritize the declarations of *G* as follows:
    * A getter declaration *G1* has higher priority than a getter declaration *G2* if:
      *  the type declaration containing *G2* has the declaration containing *G1* as a (direct or transitive) super-declaration (that is, if the type of *G2* can be a subtype of the type of *G1*.)
      * _(Can add more prioritizations here, if we come up with ones.)_
  * If the set contains one declaration which has a higher priority than all other elements, the let *D* be that declaration,
  * otherwise it’s a compile-time error.

* Then the *inferred target* of <Code>.*id*</code> is *D*.

#### Operators

We can special case operators, and definitely should for `==`. These use the base case above, but supply it with a custom typing context if necessary.

##### Equality operators `==`/`!=`

Type inference of an expression `e` of the form <code>e \<eqop\> .*id*</code> (`<eqop>` one of `==` or `!=`), proceeds as follows:

* Perform type inference of *e* with `_` as typing context.
* If successful, let *T* be the static type of *e*.
* Let *P* be the parameter type of the `operator ==` member of the type signature of *T* _(which must exist)_.
* If *P* is a supertype of `Object`, let *C* be *T*, otherwise let *C* be *P*. _(This is the only new step thing here, today we should just use P.)_
* Perform type inference of <code>.*id*</code> with typing context *C*.
* If successful, let *S* be the static type of `.id`.
* It’s a compile-time error if *S* is not assignable <code>*P*?</code>.
* The static type of `e` is <code>bool</code>.

Type inference of an expression `e` of the form <code>.*id* == *e*</code> (or `!=`), proceeds as follows _(which is completely new)_:

* Perform type inference of *e* with `_` as typing context.
* If successful, let *T* be the static type of *e*.
* Perform type inference of <code>.*id*</code> with typing context *T*.
* If successful, let *S* be the static type of `.id`.
* Let <code>*R* Function(*P*)</code> be the function signature of the `operator==` member of *S*. _(Must be a unary function, with <Code>*R*</code> \<: `bool`)_
* It’s a compile-time error if *T* is not assignable <code>*P*?</code>.
* The static type of `e` is `bool`.

_If both operands are of the form `.id`, a compile-time error occurs in the first step of either algorithm, so it doesn’t matter which we choose._

##### Other operators

We could special case other operators, but likely won’t for now. Something like `BigInt(n) + .one` is covered by the base context type inference,
`Uint64(1) + .one` is not because it’s `operator+` takes `Object` as argument.
If we want to support something like `.one + BigInt(n)`, we’ll need to do something like for `==`, infer a context type based on the other operand,
or the surrounding context, or a combination. But we’ll likely wait for selector-chain based receiver inference, which may give us some of the information for free.

#### Patterns

Type inference of a constant pattern performs normal expression type inference on the expression using the matched-value type as context type,
possibly in in a constant context if inside `const (…)`. This should just work for the static member shorthand.

The `== .id`/`!= .id` patterns, allowed by `<relationalPattern>` because `.id` is an expression, are inferred the same way as an `e == .id`
expression where `e` has the matched value type as static type. 
That is, if *M* is the matched value type and *P* is the parameter type of *M*‘s `operator==`, perform type inference on `.id` with *P*? as
typing context if *P* is not a supertype of `Object`, and with *M* as typing context if *P* is a supertype of `Object`.
Otherwise perform inference as normal _(`e == .id`  is the easy case, which only differs from normal inference at that one point)_.

It’ll be a compile-time error if the expression is not a constant expression (see below). 

After inferring a target, the pattern it works just like the  `<qualifiedName>` constant pattern would for the `T.id` pattern. _(Grammar wise, it could also be put into `<qualifiedName>`.)_

For the three-step inference of irrefutable patterns, constant patterns cannot occur in an irrefutable pattern, so no change is needed.

#### Constant expression

The expression <code>.*id*</code> is a potentially constant and constant expression if and only if its inferred target is the getter of a constant variable declaration.

#### Declarations denoted by a typing context

Which declarations we check for getters is controlled by this function.

As written, it can include multiple types from union types, which is not directly usable for the base version of the feature, since neither `Null` nor `Future` declare any static values. 

The function looks for *declared types* (types with declarations which can contain static members) which are explicitly mentioned in the context type, and which are subtypes of the context type. Those are the types that we’d want *instances of* to satisfy the context type.

Then it adds further *related* subtypes, based on heuristics that depend on the surrounding context (library imports mainly).

_We can tweak this function it if we want different behavior, like always returning at most one possible type. Or we can expand it, to take into account every type in a promotion chain when assigning to a promoted variable._

The *declarations denoted by a typing context*, *C*, is defined as:

* The result is {} (the empty set), if *C* is `_`.

* Step 1:

  * Let *A* be the declarations directly denoted by *C*, defined as follows:

    * If *C* is `D` or `D<T1, ..., Tn>` where `D` is the type of a class, mixin class, mixin, enum or extension-type declaration *D*,
      then the directly denoted declarations is {*D*}.

    * If *C* is `T?`, the directly denoted declarations are *S*&cup;{*N*}, where *S* is the declarations directly denoted by
      `T`, and *N* is the declaration of the class `Null`.

    * If *C* is `FutureOr<T>`, the directly denoted declarations are *S*&cup;{*F*}, where *S* is the declarations denoted by `T` and *F* is the declaration of the class `Future`.

    * If *C* is a promoted type variable *X*&*B*, then the directly denoted declarations of *B* are the directly denoted declarations of *C*.
    * 
    * If *C* is a type variable with bound *B*, then the directly denoted declarations of *B* are the directly denoted declarations of *C*.
 
    * Otherwise the directly denoted declarations is empty, {}. This occurs for, at least, a function type, record type,
     `dynamic`, `void`, and `Never`.
      
  * If *A* is empty, the declarations denoted by *C* is empty.

  * Otherwise continue with the following steps.

* Step 2:

  * Let *K* be a worklist containing the declarations of *A*.

  * While *K* is not empty:

    * Remove a declaration from *K* and let *S* be that declaration.

    * let *C*<sub>IS</sub> be the set of *imported type declarations* which implements *S*. An imported type declaration is:

      * A type declaration (currently `class`, `mixin class`, `mixin`, `enum`, or `extension type`) which is _successfully imported_ by the current library,
        meaning being in the export scope of the imported library of at least one `import` declaration, not being hidden by a `show`/`hide` modifier of that `import` declaration,
        and the imported name not conflicting with another imported name in the same scope.

        This includes both top-level imports and prefixed imports.

      * Or a type declaration which is aliased by a successfully imported type alias.

      Those are the declarations that implement *S* and which are considered *available* in the current library.
      _(This is very similar to how we consider extension declarations available in a library.)_

    * Add the elements of *C*<sub>IS</sub> to *A*.

* Step 3:

  * Let *K* be a worklist initially containing all the declarations of *A*.

  * While *K* is not empty:

    * Remove a declaration from *K* and let *S* be that declaration.
    * If *S* is declared `sealed`, let *C*<sub>S</sub> be the set of immediate subtypes of *S* _(the ones that exhaust the sealed type)_
      that are accessible in the current library (that is, not library private to another library).
      _(The subtypes of a sealed public class should generally not be private, but if they are private to another library, we won’t include them.)_
    * Add the elements of *C*<sub>S</sub>&setminus;*A* (the elements of *C*<sub>S</sub> which are not already in *A*, meaning we haven’t seen them before) to *K*.
    * Add the elements of *C*<sub>S</sub> to *A*.

* Step 4

  * The declarations denoted by *C* is the resulting set *A*.

### Runtime semantics

Evaluation of an expression `e` of the form <Code>.*id*</code> proceeds as follows:

* Invoke the inferred target of <Code>.*id*</code>, which is a static getter declaration with a return type that is the static type of `e`.
* The result of `e` is the result of that invocation.

_We did all the work in the inference phase, finding the actual getter member that <code>.*id*</code> is a shorthand for,
so all we need to do is invoke it, like we would have if it had been the non-shorthand <Code>*D*.*id*</code>._

## Extension to static methods/constructors.

Also allow invoking constructors or static methods, not just getters.

### Grammar

Becomes:

```ebnf
<primary> ::= ...
   | <staticMemberShorthand>
   
<staticMemberShorthand> ::= '.' <identifier> | `const`? '.' (<identifier> | 'new') <argumentPart>

<constantPattern> ::=  ...             ;; all the current cases
    | <staticMemberShorthand>
```

### Static semantics

Uses the same computation to find declarations to look for static members in.

If no `<argumentPart>` is present, the behavior is the same as above, matching only getters.

If the `<argumentPart>` is there, the applicable static declarations only include static functions or constructors with *`id`* as base name,
and if it’s using  `new`, it only allows unnamed constructors. If including `const`, also look only for constructors _(unless we introduce a `const` operator for general expressions)_. 
The return type must still be a type which implements the surrounding declaration.

The search for potential members to invoke won’t check that function arguments *match* before choosing the declaration to use.
After deciding on one, it will check that the invocation is valid (as if rewritten to _`TypeDeclaration.id(args)`_,
but without using rewriting). If `const` is there, or the code occurs in a `const` context, the inferred target must be a `const` constructor.

#### Patterns

A constant pattern is treated the same as the expression, with the matched value type as typing context, and then the expression must be a constant expression.

#### Constants

The expression is a potential constant and constant expression if and only if the inferred target is the getter of a constant variable,
or it is a constant constructor, the type arguments and argument list expressions are all constants,
and it has either an explicit `const`, or is occurring in a constant context.

### Runtime semantics

Performs the same invocation as an explicit `TypeDeclaration.id` or (`const` of) `TypeDeclaration.id<typeArgs>(args)` would.

## Discussion

### Grammar

The production is inserted as a ` <primary>` because we want it to occur in expressions like `e1 == e2`.
That requires it to be at least a `<relationalExpression>`, but to be safe, we move it as far down as possible.

It could be a `<conditionalExpression>`, because you are not allowed to put something *after* it,
except possibly a cascade. You can’t do `.foo.bar()`, because that puts `.foo` in *receiver* position,
and we want it to have a context. But if we add “vertical inference” in the future,
receivers might get a kind of contexts. And we’d have to have a special case for `==`/`!=` then.

### Candidate type declarations

The “declarations denoted by a context type” function returns, basically, the underlying type’s declaration,
if it has one, plus `Null` and/or `Future` if the context type is a union type.

If the context type is a type variable, it doesn’t use the bound or a promoted type of that type variable,
because an instance of that type would not be a subtype of the type variable, and therefore not valid in the context.

The inclusion of `Null` is not useful, since `Null` declares no static members or constructors.
If we add extension-static-members, it won’t make much of a difference, since we’ll only be looking for getters or functions returning `Null`.
We could probably just not add it when seeing `T?`, to avoid the noise.

The inclusion of `Future` only makes a difference if we include constructor calls,
or if someone introduces a user type which subtypes `Future` (and it's successfully imported).
Without a subtype, it makes sense for writing short non-`async` based asynchronous code, like `Future<int> f = .value(2);`.
Which is still not used a lot, but it can be useful
And with extension-static-members, or ourselves adding static values like a `const Future<Null> nullFuture = …;`,
then it can be even more useful. But we could probably also just not add it when seeing `FutureOr`, and nobody will notice.

A *better* reason to have more than one candidate type would be to include all the types of a promoted variable that is being assigned to.
If I have `Inflatable b = …; if (b is Balloon) b = .dirigible;`, I’m doing the assignment precisely because I *don’t* want a `Balloon`,
and only looking for `Balloon.dirigible` will fail me, but also looking for `Inflatable.dirigible` might work.
On the other hand, `if (b is Balloon && b == .modelling) makeDog(b);` could also work. 
_(Generally there are other places, including upper bounds, where knowing that there are multiple viable types can give better results.)_

### Choice of inferred targets

This design allows *any* getter, and any static method or constructor, to be used, as long as it returns something that has the same type as the declaration it’s on.

* We could allow only `enum` values, but that’s fairly restrictive, and discriminates against enum-like classes, which do exist.

* We could allow only `const` variables. That’s consistent and enforceable, but not a *necessary* restriction,
  and not all useful values are constant. (For example `Endian e = .host;` wouldn’t work.)

* We could try to allow only `final` variable getters, but that’s breaking getter/field symmetry and making the declaration part of the public API.
  We don’t have stable getters, so if we allow some non-`const` getters, we should allow all getters.

All in all, a restriction on the kind of getter doesn’t seem to be worth the effort.

We restrict to static members returning the same type as the type declaration they’re on.
We could allow any getter/function with a return type that is assignable to our *context type*. That would be sound. We choose not to.

This is more of an opinionated and intent-based restriction. We have a context type, which allows some types.
We then check each of those types for a way to get a value of *that* type, not just any type.
We ask a type for instance of itself, because the type is assumed to be the *authority* on how to get instances of itself.
It’s not considered an authority on other types. A match there would more likely be spurious.

#### Asynchrony and other element types

If we say that a type is the authority on creating instances of itself, it *might* also be an authority on creating those instances *asynchronously*.
With a context type of `Future<Foo>`, should we check the `Foo` declaration for a `Future<Foo>`-returning function, or the `Future` class?
If do we check `Foo`, it probably should be both.

The necessary change would be to make the denoted declarations of `Future<T>` be the denoted declarations of `T` plus {`Future`},
*and* check that the returned types of the static members is assignable to the context type, not just to itself (because the latter no longer implies the former.)

But while `Future` is special, it’s not *that* special, and we could equally well have a context type of `List<Foo>` and decider to ask `Foo` for such a list.
For enums, that’s even useful: `var fooSet = EnumSet<Foo>(.values)`.

And if `Foo` has a static getter returning `Foo?`, should `Foo? x = .thatGetter;` work?
We *are* checking `Foo` for that getter already, we’re just rejecting it because its return type is not `Foo`. But it would *work*. 

That is, we could, independently of everything else, check the return type for being a subtype of (the greatest closure of) the context type,
instead of the declaring type, and it would allow more things to match, including `FutureOr<Foo> f = .asyncFactory()` and `OS? os = .osIfKnown;`.

_If we do that, we should definitely not add `Null` to the candidate types when seeing `T?`, otherwise a future extension static getter of 
`int get ft => 42` on `Null` would get matched by `int? x = .ft;` That’s too weird._

This direction is likely too wide-reaching, and not something we should start doing without much more thought.
Stick to getting single values, directly, for the context type. Keep it simple, at least for now.

