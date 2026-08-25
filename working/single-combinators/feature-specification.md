# Single Combinators

Author: Sam Rawlins
Status: Proposed
Version: 1.0

Specification for issue
[#2824](https://github.com/dart-lang/language/issues/2824), restricting the
specifying of combinator clauses to one combinator per import/export directive.

## Motivation

In Dart, `import` and `export` directives currently allow an unbounded sequence
of `show` and `hide` combinator clauses:

```dart
import 'package:collection/collection.dart' show ListEquality hide MapEquality;
export 'package:foo/foo.dart' show A, B show A hide C;
```

Allowing multiple combinators introduces cognitive load, confusion, and subtle
bugs without providing any expressive benefit:

* Multiple `show` clauses compute the _set intersection_ of shown identifiers,
  which might be counter-intuitive (users might expect a union) and is
  equivalent to a single `show` clause containing only the shared names.
* Multiple `hide` clauses compute the _set union_ of hidden identifiers, which
  is equivalent to a single `hide` containing all names (`hide A, B`).
* Mixing `show` and `hide` clauses (e.g., `show A, B hide B`) is equivalent to
  a single `show A` clause.
* Repeated identical combinators or contradictory combinations add syntactic
  noise.

Restricting import and export directives to at most one combinator simplifies
the language grammar, avoids surprising intersection/hiding semantics,
simplifies tooling (code completion, formatting, linters, and IDE
refactorings), and cleans up directive syntax.

## Syntax

The grammar for import and export directives is modified to allow at most one
combinator:

### Previous grammar

```bnf
<importDirective> ::=
    <metadata> `import' <configurableUri> (`deferred'? `as' <typeIdentifier>)? <combinator>* `;'

<exportDirective> ::=
    <metadata> `export' <configurableUri> <combinator>* `;'

<combinator> ::=
    <showCombinator>
  | <hideCombinator>
```

### Proposed grammar

```bnf
<importDirective> ::=
    <metadata> `import' <configurableUri> (`deferred'? `as' <typeIdentifier>)? <combinator>? `;'

<exportDirective> ::=
    <metadata> `export' <configurableUri> <combinator>? `;'
```

## Static errors and warnings

### Compile-time Error

When the `single-combinators` experiment is enabled, having more than one
combinator (`show` or `hide`) on an `import` or `export` directive is a
**compile-time error** (`multipleCombinators`).

### Static deprecation warning

For libraries where the experiment is not enabled, writing multiple combinators
already produces a static warning (`WarningCode.multipleCombinators`, to be
renamed `WarningCode.multipleCombinatorsDeprecated`) alerting developers that
multiple combinators are deprecated and will not be supported in a future
version of Dart.

### Migration plan

Any code in which the above mentioned `multiple_combinators` static warning is
not disabled or ignored is already OK to go. Any code in which this warning is
disabled or ignored may need migration. The migration path is to stop disabling
or ignoring the static warning and collapsing multiple combinator clauses into
a single clause.

To collapse a set of combinator clauses, the following steps can be taken:

1. Collapse all `show` combinators on a given import/export directive into one
   `show` clause whose named elements are the intersection of the named
   elements in each `show` clause being combined.
2. Collapse all `hide` combinators on a given import/export directive into one
   `hide` clause whose named elements are the union of the named elements in
   each `hide` clause being combined.
3. If there is still a remaining `show` clause and `hide` clause, combine them
   into one `show` clause whose named elements are the shown elements set-minus
   the hidden elements of the clauses being combined.

## Examples

### Valid Code

```dart
import 'dart:math';
import 'dart:math' show min, max;
import 'dart:math' hide Random;
import 'dart:math' as math show min, max;

export 'dart:async';
export 'dart:async' show Future, Stream;
export 'dart:async' hide Zone;
```

### Invalid Code (with `single-combinators`)

```dart
import 'dart:math' show min show max; // Compile-time error on second 'show'
import 'dart:math' show min hide max; // Compile-time error on 'hide'
import 'dart:math' hide min hide max; // Compile-time error on second 'hide'
export 'dart:async' show Future hide Stream; // Compile-time error on 'hide'
```
