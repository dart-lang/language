# Dart Major Versions and Deprecations

Packages say which SDK version they depend on using an SDK version range in the
`pubspec.yaml` file, which is typically a “compatible with” constraint like
`sdk: ^3.5.0`. That means “an SDK version compatible with SDK 3.5.0” and is
traditionally taken to mean the same as `>= 3.5.0 <4.0.0`, because SemVer minor
version increments are assumed to be backwards compatible.

A Dart major-version-increment release can make breaking changes, so by default
Pub solving can’t assume that a package with an `sdk: ^3.5.0` constraint will be
satisfied by a 4.0.0 SDK, so when SDK 4.0.0 is released, there will likely be
zero packages in the world that are compatible with it. Even if all core and
tool packages are released, most packages will not be able to run `pub get` with
the new SDK.

If a Dart 4.0.0 SDK is released which supports everything 3.5.0 does, then Pub
solving can be told that and consider it compatible with a constraint of
`^3.5.0`. Most major version SDK releases will not be completely backwards
compatible, because then there is no need for a major version increment.

## Deprecation-compatible

We say that a package is _deprecation-compatible_ with an SDK release if (it has
a successful dependency solution, and) it contains no code that has errors or
deprecation warnings when analyzed with that SDK.

When preparing for a major release, we will release a prior minor-version
release with no new functionality, which will contain deprecations of all
functionality that will break in the upcoming major release, a “deprecation
watermark” release that sets the level for the next release. _(Maybe less will
actually be broken, if we choose to not make a change anyway, but not more.)_

Package authors will be informed that if they use that version (or any later
minor version) as their SDK dependency version, say as `^3.17.0` if that release
was SDK 3.17.0, it means that they _should_ be deprecation compatible with that
SDK version. The author of the package is aware of which features will be
removed or broken in the upcoming major version. _Possibly the deprecation
warnings themselves can contain that extra information. It’s deprecated, and
this time we really mean it!_

When the next major version is released, 4.0.0 in this example, Pub will
consider any package with an SDK constraint of `^3.17.0` (or any `^3.x.y` with x
&ge; 17) as deprecation compatible with SDK 4.0.0, and since all non-deprecated
functionality was retained, SDK 4.0.0 is considered compatible with the
package’s `^3.17.0` requirement.

This allows the ecosystem to prepare for an SDK major version without having to
add a major version constraint larger than any existing SDK version. It sets
expectations, and allows maintained packages to know that they are ready.
Unmaintained packages will not have a SDK constraint minimum version that is the
watermark release, so they will not automatically be considered compatible with
the next major release. That will make them unusable, but it’s very likely that
they won’t work anyway.

### Precision of deprecation compatibility

There is no guarantee that a package has no SDK deprecation warnings just
because it has a high enough min-SDK version. Warnings do not prevent
publication. We can _check_ this when we do Pana-scoring (which includes running
the analyzer) if we can recognize platform deprecations. _(We should be able to
do that, especially if we have special deprecation warnings of platform
deprecations after a watermark release.)_

There is no guarantee that if a package has no deprecation warnings, it will not
be broken. If the code uses dynamic invocations, it may still be calling a
deprecated member or calling a function with a deprecated parameter. _Anyone
using dynamic invocations are solely responsible for keeping them valid._

### Timing

The longer the time between the “deprecation watermark” release and the major
version, the more packages can have time to prepare. On the other hand, if the
time is too long, it’s tempting to release new features while waiting, which may
encourage some packages to upgrade for the features and not spend the time to
address the deprecations. If it’s *known* that there is a long time, some may
procrastinate, and eventually run out of time, after having upped the SDK
constraint minor version.

Also, we should not add any further deprecations before the next major release.
Doing so makes it impossible for users to figure out whether a deprecation needs
to be fixed before the major version or not. _Shouldn’t be an issue, adding a
deprecation before the major version increment won’t make the deprecated thing
go away any sooner._

### Language versions

Language versions support should be deprecated just like other features, causing
warnings for all packages with an SDK constraint min version which is
deprecated, and to all libraries with a language version marker with a
deprecated language version.

Language version that were deprecated in the deprecation watermark release will
be removed in the next major release, just like other deprecated features.

### Tool deprecation

SDK tools could/should also have deprecation outputs for features that will stop
working in the next major release. For consistency. (As long as the feature was
documented to begin with.)
