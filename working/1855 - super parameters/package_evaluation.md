**TL;DR: This feature is going to be great and will be used by most superclass
constructor calls. If we enable mixing explicit and `super.` arguments at all,
then over 95% of super constructor calls will benefit. We can get even farther
but at the cost of either a more complex feature or a slight risk of users not
getting the argument order they expect.**

When there are positional `super.` parameters in the parameter list as well as
explicit positional arguments to the superclass constructor, there are multiple
ways those two lists could be merged. To get a sense of which option would make
the proposal most useful, I [scraped a corpus][cl] of ~2,000 pub packages
(~6MLOC) and ran some simple analysis.

[cl]: https://dart-review.googlesource.com/c/sdk/+/215120

Here's the results with remarks:

```
-- Potential use (59179 total) --
  46070 ( 77.849%): No: No initializer               ======================
  12446 ( 21.031%): Yes                              ======
    663 (  1.120%): No: Empty super() argument list  =
```

Of the 59,179 constructor declarations, 12,446 contain a non-empty superclass
constructor call, which means they could potentially use this feature. We ignore
the others.

```
-- Individual arguments (25097 total) --
  19522 ( 77.786%): Argument matches a parameter                        =======
   2029 (  8.085%): Named argument expression is not identifier         =
   2001 (  7.973%): Positional argument expression is not identifier    =
    750 (  2.988%): Positional argument does not match a parameter      =
    544 (  2.168%): Named argument name does not match expression name  =
    251 (  1.000%): Named argument does not match a parameter           =
```

Looking at every argument in every superclass constructor call, we find that
most (77%) do syntactically match one of the constructor parameters. That means
the expression is a simple identifier corresponding to the name of a positional
parameter, or the expression is a named expression whose name and variable are
the same as some named parameter.

```
-- Named arguments (12446 total) --
   5853 ( 47.027%): Matched all            ==================
   4868 ( 39.113%): No arguments to match  ===============
   1046 (  8.404%): Matched none           ====
    679 (  5.456%): Matched some           ===
```

For the 12,446 superclass constructor calls, we look at the entire set of named
arguments and characterize how well they would match the proposal. A "match"
means that the superclass constructor call argument has a corresponding
parameter in the subclass constructor parameter list which could potentially
become a `super.` parameter.

In almost half the constructors, every named argument would match a named
parameter. About a third of the argument lists simply don't have any named
parameters. 8% match only a subset of the named parameters.

```
-- Positional arguments (12446 total) --
   7332 ( 58.910%): No arguments to match  ======================
   3503 ( 28.146%): Matched all            ===========
   1227 (  9.859%): Matched none           ====
    179 (  1.438%): Matched prefix         =
    147 (  1.181%): Matched suffix         =
     49 (  0.394%): Matched noncontiguous  =
      9 (  0.072%): Matched middle         =
```

Likewise, we characterize the positional argument lists. This is a little more
complex because the ordering matters. These mean:

*   **No arguments to match.** There are no positional arguments at all.
*   **Matched all.** Every positional argument matched a positional parameter in
    the subclass constructor, in order.
*   **Matched none.** There are positional arguments, but none of them matched
    any subclass constructor parameters.
*   **Matched prefix.** At least one but not all positional arguments matched,
    and they all appear at the beginning of the argument list.
*   **Matched suffix.** At least one but not all positional arguments matched,
    and they all appear at the end of the argument list.
*   **Matched noncontiguous.** More than one positional argument matched, but
    there is at least one non-matching positional argument in the middle. This
    means a user couldn't convert all of the corresponding parameters to
    `super.` because there's no good way to interleave the unmatched arguments
    in.
*   **Matched middle.** At least one but not all positional arguments matched,
    and they all appear as a contiguous run somewhere in the middle of the
    argument list.

Looking at the results, more than half of the constructors don't have any
positional arguments at all. (Since we filter out constructors with no
arguments, this means they have named ones.) This is good because it means no
matter how we handle positional arguments, most constructors will be OK.

Another 28% match all positional arguments, which again means basically every
proposal will work.

