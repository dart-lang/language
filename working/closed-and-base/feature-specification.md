# "Closed" and "base" types

Author: Bob Nystrom

Status: In-progress

Version 1.0

This proposal specifies `closed` and `base` modifiers on classes and mixins,
which allow an author to prohibit the type being extended or implemented,
respectively.

This proposal is a subset of the [type modifiers][] strawman, which also
contains most of the motivation. It is split out here because the type modifiers
strawman also proposes prohibiting classes being used as mixins, which is a
larger breaking change. This proposal is non-breaking.

[type modifiers]: https://github.com/dart-lang/language/blob/master/working/type-modifiers/feature-specification.md

## Syntax

A class declaration may be preceded with the built-in identifiers
`closed` and/or `base`:

```
classDeclaration ::=
  'closed'? 'abstract'? 'base'? 'class' identifier typeParameters?
  superclass? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
  | 'closed'? 'abstract'? 'base'? 'class' mixinApplicationClass
```

A mixin declaration may be preceded with the built-in identifier `base`:

```
mixinDeclaration ::= 'base'? 'mixin' identifier typeParameters?
  ('on' typeNotVoidList)? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
```

This proposal will likely build on top of the [sealed types][] proposal, in
which case the full grammar is:

```
classDeclaration ::=
  'closed'? ('sealed' | 'abstract')? 'base'? 'class' identifier typeParameters?
  superclass? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
  | 'closed'? ('sealed' | 'abstract')? 'base'? 'class' mixinApplicationClass

mixinDeclaration ::= sealed? 'base'? 'mixin' identifier typeParameters?
  ('on' typeNotVoidList)? interfaces?
  '{' (metadata classMemberDeclaration)* '}'
```

[sealed types]: https://github.com/dart-lang/language/blob/master/working/type-modifiers/feature-specification.md

**Breaking change:** Treating `closed` and `base` as built-in identifiers means
that existing code that uses those the names of type will no longer compile.
Since almost all types have capitalized names in Dart, this is unlikely to be
break much code.

### Static semantics

It is a compile-time error to:

*   Extend a class marked `closed` outside of the library where it is defined.

*   Implement a type marked `base` outside of the library where it is defined.

Any type that extends or mixes in a type marked `base` is implicitly treated as
if it was also marked `base` (even when the subtype is within the same library).
*This ensures that a subtype can't escape the `base` restriction of its
supertype by offering its _own_ interface that could then be implemented
without inheriting the concrete implementation from the supertype.*

A typedef can't be used to subvert these restrictions. When extending,
implementing, or mixing in a typedef, we look at the library where type the
typedef resolves to is defined to determine if the behavior is allowed. *Note
that the library where the _typedef_ is defined does not come into play.*

### Runtime semantics

There are no runtime semantics.
