// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:test/test.dart';

void main() {
  group(Query, () {
    test('can query by URI', () {
      final model = Model.fromJson({
        'package:dart_model/dart_model.dart': 'a',
        'package:dart_model/src/impl.dart': 'b'
      });

      final query = Query.uri('package:dart_model/dart_model.dart');
      final result = query.query(model);

      expect(
          result,
          Model.fromJson({
            'package:dart_model/dart_model.dart': 'a',
          }));
    });

    test('can query by URI and name', () {
      final model = Model.fromJson({
        'package:dart_model/dart_model.dart': {'a': 'a', 'b': 'b'},
        'package:dart_model/src/impl.dart': {'b': 'b'},
      });

      final query = Query.qualifiedName(
          uri: 'package:dart_model/dart_model.dart', name: 'a');
      final result = query.query(model);

      expect(
          result,
          Model.fromJson({
            'package:dart_model/dart_model.dart': {'a': 'a'},
          }));
    });

    test('can exclude by name', () {
      final model = Model.fromJson({
        'package:dart_model/dart_model.dart': {'a': 'a', 'b': 'b'},
        'package:dart_model/src/impl.dart': {'b': 'b'},
      });

      final query = Query(operations: [
        Operation.include([
          Path(['package:dart_model/dart_model.dart'])
        ]),
        Operation.exclude([
          Path(['*', 'b']),
        ])
      ]);

      final result = query.query(model);

      expect(
          result,
          Model.fromJson({
            'package:dart_model/dart_model.dart': {'a': 'a'},
          }));
    });
  });
}
