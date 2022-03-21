// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:exhaustiveness_prototype/intersect.dart';
import 'package:exhaustiveness_prototype/static_type.dart';

import 'space.dart';

/// Returns a new [Space] that contains all of the values of [left] that are
/// not also in [right].
Space subtract(Space left, Space right) {
  // Subtracting from empty is still empty.
  if (left == Space.empty) return Space.empty;

  // Subtracting nothing leaves it unchanged.
  if (right == Space.empty) return left;

  // Distribute a union on the left.
  // A|B - x => A-x | B-x
  if (left is UnionSpace) {
    return Space.union(left.arms.map((arm) => subtract(arm, right)).toList());
  }

  // Distribute a union on the right.
  // x - A|B => x - A - B
  if (right is UnionSpace) {
    var result = left;
    for (var arm in right.arms) {
      result = subtract(result, arm);
    }
    return result;
  }

  // Otherwise, it must be two extract spaces.
  return _subtractExtract(left as ExtractSpace, right as ExtractSpace);
}

/// Subtract [right] from [left].
Space _subtractExtract(ExtractSpace left, ExtractSpace right) {
  var fieldNames = {...left.fields.keys, ...right.fields.keys}.toList();

  var spaces = <Space>[];

  // If the left type is in a sealed hierarchy, expanding it to its subtypes
  // might let us calculate the subtraction more precisely.
  var subtypes = expandType(left.type, right.type);
  for (var subtype in subtypes) {
    spaces.addAll(_subtractExtractAtType(subtype, left, right, fieldNames));
  }

  return Space.union(spaces);
}

/// Subtract [right] from [left], but using [type] for left's type, which may
/// be a more specific subtype of [left]'s own type is a sealed supertype.
List<Space> _subtractExtractAtType(StaticType type, ExtractSpace left,
    ExtractSpace right, List<String> fieldNames) {
  // If the right type doesn't cover the left (even after expanding sealed
  // types), then we can't do anything with the fields since they may not
  // even come into play for all values. Subtract nothing from this subtype
  // and keep all of the current fields.
  if (!type.isSubtypeOf(right.type)) return [Space(type, left.fields)];

  // If any pair of fields have no overlapping values, then no overall value
  // that matches the left space will also match the right space. So the right
  // space doesn't subtract anything and we keep the left space as-is.
  for (var name in fieldNames) {
    var leftField = left.fields[name];
    var rightField = right.fields[name];

    if (leftField != null &&
        rightField != null &&
        intersect(leftField, rightField) == Space.empty) {
      return [Space(type, left.fields)];
    }
  }

  // If all the right's fields strictly cover all of the left's, then the
  // right completely subtracts this type and nothing remains.
  if (_isLeftSubspace(type, fieldNames, left.fields, right.fields)) {
    return const [];
  }

  // The right side is a supertype but its fields don't totally cover, so
  // handle each of them individually. This is equation 8.3 but more complex
  // to handle the fact that records may choose to match arbitrary subsets of
  // the available fields.

  // Walk the fields and see which ones are modified by the right-hand fields.
  var fixed = <String, Space>{};
  var changedLeft = <String, Space>{};
  var changedDifference = <String, Space>{};
  for (var name in fieldNames) {
    var leftField = left.fields[name];
    var rightField = right.fields[name];

    // To subtract a right field, we need a baseline left field to compare
    // it to. If there isn't one, infer a left field that matches all values
    // of its type.
    leftField ??= Space(type.fields[name]!);

    if (rightField == null) {
      // If we have a left field that constrains but aren't subtracting
      // anything from it, just keep the constraint.
      fixed[name] = leftField;
    } else {
      var difference = subtract(leftField, rightField);
      if (difference == Space.empty) {
        // TODO: This comment isn't right.
        // The left and right fields don't overlap, so there's no need to
        // consider this empty case since it will match nothing.
        fixed[name] = leftField;
      } else if (difference.isTop) {
        // Don't bother keeping a field that matches everything.
        // TODO: When does this get reached?
      } else {
        changedLeft[name] = leftField;
        changedDifference[name] = difference;
      }
    }
  }

  // If no fields are affected by the subtraction, just return a single arm
  // with all of the fields.
  if (changedLeft.isEmpty) return [Space(type, fixed)];

  // For each field whose `left - right` is different, include an arm that
  // includes that one difference.
  var changedFields = changedLeft.keys.toList();
  var spaces = <Space>[];
  for (var i = 0; i < changedFields.length; i++) {
    var fields = {...fixed};

    for (var j = 0; j < changedFields.length; j++) {
      var name = changedFields[j];
      if (i == j) {
        fields[name] = changedDifference[name]!;
      } else {
        fields[name] = changedLeft[name]!;
      }
    }

    spaces.add(Space(type, fields));
  }

  return spaces;
}

/// Returns `true` if every field in [leftFields] is covered by the
/// corresponding field in [rightFields].
bool _isLeftSubspace(StaticType leftType, List<String> fieldNames,
    Map<String, Space> leftFields, Map<String, Space> rightFields) {
  // 8.1: If this type is a subtype of the right type, and all of the fields
  // on the left are covered by the fields on the right, then the right hand
  // space covers the left space entirely.
  for (var name in fieldNames) {
    var leftField = leftFields[name];
    var rightField = rightFields[name];

    // If there is no right field, it definitely covers all values matched
    // by the left field.
    if (rightField == null) continue;

    // If there is no left field, infer it from the type on the left. This is
    // safe to do because we know the left type is a subtype of the right and
    // thus the field will exist.
    leftField ??= Space(leftType.fields[name]!);

    if (subtract(leftField, rightField) != Space.empty) return false;
  }

  // If we get here, every field covered.
  return true;
}

/// Recursively replaces [left] with a union of its sealed subtypes as long as
/// doing so enables it to more precisely match against [right].
List<StaticType> expandType(StaticType left, StaticType right) {
  // If we've reached the type, stop.
  if (left.isSubtypeOf(right)) return [left];

  if (!left.isSealed) return [left];

  // If expanding left into its subtypes won't get closer to right, then don't.
  if (!right.isSubtypeOf(left)) return [left];

  // If we remove the restriction that a type can only be a direct subtype of
  // one sealed supertype, then the above check needs to be smarter. Consider:
  //     (A)
  //     / \
  //   (B) (C)
  //   / \ / \
  //  D   E   F
  //
  // Here, `expandType(B, F)` should return [D, E, F] because even though B and
  // F aren't supertypes of each other, they have a shared supertype in a sealed
  // family.

  // Expand [left] recursively to reach down to right.
  return {
    for (var subtype in left.subtypes) ...expandType(subtype, right),
  }.toList();
}
