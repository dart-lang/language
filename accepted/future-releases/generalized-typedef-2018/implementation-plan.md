# Implementation Plan for the Q1 2019 Generalized Type Alias Feature

Relevant documents:
 - [Tracking issue](https://github.com/dart-lang/language/issues/115)
 - [Feature specification](https://github.com/dart-lang/language/blob/master/accepted/future-releases/generalized-typedef-2018/feature-specification.md)

## Implementation and Release plan

This feature is non-breaking, because it is concerned with the introduction of
support for new syntactic forms. 
Hence, there is no `--enable-experiment` flag for it.

### Phase 0 (Preliminaries)

#### Tests

The language team adds a set of tests for the new feature, in terms of
declarations and usages in the following situations:

- A type alias with and without type arguments is used
  - as a type annotation for a variable of various kinds.
  - as a type argument of a class or another type alias.
  - as part of a function type.
  - in a function declaration as return type or parameter type.
  - as an expression.
  - as the type in an `on` clause.
  - in a type test (`is`).
  - in a type cast (`as`).
- A type alias whose body is a class with or without type arguments, is used in
  - the `extends` clause of a class.
  - the `with` clause of a class.
  - the `implements` clause of a class or mixin.
  - the `on` clause of a mixin.
  - instance creation expressions, constant and non-constant.
  - an invocation of a static method, getter, setter, and a tear-off of a
    static method; note that the provision of type arguments
    (`F<int>.m()`) is an error here.

The co19 team start creating tests early, such that those tests can be
used during implementation as well.

### Phase 1 (Implementation)

All tools implement syntactic support for type aliases of the form

```dart
typedef F<TypeArguments> = type;
```

where `type` can be any type, rather than just a function type.

All tools implement support for using such type aliases, in all situations
mentioned under phase 0.

### Phase 2 (Release)

The feature is released as part of the next stable Dart release.

## Timeline

Completion goals for the phases:

- Phase 0: (TODO)
- Phase 1: (TODO)
- Phase 2: (TODO)
