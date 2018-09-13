# Dart 2 String Issues
Author: lrn@google.com

## Motivation

This document tries to summarize issues that have been filed against the Dart `String` class, as well as migration issues related to various ways to modify the `String` class or how strings are worked with.
This document does not propose any actual changes or solutions, but lists some possible options in order to discuss their potential migration issues. This should not be taken as an endorsement of any particular approach.

## Background

### Dart 2.0 Strings

Dart 2.0 strings are sequences of UTF-16 code units.
The code units are individually addressable, indices in string operations point to code units, and strings need not be valid Unicode strings (they may contain invalid encodings, which for UTF-16 means unpaired surrogates). 
In this way, Dart strings are similar to C#, Java, JavaScript strings. Like JavaScript, the index operator returns a single-code-unit string, since neither language has a "character" type.
String equality is based on code-unit equality.
This string model is simple, it allows constant time indexing and length computations, but leaves it to the user to handle any higher level of abstraction, except that strings have a Unicode code point iterator as well (`runes`), which treats paired surrogates as a single code point.

Dart regular expressions are based on JavaScript regular expressions, and work on strings as sequences of UTF-16 code units. JavaScript regular expressions have since gotten the "/u" Unicode flag which makes them work on code points instead, but the Dart VM has not ported that feature.

### History of Dart Strings

Dart 1 originally had strings based on Unicode scalar values (code points except surrogates). The VM stored non-BMP (Basic Multilingual Plane, the Unicode code points in the range 0..65535) strings as sequences of 32-bit integers (aka. UTF-32), with smaller representations for BMP-only strings (16-bit per entry) or Latin-1 only strings (8 bit per entry). 

Requiring the string to only contain valid scalar values was impractical because strings provided by the surrounding environment (mainly the browser) were not guaranteed to not contain unpaired surrogates anyway. Changing the world was not practical, so effectively strings were allowed to contain unpaired surrogates, but literals were still not allowed to express such strings. When testing, you needed workarounds like `"ab${"\u{10ffff}"[0]}"` to insert an unpaired surrogate into your test code.
So, strings were sequences of code points, not scalar values.

The code-point string model could not be efficiently compiled to JavaScript or integrated into the browser (the internal model of the Chrome browser is also UTF-16 strings).
The Dart string model was then changed to match the browser, which means UTF-16 sequences. 
This also allowed an efficient implementation of regular expressions in the VM, which previously required re-coding the string as UTF-16 before running the PCRE regular expression engine on the text. This was prohibitively slow. With UTF-16 strings, the Dart VM could integrate the Irregexp regular expression engine used by Chrome and Firefox and use it directly, and ensure that Dart programs using regular expressions would work the same in the VM and in a browser.

Dart has never had "Unicode support" in the platform libraries, in the sense of any functionality that depends on knowing Unicode tables. The only exceptions are the `toLowerCase` and `toUpperCase` methods on `String`, which were inherited from JavaScript, and which do use some notion of Unicode case conversion.
Regular expression "case insensitive" matching uses a particular kind of case folding specified in the ECMAScript specification, and not the full Unicode case folding.

The platform libraries have never been "locale aware".  Any locale-dependent operations are handled by using `package:intl`. Regular expressions are not locale aware in Dart or JavaScript.

In other words, the current Dart strings evolved to be very similar to JavaScript strings because it made it possible to compile to JavaScript while preserving both performance and behavior.

## Issues With Dart Strings

There are issues with the Dart string model, and the following issues are some of the most reported ones..

### No Extended Grapheme Cluster Support

When working with human readable text, which is one of the major use-cases of strings, looking at code units is not enough. When text is displayed, the glyphs (the visible representations of what the reader thinks of as a "character") are really representations of extended grapheme clusters. 
A grapheme cluster can be as small as a single code point, or it can be a combination of multiple code points (like the letter `e` and a combining accent together representing `é`, a smiley emoji joined with a color and a tool to create a colored professional emoji, or two country code characters combining to be a flag, and there is no upper limit to how many combining marks can be used in the same grapheme cluster). The extended grapheme cluster specification is the latest Unicode specification for which code point sequences should be grouped as a single grapheme cluster, and the "extended" part is there because it is more complex than earlier versions (mainly due to emojis).

