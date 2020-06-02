# External Variable Declarations and Abstract Variable Declarations

Authors: lrn@google.com, eernst@google.com<br>
Version: 1.1

## Background and Motivation

Dart allows abstract instance methods, getters and setters to be declared
in classes and mixins. It allows external functions, methods, getters, and
setters to be declared as top-level, static or instance declarations, and
it allows external constructors to be declared in classes.

Abstract declarations add members to a class interface, allowing statically
checked usage of different implementations provided in subclasses.
External declarations add members to a namespace (such as a class interface
or a library namespace), also allowing statically checked usage of
implementations that are not known statically; the declarations are
associated with implementations via an implementation specific mechanism.

Dart does not allow variables of any kind to be abstract or external. This
may seem obvious because variables are either storage locations (locals) or
a combination of a storage location and an implicitly induced getter and
possibly setter (all non-local variables), so they always have an
implementation.

However, the need for an abstract or external getter and possibly setter
may arise, and a non-local variable declaration is a concise and
non-redundant way to specify the desired signatures.

This need came up in connection with `dart:ffi`, where users write Dart
classes in order to specify a native memory layout. All instances of the
interface will be backed by native (external) code. Currently, `dart:ffi`
developers use a regular instance variable declaration, like `int foo;`,
and add metadata to this declaration in order to specify the corresponding
foreign language representation.

What is actually needed is an external getter and possible setter, but if
`dart:ffi` commits to using that then there will be a large amount of
client code that declares getter/setter pairs with a non-trivial amount of
redundancy: The name is specified twice, the type is specified twice, and
there might be a need for two copies of metadata specifying the native
representation. So `dart:ffi` uses regular instance variable declarations
today.

Similarly, a class can of course declare an abstract getter/setter pair if
needed, but this again causes the name and type to be specified twice.

As a workaround, it is possible to use a concrete instance variable as a
replacement for an abstract getter and possibly setter, by simply ignoring
the implementation. The concrete variable declaration will add the
implicitly induced getter and possible setter to the interface of the
enclosing class (let us call it `C`). Any concrete subtypes (`class D
implements C ..`) will be required to implement said accessors. So far, it
just works.

However, if `D` is a _subclass_ of `C` then `D` is not required to
implement the accessors. Instead, `D` tacity inherits the implementation of
the concrete variable. This may be a bug, because `C` is designed for having
these accessors overridden to do specific things that the concrete variable
will not do. Also, if `D` _does_ override the accessors with a getter and
setter as intended, the storage reserved for the concrete instance variable
will be a space leak (it is unused).

Finally, if null-safety is enabled then a concrete instance variable
declaration (say, `int foo;`) is a compile-time error if the type of the
variable is non-nullable, unless the variable is initialized in the
initializer list of each generative constructor of the class. This problem
arises both in connection with `dart:ffi` and for a an instance variable
which is used as a replacement for an abstract getter and possibly setter.

So the existing workaround of using a concrete instance variable to emulate
an abstract instance variable is inconvenient, error prone, and confusing
for a reader of the code, and for a writer of a subclass, and similar
problems exist when a regular variable is used as a replacement for an
external getter and possibly setter.


## Design Idea

In response to the issues above, this document introduces abstract and
external variables.

The basic idea is that an abstract variable is syntactic sugar for an
abstract getter and possibly an abstract setter, and similarly for an
external variable, in both cases such that there is no storage and no
implementation of the getter and possible setter, and they have the same
signatures as the ones that would be induced implicitly by a concrete
variable declaration.

The next section is the normative text that specifies the syntax and
semantics that realize this idea.


## Feature Specification

An _abstract instance variable declaration_ is an instance variable
declaration prefixed by the modifier `abstract`. It must not be late, and
it cannot have an initializer expression.

An _external variable declaration_ is a non-local, non-parameter variable
declaration prefixed by the modifier `external`. It must not be abstract,
const, or late, and it cannot have an initializer expression.

The syntax and behavior of these constructs is specified in the following
sections.


### Syntax

The grammar is modified as follows:

```
<topLevelDefinition> ::=
  ... |
  // New alternative.
  'external' <finalVarOrType> <identifierList> ';'

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
them. This fully determines the further static analysis (including errors
and warnings), and the dynamic semantics. The transformations are as
follows:

An abstract instance variable declaration _D_ is treated as an abstract
getter declaration and possibly an abstract setter declaration. The setter
is included if and only if _D_ is non-final. The return type of the getter
and the parameter type of the setter, if present, is the type of _D_
(*which may be declared explicitly, obtained by override inference, or
defaulted to `dynamic`*). The parameter of the setter, if present, has the
modifier `covariant` if and only if _D_ has the modifier `covariant`. _For
example:_

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

An external variable declaration _D_ is treated as an external getter
declaration and possibly an external setter declaration. The setter is
included if and only if _D_ is non-final. The return type of the getter and
the parameter type of the setter, if present, is the type of _D_ (*which
may be declared explicitly, obtained by override inference, or defaulted to
`dynamic`*). The parameter of the setter, if present, has the modifier
`covariant` if and only if _D_ has the modifier `covariant` (*the grammar
only allows this modifier on external instance variables*). _For example:_

```dart
// External top level variables. PS: Covariance not supported at top level.
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
with both the getter and the setter, if present, that arise by desugaring
of _D_.


### Dynamic Semantics

There are no changes to the dynamic semantics, because abstract and
external variables are eliminated by desugaring at compile time.


## Discussion

It could be claimed that `final` should not be supported, because this
feature is motivated by the ability to express certain declarations more
concisely than their desugared meaning, and `abstract final int i;` is
actually longer than the desugared form `int get i;`. However, the ability
to declare multiple abstract or external variables together allows
developers to avoid repeating the type and properties (including `final`),
if they are identical for several declared variables.

Similarly, even in the case where the long modifier `external` makes a
declaration just as verbose as its desugared form, the ability to avoid
duplication of the name and type and metadata may be an improvement in
terms of the code maintainability.
