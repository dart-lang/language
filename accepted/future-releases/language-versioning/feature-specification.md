# Dart Language Versioning

[lrn@google.com](@lrhn)<br>
Version: 1.3<br>
Status: Ready for implementation.

## Motivation

The Dart language is evolving with new language features added in most new releases.
Since Dart 2.0, a breaking language change is unlikely to be practically possible.
Any breaking of the language requires a large (and growing) body of code to be migrated.

We still want to do breaking changes, because some language changes are worth it. They just have to be worth _a lot_ to be viable.
In order to improve the cost/benefit ratio, we can also try to reduce the _cost_. 

We will definitely invest in tools to migrate code from one version of the language to another. Such a tool should be able to take any library or package and migrate it seamlessly to a new version of the language.

However, not all language changes will permit a clean automatable migration. For example, introducing non-nullable types requires _adding_ information that was not explicitly present in the original source: is a variable intended to be nullable or not? Static analysis may get us some of the way, but there will always be programs that cannot be analyzed precisely, but where a human programmer would easily see the _meaning_ of the code. So, automatic migration tools can at most be a help&mdash;they cannot be a full solution.

This document specifies an approach to easing the migration of a breaking language change by allowing unmigrated and migrated code to both run in the same program, which allows gradual migration over time while ensuring that a valid program can still run at any stage of the migration.

The end goal is still to have all code migrated to the newest language version. This feature is designed to encourage this migration by making migration the easiest path, while still allowing an author to keep some libraries back from being migrated for a while.
The goal is not to allow code to stay unmigrated indefinitely, only to give authors *reasonable* time to perform the migration, and to migrated a large body of code gradually.

The goal of this feature is not to make future or experimental features available. We use flags for that. Those flags will still need to interact with this feature, though.
It is not intended to do conditional compilation based on SDK version.
This feature is intended for shipping code running against released SDKs and language versions, 
allowing unmigrated code targeting an older language version to run alongside migrated code 
for the newest language version supported by the available SDK. 

## Language Versioning

All significant Dart language changes happen in stable releases. Such releases are designated by major/minor version numbers (the third number in a semantic version is the patch number, and a patch will/should not change the language, except for fixing a bug in an earlier release). At time of writing, the most recent release is version 2.2, and the next will be 2.3.

This document specifies the process used to assign a *language version* to every library in a program. A language version is a major/minor version number pair like 2.3.

Then the Dart language tools must be able to handle libraries written for different language versions interacting in the same program. Most language changes are incremental and non-breaking. For those, all the tools have to do is to make sure that a library does not use a feature which was introduced after the library's language version.

For breaking changes, the tool must be able to handle multiple different versions of the language, and do so in a way that allows libraries on different language versions  to interact in a predictable and useful way. For example, the "non-nullable types by default" feature (NNBD) will have NNBD libraries with non-nullable or safely nullable types *and* unmigrated libraries with unsafely nullable types, and those libraries can send values back and forth between them. This is where the main complication lies, and that is beyond the scope of this document which only specifies how we assign language versions to individual libraries.

This feature cannot support language changes that are fundamentally incompatible with earlier language versions, we do need the run-time system to be able to contain both language versions at the same time. For the same reason, this feature does not handle *platform library* changes that are not backwards compatible. The libraries are shared between the different language level libraries in a program, and must work for all of these. (The tools should still detect use of library features not supported by the minimum required SDK version for a package.)

Versioning uses _version number_ only. You cannot opt-in to one feature of a new version, but not the rest. You either migrate to that new version, or you do not. This allows us to keep the combinatorial complexity down to being (roughly) linear in the number of supported versions.

When we develop new language features under an experimental flag, that flag only enables the new features for libraries that are already using the most recent SDK language version. An experimental feature cannot be used by a library which is stuck on a lower language level. This should make complicated interaction between new features and old syntax easier to avoid, and new features are entirely incremental. 

## Program Library Level Configuration

Language versioning will allow the tools and compilers of an SDK to associated a language version with *each library* in a program.

A language tool (like a compiler or analyzer) needs to have access to this information for *all* packages available to the program it is processing. To this end, we record an SDK version for each available package in the `.packages` file, along with the path to the source files, and this SDK version is used to define the default language level for all libraries in that package. An individual library can override the default language level if necessary.

