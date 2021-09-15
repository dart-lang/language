# Dart Field Promotion Proposals

## Current state

Currently there is no language support for promoting a "field". Here, we mainly focus in *instance variables of the current `this` object* ("fields"), because those are often accessed using a single identifier and users therefore expect them to work like a local variable. The problem can be generalized to arbitrary expression values.

The state-of-the-art is to introduce a local variable:

```dart
var field = this.field; // Nullable
if (field != null) {
  methodRequringNonNull(field); // local field variable is promoted.
}    
```

The alternative is to use `!` at the use:

```dart
if (/*this.*/field != null) {
  methodRequringNonNull(/*this.*/field!);
}
```

That includes two tests, first to check that the field is not null, then again to check that it's still not null. Often that check is cheap enough that no-one cares, but it's still unnecessary overhead. It is shorter than introducing the local variable though.

The following are proposed language changes and features to allow field promotion with less syntactic and mental overhead, preferably in a way that can become idiomatic to users.

## No New Syntax (at test or invocation)

These features do not introduce new syntax related to promotion. Some do require new language features that can be used to derive promotion soundness of some variables, but those features can be used independently of promotion as well.

### Optimistic promotion [#1188](https://github.com/dart-lang/language/issues/1188)

We test the field normally, with any test that would promote a local variable, then we treat field accesses as promoted in the code gated by that test. When we read the "promoted" field again, we re-check that the original test result is still valid.

That check can be

* Repeat the `!= null` or `is Foo` check.
* Check that value hasn't changed since the test (`identical`).

The latter is cheaper, but does not support some use-cases which are currently allowed for local variables, like where an assignment preserves the promoted type: `if (x is int) { x += 1; useInt(x); }`.

Pros:

* Works without any extra user activity in situations where users expect it to work.
* Requires no new syntax.
* Works for both `null` checks and `is` checks, instance and static getters.

Cons:

* If the use-site doesn't *need* the promotion, but the static type is changed because of the promotion, this is a breaking change. The issue has an algorithm for deciding which type to use, but it's hard to make both predictable and "most correct" in all situations.
* The code is not statically sound, but we silently introduce run-time casts to make it so. That is effectively introducing implicit downcasts, which can fail at run-time. Some people won't like that.

* Needs to define which expressions can be promoted. The compiler needs to link the test to the use, so that it can re-apply the test at the use-site. For that, we very likely want the two to be "the same expression", but that's not a well-defined term without providing a specification.
  * At one end, the most simplistic, it only works for single identifiers, which we might be expanded to `this.x` being equivalent to `x` when `x` denotes an instance member, but probably not to any other non-identifier expression. 
  * Or we can allow a general `e.v` to be promoted, if `e` has the same syntactic structure and all identifiers and member-accesses denote the same declaration/interface member at both test and use. (Being aware that an change to the type of any part of `e` might change a member access from being an extension member to an interface member or vice-versa.)

### Safe promotion when possible

Like optimistic promotion, but detect some subset of code patterns where promotion is statically guaranteed to be safe.

This approach has not been very successful. It's not generally viable to detect "final variables" because of either sub-classing or breaking getter/variable symmetry. It also doesn't help with all the other cases where users might want promotion, but are not inside those limited cases.

Multiple variants have been proposed, including the following.

#### Promote static final variables

A final static variable will not change its value after being read once.

However, promoting a final static variable, but not a static getter, breaks field/getter symmetry. 

Pros:

* Sound for a given program. Does not require extra syntax. Users expect it to work.

Cons:

* Breaks field-getter migration. Locks code that declared a static property as a final field into keeping it as a field. If someone, somewhere, is promoting the field, making it a getter is a breaking change.
* The *safe* default is to make a private field with a public getter, to avoid being locked in. That incentive is exactly the opposite of the reason for introducing getter/field symmetry to begin with, which is to avoid unnecessary "private field/public getter" duplication. This suggests that allowing promotion of a field-induced getter should not be the default, and that being promotable, like being const, needs to be opt-in for the author.

#### Promote static final private variables 

If the static variable is private, promoting variables, and not getters, still makes changing a variable to a getter break other code, but it only breaks code within the same library. The author making the change can also fix all those breakages at the same time, so it's not as big an issue.

