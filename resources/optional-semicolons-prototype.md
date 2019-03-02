This is a quick write-up of the investigation I did around optional semicolons
after writing the [Terminating Tokens][] proposal.

[terminating tokens]: https://github.com/dart-lang/language/tree/master/working/terminating-tokens

That proposal was a thorough experiment to see if it's possible to make
semicolons optional with a minimum of breakage to existing code. I think the
answer is generally "yes", but the resulting rules to achieve that are quite
subtle and complex. It's not clear that I flushed out all of the ambiguities it
causes, nor is it clear if it would paint us into a corner with possible future
language changes. Honestly, it just doesn't feel like a great proposal to me. It
feels sort of weird and sort of magical.

So, at Leaf and Lasse's suggestion, I spent a bunch of time trying a couple of
different approaches. The high level difference was that instead of minimizing
breakage, assume instead that users have to opt in to implicit semicolons.
Existing code will not break because it will still be parsed without treating
newlines as significant.

In order to opt in, you would add some sort of marker to the file and then run a
tool roughly like dartfmt that would remove the semicolons and adjust any
whitespace needed to ensure the file is parsed the same way as it was before.
This explicit opt in and migration frees us to design a simpler set of rules
that don't have to be as accommodating to existing code. At least, that's the
idea.

I tried [a couple of different prototypes][prototypes] along those lines to see
if I could get something to work. **The TL;DR: is... no. Even with some kind of
formatting step, I kept needing to add more and more complex rules to handle
code that intuitively looked like it should work.**

[prototypes]: https://github.com/munificent/ui-as-code/tree/semicolons

## A More Conservative Approach

The main prototype I worked on works like this:

### Add implicit semicolon rule

First, in the grammar, replace every explicit `;` terminal with a new `term`
rule, except for the `;` in C-style for loops. The `term` rule matches a literal
`;` or a special "implicit semicolon" token inserted by the lexer. This prevents
you from using a newline for the `;` in a for loop and also ensures later phases
don't ignore a literal semicolon. It would be pretty weird if the parser
allowed:

```dart
function(;;;;;
  what;;;;
  + are;;; + you;; ;
  + ;;; thinking)
```

### Insert implicit semicolons lexically

Then, the lexer inserts implicit semicolon tokens anywhere a newline appears
between two lexemes. That inserts way too many semicolons, so we filter out as
many as we reliably can in the lexer. The rules are:

*   Ignore a newline after `&`, `&&`, `&&=`, `&=`, `!=`, `|`, `||`, `||=`, `|=`,
    `^`, `^=`, `:`, `,`, `=`, `==`, `=>`, `>=`, `>>`, `>>=`, `>>>`, `<`, `<=`,
    `<<`, `<<=`, `-`, `-=`, `{`, `(`, `[`, `%`, `%=`, `.`, `..`, `+`, `+=`,
    `?.`, `??`, `??=`, `;`, `/`, `/=`, `*`, `*=`, `~`, `~/`, `~/=`, `assert`,
    `case`, `catch`, `class`, `const`, `default`, `do`, `else`, `enum`, `final`,
    `finally`, `for`, `if`, `in`, `new`, `super`, `switch`, `throw`, `try`,
    `var`, `while`, and `with`. These are tokens that can't end an expression.
    (In retrospect, it's probably much shorter to list the tokens that a newline
    *is* significant after.)

    Note that `>` is *not* in this list. Neither is `{` We'll get to those.

*   Ignore a newline before `;`, `.`, `..`, `)`, `]`, `?`, `?.`, `:`, `=`, `=>`,
    `,`, `&&`, `||`. These are tokens that can't begin an expression. We *could*
    list all of the infix operators here too since ignoring newlines before
    those would minimize breakage. But dartfmt idiomatically does not put the
    other operators at the beginning of a line, so *not* doing that gives us
    room to grow. So the set of infix operators in here is basically based on
    the style choices we happened to make.

    I put `||` and `&&` here even though dartfmt won't start a line with them
    because lots of Flutter code is hand-formatted and *does* put them on their
    own line. As you can see, I'm already starting to make choices that feel
    arbitrary.

