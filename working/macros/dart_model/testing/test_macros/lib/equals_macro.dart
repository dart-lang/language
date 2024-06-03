// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/model.dart';
import 'package:macro_client/class_generator_macro.dart';

class EqualsMacro extends ClassGeneratorMacro {
  @override
  QualifiedName get name => QualifiedName(
      uri: 'package:test_macro_annotations/annotations.dart', name: 'Equals');

  @override
  String generateFor(Interface clazz) {
    final result = StringBuffer();

    result.writeln('augment class ${clazz.name} {');
    result.writeln('  bool operator==(Object other) =>');
    result.writeln('      other is ${clazz.name}');
    for (final field in clazz.members.values.where((m) => m.isField)) {
      result.writeln('    && other.${field.name} == this.${field.name}');
    }
    result.writeln(';}');

    return result.toString();
  }
}
