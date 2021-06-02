# Dart Unawaited Futures Language Feature

Author: lrn@google.com<br>Version: 0.2

The Dart SDK now provides `package:lints` with recommended lints for new projects. This includes the [`unawaited_futures`](https://dart-lang.github.io/linter/lints/unawaited_futures.html) lint. The lint warns if a `Future` value is not awaited, and is seemingly discarded, inside an `async` or `async*` function. Basically, it tries to avoid that you mistakenly forget to await a future which should have been awaited.

The lint is unique in that it has a large number of false positives (33K+ in internal Google code), but that the errors that it avoids are so valuable that it's worth adding extra code at every false positive. Currently all false positives call a method from `package:pedantic` as `unawaited(futureExpression)`. The function ignores its argument and returns `void`, which is sufficient to disable the lint.

This is a proposal to make that lint, and the false-positive marking, part of the Dart language directly, not just an analyzer lint.

## Proposal

### The lint

The current lint warns if an expression of type `Future<X>` or `Future<X>?` for some `X` is used in a position where it's value is "discarded", which for that purpose means that it's the expression of a statement expression. It does not consider expressions of type `FutureOr<X>`, or other positions where the value of an expression is ignored.

That is fine for a heuristic, it catches the majority of honest mistakes, but as a language feature it should perhaps be more thorough.

**Proposal:** Any expression with a static type *T* which is meaningful to await, one which is *potentially a future*, meaning:

* *T* implements <code>Future\<*S*></code> for some type `S` (which includes being <code>Future\<*S*></code> itself, but also any custom subtype of `Future`),
* *T* is <code>FutureOr\<*S*></code> for some type *S*,
* `T` is `S?` (or `S*` in non-sound null safety) and `S` is potentially a future.
* *T* is a type variable *X* with a bound *S* which is potentially a future.
* *T* is a promoted type variable *X*&*S* where *S* is potentially a future.

which occurs:

* as the expression of an expression statement,
* as an initializer expression or an increment expression of a C-style `for` loop (`for (here;…; orHere, andHere)`),
* in a context with context type `void`.

now introduces a compile-time error.

This error occurs in more positions than where the lint currently triggers, in particular it includes `FutureOr` types. That's more consistent than the lint, which detects nullable futures, but not `FutureOr`, and therefore behaves differently whether an expression has type `Future<Null>?` or `FutureOr<Null>` (two different syntactic ways to write "future of null or null").

The places where a future is not allowed are *related* to the places where we allow an expression of type `void`, except that we currently allow an expression of type `void` in slightly more places than where it truly is discarded. 

**We could go further** and define the "tail position" of an expression as follow:

An expression *e* is *in tail position* in another expression *e*<sub>2</sub> (meaning that the value of the *e* can become the value of *e*<sub>2</sub> with no chance of side effects capturing the value on the way) if

* *e*<sub>2</sub> is *e,*
* *e*<sub>2</sub> is a parenthesized expression, <code>(*e*<sub>3</sub>)</code>, and *e* is in tail position in *e*<sub>3</sub>,
* *e*<sub>2</sub> is a conditional expression, <code>*c* ? *e*<sub>3</sub> : *e*<sub>4</sub></code> and *e* is in tail position in *e*<sub>3</sub> or *e*<sub>4</sub>,
* *e*<sub>2</sub> is a null-coalescing expression, <code>*e*<sub>3</sub> ?? *e*<sub>4</sub></code> and *e* is in tail position in *e*<sub>3</sub> or *e*<sub>4</sub>, *(this one is tricky because e<sub>3</sub> is always inspected, but it is only null-checked, and its value becomes the value of the entire expression if not null)*
* or *e*<sub>2</sub> is a cast expression, <code>*e*<sub>3</sub> as *T*</code> and *e* is in tail position in *e*<sub>3</sub>.

and then it's a compile-time error if an expression *e* with a static type which is potentially a future is in tail position in an expression *e*<sub>2</sub> where

* *e*<sub>2</sub> is the expression of an expression statement,
* *e*<sub>2</sub> is an initializer expression or increment expression of a C-style `for` loop, or
* *e*<sub>2</sub> is an expression in a context with a context type of `void`.

(Still only inside asynchronous functions.)

This would capture more positions of futures which might get dropped, and would even avoid `as void` being useful to avoid the warning. It avoids relying on the type of the expression propagating out to the place where the value is discarded. Example: `test ? Object() : Future.value(2);` is an expression-statement where the expression has static type `Object`, and if `test` is false, it does not await the future. Unless we make the context type of these expressions be `void`, and propagate that context  type into the subexpressions in tail position (we currently don't), we won't be able to use static types alone to catch this example. Even if we did that, we couldn't/shouldn't propagate the context type past an `as` cast.

We'd also make it an error to use <code>unawaited *e*</code> when *e* does not have *any* expression *e*<sub>2</sub> in tail position which is potentially a future.

It's all about how *complete* we want to be vs. how complicated the analysis becomes&mdash;for tools and for users who need to understand the language.

### The false positive marker

To avoid the compile-time error, you can do any number of things within the language (including casting it using `as void`, although that would probably give you an "unnecessary cast" warning instead). We introduce a *recommended* way to avoid waiting for the future, by prefixing the expression with the contextually reserved word `unawaited` where you would otherwise write `await` to await the future. In short: `unawaited` becomes a reserved word inside asynchronous functions, just like  `await` and  `yield` currently are. It can be used in exactly the same places as `await`.

This keyword is deliberately visible and up-front so that people reading the code are aware that a future is being ignored here. A reviewer can easily see that a future is not awaited, and question whether it should be.

The grammar change needed for this is to introduce an extra production in parallel with the `await` expression:

```latex
<awaitExpression> ::= \AWAIT{} <unaryExpression>
    | \UNAWAITED{} <unaryExpession>       % new
```

For typing, <code>unawaited *e*</code> requires that *e* has a type which is potentially a future (one of the types above where the error *could* trigger) or the type `dynamic`, otherwise it's a compile-time error. If *e* has such a type, then <code>unawaited *e*</code> has static type `void`. For type inference, the expression *e* has no context type.

The run-time semantics is as follows:

* Evaluate *e* to a value *v*.
* Then <code>unawaited *e*</code> evaluates to `null`.

Example:

```dart
Future<int> foo() async {
  var x = await someComputation();
  unawaited log("Got $x"); // Ignores that `log` returns a future.
  return x + 1;
}
```

### Await only futures

Another recommended lint is [`await_only_futures`](https://dart-lang.github.io/linter/lints/await_only_futures.html), which causes a warning if you `await` an expression with a type which doesn't suggest that it could be a future. 

> **AVOID** using await on anything which is not a future.
>
> Await is allowed on the types: `Future<X>`, `FutureOr<X>`, `Future<X>?`, `FutureOr<X>?` and `dynamic`.
>
> Further, using `await null` is specifically allowed as a way to introduce a microtask delay.

These are the types which were *potentially futures*, minus the type variables, but plus `dynamic` and the `null` value. As such, this lint is like a dual to the `unawaited_futures` lint, together stating that you must await all futures, and must only await futures. We've made it an error to use `unawaited` on a non-(potential-)future, so for *symmetry*, we should include this lint in the language at the same time, and make it an error to await a something which is not a potential future, not `dynamic` and not `Null`..

**Proposal:** Any expression <code>await *e*</code> where the static type *T* of  *e* is not potentially a future, not `dynamic` an not `Null`, is a compile-time error.

### Possibly require await in return

If we are touching asynchronous functions and requiring `await` in some situations, it's a good time to revisit the "implicit `await`" in returns in `async` methods. It's a very thorny part of the type system, and it requires run-time checks just to figure out whether to await or not.

We would prefer to [remove](https://github.com/dart-lang/language/issues/870) the implicit await feature, so that in an `async` function with a return type of `Future<X>`, a return statement must return an expression with a static type assignable to `X` (subtype of `X` or `dynamic`). That would be consistent with making awaiting or not awaiting other futures explicit. 

We would be able to remove the run-time code to check for needing an `await`, reducing AoT code size, and only await when the author actually wants to.

## Summary

We define new *syntax*, making `unawaited` a reserved word inside asynchronous functions, and adding a production to `<awaitExpression>`:

```latex
<awaitExpression> ::= \AWAIT{} <unaryExpression>
    | \UNAWAITED{} <unaryExpession>       % new
```

which only works inside asynchronous functions.

We define that a type *T* is *a potential future* (with future value type *S*) if

* *T* implements <code>Future\<*S*></code>,
* *T* is <code>FutureOr\<*S*></code>,
* *T* is *R?* and *R* is a potential future (with future value type *S*).
* *T* is a type variable *X* with a bound *R* or promoted to *X*&*R*, where *R* is a potential future (with future value type *S*).

We then update the static semantics of `<awaitExpression>` such that:

* <code>await *e*</code> is a compile-time error if the static type of *e* is not a potential future, not `dynamic` and not `Null`.
* <code>unawaited *e*</code> is a compile-time error if the static type of *e* is not a a potential future and not `dynamic`. *(We don't need to allow `dynamic` here, but the general rule is that it's never a compile-time error that an expression has type `dynamic`.)*

The static type of <code>unawaited *e*</code> is `void` and *e* has no context type.

Finally, we make it a compile-time error if an expression *e* has a static type which is a potential future, and

* *e* is the expression of an `<expressionStatement>`,
* *e* is an initializer expression or increment expression of a C-style `for` loop (`for (here;…;here, here) …`).
* *e* occurs in a position which expects `void`. *(This would also trigger the [`void_checks`](https://dart-lang.github.io/linter/lints/void_checks.html) lint.)*

and we recommend using either `await` or `unawaited` to avoid such an error. *(We can extend that to any expression "in tail position" of those expressions as well.)*

Possibly remove the implicit await in return statements of `async` functions, meaning that the context type of the return expression is the future value type of the surrounding function, and the expression must have that type (or `dynamic`).

## Migration

This is a breaking change, so we may need to migrate existing code inside asynchronous functions. The following migrations can be *automated*:

* Any code which currently `await`s a non-potential-future has the `await` removed. *This might change the timing of the code.* It should not change the type. If the `await` is the last operation of an expression statement, we can possibly insert `await null;` as the next statement to reintroduce the delay. A completely non-breaking change would be to change <code>await *e*</code> to <code>await (*e* as FutureOr\<*S*>)</code> where *S* is the static type of *e*. It won't *improve* the code, but it will make it stand out as questionable (and likely trigger the "unnecessary cast" lint).
* Any code which currently doesn't `await` a potential future where it would become a compile-time error, or which uses the `unawaited` function from `package:pedantic` (or any other recognized workaround introduced before this language change) is migrated to use <code>unawaited *e*</code>. *This may break code which relies on passing a future through a `void` typed context and awaiting it later, because `unawaited` replaces the value with `null`.*
* Any code which currently declares a local variable named `unawaited` has the variable renamed to something like `unawaited_`. *Any other use of `unawaited` as an identifier in an asynchronous function, which isn't the currently used function from `package:pedantic`, becomes an error.*

* Possibly, if we change returns, any <code>return *e*;</code> statement or <code>=> *e*</code> body of an `async` function with future value type *T* and static type of *e* is a potential future with future value type *S* and *S* is a subtype of *T*, to <code>return await *e*; </code> and <code>=> await *e*</code> respectively. *This may break code relying on implicit awaits of expressions of type `Object` or `dynamic`.* It's not possible to automatically migrate all code correctly for this change because it's not currently based on the static type. That's also one of the main reasons for wanting to make the change.

### Staged migration

One alternative is to introduce the change as a *warning* before making it a *compile-time error* in a later revision.

It would require two language versions, one for each change, but could allow *some* existing code to keep working without needing to migrate immediately.

We cannot make it a non-breaking first step because we introduce a new reserved word from the start. Any code already using that word as an identifier in an asynchronous function would still break. Existing uses of the `unawaited` *function* would work because the keyword operation does precisely the same thing and allows the same syntax (apart from a possible warning about unnecessary parentheses). It's unlikely that there are many uses of the identifier`unawaited` which do not refer to the existing function, but there are [some](https://github.com/dart-lang/test/blame/ed0fe22880fd17376977ce19c3711327f4fcb01d/pkgs/test_api/lib/src/backend/invoker.dart#L465). As usual it's impossible to know for certain what happens in closed-source projects.

## Version

* 0.1 Initial draft
* 0.2 Added type variables with bounds/promotions that could be futures, and alternative enhancement using "tail position" expressions.
