# Static Metaprogramming in Dart

## Problem Statement

Programmers hate repetition—having to write the same or very similar code over
and over again. It’s boring, tedious, error-prone, and harder to maintain in
parallel correctly. A key property of what makes a programming language
productive is its facilities for eliminating repetition.

The humble loop is a simple example. Instead of:

```dart
list.add(1);
list.add(2);
list.add(3);
```

Which is asking for a copy/paste error, we’d rather write:

```dart
for (var i = 1; i <= 3; i++) {
  list.add(i);
}
```

A more powerful example is functions. If you need to build a Flutter widget
containing three similar columns, would you rather maintain this:

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text('CALL')],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text('ROUTE')],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text('SHARE')],
        ),
      ],
    );
  }
}
```

Or this:

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildColumn('CALL'),
        _buildColumn('ROUTE'),
        _buildColumn('SHARE'),
      ],
    );
  }

  Column _buildColumn(String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Text(label)],
    );
  }
}
```

Loops and functions are powerful, but fundamentally limited. They only execute
within imperative code—initializers and function bodies—and they can only
operate on data—values that are first-class in Dart. If you want to, say,
iterate over all the fields in a class (maybe to serialize them), you have to
use the “dart:mirrors” library which exists to expose data about classes as
first-class Dart objects. That works, but sacrifices performance, causes code
size problems, and isn’t supported at all in AOT builds.

In the above example, we can hoist the repetitive code to create a column into a
function because Flutter widgets are built using imperative code inside
`build()` methods. But say you wanted to define each column as a separate widget
class, like this:

```dart
class CallBuildColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Text('CALL')],
    );
  }
}

class RouteBuildColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Text('ROUTE')],
    );
  }
}

class ShareBuildColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Text('SHARE')],
    );
  }
}
```

There is no function you can write in Dart and call three times to output these
three classes, short of a heavy code generator. Dart doesn’t let you abstract
over classes or other top-level declarations.

**Metaprogramming** refers to code that can do this—code that operates on other
code as if it were data. It can take code in as parameters, reflect over it,
inspect it, create it, modify it, and return it. ***Static* metaprogramming**
means doing that work at compile-time. This avoids the safety, performance, and
code size problems of runtime metaprogramming. Examples are the C preprocessor,
C++ templates, Rust macros, Swift [function builders][function_builders], and
[compile-time execution in Zig][zig_compile_time_execution].

This document proposes an approach to adding static metaprogramming in Dart that
we’d like to investigate.

## Sample use cases

Here is a non-exhaustive list of some of the problems users have run into where
it feels like there should be a reusable general solution but instead they have
to write the same repetitive boilerplate code every time:

### JSON serialization and deserialization

Given some class declaration, it’s trivial to write a method that serializes it
to JSON:

```dart
class Dog {
  final String breed;
  final String name;

  Object toJSON() => {'breed': breed, 'name': name};
}
```

But that code requires iterating over the fields of the class somehow. Short of
using mirrors or code generation, there’s no way to write a reusable system that
can add JSON serialization/deserialization to any given class.

### Data classes

The [most requested open language issue][data_classes_issue] is to add data
classes. A data class is essentially a regular Dart class that comes with an
automatically provided constructor and implementations of `==`, `hashCode`, and
`copyWith()` (called `copy()` [in Kotlin][kotlin_copy]) methods based on the
fields the user declares in the class.

The reason this is a *language* feature request is because there’s no way for a
Dart library or framework to add data classes as a reusable mechanism. Again,
this is because there isn’t any easily available abstraction that lets a Dart
user express “given this set of fields, add these methods to the class”. The
`copyWith()` method is particularly challenging because it’s not just the *body*
of that method that depends on the surrounding class’s fields. The parameter
list itself does too.

We could add data classes to the language, but that only satisfies users who
want a nice syntax for *that specific set of policies*. What happens when users
instead want a nice notation for classes that are deeply immutable,
dependency-injected, [observable][observable], or
[differentiable][differentiable]? Sufficiently powerful static metaprogramming
could let users define these policies in reusable abstractions and keep the
slower-moving Dart language out of the fast-moving methodology business.

### Flutter verbosity

To get better incremental update performance and more maintainable fine-grained
code, it’s often useful in Flutter to break a large widget with a complex
`build()` method down into an aggregation of smaller widget classes. But
hoisting some layout code into a new widget class requires enough boilerplate
that users avoid it. For example, say you have a widget with some fixed data,
stateful data, and a bit of build code that you want to pull into a new widget
class `Foo`. You have to write:

```dart
class Foo extends StatefulWidget {
  Foo({ Key key, this.fixedStuff }) : super(key: key);
  FixedStuff fixedStuff;
  State<Foo> createState() => _FooState();
}

class _FooState extends State<Foo> {
  StatefulStuff statefulStuff = ...;
  @override
  Widget build(BuildContext context) {
    buildCode();
  }
}
```

