# Dart Language Versioning

[lrn@google.com](@lrhn)<br>
Version: 1.4<br>
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

This feature cannot support language changes that are fundamentally incompatible with earlier language versions, we do need the run-time system to be able to contain both language versions at the same time. For the same reason, this feature does not handle *platform library* changes that are not backwards compatible. The libraries are shared between the different language version libraries in a program, and must work for all of these. (The tools should still detect use of library features not supported by the minimum required SDK version for a package.)

Versioning uses _version number_ only. You cannot opt-in to one feature of a new version, but not the rest. You either migrate to that new version, or you do not. This allows us to keep the combinatorial complexity down to being (roughly) linear in the number of supported versions.

When we develop new language features under an experimental flag, that flag only enables the new features for libraries that are already using the most recent SDK language version. An experimental feature cannot be used by a library which is stuck on a lower language version. This should make complicated interaction between new features and old syntax easier to avoid, and new features are entirely incremental. 

## Program Library Level Configuration

Language versioning allows tools and compilers of an SDK to associate exactly one language version with *each library* in a program.

It does so by:

* Assigning a default language version to each Dart package.
* Assigning each Dart library to at most one Dart package.
* Making each library inherit its package’s default language version unless it specifies a library-specific language version override.
* Defaulting to the most recent language version if there is no other hint.

### Package Default Language Version

