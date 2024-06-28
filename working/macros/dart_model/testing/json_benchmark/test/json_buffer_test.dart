// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_benchmark/json_buffer.dart';
import 'package:test/test.dart';

void main() {
  group(JsonBuffer, () {
    test('map with string values', () {
      final buffer = JsonBuffer(
          keys: ['a', 'aa', 'bbb'], function: (key) => key.length.toString());

      expect(buffer.asMap.keys, ['a', 'aa', 'bbb']);
      expect(buffer.asMap, {'a': '1', 'aa': '2', 'bbb': '3'});
    });

    test('map with bool values', () {
      final buffer =
          JsonBuffer(keys: ['a', 'aa', 'bbb'], function: (key) => key == 'aa');

      expect(buffer.asMap.keys, ['a', 'aa', 'bbb']);
      expect(buffer.asMap, {'a': false, 'aa': true, 'bbb': false});
    });

    test('map with map values', () {
      final buffer = JsonBuffer(
          keys: ['a', 'aa', 'bbb'],
          function: (key) => JsonBuffer(
              keys: ['${key}1', '${key}2'],
              function: (key) => key.substring(key.length - 1)));

      expect(buffer.asMap.keys, ['a', 'aa', 'bbb']);
      expect(buffer.asMap, {
        'a': {'a1': '1', 'a2': '2'},
        'aa': {'aa1': '1', 'aa2': '2'},
        'bbb': {'bbb1': '1', 'bbb2': '2'},
      });
    });

    test('serialization round trip', () {
      final buffer = JsonBuffer(
          keys: ['a', 'aa', 'bbb'],
          function: (key) => JsonBuffer(
              keys: ['${key}1', '${key}2'],
              function: (key) => key.substring(key.length - 1)));

      final roundTripBuffer = JsonBuffer.deserialize(buffer.serialize());
      expect(roundTripBuffer.asMap, buffer.asMap);
    });

    test('serialization round trip large map', () {
      final buffer = JsonBuffer(
          keys: List.generate(1000000, (i) => i.toString()),
          function: (key) => key.toString());

      final roundTripBuffer = JsonBuffer.deserialize(buffer.serialize());
      expect(roundTripBuffer.asMap.keys.length, 1000000);

      // Don't use `expect` to compare for equality as it's quadratic in `Map`
      // size.
      expect(roundTripBuffer.asMap.keys.toList(), buffer.asMap.keys.toList());
      expect(
          roundTripBuffer.asMap.values.toList(), buffer.asMap.values.toList());
    });
  });
}