Note that lots of "keywords" aren't in this list. That's because many keywords
in Dart aren't reserved words. The lexer can't ignore a newline before `hide`
because you *could* write:

```dart
class hide {}
main() {
  int i
  hide j
}
```

### Ignore implicit semicolons inside delimited expressions

That still leaves too many obviously useless semicolons, like in:

```dart
function(
  meaning
  -
  less
  -
  newlines)
```

Code like this isn't idiomatic, but it may be what a user pounds into their
keyboard before they auto-format it. We know the newlines can be ignored because
semicolons are never meaningful inside an argument list.

So, like the Terminating Tokens proposal, in the parser we maintain a stack of
"newline contexts". Whenever some delimited expression region begins, we push an
"ignore newlines" context onto the stack. When a block of lambda body begins, we
push a "meaningful semicolons" context. (The fact that lambdas nest inside
expressions are why this is a stack.) If the innermost context is "ignore
newlines", then the parser implicitly skips over *all* implicit newline tokens.

This is pretty similar to how Python handles newlines. It treats most newlines
as signficant but ignores them inside bracket characters.

The contexts where newlines are ignored are:

*   Parentheses: parameter lists, argument lists, `if` and `while` conditions,
    and `for` loop headers.
*   Index operators.
*   List, map, and set literals. We handle them here in the grammar. We can't
    ignore a newline even directly after `{` because we don't know if that's a
    map literal, set literal, block, class body, switch body, or function body.
*   Inside string interpolation expressions.

### Ignore implicit semicolons in the grammar

Finally, the last step is to comb through the grammar and ignore implicit
semicolons in specific places where newlines can appear but where we don't want
them to be treated as significant.

This is just a laundry list of weird ugly corners of the grammar. Many of them
have to do with Dart's long list of contextual keywords. The grammar ignores
implicit semicolon tokens:

*   Between `abstract` and `class`. It could be meaningful after `abstract`:

    ```dart
    var abstract
    var another
    ```

    And it could be meaningful before `class`:

    ```dart
    var a = 1
    class Foo {}
    ```

    So we check for the explicit pair `abstract` and `class`.

*   Between `deferred` and `as`.

*   After `import`, `export`, and `part` when those are directives.

*   Before `extends`, `with`, `implements`, on `on` in declarations.

*   After `external` and `native` in declarations.

*   Between a type name and a variable name. This is the really hard, subtle
    one. The implementation in the prototype is hokey and probably not correct.
    The fundamental problem is cases like:

    ```dart
    main() {
      SomeLongClassName
          someLongVariableName
    }
    ```

    Even though each of those identifiers is a valid expression statement on its
    own, we probably want to treat this like a variable declaration. Code like
    this *does* occur in the wild.

*   Before `}` in a class body. We can't ignore a newline before all `}` because
    of blocks and function bodies:

    ```dart
    {
      var i // Need implicit semicolon here.
    }
    ```

    But a semicolon before the final `}` here would be an error:

    ```dart
    class Foo {
      method() }
      // Not here.
    }
    ```

*   After `}` in a local function declaration, block, or switch body. We can't
    ignore newlines after all `}` because of collection literals and lambdas:

    ```dart
    var lambda = () {} // Need implicit semicolon here.
    var map = {} // And here.
    ```

    We can't leave the implicit semicolon after all of them either:

    ```dart
    if (condition) {
    } // Implicit semicolon here breaks the "else".
    else {}
    ```

*   After `>` when an infix operator. This one surprised me! We can't ignore a
    newline after all `>` tokens like we can most other operators because of:

    ```dart
    class Foo {
      factory Foo() = Bar<int>
    }
    ```

    Things like this keep me up at night.

*   After `?` in a conditional expression. It's not idiomatic to have a newline
    there, but it makes it easier for users to write unformatted code. We can't
    ignore newlines after all `?` tokens because of nullable types:

    ```dart
    var b = o is Foo?
    ```

*   After `yield` and `async` when used as keywords.

