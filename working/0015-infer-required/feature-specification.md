# Infer requiredness in concrete parameter lists

Author: Erik Ernst

Status: Draft

Version 1.0 (see the [CHANGELOG](#CHANGELOG))

## Summary

This proposal is built on a large number of issues expressing the desire to
avoid writing `required` in the declaration of required named formal
parameters, when possible. This started all the way back in issue number 15
in the language repository, even before `required` was a modifier in the
language. In addition to making this point, the issues contain many
concrete ideas about how this could be turned into an actual language
feature, up to rather complete proposals. This proposal is just a
consolidation of this body of prior work.

*    [#15 Problem: Syntax for optional parameters and required named parameters is verbose and unfamiliar](https://github.com/dart-lang/language/issues/15)
*    [#878 [proposal] non-nullable named parameters required by default](https://github.com/dart-lang/language/issues/878)
*    [#938 Should NNBD type inference infer required when necessary?](https://github.com/dart-lang/language/issues/938)
*    [#1103 Replace current "@required this.name" in the named parameters with "this.name!"](https://github.com/dart-lang/language/issues/1103)
*    [#1502 Is the "required" keyword really necessary with non nullable types?](https://github.com/dart-lang/language/issues/1502)
*    [#1546 Allow a parameter to be required or not based on a generic type](https://github.com/dart-lang/language/issues/1546)
*    [#2050 remove the requirement for required on nnbd arguments](https://github.com/dart-lang/language/issues/2050)
*    [#2574 Alternative for "required" keyword](https://github.com/dart-lang/language/issues/2574)
*    [#2989 Purpose of required before named non-nullable arguments](https://github.com/dart-lang/language/issues/2989)
*    [#3206 Rethink required to be optional for non-nullable named parameters without default values](https://github.com/dart-lang/language/issues/3206)
*    [#3287 Inferring required named parameters without making function types a pitfall](https://github.com/dart-lang/language/issues/3287)

## Motivation

For brevity, it is desirable to be able to omit the rather long modifier
`required` on the declaration of a named formal parameter. Of course, the
resulting declaration should still be unambiguous, but this is indeed
possible in some cases.

This section mentions a different proposal as well, namely
[primary constructors](https://github.com/dart-lang/language/blob/main/working/2364%20-%20primary%20constructors/feature-specification.md).
The reason for this is that this proposal about eliminating `required`
turns out to be even more significant when the underlying declarations are
concise, and primary constructors will do just that.

Note that all parameters in this document are named, because the proposal
is specifically concerned with the rules about named parameters.

For example:

```dart
// Current form.

class Point {
  final int x;
  final int y;
  const Point({required this.x, required this.y});
}

// If this proposal is supported.

class Point {
  final int x;
  final int y;
  const Point({this.x, this.y});
}

// If primary constructors are supported.

class const Point({required int x, required int y}); 

// With primary constructors plus this proposal.

class const Point({int x, int y});
```

Here is a larger example (from issue 878):

```dart
// Today.

class User {
  final String id;
  final String email;
  final String userName;
  final String address;
  final String phoneNumber;
  final String name;
  final String? avatarUrl;

  User({
    required this.id,
    required this.email,
    required this.userName,
    required this.address,
    required this.phoneNumber,
    required this.name,
    this.avatarUrl,
  });
}

// With this proposal.

class User {
  final String id;
  final String email;
  final String userName;
  final String address;
  final String phoneNumber;
  final String name;
  final String? avatarUrl;

  User({
    this.id,
    this.email,
    this.userName,
    this.address,
    this.phoneNumber,
    this.name,
    this.avatarUrl,
  });
}

// With this proposal and primary constructors.

class const User({
  String id,
  String email,
  String userName,
  String address,
  String phoneNumber,
  String name,
  String? avatarUrl,
});
```

It seems likely that it will be true rather often that the required
parameters are exactly the ones whose type is non-nullable, which means
that the migration will simply be to delete every occurrence of
`required`. Of course, we aren't forced to have a migration at all, if it
is more convenient to leave code unchanged.

On the other hand, it should be noted that we can't allow every occurrence
of `required` to be inferred.

In a function type and in an abstract instance member declaration, the
modifier `required` on a formal parameter declaration is crucial: It can
be omitted, and the properties of the formal parameter will be different:

```dart
abstract class A {
  void foo({int i}); // OK.
}

void Function({int i}) fun = ({int i = 0}) {};

typedef void F({int i}); // OK.
```

For the abstract instance method `foo`, the named parameter `i` is
optional, and every implementation of the method must either specify a
default value and/or a more general nullable parameter type (which implies
that it has the default value null).

The variable `fun` must have a value which is a function object whose type
is a subtype of `void Function({int i})`.

For the function type `F`, which is the same as `void Function({int i})`,
the named parameter `i` is again optional, and values of that type must
again have a default value or a more general parameter type.

In short, in these cases the absence of the modifier `required` is already
taken to imply that the parameter is optional, and hence we cannot infer
`required` just because it is absent. Hence, `required` must always be
specified explicitly in these cases.

## Specification

### Static processing

Assume that _D_ is a declaration of a function or a concrete method with a
named, formal parameter declaration `p` that does not have the modifier
`required` and does not have a default value, and whose declared type is
potentially nullable. In this situation _D_ is transformed such that `p` is
replaced by `required p`.

This rule is applicable to `external` functions and methods, too.

### Dynamic semantics

There is no dynamic semantics of this mechanism, all behaviors are
determined by the current rules of the language applied to the program
where the compile-time transformation has taken place.

## CHANGELOG

*   Version 1.0: First public version.
