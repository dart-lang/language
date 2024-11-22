# Declaring Constructors

Author: Bob Nystrom (based on ideas by Lasse, Nate, et al)

Status: In-progress

Version 0.2 (see [CHANGELOG](#CHANGELOG) at end)

Experiment flag: declaring-constructors

Provide a less redundant way to declare instance fields and initialize them from
corresponding constructor parameters.

## Introduction

It's a tenet of object-oriented programming that instances of a class are
created by going through a constructor that the class itself defines. This gives
the class the opportunity to validate or process parameters and ensure that the
new instance is in a valid, meaningful state.

Constructors allow a class to fully encapsulate its fields: A class's stored
instance fields may have little or no correspondence to the parameters passed to
the constructor. A class can change how it stores its fields without breaking
the class's public API. Constructors are an important abstraction facility.

But that layer of abstraction is not without cost. While constructors *can* do
all sorts of interesting computation to derive their instance field values from
the given parameters, in practice most fields are directly initialized from a
corresponding parameter. In that common case, the amount of boilerplate to
define a class that takes in and stores some state is large.

Here is a trivial widget class (based on [this comparison of Jetpack Compose,
SwiftUI, and Flutter][jetpack]):

[jetpack]: https://www.jetpackcompose.app/compare-declarative-frameworks/JetpackCompose-vs-SwiftUI-vs-Flutter

```dart
class ExampleComponent extends StatelessWidget {
  final String displayString;

  ExampleComponent({required String displayString})
    : displayString = displayString;

  @override
  Widget build(BuildContext context) {
    return Text(displayString);
  }
}
```

The class stores a single field which is initialized by a corresponding
parameter in the constructor. The author of this class has to write the name
`displayString` four times, its type `String` twice, and the class name
`ExampleComponent` twice.

For many years, Dart has had a feature called "initializing formals" which
helps:

```dart
class ExampleComponent extends StatelessWidget {
  final String displayString;

  ExampleComponent({required this.displayString});

  @override
  Widget build(BuildContext context) {
    return Text(displayString);
  }
}
```

Now you don't have to say the type twice since the constructor parameter's type
is inferred from the field's. You only have to write `displayName` twice instead
of four times. You still have to write `ExampleComponent` twice. And you have to
explicitly declare both the instance field and the constructor parameter.

Can we do better?

This proposal adds *declaring constructors* to Dart. A declaring constructor
implicitly declares one or more instance fields based on corresponding
constructor parameters. Each implicitly declared field takes its name and type
from the corresponding parameter, and is implicitly initialized to that
parameter's argument value when the constructor is called.

Also, declaring constructors eliminate the annoying need to repeat the class
name, which may be long. With this proposal, the example widget class becomes:

```dart
class ExampleComponent extends StatelessWidget {
  this({required final String displayString});

  @override
  Widget build(BuildContext context) {
    return Text(displayString);
  }
}
```

That's not a monumental improvement in this toy example, but the value becomes
more noticeable in a larger (but still small) real-world example:

```dart
// Before:
class ClipboardHistoryItem extends StatefulWidget {
  final DictionaryHistoryEntry entry;
  final CreatorCallback creatorCallback;
  final VoidCallback stateCallback;

  final ScrollController dictionaryScroller;
  final ValueNotifier<double> dictionaryScrollOffset;

  ClipboardHistoryItem(
    this.entry,
    this.creatorCallback,
    this.stateCallback,
    this.dictionaryScroller,
    this.dictionaryScrollOffset,
  );

  @override
  _ClipboardHistoryItemState createState() {
    // ...
  }
}

// After:
class ClipboardHistoryItem extends StatefulWidget {
  this(
    final DictionaryHistoryEntry entry,
    final CreatorCallback creatorCallback,
    final VoidCallback stateCallback,
    final ScrollController dictionaryScroller,
    final ValueNotifier<double> dictionaryScrollOffset,
  );

  @override
  _ClipboardHistoryItemState createState() {
    // ...
  }
}
```

The class (granted with a method body elided) gets about 1/3 shorter. If you'd
like to see more real-world examples, I've taken a random sample of Dart classes
and [migrated them to this proposal][sample].

[sample]: https://github.com/munificent/temp-declaring-constructors/commit/0c38f2029783dde4c09041ef6056fe4939d77bdc

The proposal is a simple dollop of syntactic sugar. The basics are:

*   A **declaring constructor** is defined using `this` instead of the class
    name. A class may have only one.

*   Each parameter in the constructor's parameter list marked `final` or `var`
    is a **field parameter**. Each field parameter implicitly declares an
    instance field with the same name, type, and finality as the parameter.

*   The implicitly declared fields are automatically initialized by the
    corresponding field parameter value when the constructor is called.

*   Parameters in a declaring constructor not marked `final` or `var` are
    normal constructor parameters and don't declare fields. They can be used in
    the constructor's initializer list or body as usual.

### Compared to primary ctors

We've been discussing ways to reduce the verbosity around fields and
constructors for years. Another proposal aimed at the same problem is [primary
constructors][]. There are a few differences. In short, I think primary
constructors scale down better, while declaring constructors scale up better.

[primary constructors]: https://github.com/dart-lang/language/blob/main/working/2364%20-%20primary%20constructors/feature-specification.md

Primary constructors are hard to beat when the class is a very simple "plain-old
data structure" class that is effectively a nominal record or bag of fields:

```dart
// Before:
class ShoppingCartItem {
  final String name;
  final String skuNumber;
  final Currency unitPrice;
  int purchaseQuantity;

  ShoppingCartItem(
    this.name,
    this.skuNumber,
    this.unitPrice,
    this.purchaseQuantity,
  );
}

// This proposal:
class ShoppingCartItem {
  this(
    final String name,
    final String skuNumber,
    final Currency unitPrice,
    var int purchaseQuantity,
  );
}

// Primary constructors:
class PurchasedItem(
  final String name,
  final String skuNumber,
  final Currency unitPrice,
  int purchaseQuantity,
);
```

With a primary constructor, the fields are in the class header before the body.
That means they don't end up nested and indented twice, once for the body and
once for the parameter list.

Since *all* parameters in a primary constructor implicitly declare fields, you
don't need a marker keyword like `final` or `var` to distinguish field
parameters from non-field parameters. However, you *do* still need a marker to
specify the finality of the field. In practice, about 2/3 of primary constructor
parameters will still end up needing `final` since immutability is more common.
But for the 1/3 of fields that are mutable, primary constructors avoid the `var`
that this proposal requires.

There are real brevity advantages to primary constructors. But that brevity
comes with trade-offs. A primary constructor can't have a body, initializer
list, of explicit superclass constructor call. If you need any of those, you're
back to needing a regular in-body constructor.

A declaring constructor like in this proposal *is* an in-body constructor, so
it has none of those limitations. A class author can *always* make one of a
class's generative constructors be declaring if they want to.

In a large corpus of pub packages and open source Flutter applications, about
22% of existing constructors wouldn't work with the primary constructors
proposal because they have a body, explicit initializer list, etc. (On the other
hand, the fact that ~77% of constructors could still be primary constructors and
be even *more* terse than this proposal is a point in favor of that proposal.)

I like to think of this feature as syntactic sugar for *instance fields*, not
constructors. A class whose constructor initializes 80 fields will find either
of these proposals 80 times more useful than a class with just one field. If
you look at a corpus and count fields, the numbers are a little different.

In the same corpus, a little more than half (~53%) of all instance fields could
be implicitly declared using a primary constructor. Around ~65% could be
declared using this proposal. (The remaining ~35% of instance fields aren't
directly initialized from constructor parameters, so aren't helped by either
proposal.)

While these proposals are aimed at the same problem, they aren't necessarily
mutually exclusive. Their syntaxes don't collide so we could do both. Though
with factory constructors, redirecting constructors, initializing formals, and
super parameters, the amount of constructor-related syntactic sugar is getting a
little silly.

### Private field parameters and initializing formals

While we're touching constructors, we have the opportunity to fix a
long-standing annoyance. Initializing formals are common and well-loved, but
they fail when you want to initialize a *private* field using a *named*
parameter. The field's name starts with `_`, which isn't allowed for a named
parameter. Instead, you are forced to write explicit initializers like:

```dart
class House {
  int? _windows;
  int? _bedrooms;
  int? _swimmingPools;

  House({
    int? windows,
    int? bedrooms,
    int? swimmingPools,
  })  : _windows = windows,
        _bedrooms = bedrooms,
        _swimmingPools = swimmingPools;
}
```

Note also that the author is forced to type annotate the parameters as well
since they are no longer inferred from the initialized field.

When I last [analyzed a corpus][corpus private], 17% of all field initializers
in initializer lists were doing nothing but shaving off a `_`. There is an
obvious intended semantics here: simply remove the `_` from the named parameter
but keep it for the initialized field. Likewise, for declaring constructors,
the induced field keeps the `_` while the parameter name loses it. That turns
the above example into:

[corpus private]: https://github.com/dart-lang/language/blob/db9f63185707c4c89a69118e842e4cc6e0e59cc3/resources/instance-initialization-analysis.md

```dart
class House {
  int? _windows;
  int? _bedrooms;
  int? _swimmingPools;

  House({this._windows, this._bedrooms, this._swimmingPools});
}
```

And when combined with a declaring constructor:

```dart
class House {
  this({
    var int? _windows,
    var int? _bedrooms,
    var int? _swimmingPools,
  });
}
```

While this is a tiny sprinkle of syntactic sugar, it has a deeper value.
Initializing formals and declaring constructors are so much more concise that
users will want to use them whenever they can. But if they don't support private
fields and named parameters, then we are incentivizing users to make instance
fields public that they might otherwise prefer to keep private.

It's a well-established software engineering principle to minimize public state,
so we don't want the language to discourage users from encapsulating fields.

## Syntax

The syntax changes are small—just using `this` instead of the class name in a
constructor and allowing `var` on a parameter along with a type. But weaving it
into the grammar is a little complicated because some kinds of constructors
can't be declaring:

```
classMemberDeclaration ::=
  // Existing clauses...
  | declaringConstructor // Added.

declaringConstructor ::=
  declaringConstructorSignature initializers? (functionBody | ';')

declaringConstructorSignature ::=
  'const'? 'this' ('.' identifier)? formalParameterList
```

*We add a new clause to `classMemberDeclaration` for a declaring constructor. A
declaring constructor must be generative (not `factory`). Since factory
constructors have no `this`, there is no instance to implicitly initialize from
the parameter. A declaring constructor can be `const` or not. It can't be
redirecting. It also can't be `external` since an external constructor has no
implicit initializer list or body where the fields could be initialized.*

We also need to allow `var` before a simple formal parameter while also allowing
a type annotation. (Today, `var` is allowed, but only in place of a type, like
how variables are declared.) We redefine `simpleFormalParameter` to:

```
simpleFormalParameter ::=
    'covariant'? ('final' | 'var')? type? identifier
```

*The `simpleFormalParameter` rule was previously defined in terms of the same
rules used for variable declarations. That meant that the grammar for parameters
allowed `late` and `const`. Those are then disallowed by the specification
outside of the grammar. Here, we eliminate the need for that extra-grammatical
restriction by defining a grammar specifically for simple formal parameters that
only includes what they allow.*

*We could allow `late` on field parameters and have that apply to the instance
field (but not the parameter since parameters are always initialized). That
could be useful in theory if there are other generative constructors that don't
initialize the field. But to avoid confusion, we simply don't allow it. If a
user wants a `late` instance field, they can always declare it outside of the
declaring constructor.*

It is a compile-time error for a `simpleFormalParameter` to have both `var`
and a type outside of a declaring constructor.

*This keeps the normal parameter list grammar consistent with other variable
declarations. We could allow `var int x` as a parameter outside of a declaring
constructor, but doing so would be confusing because it looks like a field
parameter but isn't. Ideally, we would also disallow `final` on parameters
outside of declaring constructors, but doing so is a breaking change.*

## Static semantics

This feature is just syntactic sugar for things the user can already express,
so there are no interesting new semantics.

### Declaring constructors

Given a `declaringConstructor` D in class C:

*   For each parameter P in its formal parameter list list:

    *   If P has a `final` or `var` modifier, it is a **field parameter**:

        *   Implicitly declare an instance field F on the surrounding class with
            the same name and type as P. *If P has no type, it implicitly has
            type `dynamic`, as does F.*

        *   If P is `final`, then the instance field is also `final`.

        *   Any doc comments and metadata annotations on P are also copied to F.
            *For example, a user could mark the parameter `@override` if the
            the implicitly declared field overrides an inherited getter. If a
            user wants to document the instance field induced by a field
            parameter, they can do so by putting a doc comment on the
            parameter.*

        *   P comes an initializing formal that initializes F.

    *Note that a declaring constructor doesn't have to have any field
    parameters. A user still may want to use the feature just to use `this`
    instead of `SomePotentiallyLongClassName` to define the constructor.*

It is a compile-time error if:

*   A class has more than one declaring constructor. *If we allowed multiple,
    we'd have to decide what it meant for them to declare overlapping or
    non-overlapping field parameters. Any choice here is likely to be confusing
    for users. In practice, most classes have only a single generative
    constructor.*

    *A class can have a declaring constructor along with as many other
    generative and factory constructors as its author wants.*

*   The implicitly declared fields would lead to an erroneous class. *For
    example if the class has a `const` constructor but one of the field
    parameters induces a non-`final` field, or an induced field collides with
    another member of the same name.*

*   An implicitly declared field is also explicitly initialized in the declaring
    constructor's initializer list. *This is really just a restatement of the
    previous point since it's an error for a field to be initialized both by an
    initializing formal and in the initializer list.*

*   A field parameter is named `_`. *We could allow this but... why?*

### Private field parameters and initializing formals

An identifier is a *private name* if it starts with an underscore (`_`),
otherwise it's a *public name*.

A private name may have a *corresponding public name*. If the characters of the
identifier with the leading underscore removed form a valid identifier and a
public name, then that is the private name's corresponding public name. *For
example, the corresponding public name of `_foo` is `foo`.* If removing the
underscore does not leave something which is is a valid identifier *(as in `_`
or `_2x`)* or leaves another private name *(as in `__x`)*, then the private name
has no corresponding public name.

The private declared name, *p*, of an initializing formal or field parameter in
constructor C has a corresponding *non-conflicting public name* if it has a
corresponding public name, *n*, and no other parameter of the same constructor
declaration has either of the names *p* or *n* as declared name. *In other
words, if removing the `_` leads to a collision with another parameter, then
there is a conflict.*

Given an initializing formal or field parameter with private name *p*:

*   If *p* has a non-conflicting public name *n*, then:

    *   The name of the parameter in C is *n*. *If the parameter is named, this
        then avoids the compile-time error that would otherwise be reported for
        a private named parameter.*

    *   The local variable in the initializer list scope of C is *p*. *Inside
        the body of the constructor, uses of *p* refer to the field, not the
        parameter.*

    *   If the parameter is an initializing formal, then it initializes a
        corresponding field with name *p*.

    *   Else the field parameter induces an instance field with name *n*.

    *Any generated API documentation for the parameter should also use *n*.*

*   Else (there is no non-conflicting public name), the name of the parameter is
    left alone and also used for the initialized or induced field. *If the
    parameter is named, this is a compile-time error.*

*For example:*

```dart
class Id {
  late final int _region = 0;

  this({this._region, final int _value});

  @override
  String toString() => 'Id($_region, $_value)';
}

main() {
  print(Id(region: 1, value: 2)); // Prints "Id(1, 2)".
}
```

## Runtime semantics

The runtime semantics for field parameters inside a declaring constructor are
the same as for initializing formals:

Executing a field parameter with name *id* causes the instance variable *id*
of the immediately surrounding class to be assigned the value of the
corresponding actual argument.

## Compatibility

### Declaring constructors

The identifier `this` is already a reserved word that can't appear at this
point in the grammar, so this is a non-breaking change that doesn't affect any
existing code.

However, it does introduce a potential source of confusion. It's already
possible to mark a parameter `final`. (Doing so simply makes the parameter
non-assignable.) It's also possible to annotate a parameter using `var` (but
not with a type annotation after).

With this feature, users may expect that syntax when used outside of a declaring
constructor to do something like what it does inside a declaring constructor's
parameter list. In practice, `final` is rare on parameters and `var` is
virtually unknown:

```
-- Parameter (3992112 total) --
3948862 ( 98.917%): neither  ===================================================
  42450 (  1.063%): final    =
    800 (  0.020%): var      =
```

(More than half of the occurrences of `var` parameters are in a single pub
package. More than 82% are in only five packages, so this seems to be something
a *very* small number of authors use.)

So while the potential for confusion is there, I think it's unlikely to be a
problem in practice.

### Private field parameters and initializing formals

Any existing initializing formals with private names must be positional since
it's a compile-time error to have a private named parameter. Since those
arguments are passed positionally, the change to give the parameter a public
name has no effect on any callsites.

Generated documentation may change, but that should be harmless.

### Language versioning

Even though this change is non-breaking, it is language versioned and can only
be used in libraries whose language version is at or later than the version this
feature ships in. This is mainly to ensure that users don't inadvertently try to
use this feature in packages whose SDK constraint allows older Dart SDK versions
that don't support the feature.

## Tooling

The best language features are designed holistically with the entire user
experience in mind, including tooling and diagnostics. This section is *not
normative*, but is merely a suggestion for the implementation teams.

### Quick fix

This feature makes common idioms more concise, so users would almost certainly
want to use it, and we want them to. An automated quick fix can make that
easier.

The process to turn an existing generative constructor into a declaring
constructor is something like:

1.  For each initializing formal whose type is the same as the corresponding
    field:

    1.  Move any type annotation, doc coment, and metadata annotation from the
        field to the formal parameter.

    2.  Add `final` if the field is `final` or `var` otherwise and remove the
        `this.`.

    3.  Remove the field declaration.

I suspect this feature is better as a human-initiated quick fix than a
large-scale automated migration. It's not always clear when a constructor should
become a declaring one:

*   If the class has only one constructor but the constructor doesn't have any
    initializing formals, should it still become declaring? `this` is probably
    shorter than the class name, but is that worth it?

*   If the class has multiple generative constructors, which one becomes
    declaring? Probably the one with the most initializing formals, but what do
    you do in case there's a tie?

### Lint for `final` parameters

This proposal retcons the `final` modifier on parameters to mean something
specific in a declaring constructor. Outside of a declaring constructor the
modifier is allowed but has a different effect: it simply makes the parameter
itself non-assignable.

If declaring constructors become popular, then users will likely start to see
`final` before a parameter and read it as a field parameter. They will then be
confused if the parameter isn't actually in a declaring constructor and isn't
a field parameter.

Given that non-assignable parameters aren't actually that *useful*, it may be
worth discouraging users from marking a parameter with `final` unless it is a
field parameter. This seems like a good candidate for a lint.

## Changelog

### 0.2

-   Apply review feedback from Lasse.
-   Add section for inferring public parameter names from private ones.
-   Update `simpleFormalParameter` grammar to allow `var` followed by a type.
-   Add lint for using `final` on parameters.

### 0.1

-   Initial draft.
