# Sound non-nullable (by default) types with incremental migration 

Note: the current draft spec is [here](feature-specification.md)

Author: leafp@google.com

This document proposes a roadmap for implementing a sound null tracking type
system in Dart similar to what has been
explored [previously](https://github.com/dart-lang/sdk/pull/28619/files).  The
purpose of this document is not to describe the technical details of a proposal,
but instead to argue for a specific set of high-level goals and design choices
that define the key properties of the final system, and of the migration path to
get there.  Specifically, we propose to aim for a system which allows for an
incremental opt-in migration, and which is fully sound once all code in a
program has opted in.

## Motivation for non-nullability in Dart.

This has been fairly well explored previously, so just in brief.  This is one of
the most requested features in developer surveys, and one of the thing that
developers most frequently mention missing from other languages.  Kotlin, Swift,
C#, Typescript, and numerous other languages now have, or are adding, support
for non-nullability.  Since Dart also has no primitive types or value types, it
is possible that non-nullability could provide performance benefits as well.

## Summary of proposed goals

We propose to set the following goals for nullability tracking in Dart.

- Code can be migrated incrementally. A program can run and
have well-defined semantics when some parts have been migrated to non-nullable
types and others have not. We don't guarantee full safety in programs which mix
migrated and unmigrated code.  That is, when not all code has opted in, it is
possible that a non-nullably typed value will receive null.

- When a program has been fully migrated to non-nullable types, it
uses only the subset of the type system that is sound. No null errors (returning
null from an expression whose type is not nullable, calling methods on null that
the Null class does not support) will occur.

- During the migration, if a package opts in after all of the packages it
depends on have already opted in (or if it correctly predicts and codes against
the post-migration API of the packages it depends on) it can migrate completely
in one step.

- Migration should be minimally breaking for unmigrated packages.  Migrating a
  package should never cause compilation to fail for unmigrated downstream
  dependencies, and as much as is possible should not introduce new runtime
  failures.

- Packages can migrate before their upstream dependencies have migrated.  In so
  far as a packages is able to correctly predict how its upstream dependencies
  will eventually null-annotate their code, it should not have to re-migrate
  after those packages opt in.

## Proposed roadmap

### Summary

Non-nullable types will be rolled out as an opt-in feature.  At some point in
the indefinite future, this may become the default in a future major release of
Dart.  Until then, packages can opt in whenever they want.  Opting in will not
break other downstream packages or apps that have not yet migrated.

In order to facilitate the migration, there will be two levels of null checking:
weak null checking and strong null checking.  Until all of the code in a program
has opted in to strong null checking, only a subset of null errors will be
caught, and it will still be possible to get unexpected null exceptions at
runtime.

In addition to the technology for incremental migration, the Dart team will
build a tool to help modify code to be null-safe.  This tool will be run from
the command line or the IDE, and will suggest fixes to a package to make it work
with non-null types.  We don't anticipate that the tool will be able to fix all
issues for the programmer, but hope to be able to automate the bulk of the
migration.

#### Weak null checking

Weak null checking will turn on static null checks, and also add some automatic
runtime null assertions.  It will not guarantee that users won't get unexpected
null errors, since other libraries in the program may not have opted in yet.
Any null safety violations are only warnings with weak null checking.  That is,
static errors that arise only because of nullability annotations will only
appear as warnings at this level.  Similarly, runtime cast failures which only
fail because of nullability annotations may only be surfaced as warnings at this
level as well.

Weak null checking will also cause the compiler to insert checked-mode style
null checks on assignments to variables, parameters, and return values of
non-nullable type.  These null checks will not be warnings: they will behave as
if the programmer had written the corresponding "assert" statement in the code.
This is intended to allow programmers to remove their null assertions when they
migrate their code without losing assertion checking in the period until all
code in the program has migrated.  Once all code in the program has migrated,
these checks should be provably redundant and do not need to be inserted.

Concretely, opting in to weak null checking will proceed as follows:
- The programmer opts into the weak null checks by marking their package as
  opted in.
- This will cause warnings about null-safety violations within the package (only).
  - If the opted-in code uses other packages that have opted in, then the
    programmer will see null-safety warnings from any misuses of the opted in
    APIs from the other packages.
  - If the opted-in code uses other packages that have not opted in, the
    programmer will not see any null-safety warnings from uses of those APIs.
    They are free to treat those APIs as being null-accepting or
    non-null-accepting as appropriate.
- If the programmer runs the migration tool, it will suggest fixes to get rid of
  null safety warnings as best it can.
- Any remaining warnings should be dealt with by the programmer.  However, the
  program can still be run with null-safety warnings.
- The compiler will add null assertions to code in opted-in packages whenever a
  value is assigned to a variable or parameter of non-nullable type, or is
  returned from a function with non-nullable return type.
- The compiler will warn at runtime if code casts between incompatible nullable
  types that are otherwise compatible.

#### Strong null checking

Strong null checking is turned on globally for a program on a per-compile
basis. Turning on strong null checking turns all null-safety violations into
errors.  A programmer may turn on strong null checking before all code in their
program has opted in and still run their program, provided that they have fixed
all of the null-safety errors in the opted-in portion of their program.  They
may however see new runtime errors from non-opted in code if it misuses opted-in
APIs.  Turning on strong null-checking will provide stronger protection from
null-safety violations, but still doesn't guarantee null-safety until all
libraries in the program have been opted in.  Consequently, the compiler will
still insert null assertions in opted-in code to catch null-safety violations.
With strong null checking enabled, the programmer may also encounter runtime
cast failures if their code casts between incompatible nullable types (such as
casting a `List<int?>` to a `List<int>`).

Once all of the code in a program has opted in to strong null checking, the
compiler will stop adding null assertions, and has the option of generating
better code using the static guarantees of the type system.

#### Migration

External migration will begin by releasing a stable release of Dart with
non-nullability available ("the NNBD release").  This release will contain a
migrated SDK along with full static and runtime support for non-nullable types.
Once this is released, package migration will begin, both under the auspices of
the Dart team, and independently by package authors.  Packages required for
Flutter will be migrated, and a Flutter SDK incorporating a Dart NNBD enabled
SDK and a migrated Flutter framework will be released (subject to agreement and
buy-in from the Flutter team).

The suggested process for migrating an external library published on Pub is to
opt the package in to weak null checking, and then verify that all tests for the
package run with strong null checking turned on.  This makes it more likely that
downstream packages will be able to run with strong null checking on as well
without encountering runtime cast failures in their upstream dependencies.  The
package author may publish the opted-in package as a minor version release,
since opting in will not break any downstream packages.  The published package
must specify an SDK lower bound greater than or equal to the NNBD release of
Dart.

The process for migrating an app is similar: opt the app code in, fix all of the
warnings, and get the app running with strong null checking on.

For both apps and packages, opting in after all upstream dependencies have
opted in minimizes the chances of having to make subsequent fixes.  When an
upstream dependencies opts in, new warnings may appear in opted-in downstream
code.  However, to avoid packages and apps being blocked on slow to upgrade
upstream dependencies, we plan to fully support opting in and running before
upstream dependencies have done so.

Once all code in a program has opted in, the code will be fully null safe: the
only null safety errors at runtime will be from dynamic invocations, and the
compiler will be able to take advantage of non-nullability to produce smaller
and faster code.


### Opting in

Non-nullable types will be controlled by a language opt-in as
described [elsewhere](https://github.com/dart-lang/language/issues/93).  In
short, a library may opt in via syntax in the code, or a package may opt in in
entirety.  Opting in applies only to the library or package so marked.

Within an opted-in library, unmarked types are interpreted as non-nullable, and
only types suffixed with `?` are considered nullable (with the possible
exceptions of the top types, and of course `Null` itself).  Additional syntax
and semantics are enabled for null assertions, definite assignment analysis,
type promotion.  Additional static errors and warnings are enabled.  If we
choose to move forward as proposed in this roadmap, the details of this will be
worked out by the language team over the next quarter, drawing heavily on
previous proposals.

### Reification

Nullable (and non-nullable) types are reified, and hence have a runtime effect.
So for example, casts and instance checks can distinguish between `List<int>`
and `List<int?>`.  Without runtime reification, nullability is relegated to an
odd and inconsistent state with respect to the rest of the Dart type system,
which is uniformly reified.  Null-soundness is also almost certainly impossible
to achieve in Dart without reification, and without null-soundness we can
neither derive performance benefits in our compilers, nor deliver complete
protection from null pointer errors to developers.

### Soundness

When all libraries in a program have opted in to non-nullability, the type
system is sound and both compilers and programmers can benefit from a robust
guarantee that no non-nullably typed value may be observed to be null (and hence
dynamic calls will be the only source of noSuchMethod errors on null receivers).
We believe that a sound type system provides the most value to Dart programmers
and brings us to parity with competing languages.  Specifically, we make the
following arguments.

First, Kotlin and Swift both provide the experience of a null-sound
system. Kotlin makes a couple of small exceptions to soundness discussed in
detail below.  The key point is that these exceptions are not made in the
interest of reducing implementation effort, nor because they feeel that sound
null-checking is too painful for the programmer, but rather because of
limitations of the JVM.  The overall programmer experience is of a sound null
checking system.  As a result, from an implementation standpoint in Dart, the
implementation effort required to achieve parity in the developer experience
without soundness is not noticeably less than the implementation effort required
for a fully sound system.  Put another way, we can only save implementation
effort by compromising on the developer experience relative to Kotlin and Swift.

Second, the languages that have chosen to take an unsound path (C# and
Typescript) largely seem to have been forced to do so by legacy reasons that are
less applicable to Dart.

Third, we believe that null-soundness can be leveraged by our compilers to
generate better code.  This is especially important for Dart. Languages like
Java and C# have primitive types which are implicitly soundly non-nullable. You
never pay a price for null when you use `int` in C#. In Dart, even "primitive"
types are nullable.


Soundness is discussed in more detail below, including detailed comparisons to
other languages.

### Incremental unsoundness and dynamic checking

During the migration period, null-soundness is not guaranteed.  Opted-in code
that interacts with non-opted-in code may observe null values flowing from a
non-nullably typed location.  We propose to specify some set of migration period
dynamic checks so that opted-in code can safely remove null assertions before
the migration is complete.  Depending on the measured performance impact of
these checks, we may choose to make these dynamic checks something that are
inserted in a debug mode only (either when assertions are turned on, or perhaps
controlled by a separate flag).  These dynamic checks are orthogonal to any
dynamic checking specified as part of the core feature, and will not be required
when all packages in a program have opted in.  These checks may not be
sufficient to recover full null-soundness during the migration period: that is,
even with the debug mode null guards in place, it may still be possible to see a
null pointer error in opted-in code because of interactions with non-opted-in
code.  Consider this code.

```dart
library opted_in;

void takesListNonNull(List<int> l) {

print(l[0].isEven);
}

library opted_out;

import "opted_in.dart" as oi;

oi.takesListNonNull(<int>[null]);
```

This proposal does not allow the call to `takesListNonNulll` to be statically
rejected (since the caller has not opted in), and we believe that it is better
to allow the call to be dynamically accepted (since most working code will not
be passing null to unexpected locations).  This implies that the read from `l`
might return null (as it does in this case).  We could require a null-assertion
on every single non-nullable expression: this would "catch" this error exactly
at the point of the method call (which is where the null pointer error would
happen anyway).  But it is likely that this would be prohibitively expensive to
little benefit, and so we might choose to only insert debug mode null checks on
variables, parameters, and return values (much as was done with checked mode in
Dart 1).

### Migration path

We don't necessarily need to require users to follow a "waterfall migration" in
which a library cannot opt in until after the transitive closure of its imports
have. Instead, we could support a model in which libraries can opt in whenever
they want, independently of the state of libraries they import or that import
them.

In the waterfall model, our proposal has the property that it is mostly
non-breaking for a library to opt in.  By this we mean that opting in will never
cause static errors in any non-opted-in library, and that the behavior of a
library should be the same whether it is used from an opted-in client or a
non-opted-in client.  Any new runtime errors that are caused by opting in will
either reflect an actual violation of the nullability contract (that is, a
failure of an automatically inserted dynamic null-check), or by a runtime
interaction between two opted-in libraries mediated by a non-opted-in library
(for example, reading a `List<int?>` from opted-in library A, treating it as a
`List<int>` in a non-opted in library, and then passing it on to another
opted-in library which tries to cast it to a `List<int>`).

In the package ecosystem, we likely will want to bump major version numbers of
packages that opt in despite the "mostly non-breaking" property.

In the unconstrained model, packages may choose to opt in before their upstream
dependencies.  However, when an upstream dependency opts in, they may have to
re-migrate to accommodate the breaking change.  An advantage of the
unconstrained model is that apps can migrate without having to wait for all of
their transitive dependencies to migrate.  This makes it easier for pieces of
the ecosystem to migrate, and hopefully increases the velocity of adoption.
While it may be desireable to follow a "mostly-waterfall" model, the ability to
opt in arbitrary packages avoids the issue where a single unmaintained (or hard
to migrate) package far upstream can block an arbitrary chunk of the ecosystem
from migrating.

### Language support for migration

Implicit in both of the above models (waterfall and unconstrained) is an
assumption of language support.  While in opted-in code we propose to treat
unmarked types (e.g. `int`) as non-nullable, we propose that in non-opted-in
code, unmarked types be treated as "assumed-non-nullable", both in the static
and in the reified type system.  Static nullability checking is essentially
turned off for these "assumed-non-nullable" types, both at compile time and at
runtime.

#### Why not just treat un-opted-in types as nullable?

Firstly, in the unconstrained case, this forces you to make all of the wrong
assumptions about the APIs that you use.  You must treat them as entirely
nullable, even though it is highly likely that eventually most of the types in
them will become non-nullable.  Moreover, treating them as nullable, while
safer, makes the unmigrated APIs much more painful to use.

```dart
// not_opted_in.dart
int getInt() => 3;

// opted_in.dart
import "no_opted_in.dart";

main() {
  getInt().abs(); // Error. Can't call abs() on `int?`.
}
```

Secondly, in both the waterfall and the unconstrained case, you must decide how
to deal with un-opted-in downstream dependencies.

You could choose to treat them as having been opted in (with implicitly nullable
types) by virtue of being in the same program as an opted-in package.  Either
this is massively breaking (since the package is almost certain to mis-use the
opted-in APIs), or else you treat nullability violations in the un-opted-in
packages as warnings and allow the compile to continue.  However, you still run
into the problem of runtime breakage.

```dart
library opted_in;
void test(Object f) {
    // Assert that f maps non-null ints to non-null ints
   assert(f is int Function(int)); 
   print(f(4));
}

library opted_out;
import "opted_in.dart" as oi;

// Interpreted as having type int? Function(int?)
int f(int x) => 3;
oi.test(f);
```

Before the migration of library `opted_in`, this code worked.  After migration,
it fails the assertion.

To avoid this, you could choose to turn off runtime reification of nullability
if any package in the program is not opted-in (or equivalently, have a separate
opt-in for the runtime component that requires all packages to have opted in).
The implication of this is that when runtime reification is turned on, you can
see new runtime failures, despite all packages having migrated already.

#### Why not just treat un-opted-in types as non-nullable.

This is the approach that C# takes (see more discussion of this below).

This allows code that migrates before its upstream dependencies have migrated to
make less pessimistic (but still sometimes incorrect) assumptions about the API
of its upstream dependencies.  This means that in an unconstrained migration,
multiple migrations may be necessary.

The same issues with runtime behavior changes apply in this option.

### Migration tooling

It could be extremely valuable to provide a nullability inference tool which
does best effort inference to add nullability annotations and required
null-checks to make code pass the checker.

## How do C# and Typescript deal with migration?

If nullability violations are only warnings, and there is no runtime component,
then it is possible to compile against other libraries that have not migrated
without any language support.  You may get spurious warnings, and you may have
to re-migrate your code once the libraries you depend on migrate, but you can
continue to make progress.  Moreover, it is possible for libraries to decorate
their APIs without properly migrating their internals.

Typescript and C# more or less take this approach, supporting unconstrained
library opt-in, while providing no language support for the migration.  The
warnings are all or nothing, but libraries can be provided with an interface
file (in Typescript), or can simply be worked with as if they were de-facto
non-nullable (C#). A key part of this is that nullability violations are
warnings, and they can always be suppressed or ignored.

The C# commentary calls out all of the issues with this:

> But of course you’ll be depending on libraries. Those libraries are unlikely
> to add nullable annotations at exactly the same time as you. If they do so
> before you turn the feature on, then great: once you turn it on you will start
> getting useful warnings from their annotations as well as from your own.
>
> If they add anotations after you, however, then the situation is more
> annoying. Before they do, you will “wrongly” interpret some of their inputs
> and outputs as non-null. You’ll get warnings you didn’t “deserve”, and miss
> warnings you should have had. ...
>
> After the library owners get around to adding ?s to their signatures, updating
> to their new version may “break” you in the sense that you now get new and
> different warnings from before ...

But ultimately they decided to simply go with this:

> We spent a large amount of time thinking about mechanisms that could lessen
> the “blow” of this situation. But at the end of the day we think it’s probably
> not worth it. We base this in part on the experience from TypeScript, which
> added a similar feature recently.

This path is probably not feasible if there is a runtime component of types,
since in that case the runtime behavior of libraries depends on whether or not
you compile them with the flag on or off.  This would be more feasible if we
chose to go with a static only type system, with all of the attendant
limitations.


## Why (or why not) null-soundness?  What do other languages do?

A sound type system is one in which the type of a location is guaranteed to be a
conservative approximation of the set of values which may flow there.
Concretely for nullability tracking, in a sound nullable type system a location
with a non-nullable type can never be observed to be null.  This is in contrast
to an unsound system in which some level of effort is made to stop null values
from reaching non-nullable locations, but no guarantees are provided.

```dart
void noNull(String x) { // String is non-nullable
    // In a sound system, this property access is guaranteed not to
    // cause a null pointer exception, but in an unsound system it
    // might
    x.length; 
}
```

Note that in most cases, interop can fairly abitrarily violate the static and
dynamic guarantees of the system, so we leave the question of interop on the
side.

### Why soundness?

Benefits of soundness fall into two categories: tooling benefits and
programmability benefits.

Compilers can leverage sound non-nullability to generate better code.  Null
checks can be eliminated, and better representations can potentially be chosen
for values in locations that are guaranteed to be non-null.  For example, under
suitable assumptions about the class hierarchy above it, a method which returns
a non-nullable int can be compiled to return it unboxed if it is guaranteed to
never return null.

Programmers benefit from soundness because the checking is robust.  In the
absence of soundness, they either must choose to behave as if the system is
sound and never check for null at the risk of getting unexpected nulls flowing
into their code, or else defensively check for null despite the purported
"non-nullability" provided by the type system.  Compiler inserted null checking
can help to lighten this burden, but only at the cost of performance.

### Why not soundness?

Costs of soundness also fall into two categories: tooling costs and
programmability costs.  Unsoundness is a continuum ranging from very unsound
systems which provide limited benefit to mostly sound systems that provide much
of the benefit.  Where exactly one lands on this spectrum defines the tradeoff
between tooling cost and programmer cost/benefit.  In general, making the system
"sounder" requires either more programmer effort to satisfy the static analysis,
or more tooling effort to make the static analysis understand more idioms.

Unsound systems are generally lower cost for tools because rather than doing
more difficult analysis to understand programmer idioms (e.g. definite
assignment analysis), they can choose to simply allow the potential unsoundness.
Consider this code:
```dart
int test() {
  int x; // non-nullable
  if (something) {
    x = 3;
  } else {
    x = 4;
  }
  return x;
}
```
In a sound system, either we must reject this code (at the programmer's expense)
or we must implement a suitably sophisticated analysis to understand that `x` is
always initialized before it is used.  In an unsound system, we can simply
accept this code on the assumption that the programmer knows what they are
doing.  The downside of this of course is that if the programmer fails to
initialize the variable on some path, they may get an unexpected null pointer
error somewhere else in the program.

Unsound systems can also require less effort from the programmer, since idioms
which are difficult to understand in the static analysis can simply be allowed
unsoundly.  If the programmer finds that the static analysis cannot determine
the safety of their code, they can simply opt-out.

### Soundness in other languages

It's worth considering how other languages deal with null safety, and in
particular with the question of soundness.  Here we briefly examine how Kotlin,
Swift, C# and Typescript deal with nullability.

#### [Kotlin](https://kotlinlang.org/docs/reference/null-safety.html)

Kotlin in general aims to have a sound type system.  Interop with Java can
subvert this, but the core language experience is intended to be that types can
be relied on.  There are two small exceptions to this which mean that Kotlin
cannot actually provide full null soundness.

First, Kotlin provides an unsafe cast operator that can be used to escape the type
system. This primarily arises because Kotlin is implemented over the JVM and
hence have no way to implement the reification necessary for safe casts at
composite types.
```kotlin
var nnf : (String) -> Int = { s -> s.length};
var nf : (String ?) -> Int = nnf as (String?) -> Int; // Compiler warning.
nf(null);  // Will cause a NPE
```
The compiler will emit a warning on the unsafe cast.

Secondly, the Java constructor semantics make it very difficult to provide a
good experience for programmers in constructors, since `this` can leak or
virtual methods can be called before the instance is initialized.  Rather than
cripple constructors, Kotlin has chosen to allow potential nullability
violations to be
introduced
[via constructors](https://kotlinlang.org/docs/reference/null-safety.html#nullable-types-and-non-null-types).

In general though, from the tooling and programmer standpoint, the intention
seems to be to present the experience of a sound system.  Kotlin does not seem
to have compromised on issues like the soundness of "smart casts" (its version
of type promotion) and definite assignment analysis.

```kotlin
class B {
    var f : String? = null;
}
void test() {
    var b : B = B();
    if (b.f != null) {
        // They do not promote b.f to a non-nullable type, since to do so
        // would be unsound.
        b.f.length; // Error, failed promotion
    }

    var ns : String? = null;
    if (ns != null) {
      // This promotion succeeds, since it is sound
      ns.length;
    }
    ns.length; // Error, possibly null
    ns = "hello";
    ns.length;  // No error, definite assignment has promoted it
}
```

In general, Kotlin seems to have chosen to be unsound **only** in places where
the limitations of the JVM leave them with no good alternatives.  Notably,
Kotlin does not seem to have done so in order to save tooling effort (since it
has in general specified quite strong static analysis rules), and it does not
seem to have done so out of concern that statisfying the static analysis would
be too burdensome to programmers (since the Kotlin system is sound even in
places where it might be considered inconvenient, such as failing to promote on
fields).

Since Dart does not share the same limitations as Kotlin in terms of living over
the JVM, we should not expect to need to be unsound in the places where it is
unsound because of JVM limitations.  The success of the Kotlin approach provides
good evidence that a sound system can be attractive to programmers since almost
the entire experience of programming in Kotlin is that of programming in a sound
system.

#### [Swift](https://developer.apple.com/documentation/swift/optional)

Swift non-nullability appears to be sound, again
excepting
[interoperation with Objective C](https://developer.apple.com/swift/blog/?id=25).
Unlike Kotlin, I have not been able to find any exceptions to this.  This is
perhaps unsurprising since as with Dart, Swift does not have to live within the
constraints of running on the JVM.

Technically, Swift takes a somewhat different approach than most object-oriented
languages in that Swift "nullable" values are actually instances of the built-in
`Optional` type.  This is observable in that the type `T??` is different from
`T?`.

```swift
let maybeMaybeString : String?? = Optional.some(nil)
let maybeString : String? = maybeMaybeString // Error
```
The swift syntax for the most part hides this distinction by building in close
syntactic support for nullable values.  The result is a system that largely
feels to the programmer like a more standard language with `null` values
inhabiting every nullable type.

As with Kotlin, Swift provides a rich set of operators for dealing
with
[nullable types conveniently](https://docs.swift.org/swift-book/LanguageGuide/OptionalChaining.html).
However, Swift takes a slightly different approach to tackling the problem of
exposing to the static analysis the results of runtime checks and operations.
Kotlin primarily deals with this by allowing definite assignment analysis and
null checks to "promote" or smart cast the type of variables.  Swift on the
other hand seems to primarily deal with this via additional language constructs
making it easy to reflect the results of runtime tests into the program.


Definite assignment does not promote from nullable type to a non-nullable type
in Swift.
```swift
var str : String?;
str = "Hello, playground"
str.sorted() // Error
```

Even guarding a use with a null check doesn't promote the type.
```swift
if str != nil {
  str.sorted() // Error
}
```

Instead, Swift provides convenient ways to both check that a value is non-nil
and bind the value to a new variable in one step.  The simplest version is the
`if let` construct.
```swift
var str : String?;
// Execute the body if `str` is non-null, binding a new variable (also named
// str here) in the inner scope with a non-nullable type
if let str = str {
  str.sorted() // Ok
}
str.sorted() // Still an error
```

This is not always convenient, since the new variable goes out of scope after
the body of the `if`, so Swift also provides a guard construct.
```swift
var str : String?;
guard let nnstr = str else {
  return;  // Must exit the enclosing scope in some way
}
nnstr.sorted() // No error
```

Swift does do some amount of definite assignment analysis in order to allow late
initialization patterns.
```swift
var str : String? = "test"
var nnstr : String;
if (str != nil) {
    nnstr = "hello"
} else {
    nnstr = "world"
}
nnstr.sorted() // No error
```

Finally, Swift provides an explicit way to mark a variable as "trusted"
non-null, which means that an implicit null-check is done on each reference.
```swift
var nnstr : String!;
nnstr.sorted();
nnstr = nil;
nnstr.sorted();
```

Swift's approach then is to provide a sound type system based around optional
values, with heavy investment in additional language constructs to make working
with potentially null values convenient to the programmer, but less investment
in sophisticated static analysis.  Swift also provides a convenient mechanism
for falling back to runtime checking with low syntactic overhead where needed.

#### [C#](https://blogs.msdn.microsoft.com/dotnet/2017/11/15/nullable-reference-types-in-csharp/)

C# recently added a prototype for non-nullability for default.  Unlike Swift and
Kotlin, C# explicitly does not aim for soundness.

> There is no guaranteed null safety, even if you react to and eliminate all the
> warnings. There are many holes in the analysis by necessity, and also some by
> choice."

There reasoning behind this is sketched out
in
[this blog post](https://blogs.msdn.microsoft.com/dotnet/2017/11/15/nullable-reference-types-in-csharp/).
The high level point is that the C# designers want to avoid a "sea of errors" on
existing code.  They are open to at some point providing a stronger option to
give sound checking, but don't believe that this is the right default for them.

I believe there are three issues in play here for C#:
- In general, they cannot achieve soundness and backwards compatibility, so
clearly they need to support unsound code at least initially.  Moreover, because
of the binary installed code base, it's not clear that they ever could get away
from having to deal with unsoundness.
- Some very common constructs in C# do not play with will non-nullability, and
would result in pervasive errors in existing code.
- They feel that some programming idioms are too painful to work around if
  checked soundly.

On the first issue, there is a massive installed base of C# code, a fair bit
of it seems to be only available in a compiled form.  This is essentially the
interop problem, but at a much larger scale both because of the large user base,
and because of the large installed base.

On the second issue, the main constructs that they call out are arrays allocated
with uninitialized elements and default constructors of structs, which leave
things uninitialized.

On the third issue, they specifically call out promoting a nullably typed field
to a non-nullable type based on a null check as an unsound pattern that they
feel is too painful to disallow.


The first of these is mostly not an issue for Dart at this point.

On the second point, arrays are likely to be much less of an issue for Dart,
since the structure of the `List` API encourages incremental building, whereas
the core `C#` `Array` type does not support this.  Default constructors may be a
place where some amount of Dart code will need to be modified, but Dart
programming style encourages objects that are initialized in
constructors, and provides good support for doing so.

This leaves the third issue.  On the face of it, this flies in the face of the
experience of other languages which have simply chosen to take the sound route
on this with apparently no repercussions (Kotlin programmers seem to live fine
with this, for example).  It's possible that their sense was that this made the
migration story of large amounts of existing C# code easier, or that they simply
felt that since they were unsound elsewhere, they might as well be here.  The
migration story may come into play for Dart, but the scale of the problem is
much smaller.

#### [Java](https://blogs.oracle.com/java-platform-group/java-8s-new-type-annotations)

Java provides nullability annotations that can be used by external tools to
provide
[sound or near-sound checking](https://checkerframework.org/manual/#nullness-checker).
The annotations are not interpreted with the language at all.  The Java
documentation
[suggests](https://blogs.oracle.com/java-platform-group/java-8s-new-type-annotations) not
relying on nullability annotations, saying "Optional Type Annotations are not a
substitute for runtime validation".

#### [Typescript](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-2-0.html)

Typescript is unsound by design.  In addition to the core unsoundness of the
type system, it specifically allows unsound nullable promotion of dotted paths.

```typescript
class Ref<T> {
  v : T;
  constructor(_v : T) {this.v = _v;}
}

function main() {
	var rn: Ref<Ref<number | null>> = new Ref(new Ref(3));
	var rn2 = rn;

	if (rn.v.v != null) {
		rn2.v.v = null;
		var x : number = rn.v.v;  // Assigns null to a non-nullable type
	}
}
```

As with other languages, Typescript provides an assertion operator `e!.foo`
which asserts that `e` is non-null.  Unlike Swift and Kotlin, this operator is
not dynamically checked.

Typescript also provides an option to do definite assignment analysis in
constructors to help enforce proper object construction.

```typescript
class IntRef {
  v : number; // Error, not definitely assigned in constructor
	constructor(_v: number) { }
}
```

As with Kotlin and Swift, Typescript does not seem to have skimped on the static
analysis work, but instead has invested fairly heavily in providing robust
checking.  Since the Typescript type system is unsound there is essentially no
way for them to provide null-soundness.  As with C# however, Typescript does
seem to have chosen to be unsound in a few places out of choice in addition to
necessity, to relieve the programmer of some of the burden of proving safety to
the type checker.  Since Typescript is purely a static layer on top of
Javascript, there is also no performance benefit to null-soundness for it.

## Issues affecting migration paths

In any of the possible paths, we have to consider what happens in the following
scenarios.

### Runtime type tests

The essential questions that needs to be answered in any proposal are the
following:
  - How are the runtime types of objects from opted-in libraries viewed in
  non-opted-in libraries?
  - How are the runtime types of objects from non-opted-in libraries viewed in
    opted-in libraries?

The following examples illustrate this question.

Consider an opted in library with the following code:

```dart
library opted_in;
// A function taking and returning a non-null int
int f(int x) => x;

void test(Object f) {
  print(f is int Function(int?));
}
test(f);
```

In a post-migration world where nullable types are reified, this should return
false.  Any migration path must decide what to do about this code.

 - Return false?
 - Return true during the migration, then switch to false later?
    - If so, then there are two migration steps
 - Don't allow the question?  Difficult in the presence of implicit checks.

In either a waterfall or an unconstrained model, we need to consider what
happens with the following:


```dart
library opted_out;

import "opted_in.dart" as oi;


// A function taking a non-null int and return null
int f(int x) {
  assert(x != null);
  return null;
}

// prints true or false?
oi.test(f);
// prints true or false?
print(oi.f is int Function(int));
```

In an unconstrained model, we must also consider the following.

```dart
library not_converted;
// A function taking a non-null int and return null
int f(int x) {
  assert(x != null);
  return null;
}

library opted_in;
import "not_converted.dart" as nc;

void test(Object f) {
  print(f is int Function(int?));
}
// Prints true or false?
test(nc.f);
```

### Cross library static checks

Consider an opted in library with the following code:

```dart
library opted_in;

int Function(int) fnn;
int Function(int?) fyn;
int? Function(int) fny;
int? Function(int?) fyy;

// A non-null top level variable
int x = 3;
// A nullable top level variable
int? y = null;
```

In a waterfall model, an un-opted-in client of this library that worked before
conversion should still work after the library has converted.  In particular,
the following code would have been statically allowed pre-conversion, and hence
should still be statically allowed posts-conversion (and should arguably
dynamically continue to work at least as well as it did pre-conversion).

```dart
library opted_out;

import "opted_in.dart" as oi;

int f(int x) => null;

void test() {
  // Assigning between nullable and non-nullable fields
  oi.x = null;
  int y = oi.y;
  oi.x = oi.y;
  oi.y = oi.x;

  // Calling methods on nullable fields
  oi.y.isEven;


  oi.fnn(null);
  int _ = oi.fny(3);

  // Assigning between higher order objects with nullable types embedded
  oi.fnn = f;
  oi.fyn = f;
  oi.fny = f;
  oi.fyy = f;
  f = oi.fnn;
  f = oi.fyn;
  f = oi.fny;
  f = oi.fyy;
}
```

In an unconstrained model, we must also consider opted-in libraries that import
non-opted-in libraries.


```dart
library not_converted;

int f(int x) => null;

int x = null;
}
```

```dart
library opted_in;

import "not_converted.dart" as nc;

int Function(int) fnn;
int Function(int?) fyn;
int? Function(int) fny;
int? Function(int?) fyy;

// A non-null top level variable
int x = 3;
// A nullable top level variable
int? y = null;

void test() {

  nc.x = null;
  nc.x = 3;
  x = nc.x;

  int y = nc.y;
  nc.x = y;

  nc.x.isEven;

  nc.f(null);
  int _ = nc.f(3);

  // Assigning between higher order objects with nullable types embedded
  fnn = nc.f;
  fyn = nc.f;
  fny = nc.f;
  fyy = nc.f;
  nc.f = fnn;
  nc.f = fyn;
  nc.f = fny;
  nc.f = fyy;
}
```