You should never separate text inside a grapheme cluster, but the string class does not provide any way to find the grapheme clusters or work with them. This leads users to use either code points or code units as the way to manipulate text strings, which works deceptively well for many western languages (those with all letters included in Latin-1 are particularly safe, because they rarely use combining marks, but even those just in the basic multilingual plane will often work well for common use-cases). It then breaks down the moment it encounters a non-BMP character, e.g., a Chinese, Japanese, or Korean character, or an emoji.

Dart should support working with text strings at the extended grapheme cluster level.
Grapheme cluster based operations should preferably be locale aware.

### Easy Misusable API

Even if Dart starts supporting string operations based on extended grapheme clusters, the current string API is still available and misusable.
Methods directly on the `String` class are easy to discover and use, and since it mostly works for simple cases, it's still likely to be used where the grapheme cluster based API should have been used.

To avoid such misuse, the existing API may potentially be discouraged or removed. Removing it will be a breaking change.

### Indexing

Indexing into strings, like the index returned by `String.indexOf`, is error prone because it is a plain integer and you shouldn't be doing arithmetic operations on the index (blindly incrementing an index can create an index in the middle of a grapheme cluster, which you shouldn't be using for anything).

For a grapheme cluster based API, such indexing can either use integers, but discourage doing arithmetic on them, use opaque immutable position objects to hide the integer, or return an object that can be used to iterate from, moving the position forwards in grapheme cluster steps, and allowing operations at the current position (like an object representing the remainder of the string from that position).

Random access into a string is likely a mistake - it should always be using indices or position objects returned by the string itself (or generic "start"/"end" markers). That should then always be at code point or grapheme cluster boundaries.

### (In-)Compatible Strings

The UTF-16 based strings are a perfect fit for JavaScript compilation because they are the platform's native string format. That also make them less than perfect for platforms where the native string representation (the kind you need to use to communicate with system libraries) is not UTF-16 based. That is the case for Flutter and Fuchsia, and to some extend for the VM on any Posix system.

When the VM prints a string, it converts it to UTF-8 before sending the bytes to stdout. When the platform uses UTF-8 strings and Dart uses UTF-16 strings, all system communication needs to copy and convert string data in both directions, which is an annoying and worthless overhead.