Pros:

* Sound, does not require extra syntax.

Cons:

* Only works for static final private variables, which is not that common a problem.
* Users may have trouble remember the exact conditions for when promotion works and when it doesn't. Can feel arbitrary. If combined with another rule for (some) private instance variables, it might work out to something coherent.
* If we introduce "private imports" which allow other libraries to see/declare private members of other libraries, the breakage extends to the entire same module. The author should still be in a position to fix all the breakages, since all libraries of a module will be in the same package.

#### Promoting final instance variables [#104](https://github.com/dart-lang/language/issues/104)

Generally doesn't work because an override might make it impossible to correlate the test and use values. Even when only accessing the variable using `this.x`, there is no guarantee that the test and read will give the same value.

Using `super.x` may be sound for a single program, but breaks the superclass's ability to change a field to a getter.

Cons:

* Doesn't work.
* For experts only: Might work if restricted in other ways, like the ones below.

#### Promoting private final instance variables [#1167](https://github.com/dart-lang/language/issues/1167)

A final private instance variable *which isn't overridden inside the same library* might be safe to promote.

Only `this._x` accesses (usually with implicit `this.`) should be promotable. Accessing through an interface means that someone might implement the private field using `noSuchMethod`. (Unless the interface is not publicly available in any way, but that's very likely to be too fragile a property to depend on.)

Even with that restriction, this ability is still fragile against seemingly unrelated changes. Adding an override of the field anywhere in the library may break promotion. We disallow a mixin application from overriding an inaccessible private variable, so at least mixin applications happening outside of the library won't be a problem.

Pros:

* Does capture a certain number of actual use-cases. Final private fields that are not overridden are common in implementation classes.

Cons:

* Fairly restricted.

* Only works if the library avoids conflicting declarations.
* If we introduce "private imports" with the ability to see/declare private members of other libraries, then we need to check the entire module for conflicts, not just the same library.

#### Promoting private final instance variable of sealed class

If we introduce "sealed" classes which cannot be extended outside of the current library, then the override worry from above is reduced.

Then we can promote `this._x` where `_x` is a final instance variable declared on a sealed class, if all subclasses declared in the same module (unit which can ignore being sealed) are also sealed (that might be the default, or even required, depending on the definition of "sealed") and do not override `_x`. We may also be able to promote `expression._x` because we can ensure that there are no unknown classes implementing the interface of the static type of `expression` outside of the current module, and we can check hat the current module allows promotion to be sound.

Pros: 

* Probably sound. Does not require new syntax for the promotion ("sealed" is a new language feature by itself, with uses other than promotion).

Cons:

* Requires introducing "sealed classes" as a feature, and to design that feature in a way which allows it to be used for promotion.

* Restricted to private final instance variables of sealed classes. Even if classes are made sealed by default, that's still a significant restriction. Does not apply to static variables (but private static variables can be addressed separately as described above.)
* It requires looking at the entire module to see if someone overrides/implements the sealed class in a way which breaks that invariants used to do promotion (including implementing it using `noSuchMethod`). Sealing doesn't mean anything inside the same module (as by the currently proposed design), so enabling promotion based on the class being sealed, and therefore deriving that the fields is not being implemented in an incompatible way, still needs to check the entire current module for whether that happens anyway. Checking the entire module requires *finding* the entire module that a library belongs to, given the library, in order to see whether local promotion is possible. That's not trivial with the current module proposal.
* If we introduce "private imports" with the ability to see/declare private members of other libraries, we also need to check the entire module for potential conflicting declarations - and changing the field to a getter may break code in the entire module.

#### Promoting stable instance getters

The proposed "stable getters" ([#1518](https://github.com/dart-lang/language/issues/1518)) feature introduces a new kind of restricted declarations which are safe to promote.

Pros:

* Sound if the getter is declared `stable`.

Cons:

* Only works for variables actually declared stable.
* If you forget to declare a variable `stable`, it will be a breaking change to add it later.
* If you declare a variable `stable`, it will be a breaking change to remove it later.
* Which together means that a class designer must decide up-front whether each property of their class should be stable or not. There is no obvious default, and making the wrong choice may lock you in. That's a bad user experience.
* Stable getters are very restricted, and won't apply to many actual use-cases.
* Not really usable for anything except allowing promotion, and provides no way to promote variables which weren't declared stable. Moves all the complexity of deciding whether something should be promotable to early in your API design process.

## Introducing syntax at the use-site

We could introduce new syntax at the use-site to check that the variable is still valid at the earlier checked type.

In practice, the reports we get about field promotion not working are almost invariably solvable by adding `!` at the use site. If that's not good enough, it's unlikely we can find anything better.

Cons:

* We already have `!`, and that's not good enough.

## Introducing syntax at the test site

### Explicit optimistic promotion [#1187](https://github.com/dart-lang/language/issues/1187)

We can introduce new *checking syntax*, perhaps `x is int!` (similar to Swift implicit nullable types), or `x ?= null` or `x is? Foo`, which enables optimistic promotion *explicitly* and therefore doesn't feel as much like introducing *implicit* downcasts at the use-sites. 

Pros:

* Allows users to add the extra syntax when they need it.
* Potentially allows more complicated expressions to be tested.

Cons:

* It's new syntax in an already heavily crowded syntactic area.
* Not visible at the use-site where the error will actually occur.
* Users might add the new syntax blindly when something fails to promote, even if it's not the right thing. (It's effectively turning a static type check into a dynamic type check.)
* Like the implicit optimistic promotion, we need to define which *expressions* can be explicitly promoted. That's a non-trivial definition which adds complexity to learning the language.

### Introducing new variables at the test

We have numerous proposals for introducing local variables which can then be promoted using the normal local variable promotion.

Some allow the variable name to be implicit, implied by the expression it's initialized with, but are therefore restricted to expressions that imply a name. Other require the variable name to be explicit.

All of these introduce variables inside expressions, and need to define the scope of the introduced variable to (at most) the code dominated by the variable binding. That's generally not a problem, it will likely be the same scope where a previously defined, but unassiged, variable would become definitely assigned by a normal assignment.

#### Binding type check [#1191](https://github.com/dart-lang/language/issues/1191)

Uses `e is SomeType x` to bind `x` to `SomeType`, inspired by C#. 

Pros:

* Simple syntax.
* Familiar syntax to people from other languages.

Cons:

* Only works for `is` checks, not `!= null`. (Works with `is!` by making equivalent to `!(...is...)`).

* Might conflict with a later pattern matching syntax (but might just agree with it).

#### If-variables [#1201](https://github.com/dart-lang/language/issues/1201)

Used as, e.g., `if (var id != null)` or `if (final expression.id is Foo)`. Implicitly introduces local variable named `id` bound to `expression.id` and then checked against `null` or `Foo`.

Basically, if a test would not promote, put a `var` or `final` in front, and then if the test would promote a local variable, introduce a new local variable with the implicit name and the promoted type in the following code flow (available in the code dominated by that test).

Restricted to binding the value of test expressions (expression followed by `==`/`!=` or `is`/`is!`).

Pros:

* Avoids needing to find a new name.
* Avoids duplicating the name if you want to use the same name.

Cons:

* Only works for expressions which end in an identifier, not, say, `expression[1]` or `expression >> 1`.
* Doesn't read well for implicit `this.` access: `var x == null` does not read as `var this.x == null` to everybody.
* Doesn't generalize to other contexts than tests, and only the left-hand side of `==` tests.

#### Binding expressions [#1210](https://github.com/dart-lang/language/issues/1210)

Used as `if (var:e.id != null)` or `if (var x:e != null)` to introduce either an implicitly named variable or an explicitly named variable bound to the following expression, then allowing tests on the expression. Using `:` allows it to bind stronger than `!=` and `is` checks (grammar would requires a `<relationalExpression>` after the `:`)

Can again work anywhere, not just in tests.

Pros:

* Same as if-variables.
* Also allows introducing a variable name, and therefore works with expressions not ending in member access.

Cons:

* Syntax is less Dart-like and hard to read for some people.
* Uses `:`, a very overloaded operator already.

#### Declaration expressions and assignment promotion [#1420](https://github.com/dart-lang/language/issues/1420)

Allow `var x = e` or `final x = e` as an assignment expression anywhere, introducing an explicitly named variable. Then allow `a != null` an `a is Foo` where `a` is an assignment expression (possibly parenthesized) to promote the assigned variable (`var tmp; if ((tmp = e) is int) { … tmp is int …}` and `if ((var tmp = e) is int) { … tmp is int …}`). 

Can be used everywhere to introduce a local variable. Often requires parentheses when used inside conditions. No implicit name. Also works with normal assignments.

(Can be made to work with implicit naming too, like "if-variables": `var <primary>(.<selector>)*.id` would be a postfix expression which introduces a variable named `id`. Only works with a trailing `.id` selector.)

Alternative proposed syntax is `x := e` which is equivalent to `final x = e`, but shorter. Allowing only that would force expression-introduced variables to be final, which might be a nice restriction, but won't work with implicit naming.

Pros:

* General expression-level variable introduction.
* Dart-like syntax (or alternative `:=` syntax which is very concise).

Cons:

* No implicit naming, needs to find a name. (Can be made to work with implicit naming, though.)
* Needs to include `this.` to do `var x = this.x` if `var x` shadows the instance `x` (unless we somehow remove the declared variable from the scope of its identifier, unlike all other declarations, but then `var x = x` is potentially confusing, and with implicit naming, `var x` might seem like it should work, but is really unreadable. Maybe just a matter of habit, if we made (all* variable declarations to only be in scope after their declaration it's likely that people would start seeing `var x = x;` as idiomatic for making a local variable for a scoped name. It already works in initializer lists.)
* Needs parentheses, `(var x = this.x) != null` cannot be written without those parentheses. That makes the syntax more verbose than something like `var this.x != null`. (With implicit naming, `var this.x != null` works because it can have the same precedence as a selector chain.)
* The `x := e` syntax may end up being favored over `var`/`final` declarations, but only works as expression-statements, not class-level/top-level declarations (it's an expression which introduces a variable, not a declaration).

#### Write-through local variable [#1514](https://github.com/dart-lang/language/issues/1514)

One issue with introducing local variables is that you might assign to the variable, then forget to write back to the instance variable you're caching.

This proposal uses `shadow x` to implicitly "shadow" a variable. It introduces a new local variable with the existing value of the variable`x`, but writes to that local variable are written through to the original variable too.

This idea can be applied to any of the local variable-introducing syntaxes.

Pros:

* Helps prevent a potential bug when you introduce a local variable just to promote a field.

Cons:

* If you are aware enough to add the `shadow`, you can probably also avoid the original problem. If you forget to think about it, and don't add `shadow`, it still doesn't help you. Only really works if it's the default, which would be unnecessary in most situations, and then you'd need a way to opt out.

## Bug reports

### Final `this` variable, null promotion

* https://github.com/dart-lang/sdk/issues/45190
* https://github.com/dart-lang/sdk/issues/44327
* https://github.com/dart-lang/sdk/issues/43764
* https://github.com/dart-lang/sdk/issues/42033
* https://github.com/dart-lang/language/issues/1543
* https://stackoverflow.com/questions/66468181/how-to-use-the-null-assertion-operator-with-instance-fields

### Non-final `this` variable, null promotion

* https://github.com/dart-lang/language/issues/1343

* https://stackoverflow.com/questions/65035574/null-check-doesnt-cause-type-promotion-in-dart
* https://stackoverflow.com/questions/66583766/how-to-safely-unwrap-optional-variables-in-dart/66584174#66584174

### Final `this` variable, type promotion

* https://github.com/dart-lang/sdk/issues/44672
* https://github.com/dart-lang/sdk/issues/43334
* https://github.com/dart-lang/sdk/issues/43167t

### Other object variable, null promotion

* https://github.com/dart-lang/sdk/issues/44318
* https://github.com/dart-lang/sdk/issues/42626
* https://github.com/dart-lang/language/issues/1415

### Index lookup

* https://github.com/dart-lang/sdk/issues/44331

### Static non-final variable, null promotion

* https://github.com/dart-lang/sdk/issues/42086

### Assignment variable promotion

* https://github.com/dart-lang/sdk/issues/41762

