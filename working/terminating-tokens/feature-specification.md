# Terminating Tokens

Make Dart cleaner and less error-prone by eliminating pointless semicolon
syntax, while avoiding the insanity of JavaScript's semicolon insertion rules.

**Note: This proposal was a useful exercise to figure out the "least invasive"
way to make semicolons optional in Dart without breaking existing code. The
result works, but is quite subtle and complex. Based on that, we're unlikely
to move forward with this proposal, though we may investigate other approaches
to optional semicolons.**

## Motivation

For such a tiny feature&mdash;literally just eliminating some `;` at the ends of
some lines&mdash;people have *really* strong feelings about using newlines as
statement separators. Because of that, 2/3 of this proposal is about persuading
you that we *should* and *can* do it. If you already think optional semicolons
is a good idea, feel free to skip the next two sections and go straight to the
proposal. Otherwise, I'll do my best to convince you first.

### User desire

The simplest motivation is that many users already want it. It was one of the
[very first feature requests for Dart][sdk#34], and has 20 👍 and 3 ❤️. (That's
not a lot, but keep in mind this bug was closed years ago.) The [more recent
issue][sdk#30347] has 40 👍, 18 🎉, and 11 ❤️, compared to 7 😕 and 2 👎.

[sdk#34]: https://github.com/dart-lang/sdk/issues/34
[sdk#30347]: https://github.com/dart-lang/sdk/issues/30347

BASIC, F#, Go, Groovy, Haskell, JavaScript, Julia, Lua, Python, R, Ruby, Scala,
and the various shell languages all omit semicolons. Dart's main competitors are
TypeScript, Swift, and Kotlin. They all do too.

The odds that all of the Dart users who starred those bugs, the designers of
those other languages, and their users are all delusional is pretty slim. This
may not be enough to convince you that significant newlines are *better*, since
there are also plenty of successful languages that *don't* have them, but it
should send a clear signal that they are a reasonable idea.

### User errors

One aspect of good syntax design is that it minimizes user error. Humans are
fallible no matter what, but a good syntax has fewer bumps in the carpet to trip
over. Those of us well-versed in semicolons are so used to writing them that we
probably forgot how *un*-natural they were at first. That bump is still there,
we've just learned to sidestep it. New Dart users, though, still have to learn
that. Eliminating them can make that process easier.

**TODO: Are there any studies on this we can reference?**

Even experienced manual semicolon inserters still make mistakes. After years of
programming in Dart, I still forget the mandatory semicolon when assigning a
lambda to a variable:

```dart
someCallback = () {
  ...
} // <-- Error!
```

Flutter code, with its deep nesting of expressions and lambdas exacerbates this. Look at the series of closing delimiters at the end of:

```dart
Widget build(BuildContext context) {
  return CupertinoTabScaffold(
    tabBuilder: (context, int index) {
      return CupertinoTabView(
        builder: (context) {
          return CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(
              middle: Text('Page 1 of tab $index'),
            ),
            child: Center(
              child: CupertinoButton(
                child: const Text('Next page'),
                onPressed: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute<Null>(
                      builder: (context) {
                        return CupertinoPageScaffold(
                          navigationBar: CupertinoNavigationBar(
                            middle: Text('Page 2 of tab $index'),
                          ),
                          child: Center(
                            child: CupertinoButton(
                              child: const Text('Back'),
                              onPressed: () { Navigator.of(context).pop(); },
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    },
  );
}
```

The commas are optional, but each of those five semicolons is required. Omit
one, and it's an error. Place one on any of the other lines where they aren't
required, and it's an error.

The fact that it's an *error* to omit them shows how needless they are in many
places. The language *already knows* the statement has ended, which is why it's
able to tell you you forget the semicolon at exactly that point. The semicolons
tell it nothing it doesn't already know.

### Language commitment

Fair warning, this gets kind of squishy.

Choosing a language is a big commitment. When a user chooses to write a large
program in Dart, they are stuck with it for a long period of time. To make that
kind of commitment, they want assurance not just that Dart is good today but
that its stewards are taking it in the direction they want. They are looking for
signals about what kind of principles or philosophy the shepherds of the
language have so they can predict if the language will continue to be a good fit
for them.

This does actually matter, because if future versions of a language invest in
features you don't want, you have to deal with the migration and the opportunity
cost of features you *could* have had.

Some camps have formed around how explicitly the user must express their intent
to the computer versus the computer filling in the blanks on their behalf. On
one side are the dynamically-typed scripting languages where the implementation
does its best to take the user's code and go off and run it. If the user wrote
something wrong, it's not discovered until the last possible minute when an
operation can't be performed.

On the other end are very explicitly-typed languages like Java, Ada, and C++.
Those require you to laboriously prove to the compiler that you know what your
code is doing. In this:

```c
int i = 3;
```

You are telling the compiler that `i` is `3`, and you're also telling it that
`i` is an integer. The compiler already knows that, but it needs to know that
*you* know it too. Either it doesn't trust you, or you don't trust it to figure
that out.

Newer languages stake out a middle position: the user states their intent once,
briefly. The machine figures out what they mean. If unclear, it requires
clarification instead of just trying to muddle through.

Type inference is the canonical example. If it can figure out the static type of
the code for you, it does. Once it has, it reflects that *back* to you in terms
of static errors so that you can *see* what it figured out before you run it.

Dart, especially after Dart 2, is in that camp. I can't say it better than [Seth
Ladd][seth]:

[seth]: https://github.com/dart-lang/sdk/issues/30347#issuecomment-321058277

> Modern languages are generally believed to be less boilerplate, more terse,
> and include language features working for you. For example, type inferencing
> is the language working for you. We could force you to write type annotations
> everywhere, or we can say "in many cases, we can infer it for you".
> Auto-inserting punctuation is another way the language can work for you. Also,
> there's an element of being seen as a light-weight, modern language and
> staying competitive. The trend in languages was to go to `var`, to go for
> closures, to go for `=>` functions, and now to go for implicit semicolons
> (done right, of course).

When users ask us to support optional semicolons, part of that is a question:
"Is that the kind of language you are?" I believe Dart already *is* that kind of
language. With type inference, optional `new` and `const`, unprefixed imports,
implicit `this`, tear-offs, and other features, the language is clearly
well-established in the camp of languages that don't require unnecessary
verbiage.

From that angle, supporting optional semicolons is an *accurate* and *useful*
signal for us to send.

### What "optional" means

One last point. I know some are less concerned about making newlines significant
than they are with doing that *and* still allowing semicolons. For very good
reasons, they don't want a bifurcation in the ecosystem where half the Dart
world says "You need to write semicolons!" and the other half says "No
semicolons ever!"

This is a valid concern. This proposal *does* allow both explicit and inferred
semicolons. The intent is *not* to allow users to choose their preferred style.
If this proposal ships, the [official style guide][] will tell you to omit
semicolons. [Dartfmt][], the canonical automatted formatter for Dart code will
remove them.

[official style guide]: https://www.dartlang.org/guides/language/effective-dart
[dartfmt]: https://github.com/dart-lang/dart_style

We still allow semicolons for three reasons:

*   **To avoid massively breaking existing Dart code which has them.** Making
    semicolons an error would break every single Dart program in the world when
    users upgraded to the latest SDK. That's bad.

    It would make it harder to write migration tools that remove those
    semicolons, since those tools would then need to be able to parse some
    pseudo-Dart language that is the superposition of Dart-with-semicolons and
    Dart-without-semicolons. In other words, we need to implement a parser that
    supports both semicolons and significant newlines no matter what.

*   **As an input format for dartfmt and other IDEs.** Many users have strong
    muscle memory for writing those `;`. If you have your editor set to
    auto-format on save, you can keep doing that and it will strip them back out
    for you. Eventually, that muscle memory will fade. But in the meantime, it
    avoids forcing you to manually delete them every time you accidentally hit
    the `;` key.

*   **As an output format for code generators.** The Dart ecosystem uses code
    generation pretty heavily. It's often easier for tools that output Dart
    source code to be able to do so using semicolons without worrying about
    whitespace or formatting. Those tools can then either run the output through
    dartfmt to remove the semicolons or just leave them since they're harmless.

OK, that's what I have to try to persuade you that optional semicolon are an
idea worth *wanting*. The next question is whether it's an *attainable* goal.
JavaScript is a good example of the fact that optional semicolons can be done,
but done so poorly as to be an anti-feature.

Also, each language has its own pecularities, so a good optional semicolon
system in one language may not work in another. In other words, we need to not
just specify the optional semicolon rules, but *evaluate* them in the context
Dart's own grammar and ecosystem.

## Evaluation

Given some set of rules for eliminating semicolons, how can we tell if they are
*good* rules? I measure it along a couple of axes. We want to maximize:

*   **Unambiguity** - Removing mandatory semicolons as terminators can lead to
    ambiguous cases where both ignoring a newline or treating it as a semicolon
    lead to valid parses. Any syntax *must* be unambiguous&mdash;users don't
    like it if their code is parsed differently on different days of the week.
    When given an ambiguous choice, it must resolve it in a way that aligns with
    the user's intention as often as possible.

*   **Compatibility** - How much existing code (with explicit semicolons and
    whatever whitespace and newlines it happens to have) parses the same way
    with the new newline-sensitive grammar as it did with the old grammar? Any
    difference here is existing code that is broken by the new rules.

*   **Accuracy** - When users write code without semicolons and with newlines
    wherever they feel they look best, how often does the parser see the code
    they way the user wants it to? How often do users have to fight the grammar
    and tweak newlines to satisfy the parser?

*   **Robustness** - Given a chunk of code where the newlines are *not*
    deliberate, how likely is it to be parsed the way the user wants? If someone
    is just banging code into their editor and not thinking about
    formatting&mdash;that's dartfmt's job after all&mdash;how likely are they to
    get what they want out? If they copy and paste a big chunk of code somewhere else, how often does it end up still correct?

In an ideal world, we'd hit 100% on all four of those. Short of radically
changing the language into something like Lisp, that's impossible. But we can
run experiments on a corpus of Dart code to try to empirically measure these to
some degree.

The corpus I used is the Flutter repository, the Dart SDK repository, and the
1,000 most-recently published packages to pub.dartlang.org. It contains
**4,963,739 lines of Dart code** across **19,856 files**. I ignore results from
a few language/compiler test files that deliberately test syntax errors or
contain comments in odd locations required by the test framework.

There are **1,677,054** semicolons that would be removed by this proposal.

In order to test the proposal, I hacked together a prototype implementation of
its parsing rules in [a fork of the front_end][front_end] package's Fasta
parser. I'm not very familiar with Fasta and I ran into a few places where it
was hard to correctly *ignore* newlines, so there are a few false positive diffs
that I'll call out below.

[front_end]: https://github.com/munificent/ui-as-code/tree/master/code/front_end_semicolon

### Ambiguity

In most places in the grammar, we know a newline is *not* significant because a
semicolon can't appear there. For example, we can always safely the ignore
newline after `class`:

```dart
class
  Foo {}
```

In other places, we know the newline *must* be significant because ignoring it
leads to an error, as in:

```dart
main(List<String> arguments) {
  print("Hello");
  if (arguments.isNotEmpty) print("Passed $arguments");
}
```

Here, we know the newline before `if` *must* be significant because ignoring it
leads to an error on the `if`.

Now, consider:

```dart
main() {
  foo
  (bar)
}
```

This could either be parsed as an expression statement `foo;` followed by an
expression statement `(bar);`. Or it could be parsed as an invocation of
`foo(bar);`. We have a choice as to whether to treat the newline after `foo` as
significant or not. Either option leads to a valid program, but only one is what
the user intends.

Any optional semicolon system has to resolve these ambiguities and do it in a
way that agrees with the user's intention. This is why optional semicolons can
be difficult. Most of these ambiguities center around *expression statements*.
That's the corner of the language where the rich expression grammar comes into
play, and where a semicolon is often necessary to separate two expression
statements.

The rules for resolving ambiguities need to be simple enough for users to
internalize, while also being what the user wants. It turns out there is a
simple rule that does what users want most of the time. I call it the "eagerness
principle". It says, **if there is a valid way to treat a newline as
significant, it *should* be significant.**

The intuition is that if the user chose to put a newline there, the language
should respect that choice and consider it a signal of intent unless it clearly
can't be. Eagerness implies that the newline before `(` in the example is
significant, so the language parses it like:

```dart
main() {
  foo;
  (bar);
}
```

(Note that this is the exact opposite of JavaScript. JS says that newlines do
*not* signal user intent at all... unless that leads to ambiguity in which case
it circles back and reluctantly takes them into account.)

#### Hanging returns

This:

```dart
return
123
```

could be parsed as:

```dart
return 123;
```

or:

```dart
return;
123;
```

The latter is obviously not useful since it causes unreachable code, but it's
structurally similar to this useful code:

```dart
if (condition) return
print("didn't return")
```

It would be bad to ignore the newline after `return` in this last example. So,
based on that, and following the eagerness principle, we treat the newline as a
semicolon after `return` in all cases. This is how Go and Kotlin behave. Swift
ignores the newline, but also requires braces around all control flow
statements.

This is technically a breaking change to existing return statements that have a
newline before their value. How breaking of a change is it? The corpus contains:

*   **158,407** return statements.
*   **151,363** (95.553%) have a value that starts on the same line as the
    `return`.
*   **6,949** (4.387%) do not return a value.
*   **95** (0.060%) have a value that starts on the next line.
*   **81** (0.051%) of those come from a single, um, *idiosyncratically*
    formatted package.
*   **14** (0.008%) come from other files.

This isn't entirely surprising since dartfmt will never place the return value
on the next line and most users use the formatter.

In cases where a newline is treated as significant and the user doesn't intend
that, the resulting code almost always ends up with some static warning or
error. You'll usually end up with unreachable code. If not that, you'll
typically get a "missing return value" error because the function's return type
is not void, but the value is treated as not part of the return.

#### Empty statements in control flow

Consider:

```dart
for (var i = 0; i < 10; i++)
print("hi")
```

Does this print "hi" once or ten times? Does your answer change if that
`print()` were to be indented? Dart supports the empty statement, a semicolon
all by itself, so the latter is possible if it parses the above as:

```dart
for (var i = 0; i < 10; i++);
print("hi");
```

We don't want to make *indentation* significant when it comes to semicolons.
That tends to make the grammar very sensitive to whitespace mistakes and brittle
in unpleasant ways when users do things like copy and paste code.

In the corpus, there are:

*   **216,865** control flow statements (await-for, do, else, for, for-in, if,
    and while).

*   **210,746** (97.178%) have a body that isn't an empty statement and starts
    on the same line as the control flow header, as in:

    ```dart
    if (condition) { // <-- block starts on same line
      body();
    }
    ```

*   **6,102** (2.814%) have a non-empty body starting on the next line as in:

    ```dart
    if (condition)
      body();
    ```

    It's worth noting this [violates the official style guide][style guide].
    Even so, the formatter will produce this formatting if the user didn't write
    braces and the body doesn't fit on one line. More than half of these are in
    the Flutter repository, which doesn't use dartfmt or fully follow the style
    guide.

*   **17** (0.008%) have bodies that are empty statements.

[style guide]: https://www.dartlang.org/guides/language/effective-dart/style#do-use-curly-braces-for-all-flow-control-structures

It's *very* rare that a user deliberately wants an empty statement (`;`) as the
body of a control flow statement. So, given some piece of Dart code with the
semicolons removed like:

```dart
for (var i = 0; i < 10; i++)
  print("hi")
```

It is almost certain that the original code did intend the second statement to
be the body of the previous control flow statement. We make the language choose
that interpretation even without semicolons by simply disallowing empty
statements as control flow bodies. That means the code *cannot* be parsed as:

```dart
for (var i = 0; i < 10; i++); // <-- Not allowed.
print("hi");
```

Then it must be:

```dart
for (var i = 0; i < 10; i++) print("hi");
```

Which is what the user almost always wants. In the rare cases where user does
want an empty body (typically a loop where the condition expression has a side
effect), they can use an empty block (`{}`), which is usually more readable
anyway.

That means the 6,102 existing cases of newlines before control flow bodies are
not broken, at the expense of having to fix the 17 uses of empty statements.

**TODO: The prototype doesn't currently implement this restriction, but there
are only a handful of cases where it occurs.**

#### Prefix and infix operators

Dart has a couple of operators that can appear both at the beginning and middle
of an expression. That leads to ambiguity if a newline appears before that
operator, as in:

```dart
a
-b
```

That could be parsed as either:

```dart
a;
-b;
```

or:

```dart
a - b;
```



In all cases, we follow the eagerness principle and treat a newline as
significant before these operators. That means one of these operators at the
beginning of a line is treated like a unary operator if possible.

Note that these are *only* a problem at the "top level" of a statement
expression. Once the operator is nested inside parentheses or an argument list
or something, a semicolon is never allowed and we know we can ignore the
newline.

The set of operators affected are:

*   `-`, which can be used for both unary negation and infix subtraction:

    ```dart
    -negate
    sub - tract
    ```

    There are **10,551** infix `-` operators in the corpus and **13** (0.123%)
    are at the beginning of a line. Those thirteen are all in an expression
    context where we know the newline cannot be significant, so are OK too.

*   `<`, which can be used for generic collection literals and comparison:

    ```dart
    <int>[]
    less < than
    ```

    There are **26,049** infix `<` operators and none at the beginning of a
    line.

*   `(`, which can be a parenthesized expression or a function invocation:

    ```dart
    (parenthesized)
    function(call)
    ```

    There are **1,437,185** invocations in the corpus, none of which have the
    `(` on the next line.

*   `[`, which can be a list literal or an index operator:

    ```dart
    [list, literal]
    list[access]
    ```

    There are **173,429** index operator calls in the corpus, **2** (0.001%) of
    which have the `[` on the next line. Both are the result of chained index
    operators like:

    ```dart
    exifData[tag] = ExifConstants.stringValues["Components"]
            [exifData[tag][0]]
    ```

    One is in an expression context where the newline is ignored and one is not.

#### Adjacent strings

Adjacent strings are an odd corner of the language. They were added during a
period of time when Dart disallowed `+` on strings. Now that it supports that,
there is little reason to also support adjacent strings, but the language still
does and using it is idiomatic.

This leads to obvious ambiguity. This:

```dart
"one"
"two"
```

Could be:

```dart
"one";
"two";
```

or:

```dart
"one" "two";
```

This is the one case where eagerness is obviously wrong. The former
interpretation can't accomplish anything useful. And, in fact, newlines are the
primary use case for splitting a string literal into multiple adjacent strings:

*   The corpus has **11,256** adjacent strings. By that, I mean strings that
    immediately follow another string literal, so `"a" "b" "c"` is two adjacent
    strings.

*   **11,222** (99.698%) have a newline between them and the previous string.

So, in this case, we don't follow eagerness and ignore a newline between
adjacent strings.

#### Local variable types

Inside a block, this:

```dart
a
b
```

Could be two expression statements that call the getters `a` and `b`,
respectively. Or it could declare a local variable `b` of type `a`.

Likewise:

```dart
a.b
c
```

Could be either:

```dart
a.b; // Call "b" getter on "a".
c;   // Call "c" getter.
```

or:

```dart
a.b c; // Declare "c" of type "b" from prefixed library "a".
```

Code like this is rare either way. In the corpus:

*   There are **754,851** expression statements.
*   **189** (0.025%) are single identifiers like `a`.
*   **92** (0.012%) are prefixed/getters like `a.b`.
*   There are **307,908** local variable declarations.
*   **10** (0.003%) have newlines after the type. A few are in generated code.
    A couple look like:

    ```dart
    Response
    response = await dio.get("/fakepath1");
    ```

    (It's not clear why the author put a newline there since the whole
    declaration easily fits on one line.)

Since this is so rare, it doesn't matter much which way we pick. The eagerness
principle prefers treating it as two expression statements, so we stick with
that. The user can always get a local variable declaration by *removing* the
newline. If we picked the other option, they would have to add an explicit
semicolon if they *did* want two identifier expression statements.

Note that this is only an ambiguity for *local* variables. For fields and
top-level variables, there are no expression statements, so no ambiguity. That's
good because newlines between types and variables are more common there:

*   There are **152,370** field declarations.
*   **194** (0.127%) have a newline before the variable name.
*   There are **25,769** top level variable declarations.
*   **397** (1.541%) have a newline before the variable name.

A related ambiguity occurs when declaring local variables using `final` or
`const` since the type is optional when those are used:

```dart
final c
d = 1
```

This could be parsed as:

```dart
final c;
d = 1;
```

or:

```dart
final c d = 1;
```

As above, eagerness says we prefer the first option. There are no cases of this
in the corpus.

#### Local function return types

Inside a block:

```dart
main() {
  foo
  bar() {}
}
```

Could be either:

```dart
main() {
  foo;
  bar() {}
}
```

or:

```dart
main() {
  foo bar() {}
}
```

This ambiguity only exists for return types that are also syntactically valid
expressions. A bare identifier like the example here is one, but most return
types long enough to be split tend to be function types which can't be parsed as
an expression, as in:

```dart
Function(int i)
returnsFunction() {}
```

Here, because of the parameter name and type, the `Function(int i`) part can't
be parsed as an expression statement.

But, in cases where it is ambiguous, eagerness says we pick the former. The
corpus contains **12,785** local functions:

*   **9,600** (75.088%) don't have a return type at all.
*   **3,184** (24.904%) have a return type on the same line as the function
    name.
*   Exactly **1** (0.008%) puts return type on a separate line from the name:

    ```dart
    /// Returns a service method handler that verifies that awaiting the request
    /// stream throws a specific error.
    Stream<int> Function(ServiceCall call, Stream<int> request)
        expectErrorStreaming(expectedError) {
      ...
    }
    ```

    In this case, the line containing the return type can't be parsed as an
    expression statement, so this still avoids the ambiguity.

#### Local function block bodies

Inside a block, this:

```dart
function(a, b)
{
  body
}
```

Could be either:

```dart
function(a, b);
{
  body;
}
```

or:

```dart
function(a, b) {
  body;
}
```

This is only an issue for *local* functions since bare block statements aren't
allowed at the declaration level. It's also only an issue with local functions
that don't have types for any of their parameters, so that the parameter list
could also be parsed as an argument list.

There are **12,785** local functions with block bodies in the corpus and none of
them put the `{` on the next line. (K&R style is completely victorious over
Allman style in Dart, apparently.) We thus go with eagerness and prefer the
first interpretation.

#### Variable followed by getter

Here's an odd one:

```dart
class Foo {
  final a
  b
  get c {}
}
```

Could be:

```dart
class Foo {
  final a;
  b get c {}
}
```

or:

```dart
class Foo {
  final a b;
  get c {}
}
```

I haven't encountered any examples of this. As eagerness says, we pick the first
interpretation.

#### Hanging break and continue labels

The rarer cousins to hanging returns. The `break` and `continue` statements
allow jumping to a named label, so this:

```dart
break
foo

continue
foo
```

Could be either:

```dart
break;
foo;

continue;
foo;
```

or:

```dart
break foo;

continue foo;
```

In the corpuse, there are **5,992** break statements:

*   **5,948** (99.266%) don't have a label.

*   **44** (0.734%) have a label on the same line. None of them put the label
    on the next line.

There are *1,605* continue statements.

*   **1,535** (95.639%) don't have a label.

*   **70** (4.361%) have a label on the same line. None of them put the label
    on the next line.

Since the label can only be a single bare identifier, it's unlikely a user will
feel a need to move it to its own line. So we stick with eagerness and treat the
newlines as significant.

**TODO: Are there other ambiguities caused by contextual keywords possibly
being used as identifiers?**

### Compatibility

The transition to Dart 2's new type system has exhausted our users' stamina for
breaking changes, so any optional semicolon feature needs to parse almost all
existing Dart code the same way it's parsed today.

We can measure that like so:

1.  Using the current Dart grammar, parse it and then output the resulting
    syntax tree to some canonical form. We just want a well-defined
    serialization of how the parser views the code. Dartfmt turns out to be a
    handy tool for this. (The fact that it formats the AST is incidental for our
    purposes and doesn't affect the experiment.)

1.  Using the new optional semicolon rules, parse the *same* corpus and output
    it.

1.  Diff the results.

Any difference shows a place where existing code is broken (i.e. interpreted
differently) by the new parsing rules. The fewer of those, the greater the
compatibility. Note that even zero differences doesn't ensure perfect
compatibility since we're limited by the actual code patterns captured by the
corpus.

The numbers in this section and the next are a little different from the counts
in the ambiguities section. That's because I used custom scripts to count
individual occurrences of specific code constructs in the previous section.
The results here and below count *files* that contain differences.

The results are:

*    **77** (0.388%) files in the corpus have differences. Most only have a
     single difference or have a parse error from the incomplete prototype (see
     below).

*    **48** (0.242%) are differences from hanging returns which get a semicolon
     after the `;` in the new parser. **34** (0.171%) are in a single package
     which has some strange, inconsistent formatting. **14** (0.071%) are in
     other code.

*    **25** (0.126%) are false positives because the prototype doesn't fully
     implement ignoring the newline after a type in a top-level variable or
     field declaration. These would go away in a complete implementation. **11**
     (0.055%) of them are in generated code in the googleapis package.

*    **4** (0.020%) are differences where a newline after a local variable type
     is treated as significant in the new parser. **2** (0.010%) of those are
     in the generated googleapis package.

*    There are **16** (0.081%) significant differences, ignoring false positives
     and googleapis and one other odd packages.

In other words, about **one in every 1,241 files** (0.081%) would be impacted by
this change.

\* "Representative" is hard. Using only code that's been committed biases
towards code that's "good enough" in some way and doesn't give us much insight
to the kind of half-baked, in-progress, broken code users often have in their
editor in the middle of programming.

### Accuracy

Compatibility ensures that old code with semicolons isn't *re*-interpreted in a
bad way. Once they've moved into the brave new world of significant newlines,
does the language see their code the way they do?

In a perfect world, they can write newlines in a style that matches the style
guide and feels natural. The parser will then insert semicolons exactly where
they imagine they should be. If we assume that the existing corpus does have
newlines where people like, we can measure accuracy like so:

1.  Run a [simple script][strip] to mechanically remove the semicolons from the
    corpus without otherwise disturbing its formatting.

    [strip]: https://github.com/munificent/ui-as-code/tree/master/scripts/bin/strip_semicolons.dart

1.  Using the current Dart grammar, parse the original unstripped corpus and
    output the resulting syntax tree to some canonical form.

1.  Using the new optional semicolon rules, parse the *stripped* corpus and
    output it.

1.  Diff the results.

The fewer differences, the greater the existing newline styles match the
significant newline rules and result in code that is parsed the same way
existing code with semicolons is parsed. Differences here are places where we
need to either change the grammar rules or where users need to tweak their
style.

*   **372** (1.873%) files have differences.

*   **254** (68.280%) of those are spurious diffs caused by whitespace changes
    or syntax errors in the original code. This is mostly things like a
    semicolon getting moved before or after a comment. The actual behavior of
    the code is unchanged.

*   **53** (14.247%) are false positives because my prototype parser isn't fully
    complete or robust. **25** of the false positives are because the prototype
    doesn't correctly ignore newlines in field and top-level variable
    declarations. **15** of the false positives are because the prototype parser
    doesn't correctly handle treating `factory`, `async`, `get`, and `set` as
    identifiers in some contexts because it's looking for a `;` to make the
    distinction. **6** are spurious diffs from a semicolon getting inserted
    before or after a comment. The remaining few are things like test files that
    have deliberate syntax errors which get parsed differently, etc.

    In all of these cases, the underlying grammar isn't ambiguous. I just didn't
    implement full correct support because it was too much effort for the
    prototype.

*   **65** (0.327%) are real failures. Places where the same code with
    semicolons gets parsed differently when the semicolons are removed and
    newlines are significant.

*   **48** (0.242%) of those failures are newlines after return statements that
    have values. 34 (70.833%) of those are in that one odd package. The
    remaining are scattered across Flutter (4) and a handful of packages.

*   **12** (0.060%) are empty statements in control flow statements. Half of
    those are in observatory. (You get an interesting window into programmers'
    idiosyncratic coding styles by doing these investigations.)

*   **5** (0.025%) are newlines after a local variable's type, which causes it
    to be split into two expression statements.

In other words, about **one in every 305 files** (0.282%) would need a small
tweak after removing the semicolons to get it back to what the user intends.
Usually dartfmt is sufficient to fix them.

### Robustness

Robustness is harder to measure empirically because I don't have easy access to
a corpus of "live" uncommitted code while users are in the middle of typing it.
I have fairly high confidence in this. As you'll see in the proposal below,
relatively few places in the grammar care about newlines at all. In most places,
they can be present or not, and the parser will ignore them because they aren't
needed to avoid ambiguity.

**TODO: See if there are any experiments we can perform.**

## Proposal

You finally made it to the actual proposal. The pot of gold at the end of the
very long rainbow of motivation and justification.

This proposal is a syntax-only change. Once a program has been correctly parsed,
it is semantically identical to an existing Dart program with semicolons
inserted at the relevant locations.

### Context

Unlike Go (but like most other languages) the optional semicolon rules are not
perfectly [regular][]. They aren't handled entirely by the lexer and rely on
where a newline appears in the syntactic grammar to determine if it should be
meaningful. For example:

[regular]: https://en.wikipedia.org/wiki/Regular_language

```dart
main() {
  a
  -b
  function(c
  -d)
}
```

The newline before the first `-` is significant because this is valid (though
likely not very useful):

```dart
main() {
  a;
  -b;
}
```

But the newline before the second `-` is ignored because this is not:

```dart
main() {
  function(c; // <- Error.
  -d);
}
```

To track this, certain rules in the grammar establish a **context**, which can
be either "declaration", "statement", or "expression". The context begins with a
terminal, surrounds some rules, and then ends with another terminal. The context
applies to all of the rules in the middle, transitively.

*   "Declaration" is the context of top level code and class bodies. It's very
    similar to "statement" except that we can ignore newlines before a couple
    more tokens there because there's no concept of an expression statement at
    the top level.

*   "Statement" is the context where statements can appear, in particular
    expression statements. This is the place where most semicolons appear and
    where newlines are the most involved.

*   "Expression" is nested inside an expression that must have some explicit
    closing delimiter. Until that delimiter is reached, we know we haven't
    reached the end of the expression, so all newlines can be ignored.

The rules are:

*   The initial context is declaration.

*   The `{` and `}` in `block` establish a statement context.

*   The `{` and `}` in `mapLiteral` establish an expression context. (The
    difference between this and the previous rule is the one reason why the
    rules can't be defined lexically.)

*   The `(` and `)` in `arguments`, `assertStatement`
    `forLoopParts`, `formalParameterList`, `primary`, `ifStatement`,
    `whileStatement`, `doStatement`, and `switchStatement` establish an
    expression context.

*   The `[` and `]` inside `listLiteral`, `cascadeSelector`, and
    `unconditionalAssignableSelector` establish an expression context.

*   The `case` and `:` in `switchCase` establish an expression context.

**TODO: Should the first two clauses of `?:` establish expression contexts? I
haven't found it was needed in the corpus I tested, but it's something we could
consider.**

When multiple rules surrounding a token establish contexts, the innermost wins.
So, in:

```dart
main() {
  [1, () {
    a
    -b
  }]
}
```

The stack of contexts surrounding `-` is:

*   "declaration" (the default)
*   "statement" (main's block body)
*   "expression" (the list literal)
*   "statement" (the lambda body)

The innermost is "statement", so the newline before `-` is significant.

### Terminating tokens

Some languages work by having a set of rules for inserting synthetic semicolon
tokens when a newline appears in a significant position. The problem with that
is you have to take extra care to *not* insert them in the many places where a
semicolon can never appear and where a newline should be ignored.

This proposal takes a slightly different approach. Instead, we say that any
token may or may not be "terminating". A terminating token is the token *after*
a newline in a context where that newline could be significant. For example:

```dart
main() {
  foo()
  bar()
}
```

Here, `bar` is a terminating token and behaves as if a semicolon appeared before
it, after the `)` on `foo()`. The "should be ignored" is vague. More
precisely:

*   If a newline character appears after the preceding token's lexeme and
    before this token's lexeme, it **is** terminating. This is the key rule
    that makes a newline significant.

*   Else, if the token is `}`, it **is** terminating. This lets us robustly
    handle `}` on the same line as the final statement in a block:

    ```dart
    function() { print("hi") }
    ```

*   Otherwise, it is not.

### Terminator rules

To use terminating tokens we introduce a couple of special grammar terminals:

*   The `TERM` rule matches and consumes an explicit semicolon. It also matches
    the end of a source file. If not currently in an expression context, it
    matches but does not consume a terminating token. Think of it like a
    zero-width lookahead in a regular expression.

*   The `NO_TERM` rule matches if the current token is non-terminating or if we
    are in an expression context. Like `TERM`, when it matches, it doesn't
    consume the token. This is used to prohibit a newline from being ignored in
    places that would break the eagerness principle, like:

    ```dart
    foo() {
      bar
      (arg)
    }
    ```

    A `NO_TERM` rule between the function name and argument list rules ensures
    that the newline before `(` cannot be ignored and lead this to be parsed
    as `bar(arg)`.

*   The `NO_STMT_TERM` rule is like `NO_TERM` except it permits terminating
    tokens in a declaration context. It only prohibits terminating tokens in a
    statement context.

    (We could eliminate this rule by duplicating every grammar rule used in both
    statement and declaration contexts and then inserting `NO_TERM` only in the
    former, but this seemed simpler.)

Next, we weave these new rules into the grammar:

*   Replace all occurrences of `;` in the grammar with `TERM` in these rules:

    *   `libraryName`
    *   `importSpecification`
    *   `libraryExport`
    *   `partDirective`
    *   `partHeader`
    *   `typeAlias`
    *   `functionTypeAlias`
    *   `localVariableDeclaration`
    *   `functionBody`
    *   `classMemberDefinition`
    *   `mixinApplicationClass`
    *   `yieldStatement`
    *   `yieldEachStatement`
    *   `expressionStatement`
    *   `doStatement`
    *   `rethrowStatement`
    *   `assertStatement`
    *   `topLevelDefinition`

    This is the main change that makes semicolons actually optional.

    We leave `;` alone in `forLoopParts`. The semicolons are still required in a
    C-style for loop.

*   Change `returnStatement` to:

    ```
    returnStatement:
      'return' TERM |
      'return' NO_TERM expression TERM
      ;
    ```

    This makes the `;` optional and addresses ambiguity with hanging returns.

*   Disallow empty statements in control flow statements. Change
    `expressionStatement` to:

    ```
    expressionStatement:
      expression TERM
    ```

    Change `statement` to:

    ```
    statement:
      label* nonLabelledStatement |
      ';'
      ;
    ```

    (This also eliminates support for labeled empty statements. That isn't
    needed by this proposal, but it seems like a good time to disallow that
    pointless construction.)

    Add:

    ```
    nonEmptyStatement:
      label* nonLabelledStatement
      ;
    ```

    In `forStatement`, `whileStatement`, `doStatement`, and `ifStatement`,
    replace `statement` with `nonEmptyStatement`.

*   Insert `NO_TERM` into:

    ```
    relationalOperator
      : '>' '='
      | '>'
      | '<='
      | NO_TERM '<'
      ;

    additiveOperator
      : '+'
      | NO_TERM '-'
      ;

    arguments
      : NO_TERM '(' (argumentList ','?)? ')'
      ;

    unconditionalAssignableSelector:
      NO_TERM '[' expression ']' |
      '.' identifier
      ;
    ```

    These ensure that a line starting with an operator that can be used in
    prefix or infix position is always treated like the former.

    Note that placing `NO_TERM` in `arguments` means the newline is significant
    in:

    ```dart
    new Foo
      (arg)
    ```

    This becomes a syntax error, even though ignoring the newline does not lead
    to ambiguity. We do this so that removing `new` and `const` doesn't cause
    the resulting code to be parsed differently. I've never seen a newline
    appear here in real code.

*   No changes are needed for adjacent strings. Since we *do* allow and ignore
    newlines between a series of strings, the existing grammar rule for
    `stringLiteral` is fine.

*   Change `declaredIdentifier` to:

    ```
    declaredIdentifier:
      metadata ( 'final' | 'const' )? type NO_STMT_TERM identifier
      metadata ( 'final' | 'const' | 'var' ) identifier
      ;
    ```

    This addresses ambiguity around local variable declarations.

*   Change `functionSignature` to:

    ```
    functionSignature:
      metadata ( returnType NO_STMT_TERM )? identifier formalParameterList
      ;
    ```

    This addresses ambiguity around return types on local functions.

*   Insert `NO_STMT_TERM` into:

    ```
    functionBody:
      async? '=>' expression ';' |
      (async | async* | sync*)? NO_STMT_TERM block
      ;
    ```

    This addresses ambiguity around local functions with block bodies where the
    `{` is on the next line.

*   Change `getterSignature` to:

    ```
    getterSignature:
      get identifier |
      returnType NO_TERM get identifier
      ;
    ```

    That avoids the obscure ambiguity in:

    ```dart
    class Foo {
      final a
      b
      get c {}
    }
    ```

*   Insert `NO_TERM` in:

    ```
    breakStatement:
      'break' NO_TERM identifier? TERM

    continueStatement:
      'continue' NO_TERM identifier? TERM
    ```

    This makes the `;` optional and addresses ambiguity with hanging break
    and continue labels.

## Migration

A key goal for me doing these experiments and writing this proposal was to
measure how *easily* we could go from Dart code today to Dart without
semicolons.

### Incremental rollout

As the evaluation and the prototype shows, it's feasible to implement a parser
that both:

*   Parses almost all existing Dart code the same way it is currently parsed.

*   Parses almost all Dart code without semicolons the way the corresponding
    explicit semicolon code is parsed.

The number of changes is quite small, which implies the migration cost is small.
However, it's not *zero* and there are a small number of technically breaking
changes, even though they rarely occur in real code.

To ease that, I propose that we roll this out in a couple of phases:

1.  Tell users optional semicolons are coming, loudly and clearly. This should
    be a delightful message for most users.

1.  In a minor release of the SDK, add static warnings to the
    previously-described ambiguous places where a newline would cause the code
    to be parsed differently with optional semicolons.

1.  Fix any of these warnings that happen to exist inside Google, and in our own
    tools and packages.

1.  In the next minor release of the SDK, enable the optional semicolon rules
    in the parsers.

### Tooling

The goal of optional semicolons is move the entire ecosystem to a consistent
world where semicolons aren't in Dart code. We obviously don't expect users to
do that manually.

The natural place to tool this is dartfmt. It already supports `--fix`, which
can apply other "modernizing" changes to your code. We'll add another fix that
removes semicolons. This is the perfect place to implement this because the
formatter can also ensure that the resulting code has the correct newlines to
preserve the original code's meaning.

### Fix dartfmt

The formatter's newline handling already mostly follows the rules this proposal
needs to correctly infer semicolons in the right places. (One might wonder if
the author of dartfmt had optional semicolons in mind way back when initially
implementing it...)

This is a large part of the reason why it's feasible to go to optional
semicolons in the first place. The formatter's style is the canonical style and
almost all Dart users use it. This proposal follows that, which is why there are
so few breaking changes when semicolons are removed.

However, it's not perfect. It can sometimes insert newlines in a couple of
places where it shouldn't:

*   Between a local variable's type and name.
*   Between a local function's return type and name.
*   Before a `[` index expression in a long chained series of indexes.

We'll need to fix these issues. That can be done and shipped at any time since
very little code runs into the case where the line is long enough to cause a
split in these places.

## Next Steps

Before we move ahead with this proposal, I'd like more confidence in two things:

### Ensure the prototype is aligned with the proposal

I have two things:

*   A prototype implementation that I validated parses existing code correctly
    and code without semicolons correctly. So I know I have an implementation
    that works, at least on the kind of code in the corpus.

*   A description of a concrete set of grammar changes in this proposal. I made
    these based on my changes to the front end package in the prototype.

But I'm not entirely confident the former correctly implements the latter. I'm
not familiar with Fasta, so it may be that my prototype isn't a faithful
implementation of this proposal. One first step is to get help from others to
make sure my prototype does what this proposal says.

I'm not worried that it's *impossible* to specify good optional semicolon rules
because the prototype *does* work. I'm just worried that my description of *how*
it works in this proposal isn't correct.

### Ensure there aren't other undiscovered ambiguities

There is no way to [*prove* any context-free grammar is unambiguous][proof],
though it might be possible to do so for Dart's own specific grammar. In the
absence of a full proof, the next best thing is as many eyes on the problem as
possible and as much testing on real and contrived code.

[proof]: https://cstheory.stackexchange.com/questions/4352/how-is-proving-a-context-free-language-to-be-ambiguous-undecidable

I've done a lot of testing on realistic code, but I'd like more help seeking
out ambiguities I haven't found.

## Concerns

Based on the empirical numbers and the simplicity of the grammar changes, I
think this proposal works. As always, though, we should be cautious.

### Future language changes

One concern is that treating newlines as significant may paint us into a corner
with future language changes. For example, this proposal allows:

```dart
a
+ b
```

It's treated as `a + b`, which is the only unambiguous interpretation. However,
if we were to later add a prefix `+` operator (unlikely, but for example), then
the above code would change in meaning if we then treat the newline before a `+`
as significant.

Similar problems can occur if we add an infix form of an existing postfix
operator, like:

```dart
a++
b
```

We have some control over this. We can sacrifice a little robustness now and
make more newlines significant in unambiguous code. So we could say that a
newline is significant before `+` even though it leads to a syntax error today.
That would give us room to grow in the future.

Or we can treat dealing with newline changes as part of the migration plan for
future syntax additions as this proposal does for the current syntax.

Given that we are generally conservative about new operators (for good reason),
I think the risk of pain from this is relatively low.

## Questions and Alternatives

### Optional semicolons are terrible! Look at how bad they are in JavaScript!

It is true that JavaScript's handling of optional semicolons is bad. Brendan
Eich himself [says][eich]:

> ASI is (formally speaking) a syntactic error correction procedure. If you
> start to code as if it were a universal significant-newline rule, you will get
> into trouble. ... I wish I had made newlines more significant in JS back in
> those ten days in May, 1995.

[eich]: https://brendaneich.com/2012/04/the-infernal-semicolon/

Each language that does optional semicolons&mdash;and there are a lot of
them&mdash;does so using a different mechanism. Some of this is because the
language's grammar has different needs and some is just a matter of taste and
history.

JavaScript's rules were well-intentioned (few of us have designed and
implemented an entirely new language in less than two weeks!) but turned out to
be the wrong ones. The gist is that JavaScript tries to *ignore* all newlines
and *only if an error occurs* does it go back and turn some of them into
semicolons. All of the famous pitfalls of ASI in JavaScript flow from that.

This proposal, like other languages where semicolons are rarely seen in the
wild, presumes the opposite: a newline that can be a semicolon should be a
semicolon. None of the specific pitfalls you encounter in JavaScript apply to
this proposal. (In fact, it very deliberately does the exact opposite of JS in
all of those cases.)

### I hate how code looks without semicolons!

One of the challenges of programming language design is that some of it is
simply a matter of taste and different reasonable people have different
preferences. No ice cream flavor, no matter how tasty, will ever be *everyone's*
favorite.

I have hopped through several languages and coding style guides through my
career. Every time I do, my first impression is unpleasant. When I went from C#
to Java, I thought `lowerCaseMethodNames()` looked bad. Now when I look at C#
code, `CapitalizedMethodNames()` look wrong.

The lesson for me was that what I was really noticing was just that something
was *different* not that it was *bad*. The nice thing about *different* is that
it fades, surprisingly quickly. Humans are adaptable creatures. Name another
species that lives on all seven continents (that doesn't inhabit our own
bodies).

If Dart *sans* semicolons looks wrong to you, I ask you to consider that maybe
it just looks *different* and before too long it won't anymore. After all, there
is nothing natural about semicolons at the end of every statement. In no written
language are semicolons used heavily and in English they are only used as a
*separator*, not a terminator.

You may not remember it, but it probably was a long painful process to learn to
consistently insert semicolons in all the right places in your code. By making
semicolons optional, we can spare future new programmers from that pain.

### Why can't semicolons be inserted lexically?

I said each language implements optional semicolons differently. Some do it
purely or almost purely lexically. Go uses a [simple rule][go] where a semicolon
is implicitly inserted after any token from the set of tokens that can possible
end a statement.

Simple is good because it's easier to implement and easier for users to
internalize. Go's simple rule works well for Go because Go has a very clean,
simple grammar. The designers deliberately broke with C's syntactic tradition to
make something less familiar but more elegant.

[go]: https://golang.org/ref/spec#Semicolons

Dart hews much closer to C and also has a richer, more complex grammar. Fitting
more syntax into the same set of ASCII characters sometimes means "overloading"
punctuation to mean different things in different contexts. Consider:

```dart
{
  foo: bar()
}
```

Should we insert a semicolon after the `)`? If that code is a block containing a
labelled statement, yes. If it's a map literal, no. The lexical grammar doesn't
know if you're using curly braces for a block or a map.

Contextual keywords, which Dart uses heavily, pose another problem:

```dart
import 'foo.dart' show
  bar

main() {
  ui.show
  bar()
}
```

The lexer doesn't know that the newline should be ignored between the first
`show` and `bar`, but not the second. That syntactic overloading means the right
place for Dart to handle newlines is in the parser&mdash;in the syntactic
grammar&mdash;where we have that needed context.

## Methods and Data

All of the numbers in this proposal are based on a set of custom scripts and a
fork of the front_end package. Those are all here at
[github.com/munificent/ui-as-code][repo]. They aren't the most beautiful code,
but you should be able to run them locally yourself without too much difficulty.
I'll help you if you want.

[repo]: https://github.com/munificent/ui-as-code/tree/master/scripts

They need a corpus to run on (which you usually pass to the scripts as a
command line argument). I used a recent commit of the Dart SDK, the Flutter SDK,
and a cobbled-together script to download packages from pub.dartlang.org. You
should be able to run them on any Dart code you like.

I would definitely be interested to see the results if your codebase is
significantly different from what I tested against.