When you read a file name from disk, it is converted it to a string in some way. Not all file names are even valid UTF-8 strings, so using a String object to represent the file name is error prone (but as ususal, when most things are ASCII, you won't see the problem).

It would be convenient if the Dart string representation could match the platform string representation, and if there is a way to represent arbitrary byte sequences as well (whether as strings, or as something as convenient to create as a string literal).

It might be valuable to allow each platform to define its own string representation, or at least to allow it to pick between UTF-8, UTF-16 and UTF-32 (allowing all Unicode strings, rather than only, say, Latin-1 strings).
It is also possible to allow a either single platform to support multiple string encodings at the same time, or have all Dart platforms support two or all three of these, but with only one encoding being really efficient for the platform.

If we remove most existing API from the `String` class, it might even be possible to completely hide the underlying storage format, and only expose strings as iterable sequences of code points, independently of the underlying representation. This would ensure that string code would be platform independent. If we cannot do this, then it's likely that Dart code for the web will not consider that other string representations than UTF-16 exist.

### Invalid Unicode Strings

Not all sequences of code units are valid. For UTF-16, an unpaired surrogate is invalid. For UTF-8, a leading byte not followed by the correct number of trailing bytes is invalid, as are invalid leading bytes (0xF8..0xFF), overlong encodings and encodings of surrogate values.
For UTF-32, any value that is not a Unicode scalar values is invalid.
If Dart has a string backed by code units, of either kind, it's hard to reject strings that do not contain valid encodings when they are supplied by the surrounding system.
If Dart chooses to reject such strings, then Dart needs to validate all external data before accepting it as a string, and it might just cause unavoidable run-time errors when input isn't valid, without any good work-around.
A mis-match between system strings and Dart strings is already causing problems, so to deliberately add another difference may be problematic.

It's likely that Dart will have to accept invalid encodings in externally backed strings or strings created from run-time data. It's likely impractical to not support them in plain Dart strings then.

If we hide the underlying representation in the API, then it becomes harder to handle invalid encodings, because they will leak through anyway. A code point iterator may need to be able to tell whether the previous value was invalid or valid.

### Equality

String equality is currently based on code-unit equality. It would be convenient if equality worked at a higher abstraction level than that.

String equality (and hashing) needs to be fairly efficient. Any code using JSON will need to do string lookup and equality, and adding too much overhead is not viable.

Equality of extended grapheme clusters is very complicated, which is why there is more than one kind to choose from. Grapheme cluster based equality would be based on first normalizing to one of four normal forms and then comparing the code points of the normal form. While making that kind of equality available, it's unlikely to be the default (if for no other reason than having to pick a normal form).

A more likely equality would be code-point based equality, where a string representing a sequence of valid code points is equal to another string representing the same code points.

If we allow invalid encodings, one option is to consider valid code point encodings as equal to another valid encoding of the same code point, and an invalid encoding as equal only to the same (invalid) sequence of code units. For comparing two UTF-16 based strings, that is equivalent to the current string equality, which is also the string equality of JavaScript. For comparing two UTF-8 based strings, it's also equivalent to comparing code units directly.

You can compare a UTF-16 based string to a UTF-8 based string if necessary, and since their invalid encoding sequences are disjoint, they would only be equal if they are valid Unicode strings. If a platform has both kinds of strings (which is an option), then hash code becomes more expensive because it has to recognize valid code point encodings.

For ordering (`String.compareTo`), one approach would be to order invalid encoding code units before or after valid encoded code points, and then compare invalid code units to each other and valid code points to each other.

A grapheme cluster based string can also add normalization operations which change the code point order or content in order to canonicalize the representation of a text. It should likely not be done by default. It should be possible to write a string literal that is equal to any externally supplied, potentially invalid and non-normalized, string.

### Patterns and Parsers

The Dart `Pattern` class represents "string matchers" which can be applied against a string and find matching substrings. The platform libraries contain only two pattern classes, `RegExp` and `String` itself. The `Pattern` class is a generalization over regular expressions, and it has worked well for Dart to allow strings to be patterns. Languages without such a generalization often require you to escape a string before using it as a regular expression, just to get the functionality of pattern matching for a literal string.

There are other implementations of `Pattern` in the wild, even if there aren't many. All Such classes will likely need to be rewritten if the string representation changes or if direct code-unit access is removed.

Likewise, other functions that access individual characters will also need to be rewritten. The typical example of that is a parser. The platform parsers (like `int.parse` or `jsonDecode`, which works on code units because they only need to recognize ASCII) can be migrated along with the string class, but external parsers need to be migrated.

### Regular Expressions

Regular expressions is a special case of patterns. In the Dart VM they are implemented using a version of the Irregexp regular expression engine, and they are compiled directly to JavaScript regular expressions on the web.
If the Dart VM changes the string representation, say to something backed by UTF-8, it will need to also adapt the regular expression sub-system to handle that kind of strings.

It would be convenient if regular expressions worked at the code-point level instead of at the code unit level.

JavaScript regular expressions have a `/u` flag which make them work on code points, which for JavaScript means treating a surrogate pair as a single character (matched by a single `.`).
Dart could probably change its regular expressions to use this flag by default, but the VM would need to port the newer version of Irregexp, and then find a way to generalize it to UTF-8 instead of UTF-16.
It's unlikely that regular expressions will be grapheme cluster based, since we can't compile that to JavaScript anyway.

If we allow invalid string content, it's not clear how a regular expression should treat invalid UTF-8 bytes. Using their actual value would conflict with a valid encoding of the same byte value, a problem that UTF-16 does not have.
Converting each strings from UTF-8 to UTF-16 before running a regular expression on the string is prohibitively slow. That was what the VM did before porting Irregexp.

## Migration Considerations

If we change the `String` type or introduce more string types, existing code will need to be migrated.
Migrating platform code is hard because any API change is a breaking change, but since `String` cannot be implemented, we may have some options for adding things to that class.

### Modifying the String Class

We can add more members to `String` without breaking anything. Since classes cannot implement `String`, adding functionality is non-breaking. 
We can easily add a `graphemes` getter on `String` which provides access to the extended grapheme clusters of the string along with functionality on those, similarly to how `runes` give access to code points.
It does make grapheme cluster operations harder to discover than the members directly on `String`, but it allows those operations to have the optimal names, without having to conflict with existing `String` members.

Removing functionality from `String` is breaking, because any existing code using the functionality would break. That would have to go through a deprecation period where the functionality still works, and where all existing code is migrated off the functionality. 
It is likely an impossible task to migrate all existing `String`-based code manually.
Depending on the change, it might be possible to migrate code mechanically, by having a tool which understands Dart well enough to identify string operations and rewrite them to a new behavior, such that any package can instruct `pub` to automatically migrate its dependencies.
As usual, dynamic code is incredibly hard to understand for tools, so it's unlikely that such a tool can have a perfect success-rate. There may be existing code doing `dynamicVariable[3]` on both a string and a list.

Even if we deprecate and remove existing `String` members, we will not be able to reuse the names for new functionality until the old member has been removed. That makes it impossible to migrate from an existing member to a new member with the same name (but different grapheme-cluster based functionality and/or parameters), without introducing an intermediate member, which should then also be removed again afterwards.

### Multiple String Types

Instead of changing the behavior of `String`, another possibility is to add a separate type, maybe something like `Text` (but not exactly that, it's already been used for other things) with a new grapheme cluster based API.

That does introduce other problems. It's unclear what type a string literal should represent, and requiring a prefix, like `t"text string"` would still make it less usable than the original string class.
Also, having two types would mean that every method that takes a string-ish input would have to choose which kind to accept (or accept some common super-class which cannot have much functionality itself).

Even if string literals implemented both types, it would mean that the new operations wouldn't be able to use the old method names, even where they are the obvious choice.

Migration would be trivial (the old class still exists), but the new class isn't as usable as possible, and we can't migrate existing class APIs to expect the new class, since that would break existing implementations of those classes.

### Introduce a Super-class for String

We could introduce a super-class of the `String` class with a very restricted set of functionality.
Maybe something like:
```dart
abstract class CharSequence {
  RuneIterator get runes;
  GraphemeClusters get graphemes { /* A default implementation based on RuneIterator */ }
  int get hashCode { /* A default implementation based on RuneIterator */ }
  bool operator==(Object other) { /* A default implementation based on RuneIterator */ }
  int compareTo(CharSequence other) { /* A default implementation based on RuneIterator */ }
}
@deprecated
abstract class String implements CharSequence {
  // current methods
}
```
A new function could accept `CharSequence`, and it will be compatible with strings.

We still can't make existing APIs accept `CharSequence` instead of `String` because it would be breaking for sub-classes that still accept `String`.

It's better than having two parallel string types, but not by much. 

### Making String Methods Extension Methods
If Dart gets extension methods, we could change the functionality on `String` to be entirely defined by extension methods (apart from the rune iterator). That way, the old behavior can be replaced with new behavior by changing the extension method import. (This can work because the `String` class cannot be implemented by non-platform classes, it's not generally a non-breaking change to make a virtual method non-virtual).

Assume we can hide extension methods in imports, the new functionality could be opted-into by doing:
```dart
import "dart:core" hide String.*;  // Hides extension methods on String, not static methods.
import "dart:core/2.2" show String.*; // Imports new String extension methods from core/2.2.
```
We can then deprecate the existing methods that we want to remove, move them to an opt-in library, say `dart:core/2.1`, so you can keep using them by doing `import "dart:core/2.1" show String.*`, then switch the default version in `dart:core` to be the new methods, and finally, maybe, remove the old version.

If Dart gets a platform version/feature opt-in functionality, it might be used to pick the default string behavior, so any code opting in to a version 2.2 or later will get the new string automatically, and will need to import the backwards compatible extension methods or migrate their code.

### Making String Methods "Static Type Alias" Methods

Another option for implementing extension method-like behavior is to introduce a new "static alias type" with those methods, and allowing objects to be cast to and from such a type. That is, instead of attaching the extension method to the existing class, attach it to a new type which is effectively an alias for the existing type, and you have to opt in to the new functionality by casting the object to the new type.
In that case, we could make `CharSequence` above the actual type and `String` a static alias for `CharSequence` which adds the existing string functionality.
```dart
class CharSequence { ... }
typedef String extends CharSequence {
  int indexOf(...) { ... }
}
typedef Graphemes extends CharSequence {
  // grapheme based operations.
}
```
This will allow the `String`, `Graphemes` and `CharSequence` types to be used interchangeably (they are all `CharSequence` objects, some just aliases with more static functionality), but new code could be encouraged to use `Graphemes` instead of `String`.

We could even name both APIs `String` and use versioning and/or opt-in to select which one a user gets, as described in the previous section. 
