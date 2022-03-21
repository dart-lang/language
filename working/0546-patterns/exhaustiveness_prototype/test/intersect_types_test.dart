// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:exhaustiveness_prototype/intersect.dart';
import 'package:exhaustiveness_prototype/static_type.dart';
import 'package:test/test.dart';

void main() {
  test('hierarchy', () {
    //   (A)
    //   /|\
    //  B C(D)
    //     / \
    //    E   F
    var a = StaticType('A', isSealed: true);
    var b = StaticType('B', inherits: [a]);
    var c = StaticType('C', inherits: [a]);
    var d = StaticType('D', isSealed: true, inherits: [a]);
    var e = StaticType('E', inherits: [d]);
    var f = StaticType('F', inherits: [d]);

    expectIntersect(a, a, a);
    expectIntersect(a, b, b);
    expectIntersect(a, c, c);
    expectIntersect(a, d, d);
    expectIntersect(a, e, e);
    expectIntersect(a, f, f);

    expectIntersect(b, b, b);
    expectIntersect(b, c, null);
    expectIntersect(b, d, null);
    expectIntersect(b, e, null);
    expectIntersect(b, f, null);

    expectIntersect(c, c, c);
    expectIntersect(c, d, null);
    expectIntersect(c, e, null);
    expectIntersect(c, f, null);

    expectIntersect(d, d, d);
    expectIntersect(d, e, e);
    expectIntersect(d, f, f);

    expectIntersect(e, e, e);
    expectIntersect(e, f, null);
  });

  test('sealed with multiple paths', () {
    //     (A)
    //     / \
    //   (B)  C
    //   / \ /
    //  D   E
    var a = StaticType('A', isSealed: true);
    var b = StaticType('B', isSealed: true, inherits: [a]);
    var c = StaticType('C', inherits: [a]);
    var d = StaticType('D', inherits: [b]);
    var e = StaticType('E', inherits: [b, c]);

    expectIntersect(a, a, a);
    expectIntersect(a, b, b);
    expectIntersect(a, c, c);
    expectIntersect(a, d, d);
    expectIntersect(a, e, e);
    expectIntersect(b, b, b);
    expectIntersect(b, c, null);
    expectIntersect(b, d, d);
    expectIntersect(b, e, e);
    expectIntersect(c, c, c);
    expectIntersect(c, d, null);
    expectIntersect(c, e, e);
    expectIntersect(d, d, d);
    expectIntersect(d, e, null);
    expectIntersect(e, e, e);
  });
}

void expectIntersect(StaticType left, StaticType right, StaticType? expected) {
  // Intersection is symmetric so try both directions.
  expect(intersectTypes(left, right), expected);
  expect(intersectTypes(right, left), expected);
}
