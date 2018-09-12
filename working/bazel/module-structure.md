The following is a reference for [`Bazel`](https://bazel.build/) (internally
called `Blaze` at Google) structures modules of Dart code, especially when
compared to external structures (i.e. via `pub`).

This is *not* a proposal, nor a commitment to build out further Bazel support
externally, but rather a reference to help guide discussions around visibility
modifiers and terminology around modular/reusable Dart code.

## Monolothic Repository

In ["Why Google Stores Billions of Lines of Code in a Single Repository"][1]
the author explain the benefits of a _Monolothic Repository_ ("Mono Repo").
Many of the constraints described in this document are due to this decision,
and be expected to be _unchangeable_ - i.e. it is quite outside of the scope
of any language (including Dart) to change these requirements.

[1]: https://cacm.acm.org/magazines/2016/7/204032-why-google-stores-billions-of-lines-of-code-in-a-single-repository/fulltext

## Typical Structure

In the Google mono-repository, there is a single root directory. Let's call it
`google` - and it is commonly referenced by tools and Bazel with a prefix of
`//`, so `//ninjacat` is logically located at `/google/ninjacat`. This root
directory is called a _workspace_.

Bazel [defines a _package_][2] as so:

> The primary unit of code organization in a workspace is the _package_. A
> package is a collection of related files and a specification of the
> dependencies among them.
>
> A package is defined as a directory containing a file named `BUILD`,
> residing beneath the top-level directory in the workspace. A package includes
> all files in its directory, plus all subdirectories beneath it, except those
> which themselves contain a BUILD file.

[2]: https://docs.bazel.build/versions/master/build-ref.html#packages_targets

As one can see, already _package_ is very different from a [`pub` package][3].

[3]: https://www.dartlang.org/guides/libraries/create-library-packages

We map the concept of `pub` packages with the following rules:

* A `package:<a>.<b>/uri.dart` resolves to `//a/b/lib/uri.dart`.
* Any other `package:<name>/uri.dart` resolves to `//third_party/dart/<name>`,
  i.e. without a `.` in the name.

### Inside a Package

Inside a package, such as `//ninjacat/app`, you can expect the following:

```
> ninjacat/
  > app/
    > lib/
    > test/
    > BUILD
```

(If the package happens to be a Dart web _entrypoint_, you might also see `web/`
and for VM binaries, you might also see `bin/`.)

However, there is another important concept, [`targets`][4]:

> A package is a container. The elements of a package are called _targets_. Most
> targets are one of two principal kinds, files and rules. Additionally, there
> is another kind of target, package groups, but they are far less numerous.

[4]: https://docs.bazel.build/versions/master/build-ref.html#targets

So, imagine the following, in the `BUILD` file:

```
dart_library(
    name = "app",
    srcs = ["lib/app.dart"],
    deps = [
         ":flags",
    ],
)

dart_library(
    name = "flags",
    srcs = ["lib/flags.dart"],
)

dart_test(
    name = "flags_test",
    srcs = ["test/flags_test.dart"],
    deps = [
        ":flags",
        "//third_party/dart/test",
    ],
)
```

Here we have _3_ targets:
* `app`, which potentially is code that wraps together application-specific
  code before being used later in the `main()` function of something in either
  `web/` or `bin/`.
* `flags`, which contains some common code for setting/getting flags.
* `flags_test`, which tests that `flags` is working-as-intended.

This concept already is quite different than a `pub` package, where all of the
files in `lib/` are accessible once you have a dependency on that package. In
fact, a common issue externally is that `pubspec.yaml` (sort of similar to
`BUILD`) is not granular enough, leading to the creation of "micro packages" 
that have a single file or capability.

### Common Patterns

Based on the above, teams tend to structure their projects _hierarchically_,
with more specific code living deeper in a sub-package. For example, imagine
the `ninjacat` project after a few more weeks:

```
> ninjacat/
  > app/
    > views/
      > checkout/
        > lib/
        > test/
        > BUILD
      > home/
        > lib/
        > test/
        > BUILD
  > common/
    > widgets/
      > login/
        > lib/
        > test/
        > testing/
          > lib/
          > BUILD
        > BUILD
```

Already we have the following "packages":

* `package:ninjacat.app.views.checkout`
* `package:ninjacat.app.views.home`
* `package:ninjacat.common.widgets.login`
* `package:ninjacat.common.widgets.login.testing`

It's common to use the [`visibility`][5] property to setup the concept of
"friend" packages, i.e. packages that are only accessible to _specific_ other
packages. In the following code, we ensure that the `login` "package" is only
accessible to packages under `app/`:

```
# //ninjacat/common/widgets/login/BUILD

dart_library(
    name = "login",
    srcs = glob(["lib/**.dart"]),
    visibility = [
        "//ninajacat/app:__subpackages__",
    ],
)
```

[5]: https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes

Another common pattern is the concept of `testonly`, and `testing` packages:

```
# //ninjacat/common/widgets/login/BUILD

dart_test(
    name = "login_test",
    srcs = ["test/login_test.dart"],
    deps = [
        "//ninjacat/common/widgets/login/testing",
        "//third_party/dart/test",
    ],
)
```

```
# //ninjacat/common/widgets/login/testing

dart_library(
    name = "testing",
    srcs = glob(["lib/**.dart"]),
    testonly = 1,
    deps = [
        "//third_party/dart/pageloader",
    ],
)
```

In this case, `package:ninjacat.common.widgets.login.testing` exposes a set of
test-only libraries that can be used, only in _test_ targets. This pattern isn't
replicable externally at all, but is _very_ common internally to avoid bringing
in test utilities and code into production applications.

## Notable Differences

### No cyclical _targets_

Dart, as the language, allows cyclical dependencies between `.dart` files 
(libraries). Bazel does _not_ allow cyclical dependencies between packages
(i.e. _targets_). So, the following is illegal in Bazel where it is fine
externally with `pub`:

```
# //ninjacat/common/foo (i.e. package:ninjacat.common.foo/foo.dart)

dart_library(
    name = "foo",
    srcs = ["lib/foo.dart"],
    dependencies = [
        "//ninjacat/common/bar",
    ],
)
```

```
# //ninjacat/common/bar (i.e. package:ninjacat.common.bar/bar.dart)

dart_library(
    name = "bar",
    srcs = ["lib/bar.dart"],
    dependencies = [
        "//ninjacat/common/foo",
    ],
)
```

Unfortunately this is quite common when you take into account the concept of
pub's `dev_dependencies: ...`. If you have a testing only package (
`angular_test`, `build_test`, `flutter_test`), which depends on the main package
but is also used within the main packages tests you have a cyclic dependency.
