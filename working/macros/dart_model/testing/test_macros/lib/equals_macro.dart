// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_model/delta.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:macro_client/macro.dart';
import 'package:macro_protocol/host.dart';

class EqualsMacro implements Macro {
  final Model model = Model();

  @override
  QualifiedName get name => QualifiedName(
      uri: 'package:test_macros/equals_macro.dart', name: 'EqualsMacro');

  @override
  Future<void> start(Host host) async {
    final service = host.service;
    final stream = await service.watch(Query.annotation(QualifiedName(
      uri: 'package:test_macro_annotations/annotations.dart',
      name: 'Equals',
    )));
    stream.listen((delta) => generate(host, delta));
  }

  void generate(Host host, Delta delta) async {
    delta.update(model);

    for (final uri in delta.uris) {
      final library = model.library(uri)!;
      final result = StringBuffer();
      for (final scope in library.scopes) {
        final clazz = scope.asInterface!;
        result.write(generateFor(clazz));
      }

      unawaited(
          host.augment(macro: name, uri: uri, augmentation: result.toString()));
    }
  }

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
