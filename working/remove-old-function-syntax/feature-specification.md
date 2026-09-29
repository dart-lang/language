# Remove Old Function Syntax

Author: Bob Nystrom

Status: In-progress

Version 0.1 (see [CHANGELOG](#CHANGELOG) at end)

Experiment flag: remove-old-function-syntax

Remove the long-deprecated pre-2.0 syntax for function-typed parameters and
function typedefs ([#2901][], [#2517][]).

[#2901]: https://github.com/dart-lang/language/issues/2901
[#2517]: https://github.com/dart-lang/language/issues/2517

## Introduction

In a statically typed language like Dart, every value that exists in the
language has some corresponding static type (or types) that contain it. The user
usually has a way to write that type explicitly in a type annotation. Those
annotations can appear on variable declarations, function parameters, function
return types, type arguments, etc.

For example, Dart has integers like `123` and a user can write `int` to declare
a variable that holds an integer. Likewise, Dart has always had first-class
functions ("lambdas", "closures", "callbacks", etc.). But when the language was
first launched, it had no type annotation syntax for a function type. If you
wanted to, say, store a callback in an instance variable, there was nothing you
could write at that variable's declaration to describe the callback functions's
type.

This is obviously a problem for a language that does have first-class functions,
so Dart 1.0 had two workarounds:

### Function-typed parameters

When declaring a parameter for a function, there was a syntax to give that
parameter a function type. For example:

```dart
class Iterable<E> {
  Iterable<E> where(bool test(E element) { ... }
}
```

Here, the `where()` method takes a single parameter named `test` whose type is
`bool Function(E)`. Note how the parameter's name is stuffed in the middle of
the syntax for specifying its type. This may look familiar to users coming from
C with its unusual ["declaration reflects use"][c wtf] syntax.

[c wtf]: https://softwareengineering.stackexchange.com/questions/117024/why-was-the-c-syntax-for-arrays-pointers-and-functions-designed-this-way

### Function typedefs

Most values in Dart are instances of classes so most type annotations are simply
the name of the class (with maybe some type arguments applied). Dart 1.0
extended that to work with function types by having a `typedef` syntax that let
you define a named alias for a function type:

```dart
typedef int Measure(String text);
```

Here, `Measure` is now an alias for a function that takes a positional string
argument named `text` and returns an `int`. Now you can use `Measure` anywhere
you want to refer to that function type.

As with function-typed parameters, note that the name being declared is mixed
into the middle of the function type.

This syntax is also unfortunately error prone. In a function type, a positional
parameter name doesn't do anything. It's only for documentation purposes. Given
that, you might consider omitting it:

```dart
typedef int Measure(String);
```

This is valid, but not what you want. It declares `Measure` to be a function
that takes a parameter of *type `dynamic`* whose *name* is `String`. And,
because `dynamic` accepts values of all types, the compiler will rarely help you
if you make this mistake. You just silently get worse type checking.

### Real function types and typedefs

In [Dart 2][], we shipped a richer, strong static type system. A change relevant
to this proposal is that it added support for generic methods and first-class
generic functions. The existing function typedef syntax did not work well with
those. The language did support generic *typedefs*, but it was the typedef
itself that accepted type arguments. There was no way to create an alias to a
generic function type. And, since there was also no other way to write a
function type in many places, that meant there was no way to write a type
annotation for a generic function type at all.

[dart 2]: https://dart.dev/blog/announcing-dart-2-optimized-for-client-side-development

(Also, frankly, the original design wasn't great. In a language with first-class
functions and static types, users really should be able to just *write the type
of a function* wherever they want.)

Dart 2.0 fixed this by adding a real function type syntax:

```dart
class Iterable<E> {
  Iterable<E> where(bool Function(E element) test { ... }
}
```

Here, `bool Function(E element)` is a type annotation for a function type that
takes an `E` and returns `bool`. If you omit the name of a parameter (`bool
Function(E)`), the function type still takes an `E`, not `dynamic`.

Dart 2.0 also add a more generalized `typedef` that allows you to define an
alias for any type: function types, generic function types, classes,
instantiations of generic classes, etc.:

```dart
typedef Measure = int Function(String);
typedef ListOfInts = List<int>;
typedef Text = String;
```

These two features -- function type annotations and generalized typedefs --
completely supersede the older function-type parameters and function typedefs.
They can express everything the old syntax could express and more, and they
don't have the hazard of omitting a parameter name and silently getting
`dynamic` instead of an unnamed but typed parameter.

Admittedly, the old syntax is more concise. But it gets that at the expense of
being unfamiliar to users coming from most languages, not supporting all use
cases, and forcing users to often write aliases for function types. The new
syntax is simpler, regular, works everywhere, more expressive, and less
error-prone.

### Usage

We think the new syntax is so much better for the Dart ecosystem that as soon
as Dart 2.0 shipped, we started discouraging users from using the old features
in favor of the new ones. That encouragement seems to have worked. I analyzed
2,000 pub packages (21,981,565 lines in 104,253 files).

Old style function-typed parameters are rare:

```
-- Parameter (1769762 total) --
1768775 ( 99.944%): Normal parameter  ==========================================
    987 (  0.056%): Function-typed    =
```

Even when the parameter type is a function type, most use the new syntax:

```
-- Parameter with function type (25488 total) --
  24501 ( 96.128%): New syntax  ===============================================
    987 (  3.872%): Old syntax  ==
```

Of those 987 occurrences, 766 (77.609%) are in code generated by the freezed
package. A fix to the freezed code generator would fix all of them.

Likewise, old-style function typedefs are rare:

```
-- Typedef (15869 total) --
  15663 ( 98.702%): New syntax  ================================================
    206 (  1.298%): Old syntax  =
```

Most of those 206 occurrences are in a handful of packages.

I also analyzed all of the Dart code inside Google. We don't publicly publish
detailed code size stats of Google's internal codebase but the numbers were
similar. 95% of parameters that have a function type use the new syntax. Almost
all of those are in the Dart SDK itself or other packages the Dart team
maintains. 98% of typedefs use the new syntax.

### Simplifying

I think it's time to remove the old syntax. It should be a language-versioned
change to avoid breaking users. When they update to the latest version, they
will have to migrate off the old function syntax before they do. They can do
this easily using `dart fix`.

Eventually, we would like the benefit of not having to support the syntax in the
implementations of our various tools. Since the SDK supports older language
versions which still support the old function syntax, we won't get that benefit
immediately. But, eventually, we will ship a major version of the Dart SDK that
drops support for all of the language versions that allow the old function
syntax. When that happens, we can remove it for real. If we ever want to get to
that point, we have to start with making the syntax an error first.

Even before we get there, there is benefit to disallowing the syntax. Many
language features touch the parameter list grammar. Recent ones include [super
parameters][], [private named parameters][], and [primary constructors][]. We've
discussed future features like [destructuring in parameter lists][],
[varargs][], and [non-constant default values][]. Removing the old
function-typed parameter syntax frees up space in the parameter list grammar for
other new language features like those.

[super parameters]: https://github.com/dart-lang/language/blob/master/accepted/2.17/super-parameters/feature-specification.md
[private named parameters]: https://github.com/dart-lang/language/blob/main/accepted/3.12/private-named-parameters/feature-specification.md
[primary constructors]: https://github.com/dart-lang/language/blob/main/accepted/3.13/primary-constructors/feature-specification.md
[destructuring in parameter lists]: https://github.com/dart-lang/language/issues/3001
[varargs]: https://github.com/dart-lang/language/issues/1014
[non-constant default values]: https://github.com/dart-lang/language/issues/140

I don't think it's sustainable to add complexity to the language forever. If we
want to eventually claw back some simplicity, we have to start making old
deprecated features an error so that we can eventually remove them completely
when their language versions are no longer supported by the SDK.

## Proposal

This feature is strictly a removal, so there are no new static or dynamic
semantics. Everything the old syntax can express can be expressed using newer
better syntax, so there is no loss of expressive power.

## Syntax

Probably the clearest way to show the grammar changes is a diff:

```diff
 // Function-typed parameters:
 normalFormalParameterNoMetadata ::=
-    functionFormalParameter |
     fieldFormalParameter |
     simpleFormalParameter |
     superFormalParameter

-functionFormalParameter ::=
-    'covariant'? type? identifier formalParameterPart '?'?
-
 fieldFormalParameter ::=
-    type? 'this' '.' identifier (formalParameterPart '?'?)?
+    type? 'this' '.' identifier

 superFormalParameter ::=
-    type? 'super' '.' identifier (formalParameterPart '?'?)?
+    type? 'super' '.' identifier

 declaringFormalParameterNoMetadata ::=
-    declaringFunctionFormalParameter |
     fieldFormalParameter |
     declaringSimpleFormalParameter |
     superFormalParameter

-declaringFunctionFormalParameter ::=
-    'covariant'? ('var' | 'final')? type? identifier formalParameterPart '?'?
-
 // Function typedefs:
 typeAlias ::=
-    'typedef' typeWithParameters '=' type ';' |
-    'typedef' functionTypeAlias
-
-functionTypeAlias ::= functionPrefix formalParameterPart ';'
+    'typedef' typeWithParameters '=' type ';'
```

Or, in prose:

*   From `normalFormalParameterNoMetadata`, remove the `functionFormalParameter`
    branch.
*   Remove the `functionFormalParameter` rule.
*   From `fieldFormalParameter` and `superFormalParameter`, remove the trailing
    `(formalParameterPart '?'?)?`.
*   From `declaringFormalParameterNoMetadata`, remove the
    `declaringFunctionFormalParameter` branch.
*   Remove the `declaringFunctionFormalParameter` rule.
*   From `typeAlias`, remove the `'typedef' functionTypeAlias` branch.
*   Remove the `functionTypeAlias` rule.

## Compatibility and migration

This is a language versioned change, so no existing code is broken by this
proposal, not even code that uses the old syntax. Only when a user upgrades to
the Dart version this proposal ships in do they have to migrate off the old
syntax.

### Lints and quick fixes

We already have lints to help users move off the old syntax:

*   [`use_function_type_syntax_for_parameters`][use_function_type_syntax_for_parameters]:
    warns when a user uses a function-typed parameter. This lint is in the
    recommended lints.

*   [`prefer_generic_function_type_aliases`][prefer_generic_function_type_aliases]
    warns when a user uses the old function typedef syntax. This lint is in the
    core lint set.

[use_function_type_syntax_for_parameters]: https://dart.dev/tools/linter-rules/use_function_type_syntax_for_parameters

[prefer_generic_function_type_aliases]: https://dart.dev/tools/linter-rules/prefer_generic_function_type_aliases

Both lints have existed for at least five years. Core lints affect package
scoring so users are strongly encouraged to avoid the lint firing. Both lints
have an associated quick fix that will mechanically migrate the offending code
to the newer general syntax. Migrating your code off the removed syntax is as
simple as running `dart fix`.

### SDK code libraries

Our own core library implementations still use the old function-typed parameter
syntax. (I believe Lasse likes it because it's more concise.) We will have to
migrate that. Again, that's just a matter of re-enabling the lint and running
`dart fix`.

### Dartdoc

When Dartdoc generates documentation for a parameter whose type is a function
type, the generated documentation uses the old function-typed parameter syntax.
It does this regardless of what source syntax the user wrote. Even if they use
a parameter type like `void Function() foo`, the generated docs will look like
`void foo()`. [Here][group] is an example of a function in the test package.

[group]: https://pub.dev/documentation/test/latest/test/group.html

We should definitely fix this. In fact, we should fix this even if we decide not
to ship this proposal, since Dartdoc is generating a syntax that our lints tell
users not to use and that users may not be familiar with. There is [an existing
issue][3671] for this.

[3671]: https://github.com/dart-lang/dartdoc/issues/3671

## Changelog

### 0.1

-   Initial draft.
