// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/model.dart';
import 'package:macro_client/class_generator_macro.dart';

class ToStringMacro extends ClassGeneratorMacro {
  @override
  QualifiedName get name => QualifiedName(
      uri: 'package:test_macro_annotations/annotations.dart', name: 'ToString');

  @override
  String generateFor(Interface clazz) {
    final result = StringBuffer();

    result.writeln('augment class ${clazz.name} {');
    result.writeln("  String toString() => '''");
    result.write('${clazz.name}(');
    final fields = clazz.members.values.where((m) => m.isField).toList();
    for (final field in fields) {
      result.write('${field.name}: \$${field.name}');
      if (field != fields.last) result.write(', ');
    }
    result.writeln(")''';");
    result.writeln('}');

    return result.toString();
  }
}
