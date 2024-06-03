// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/model.dart';
import 'package:macro_client/class_generator_macro.dart';

class HashCodeMacro extends ClassGeneratorMacro {
  @override
  QualifiedName get name => QualifiedName(
      uri: 'package:test_macro_annotations/annotations.dart', name: 'HashCode');

  @override
  String generateFor(Interface clazz) {
    final result = StringBuffer();

    result.writeln('augment class ${clazz.name} {');
    result.writeln('  int get hashCode =>');
    final fields = clazz.members.values.where((m) => m.isField).toList();
    for (final field in fields) {
      if (field != fields.first) result.writeln('^');
      result.writeln('${field.name}.hashCode');
    }
    result.writeln(';}');

    return result.toString();
  }
}