*   After `)` in a function type:

    ```dart
    void Function(SomeLong parameterList) // Ignore newline here.
    aHigherOrderFunction() {
      // ...
    }
    ```

    We have to be careful on this one because that syntax is also ambiguous:

    ```dart
    abstract class Foo {
      void Function(SomeLong parameterList) // Ignore newline here.
      aHigherOrderFunction() {
        // ...
      }
    }
    ```

    Now, because `Function` isn't a reserved word, that looks like a declaration
    of an abstract method. Ugh.

*   After `)` in `if`, `for`, and `while` statements. Treating it as significant
    would be valid, but not what the user wants:

    ```dart
    if (condition) // Don't want an empty statement here!
      body()
    ```

*   Before `in` in a `for` loop.

There are more, but you get the idea. I actually never got to the point in the
prototype where I felt like I'd chased down all of the places in the grammar
that need to be addressed. I just ran out of steam.

The initial goal was a simpler set of rules, and I think the above is already a
failure to achieve that.

## Future Exploration

For now, given the bandwidth we have, I think the right choice is to table
optional semicolons and focus on non-nullable types and other changes. At the
same time, I do think this is a desirable feature at a high level. In the
future, I think it's worth taking another shot at it, probably by coming at it
from a different angle.

Much of the difficulty of doing optional semicolons in Dart compared to other
languages comes from a few parts of the language:

*   **C-style declaration syntax.** Not having a mandatory keyword for creating
    a variable means that inside the body of a function, the type annotation and
    expression grammars are superimposed. That makes it hard to tell what
    something like this means:

    ```dart
    main() {
      SomeLongClassName
          someLongVariableName
    }
    ```

    Method syntax that doesn't use a keyword is also problematic, but less so
    since the top level and class body grammars don't also include arbitrary
    expressions.

*   **The weird `Function` function type syntax.** Placing the return type
    before a function declaration causes some ambiguity. The fact that
    `Function` is not even a reserved word makes things harder, especially when
    you have functions that return function types.

*   **The large number of non-reserved contextual keywords.** Many newlines have
    to be handled in the parser because, who knows, maybe someone wants to name
    a variable `abstract` one day. This also causes ambiguity:

    ```dart
    import 'foo.dart'
    hide bar
    ```

    It's possible that the user actually intends this to declare a variable
    `bar` of type `hide`. The fact that many contextual keywords like `hide`,
    `show`, `get`, and `set` are also very practically useful identifiers
    exacerbates this.

When I first started working on optional semicolons, I felt the feature was too
small-scale to require users to explicitly opt in. But, once we put an opt in
step and a mechanical migration on the table, that gives us some opportunities.
If the user is running a tool to fix their code *anyway*, it could also apply
other syntax changes.

One very ambitious option then is to address the syntax problems that make
optional semicolons hard at the same time:


*   **C-style declaration syntax.** We could require a keyword for declaring a
    variable like TypeScript, Kotlin, and Swift all do. Possibly even move types
    on the right:

    ```
    let foo = value
    ```

*   **The weird `Function` function type syntax.** We could add a more
    conventional arrow-style notation for function types:

    ```
    aHigherOrderFunction(): (SomeLong parameterList) -> void {
      // ...
    }
    ```

*   **The large number of non-reserved contextual keywords.** Except for the
    really useful ones like `hide`, `show`, `get`, and `set`, we could reserve
    them. Do users really need to be able to name a class "extends"?

    One key challenge with this is that if we reserve an identifier the user is
    using in their public API, that's no longer a change we can mechanically
    fix. They have to make a breaking change to their API to use a different
    name.

    But, we can address that by adding an escaping syntax to let you explicitly
    use an identifier that collides with a reserved word. In Swift, [you do this
    using backticks][backticks]. This would give us a way to let users continue
    to use that lexeme as an identifier even though it's reserved. It might also
    be useful for interop with other languages whose set of reserved words
    differs from Dart's.

[backticks]: https://swift.unicorn.tv/articles/reserved-words-in-swift-and-how-to-escape-them
