// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/delta.dart';
import 'package:dart_model/model.dart';
import 'package:test/test.dart';

void main() {
  group(Delta, () {
    test('describes new data as updates', () {
      final previous = Model.fromJson({'a': 'a', 'c': 'c'});
      final current = Model.fromJson({'a': 'a', 'b': 'b'});
      final delta = Delta.compute(previous, current);

      expect(delta.updates, [
        Update(path: Path(['b']), value: 'b')
      ]);
    });

    test('describes deeply nested new data as updates', () {
      final previous = Model.fromJson({
        'a': {
          'b': {'c': 'd'}
        },
      });
      final current = Model.fromJson({
        'a': {
          'b': {
            'c': {
              'd': {'e': 'f'}
            }
          }
        },
      });
      final delta = Delta.compute(previous, current);

      expect(delta.updates, [
        Update(path: Path(['a', 'b', 'c']), value: {
          'd': {'e': 'f'}
        })
      ]);
    });

    test('describes changed data as updates', () {
      final previous = Model.fromJson({'a': 'a', 'c': 'c'});
      final current = Model.fromJson({'a': 'a2', 'c': 'c'});
      final delta = Delta.compute(previous, current);

      expect(delta.updates, [
        Update(path: Path(['a']), value: 'a2')
      ]);
    });

    test('describes deeply nested changed data as updates', () {
      final previous = Model.fromJson({
        'a': {
          'b': {'c': 'a'}
        },
        'c': 'c'
      });
      final current = Model.fromJson({
        'a': {
          'b': {'c': 'a2'}
        },
        'c': 'c'
      });
      final delta = Delta.compute(previous, current);

      expect(delta.updates, [
        Update(path: Path(['a', 'b', 'c']), value: 'a2')
      ]);
    });

    test('describes removed data', () {
      final previous = Model.fromJson({'a': 'a', 'c': 'c'});
      final current = Model.fromJson({'a': 'a'});
      final delta = Delta.compute(previous, current);

      expect(delta.removals, [
        Removal(path: Path(['c']))
      ]);
    });

    test('describes deeply nested removed data', () {
      final previous = Model.fromJson({
        'a': 'a',
        'c': {
          'd': {
            'e': {'c': 'c'}
          }
        }
      });
      final current = Model.fromJson({
        'a': 'a',
        'c': {
          'd': {'e': <String, Object?>{}}
        }
      });
      final delta = Delta.compute(previous, current);

      expect(delta.removals, [
        Removal(path: Path(['c', 'd', 'e', 'c']))
      ]);
    });

    test('can handle lists', () {
      final previous = Model.fromJson({
        'a': ['a'],
      });
      final current = Model.fromJson({
        'a': ['b'],
      });
      final delta = Delta.compute(previous, current);

      expect(delta.updates, [
        Update(path: Path(['a']), value: ['b'])
      ]);
    });

    test('can be applied to a model', () {
      final previous = Model.fromJson({
        'a': 'a',
        'b': 'b',
      });
      final current = Model.fromJson({
        'a': {'b': 'c'},
        'b': {'c': 'a'},
      });
      final delta = Delta.compute(previous, current);

      expect(previous, isNot(current));
      delta.update(previous);
      expect(previous, current);
    });
  });
}
