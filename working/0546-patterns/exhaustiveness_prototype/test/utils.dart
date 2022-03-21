// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:exhaustiveness_prototype/exhaustive.dart';
import 'package:exhaustiveness_prototype/space.dart';
import 'package:exhaustiveness_prototype/static_type.dart';
import 'package:test/test.dart';

Map<String, Space> fieldsToSpace(Map<String, Object> fields) =>
    fields.map((key, value) => MapEntry(key, parseSpace(value)));

/// Make a [Space] with [type] and [fields].
Space ty(StaticType type, Map<String, Object> fields) =>
    Space(type, fieldsToSpace(fields));

/// Make a record space with the given fields.
Space rec({Object? w, Object? x, Object? y, Object? z}) => Space.record({
  if (w != null) 'w': parseSpace(w),
  if (x != null) 'x': parseSpace(x),
  if (y != null) 'y': parseSpace(y),
  if (z != null) 'z': parseSpace(z)
});

/// Parse a list of spaces using [parseSpace].
List<Space> parseSpaces(List<Object> objects) =>
    objects.map(parseSpace).toList();

Space parseSpace(Object object) {
  if (object is Space) return object;
  if (object == '∅') return Space.empty;
  if (object is StaticType) return Space(object);
  if (object is List<Object>) {
    return Space.union(object.map(parseSpace).toList());
  }
  if (object is Map<String, Object>) {
    return Space.record(fieldsToSpace(object));
  }

  throw ArgumentError('Invalid space $object');
}

/// Test that [spaces] is exhaustive over [value].
void expectExhaustive(Space value, List<Space> spaces) {
  _expectExhaustive(value, spaces, true);
}

/// Test that [spaces] is not exhaustive over [value].
void expectNotExhaustive(Space value, List<Space> spaces) {
  _expectExhaustive(value, spaces, false);
}

void _expectExhaustive(Space value, List<Space> spaces, bool expectation) {
  test(
      '$value - ${spaces.join(' - ')} ${expectation ? 'is' : 'is not'} '
      'exhaustive', () {
    _checkExhaustive(value, spaces, expectation);
  });
}

/// Test that [cases] are exhaustive over [type] if and only if all cases are
/// included and that all subsets of the cases are not exhaustive.
void expectExhaustiveOnlyAll(StaticType type, List<Object> cases) {
  _testCases(type, cases, true);
}

/// Test that [cases] are not exhaustive over [type]. Also test that omitting
/// each case is still not exhaustive.
void expectNeverExhaustive(StaticType type, List<Object> cases) {
  _testCases(type, cases, false);
}

/// Test that [cases] are not exhaustive over [type].
void _testCases(StaticType type, List<Object> cases, bool expectation) {
  var valueSpace = Space(type);
  var spaces = parseSpaces(cases);

  test('$type with all cases', () {
    _checkExhaustive(valueSpace, spaces, expectation);
  });

  // With any single case removed, should also not be exhaustive.
  for (var i = 0; i < spaces.length; i++) {
    var filtered = spaces.toList();
    filtered.removeAt(i);

    test('$type without case ${spaces[i]}', () {
      _checkExhaustive(valueSpace, filtered, false);
    });
  }
}

void _checkExhaustive(Space value, List<Space> spaces, bool expectation) {
  var actual = isExhaustive(value, spaces);
  if (expectation != actual) {
    if (expectation) {
      fail('Expected $spaces to cover $value but did not.');
    } else {
      fail('Expected $spaces to not cover $value but did.');
    }
  }
}
