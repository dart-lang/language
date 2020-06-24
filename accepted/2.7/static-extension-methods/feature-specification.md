# Dart Static Extension Methods Design

lrn@google.com<br>Version: 1.6<br>Status: Design Document.

This is a design document for *static extension members* for Dart. This document describes the feature's syntax and semantics.

See [Problem Description](https://github.com/dart-lang/language/issues/40) and [Feature Request](https://github.com/dart-lang/language/issues/41) for background. 
See [Prefix import request](https://github.com/dart-lang/language/issues/671) for the background for the v1.5 specification update.

The design of this feature is kept deliberately simple, while still attempting to make extension methods act similarly to instance methods in most cases.

## What Are Static Extension Methods

Dart classes have virtual methods. An invocation like `thing.doStuff()` will invoke the virtual `doStuff` method on the object denoted by `thing`. The only way to add methods to a class is to modify the class. If you are not the author of the class, you have to use static helper functions instead of methods, so `doMyStuff(thing)` instead of `thing.doMyStuff()`. That's acceptable for a single function, but in a larger chain of operations, it becomes overly cumbersome. Example:

```dart
doMyOtherStuff(doMyStuff(something.doStuff()).doOtherStuff())
```

That code is much less readable than:

```dart
something.doStuff().doMyStuff().doOtherStuff().doMyOtherStuff()
```

The code is also much less discoverable. An IDE can suggest `doMyStuff()` after `something.doStuff().`, but will be unlikely to suggest putting `doMyOtherStuff(…)` around the expression.

For these discoverability and readability reasons, static extension methods will allow you to add "extension methods", which are really just static functions, to existing types, and allow you to discover and call those methods as if they were actual methods, using `.`-notation. It will not add any new abilities to the language which are not already available, they just require a more cumbersome and less discoverable syntax to reach.

The extension methods are *static*, which means that we use the static type of an expression to figure out which method to call, and that also means that static extension methods are not virtual methods.

The methods we allow you to add this way are normal methods, operators, getter and setters. As such, the feature should really be called "Static Extension Members". For historical reasons, we will stick with the "Static Extension Methods" name.

## Declaring Static Extension Methods

### Syntax

A static extension of a type is declared using syntax like:

```dart
extension MyFancyList<T> on List<T> {
  int get doubleLength => this.length * 2;
  List<T> operator-() => this.reversed.toList();
  List<List<T>> split(int at) => 
      <List<T>>[this.sublist(0, at), this.sublist(at)];
  List<T> mapToList<R>(R Function(T) convert) => this.map(convert).toList();
}
```

More precisely, an extension declaration is a declaration with a grammar similar to:

```ebnf
<extensionDeclaration> ::= 
  <metadata> `extension' <identifier>? <typeParameters>? `on' <type> `{'
     (<metadata> <classMemberDefinition>)*
  `}'
```

which is added as a top level declaration:

```ebnf
<topLevelDefinition> ::= ...
    | <extensionDeclaration>
```

Such a declaration introduces its *name* (the identifier) into the surrounding scope. The name does not denote a type, but it can be used to denote the extension itself in various places, and for accessing static members. The name can be hidden or shown in `import` or `export` declarations. The name of an extension must not be a built-in identifier. If an extension declaration omits the name identifier, its equivalent to an extension declaration with a fresh private name.

The type parameters have the same restrictions as type parameters on a class or mixin declaration (no cyclic bounds, no repeated names, etc.)

The *type* can be any valid Dart type, including a single type variable. It can refer to the type parameters of the extension.

Extension declarations have essentially the same name conflict rules as class declarations. Some of the rules can be simplified because extensions have no constructors or super-interfaces. Some further restrictions apply only to extensions. It is a compile-time error if an extension:

- Declares a member with the same basename as the extension.
- Declares a type parameter with the same name as the extension.
- Declares a member with the same basename as the name of any of the extension's type parameters.
- Declares two members with the same basename unless one is a getter and the other is a setter.
- Declares a setter and a getter with the same basename and one is static and the other is not.
- Declares a member with the same basename as a member declared by `Object` (`==`, `hashCode`, `toString`, `noSuchMethod`, `runtimeType`). This applies to both static and instance member declarations.
- Declares a constructor.
- Declares an instance variable.
- Declares an abstract member.
- Declares a member with a formal parameter marked `covariant`.

(The *basename* of a declaration is the declared name of the declaration for variable, method, getter and most operator declarations, and it's the declared name without the trailing `=` for setter declarations and the `[]=` operator.)

_Abstract members are not allowed since the extension declaration does not introduce an interface, and constructors are not allowed because the extension declaration doesn't introduce any type that can be constructed. Instance variables are not allowed because there won't be any memory allocation per instance that the extension applies to. We could implement instance variables using an `Expando`, but it would necessarily be nullable, so it would still not be an actual instance variable. Users who want that functionality can still add it manually using getter/setter declarations. Members with the same base name as members of `Object` are not allowed because some of them are accessed directly by the language semantics, and it is potentially confusing and error-prone if extension members could have the same name and a wildly different signature._

An extension declaration with a non-private name is included in the library's export scope, and a privately named or unnamed extension is not. It is a compile-time error to export two declarations, including extensions, with the same name, whether they come from declarations in the library itself or from export declarations (with the usual exception when all but one declaration come from platform libraries). Extension *members* with private names are simply inaccessible in other libraries.

We make `extension` a built-in identifier. Is not necessary for disambiguation, but it makes error-recovery in parsers much easier.

If we make `on` a built-in identifier, then there should not be any parsing issue. Even without that, the grammar should be unambiguous because `extension on on on { … }` and `extension on on { … }` are distinguishable, and the final type cannot be empty. It may be *harder* to parse.

The ability to implicitly give an extension a private name is a simple feature, but with very low impact. It only allows you to omit a single private name for an extension that is only used in a single library.

### Explicit Extension Member Invocation

You can explicitly invoke an extension member on a particular object by performing a *member invocation* on an *extension application*.

An *extension application* is an expression of the form `E(expr)` or `E<typeArgs>(expr)` where `E` denotes an extension declaration (that is, `E` a simple or qualified identifier which refers to the extension declaration).

An extension application is subject to static type inference.  If `E` is an extension declared as `extension E<X...> on T {...}`, then the type inference for an extension application is done exactly the same as it would be for the same syntax considered as a constructor invocation on a class declared as:

```dart
class E<X...> {
    final T $target;
    E(this.$target);
}
```

with no context type for the constructor invocation.

This will infer type arguments for `E(expr)`, and it will introduce a static context type for `expr`. *For example, if `E` is declared as `extension E<T> on Set<T> { ... }` then `E({})` will provide the `{}` literal with a context type making it a set literal.* It is a **compile-time error** if the corresponding class constructor invocation would be a compile-time error.

It is a **compile-time error** if the static type of the argument expression (`expr`) of an explicit extension invocation is `void`. *(Expressions of type `void`are only allowed in a few specific syntactic positions, and the new explicit extension invocation object position is not included in those.)*

We defined the *instantiated `on` type* of `E` as the `on` type of the declaration of `E` with the inferred or explicit type arguments of the extension application replacing the type parameters of `E`.

We define the *instantiate-to-bounds `on` type* of an extension as the `on` type with type parameters replaced by the types that the instantiate-to-bounds algorithm would derive for any type parameters of the extension.

A *simple member invocation,* null aware or not, on a target expression `X` is an expression of one of the forms:

| Simple invocation   | Simple null-aware invocation | Corresponding member name |
| :------------------ | :--------------------------- | :------------------------ |
| `X.id`              | `X?.id`                      | `id`                      |
| `X.id = expr2`      | `X?.id = expr2`              | `id=`                     |
| `X.id(args)`        | `X?.id(args)`                | `id`                      |
| `X.id<types>(args)` | `X?.id<types>(args)`         | `id`                      |
| `X[expr2]`          | `X?.[expr2]`                 | `[]`                      |
| `X[expr2] = expr3`  | `X?.[expr2] = expr3`         | `[]=`                     |
| `-X`                |                              | `unary-`                  |
| `~X`                |                              | `~`                       |
| `X binop expr2`     |                              | `binop`                   |
| `X(args)`           |                              | `call`                    |
| `X<types>(args)`    |                              | `call`                    |

where `binop` is one of `+`, `-`, `*`, `/` , `~/`, `%`, `<`, `<=`, `>`, `>=`, `<<`, `>>`, `>>>`, `^`, `\|`, and `&`.

A *composite member invocation*, either null-aware or not, on a target expression `X` is an expression of one of the forms:

| Composite invocation    | Composite null-aware invocation | Member base name |
| :---------------------- | :------------------------------ | :--------------- |
| `X.id binop= expr2`     | `X?.id binop= expr2`            | `id`             |
| `X[expr1] binop= expr2` | `X?.[expr1] binop= expr2`       | `[]`             |
| `X.id++`                | `X?.id++`                       | `id`             |
| `X.id--`                | `X?.id--`                       | `id`             |
| `++X.id`                | `++X?.id`                       | `id`             |
| `--X.id`                | `--X?.id`                       | `id`             |
| `X[expr]++`             | `X?.[expr]++`                   | `[]`             |
| `X[expr]--`             | `X?.[expr]--`                   | `[]`             |
| `++X[expr]`             | `++X?.[expr]`                   | `[]`             |
| `--X[expr]`             | `--X?.[expr]`                   | `[]`             |

Each simple member invocation has a *corresponding member name*, the name of the member being invoked (and its associated basename, which is the name without the trailing `=` on setter names and `[]=`). 

A composite member invocation invokes both a getter and a setter, so the table above lists only the basename of those two.

A null-aware member invocation is listed with its *corresponding simple* (non-null-aware) *invocation* form which corresponds to the operation being performed when the target is not `null`.

It is a **compile-time error** if an extension application occurs in a place where it is *not* the target expression of a simple or composite member invocation. That is, the only valid use of an extension application is to invoke members on it. *This is similar to how prefix names can also only be used as member invocation targets. The main difference is that extensions can also declare operators.* 

It is a **compile-time error** to have a simple member invocation on an extension application where the extension in question does not declare an instance member with the same name as the corresponding member name of the invocation, or to have a composite member invocation on an extension application where the extension does not declare both a getter and a setter with the corresponding base name of the invocation. *You can only invoke members which are actually there.*

This means that you cannot do cascade invocations on explicit extension applications: `E(e)..foo()..bar()` is a compile-time error. This is necessary because that expression evaluates to the value of `E(e)`, and an extension application does not have a value.

if *A* is a member invocation with an extension application of an extension *E* as target expression, then type inference applies to the member invocation. If `E` is declared as

```dart
extension E<X...> on T {
  ... members ...
}
```

then the type inference on *A* is the same that would be applied to the member invocation on *E* considered as a constructor invocation on a class declared as:

```dart
class E<X...> {
  final T $target;
  E(this.$target);
  ... members // with inference applied to the body, including implicit extension 
              // member invocations as described in later sections, 
              // and with `$target` instead of `this` ...
}
```

That is, if `E` declares an instance member `T foo(T arg)`, then the inference of `E(e1).foo(e2)` will first perform inference to `E(e1)` as described above, and then perform inference on the member invocation just as if it was a class member. It is a **compile-time error** if this class member invocation would be a compile-time error

The static type of a member invocation on an extension application is the return type of the extension member with the corresponding member name of the invocation, with the explicit or inferred type arguments of the extension application replacing the type parameters bound by the extension, and the explicit or inferred type arguments of the invoked member replacing the type parameters bound by the member.

##### Composite Assignments and Increment Operations

Composite member invocations, like the composite assignment `e.id += 2` or the increment `e.id++`, are defined in terms of two individual member invocations (always one *get* operation and one *set* operation with the same basename). If the target expression of a composite member invocation is an extension application, we need to recognize and handle it specially.

A composite assignment of the form `e1.id += 2` is equivalent to `e1.id = e1.id + 2` except that `e1` is only evaluated once, and the value is used twice. 

However, you cannot evaluate an extension invocation to a value, so we have to specify the case where `e1` is an extension invocation `E(e)` specially (just as we handle the cases where `e1` denotes a class or a prefix). We modify the evaluation rules for composite evaluation to account for this, ensuring that:

- An expression of the form `e1.id op= e2` where `e1` is an extension application `E<...>(e)`, is treated as if it was `E<...>(e).id = E<...>(e).id op e2` except that `e` is only type-inferred and evaluate once.
- An expression of the form `e1[e2] op= e3` where `e1` is an extension application `E<...>(e)`, is treated as if it was `E<...>(e)[e2] = E<...>(e)[e2] op e3` except that `e` and `e2` are type-inferred and evaluated only once.

Increment/decrement operations like `++e` and `e--` are equivalent to composite assignments, except that the post-increment/decrement operations evaluate to one of the intermediate values of the computation.

- A pre-increment expression of the form `++e1.id` is generally equivalent to  `e1.id += 1`. Similarly for `--e1.id`, `++e1[e2]` and `--e1[e2]`. This applies when `e1` is an extension application too, reducing it to the former case.
- A post-increment expression of the form `e1.id++` is generally equivalent to `e1.id += 1` (which is `e1.id = e1.id + 1` except that subexpressions of `e1` are not evaluated more than once), but the value of the expression is the value from evaluating `e1.id` before adding `1`. This too, works similarly when `e1` is an extension application:
  - `E<...>(e).id++` is equivalent to `E<...>(e).id = E<...>(e).id + 1` except that `e` is only evaluated once, and the value of the increment expression is the value of the subexpression `E<...>(e).id` before the addition. Symmetrically for post-decrement.
  - `E<...>(e)[e1]++` is equivalent to `E<...>(e)[e2] = E<...>(e)[e2] + 1` except that `e` and `e2` are only evaluated once, and the value of the increment expression is the value of the subexpression `E<...>(e)[e2]` before the addition. Symmetrically for post decrement.

##### Null Aware Member Invocations

A null-aware member invocation, whether simpler or composite, where the target is a extension application `E(e1)`, is evaluated by first evaluating `e1` to a value *v*. If *v* is `null` then the entire null-aware member invocation evaluates to `null` (and with NNBD, so does a following chain of selectors). If not, then the evaluation continues as the *corresponding simple  member invocation* with target `E(t)` where `t` is a fresh variable bound to *v*.

The static type of a null-aware member invocation on an extension application is the same as the static type of the corresponding simple member invocation with the same extension application as target. (With NNBD, the type of `e1` is promoted to non-`null` before inferring the `on` type of the extension application, just as for the *implicit* invocation `e1?.…`, and the result type becomes nullable if it isn't already.)

### Implicit Extension Member Invocation

Extension members can be invoked *implicitly* (without mentioning the extension by name) as if they were members of the `on` type of the extension. This is intended as the primary way to use extensions, with explicit extension member invocation as a fallback for cases where the implicit extension resolution doesn't do what the user want. 

An implicit extension member invocation occurs for a simple or composite member invocation with a target expression `e` iff there exists a unique *most specific* extension declaration which is *accessible* and *applicable* to the member invocation (see below).

If `E` is the single most specific accessible and applicable extension for a member invocation *i* with target expression `e`, then we treat the target expression as if it was the extension application of the extension `E` to `e`, and if `E` is generic, also providing the type arguments inferred for `E` in checking that it was applicable. This makes the member invocation behave equivalently to an explicit extension member invocation. This happens even if the *name* of `E` is not accessible, so this is not a purely syntactic rewrite.

Implicit extension member invocation applies to null-aware member access. A null-aware invocation, for example `e?.id`, is defined as first evaluating `e` to a value and then if that value, `v`, is non-`null`, it performs the invocation `v.id`. This latter invocation *is* subject to implicit extension invocation if the static type of `e` does not have a member with basename `id`, and similarly for all other simple or composite instance member invocations guarded by a null-aware member access.

Implicit extension member invocation can also apply to individual *cascade* invocations. A cascade is treated as if each cascade section was a separate member invocation on an expression with the same value as the cascade receiver expression (the expression before the first `..`). This means that a cascade like `o..foo()..bar()` may perform an implicit extension member invocation on `o` for `foo()` and a normal invocation on `o` for `bar()`. There is no way to specify the corresponding explicit member invocation without expanding the cascade to a sequence of individual member invocations.

##### Accessibility

An extension is *accessible* for an expression if it is declared in the current library, or if there is a non-deferred `import` declaration in the current library which imports a library with the extension in its export scope, where the name of the extension is not private, and the declaration is not hidden by a `hide` combinator mentioning the extension name, or a `show` combinator not mentioning the name, on the import. _This includes (non-deferred) imports with a prefix._

It is a *compile-time error* if a *deferred* import declaration imports a library with an extension declaration in its export scope, unless all such extensions are hidden by a `hide` combinator with the extension's name, or a `show`  combinator without the extension's name, on the deferred import. *This is a temporary restriction ensuring that no extensions are introduced using deferred imports, allowing us to later introduce semantics for such extensions without affecting existing code*.

An extension *is* accessible if its name is *shadowed* by another declaration (a class or local variable with the same name shadowing a top-level or imported declaration, a top-level declaration shadowing an imported extension, or a non-platform import shadowing a platform import).

An extension *is* accessible if it is imported and the extension name conflicts with one or more other imported declarations.

_This definition of being accessible ignores name shadowing or import name conflicts; the extension is accessible if it *could have been* referenced by name absent of any declarations shadowing it or its import prefix, and absent any other imported declarations with the same name preventing access to the name. If it *is* in scope, then it is obviously also accessible. Compilers need to remember declarations of extensions in imports even if those extensions declarations do not make it into the  importing library scope_

You can *avoid* making the extension accessible for a library by either not importing any library exporting the extension or by importing such a library and hiding the extension using a `hide` combinator with the extension name or a `show` combinator without the extension name.

The usual rules apply to referencing the extension by name. The extension's *name* is not in scope (e.g., for explicit extension invocation) if it is shadowed or if it is conflicting with another imported declaration, but the extension *itself* is still accessible for implicit extension member invocations since that operation does not reference the extension by name.

If an extension conflicts with, or is shadowed by, another declaration, and you need to access it by name anyway, it can be imported with a prefix and the name referenced through that prefix.

_*Rationale*: We want users to have control over which extensions are available. They control this through the imports and declarations used to include declarations into the library. The typical ways to control name conflicts of the imported names is to use `show` /`hide` in the imports or importing into a prefix scope. On the other hand, we do not want extension writers to have to worry too much about name clashes for their extension names since most extension members are not accessed through their name anyway. In particular we do not want them to name-mangle their extensions in order to avoid hypothetical conflicts. So, all imported extensions are considered accessible, and choosing between the individual extensions is handled by using explicit extension applications as described earlier. You only run into problems with the extension name if you try to use the name. That way you can import two extensions with the same name and use the members without issue (as long as they don't otherwise conflict in an unresolvable way), even if you can only refer to *at most* one of them by name._

You still cannot *export* two extensions with the same name. The rules for export makes it a compile-time error to add two declarations with the same name to the export scope of a library.

##### Applicability

An extension `E` is *applicable* to a simple or composite member invocation with corresponding member *basename* *m* and target expression `e`, where `e` has static type *S*, if

- The invocation is an *instance* member invocation. That is the case if the expression `e` does not denote a prefix or a class, mixin or extension declaration *(because then the member invocation would be a static invocation)*, and it is not an explicit extension application. An instance member invocation on `e` will always begin by evaluating `e` to an object, and then continue by performing an instance member invocation on that object.
- The type *S* does not have a member with the basename *m*. For this, the type `dynamic`is considered as having all member names, and an expression of type `Never` or `void` cannot occur as the target of a member invocation, so none of these can ever have applicable extensions. Function types and the type `Function` are considered as having a `call` member. *This ensure that if there is an applicable extension, the existing invocation would otherwise be a compile-time error*. Members of `Object` exists on all types, so they can never be the target of implicit member invocations _(they can also not be declared as extension members)_.
- The extension application `E(x)` would be valid (not a compile-time error) where `x` is a fresh variable with static type *S* (to avoid type inference for any type parameters of `E` from affecting the already determined static type of `e`) in a scope where `E` denotes the extension.
- and `E` declares an instance member with the basename *m*.

Notice that the context type of the invocation does not affect whether the extension applies, and neither the context type nor the method invocation affects the type inference of `e`, but if the extension method itself is generic, the context type may affect the member invocation.

##### Specificity

When more than one extension is accessible and applicable to a member invocation, we define a partial ordering on those extensions wrt. that member invocation, so that we can choose the "best" candidate which will have its extension member be implicitly invoked.

Let *i* be a member invocation with target expression `e` and corresponding member name *m*, and let `E1` and `E2` denote different accessible and applicable extensions for *i*. Let *T<sub>1</sub>* be the instantiated "on" type of `E1` wrt. `e` and let *T<sub>2</sub>* be the instantiated "on" type of `E2` wrt. `e`. Then `E1` is more specific than `E2` wrt. *i* iff:

1. The `E2` extension is declared in a platform library and the `E1` extension is not, or
2. either both or neither are declared in platform libraries and
3. *T<sub>1</sub>* is a subtype of of *T<sub>2</sub>* and either
4. not vice versa, or
5. the instantiate-to-bounds `on` type of `E1` is a subtype of the instantiate-to-bounds `on` type of `E2` and not vice versa.

This definition ensures that "more specific than" is a partial order (anti-symmetric and transitive) relation.

##### Examples

The following examples display the implicit extension resolution when multiple applicable extensions are available.

Example:

```dart
extension SmartIterable<T> on Iterable<T> {
  void doTheSmartThing(void Function(T) smart) {
    for (var e in this) smart(e);
  }
}
extension SmartList<T> on List<T> {
  void doTheSmartThing(void Function(T) smart) {
    for (int i = 0; i < length; i++) smart(this[i]);
  }
}
...
  List<int> x = ....;
  x.doTheSmartThing(print);
```

Here both the extensions apply, but the `SmartList` extension is more specific than the `SmartIterable` extension because `List<dynamic>` &lt;: `Iterable<dynamic>`.

Example:

```dart
extension BestCom<T extends num> on Iterable<T> { T best() {...} }
extension BestList<T> on List<T> { T best() {...} }
extension BestSpec on List<num> { num best() {...} }
...
  List<int> x = ...;
  var v = x.best();
  List<num> y = ...;
  var w = y.best();
```

Here all three extensions apply to both invocations.

For `x.best()`, the most specific one is `BestList`. Because `List<int>` is a proper subtype of both ` iterable<int>` and `<List<num>`, we expect `BestList` to be the best implementation. The return type causes `v` to have type `int`. If we had chosen `BestSpec` instead, the return type could only be `num`, which is one of the reasons why we choose the most specific instantiated type as the winner. 

For `y.best()`, the most specific extension is `BestSpec`. The instantiated `on` types that are compared are `Iterable<num>` for `Best
Com` and `List<num>` for the two other. Using the instantiate-to-bounds types as tie-breaker, we find that `List<Object>` is less precise than `List<num>`, so the code of `BestSpec` has more precise information available for its method implementation. The type of `w` becomes `num`.

In practice, unintended extension method name conflicts are likely to be rare. Intended conflicts happen where the same author is providing more specialized versions of an extension for subtypes, and in that case, picking the extension which has the most precise types available to it is considered the best choice.

### Static Members and Member Resolution

Static member declarations in the extension declaration can be accessed the same way as static members of a class or mixin declaration: By prefixing with the extension's name.

Example:

```dart
extension MySmart on Object {
  smart() => smartHelper(this);  // valid
  static smartHelper(Object o) { ... }
}
...
  MySmart.smartHelper(someObject);  // valid
```

Like for a class or mixin declaration, static members simply treat the surrounding declaration as a namespace.

It is a **compile-time error** if a simple or qualified identifier denoting the extension occurs in an expression except as the extension name of an extension application or as the target of a (static) simple or composite member invocation. In the latter case, it is a **compile-time error** if the extension does not declare a static member with the corresponding member name (or both a getter and a setter for a composite member invocation), and the invocation itself must be a valid invocation as for any other static member invocation.

### Semantics of Invocations

An extension member invocation is a member invocation where the target is an extension application, or where the target is an object where we perform implicit extension application. At run-time, implicit extension invocations have been resolved and any type arguments will have been inferred, so we can assume they are all known.

Evaluating the invocation performs a method invocation of the corresponding instance member of the extension, with `this` bound to the receiver value and type parameters (both for the extension and for the member itself, if that is generic) bound to the types found by static inference.

Prior to NNBD, all extension members can be invoked on a `null` value. Since `null` is a subtype of the `on` type, this is consistent behavior.

Post-NNBD, a non-nullable `on` type would not match a nullable receiver type, so it is impossible to invoke an extension method that does not expect `null` on a `null` value.

During NNBD migration, where a non-nullable type or a legacy unsafely nullable type may contain `null` , it is a run-time error if a migrated extension with a non-nullable `on` type is called on `null`, just as all other cases where an unsafe `null` reaches a non-nullable context. This requires a run-time check which can be omitted when all non-NNBD code has been migrated.

### Semantics of Extension Members

When executing an extension instance member, we stated earlier that the member is invoked with the original receiver as `this` object. We still have to describe how that works, and what the lexical scope is for those members.

Inside an extension method body, `this` does not refer to an instance of a surrounding type. Instead it is bound to the original receiver, and the static type of `this` is the declared `on` type of the surrounding extension.

Invocations on `this` use the same extension method resolution as any other code. Most likely, the current extension will be the only one in scope which applies. It definitely applies to its own declared `on` type.

Like for a class or mixin member declaration, the names of the extension members, both static and instance, are in the *lexical* scope of the extension member body. That is why `MySmart` above can invoke the static `smartHelper` without prefixing it by the extension name. In the same way, *instance* member declarations (the extension members) are in the lexical scope. 

If an unqualified identifier inside an extension instance member lexically resolves to an extension member of the surrounding extension (if the nearest enclosing declaration with the same basename is an instance member of an extension), then that identifier is not equivalent to `this.id`, rather the invocation is equivalent to an explicit invocation of that extension method on `this` (which we already know has a compatible type for the extension): `Ext<T1,…,Tn>(this).id`, where `Ext` is the surrounding extension and `T1` through `Tn` are its type parameters, if any. The invocation works whether or not the names of the extension or parameters are actually accessible, it is not a syntactic rewrite.

If an unqualified identifier inside an extension *static* member lexically resolves to an extension member, it is a **compile-time error**. This is similar to how a static member cannot access instance members of the same class by name.

Example:

```dart
extension MyUnaryNumber on List<Object> {
  bool get isEven => length.isEven;
  bool get isOdd => !isEven;
  static bool isListEven(List<Object> list) => list.isEven;
}
```

Here the `list.isEven` will find that `isEven` of `MyUnaryNumber` applies, and unless there are any other extensions in scope, it will call that. (Or unless someone adds an `isEven` member to `List`, but that's a breaking change, and then, if still necessary, this code can change the call to `MyUnaryNumber(list).isEven`.)

The unqualified `length` of `isEven` is not defined in the current lexical scope, so is equivalent to  `this.length`, which is valid since `List<Object>` has a `length` getter.

The unqualified `isEven` of `isOdd` resolves lexically to the `isEven` getter above it, so it is equivalent to `MyUnaryNumber(this).isEven`,  even if there are other extensions in scope which define an `isEven` on `List<Object>`.

An unqualified identifier `id` which is not declared in the lexical scope at all, is considered equivalent to `this.id` inside instance members as usual. It is subject to extension if `id` is not declared by the static type of `this` (the `on` type).

Even though you can access `this`, you cannot use `super` inside an extension method.

### Member Conflict Resolution

An extension can declare a member with the same (base-)name as a member of the type it is declared on. This does not cause a compile-time conflict, even if the member does not have a compatible signature.

Example:

```dart
extension MyList<T> on List<T> {
  void add(T value, {int count = 1}) { ... }
  void add2(T value1, T value2) { ... }
}
```

You cannot *access* this member in a normal invocation, so it could be argued that you shouldn't be allowed to add it. We allow it because we do not want to make it a compile-time error to add an instance member to an existing class just because an extension is already adding a method with the same name. It will likely be a problem if any code *uses* the method, but only that code needs to change (perhaps using an override to keep using the extension).

An unqualified identifier in the extension can refer to any extension member declaration, so inside an extension member body, `this.add` and `add` are not necessarily the same thing (if the `on` type has an `add` member, then `this.add` refers to that, while `add` refers to the extension method in the lexical scope). This may be confusing. In practice, extensions will rarely introduce members with the same name as their `on` type's members.

### Tearoffs

A static extension method can be torn off like an instance method.

```dart
extension Foo on Bar {
  int baz<T>(T x) => x.toString().length;
}
...
  Bar b = ...;
  int Function(int) func = b.baz;
```

This assignment does a tear-off of the `baz` method. In this case it even does generic specialization, so it creates a function value of type `int Function(int)` which, when called with argument `x`, works just as `Foo(b).baz<int>(x)`, whether or not`Foo` is in scope at the point where the function is called. The torn off function closes over both the extension method, the receiver, and any type arguments to the extension, and if the tear-off is an instantiating tear-off of a generic method, also over the type arguments that it is implicitly instantiated with. The tear-off effectively creates a curried function from the extension:

```dart
int Function(int) func = (int x) => Foo(b).baz<int>(x);
```

*Torn off extension methods are never equal unless they are identical*. Unlike instance methods, which are equal if it's the same method torn off from the same object (unless it's an instantiated tear-off of a generic function), torn off extension methods may close over the type variables of the extension as well. To avoid distinction between generic and non-generic extensions, no two torn off extension methods are equal, even if they are torn off from the same extension on the same object at the same static type.

An extension method torn off a *constant* receiver expression is not a constant expression. It creates a new function object each time the tear-off expression is evaluated.

An explicit extension method application member invocation like `Foo<Bar>(b).baz`, also creates a tear-off if `Foo.baz` is an extension method.

There is still no way to tear off getters, setters or operators. If we ever introduce such a feature, it should work for extension methods too.

### The `call` Member

A class instance method named `call` is implicitly callable on the object, and implicitly torn off when assigning the instance to a function type.

As the initial examples suggest, an extension method named `call` can also be called implicitly. The following must work:

```dart
extension Tricky on int {
  Iterable<int> call(int to) => 
      Iterable<int>.generate(to - this + 1, (i) => i + this);
}
...
  for (var i in 1(10)) { 
    print(i);  // prints 1, 2, 3, 4, 5, 6, 7, 8, 9, 10.
  }
```

This looks somewhat surprising, but not much more surprising that an extension `operator[]` would: `for (var i in 1[10])...`. We will expect users to use this power responsibly.

In detail: Any expression of the form `e1(args)` or `e1<types>(args)` where `e1` does not denote a method, and where the static type of `e1` is not a function type, an interface type declaring a `call` method, or `dynamic,` will currently be a compile-time error. If the static type of `e1` is an interface type declaring a `call` *getter* or a `call=` *setter*, then this stays a compile-time error (the interface has a member with basename `call`). Otherwise we check for extensions applying to the static type of `e1` and declaring a `call` member. If one such most specific extension exists, and it declares a `call` extension *method*, then the expression is equivalent to `e1.call(args)` or `e1.call<typeS>(args)`. Otherwise it is still a compile-time error.

A second question is whether this would also work with implicit `call` method tear-off:

```dart
Iterable<int> Function(int) from2 = 2; // Erroneous code!
```

This code will find, during type inference, that `2` is not a function. It will then find that the interface type `int` does not have a `call` method, and inference will fail to make the program valid.  

We could allow an applicable `call` extension method to be coerced instead, as an implicit tear-off. We will not do so.

That is: We do *not* allow implicit tear-off of an extension `call` method in a function typed context.

This implicit conversion would come at a readability cost. A type like `int` is well known as being non-callable, and an implicit `.call` tear-off would have no visible syntax at the tear-off point to inform the reader what is going on. For implicit `call` invocations, the *arguments* are visible to a reader, but for implicit coercion to a function, there is no visible syntax at all.

## Migration and Breaking Changes

Introduction of static extension methods is a non-breaking change to the language. No existing correct programs will change behavior.

### Breaking Changes for Extension Methods

Introducing a new extension to an existing library has the same problems as adding any other top-level name: A potential naming conflict. It may also change the behavior of existing extension member invocations if it causes an extension resolution conflict, and it wins by being more specific than the currently used extension. Barring an extension member conflict, adding an extension will not change the behavior of any code that isn't already a compile-time error. The choice of making interface instance members take precedence over extension methods ensures this.

Adding an instance member to a class may now change behavior of code relying on extension methods. Adding instance members to interfaces is already breaking in case someone implements the interface. With extension methods, it may be breaking even for classes that are never implemented.

## Interaction With Potential Future Features

### Non-Null by Default

The interaction with NNBD was discussed above. It will be possible to declare extensions on nullable and non-nullable types, and only on a nullable type can `this` be bound to `null`. Null-aware extension member invocations, both explicit and implicit, will evaluate the receiver expression first, and then only apply the extension to a non-null value.

### Sealed Classes

If we introduce sealed classes, we may want to consider whether to allow extensions on sealed classes, since adding members even to a sealed class could still be a breaking change.

One of the reasons for having sealed classes is that it ensures the author can add to the interface without breaking code. If adding a member changes the meaning of code which currently calls an extension member, that reason is eliminated. 

Since it's possible to add extensions on superclass (including `Object`), it would not be sufficient to disallow *declaring* extensions on a sealed class, you would have to disallow *invoking* an extension on a sealed class, at least without an explicit override (which would also prevent breaking if a similarly named instance member is added).

## Summary

- Extensions are declared using the syntax:

  ```ebnf
  <extension> ::= `extension' <identifier>? <typeParameters>? `on' <type>
     `{'
       <memberDeclaration>*
     `}'
  
  ```

  where `extension` becomes a built-in identifier and `<memberDeclaration>` does not allow instance variables, constructors or abstract members. It does allow static members.

- The extension declaration introduces a name (`<identifier>`) into the surrounding scope. 

  - The name can be shown or hidden in imports/export. It can be shadowed by other declarations as any other top-level declaration.
  - The name can be used as prefix for invoking static members (used as a namespace, same as class/mixin declarations).

- A member invocation (getter/setter/method/operator) which targets a member that is not on the static type of the receiver (no member with same base-name is available) is subject to extension application.  It would otherwise be a compile-time error.

- An extension applies to such a member invocation if 

  - the extension is declared or imported by the current library,
  - the extension declares an instance member with the same base name, and 
  - the `on` type (after type inference) of the extension is a super-type of the static type of the receiver.

- Type inference for `extension Foo<T> on Bar<T> { baz<S>(params) => ...}` for an invocation `receiver.baz(args)` is performed as if the extension was a class:

  ```dart
  class Foo<T> {
    Bar<T> _receiver;
    Foo(this._receiver);
    void baz<S>(params) => ...;
  }
  
  ```

  that was invoked as `Foo(receiver).baz(args)`. The binding of `T` and `S` found here is the same binding used by the extension.  If the constructor invocation would be a compile-time error, the extension does not apply.

- One extension is more specific than another if the former is a non-platform extension and the latter is a platform extension, or if the instantiated `on` type of the former is a proper subtype of the instantiated `on` type of the latter, or if the two instantiated types are equivalent and the instantiate-to-bounds `on` type of the former is a proper subtype of the one on the latter. 

- If there is no single most-specific extension which applies to a member invocation, then it is a compile-time error. (This includes the case with no applicable extensions, which is just the current behavior).

- Otherwise, the single most-specific extension's member is invoked with the extension's type parameters bound to the types found by inference, and with `this ` bound to the receiver.

- An extension method can be invoked explicitly using the syntax `ExtensionName(object).method(args)`. Type arguments can be applied to the extension explicitly as well, `MyList<String>(listOfString).quickSort()`. Such an invocation overrides all extension resolution. It is a compile-time error if `ExtensionName` would not apply to the `object.method(args)` invocation if it was in scope. 

- An invocation of an extension method succeeds even if the receiver is `null`. With legacy NNBD types, the invocation throws if the receiver is `null` and the instantiated `on` type of the selected extension does not accept `null`, which can only happen if the extension is declared in NNBD code. For full NNBD types, an extension with a non-nullable `on` type is not applicable to a nullable receiver.

- Otherwise an invocation of an extension method runs the instance method with `this` bound to the receiver and with type variables bound to the types found by type inference (or written explicitly for an override invocation). The static type of `this` is the `on` type of the extension.

- Inside an instance extension member, extension members accessed by unqualified name are treated as extension override accesses on `this`. Otherwise invocations on `this` are treated as any other invocations on the same static type.

## Revisions

#### 1.0

- Initial version.

#### 1.1:

- Removed `?` after types. The behavior was subtly inconsistent with the eventual NNBD behavior of a nullable type. Instead all extensions can be invoked on `null` until we get NNBD.
- Specified that override syntax like `MyList(o)` can only be used for member access, not as an expression with a value.

#### 1.2:

- Specified that `Ext(o)` also cannot be used with `+=` or `++`.
- Specify that extension members cannot have the same name as object members.
- Specfiy that `extension` is a built-in identifier, and `on` is not.
- Specify that the name of an extension must not be a built-in identifier.

#### 1.3:

- Elaborate on naming conflict rules.
- Elaborate on explicit member access.
- `Ext(o).x += v` and `Ext(o).x++` can be used.

#### 1.4:

- Remove optional variants that were not part of the final design.

#### 1.5

- Post 2.6 release modification to allow non-deferred prefix-imported extensions to work.
- Removed discussion of interaction with language versioning since extension methods launched before language versioning.
- Disallow deferred imports of extensions by requiring the import statement to hide them.

#### 1.6

* Allow `Ext(e)?.foo` and `Ext(e)?.[e2]` and specify their meaning.