The widget name is repeated six times, `fixedStuff` appears twice, and the
remaining code is almost pure boilerplate that is identical across all
`StatefulWidget` and `State` subclasses.

There are other patterns in Flutter like this that are commonly applied to
widget classes but require Flutter users to write a lot of repetitive code,
such as the `dispose()` method which needs to do any required cleanup of widget
state (removing listeners, calling custom `dispose` methods on fields, etc).
Metaprogramming could enable the Flutter framework to express these patterns
more tersely and with less chance for user error.

## Requirements

From these sample use cases and others, we can generalize some requirements:

* **Must be able to introspect on the existing program**. Almost all the use
  cases we want to cover need to be able to look at the fields of an existing
  class at a minimum, as well as the fields of super classes in many cases. Many
  also need to inspect the methods, constructors, and parameters of those.
* **Must be able to synthesize new APIs in existing classes**. Most of the core
  use cases require adding new methods to classes, whose signatures may not be
  known ahead of time. Some also require the ability to add new fields, both
  private and public to classes.
* **Should be able to synthesize whole new classes**. Some of the core use cases
  involve creating new classes from either other classes or even just top level
  functions.
* **Metaprogramming should be composable**. In one form or another,
  metaprogramming applications should be able to be composed together. A data
  class code generator for instance would ideally be a combination of several
  more targeted code generators for each of the desired features (`copyWith()`,
  `==`, `hashCode`, etc).
* **Generated code must be debuggable and user visible**. See the Usability
  section below.

## Design constraints

In addition to user-level requirements, there are some practical constraints to
ensure that we don't compromise the existing advantages of Dart.

* **Must support modular compilation**. Any individual library should be able to
  be fully compiled (including running all macros) using only the transitive
  dependencies of the library. To this end we should not expose any API or
  functionality that allows global access to the program, outside of the current
  library and/or its dependencies. Such functionality would defeat modular
  compilation.
* **Must support incremental compilation**. This is key to the hot reload
  workflow—any change in the program should not have to rerun all
  metaprogramming in the entire program. It should at worst require a rerun of
  the metaprogramming in libraries that depend on the modified library.
* **Must support expression evaluation**. Expression evaluation is a vital tool
  for the development experience and we need to ensure it is not negatively
  affected.

For the most part the design constraints here align with the modular compilation
design constraints. In short, metaprogramming should not introduce global action
at a distance.

## Non-goals

* **Modifying existing code**. We don’t see a need to allow modifiying existing
  code through metaprogramming. This leads to unexpected behavior, and
  negatively affects usability. Dart code that already has clearly defined
  meaning today should continue to mean the same thing after metaprogramming.
  The goal is not to be able to hijack existing Dart syntax to do wildly
  different things, but to augment code with new capabilities.

## Approach

To understand what a static metaprogramming solution might look like, we’ll walk
through one of the use cases. Say a Dart user wants to write a library that
automatically defines `copyWith()` methods for classes. For them to do that,
Dart needs to provide a way for users to:

1. **Invoke the metaprogramming** to control which classes should get the
   `copyWith()` method.
2. **Define some metaprogramming** that specifies how the copyWith() method is
   defined in terms of the class’s fields. That metaprogramming needs to be
   authored in some kind of metaprogramming language.
3. Use an **introspection mechanism** to walk over the class’s field
   declarations.
4. Use a **construction mechanism** to produce a new method including its
   signature and body. The resulting is then added to the original class
   declaration.

The approach we propose is **macros**, and the above requirements list can be
stated more concretely as:

1. We design some sort of syntax to apply a macro by name to a given class,
   method declaration, etc.
2. We propose to design a way of defining macros which can be then be applied
   as above.
3. We propose to design an introspection system to allow macros to introspect
   on the program during their execution. This might be an imperative API
   similar to the existing mirrors API or analyzer API, or something
   declarative like to pattern matching over syntax examples.
4. We propose to consider designing a quotation syntax so that macros that
   generate Dart code can generate code in a readable fashion. This also means
   code generators only depend on language *syntax* for code generation and not
   an imperative api, which will better stand the test of time.

Most of this is as-yet-undesigned, but the key piece is that **we think macros
should be written in normal imperative Dart code which is executed at compile
time**.

## Compile-time Dart execution

Allowing a general-purpose, Turing-complete imperative language to run at
compile time is a big ask. Here’s why we think it’s a good choice:

### We already do it

A subset of the Dart language is already allowed at compile time, which is
specifically carved out to support limited const expressions. This means users
are familiar with the concept of “running” Dart code at compile time, and we
have invested some implementation time in supporting it. You could think of this
proposal as merely (massively) expanding the subset of Dart allowed in a const
expression.

### One less language to define

Metaprogramming has to be authored in some language. It takes significant time
to design, specify, implement, and test a language. Anyone user authoring macros
will have to learn that language. By making that Dart language, we let the user
write macros in a language they already know, and we take advantage of all of
he existing work we’ve done on Dart.

### Declarative languages are too limited

