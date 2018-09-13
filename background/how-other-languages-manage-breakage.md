In order to mimize hard breaking changes, we may want to introduce some kind
of pragmas or options to let users explicitly opt-in to new changes instead of
having them foisted upon them.

I did a little poking around at other languages to see how they handle this
problem.

## C/C++

Since these languages are ancient and are used very low in the stack where
stability is at a premium, they effectively never ship a breaking change.

For static changes, C++ and to a lesser extent C sometimes add new *warnings*
instead of errors. Those are considered non-breaking. Users can (and most do)
flip those warnings into errors once they have migrated to being warning-clean.
The `-Werror` flag globally turns *all* warnings into errors and the standard
practice is to enable that. This means that a new warning will, by default,
break many users, but they have an easy way to *un*-break themselves.

Users can also accommodate changes in language behavior using `#ifdef` to select
appropriate code for different language versions. Compilers make defines
available that expose the language version to the preprocessor.

Most IDEs also let users explicitly choose which version of the language they
target. This ensures they don't use features that are *newer* than they intend,
which is important to writing code today that is still compatible with older
compilers.

## Python

Python's transition from 2 to 3 has been famously difficult and long-running.
One way they ease the migration is by letting you ["import" Python 3 features
into Python 2 code][from future]:

[from future]: https://docs.python.org/2/reference/simple_stmts.html#future

```python
from __future__ import print_function
```

In Python 2, `print` is a statement whose argument is not parenthesized. In
Python 3, it's a regular function. The above import says that in this file,
`print` should be treated like a function. The scope of this is a single file.

There are seven features that can be opted into this way: nested_scopes,
generators, division, absolute_import, with_statement, print_function,
unicode_literals. (These aren't all Python 3 features. The "import from future"
has been around since Python 2.1.)

Python 2 and Python 3 are actively developed in parallel. Many Python 3 features
are back-ported to Python 2, except that users must explicitly opt into them
using the above.

This enables users to write code that works in both Python 2 and Python 3 by
explicitly opting in. In Python 3, the `from __future__` statements are still
allowed, but are no-ops.

For deployed applications, large-scale users typically explicitly control the
version of the Python runtime their app runs on. Tools like [pyenv][] and
[virtualenv][] control the Python runtime version (which also includes its core
libraries) on a per-application basis.

Python is in an interesting overlapping situation. Many Python apps run on
servers that developers control, so it would be possible for Python to be more
aggressive about breaking changes since users could simply choose to keep using
an older version of Python.

But Python is also installed by default on OS X and most Linuxes and Python is
heavily used for little scripts. A breaking change in Python can make distro
maintainers loath to take the new version for fear of breaking all of those
scripts.

In practice, Python ends up being very conservative about breaking changes to
the language and core libraries. There is a running joke that the standard
library is "[where modules go to die][die]" since they become so difficult to
change after moving into the core.

[pyenv]: https://github.com/pyenv/pyenv
[virtualenv]: https://virtualenv.pypa.io/en/stable/
[die]: http://www.leancrew.com/all-this/2012/04/where-modules-go-to-die/

## Ruby

Situationally, Ruby is similar to Python. It's dynamically typed, so most
breaking changes don't cause a program to *statically* fail, but only fail at
runtime if you happen to hit the changed API or behavior. This is both good
(more existing programs continue to run correctly) and bad (if your program is
broken, it's hard to tell without good tests).

Also like Python, deployed Ruby applications usually run on servers controlled
by developers. Tools like rvm let them control the version of Ruby used. But
Ruby is also installed by default by most distributions, so rolling forward can
be hard.

Despite that, Ruby seems to have a policy of being OK with breaking changes.
Every point release includes breaking changes, usually to core libraries. In
some cases, the VM will print a warning if you touch an API that had a breaking
change, or if you're using something that's about to break.

They may be able to get away with this in part because the Ruby ecosystem has a
very strong culture of testing. When a new version of Ruby comes out, if your
tests pass, hopefully your app was not broken. If they fail, it should point you
to what you need to upgrade.

For the in-progress Ruby 3.0, Matz and company are considering changing strings
to be frozen by default. (Ruby currently features mutable strings (!).) This is
a massively breaking change. To ease migration, they [plan to support a
comment][freeze]] to turn this behavior on on a per-file basis:

```ruby
# freeze_string: true
```

Initially, Matz was against this and considered not making the breaking change
at all to avoid needing these comments. Now, he's on board with them
specifically as a migratory feature but not something users need after moving
fully onto Ruby 3.0.