A language tool (like a compiler or analyzer) needs to derive this information for *all* packages available to the program it is processing. To this end, we record a language version for each available package in the new [`.dart_tool/package_config.json`](https://github.com/dart-lang/language/blob/master/accepted/future-releases/language-versioning/package-config-file-v2.md) file (which replaces `.packages` as the package configuration file), and this language version is used to define the *default* language version for all libraries in that package. Each individual library can override the default language version if necessary.

The `.dart_tool/package_config.json` file is a JSON formatted text file which declares a number of named packages with a root and a package URI root directory for each. The SDK version for a specific package is added as an extra `languageVersion` property on the JSON object for the package.  The package configuration file is generated automatically by the `pub` tool as documented in the file’s specification.

Example package entry:

```ini
 {
   "name": "quiver",
   "rootUri": "../../.pubcache/quiver/1.3.17/",
   "packageUri": "lib/",
   "languageVersion": "2.8"
 } 
```

This specifies that the `quiver` package has a default language version of 2.8.

If an entry in the `package_config.json` file contains no language version entry (the `"languageVersion"` entry is optional), or there is no `package_config.json` file available (yet), the compiler defaults the package to the most recent language version supported by the SDK processing the package. If an entry contains an invalid `dart` version value, any other value which is not two decimal integers with a `.` between them, then tools which need the version should report an error.

Tools will not have a language default version available for the current package until a `package_config.json` file has been generated by running `pub get`. Any tool able to understand Pub package layout *may* use the most recent stable language version available to the minimum SDK version allowed by the  `pubspec.yaml` of the current package, rather than rely on an entry in the `package_config.jsos` file. A lack of a `package_config.json` file is only an issue for *new* packages, or packages with no dependencies, because otherwise the package is mostly unusable until you run `pub get` anyway. A new package is likely to want to be run at the most recent language version, so this is not a major problem. An IDE which reruns `pub get` after each change to `pubspec.yaml` will keep the `package_config.json` file up-to-date.

### Package Library Language Version

The *default* language version of a Dart library is the default language version of the package that the library belongs to. If the library does not belong to a package, it has no default version. Which package a file belongs to is defined by the `.dart_tool/package_config.json` file.

The package configuration file assigns both a root directory and a package URI root directory to a package, where the latter must be contained in the former. The package configuration specification states how these directories may overlap, and the package configuration is used to associate each file to at most one package. A file belongs to a package if its path is inside the package’s declared root directory and not inside any nested package’s root directory. A file with a `package:packageName/…` URI belongs to the package with name `packageName`. *(This is effectively the same as resolving the package URI to a file URI and then figuring out which package that file URI belongs to.)*

For a Pub package, the root directory will typically be the package directory, and the package URI root is the `lib/` directory inside the package directory. 

This means that all Dart libraries in, e.g., `test/` and `bin/` directories of a Pub package are considered as belonging to the package, not just the libraries accessed using `package:` URIs.

### Individual Library Language Version Override

A library is assigned the default language version of its package unless it specifies a different language version in the library itself.

This can be used for the case where not all libraries of package have yet been migrated to the newer semantics, which allows gradual migration of a single package, or where we generate code adapted to the current SDK, allowing the code generator to use new features that the package itself doesn't know of yet.

The syntax for choosing a different language version than the default is a single source line consisting only of a single-line comment of the form `// @dart = 2.0` (exactly two slashes, the string `@dart`, an `=`, and a version string which is two decimal numerals separated by `.`) in the initial part of the file, prior to any language declarations. It can be preceded by a `#!` line or by other comments, but not by a `library` declaration or any other declaration. Whitespace (space and tabs) are allowed everywhere except between the slashes, inside the `@dart` string and inside the version string. The comment must be an actual single-line comment, and not, say, a line of that form embedded in a block comment. (Block comments traditionally start lines with a `*` character, but that is purely convention, so it would be possible to have a line containing just  `//@dart=2.3` inside a block comment. That will not count as a language version override marker.) If there is more than one such marker, only the first one applies, but tools are encouraged to warn about the extra unused markers.

*When a published Pub package wants to use a new published language feature, the package itself must require a sufficient SDK version to support the feature. This also updates the package's default language version to the higher version and changes to the higher language version everywhere. In order to not have to migrate every library in the package immediately, the author can mark unmigrated packages as such, putting them back at the earlier language version they are compatible with. For a non-breaking language change, such marking is not necessary since the "unmigrated" libraries are already compatible with the newer language version.*

This does mean that if a later language version changes the *comment syntax* in a non-backwards compatible way, we may have to add further restrictions at that point. That is unlikely to happen. 

Part files *must* be marked with the same version as their library. They must always be treated the same way as the library they belong to, so it is a compile-time error if a part file has a different language version override than its library. It is also a compile-time error if a part file has no language version marker, and the importing library does, or vice versa. Tools that work on individual part files, like the formatter, need a marker in the part file. If there isn't one, the tool can assume that the default language version of the package applies.

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

The language version override marker can select a version *later* than the default language version of the package. The language itself is indifferent to this—as long as the version is below the current SDK version, the program can compile.

The `pub` tool, however, should reject publishing any package where any library has a language version override with a version later than the SDK version lower bound of that package. Such a package will not work if it is run on the minimal SDK that it claims to support. Since `package_config.json` files are, by default, generated based on the SDK version lower bound, such later-override libraries can only occur locally, either while developing or when using a program that generates local code before running. We allow the later version override explicitly to support code generators which can generate code depending on the current SDK.

## Migration

This feature is intended to make language feature migration easier, but that also means that migration *to* this feature must be painless. We cannot require older packages to do a large amount of work to migrate because they *can't* use this feature to alleviate the pain until they have migrated to the feature.

*The chosen design allows existing Pub packages to keep running without modification.* They will keep meaning what they currently mean, even if a later version of the language changes the language in a backwards incompatible way.

New packages will almost automatically use the most recently available language version, because a new `pubspec.yaml` is likely to be written to require the SDK version that the author is developing on.

The syntax is primitive, but easily readable.

The platform tools will need to support a *range* of language version. We will eventually deprecated and end support for old language versions.

Opting in to new version is as easy as updating the SDK version in the `pubspec.yaml` and, for breaking changes, updating any libraries that need to be updated. Keeping some libraries back at an earlier version is possible, but requires extra work. When a library is migrated, the language version marker is removed, and when all libraries have been migrated, there is nothing further for the author to do. This avoids old markers cluttering code after they have become unnecessary.

## Experiment Flags

The Dart SDK development releases makes some new language features available under experiment flags.

These are the language features which will be released in later versions of the SDK, and it allows users to prepare for that release early.

Most language changes are backwards compatible, and enabling those features globally is not a problem, but other changes are breaking. The breaking changes are exactly those where language versioning is necessary, and where we want to be able to keep some libraries back from the new version during migration, and therefore also during pre-release migration and testing.

To make experiments possible, and opting-out easy, experiments flags like `--enable-experiment=nnbd` will enable the new language feature (and language *changes*) for all libraries with *no* library language version marker *and* where the package's default language version (as reflected in the `package_config.json` file or directly from `.pubspec.yaml`) is the language version of the *current* SDK.

Libraries which need to disable the experiment must add a version override.

This applies to all experiment flags, even those for non-breaking, incremental changes.

This design is complicated for the user, they have to go through some hoops to enable experiments, but it also ensures that code that you migrate during the experimental phase will work without further change when the feature is released. All you have to do is update the SDK requirement to the stable version that releases the feature.

## Tool Cost

The described approach carries a significant cost for all Dart tools. They need to support multiple versions of the language at the same time, and need to be able to switch between the different versions on a per-library basis.

We develop and test new language features "experiments" flags, so the tools already need to be able to turn individual features on and off. When a feature is released, the feature enabling is then only based on version, and not both version and command-line flags. It does mean that the tools must be able to flip flags on a per-library basis.

The same feature should not be available under both a version flag and an experiment flag. The moment the feature releases, the experiment command-line flag stops working and cause a warning to be printed, until the flag is eventually removed.

We should deprecate old language _versions_ eventually. For example, we can _deprecate_ all language versions older than, say, six months (but probably more). Being deprecated means that you get a warning if using it, but everything keeps working. Then maybe we can remove support for deprecated language versions when we do a major-version release of the language.

Again, we need to invest in tools that automate migration to new language versions, at least as well as technically possible. That tool definitely needs to know about all language versions since 2.0.

The _Dart formatter_ might be more affected than other tools, because it can be run on individual files, or even parts of files, without having the package resolution configuration that we would piggy-back the versioning on. Since the Dart formatter still uses the analyzer for parsing, it might be handled by the analyzer's knowledge of `pubspec.yaml`. The analyzer will need version information in all cases. Defaulting to the most recent version when there is no other hint is the obvious choice. The Dart formatter also needs to be able to _output_ all supported versions, which may be complicated (especially if we do something like adding optional semicolons in a version).

Another issue is that _during_ migration a file may not yet be at the level that the package intends.

So far, all planned language changes are *syntactically* backwards compatible (no existing syntax parses differently in a newer language version, even though it might change *semantics*), so it should be possible for the Dart formatter to parse and format code in a version independent manner. As long as we keep this true, having breaking changes only in the semantics, not the grammar, the problem above might not be an issue.

If a package increases its SDK requirement, it also changes the default language version. 

If an IDE detects a _change_ in default language version for the package being edited, it could offer to add an explicit version marker to each library in the package, or to upgrade all files automatically—because we will have a migration tool for breaking changes!

If neither of those happen, all old files then need to be migrated, but by default they are being interpreted as the newer language by parsers. The _version migration tool_ (dartfix?) needs to see past the default language version. It might even need to be able to detect versions from source code (that is not always possible, any change that changes behavior of valid syntax cannot be detected either way).

### Generated Code and Code Generators

Code generation means that all code in a package is not written by the same author. The author of a package cannot generate migrated code until the code generator has been updated, and they likely can't even add a version marker to the generated file (although code-generation tools might want to introduce that feature).

Code generating packages can either release a new version which only generates code using the new language version, so users migrate the generated code by changing the generator version, or they can have a single code generator package which can generate code for multiple language versions, and then the user has to parameterize the generation somehow.

If the generated file is a part file, then the importing library can specify the language version and stay unmigrated until the part file generator is updated.

If the generated file is a library with no language-version marker, then it may not be possible to update the package to a new language version at all until a new version of the code generator is available. On the other hand, if the generated code contains a language version marker, then it should be safe for any future language version until the chosen version becomes unsupported.

## Feature Introduction

The language versioning feature is not a feature which can be *disabled* using language versioning. Selecting a library language version prior to the introduction of language versioning cannot disable the language versioning feature used to select that version.

Also, the language features introduced prior to language versioning were not built in such a way that they can be disabled. For that reason, a library selecting any language version prior to the introduction of language versioning is equivalent to selecting the most recent language version *just* prior to language versioning. So, if language versioning is introduced with Dart version 2.8, a `//@dart=2.4` marker is equivalent to `//@dart=2.7`. Tools may (or *should*) issue *warnings* if the library uses features introduced in Dart versions 2.6 or 2.7, but the code should compile.

This approach ensures that any code that currently compiles will keep compiling.

We might consider introducing an `–enable-experiment=language-versioning` flag, but because of the above treatment of prior versions, it would not actually do anything for any feature which is not introduced along with the language versioning feature, and in that case, that feature would have its own experiments flag. As such, there need not be any public language versioning experiment flag. We may have one anyway for testing.

Features introduced along with, or later than, the language versioning feature must be disabled for libraries running an earlier language version than where the feature was introduced.

### Testing

Testing the feature is tricky because we don’t have any future versions of the SDK available, and prior versions ignore versioning. It might be useful to allow the SDK to change its *own* version for testing purposes.

## Examples

### Manual Upgrade

Assume NNBD is released in Dart version 2.9.0.

The package `floo` wants to use NNBD, so it changes its `pubspec.yaml` to contain:

```yaml
environment:
  sdk: "^2.9.0"
```

and runs `pub get` or `pub upgrade`. The IDE may do that automatically after any change to `pubspec.yaml`, or you can do it manually.

The `pub` tool rewrites the `.dart_tool/package_config.json` file to contain the lines:

```json
{
  "name": "floo",
  "rootUri": "./",
  "packageUri": "lib/",
  "languageVersion": "2.9"
}
```

along with the similar entries for all the third-party packages.

Now nothing compiles because all the `floo` libraries are written for Dart 2.8. 

The user then goes through every `.dart` file in the package and either upgrades them to NNBD or adds an 

```dart
// @dart=2.8
```

comment at the top. 

Over time, they migrate all the libraries to NNBD, removing the `@dart=2.4` comments one by one. When they are done with that, the code is completely migrated.

### Automatic Upgrade (Speculative)

The user runs the Dart *upgrade tool* (might be `dartfix`, might be a specialized tool) and tells it to update the current package to language version 2.9. 

The tool updates the `pubspec.yaml` file to SDK version `^2.9.0` and runs `pub upgrade`. It remembers the original version, so it knows which upgrades to apply.

It then goes through all `.dart` files in the package, at least in `lib/`, `test/`, `bin/` and `web/`,  but potentially any `.dart` file it can find that belongs to the same package (it might have to recognize a nested `.dart_tool/package_config.json` file representing a separate nested package), while somehow avoiding generated code, and upgrades each file from the original version to version 2.9. That may do several incremental upgrades if it needs to go from 2.5 to 2.9.

If the user asked for an *optimistic* upgrade, the upgrade tool does its best to analyze the code and insert the needed `?` and `!` operators, along with any other necessary changes to make the code compile. If not, it just inserts `//@dart=2.8` in each file which does not already have a language version marker, where `2.8` was the language version of the minimal SDK accepted by the original `pubspec.yaml` file. Any file which already has, say, a `//@dart=2.1` comment will just be kept at that version (unless there is perhaps a `--force` option to make it be upgraded anyway).

The optimistic upgrade from version 2.5 to 2.9 will go through all the intermediate language versions and upgrade to each (if there is an upgrade to do), before doing the NNBD upgrade. The migration may get easier if you take it one step at a time.

## Revisions

1.0: Initial version (adapted from [strawman proposal](<https://github.com/dart-lang/language/blob/master/working/0093%20-%20Gradual%20Language%20Change%20Migration/0094%20-%20Per%20Library%20Language%20Version%20Selection/strawman.md>)).

1.1: Update specification after rewiew.

- Update `.packages` file format to contain entire SDK version.
- Restrict override syntax to only `// @dart = 2.3` format.
- Specify experiment flag behavior.
- Change `*:defaultPackage` to `:defaultPackage` because `*` was already a valid package name in the [`.packages` file specification](<https://github.com/lrhn/dep-pkgspec/blob/master/DEP-pkgspec.md>).

1.2: Require language version markers in part files when the library has one.

1.3: Restructure and cleanup.

- Allow language version markers above the package default level (for generated code).
- State that the version used from `pubspec.yaml` is the lower bound, whether inclusive or exclusive, and that the language version is the major/minor versions of that.

1.4:  Update to use new `package_config.json` file.
