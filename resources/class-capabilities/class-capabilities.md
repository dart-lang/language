With the in-progress [explicit mixin declaration syntax][6] and experiments
around [sealed classes][11], we are inching towards a world where users have
syntax to directly control the capabilities a class exposes. If we're going to
go there, it might be worth considering the full set of capabilities and what
keywords/modifiers we might use for them.

This is *not* a proposal. It's just a note to capture some earlier informal
discussions. *If* we decide to go in this direction, it might be useful source
material.

[6]: https://github.com/dart-lang/language/issues/6
[11]: https://github.com/dart-lang/language/issues/11

Here are the capabilities of a "type" that a user may want to control:

-   **"Construct" – Whether it can be constructed.** Currently, this is true iff
    it is not abstract and defines a generative constructor has a default
    constructor.

-   **"Extend" – Whether it can be subclassed.** Currently this is true if it
    has a generative or default constructor. To be subclassed from another
    library, the generative constructor must be public.

-   **"Implement" – Whether it defines an interface that can be implemented.**
    Always true inside the library, except for a few magic classes in core. If
    the type has private methods it's technically allowed but sort of broken to
    implement it outside the library.

-   **"Mix-in" – Whether it can be mixed in.** True if it does not define any
    constructors and has no superclass, I think?

In theory, any combination of these capabilities is meaningful. Here's all the
combinations and what I think they conceptually represent. For each one, I've
given them zero to two stars based on how common/typical/useful I think that
combination is. If we start looking into this seriously, I would validate this
using a real corpus.

-   **(none)** – ★ A static-only "class as a namespace".
-   **Implement** – ★★ An interface.
-   **Extend** – ★★ An abstract base class.
-   **Extend Implement** – ★★ A capability that can be implemented explicitly
    or supported by inheriting a default implementation.
-   **Construct** – ★★ A concrete sealed class.
-   **Construct Implement** – ★ A capability with a canonical but not reusable
    default implementation.
-   **Construct Extend** – ★★ An extensible concrete base class.
-   **Construct Extend Implement** – ★★ A capability that can be used, reused,
    or implemented.
-   **Mix-in** – ★ A mixin, duh.
-   **Implement Mix-in** – ★ A capability that can be implemented explicitly or
    supported by mixing in a default implementation.
-   **Extend Mix-in** – Not a useful combination. **Mix-in** covers this since
    you can always mix one of those in and extend Object.
-   **Extend Implement Mix-in** – A capability that can be implemented
    explicitly or supported by inheriting _or_ mixing in a default
    implementation.
-   **Construct Mix-in** – I'm not sure how I'd think about this one.
-   **Construct Implement Mix-in** – Not sure.
-   **Construct Extend Mix-in** – A flexibly-reusable collection of methods
    where an API can still rely on them bottoming out on some concrete code.
-   **Construct Extend Implement Mix-in** – A chunk of code you can do anything
    with.

I've sorted all of the mixin ones after the non-mixin ones and my impression is
that mixins are different enough that many of the combinations that involve
mixins aren't really useful. I believe all other combinations of
capabilities—the first eight items in the list—*are* useful and should be
expressible.

As a very rough strawman, let's try ascribing some syntax to these. We need four
distinct words to express all of the combinations. It would be simpler if we
could pick words that always represented the positive case—for example
`concrete` to mean you *can* construct instead of `abstract` to mean you
*cannot*—but that doesn't work:

1.  The case with no capabilities (i.e. a static class) would get zero words.
2.  We'd have to pick unfamiliar words that are different from other languages
    for little good reason.
3.  Some common combinations would end up with long names.

Instead, the rules are a little more complex:

-   `abstract` means it does *not* have the "Construct" capability.
-   `sealed` means it does *not* have the "Extend" capability.
-   `interface` means it has the "Implement" capability.
-   `mixin` means it has the "Mix-in" capability.
-   If it has the "Construct" or "Extend" capability, or has no capabilities at
    all, add `class`.
-   If it does not have `class`, discard `sealed` and/or `abstract`.

Going through all of the combinations gives us:

``` dart
sealed abstract class             // ★ (none)
interface                         // ★★ Implement
abstract class                    // ★★ Extend
abstract interface class          // ★★ Implement Extend
sealed class                      // ★★ Construct
sealed interface class            // ★ Implement Construct
class                             // ★★ Extend Construct
interface class                   // ★★ Implement Extend Construct
mixin                             // ★ Mix-in
interface mixin                   // ★ Mix-in Implement
abstract mixin class              // Mix-in Extend
abstract interface mixin class    // Mix-in Implement Extend
sealed mixin class                // Mix-in Construct
sealed interface mixin class      // Mix-in Implement Construct
mixin class                       // Mix-in Extend Construct
interface mixin class             // Mix-in Implement Extend Construct
```

That doesn't look too bad to me, though I'm not firmly attached to it.

---

@eernstg followed up with a different proposed set of modifiers:

I agree that Mixin doesn't blend well with Construct nor Extend, so that makes
the last 6 variants low priority. I do think that Mixin + Implement makes sense.
You did also have a single star on it in the first list, so I'd suggest that we
include that one as well. I think the combination Implement + Construct is of
little value: Preventing subclasses could ensure that the implementation of
methods is known, but that's destroyed by Implement; so I left that one out.

I think we'd need to keep the number of new keywords to an absolute minimum in
order to avoid breaking existing code using those words as identifiers -- but
everybody seems to be completely unworried about this particular issue so I'll
proceed without going into that, assuming that we'll find a way to make them
"keywords only in this location", or something like that.

In keeping with my general preference for "extensibility by default", I'd prefer
to allow `class` declarations to be implemented as well as extended. We can
achieve this by using a word for removing that capability, e.g., `direct`.

We would then have the following interpretations for the keywords: We have the
capability introducers:

* `interface` => Implement
* `class` => Implement, Extend, Construct,
* `mixin` => Mixin, Implement

Plus some capability eliminators:

* `abstract` => ~Construct
* `direct` => ~Implement
* `sealed` => ~Implement, ~Extend.

That yields:

```
sealed interface        // ★ (none)
interface               // ★★ Implement
direct abstract class   // ★★ Extend
abstract class          // ★★ Implement Extend
sealed class            // ★★ Construct
direct class            // ★★ Extend Construct
class                   // ★★ Implement Extend Construct
direct mixin            // ★ Mix-in
mixin                   // ★★ Mix-in Implement
```

I think this is a little bit more concise and puts the focus on a reasonably
useful set of cases, and I think developers might even be able to get an
intuition about what each variant will do for them. ;-)
