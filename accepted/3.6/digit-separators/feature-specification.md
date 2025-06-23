# Digit Separators

Author: Lasse Nielsen, Sam Rawlins

Status: Accepted

Version 1.0

## Motivation

To make long number literals more readable, allow authors to inject [digit
group separators][] inside numbers. Examples with different possible separators:

```none
100 000 000 000 000 000 000  // space 
100,000,000,000,000,000,000  // comma
100.000.000.000.000.000.000  // period
100'000'000'000'000'000'000  // apostrophe (C++)
100_000_000_000_000_000_000  // underscore (many programming languages).
```

## Proposal

### Digit separators in number literals

Allow one or more `_`s between any two otherwise adjacent _digits_ of a NUMBER
or HEX\_NUMBER token. The following are not digits: The leading `0x` or `0X` in
HEX\_NUMBER, and any `.`, `e`, `E`, `+` or `-` in NUMBER.

That means only allowing `_`s between two `0-9` digits in NUMBER and between
two `0-9`,`a-f`,`A-F` digits in HEX\_NUMBER.

The grammar would be changing `<DIGIT>+` to `<DIGITS>` which is then `<DIGIT>`s
with optional `_`s between, and same for hex digits:

```bnf
<NUMBER> ::= <DIGITS> (`.' <DIGITS>)? <EXPONENT>?
  \alt `.' <DIGITS> <EXPONENT>?

<EXPONENT> ::= (`e' | `E') (`+' | `-')? <DIGITS>

<DIGITS> ::= <DIGIT> (`_'* <DIGIT>)*

<HEX\_NUMBER> ::= `0x' <HEX\_DIGITS>
  \alt `0X' <HEX\_DIGITS>

<HEX\_DIGIT> ::= `a' .. `f'
  \alt `A' .. `F'
  \alt <DIGIT>

<HEX\_DIGITS> ::= <HEX\_DIGIT> (`_'* <HEX\_DIGIT>)*
```

### Examples

```none
100__000_000__000_000__000_000  // one hundred million million millions!
0x4000_0000_0000_0000
0.000_000_000_01
0x00_14_22_01_23_45  // MAC address
555_123_4567  // US Phone number
```

**Invalid** literals:

```none
100_
0x_00_14_22_01_23_45 
0._000_000_000_1
100_.1
1.2e_3
```

An identifier like `_100` is a valid identifier, and `_100._100` is a valid
member access. If users learn the "separator only between digits" rule quickly,
this will likely not be an issue.

### Why choose underscores

The syntax must work even with just a single separator, so it can't be anything
that can already validly seperate two expressions (excludes all infix operators
and comma) and should already be part of a number literal (excludes decimal
point).

So, the comma and decimal point are probably never going to work, even if they
are already the standard "thousands separator" in text in different parts of
the world.

Space separation is dangerous because it's hard to see whether it's just space,
or it's an accidental tab character. If we allow spacing, should we allow
arbitrary whitespace, including line terminators? If so, then this suddenly
become quite dangerous. Forget a comma at the end of a line in a multiline
list, and two adjacent integers are automatically combined (we already have
that problem with strings). So, probably not a good choice, even if it is the
preferred formatting for print text.

The apostrope is also the string single-quote character. We don't currently
allow adjacent numbers and strings, but if we ever do, then this syntax becomes
ambiguous. It's still possible (we disambiguate by assuming it's a digit
separator). It is currently used by C++ 14 as a digit group separator, so it is
definitely possible.

That leaves underscore, which could be the start of an identifier. Currently
`100_000` would be tokenized as "integer literal 100" followed by "identifier
`_000`". However, users would never write an identifier adjacent to another
token that contains identifier-valid characters (unlike strings, which have
clear delimiters that do not occur anywher else), so this is unlikely to happen
in practice. Underscore is already used by a large number of programming
languages including Java, Swift, and Python.

We also want to allow multiple separators for higher-level grouping, e.g.,:

```none
100__000_000_000__000_000_000
```

For this purpose, the underscore extends gracefully. So does space, but has the
disadvantage that it collapses when inserted into HTML, whereas `''` looks odd.

### Related work

* [Java digit separators](https://docs.oracle.com/javase/8/docs/technotes/guides/language/underscores-literals.html)
* [Python PEP 515 - underscores in numeric literals](https://peps.python.org/pep-0515/)

### Possible new lint rules

There are some possible new lint rule considerations, but none of these are
considered vital to the usability or general success of the feature.

The feature is designed to help the readability of long numbers. But a
developer can still make a mistake about where to place separators. For example:

```
var one = 1_000_000;
var two = 2_000_000;
var three = 3_000_000;
var four = 4_0000_000; // Whoops!
```

If a developer uses the Dart formatter to format their code, they cannot try to
vertically align the numbers with whitespace (extra space characters are
removed by the formatter). So we could offer a lint rule to only place
separators every three digits of a decimal number. Also possibly a similar rule
for hexadecimal numbers. If a developer ever uses digit separators for a
different purpose (as in separating the digits of a phone number), the rule may
not prove useful.

A separate lint rule could encourage _consistent_ digit separators, which
triggers if the digit groups do not have the same size (except the most
significant one, which can be shorter). If there are any `__` separators, the
number of `_`-separated groups between them should also be the same, and
repeatedly for higher numbers of `_`s.

### Possible new quick fixes

There are some possible new automated fix ("quick fix") considerations, but
none of these are considered vital to the usability or general success of the
feature.

#### Unexpected underscores

With the digit-separators feature, separators can be added between _digits_ of
a number literal, but nowhere else. In most error cases, the unexpected
underscore can be detected as such, and we can offer quick fixes to remove
unexpected errors (for example, `100_`, `100_e1.2`, `100._00`). In a few cases,
the intention is not as straightforward, such as `100._100`, where `_100` can
be a legal name of an extension member (though the presense of such a private
extension member can be detected).

#### Unexpected commas

The only legal digit separator that is introduced with this feature is the
underscore character. If a developer attempts to use another character, for
example commas, as a separator, we may be able to detect this, and offer a
quick fix to convert the commas to underscores.

### Non-breaking change

This change is strictly non-breaking. The feature can be thought of as a single
change from previous Dart syntax: some syntax which was previously illegal
(producing compile-time errors) becomes legal.

(The feature is still introduced with a [Dart language version][], so that
packages that start using the feature declare that they require some new lower
bound of the Dart SDK.)

### Formatting

As any number literal remains a single token, there are no formatting
considerations.

## Changelog

### 1.0

- Initial version

[digit group separators]: https://en.wikipedia.org/wiki/Decimal_separator#Digit_grouping
[Dart language version]: https://github.com/dart-lang/language/blob/main/accepted/2.8/language-versioning/feature-specification.md
