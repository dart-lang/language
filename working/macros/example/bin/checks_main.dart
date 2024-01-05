@ChecksExtensions([Person])
library;

import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'package:macro_proposal/checks_extensions.dart';

void main() {
  test('can use generated extensions', () {
    final draco = Person(name: 'Draco', age: 39);
    check(draco)
      ..name.equals('Draco')
      ..age.equals(39);
  });
}

class Person {
  final String name;
  final int age;

  Person({required this.name, required this.age});
}
