# Type Modifiers

Author: Bob Nystrom

Status: Strawman

Version 1.0

This is a proposal for capability modifiers on classes and mixins. It's based on
[Erik's proposal][erik] as well as some informal user surveys.

[erik]: https://github.com/dart-lang/language/blob/master/resources/class-capabilities/class-capabilities.md

## Goals

With [pattern matching][], we want to support [exhaustiveness checking][] over
class hierarchies in order to support algebraic datatype-style code. That means
a way to define a supertype with a fixed, closed set of subtypes. That way, if
you match on all of the subtypes, you know the supertype is exhaustively
covered.

[pattern matching]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/patterns-feature-specification.md

[exhaustiveness checking]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/exhaustiveness.md

We don't necessarily need to express that using a modifier, but that's what
most other languages do and it seems to work well. If we're going to add one
modifier on types, it's a good time to look at other modifiers so that we can
design them holistically.

This proposes a small number of language changes to give users better control
over the main capabilities a type exposes:

*   Whether it can be constructed.
*   Whether it can be subclassed.
*   Whether it defines an interface that can be implemented.
*   Whether it can be mixed in.
*   Whether it has a closed set of subtypes for exhaustiveness checks.

## Mixins

When we added support for `on` clauses, we also added dedicated syntax for
defining mixins since `on` clauses don't make sense for class declarations.
However, Dart still allows you do treat a class as a mixin if it fits within
restrictions.

Since those restrictions are easy to forget, it's easy for a class maintainer
to accidentally cause the class to no longer be a valid mixin and break users
that were using it as one. For that and other reasons, we've long wanted to
remove the ability to use a class as a mixin ([#1529][], [#1643][]).

[#1529]: https://github.com/dart-lang/language/issues/1529
[#1643]: https://github.com/dart-lang/language/issues/1643

Based on our survey feedback, users seem OK with that. So the first change is
to **stop allowing classes to appear in `with` clauses.**

I think this change makes sense. Classes and mixins are fundamentally different
things. A mixin *has no superclass*. It's *not* a class. You can't construct it
or extend it because it's not a complete entity. It's more like a function that
*produces* a class when "invoked" with a superclass.

This is technically a breaking change, but I believe it will be relatively
minor.

## Capability defaults

When designing modifiers, you have to decide what the default behavior is. What
do you get *without* the modifier. The modifier then toggles that. For types,
do we default to making them permissive with all the capabilities and then have
modifiers to remove those? Or do we default to classes being restricted and
allow modifiers to add capabilities?

I propose that we default to permissive: **Without any modifiers, a type has all
capabilities.** Since mixins are separate from classes that means a class
defaults to being constructible, extensible, and implementable. A mixin defaults
to being miscible and implementable.

My reasoning is:

*   **It's nonbreaking.** Classes are permissible by default right now, so
    keeping that default behavior lets us add modifiers without breaking
    existing code. If we made `class` and `mixin` default to *not* allowing
    these capabilities, every existing Dart type would break. Fixing that is
    mechanically toolable, but that doesn't magically repair every line of
    documentation, blog post, or StackOverflow answer. It would be a *lot* of
    churn.

*   **We've gotten by so far.** Permissive is the current default and it can't
    be *that* bad, or we would have changed it years ago. Users *do* ask for
    more declarative control over these capabilities, but it has never risen to
    the top of any lists of user priorities.

*   **It's consistent.** Dart does already have one capability modifier for
    classes: `abstract`. It *removes* a capability: the ability to construct
    instances of the class. (`abstract` also *enables* the ability to define
    abstract members inside the class body, but that's a secondary effect. A
    class you can construct can't contain abstract members. Mixins can also
    contain abstract members, but don't need an `abstract` modifier.)

    If we switch the defaults, we'd either have to get rid of `abstract` and add
    a "constructible" modifier, or have a mixture of some capabilities that
    default to on (construction) and others that default to off (extension and
    implementation). Having everything default to on is simpler for users to
    reason about.

*   **Users like the current defaults.** From our limited survey, users
    generally seem to prefer the current permissive defaults. We have long heard
    that automatic implicit interfaces are a *beloved* feature of the language.

*   **It stays out of the way for app developers.** Removing capabilities helps
    package maintainers because it lets them change their classes in more ways
    without breaking users. For example, if a class doesn't expose an implicit
    interface, then it's safe to add new methods to the class. Removing
    capabilities can also help app developers understand very large codebases.
    If they see that a class is closed to extension, they don't have to wonder
    if there are subclasses floating around elsewhere in the codebase.

    But for developers writing smaller applications over shorter timescales,
    these restrictions are likely unnecessary and may just be distracting. Dart
    and Flutter are used particularly heavily for small-scale client
    applications, often written quickly at agencies. A large fraction of Dart
    code is in relatively small "leaf" codebases like this. Defaulting to
    permissive lets developers of those programs do what they want with their
    types without any potentially distracting or confusing ceremony.

    Meanwhile, package authors who do want to restrict capabilities still have
    the ability to opt in to those restrictions.

For those reasons, I suggest we default to types being permissive. Since we are
separating mixins out from classes, we don't need a modifier to remove the
capability of mixing in a class. We already have a modifier `abstract` to opt
out of construction. What remains are modifiers for opting out of extension and
implementation.

## Prohibiting subclassing

Most other object-oriented languages give users control over whether a class can
be subclassed. C# defaults to allowing subclassing and uses a `sealed` modifier
to prohibit it. Java and Scala also default to allowing it and use `final` to
opt out. Swift and Scala default to disallowing and use `open` to allow
subclassing.

We could use `sealed` for Dart, but that keyword is used for exhaustiveness
checking in Swift and Kotlin, which could be confusing. We could use `final`,
but I think it would be confusing if a class marked `final` could still be
implemented. "Final" sounds, well, *final* to me.

I like to reuse keywords from other languages when possible, but given that the
existing keywords have conflicting meanings in different languages, it may be
*less* confusing to use a new keyword that has no existing association. Swift
and Kotlin use `open` to mean that a class is "open to extension". We need the
opposite, a modifier that means the class is "closed to extension".

Based on that, I suggest we **use `closed` to mean that the class isn't open to
being subclassed.** A user coming from Kotlin or Swift can probably infer that
it means the opposite of the `open` keyword they are familiar with.

## Prohibiting implementing

Disabling implementation is harder. No other language I know supports implicit
interfaces, so there isn't much prior art or user intuition to lean on. We are
defaulting to allowing an unfamiliar (but much loved) behavior and now need a
keyword to mean the *opposite* of an unfamiliar concept.

I considered `concrete` since a class with no interface is a "concrete class",
but that keyword implies that it means the opposite of `abstract` when it would
have nothing to do with that other modifier.

Here's one way to look at it: Think about a user who applies this modifier.
What are they trying to accomplish? What does the class they end up with
represent?

When a class exposes no implicit interface it means that every instance of that
class's type is either a direct instance of the class itself, or one of its
concrete subclasses. Every instance will have that class's instance fields and
will inherit its method implementations.

If this class happened to also be abstract so that there were no direct
instances of it, how would you describe? It would be a class that existed
solely to be extended: an [abstract base class][].

[abstract base class]: https://en.wikipedia.org/wiki/Class_(computer_programming)#Abstract_and_concrete

If the class isn't abstract and can be both constructed and extended, you might
think of it as a "base class". Given that, I suggest we use `base` to mean "no
interface". In other words, this class defines a *base* that all subtypes of
this class (if there are any) must inherit from.

It's short. I think it reads very naturally in `abstract base class` and `base
class`. It works OK in `base mixin` to define a mixin with no implicit
interface. If you want a class that can't be implemented *or* extended (in other
words, a fully "final" or "sealed" leaf class), it would be a `closed base
class`. I admit that reads a little like an oxymoron. It's not *great*, but
maybe that's acceptable?

## Exhaustiveness checking

In order for exhaustiveness checking to be sound, we need to ensure that there
are no [non-local][global] subtypes of the class being matched. If we defaulted
to allowing exhaustiveness checks on all classes, that would require us to
default to *prohibiting* extending and implementing the class outside of its
library.

[global]: https://github.com/dart-lang/language/blob/master/working/0546-patterns/exhaustiveness.md#global-analysis

So we want to default exhaustiveness checks *off* and provide a way to opt in.
We *could* say that any abstract class that disables extension and
implementation implicitly enables exhaustiveness checks. But I don't think
that's what users will want in many cases. Once a type has enabled
exhaustiveness checks, it is a breaking API change for the maintainer of that
type to add a new subtype. A package maintainer may want to prohibit *others*
from subtyping the types it exposes while still retaining the flexibility to add
them themselves in minor versions of the package.

Kotlin and Scala use `sealed` to opt in to exhaustiveness checks. We could use
that but it might be confusing since `sealed` just means "can't subclass" in C#.

Given that I suggested novel keywords for the other two modifiers, we could use
a new one here too. I propose `switch`. This keyword directly points to where
the modifier's behavior comes into play: exhaustiveness checks on switch cases.
(`case` is another obvious choice. But, confusingly, `case class` in Scala has
nothing to do with exhaustiveness even though match cases are where
exhaustiveness comes into play.)

I'm not in love with this. Maybe it's best to stick with `sealed` and risk a
little confusion from C# users.

## Modifier combinations

Given all of the above, here are the valid capability combinations and the
keywords to express them:

```dart
closed abstract base class  // (none)
closed base class           // Construct
abstract base class         // Extend
switch base class           // Extend Exhaustive
base class                  // Extend Construct
closed abstract class       // Implement
switch closed class         // Implement Exhaustive
closed class                // Implement Construct
abstract class              // Implement Extend
switch class                // Implement Extend Exhaustive
class                       // Implement Extend Construct

base mixin                  // Mix-In
switch base mixin           // Mix-In Exhaustive
mixin                       // Mix-In Implement
switch mixin                // Mix-In Implement Exhaustive
```

Note that all 32 Boolean combinations are not present:

*   `Mix-In` can't be combined with `Extend` or `Construct` because a mixin has
    no superclass and thus isn't a thing you can use directly without applying a
    superclass first by mixing it in.

*   `Exhaustive` implies that the class itself can't be directly constructed
    (otherwise checking its subtypes isn't exhaustive), so it can't be combined
    with `Construct`. Also, it implies `abstract` so the latter doesn't need to
    be written.

*   Likewise, `Exhaustive` is meaningless without any subtypes, so `switch`
    can't be combined with both `closed` and `base`.

A grammar for the valid combinations is:

```
classHeader ::= 'closed'? 'abstract'? 'base'? 'class'
              | 'switch' ( 'closed' | 'base' )? 'class'

mixinHeader ::= 'switch'? 'base'? 'mixin'
```

## Scope

That's syntax, but what are the semantics? I don't want to get into detail but
one important question is the scope where the restrictions are applied. Can
they be ignored in some places? For example, can you subclass a class marked
`closed` within the same library? Same Pub package? Can you use a `base class`
in an `implements` clause in the class's package's tests?

For exhaustiveness checking, we need to allow *some* subtypes to exist, but they
must be prohibited outside of scope known to the compiler so that users can
[reason about them in a modular way][global]. The principle I suggest for that
is: *The compile errors in a file should be determined solely by the files that
file depends on, directly or indirectly.*

That implies that for `switch`, the restriction on subtyping is ignored in the
current library. I suggest we use the same scope for the other modifiers. So
when a class is marked `closed`, you can still extend it from another class in
the same library. Likewise, a type marked `base` can still be implemented in the
same library.

The restriction is *not* ignored outside of the library, even in other libraries
in the same package, including its tests. My thinking is:

*   Libraries are the boundary for privacy, so they are already establishes as
    the natural unit of capability restrictions.

*   Since the default behavior is permissive, it's not onerous if the user does
    want to access these capabilities outside of the current library. They get
    that freedom by default unless they go out of their way to remove it.

*   We would like to be able to use static analysis to improve modular
    compilation in Dart. Knowing that a type can't be extended and/or
    implemented might give a compiler the ability to devirtualize members or
    apply other optimizations.

    The library is the natural granularity for that. Our compilers don't
    currently work at the granularity of a pub package and are unlikely to since
    a package's library code, tests, and examples all have very different
    package dependencies. Also, some packages contain different libraries that
    each target different platforms. That would make it hard for a modular
    compiler to look at an entire pub package as a single "unit".

*   If a user does want to ignore these restrictions across multiple files in
    their package, they can always split the library up using part files. If
    we ship [augmentation libraries][], they can even give each of those files
    their own imports and private scope.

[augmentation libraries]: https://github.com/dart-lang/language/tree/master/working/augmentation-libraries

## Summary

This proposal gives Dart users full control over all meaningful combinations of
capabilities a class can expose. It does so mostly without breaking existing code.

It splits mixins out completely from classes. Then it adds three new modifiers:

*   A `closed` modifier on a class disables extending it.
*   A `base` modifier on a class or mixin disables its implicit interface.
*   A `switch` modifier on a class or mixin defines the root of a sealed type
    family for exhaustiveness checking. It also implies `abstract`.