The `.packages` file is an `.ini`-file like text file with package names as keys and URI references as values. The SDK version for a specific package is written as a *fragment* on that URI reference.  The `.packages` file is generated automatically by the `pub` tool, which will need to be updated to generate the new format.

Example:

```ini
quiver:../../.pubcache/quiver/1.3.17/lib#dart=2.5.3-dev.2
```

This specifies that the `quiver` package requires SDK version 2.5.3-dev.2, and it therefore has a default language level of 2.5 (the major and minor version of the semantic version), which is the most recent stable language version available to all SDKs allowed by the package.

If an entry in the `.packages` file contains no language version fragment, or there is no `.packages` file yet, the package defaults to the most recent language version supported by the SDK processing the package. If an entry contains an invalid `dart` version value, `#dart=arglebargle` or `#dart=` or any other value which is not a semantic versioning version, or multiple `dart=` entries, then tools which need the version should report an error.

Tools will not have a language default version available for the current package until a `.packages` file has been generated by running `pub get`. Any tool able to understand Pub package layout may use the `pubspec.yaml` file for the SDK version of the current package rather than rely on an entry in the `.packages` file. A lack of a `.packages` file is only an issue for *new* packages, or packages with no dependencies, because otherwise the package is mostly unusable until you run `pub get` anyway. A new package is likely to want to be run at the most recent language version, so this is not a major problem. An IDE which reruns `pub get` after each change to `pubspec.yaml` will keep the `.packages` file up-to-date.

