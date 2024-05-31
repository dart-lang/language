// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:macro_client/macro.dart';
import 'package:macro_protocol/host.dart';
import 'package:macro_protocol/message.dart';

class HashCodeMacro implements Macro {
  final Model model = Model();

  @override
  QualifiedName get name => QualifiedName(
      uri: 'package:test_macros/hash_code_macro.dart', name: 'HashCodeMacro');

  @override
  Future<void> start(Host host) async {
    final stream = await host.watch(Query.annotation(QualifiedName(
      uri: 'package:test_macro_annotations/annotations.dart',
      name: 'HashCode',
    )));
    stream.listen((round) => generate(host, round));
  }

  void generate(Host host, Round round) async {
    final delta = round.delta;
    delta.update(model);

    final augmentationsByUri = <String, String>{};
    for (final uri in delta.uris) {
      final library = model.library(uri)!;
      final result = StringBuffer();
      for (final scope in library.scopes) {
        final clazz = scope.asInterface!;
        result.write(generateFor(clazz));
      }

      augmentationsByUri[uri] = result.toString();
    }

    unawaited(host.augment(
        macro: name,
        round: round.round,
        augmentationsByUri: augmentationsByUri));
  }

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
