# Partial classes

Author: kevmoo@google.com

Proposed solution to [partial classes (#252)](https://github.com/dart-lang/language/issues/252).
Discussion about this proposal should go in [Issue #678](https://github.com/dart-lang/language/issues/678).

## Motivation

A critical use of code generation is adding boilerplate to hand-written classes.

An ideal solution would provide:

- Strict separation between human- and computer-generated code.
- Allow computer-generated code to add members (functions, fields, properties,
  constructors, etc) to human-generated code directly – without requiring
  subclasses, mix-ins, or manually connecting generated private members with user-created public members.
  - The user will still have to provide "stubs" for these members to enable
    static analysis.
- Allow user-created "stubs" to be filled in by generated code. This allows
  a number of static-analysis and tooling scenarios to work without the code
  being generated first.

## json_serializable before/after example

Here's a motivating example with a speculative future implementation for
[json_serializable](https://pub.dev/packages/json_serializable).

### Before (current behavior)

```dart
// before: User-generated code
import 'package:json_annotation/json_annotation.dart';

part 'example.g.dart';

@JsonSerializable(nullable: false)
class Person {
  final String firstName;
  final String lastName;
  final DateTime dateOfBirth;
  Person({this.firstName, this.lastName, this.dateOfBirth});

  // User needs to connect machine-generated factory. Cannot be a constructor.
  factory Person.fromJson(Map<String, dynamic> json) => _$PersonFromJson(json);

  // User needs to connect machine-generated function.
  Map<String, dynamic> toJson() => _$PersonToJson(this);
}
```

```dart
// before: machine-generated
part of 'example.dart';

// Machine-generated code dirties up the private namespace of the user library
// with specially named private functions
Person _$PersonFromJson(Map<String, dynamic> json) {
  return Person(
    firstName: json['firstName'] as String,
    lastName: json['lastName'] as String,
    dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
  );
}

Map<String, dynamic> _$PersonToJson(Person instance) => <String, dynamic>{
      'firstName': instance.firstName,
      'lastName': instance.lastName,
      'dateOfBirth': instance.dateOfBirth.toIso8601String(),
    };
```

### After (possible future)

```dart
// after: User-generated code
import 'package:json_annotation/json_annotation.dart';

part 'example.g.dart';

@JsonSerializable(nullable: false)
class Person partial {
  final String firstName;
  final String lastName;
  final DateTime dateOfBirth;
  Person({this.firstName, this.lastName, this.dateOfBirth});

  // These stubs ensure the shape of the type is fully visible before code
  // generation to enable static analysis. The stubs can also be available
  // in the analyzer API allow code generation to use them. For instance:
  // json_serializable could drop the explicit annotations to enable/disable
  // factory and/or toJson members and instead just key off the existence of
  // the corresponding stubs.
  partial factory Person.fromJson(Map<String, dynamic json>);
  partial Map<String, dynamic> toJson();
}
```

```dart
// after: machine-generated
part of 'example.dart';

class Person partial {
  // Note: instead of a factory constructor, a "normal" constructor could be
  // generated that simply populates the fields!
  factory Person.fromJson(Map<String, dynamic> json) =>
    Person(
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
    );

  Map<String, dynamic> toJson() => <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'dateOfBirth': dateOfBirth.toIso8601String(),
    };
}
```

## Design ideas

### Legal to define the same type multiple times in the same library

The following would be legal:

```dart
class Person partial {}
class Person partial {}
class Person partial {}
```

...and would be treated as

```dart
class Person {}
```

> Why not restrict it to one-definition-per-file? It's common for code
generators to create one file with the output from several separate generators.

### Class hierarchy and members are merged across partial classes

The following would be legal:

```dart
class Person extends A<int> partial {
  final int field;
  Person(this.field);
}

class Person implements B<String> partial {}
```

...and would be treated as

```dart
class Person extends A<int> implements B<String>{
  final int field;
  Person(this.field);
}
```

- Things that are currently not allowed (such as extending more than one type)
  are still illegal. Implementing multiple interfaces, though, is fine –
  as long as the interfaces are compatible.

### Defining member "stubs"

The following would be legal:

```dart
// User-defined class
class Person {
  // Reusing `external` keyword here. Not sure if we can/want to add another
  // keyword. We don't want this to "look" abstract.
  external int get value;
}

// Machine-generated class
class Person {
  int get value => 42;
}
```

...and would be treated as

```dart
class Person {
  int get value => 42;
}
```

- The "shape" of `Person` is now visible to static analysis tools even before
  code generation is ran.

### Open questions

* Do we want a `partial` keyword or similar?

## Existing Dart code-generation tools that could leverage Partial Classes

- [json_serializable](https://pub.dev/packages/json_serializable)
- [built_value](https://pub.dev/packages/built_value)

## Implementations in other languages

- C# - https://docs.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/partial-classes-and-methods
