# Dart Language Versioning

[lrn@google.com](@lrhn)<br>
Version 1.0<br>
Status: Superceded by [feature specification](https://github.com/dart-lang/language/blob/master/accepted/future-releases/language-versioning/feature-specification.md)

This document is no longer relevant, and should only be used for historical reference. 
It has been superceeded by an actual design document.

## Motivation

The Dart language is evolving with new language features added in most new releases.

However, since Dart 2.0, a breaking language change is unlikely to be practically possible.

Breaking the language will require a large (and growing) body of code to be migrated.

We still want to do breaking changes, because some language changes are worth it. They just have to be worth _a lot_ to be viable. 

In order to improve the cost/benefit ratio, we can also try to reduce the _cost_. 

We will definitely invest tools to migrate code from one version of the language to another. Such a tool should be able to take any library or package and migrate it seamlessly to a new version of the language.

However, it's not clear that all language changes will permit a clean automatable migration. For example, introducing non-nullable types requires _adding_ information that was not explicitly present in the original source: is a variable intended to be nullable or not? Static analysis may get us some of the way, but there will always be programs that cannot be analyzed precisely, but where a human programmer would easily see the _meaning_ of the code. So, automatic migration tools can at most be a help, they cannot be a full solution.

This document specifies an approach to easing the migration of a breaking language change by allowing unmigrated and migrated code to both run in the same program, which allows gradual migration over time while ensuring that a valid program can still run at any stage of the migration.

The end goal is still to migrate all code to the newest language version. The feature is designed to encourage this migration by making it the easiest path, while still allowing an author to keep some libraries back from being migrated, at least for a while.

The goal of this feature is not to make future or experimental features available. We use flags for that. 
It is not intended to do conditional compilation based on SDK version.
This feature is intended for shipping code running against released SDKs and language versions, 
allowing unmigrated code targeting an older language version to run alongside migrated code 
for the newest language version supported by the available SDK. 

## Language Versioning

All significant Dart language changes happen in stable releases. Such releases are designated by major/minor version numbers (the third number in a semantic version is the patch number, and a patch will/should not change the language, except for fixing a bug in an earlier release). At time of writing, the most recent release is version 2.2, and the next will be 2.3.

This document specifies the process used to assign a *language version* to every library in a program.

Then the Dart language tools must be able to handle libraries written for different language versions. Most language changes are incremental and non-breaking. For those, all the tools have to do is to make sure that a library does not use a feature which was introduced after the library's language version.

For breaking changes, the tool must be able to handle multiple different versions of the language, and do so in a way that allows libraries on different language versions  to interact in a predictable and useful way. For example, the "non-nullable types by default" feature (NNBD) will have NNBD libraries with non-nullable or safely nullable types *and* unmigrated libraries with unsafely nullable types, and those libraries can send values back and forth between them. This is where the main complication lies, and that is beyond the scope of this document which only specifies how we assign language versions to individual libraries.

This feature cannot support language changes that are fundamentally incompatible with earlier language versions, we do need the run-time system to be able to contain both language versions at the same time. For the same reason, this feature does not handle *platform library* changes that are not backwards compatible. The libraries are shared between different language level libraries, and must work on all of these. (The tools should still detect use of library features not supported by the minimum required SDK version for a package.)

Versioning uses _version number_ only. You cannot opt-in to one feature of a new version, but not the rest. You either migrate to that new version, or you do not. This allows us to keep the combinatorial complexity down to being (roughly) linear in the number of supported versions.

When we develop new language features under an experimental flag, that flag only enables the new features for libraries that are already using the most recent SDK language version. An experimental feature cannot be used by a library which is stuck on a lower language level. This should make complicated interaction between new features and old syntax easier to avoid, and new features are entirely incremental. 

#### Default Language Version of Package

Each Pub package already defines which _SDK version_ it expects (and requires) using its `pubspec.yaml` SDK version constraint.

A current Pub package can have its SDK version specified like the following:

```yaml
environment:
  sdk: '>=2.1.0-dev.5.0 <3.0.0'
```

The *minimum* accepted SDK version here is used to define the *default language version* of the package. For this package, the default language version is 2.1. The default language version is the version of the language which is used to interpret the libraries of the package. A package should not use any SDK or language feature which is not available in its minimal required version, so interpreting a library at this language version should be safe.

If a `pubspec.yaml` does not contain a minimum SDK version, the default language level will be the most recent level supported by the SDK that is processing the `pubspec.yaml` file. This may be breaking if a new SDK comes out with a breaking language change, but it is also an incredibly unsafe practice to have a package without bounds on the SDKs it claims to be able to run on.

#### Individual Library Language Version Override

We further allow an individual library in a package to select an *earlier* language version than the default version of its package, for the case where that library has not yet been migrated to the newer semantics. This allows gradual migration of a single package.

As soon as any library in a package requires the new language feature, the package itself must require a sufficient SDK version to support the feature. This also updates the package's default language version to the higher version. In order to not have to migrate every library in the package, the author can mark unmigrated packages as such, putting them back at the language version they are compatible with. For a non-breaking language change, such marking is not necessary since the "unmigrated" libraries are already compatible with the newer language version.

The syntax for defaulting to a lower language level is a comment line of the form `@sdk=2.0` (allowing for whitespace except inside the `@sdk` or the version) in the initial part of the file, prior to any language declarations. So, it can be preceded by a `#!` line or by other comments, but not by a `library` declaration or any other declaration. Part files cannot be marked, they are always treated the same way as the library they belong to. All tools processing source files must be able to recognize this marker and process the library accordingly. 

Examples:

```dart
#! /bin/dart
// This library is yadda, yadda, exceptional, yadda.
// @sdk = 2.1
library yadda;
```

or

```dart
/*
 * This library is yadda, yadda, exceptional, yadda.
 * @sdk=2.1
 */
import "dart:math";
```

#### Option: Symbolic Version Names

We may want to introduce symbolic names for versions mentioned in library language version tags. The most likely reason to have such a tag is that you want to stay *before* a particular breaking change, say non-nullable types by default (NNBD). It would be convenient to be able to write `//@sdk=!nnbd` to pick the version just before NNBD was introduced, instead of having to remember whether that was 2.4 or 2.5 (and recognizing `//@sdk=2.4` as being an opt-out of the NNBD change). This should still not be a way to opt out of individual features, just a way to specify a specific version number in a more readable way.

This feature is not required, but we can add it if it seems convenient. The syntax for library SDK version is a comment, so there is not syntax support to worry about.

## Program Library Level Configuration

The features in the previous section allows each library in a single package to have an associated language level, capped from above by the minimum SDK version that the package claims to be compatible with (and capped from below by which language versions the SDK actually supports).

A language tool (like a compiler or analyzer) needs to have access to this information for *all* packages available to the program it is processing. To this end, we record the default language version for each available package in the `.packages` file, along with the path to the source files. The individual library version overrides are still available in the source files of those packages.

The `pub` tool reads the `pubspec.yaml` file of the current package, and all packages that this package recursively depends on (in many versions, then it uses constraint solving to pick a specific version of each), and writes the `pubspec.lock` and `.packages` file. Doing this, it can see the SDK requirement of each package that is available to the current package and can write this into the `.packages` file.

The `.packages` file is an `.ini`-file like text file with package names as keys and URI references as values. The default package version for a specific package is written as a *fragment* on that URI reference. 

Example:

```ini
quiver=../../.pubcache/quiver/1.3.17/lib#sdk=2.5
```

This specifies that the `quiver` package has a default language level of 2.5.

If an entry in the `.packages` file contains no language version fragment, or there is no `.packages` file yet, the package defaults to the most recent language version supported by the SDK processing the package.

The biggest issue is that tools will not have a language default version available for the current package until a `.packages` file has been generated by running `pub get`. Any tool able to understand Pub package layout should use the `pubspec.yaml` file for the language version of the current package rather than rely on an entry in the `.packages` file. This is only an issue for *new* packages, or packages with no dependencies, because otherwise the package is unusable until you run `pub get` anyway. A new package is likely to want to be run at the most recent language version, so this is not a major problem. An IDE which reruns `pub get` after each change to `pubspec.yaml` will keep the `.packages` file up-to-date.

### Unpackaged Libraries

Unpackaged libraries (libraries with `file:` or `http:` URIs, anything except `package:` and `dart:`) cannot use this approach to get a different default. Unpackaged libraries include those in the `test/` and `bin/` directories of a Pub package.

Any tool which understands Pub package layouts should treat a file in the same pub package as having the same default language level as the actual package files from the `lib/` directory.

A tool which does not understand Pub packages must get the default level to use from somewhere. We extend the `.packages` file with an extra entry which specifies the package of unpackaged files. The entry has the form `*=quiver`, which means that unpackaged files are considered part of the `quiver` package for any purpose where that matters, including choosing the default language level. It is intended as the name of the "current Pub package".

With no default package in the `.packages` file, unpackaged libraries default to the newest language version supported by the current SDK.

This treats unpackaged code to act as if it was in a package (even if its URI does not start with `package:`), which is reasonable since that code is usually in the same *Pub* package, just not in the exported Dart package. 

Other alternatives include:

- A `.packages` entry of the form `*=#sdk=2.5`which sets the default language version for unpackaged files directly. This risks having a version skew between the package libraries and the unpackaged support files in the same Pub package.
- A `--default-package=quiver` flag on all tools which works like the entry in `.packages`. We can choose to have this anyway, as an override so you don't have to edit the `.packages`, but there are no clear use-cases for it.
- A `--default-language-version=2.5` flag on all tools which sets the default language version for unpackaged libraries. 

The most user-approachable choice is to just specify the default package in the `.packages` file. This allows the `pub` tool to just write the current package's name into the `.packages` file, and all other tools can get the information from there without needing to understand Pub packages. The user never needs to write anything on a command line. Using the package name instead of just a copy of the package's language version ensures that there is no version skew.

It's also here an issue that unpackaged files in a Pub package are not recognized as part of the same Pub package until a `.packages` file has been generated by running `pub get`. Any tool able to understand Pub package layout should use `pubspec.yaml` directly for the default language version of the current package, and they should consider libraries outside of `lib/` as being in the same package as well. Other tools tend to require a `.packages` file anyway.

It might be practical to allow a `--default-package` command line override as well, but it isn't essential. We can add it if we find an actual use-case.

If we ever add other features that are package-local (like package privacy), the unpackaged files in the same pub package would get those as well.

## Migration

This feature is intended to make language feature migration easier, but that also means that migration *to* this feature must be painless. We cannot require older packages to do a large amount of work to migrate because they *can't* use this feature to alleviate the pain until they have migrated to the feature.

*The chosen design allows existing Pub packages to keep running without modification.* They will keep meaning what they currently mean, even if a later version of the language changes the language in a backwards incompatible way.

New packages will almost automatically use the most recently available language level, because a new `pubspec.yaml` is likely to be written to require the SDK version that the author is developing on.

The syntax is primitive, but easily readable.

The platform tools then need to support a *range* of language version. We will eventually deprecated and end support for old language versions.

Opting in to new version is as easy as updating the SDK version in the `pubspec.yaml` and, for breaking changes, updating any libraries that need to be updated. Keeping some libraries back at an earlier version is possible, but requires extra work. When a library is migrated, the language version marker is removed, and when all libraries have been migrated, there is nothing further for the author to do. This avoids old markers cluttering code after they have become unnecessary.

## Tool Cost

The described approach carries a significant cost for all Dart tools. They need to support multiple versions of the language at the same time, and need to be able to switch between the different versions on a per-library basis.

Since our plan for new language features is to develop and test them under an "experiments" flag, the tools already need to be able to turn individual features on and off. When a feature is released, we can then just keep those flags alive, but link them to the language versions instead of individual command-line flags. It does mean that the tools must be able to flip flags on a per-library basis.

The same feature should not be available under both a version flag and an experiment flag. The moment the feature releases, the experiment command-line flag stops working and cause a warning to be printed, until the flag is eventually removed.

We should deprecate old language _versions_ eventually. For example, we can _deprecate_ all language versions older than, say, six months (but probably more). Being deprecated means that you get a warning if using it, but everything keeps working. Then maybe we can remove support for deprecated language versions when we do a major-version release of the language.

Again, we should invest in tools that automate migration to new language versions, at least as well as technically possible. That tool definitely needs to know about all language versions since 2.0.

The _Dart formatter_ might be more affected than other tools, because it can be run on individual files, without having the package resolution configuration that we would piggy-back the versioning on. Since the Dart formatter still uses the analyzer for parsing, it might be handled by the analyzer's knowledge of `pubspec.yaml`. The analyzer will need version information in all cases. Defaulting to the most recent version when there is no other hint is the obvious choice. The Dart formatter also needs to be able to _output_ all supported versions, which may be complicated (especially if we do something like adding optional semicolons in a version).

Another issue is that _during_ migration, a file may not yet be at the level that the package intends.

If a package increases its SDK requirement, it also changes the default language level. 

If an IDE detects a _change_ in default language level for the package being edited, it could offer to add an explicit version marker to each library in the package, or to upgrade all files automatically—because we will have a migration tool for breaking changes!

If neither of those happen, all old files then need to be migrated, but they are then being interpreted as the newer language by parsers. The _version migration tool_ (dartfix?) needs to see past the default language level. It might even need to be able to detect versions from source code (that is not always possible, any change that changes behavior of valid syntax cannot be detected either way).

## Examples

### Manual Upgrade

Assume NNBD is released in Dart version 2.5.0.

The package `floo` wants to use NNBD, so it changes its pubspec to contain:

```yaml
environment:
    sdk: "^2.5.0"
```

and runs `pub get` or `pub upgrade`. This is needed when you change the SDK version, because that might affect which version of a third-party library that you use.

The `pub` tool rewrites the `.packages` file to contain the lines:

```ini
*:floo
floo:lib/#sdk=2.5
```

along with the similar lines for all the third-party packages.

Now nothing compiles because all the `floo` libraries are written for Dart 2.4. 

The user then goes through every `.dart` file in the package and either upgrades them to NNBD or adds an 

```dart
// @sdk=2.4
```

comment at the top. 

Over time, they migrate all the libraries to NNBD, removing the `@sdk=2.4` comments one by one. When they are done with that, the code is completely migrated.

### Automatic Upgrade (Speculative)

The user runs the Dart *upgrade tool* (might be `dartfix`, might be a specialized tool) and tells it to update the current package to language version 2.5. 

The tool updates the `pubspec.yaml` file to SDK version `^2.5.0` and runs `pub upgrade`. It remembers the original version, so it knows which upgrades to apply.

It then goes through all `.dart` files in the package, at least in `lib/`, `test/`, `bin/` and `web/`,  but potentially any `.dart` file it can find—while somehow avoiding generated code, and upgrades each file from the original version to version 2.5. That may do several incremental upgrades, if it wants to go from 2.1 to 2.5 .

If the user asked for an *optimistic* upgrade, the upgrade tool does its best to analyze the code and insert the needed `?` and `!` operators to make the code compile. If not, it just inserts `//@sdk=2.x` in each file, where `2.x` was the minimal SDK version accepted by the original `pubspec.yaml` file. Any file which already has, say, a `//@sdk=2.1` comment will just be kept at that level (unless there is a `--force` option to make it be upgraded anyway).

The optimistic upgrade from version 2.1 to 2.5 may go through 2.2 (inserting set literals instead where possible), 2.3 (inserting list/set/map comprehensions where possible) and 2.4 (whatever that may be), before doing the NNBD upgrade. The migration may get easier if you take it one step at a time.

## Revisions

1.0: Initial version (adapted from [strawman proposal](<https://github.com/dart-lang/language/blob/master/working/0093%20-%20Gradual%20Language%20Change%20Migration/0094%20-%20Per%20Library%20Language%20Version%20Selection/strawman.md>)).