The fragment part of the `.packages` file should be assumed to contain more than one "property" encoded using the [`application/x-www-form-urlencoded`](https://en.wikipedia.org/wiki/Percent-encoding#The_application.2Fx-www-form-urlencoded_type) format (`&`-separated entries of `=`-separated key and value pairs, each key and value URL-encoded as needed). The `dart` property is the only one used to find the default language version of the package, and it is always entirely in ASCII, so no decoding should be necessary.

#### Non-`package:` Libraries

Non-`package:` libraries (libraries with `file:` or `http:` URIs, anything except the schemes `package:` and `dart:`) cannot use this approach to get a default language version. Non-`package:` libraries include those in the `test/` and `bin/` directories of a Pub package.

We extend the `.packages` file with an extra entry which specifies the package of non-`package:` files. The entry has the form `:quiver` (an entry for the empty package name), which would mean that such files are considered part of the `quiver` package for any purpose where that matters, including choosing the default language level. It is intended as the name of the "current Pub package".

With no default package in the `.packages` file, non-`package:` libraries default to the newest language version supported by the current SDK.

This feature makes non-`package:` code act as if it was in a package (even if its URI does not start with `package:`), which is reasonable since that code is usually in the same *Pub* package, just not in the exported Dart package. 

It's also here an issue that non-`package:` files in a Pub package are not recognized as part of the same Pub package until a `.packages` file has been generated by running `pub get`. Any tool able to understand Pub package layout should use `pubspec.yaml` directly for the default language version of the current package, and they should consider libraries outside of `lib/` as being in the same package as well. Other tools tend to require a `.packages` file anyway.

It might be practical to allow a `--default-package` command line override as well, but it isn't essential. We can add it if we find an actual use-case.

If we ever add other features that are package-local (like package privacy), the non-`package:` files in the same pub package would get those as well.

#### Generating `.packages`

The `pub` tool needs to generate the `.packages` file.

Each Pub package already defines which _SDK versions_ it can be used on using its `pubspec.yaml` SDK version constraint.

A current Pub package can have its SDK version specified like the following:

```yaml
environment:
  sdk: '>=2.1.0-dev.5.0 <3.0.0'
```

We define the *SDK version lower bound* of a package with a `pubspec.yaml` SDK version constraint as the semantic version occurring in the lower bound of the SDK constraint. In the example above, the lower bound is `2.1.0-dev.5.0`. If the lower bound had used `>` instead of `>=`, the version would be the same. That SDK version is the latest SDK version which is not later than any SDK version which would be accepted by the constraint.

The `pub` tool reads the `pubspec.yaml` file of the current package, and all packages that this package recursively depends on (in many versions, then it uses constraint solving to pick a specific version of each), and writes the `pubspec.lock` and `.packages` file. Doing this, it sees the SDK requirement of each package that is available to the current package, and it writes the associated SDK version lower bound as the `dart=` version of each package in the `.packages` file. It then writes the current package as the non-package default package.

If a `pubspec.yaml` does not contain a minimum SDK version, the default language level will be the most recent level supported by the SDK that is processing the `pubspec.yaml` file. This may be breaking if a new SDK comes out with a breaking language change, but it is also an incredibly unsafe practice to have a package without bounds on the SDKs it claims to be able to run on.

#### Individual Library Language Version Override

We further allow an individual library in a package to select a *different* language version than the default language version of its package, for the case where that library has not yet been migrated to the newer semantics, which allows gradual migration of a single package, or where we generate code adapted to the current SDK, allowing the code generator to use new features that the library doesn't know of yet.

The syntax for choosing a different language level than the default is line consisting only of a single-line comment of the form `// @dart = 2.0` (exactly two slashes, the string `@dart`, a `=`, and a numeral which is two decimal numerals separated by `.`) in the initial part of the file, prior to any language declarations. It can be preceded by a `#!` line or by other comments, but not by a `library` declaration or any other declaration. Whitespace (space and tabs) are allowed everywhere except between the slashes, inside the `@dart` string and inside the version numeral. The comment must be an actual single-line comment, and not a string of that form embedded in a block comment. Block comments traditionally start lines with a `*` character, but that is purely convention, so it would be possible to have a line containing just  `//@dart=2.3` inside a block comment. That will not count as a language version override marker. If there is more than one such marker, only the first one applies, but tools are encouraged to warn about the extra unused markers.

As soon as any library in a Pub package requires the new language feature, the package itself must require a sufficient SDK version to support the feature. This also updates the package's default language version to the higher version. In order to not have to migrate every library in the package immediately, the author can mark unmigrated packages as such, putting them back at the language version they are compatible with. For a non-breaking language change, such marking is not necessary since the "unmigrated" libraries are already compatible with the newer language version.

This does mean that if a later language version change the *comment syntax* in a non-backwards compatible way, we may have to add further restrictions at that point. That is unlikely to happen. 

Part files must be marked with the same version as their library. They must always be treated the same way as the library they belong to, so it is a compile-time error if a part file has a different language level override than its library. It is also a compile-time error if a part file has no language version marker, and the importing library does, or vice versa. Tools that work on individual part files, like the formatter, needs a marker in the part file. If there isn't one, the tool can assume that the default language version of the package applies.

All tools processing source files must be able to recognize this override marker and process the library accordingly. 

**Examples:**

```dart
#! /bin/dart
// This library is yadda, yadda, exceptional, yadda.
// @dart = 2.1
library yadda;
```

or

```dart
/*
 * This library is yadda, yadda, exceptional, yadda.
 */
// @dart=2.1
import "dart:math";
```

or

```dart
// @dart = 2.1
part of old.library.name;
```

The language level override marker can choose a version *later* than the default level of the package. The language itself is indifferent to this, as long as the version is below the current SDK version, the program can compile.

The `pub` tool, however, should reject publishing any package where any library has a language version override with a version later than the SDK version lower bound of that package. Such a package will not work if it is run on the minimal SDK that it claims to support. Since `.packages` files are, by default, generated based on the SDK version lower bound, such later-override libraries can only occur locally, either while developing or when using a program that generates local code before running. We allow the later version override explicitly to support such code generators which can generate code depending on the current SDK.

#### Option: Symbolic Version Names

We *may* want to consider introducing symbolic names for versions mentioned in library language version tags. The most likely reason to have such a tag is that you want to stay *before* a particular breaking change, say non-nullable types by default (NNBD). It would be convenient to be able to write `//@dart<nnbd` to pick the version just before NNBD was introduced, instead of having to remember whether that was 2.4 or 2.5 (and recognizing `//@dart=2.4` as being an opt-out of the NNBD change). This should still not be a way to opt out of individual features, just a way to specify a specific version number in a more readable way.

This feature is not required, and it might even not be desired. It's not clear whether it will reduce user confusion, or increase it. The syntax for library SDK version is a comment, so there is no syntax support to worry about.
For now, we can do without the feature, and we can add it later if it is in demand.

## Migration

This feature is intended to make language feature migration easier, but that also means that migration *to* this feature must be painless. We cannot require older packages to do a large amount of work to migrate because they *can't* use this feature to alleviate the pain until they have migrated to the feature.

*The chosen design allows existing Pub packages to keep running without modification.* They will keep meaning what they currently mean, even if a later version of the language changes the language in a backwards incompatible way.

New packages will almost automatically use the most recently available language level, because a new `pubspec.yaml` is likely to be written to require the SDK version that the author is developing on.

The syntax is primitive, but easily readable.

The platform tools then need to support a *range* of language version. We will eventually deprecated and end support for old language versions.

Opting in to new version is as easy as updating the SDK version in the `pubspec.yaml` and, for breaking changes, updating any libraries that need to be updated. Keeping some libraries back at an earlier version is possible, but requires extra work. When a library is migrated, the language version marker is removed, and when all libraries have been migrated, there is nothing further for the author to do. This avoids old markers cluttering code after they have become unnecessary.

## Experiment Flags

The Dart SDK development releases makes some new language features available under experiment flags.

These are the language features which will be released in later versions of the SDK, and it allows users to prepare for that release early.

Most language changes are backwards compatible, and enabling those features globally is not a problem, but other changes are breaking. The breaking changes are exactly those where language versioning is necessary, and where we want to be able to keep some libraries back from the new version during migration, and therefore also during pre-release migration and testing.

To make experiments possible, and opting-out easy, experiments flags like `--enable-experiment=nnbd` will enable the new language feature (and language *changes*) for all libraries with *no* library language level marker *and* where the package's minimum SDK version (as reflected in the `.packages` file or directly from `.pubspec.yaml`) is exactly the *current* SDK's version.

The SDK's version can be found in the `version` file of the SDK installation directory. Copying that string verbatim into your package's `pubspec.yaml` as, for example,

```yaml
environment:
    sdk: "^2.2.1-edge.c2dc4a54b8ca5463473d100c5d69aed49b4ba971"
```

(then running `pub` to generate the `.packages` file) *and* passing the experiment flag to the compiler/analyzer will treat all libraries that are not opted out (by having a language level marker) as using the experimental language feature.

This applies to all experiment flags, even those for non-breaking, incremental changes.

It is as if the experiment flag changes the meaning of `#dart=<current SDK version>` into `#dart=<next SDK version>` and then the SDK acts like it is a next version of the SDK, where (some of) the experimental features are now enabled.

This design is complicated for the user, they have to go through some hoops to enable experiments, but it also ensures that code that you migrate during the experimental phase will work without further change when the feature is released. All you have to do is update the SDK requirement to the stable version that releases the feature.

(We may want to have a way to enable experiments globally for a package, so the user doesn't have to pass `--enable-experiment=nnbd` to every tool they call, including those that they are not calling directly).

## Tool Cost

The described approach carries a significant cost for all Dart tools. They need to support multiple versions of the language at the same time, and need to be able to switch between the different versions on a per-library basis.

We develop and test new language features "experiments" flags, so the tools already need to be able to turn individual features on and off. When a feature is released, the feature enabling is then only based on version, and not both version and command-line flags. It does mean that the tools must be able to flip flags on a per-library basis.

The same feature should not be available under both a version flag and an experiment flag. The moment the feature releases, the experiment command-line flag stops working and cause a warning to be printed, until the flag is eventually removed.

We should deprecate old language _versions_ eventually. For example, we can _deprecate_ all language versions older than, say, six months (but probably more). Being deprecated means that you get a warning if using it, but everything keeps working. Then maybe we can remove support for deprecated language versions when we do a major-version release of the language.

Again, we should invest in tools that automate migration to new language versions, at least as well as technically possible. That tool definitely needs to know about all language versions since 2.0.

The _Dart formatter_ might be more affected than other tools, because it can be run on individual files, or even parts of files, without having the package resolution configuration that we would piggy-back the versioning on. Since the Dart formatter still uses the analyzer for parsing, it might be handled by the analyzer's knowledge of `pubspec.yaml`. The analyzer will need version information in all cases. Defaulting to the most recent version when there is no other hint is the obvious choice. The Dart formatter also needs to be able to _output_ all supported versions, which may be complicated (especially if we do something like adding optional semicolons in a version).

Another issue is that _during_ migration, a file may not yet be at the level that the package intends.

So far, all planned language changes are *syntactically* backwards compatible (no existing syntax parses differently in a newer language version, even though it might change *semantics*), so it should be possible for the Dart formatter to parse and format code in a version independent manner. As long as we keep this true, having breaking changes only in the semantics, not the grammar, the problem above might not be an issue.

If a package increases its SDK requirement, it also changes the default language level. 

If an IDE detects a _change_ in default language level for the package being edited, it could offer to add an explicit version marker to each library in the package, or to upgrade all files automatically—because we will have a migration tool for breaking changes!

If neither of those happen, all old files then need to be migrated, but they are then being interpreted as the newer language by parsers. The _version migration tool_ (dartfix?) needs to see past the default language level. It might even need to be able to detect versions from source code (that is not always possible, any change that changes behavior of valid syntax cannot be detected either way).

### Generated Code and Code Generators

Code generation means that all code in a package is not written by the same author. The author of a package cannot generate migrated code until the code generator has been updated, and they likely can't even add a version marker to the generated file (although code-generation tools might want to introduce that feature).

Code generating packages can either release a new version which only generates code using the new language version, so users migrate the generated code by changing the generator version, or they can have a single code generator package which can generate code for multiple language versions, and then the user has to parameterize the generation somehow.

If the generated file is a part file, then the importing library can specify the language version and stay unmigrated until the part file generator is updated.

If the generated file is a library with no language-version marker, then it may not be possible to update the package to a new language version at all until a new version of the code generator is available. On the other hand, if the generated code contains a language version marker, then it should be safe for any future language version until the chosen version becomes unsupported.

## Examples

### Manual Upgrade

Assume NNBD is released in Dart version 2.5.0.

The package `floo` wants to use NNBD, so it changes its `pubspec.yaml` to contain:

```yaml
environment:
  sdk: "^2.5.0"
```

and runs `pub get` or `pub upgrade`. The IDE may do that automatically after any change to `pubspec.yaml`, or you can do it manually.

The `pub` tool rewrites the `.packages` file to contain the lines:

```ini
:floo
floo:lib/#dart=2.5.0
```

along with the similar lines for all the third-party packages.

Now nothing compiles because all the `floo` libraries are written for Dart 2.4. 

The user then goes through every `.dart` file in the package and either upgrades them to NNBD or adds an 

```dart
// @dart=2.4
```

comment at the top. 

Over time, they migrate all the libraries to NNBD, removing the `@dart=2.4` comments one by one. When they are done with that, the code is completely migrated.

### Automatic Upgrade (Speculative)

The user runs the Dart *upgrade tool* (might be `dartfix`, might be a specialized tool) and tells it to update the current package to language version 2.5. 

The tool updates the `pubspec.yaml` file to SDK version `^2.5.0` and runs `pub upgrade`. It remembers the original version, so it knows which upgrades to apply.

It then goes through all `.dart` files in the package, at least in `lib/`, `test/`, `bin/` and `web/`,  but potentially any `.dart` file it can find, while somehow avoiding generated code, and upgrades each file from the original version to version 2.5. That may do several incremental upgrades if it needs to go from 2.1 to 2.5 .

If the user asked for an *optimistic* upgrade, the upgrade tool does its best to analyze the code and insert the needed `?` and `!` operators to make the code compile. If not, it just inserts `//@dart=2.x` in each file, where `2.x` was the minimal SDK version accepted by the original `pubspec.yaml` file. Any file which already has, say, a `//@dart=2.1` comment will just be kept at that level (unless there is a `--force` option to make it be upgraded anyway).

The optimistic upgrade from version 2.1 to 2.5 may go through 2.2 (inserting set literals instead where possible), 2.3 (inserting list/set/map comprehensions where possible) and 2.4 (whatever that may be), before doing the NNBD upgrade. The migration may get easier if you take it one step at a time.

## Revisions

1.0: Initial version (adapted from [strawman proposal](<https://github.com/dart-lang/language/blob/master/working/0093%20-%20Gradual%20Language%20Change%20Migration/0094%20-%20Per%20Library%20Language%20Version%20Selection/strawman.md>)).

1.1: Update specification after rewiew.

- Update `.packages` file format to contain entire SDK version.
- Restrict override syntax to only `// @dart = 2.3` format.
- Specify experiment flag behavior.
- Change `*:defaultPackage` to `:defaultPackage` because `*` was already a valid package name in the [`.packages` file specification](<https://github.com/lrhn/dep-pkgspec/blob/master/DEP-pkgspec.md>).

1.2: Require language level markers in part files when the library has one.

1.3: Restructure and cleanup.

- Allow language version markers above the package default level (for generated code).
- State that the version used from `pubspec.yaml` is the lower bound, whether inclusive or exclusive, and that the language version is the major/minor versions of that.
