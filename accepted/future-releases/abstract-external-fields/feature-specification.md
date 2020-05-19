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

However, variables do not seem to be compatible with these modifiers. A
variable is associated with a storage location and an implicitly induced
setter and/or getter. This amounts to an implementation, so variables seem
to be inherently non-abstract and non-external.

However, we may focus on the implicitly induced setter and/or getter for a
given instance variable declaration, in which case it is simply considered
to be a more concise notation for said accessors. The point is that the
getter and/or setter is added to the class interface, and they are intended
to be implemented by subtypes.

As a workaround, it is possible to use a concrete instance variable as an
"abstract instance variable" by simply ignoring the implementation. The
concrete variable declaration will add the implicitly induced setter and/or
getter to the interface of the enclosing class (let us call it `C`). Any
concrete subtypes (`class D implements C ..`) will be required to implement
said accessors.

However, _subclasses_ of `C` will not be required to implement the
accessors, they will tacity inherit the implementation of the concrete
field, which may be a bug. Also, if the subclasses of `C` _do_ implement
the accessors, the storage reserved for the concrete variable will be a
space leak (it's simply unused).

Finally, if null-safety is enabled then a concrete instance variable
declaration (say, `int foo;`) is a compile-time error if the type of the
variable is non-nullable, unless the variable is initialized in the
initializer list of each generative constructor of the class.

So the existing workaround of using a concrete instance variable to emulate
an abstract instance variable is inconvenient, error prone, and confusing
for a reader of the code, and for a writer of a subclass.

A similar perspective can be used as a foundation for the notion of an
"external variable". We focus on the implicitly induced setter and/or
getter for a given variable declaration, and the external variable
declaration is thus simply a concise notation for said accessors.

The need for such accessors came up in connection with `dart:ffi`, where
users write Dart classes in order to specify a native memory layout. All
instances of the interface will be backed by native (external)
code. Currently, `dart:ffi` developers use a regular field declaration,
like `int foo;`, and add metadata to this declaration in order to specify
the corresponding foreign language representation. But what is actually
needed is an external setter and/or getter.

It is of course possible to declare an external setter and/or getter
directly. However, this gives rise to duplicate code elements (the name and
type and metadata may need to be written twice, and they must be kept
consistent when the code is maintained). This means that the ability to
declare an external variable and avoid this duplication is useful, in a
similar way as for the abstract instance variables.


## Feature Specification

In response to the above motivation, we introduce _external variable
dclarations_ and _abstract variable declarations_, which are syntactic
sugar for the implicitly induced accessors of similar, concrete variable
declarations, carrying over the property of being abstract or external.


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
them. This fully determines the further static analysis (including errors
and warnings), and the dynamic semantics. The transformations are as
follows:

An abstract instance variable declaration _D_ is treated as an abstract setter
declaration and/or an abstract getter declaration. The setter is included if
and only if _D_ is non-final. The return type of the getter and the parameter
type of the setter, if present, is the type of _D_ (*which may be declared
explicitly, obtained by override inference, or defaulted to `dynamic`*). The
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
declaration and/or an external getter declaration. The setter is included
if and only if _D_ is non-final. The return type of the getter and the
parameter type of the setter, if present, is the type of _D_ (*which may be
declared explicitly, obtained by override inference, or defaulted to
`dynamic`*). The parameter of the setter, if present, has the modifier
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