```
-- Argument pattern (12446 total) --
   4538 ( 36.462%): (:s)
   2181 ( 17.524%): (s)
   1027 (  8.252%): (_)
    581 (  4.668%): (s,s)
    501 (  4.025%): (:_)
    445 (  3.575%): (:s,:s)
    207 (  1.663%): (_,_)
    201 (  1.615%): (:s,:_)
    147 (  1.181%): (s,_)
    146 (  1.173%): (:_,:_)
    137 (  1.101%): (_,s)
    136 (  1.093%): (s,s,s)
    131 (  1.053%): (:s,:s,:s)
    126 (  1.012%): (:s,:s,:s,:s,:s,:s,:s,:s,:s)
    106 (  0.852%): (:s,:s,:s,:s)
     91 (  0.731%): (s,s,s,s)
     73 (  0.587%): (s,:_)
     70 (  0.562%): (:_,:_,:_)
     69 (  0.554%): (_,:_,:_)
     67 (  0.538%): (:s,:s,:s,:s,:s)
     65 (  0.522%): (s,:s,:s)
     64 (  0.514%): (_,:s)
     62 (  0.498%): (_,:_)
     55 (  0.442%): (:s,:s,:_,:_)
     54 (  0.434%): (s,:s)
     53 (  0.426%): (_,_,_)
     48 (  0.386%): (s,s,s,s,s,s)
     39 (  0.313%): (:s,:s,:_)
     32 (  0.257%): (:_,:_,:_,:_)
     31 (  0.249%): (:s,:s,:s,:s,:s,:s)
     31 (  0.249%): (:s,:s,:s,:s,:_)
     31 (  0.249%): (s,s,s,s,s)
     28 (  0.225%): (:s,:_,:_)
     28 (  0.225%): (_,_,_,_)
     28 (  0.225%): (:s,:s,:s,:s,:s,:s,:_)
     28 (  0.225%): (:s,:s,:s,:_)
     26 (  0.209%): (:s,:s,:s,:s,:s,:s,:s,:_)
     25 (  0.201%): (s,s,:s)
     24 (  0.193%): (_,_,s)
     21 (  0.169%): (:s,:s,:s,:s,:s,:s,:s,:s)
     20 (  0.161%): (_,_,_,_,_)
     19 (  0.153%): (s,s,s,_)
     18 (  0.145%): (s,_,_)
     18 (  0.145%): (:s,:s,:s,:s,:s,:_)
     16 (  0.129%): (_,s,s)
     16 (  0.129%): (s,_,s,s)
     15 (  0.121%): (s,s,_)
     14 (  0.112%): (:s,:s,:s,:s,:s,:s,:s)
     14 (  0.112%): (:s,:s,:s,:s,:_,:_)
     14 (  0.112%): (s,:_,:_)
     13 (  0.104%): (:s,:_,:_,:_)
     12 (  0.096%): (:_,:_,:_,:_,:_)
     11 (  0.088%): (s,s,:_)
     10 (  0.080%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:_)
     10 (  0.080%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:_)
      9 (  0.072%): (s,s,_,_,:_,:_)
      9 (  0.072%): (_,s,:s)
      8 (  0.064%): (s,:s,:s,:s)
      8 (  0.064%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:_)
      8 (  0.064%): (_,:_,:_,:_)
      8 (  0.064%): (s,_,s)
      8 (  0.064%): (:s,:s,:s,:s,:s,:s,:s,:s,:_)
      7 (  0.056%): (:s,:s,:_,:_,:_)
      7 (  0.056%): (_,s,_)
      7 (  0.056%): (_,_,:s)
      7 (  0.056%): (:s,:s,:s,:_,:_)
      7 (  0.056%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      7 (  0.056%): (_,_,_,_,:s,:s,:s,:s)
      6 (  0.048%): (:s,:s,:s,:_,:_,:_)
      6 (  0.048%): (s,_,s,_)
      6 (  0.048%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:_)
      6 (  0.048%): (:s,:s,:s,:s,:s,:_,:_)
      6 (  0.048%): (s,s,s,:s,:s)
      6 (  0.048%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      6 (  0.048%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      6 (  0.048%): (_,:s,:_)
      5 (  0.040%): (_,_,:_)
      5 (  0.040%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      5 (  0.040%): (s,s,_,_,_)
      5 (  0.040%): (:s,:_,:_,:_,:_)
      5 (  0.040%): (s,s,s,s,s,s,s)
      5 (  0.040%): (s,s,_,_)
      5 (  0.040%): (_,s,:s,:s)
      5 (  0.040%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      5 (  0.040%): (_,:s,:s,:s)
      5 (  0.040%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:_,:_)
      4 (  0.032%): (s,_,_,_,_,_,s)
      4 (  0.032%): (_,:s,:s)
      4 (  0.032%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      4 (  0.032%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      4 (  0.032%): (s,_,:_)
      4 (  0.032%): (:s,:s,:s,:s,:s,:s,:_,:_,:_)
# Enter a description of the change.
      4 (  0.032%): (s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s)
      4 (  0.032%): (s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s)
      4 (  0.032%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      4 (  0.032%): (:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s,:s)
      4 (  0.032%): (s,_,:s)
      4 (  0.032%): (s,s,s,s,:s)
      4 (  0.032%): (:s,:s,:s,:s,:s,:s,:_,:_)
      3 (  0.024%): (:s,:s,:s,:s,:s,:s,:s,:s,:_,:_)
And 145 more...
```

