# Abstract and External Field Declarations

Author: lrn@google.com<br>
Proposed solution to: https://github.com/dart-lang/language/issues/44


## Background and Motivation

Currently Dart does not have a way to declare an “abstract field” other than to declare an abstract getter/setter pair. There are situations where it would be more *convenient* (and even more *readable*) to simply declare a field (`int x;` rather than `int get x; set(int x);`), however the syntax does not allow that field to be *abstract*. 

If a class is used entirely as an *interface*, then declaring a field has worked until now. It introduces a getter and setter to the interface, and if nobody *extends* the class anyway, it doesn’t matter that it allocates space for a field.

The same issue applies to mixins, where you may want to add an abstract field to the mixin, which allows the code of mixin itself to access the field without requiring an implementation. This currently requires you to write a getter/setter pair instead.

With the Null Safety feature, that stops working for non-nullable fields. A non-nullable field *must* be initialized, which means that simply declaring a non-abstract field imposes further requirements on the class. Either the field must be initialized, `int x = 0;`, which requires an arbitrary value that is confusing to readers (and not all types even have an easily creatable dummy-value), or the field must be initialized by a constructor, and a plain interface class likely has no constructor, so it gets the default constructor which does not initialize anything. So, an interface class with an `int x;` field will stop working with Null Safety.

This has already been recognized by `dart:fii` which relies on such abstract interface classes for user defined structures. They currently consider the class concrete, only with a magical compiler-provided implementation of the field getters/setters, and those could be considered as *external* fields instead, but either way, their current interface classes stops being valid.

One reason that we don’t have abstract fields already is that the current syntax does not make it easy to do so. All abstract methods have a `;` instead of a body, but a field declaration already ends with a `;` and doesn’t need a body, so we cannot use the *same* syntax.

## Proposal

We introduce *abstract variable declarations* and *external variable declarations*.

### Abstract variables

Any *instance* variable can be declared *abstract*. This is done by prefixing the declaration with the built-in identifier `abstract`. This goes before all other keywords.

Example:

```dart
abstract class Indexable<T> {
  abstract int length; // Abstract getter and setter declaration.
  T operator[](int index);
}
```

An abstract variable declaration cannot have an initializer expression, and it cannot be `const`,  `late` or `external`. It *can* be either `covariant` and `final`, but not both. It can be preceded by metadata like any other variable declaration.

An abstract variable declaration introduces an abstract getter, and an abstract setter if the variable is not final, with the same type as the variable declaration, and the setter is covariant if the variable declaration was. As such, an abstract variable cannot be initialized by constructors, and does not need to be initialized. 

An abstract variable does not introduce a getter or setter implementation, so if the class does not inherit a concrete getter and setter implementation, the class needs to be marked as abstract.

### External variables

Any *library* (top-level), *class* (static) or *instance* variable can be declared *external*. This is done by prefixing the declaration with the built-in identifier `external`. This goes before all other keywords, including `static` for static variables.

Example:

```dart
class PointStruct extends Struct { // FFI class
  @Int32()  
  external int x;
  @Int32()  
  external int y;
}
```

An external variable declaration cannot have an initializer expression, and it cannot be `const`,  `late` or `abstract`. It *can* be `covariant` if it is an instance variable, and it can be `final`, but it cannot be both. It can be preceded by metadata like any other variable declaration.

An external variable declaration introduces an external getter, and an external setter if the variable is not final, with the same type and static-ness as the variable declaration, and the setter is covariant if the variable declaration was. An external variable cannot be initialized by constructors, and does not need to be initialized. An external variable counts as an *implementation* of the getter and setter that it introduces.

## Consequences

The proposed change to the grammar does not introduce any ambiguities. 

There are no instance members which can currently start with `abstract`, and parsers can now use `abstract` at the beginning of a member declaration to infer that what follows should be a variable declaration.

Parser may previously have been able to infer that something starting with `external` was not a variable declaration, which is no longer true. That may affect error recovery, but should not otherwise affect parsing.

The front end can convert external and abstract variable declarations to getter and setter declarations, so back-ends see nothing new. Location data for those setters and getters does need to be passed on in way which allows correct error message locations.

The DartDoc tool can treat external and abstract variable declarations like any other variable declaration. The abstractness does not affect the API.

The Dart Formatter needs to recognize the prefixes and treat them like any other prefixe (like `static` , `final` or `late`).

The proposed syntax solves the existing problems of `dart:ffi`, it supports easier writing interfaces post Null Safety, and it can also be used to more easily add "field" signatures to mixins.
