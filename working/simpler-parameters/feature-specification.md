# Simpler Parameters

Author: Bob Nystrom

Status: In-progress

Version 0.1 (see [CHANGELOG](#CHANGELOG) at end)

Experiment flag: simpler-parameters

Simplify parameter lists with consistent, orthogonal syntax to specify calling
convention and optionality. Eliminate restrictions around optional parameters.

## Background

Since function calls are so central to programming, Dart provides flexibility in
how functions are authored and called. When you define a function, for each
parameter you control:

*   **Calling convention:** Whether the argument is passed by position or by
    name.

*   **Optionality:** Whether an argument must be passed for the parameter or
    whether the callsite can omit it.

*   If the parameter is optional, then a **default value** to use for the
    parameter if no argument is passed.

(In constructors, a parameter may also use `this.`, `super.`, or `covariant`
but we'll ignore those here.)

Having a good notation to control all of that is more difficult in Dart because
these features were added over time. The language initially supported only
mandatory positional parameters, like C or Java:

```dart
f(int x, String y) {}
```

Later, the language gained support for optional parameters. A user had to choose
whether all of those optional parameters were passed positionally or by name:

```dart
f(int x, [int y, int z]) {} // Optional positional.
g(int x, {int y, int z}) {} // Optional named.
```

If there are multiple optional positional parameters, arguments fill them in
from left to right. There's no way to omit an earlier parameter while passing a
later one. Named parameters were added largely to work around this restriction
and were less about making the callsite more readable by having names visible
there.

C++, C#, JavaScript, PHP, Python, Swift, Scala, and other languages use the
presence of a default value expression to make a parameter optional. When we
added optional parameters to Dart, all types were nullable, even primitive types
(unlike some of these other languages). Since `null` is the most common default
value, the `[...]` and `{...}` syntax makes sense: it gives users a way to
specify multiple optional parameters without having to write `= null` on every
one.

Then we added null safety. Many existing named parameters now had non-nullable
types and no obvious way for users to provide a default value for them. In
practice, these parameters were effectively mandatory, with a `@required`
metadata annotation and a lint that enforced that callsites passed arguments. In
order to make those parameters actually sound, we added support for true
required named parameters. We chose a `required` modifier in part because it was
close to the annotation already in use.

The end result of this incremental evolution is inconsistency:

*   Positional parameters are mandatory by default and have to opt into being
    optional. Meanwhile, named parameters are optional by default and have to
    opt into being mandatory.

*   The `[...]` section syntax specifies the *optionality* of positional
    parameters. Meanwhile, the `{...}` section syntax specifies the *calling
    convention* of named parameters.

*   One syntax (`[...]`) makes an entire series of positional parameters
    optional. Meanwhile the `required` keyword only makes one named parameter
    mandatory.

Each incremental step [made sense at the time][path dependence] but led us to an
overall syntax that is inconsistent. The additional syntax used for constructor
parameters add more complexity.

If we add support for [primary constructors][], they will exacerbate the issue.
They will push all of this parameter list complexity into already-crowded class
headers and add more parameter syntax for controlling whether a parameter
declares a field or not and, if so, whether the field is `final`.

[path dependence]: https://en.wikipedia.org/wiki/Path_dependence

[primary constructors]: https://github.com/dart-lang/language/blob/main/working/2364%20-%20primary%20constructors/feature-specification.md

Compared to other languages, there is only so much we can do. Bifurcating
parameters into positional and named sets requires users to have a syntax to
control which set a parameter goes into. That choice has real upsides:

*   It lets the function author decide *once* whether a given parameter is
    passed by position or by name instead of users having to decide at each of
    the potentially many callsites whether to use a positional or named
    argument.

*   It makes it possible to add new named parameters to an existing function,
    in any syntactic order in the parameter list, without breaking any existing
    code. (Other languages often address this by supporting overloading, but
    that's another can of worms.)

This proposal tries to strike a balance. It retains the essential semantics of
parameter lists which separate positional and named ones. Because of that, it
still carries some syntactic complexity to specify those.

But it otherwise simplifies and rationalizes the parameter syntax:

*   Calling convention is always specified by a delimited section.

*   Optionality is specified on a per-parameter basis, using the same syntax
    regardless of calling convention. No more unloved `required` keyword or
    uncommon `[...]` section.

    Instead, we follow other languages and use the presence of a default value
    to mark a parameter as optional. This should be more familiar to users
    coming from other languages. Perhaps it will also make it easier for LLMs to
    understand and generate Dart code.

While we're at it, the proposal also removes the restriction around optional
parameters and allows a function to have both optional positional and named
parameters ([#1076][both]).

Here's a real-world example today:

```dart
class InsuranceCatalogItem extends StatefulWidget {
  InsuranceCatalogItem({
    required this.texts,
    this.iconColor = Colors.black,
    required this.cardBackgroundColor,
    this.insuranceImagePath = '',
    this.moreInformationFunction,
  });

  final List<String> texts;
  final Color iconColor;
  final Color cardBackgroundColor;
  final String insuranceImagePath;
  final Function()? moreInformationFunction;

  ...
}
```

With primary constructors, it would look like:

```dart
class InsuranceCatalogItem({
  required final List<String> texts,
  final Color iconColor = Colors.black,
  required final Color cardBackgroundColor,
  final String insuranceImagePath = '',
  final Function()? moreInformationFunction,
}) extends StatefulWidget {
  ...
}
```

Better, but the resulting parameter list is pretty cluttered. When combined
with this proposal, the result is:

```dart
class InsuranceCatalogItem({
  final List<String> texts,
  final Color iconColor = Colors.black,
  final Color cardBackgroundColor,
  final String insuranceImagePath = '',
  final Function()? moreInformationFunction =,
}) extends StatefulWidget {
  ...
}
```

## Proposal

While the proposal is holistic, it's easiest to explain the changes separately.

### Default value indicates optionality

A parameter is made optional by adding `=` followed by a default value
expression:

```dart
// Current:
f(int a, [int b = 1, int c = 2]) {}

// Proposed:
f(int a, int b = 1, int c = 2) {}
```

As in Dart today, parameters immediately inside the parentheses of the parameter
list are positional. Since the default value marks the parameter as optional
(and thus optional positional), we no longer need the `[...]` delimiter syntax
and remove it from the language.

We continue to use a `{...}` section for named parameters. But inside that
section, again, the presence of a default value determines whether a parameter
is required or optional:

```dart
// Current:
f(int a, {required int b, int c = 2}) {}

// Proposed:
f(int a, {int b, int c = 2}) {}
```

### No non-trailing optional positional parameters

Not using a section for optional positional parameters means the syntax allows
a user to write a non-trailing optional positional parameter:

```dart
f(int a = 1, int b) {}
```

We forbid that. It's a **compile-time error** if a mandatory positional
parameter follows an optional positional parameter.

*C++ and C# have the same restriction. We could support non-trailing optional
parameters. The old [parameter freedom][] proposal works through all of the
semantics to make this make sense, including parameter binding and subtyping.
But given that named parameters are increasingly common in Dart, I think places
where non-trailing optional parameters would be useful are just as well served
by using named parameters.*

[parameter freedom]: https://github.com/munificent/ui-as-code/blob/master/in-progress/parameter-freedom.md

### Both named and optional parameters

When optional parameters were first added to the language, the language team
added a restriction to only allow them to be either all positional or all named.
Users [immediately requested the limitation be lifted][both]. This 13-year-old
issue is the #11 most requested feature on the language repo.

[both]: https://github.com/dart-lang/language/issues/1076

The limitation causes real problems for API maintainers. Optional positional
parameters are rarely used because API authors know that if they ship an API
that uses one, they can never add a named parameter to that function. I've heard
accounts of API maintainers making an optional parameter named that they would
prefer to be positional, just so that they are able to add other named
parameters later.

Since the proposed syntax no longer uses a delimited section for optional
positional parameters, it seems like a good time to remove this restriction too.
We allow a parameter list to have both positional and named parameters, and any
number of parameters in either or both of those sections can be optional:

```dart
f(int a, int b = 0, int c = 0, {int d = 0, int e, int f = 0, int g}) {}
```

### Corresponding syntax in function types

The previous sections describe syntax changes in function *declarations*. We
also need corresponding changes in function *type annotation* syntax. The
changes are similar but not quite the same because you can't specify a default
value in a function type. Therefore, instead of using `=` followed by an default
value expression to mark a parameter as optional, we use just a trailing `=`:

```dart
// Current:
typedef F = f(int a, [int b]);
typedef G = g({required int c, int d});

// Proposed:
typedef F = f(int a, int b =);
typedef G = g({int c, int d =});
```

I admit, a bare `=` is unusual. I believe it's fairly intuitive. Likely more
intuitive than using `[...]` to mean "optional positional" and `{...}` to mean
"named" and users tolerate that.

### Default default value of `null`

In practice, when a parameter is optional, the default value is `null` about 80%
of the time. The current parameter syntax does a nice job of optimizing for that
case. This proposal makes that more verbose by requiring `= null`.

If we are going to make users get used to a dangling `=` in function types
anyway, we can also allow that syntax in a function declaration and treat it as
a tiny syntactic sugar for `= null`.

For example, here's some code today:

```dart
Widget buildFrame({
  Key? tabBarKey,
  bool secondaryTabBar = false,
  required List<String> tabs,
  required String value,
  bool isScrollable = false,
  Color? indicatorColor,
  Duration? animationDuration,
  EdgeInsetsGeometry? padding,
  TextDirection textDirection = TextDirection.ltr,
  TabAlignment? tabAlignment,
  TabBarThemeData? tabBarTheme,
  Decoration? indicator,
  bool? useMaterial3,
}) {}
```

With this proposal, it becomes:

```dart
Widget buildFrame({
  Key? tabBarKey = null,
  bool secondaryTabBar = false,
  List<String> tabs,
  String value,
  bool isScrollable = false,
  Color? indicatorColor = null,
  Duration? animationDuration = null,
  EdgeInsetsGeometry? padding = null,
  TextDirection textDirection = TextDirection.ltr,
  TabAlignment? tabAlignment = null,
  TabBarThemeData? tabBarTheme = null,
  Decoration? indicator = null,
  bool? useMaterial3 = null,
}) {}
```

We eliminate two `required`, but we add eight `= null`. If we allow omitting
the `null`, then it's:

```dart
Widget buildFrame({
  Key? tabBarKey =,
  bool secondaryTabBar = false,
  List<String> tabs,
  String value,
  bool isScrollable = false,
  Color? indicatorColor =,
  Duration? animationDuration =,
  EdgeInsetsGeometry? padding =,
  TextDirection textDirection = TextDirection.ltr,
  TabAlignment? tabAlignment =,
  TabBarThemeData? tabBarTheme =,
  Decoration? indicator =,
  bool? useMaterial3 =,
}) {}
```

Obviously, this isn't a huge improvement, and we could choose to *not* add this
tweak, but I believe it's worth it.

## Syntax

We make a few changes to the grammar for parameter lists in function
declarations and in function type annotations.

### Function declarations

The function grammar is adjusted in several places:

```
formalParameterList
  : '(' ')'
  | '(' defaultFormalParameters ','? ')'
  | '(' defaultFormalParameters ',' namedFormalParameters ')'
  | '(' namedFormalParameters ')'
  ;

namedFormalParameters
  : '{' defaultFormalParameters ','? '}'
  ;

defaultFormalParameters
  : defaultFormalParameter (',' defaultFormalParameter)*
  ;

defaultFormalParameter
  : metadata normalFormalParameter ('=' expression?)? // todo: explain why expr optional
  ;

normalFormalParameter
  : fieldFormalParameter
  | functionFormalParameter
  | simpleFormalParameter
  | superFormalParameter
  ;
```

*We remove the optional positional parameter section. We remove `required` for
named parameters. Since that means named and positional parameters now have the
same grammar, we merge those corresponding rules into just
`defaultFormalParameter`.*

*Also, we make the default value expression after `=` optional for the implied
`null` syntactic sugar.*

### Function type

Function type annotations have parallel changes:

```
parameterTypeList
  : '(' ')'
  | '(' parameterTypes ',' namedParameterTypes ')'
  | '(' parameterTypes ','? ')'
  | '(' namedParameterTypes ')'
  ;

parameterTypes
  : parameterType (',' parameterType)*
  ;

namedParameterTypes
  : '{' parameterTypes ','? '}'
  ;

parameterType
  : metadata (typedIdentifier | type) '='?
  ;
```

*Since there is now only one kind of parameter type, I renamed the
`normalParameterType` rule to `parameterType`.

## Static semantics

The only change to the semantics of the language is allowing a single function
or function type to contain both optional positional and named parameters. The
semantics for combining those fall out in the obvious ways.

### Subtyping

The type system currently has separate subtyping rules for function types with
optional positional parameters versus ones with named parameters. We merge
these into a single subtyping rule that covers all function types.

Given two function types `T` and `S`, then `S` is a subtype of `T` if and only
if:

*   The return type of `S` is a subtype of the return type of `T`. *The usual
    covariant return type rule.*

*   The type of each parameter of `T` is a subtype of the type of the
    corresponding parameter of `S`. Here corresponding means by position for
    positional parameters and by name for named parameters. *The usual
    contravariant parameter type rule.*

    *Note that `S` may have extra parameters which have no corresponding
    parameter in `T`. Those extra parameters (which must be optional, covered
    below) are ignored here.*

*   The number of mandatory positional parameters of `S` is not more than the
    number of mandatory positional parameters of `T`. *A call of a function with
    type `S` through type `T` must be ensured to pass at least as many
    positional parameters as `S` requires.*

*   The number of positional parameters (mandatory and optional) of `T` is not
    more than the number of positional parameters of `S`. *A call of `S` through
    `T` can't be able to pass more positional parameters than `S` can accept.*

*   For each named parameter `n` in `T`, `S` also has a parameter with that
    name. If `n` is optional then the corresponding parameter in `S` must also
    be optional. *A call of `S` through `T` can't be able to pass a named
    argument that `S` doesn't accept. Nor can it omit a named argument that `S`
    requires.*

*   There are no mandatory named parameters in `S` where `T` does not have a
    corresponding parameter with that name. *A call of `S` through `T` must be
    ensured to pass any named argument that `S` requires.*

    *The previous four rules mean that a subtype can make mandatory parameters
    optional and can add more optional parameters. But it can't turn an optional
    parameter mandatory, and must accept at least as much as the supertype does.
    In short, the subtype must accept everything the supertype can accept and
    can permissively accept more than that, but not require anything more.*

*   The existing subtyping rules for generic function type parameters allow `S`
    to be a subtype of `T`. *The current language's two subtyping rules for
    function types handle generics the same way, and we preserve that same
    behavior... which the author is not enough of a type theorist to restate
    here.*

## Binding arguments to parameters

A single function invocation may now pass both named arguments and positional
arguments to optional parameters. Otherwise, the process is mostly the same.

To bind an argument list with a set *namedArgs* of named arguments and an
ordered list *positionalArgs* of positional arguments to a parameter list with a
set *namedParams* of named parameters and an ordered list *positionalParams* of
positional parameters:

*   Bind each named argument in *namedArgs* to the named parameter with the same
    name in *namedParams*. It is a compile-time error if there is no named
    parameter with that name or if the same argument name appears more than
    once.

*   Let *mandatoryCount* be the number of non-optional parameters in
    *positionalParams*.

*   It's a **compile-time error** if the length of *positionalArgs* is less than
    *mandatoryCount* *(not enough positional arguments)* or is greater than the
    length of *positionalParams* *(too many positional arguments)*.

*   For each argument *arg* in *positionalArgs*:

    *   Bind *arg* to the corresponding parameter in *positionalParams.*

*   Any remaining parameter in *namedParams* and *positionalParams* that has not
    had an argument bound to it takes its default value.

## Compatibility

This proposal makes three breaking syntax changes:

*   It removes the `[...]` optional positional parameter syntax.

*   It removes the `required` modifier on named parameters.

*   It reinterprets a named parameter as being mandatory by default instead of
    optional. So a named parameter like `int x` which previously meant
    "optional with implicit default `null`" now means "required".

These breaking changes are in both function declarations and function types.

To not break existing code, these changes are language-versioned. Pre-feature
Dart code continues to use the existing syntax.

### Automated migration

Code can be mechanically to the new syntax without requiring static analysis:

*   Remove the `[` and `]` from an optional parameter list. For any parameter
    in there that doesn't already have a default value, append `=`.

*   For every named parameter that doesn't have `required` or a default value,
    append `=`.

*   Remove `required` from every named parameter.

Note that the middle rule requires the migration tool to *know* that it is
migrating old syntax to new syntax. A function like this:

```dart
f({int? x}) {}
```

Is valid both before and after this proposal, but it means something different.
(This is similar to null-safety where type annotations were nullable before and
not after.)

### Cognitive cost

In addition to having to actually migrate code, which can be done automatically,
users have to learn to read the new syntax and to no longer read a parameter
inside `{...}` as optional by default.

That's a real cognitive migration cost for existing Dart users. However, I
believe the long-term cognitive load is less. New Dart users have
less to learn and the language is less contextual:

*   An unadorned parameter like `int x` is always mandatory, not mandatory in
    the positional parameter section and optional in the named parameter
    section.

*   The way you make a parameter optional is always by adding `=` (and maybe a
    default value), and not moving it to a `[...]` section of positional and
    *not* having a `required` modifier if named.

The language currently has four pieces of syntax users must contend with:
`[...]` for optional positional parameters, `{...}` for named, `= expr` for
default values, `required` for required named parameters.

After this change, there are only two or three depending on how you count `=`:
`{...}` for named parameters, `= expr` for optional parameters and default
values, and `=` for an implied default of `null`.

## Changelog

### 0.1

-   Initial draft.