Just to get a feel for what the superclass constructor call argument lists, this
shows all of them in a simplified structural form. Here, `s` means a matching
positional argument, `_` is a non-matching positional, `:s` is a matching named,
and `:_` is a non-matching name.

Over a third of the calls just have a single named parameter. That is almost
certain to be the `key` argument to Flutter's `Widget` class. There are a number
of particularly long argument lists where every parameter matches. Those are
cases where this feature would eliminate a *lot* of uninteresting code.

Now looking at the individual proposals. There are five options and here's how
many constructor calls would be able to use each for all potentially matched
arguments:

*  **Append super args (97.676% 9960/10197).** Here, the positional `super.`
   parameters are appended to the explicit arguments in the superclass
   constructor call.

*  **Prepend super args (97.990% 9992/10197).** Here, the positional `super.`
   parameters are prepended before the explicit arguments in the superclass
   constructor call.

*  **Insert super args (99.519% 10148/10197).** Here, we allow some new syntax
   like `...super` that users can place inside the superclass constructor call's
   argument list to indicate where the positional `super.` parameters should be
   inserted. This is the most complex proposal because it involves new syntax.
   It's also more verbose than the others because the user has to write the
   insertion point syntax.

My initial [strawman][] only allowed `super.` parameters when the *entire*
superclass constructor call could be inferred from it. In other words, the user
couldn't write the superclass constructor call at all. The language would use
the `super.` parameters to synthesize the whole superclass call. This raises a
question of *which* superclass constructor to call.

[strawman]: https://github.com/dart-lang/language/issues/1855#issuecomment-918420006

*  **Call unnamed (80.592% 8218/10197).** Here, the synthesized superclass
   constructor call always invokes the unnamed constructor.

*  **Call same name (82.181% 8380/10197).** Here, the synthesized call calls the
   superclass constructor with the same name as the subclass constructor being
   defined (which might be unnamed).

*Bob's opinion:* I think the data shows that being able to write an explicit
super call with some explicit arguments that gets merged with the `super.`
parameters is valuable. It allows roughly 20% more constructors to take
advantage of the feature and is strictly more expressive.

Once you have that, almost every superclass constructor call in the entire
corpus will benefit from this feature. In most cases, all or none of the
positional arguments match, so the specific merge strategy doesn't matter. Being
able to insert is obviously the most effective since it covers both of the other
two options. But the difference is only about 2%. That feels like a small enough
benefit to me that it doesn't outweigh the cost of asking users to write
`...super`.

Prepending is *slightly* more useful than appending. But it comes at the cost of
meaning that when you look at the explicit argument list, the arguments don't
appear at their actual positions in the superclass constructor. They get shifted
down by the prepending `super.` parameters. On the other hand, this does mean
that the arguments appear in textual order, since the `super.` parameters appear
first, over in the subclass's parameter list.

This makes me consider another potential strategy: disallow merging positional
arguments. We allow merging explicit and `super.` *named* arguments because
that's obvious. And we allow *all* positional arguments to use `super.` or
*none* of them. But we don't allow both explicit and `super.` positional
arguments.

*   **Do not merge super args (96.234% 9813/10197).** This avoids all of the
    confusion of the other merge strategies. A user never has to wonder whether
    the arguments are appended or prepended since combinations of explicit and
    `super.` positional arguments are simply disallowed. Despite being more
    restrictive, it still covers nearly as many cases. It's only about 1% less
    useful.

These numbers are all so close that I don't have a strong opinion one way or
the other. I'd lean slightly towards the "do not merge" option because it's the
most conservative. There is a potential failure mode to worry about. If all of
the positional parameters in the superclass constructor have the same time, then
any merge strategy will not produce a compile error. If the user guesses that
the language has one strategy but it actually has another, then instead of an
error, they will get a program that silently runs with the wrong argument
values. That seems pretty bad to me.

The "no merge" strategy avoids that error. In the rare case where the language
*would* have to merge, it simply becomes an error and the user must not use the
`super.` syntactic sugar and specifies the argument list clearly and explicitly.
This strategy also gives us room to be more flexible in a future release of the
language if a particular merge strategy becomes a clearer winner.

Another option would be to support an explicit insert syntax, but allow users
to elide in cases when all positional parameters use `super.`. That gives the
brevity of the other options in the majority of cases. In the rare case where
there is merging, there is then a piece of syntax to make it clear what order
it happens. This would cover almost every single use case and be explicit in
cases where doing so is beneficial. The only real downside is the complexity of
an insert syntax and users having to know that it can be elided in most cases.
