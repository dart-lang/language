# Dart Language Versioning

[lrn@google.com](@lrhn)

Version: 1.1

## Motivation

The Dart language is evolving with new language features added in most new releases.

However, since Dart 2.0, a breaking language change is unlikely to be practically possible.

Breaking the language will require a large (and growing) body of code to be migrated.

We still want to do breaking changes, because some language changes are worth it. They just have to be worth _a lot_ to be viable. 

In order to improve the cost/benefit ratio, we can also try to reduce the _cost_. 

One approach, which we should definitely invest in, is to create tools to migrate code from one version of the language to another. Such a tool should be able to take any library or package and migrate it seamlessly to a new version of the language. Users of an unmigrated package can then migrate it themselves, perhaps aided by `pub`, when they choose to depend on the package.

However, it's not clear that all language changes will permit a clean automatable migration. For example, introducing non-nullable types requires _adding_ information that was not explicitly present in the original source: is a variable intended to be nullable or not? Static analysis may get us some of the way, but there will always be programs that cannot be analyzed precisely, but where a human programmer would easily see the _meaning_ of the code. So, automatic migration tools can at most be a help, they cannot be a full solution.

This document describes another approach to reducing the migration cost of introducing a breaking change by allowing unmigrated and migrated code to both run in the same program, which allows migration to happen over time, while keeping a valid program running at all times.

The end goal is still to migrate all code to the newest language version.

The goal of this feature is not to make future or experimental features available. We use flags for that. 
It is not intended to do conditional compilation based on SDK version.
This feature is intended for shipping code running against released SDKs and language versions, 
allowing unmigrated code targeting an older language version running alongside migrated code 
for the newest language version supported by the available SDK. 

## Language Versioning

We assume that all language changes happen in Dart stable releases. Such releases are designated by major/minor version numbers (the third number in a semantic version is the patch number, and a patch will/should not change the language, except when fixing a bug in an earlier release). At time of writing, the most recent release is version 2.1, and the next will be 2.2.

We will allow a library to select which _language version level_ it wants to be interpreted as. This can be explicitly specified in the library itself, or be implicitly applied to entire packages.

Dart tools will have a range of versions that they support.

The design allows existing code to keep running without modification, and new packages will automatically use the most recently available language level (assuming their SDK version is set to the most recent version, which most authors are likely to do).

The exact syntax isn't decided, but maybe something like:

```dart

library foo with 2.2;

```

This adds the version selection to the first declaration in the library. That may still be problematic if we want a later version to change the library declaration syntax. An alternative is to introduce a formal version declaration even earlier in the file. Perhaps we can re-use the initial comment line

```dart

#! dart -v2.2

```

or just add special comment syntax:

```dart

//#2.2 

```

which must occur before the first declaration of the library. I would prefer if the marker is part of the language syntax, not just hidden in a comment, even though that is definitely practically possible.

The syntax can be bike-shedded a lot more. The important point is that versioning uses _version_ only. You cannot opt-in to one feature of a new version, but not the rest. You either migrate or not.

When we develop new language features under an experimental flag, that flag only enables the new features for libraries that are already using the most recent SDK language version (where it makes sense for a feature to be enabled per-library) or for programs that are entirely using the most recent language version (where the new feature is inherently global).

Each package available to a program can have its own language version level associated (most likely specified in the `.packages` file). All libraries in that package will use that associated language level unless it declares a different level in the library.

The `pub` tool configures this default language level for a package based on its SDK dependency. If a package requires an SDK of `^2.2.0`, it will default to the 2.2 language level.

This means that a package cannot use features of a new SDK release without depending on that SDK release. Individual libraries can opt-in to a lower version than the package default, but not a higher one.

Unpackaged libraries (libraries with `file:` or `http:` URIs, or anything except `package:` and `dart:`) cannot use this approach to get a different default. Unpackaged libraries include *tests* in pub packages. Tools will get a `--default-package` flag that allows users to set a package that all unpackaged libraries are considered to belonging to. This should be used when running tests or other pub-package related files that are not in the Dart package. (If Dart ever gets a notion of package-privacy, this feature will allow tests to pierce the privacy of their own package, without providing a general way for code to do so).
Alternatively, unpackaged libraries can have their version specified directly on the command line for the compiler (`dart --default-version=2.2`). With no flags, neither `--default-package` or `--default-version`, unpackaged libraries default to the newest language version.