The issue discussion notes they did something similar in the past with:

```ruby
# -*- warn_indent: false -*-
```

Here, the `-*-` is the same syntax Ruby uses for the special comments to
indicate the source file's encoding.

[freeze]: https://bugs.ruby-lang.org/issues/8976

## JavaScript

JavaScript is in perhaps the worst position of all languages. Billions of lines
of extant code, many written by non-developers, all run directly from source on
billions of end user machines.

As such, it is virtually impossible to ship a breaking change to JavaScript.
It's even hard to ship new features because old clients won't support them.

In order to fix some particularly nasty legacy semantics, ES5 added "[strict
mode][]", which you opt into by placing the bare string literal `"use strict"`
in an expression statement at the top of a function or file:

[strict mode]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Strict_mode

```javascript
"use strict";
```

If you don't do this, you get the old bad behavior. This opt-in will never
expire&mdash;users in 2075 will theoretically still need to put this at the top
of every file. (In practice, by then everyone will be using another language
that compiles to JS and that transpiler will output "use strict" for them.)

In order to handle running on older browsers, users also need to tell when
*non-breaking* new features are available. They used to do this by detecting
exactly which browser and version the program was running on, but that obviously
didn't scale well.

Today, the practice is to use [feature detection][]. For example, you might be
running on a browser that doesn't support the new geolocation API. The ensure
your program doesn't die in that case, you write:

```javascript
if ("geolocation" in navigator) {
  navigator.geolocation.getCurrentPosition(function(position) {
    // show the location on a map, perhaps using the Google Maps API
  });
} else {
  // Give the user a choice of static maps instead perhaps
}
```

[feature detection]: https://developer.mozilla.org/en-US/docs/Learn/Tools_and_testing/Cross_browser_testing/Feature_detection

To avoid breakage, they instead require users to explicitly opt in. The opt-ins
never expire.

## TypeScript

TypeScript [ships breaking changes][ts break] with virtually every minor version
release.

[ts break]: https://github.com/Microsoft/TypeScript/wiki/Breaking-Changes

Sometimes, these changes are hidden behind [flags][] that users need to
explicitly turn on. Many of these start with `--strict`, like
`--strictNullChecks` which adds non-nullable types to the type system. Like
`-Werror` for C/C++, the blanket `--strict` turns them all on, which means any
theoretically opt-in change is effectively opt-*out*.

The granularity of these flags is a compilation unit, which users can manually
define. By default, many users compile their entire program with a single
invocation, which means these flags are all-or-nothing. You can see some
discussion [here][compile] of the pain that causes.

Users have [asked for more fine-grained control][per-file] but so far the
TypeScript team has said it's too complicated and makes the type system really
hard to reason about. Instead, they ask users to break their program into
multiple separate compilations and migration each of those one at a time. There
is support for using a module compiled with one set of flags from another
module, though they have sometimes [run into problems with that][problem].

[flags]: https://www.typescriptlang.org/docs/handbook/compiler-options.html
[compile]: https://github.com/Microsoft/TypeScript/issues/9432
[per-file]: https://github.com/Microsoft/TypeScript/issues/8405
[problem]: https://github.com/Microsoft/TypeScript/issues/8995

In many ways, TypeScript has an easier story. Programs are always compiled on
developer machines where they control the version of TypeScript being used. The
type system is unsound, so many changes that would be breaking in a sound system
can be considered non-breaking.

## Swift

Swift went through a very public rapid series of breaking changes when it first
launched. After Swift 3, once they had enough users pushing back, they started
to slow this down. For the transition to Swift 4, they wrote a detailed
[migration guide][] and added automated migration tools to XCode.

[migration guide]: https://swift.org/migration-guide-swift4/

They are aiming for stability now. The plan when Swift 5 ships is to have [no
more breaking changes after that][compatibility]. They are also working to
[stabilize their ABI][] so that new versions of Swift won't even require a
recompile and so that code compiled with later versions can run on older
runtimes. They say:

> Similar to Swift 4 , the Swift 5 compiler will provide a source compatibility
> mode to allow source code written using some previous versions of Swift to
> compile with the Swift 5 compiler. The Swift 5 compiler will at least support
> code written in Swift 4, but may also extend back to supporting code written
> in Swift 3.

[compatibility]: https://swift.org/source-compatibility/
[stabilize their abi]: https://swift.org/abi-stability/

**TODO: Java, C#, Kotlin, PHP?**