Declarative macro systems are usually not Turing complete. This ensures that
metaprogramming has finite execution time, which is a nice property. The cost is
that many potentially useful metaprogramming abstractions can’t be defined
within the limitations of that declarative language. Experience from other
language communities is that declarative-only metaprogramming ends up being too
limited.

The Scheme community has gone through a number of rules-based macro systems over
decades as each proved to be too limiting. Meanwhile Common Lisp let Lispers
define macros imperatively. This sometimes makes it a challenge to implement
macros *correctly*, but has always been sufficiently powerful.

Experience from many UI templating languages (which are surprisingly similar to
macro metaprogramming in many ways) is that most declarative ones gradually
accumulate imperative features or end up replaced by those that do.

In the Dart ecosystem, in the absence of metaprogramming in the language, users
often resort to code generators. Some of those are quite sophisticated and are
written in imperative Dart code. These typically take the form of kernel
transformers or separate build processes like build_runner which run before the
compilers and are not directly integrated.

Rust has a nice [declarative, rule-based macro system][rust_declarative_macros].
But, because that rule-based system is limited, Rust also has a second
[imperative procedural macro system][rust_procedural_macros] for when you need
more power. In Dart, we would prefer to only have one metaprogramming system, so
it should be one that is powerful enough to cover all known use cases.

## Challenges

Having said that, allowing the whole Dart language to run at compile-time
exposes a number of really difficult problems we will have to solve in 2021:

### Scoping and hygiene

A macro may introduce new symbols into an existing scope (where that function is
used). How do we deal with conflicts here? Would the generated code exist in its
own scope and not have the ability to leak any new variables into the
surrounding scope?

Generated code may also need to access variables in at least 3 different scopes —
the scope where the macro is applied, the scope of the generated code (may be
same as the former), and the scope where the macro is defined. How does it
distinguish between these?

### Ordering and staging

In what order are macros run? If they can both generate new APIs and introspect
on the program, then ordering can be user-visible. Consider a macro that adds a
field for memoization and another that adds a method to serialize all fields. If
both are applied to the same class, does the memoized field get serialized?

Do macros run before type checking, after, or interleaved? What is the static
type context in which a macro runs?

How do macros interact with const canonicalization and evaluation, do they run
before, after, or interleaved? Can macros read const values *and* generate them?

There are additional considerations if we allow recursive macros, and cycles
between macro defining libraries.

### Usability

Macros can easily lead to incomprehensible programs if they become overly
magical, or are a complete black box to the user. In order to demystify macros
you should:

* Be able to easily navigate to the macro implementation.
* Be able to visualize in some way the code generated into your program, at
  development time.
* Be able to debug generated code (step through it, etc).
  * Possibly provide an opt out for this, if feasible/desirable.
* Be able to trace errors that flow through generated code, as well as navigate
  back to the line in the macro implementation that produced the code.
* Be able to auto-complete macro generated apis.

### Performance

A Turing-complete programming language that runs in your typechecker opens the
door to user-code that locks the IDE. How do we ensure that users maintain a
fast edit refresh cycle when arbitrary Dart code may be running during compilation?

### Security

Today, users are fully aware of exactly when third party code (excluding code
from the sdk) might be executed (only when they explicitly run a program). This
will change with this proposal, since it involves running user code as a part
of the compilation and likely program analysis process. This means that even
opening your IDE for instance could expose you to malicious code if we aren't
careful.

In order to minimize the threat of malicious code which could run in these
contexts, we will likely need to limit the read/write/execution access of
macro code, including access to ffi or other libraries which might enable that
same access.

One possible way to do this would to be to explicitly limit the `dart:`
libraries that are available for use at compile time.


[function_builders]: https://github.com/apple/swift-evolution/blob/9992cf3c11c2d5e0ea20bee98657d93902d5b174/proposals/XXXX-function-builders.md
[zig_compile_time_execution]: https://andrewkelley.me/post/zig-programming-language-blurs-line-compile-time-run-time.html#:~:text=Compile%2DTime%20Parameters,-Compile%2Dtime%20parameters&text=In%20Zig%2C%20types%20are%20first,functions%2C%20and%20returned%20from%20functions.&text=At%20the%20callsite%2C%20the%20value,is%20known%20at%20compile%2Dtime.
[data_classes_issue]: https://github.com/dart-lang/language/issues/314
[kotlin_copy]: https://kotlinlang.org/docs/reference/data-classes.html#copying
[observable]: https://docs.google.com/document/d/1L2NgM-Kl1PKt8iWQIrFugH0JUQ7Ky86MrM-WM1CPf0I/edit#heading=h.sb9uvy8myyqv
[differentiable]: https://en.wikipedia.org/wiki/Differentiable_programming
[rust_declarative_macros]: https://doc.rust-lang.org/book/ch19-06-macros.html#declarative-macros-with-macro_rules-for-general-metaprogramming
[rust_procedural_macros]: https://doc.rust-lang.org/book/ch19-06-macros.html#procedural-macros-for-generating-code-from-attributes