(If we allow un-packaged code to act as if it was in a package, e.g., for testing, it will inherit the package's language level, which is reasonable since that code is usually in the same pub package).

It *is* an option to only support per-package versioning. It may increase the migration cost for a package, which encourages putting it off until the latest possible moment, but it may also encourage *completing* a migration sooner instead of leaving a few less-important files hanging.

#### Recommendation

Use `//@2.2` initially in the file to trigger language version downgrade from the default to 2.2. It's a compile-time error to ask for a version larger than the default version. It's a warning to ask for the same version as the default version.

Add a `#@2.2` fragment to `.packages` paths to specify the default language version for that particular package.
This is added by `pub` when generating the `.packages` file based on the minimum required SDK of the package.

Add a `--default-package=foo` flag to all Dart program tools. A "program tool" is one that handles Dart source at the level of a single Dart program. That includes all compilers. This flag will make the program treat all un-packaged libraries (any library with a URI not starting with `package:` or `dart:`) as belonging to package `foo` for all practical purposes. This includes using the default language version for package `foo` for all unpackaged libraries.

All Dart program tools must understand these markers and flags.

All tools that handle Dart files at a *higher* level than a single program, and which recognizes Pub packages, 
should infer the default language version directly from the `pubspec.yaml` file's SDK version, 
and apply it to every file in the Pub package.

Tools that support other module systems than Pub systems should also recognize which files belong with which packages, 
and detect a language version in some way.

### Tool Cost

The described approach carries a significant cost for all Dart tools. They need to support multiple versions of the language at the same time, and need to be able to switch between the different versions on a per-library basis.

Since our plan for new language features is to develop and test them under an "experiments" flag, the tools already need to be able to turn individual features on and off. When a feature is released, we can then just keep those flags alive, but link them to the language versions instead of individual command-line flags. It does mean that the tools must be able to flip flags on a per-library basis.

The same feature should not be available under both a version flag and an experiment flag. The moment it releases, the experiment command-line flag stops working and cause a warning to be printer, until it is eventually removed.

We should deprecate old language _versions_ eventually. For example, we can _deprecate_ all language versions older than, say, six months (but probably more). Being deprecated means that you get a warning if using it, but everything keeps working. Then maybe we can remove support for deprecated language versions when we do a major-version release of the language.

Again, we should invest in tools that automate migration to new language versions, at least as well as technically possible. That tool definitely needs to know about all language versions since

2.0.

The _Dart formatter_ might be more affected than other tools, because it can be run on individual files, without having the package resolution configuration that we would piggy-back the versioning on. Since the Dart formatter still uses the analyzer for parsing, it might be handled by the analyzer. The analyzer will need version information in all cases. Defaulting to the most recent version when there is no other hint is the obvious choice. The Dart formatter also needs to be able to _output_ all supported versions, which may be complicated (especially if we do something like adding optional semicolons in a version).

Another issue is that _during_ migration, a file may not yet be at the level that the package intends.

If a package ups its SDK requirement, it also changes the default language level. 

We could add an explicit language level selection to the pubspec.yaml file, but that's going to be detrimental to migration. Instead users will have to explicitly opt out in each library. If an IDE detects a _change_ in default language level for the package being edited, it could offer to add an explicit version marker to each library, or to upgrade all files automatically.

If neither of those happen, all old files then need to be migrated, but they are then being interpreted as the newer language by parsers. The _version migration tool_ (dartfix) needs to see past the default language level. It might even need to be able to detect versions from source code (that is not always possible, any change that changes behavior of valid syntax cannot be detected either way).


## Kinds of Language Changes

Some language changes work well with this model.

A completely non-breaking language change doesn't really need a new version, 
but it can help drive adoption of a new version that also contains a breaking change. 
In either case, our tools should detect uses of features that are not guaranteed 
by the SDK version requirement of a package. 
Using such a feature should require increasing the SDK requirement to a version that actually supports the feature.

Non-breaking changes could be something as simple as allowing underscores in number literals. 

Some breaking changes are entirely local in their effect. Assume we change how `null`-guarded invocation associates, so `foo?.bar().baz()` short-circuits the entire chain of calls, not just the first one.

That affects nothing except the local code. Any library can opt in to the new behavior without affecting other libraries.

A much more complicated change would be the so-called "non-null by default".

That change would introduce new _types_, and any library interacting with the migrated library need to account for the new types in some way, and the migrated library needs to be able to call methods in non-migrated libraries too.

Most likely, the result is a very permissive model that allows old and new code to work together with a lot of extra run-time checks, but which will eventually allow fully-migrated code to be more efficient.

Any change that affects the public API of a library is non-local. Any change that changes the behavior of a shared type is non-local (and maybe impossible), and opt-in to that feature will require complicated interoperability code.

Some changes may simply not be viable via language versioning alone, and will require a feature that allows _API versioning_. For example, changing the way the `String` class works will require different libraries to see different APIs for the same `String` class. That is not supported by mere language versioning, but if we find a way to version API, we might be able to use language-level/SDK-level to select the visible API.


## Examples

### Non-breaking changes

*   Allowing `int` literals in double contexts.
*   Allowing underscores separators in number literals.

These changes can be added at any time. They change the meaning of syntax that would otherwise be a compile-time error. No existing valid code needs migration since the new syntax would not occur anywhere.


### Local Changes

*   Making null-aware operator `?.` extend to following selectors.
*   Disallow unmatched surrogates in string literals.
*   Removing a language feature (say, symbol literals).
*   Improved type promotion.
*   Improved local type inference.
*   Disallowing implicit downcasts.
*   Making the `_` identifier a non-binding pattern.

These changes affect the meaning of existing expressions. If the change is from a run-time error to a successful evaluation, it's probably still non-breaking. If it changes one successful behavior to another, or to an error, then the code needs migration. In any case, the change does not affect types or public API, only function bodies.


### API-Breaking Changes

*   Sealed classes by default (or other access control).
*   Disallowing mixins derived from classes.
*   Introducing new kinds of types (say, non-nullable types, union types or value types).
*   Changing the type hierarchy, e.g., making some type no longer extend `Object`.

These changes may change how (or whether) someone else can use existing API.

In some cases, you can keep having the old behavior, you just need to migrate carefully. In other cases (like removing a feature), that may not be possible.

What happens depends on how interoperability between migrated and non-migrated code is handled for these features. If non-migrated code can still use migrated classes as mixins, then the migration gives new code no actual advantage, but it will also not count as a breaking change for the migrated code. If non-migrated code fails when trying to use a migrated class as a mixin, then the new feature can immediately be used for optimizations. Which approach to take depends on how invasive the feature is (mixins are rare, nullable types are everywhere).

# Revisions
1.0: Initial version.
1.1: Add --default-package flag.
