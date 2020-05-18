# Abstract Fields and External Fields

Authors: lrn@google.com, eernst@google.com<br>
Version: 1.0

## Background and Motivation

Dart allows abstract instance methods, getters and setters to be declared
in classes and mixins.  It allows external functions, methods, getters, and
setters to be declared as top-level, static or instance declarations, and
it allows external constructors to be declared in classes.

The syntax of an abstract member is simply a declaration with no body.  The
syntax for an external declaration prefixes the declaration with the
modifier `external`.

Abstract declarations add members to a class interface, allowing statically
checked usage of different implementations provided in subclasses.
External declarations add members to a namespace (such as a class interface
or a library namespace), also allowing statically checked usage of
implementations that are not known statically; the declarations are
associated with implementations via an implementation specific mechanism.

A field is associated with a storage location and an implicitly induced
setter and/or getter which amounts to an implementation, so fields seem to
be inherently non-abstract and non-external. However, we can identify the
field with its accessors:

1. An "abstract instance field" can be a pair of an abstract instance
   getter and an abstract instance setter.  This can be useful, because one
   declaration replaces two declarations containing some redundant
   elements: `int get foo;s et foo(int _);`.  Developers could otherwise
   use a concrete field, `int foo;`, but this may cause a waste of space if
   someone _extends_ the class instead of implementing it, because the
   intention is to override the getter and setter, and never use the
   storage.

2. Similarly, an "external field" can be a pair of an external getter and
   an external setter.  This came up in connection with `dart:ffi`, where
   users write Dart classes in order to specify a native memory layout.
   All instances of the interface will be backed by native (external)
   code. Currently, `dart:ffi` developers use a regular field declaration,
   `int foo;`, but what is actually needed is an external setter and/or
   getter.

An abstract or external field declaration replaces a setter/getter pair or
a getter.  In the former case it helps avoid redundant specification of the
name and type, which is more concise and less error-prone.  In the latter
case the declaration may actually be more verbose (`abstract final int foo;`
vs. `int get foo;`), but it does no harm to include support for these
forms, and they may be used to maintain a specific coding style, or it may
be used by the implementation specific mechanism which is used with a
certain external field declaration,

A concrete field declaration can be made to work for both situations until
the null-safety features are introduced.  It is suboptimal, but it works.
With `dart:ffi`, domain specific rules are used to determine which fields
are "external", and how they should be connected with the relevant external
entities.

With null safety that approach no longer works.  For a field whose type
annotation is a non-nullable type, e.g., `int foo;`, it is an error unless
initialization is performed by every generative constructor, or the field
itself is modified to have an initializing expression, e.g.,
`int foo = 0;`.  This adds yet another element to the declaration which is
meaningless, confusing for readers of the code, and which may be
inconvenient to write.  It may even involve nonsensical code like
`X foo = throw 0;` (where `X` is a type variable) in the case where no
expression is statically known to evaluate to an instance with the required
type.

To provide a migration path for these use cases, we introduce _abstract and
external field declarations_.


## Feature Specification

This section specifies abstract and external variables.


### Syntax

The grammar is modified as follows:

```
<topLevelDefinition> ::=
  ... |
  // New alternative.
  'external' ('final' <type>? | <varOrType>) <identifierList> ';'

<finalVarOrType> ::= // New rule.
  'final' <type>? |
  <varOrType>

<declaration> ::=
  ... |
  // New alternative.
  'external' ('static'? <finalVarOrType> | 'covariant' <varOrType>)
      <identifierList> |
  // New alternative.
  'abstract' (<finalVarOrType> | 'covariant' <varOrType>) <identifierList>
```


### Static Analysis

The features specified in this document are syntactic sugar, that is, they
are specified in terms of a small program transformation that eliminates
them.  This fully determines the further static analysis (including errors
and warnings), and the dynamic semantics.  The transformations are as
follows:

An abstract instance variable declaration _D_ is treated as an abstract setter
declaration and/or an abstract getter declaration. The setter is included if
and only if _D_ is non-final. The return type of the getter and the parameter
type of the setter, if present, is the type of _D_ (*which may be declared
explicitly, obtained by override inference, or defaulted to `dynamic`*).  The
parameter of the setter, if present, has the modifier `covariant` if and only if
_D_ has the modifier `covariant`. _For example:_

```dart
abstract class A {
  // Abstract instance variables.
  abstract int i1, i2;
  abstract var x;
  abstract final int fi;
  abstract final fx;
  abstract covariant num cn;
  abstract covariant var cx;

  // Desugared meaning of the above.
  int get i1;
  void set i1(int _);
  int get i2;
  void set i2(int _);
  dynamic get x;
  void set x(dynamic _);
  int get fi;
  dynamic get fx;
  num get cn;
  void cn(covariant num _);
  dynamic get cx;
  void set cx(covariant dynamic _);
}
```

An external variable declaration _D_ is treated as an external setter
declaration and/or an external getter declaration.  The setter is included
if and only if _D_ is non-final. The return type of the getter and the
parameter type of the setter, if present, is the type of _D_ (*which may be
declared explicitly, obtained by override inference, or defaulted to
`dynamic`*).  The parameter of the setter, if present, has the modifier
`covariant` if and only if _D_ has the modifier `covariant` (*the grammar
only allows this modifier on external instance variables*). _For example:_

```dart
// External instance variables. PS: Covariance not supported at top level.
external int i1; // ...
external final fx;

// Desugared meaning of the above.
external int get i1;
external void set i1(int _); // ...
external dynamic get fx;

class A {
  // External instance variables.
  external int i1; // ...
  external covariant var cx;

  // Desugared meaning of external instance variables.
  external int get i1;
  external void set i1(int _); // ...
  external dynamic get cx;
  external void set cx(covariant dynamic _);

  // External static variables. PS: Covariance not supported with static.
  external static int i1; // ...
  external static final fx;

  // Desugared meaning of external static variables.
  external static int get i1;
  external static void set i1(int _); // ...
  external static dynamic get fx;
}
```

Metadata on an abstract or external variable declaration _D_ is associated
with both getter and the setter, if present, that arise by desugaring of
_D_.


### Dynamic Semantics

There are no changes to the dynamic semantics, because abstract and
external variables are eliminated by desugaring at compile time.


## Discussion

The ability to declare multiple abstract or external variables together
allows developers to avoid repeating the type and properties like `final`,
if they are identical for several declared variables.  However, it would of
course be easy to omit this feature, if it is considered detrimental to the
maintainability or readability of the code.
