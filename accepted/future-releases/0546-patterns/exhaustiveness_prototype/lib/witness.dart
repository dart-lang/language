// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'space.dart';
import 'static_type.dart';

/// Returns `true` if [caseSpaces] exhaustively covers all possible values of
/// [valueSpace].
bool isExhaustiveNew(Space valueSpace, List<Space> caseSpaces) {
  return checkExhaustiveness(valueSpace, caseSpaces) == null;
}

/// Determines if [caseSpaces] is exhaustive over all values contained by
/// [valueSpace]. If so, returns `null`. Otherwise, returns a string describing
/// an example of one value that isn't matched by anything in [caseSpaces].
String? checkExhaustiveness(Space valueSpace, List<Space> caseSpaces) {
  var value = _spaceToPattern(valueSpace);
  var cases = caseSpaces.map((space) => [_spaceToPattern(space)]).toList();

  var witness = _unmatched(cases, [value]);

  // TODO: Uncomment this to have it print out the witness for non-exhaustive
  // matches.
  // if (witness != null) print(witness);

  return witness;
}

/// Convert the prototype's original [Space] representation to the [Pattern]
/// representation used here.
///
/// This is only a convenience to run the existing test code which creates
/// [Space]s using the new algorithm.
Pattern _spaceToPattern(Space space, [List<String> path = const []]) {
  if (space is! ExtractSpace) {
    // TODO: The old algorithm creates UnionSpaces internally but they are
    // never used directly as entrypoint arguments, so this function doesn't
    // support them.
    throw ArgumentError('Space should be an ExtractSpace.');
  }

  var fields = {
    for (var name in space.fields.keys)
      name: _spaceToPattern(space.fields[name]!, [...path, name])
  };
  return Pattern(space.type, fields, path);
}

/// Tries to find a pattern containing at least one value matched by
/// [valuePatterns] that is not matched by any of the patterns in [caseRows].
///
/// If found, returns it. This is a witness example showing that [caseRows] is
/// not exhaustive over all values in [valuePatterns]. If it returns `null`,
/// then [caseRows] exhaustively covers [valuePatterns].
String? _unmatched(List<List<Pattern>> caseRows, List<Pattern> valuePatterns,
    [List<Predicate> witnessPredicates = const []]) {
  // If there are no more columns, then we've tested all the predicates we have
  // to test.
  if (valuePatterns.isEmpty) {
    // If there are still any rows left, then it means every remaining value
    // will go to one of those rows' bodies, so we have successfully matched.
    if (caseRows.isNotEmpty) return null;

    // If we ran out of rows too, then it means [witnessPredicates] is now a
    // complete description of at least one value that slipped past all the
    // rows.
    return _witnessString(witnessPredicates);
  }

  // Look down the first column of tests.
  var valuePattern = valuePatterns[0];

  // TODO: Right now, this brute force expands all subtypes of sealed types and
  // considers them individually. It would be faster to look at the types of
  // the patterns in the first column of each row and only expand subtypes that
  // are actually tested.
  // Split the type into its sealed subtypes and consider each one separately.
  // This enables it to filter rows more effectively.
  var subtypes = _expandSealedSubtypes(valuePattern.type);
  for (var subtype in subtypes) {
    var result =
        _filterByType(subtype, caseRows, valuePatterns, witnessPredicates);

    // If we found a witness for a subtype that no rows match, then we can
    // stop. There may be others but we don't need to find more.
    if (result != null) return result;
  }

  // If we get here, no subtype yielded a witness, so we must have matched
  // everything.
  return null;
}

String? _filterByType(StaticType type, List<List<Pattern>> caseRows,
    List<Pattern> valuePatterns, List<Predicate> witnessPredicates) {
  // Extend the witness with the type we're matching.
  var extendedWitness = [
    ...witnessPredicates,
    Predicate(valuePatterns[0].path, type)
  ];

  // Discard any row that may not match by type. We only keep rows that *must*
  // match because a row that could potentially fail to match will not help us
  // prove exhaustiveness.
  var remainingRows = <List<Pattern>>[];
  for (var row in caseRows) {
    var firstPattern = row[0];

    // If the row's type is a supertype of the value pattern's type then it
    // must match.
    if (type.isSubtypeOf(firstPattern.type)) {
      remainingRows.add(row);
    }
  }

  // We have now filtered by the type test of the first column of patterns, but
  // some of those may also have field subpatterns. If so, lift those out so we
  // can recurse into them.
  var fieldNames = {
    ...valuePatterns[0].fields.keys,
    for (var row in remainingRows) ...row.first.fields.keys
  };

  // Sorting isn't necessary, but makes the behavior deterministic.
  var sorted = fieldNames.toList()..sort();

  // Remove the first column from the value list and replace it with any
  // expanded fields.
  valuePatterns = [
    ..._expandFields(sorted, valuePatterns.first),
    ...valuePatterns.skip(1)
  ];

  // Remove the first column from each row and replace it with any expanded
  // fields.
  for (var i = 0; i < remainingRows.length; i++) {
    remainingRows[i] = [
      ..._expandFields(sorted, remainingRows[i].first),
      ...remainingRows[i].skip(1)
    ];
  }

  // Proceed to the next column.
  return _unmatched(remainingRows, valuePatterns, extendedWitness);
}

/// Given a list of [fieldNames] and a [pattern], generates a list of patterns,
/// one for each named field.
///
/// When pattern contains a field with that name, extracts it into the
/// resulting list. Otherwise, the pattern doesn't care
/// about that field, so inserts a default pattern that matches all values for
/// the field.
///
/// In other words, this unpacks a set of fields so that the main algorithm can
/// add them to the worklist.
List<Pattern> _expandFields(List<String> fieldNames, Pattern pattern) {
  var result = <Pattern>[];
  for (var fieldName in fieldNames) {
    var field = pattern.fields[fieldName];
    if (field != null) {
      result.add(field);
    } else {
      // This pattern doesn't test this field, so add a pattern for the
      // field that matches all values. This way the columns stay aligned.
      result.add(Pattern(
          pattern.type.fields[fieldName]!, {}, [...pattern.path, fieldName]));
    }
  }

  return result;
}

/// Recursively expands [type] with its subtypes if its sealed.
///
/// Otherwise, just returns [type].
List<StaticType> _expandSealedSubtypes(StaticType type) {
  if (!type.isSealed) return [type];

  return {for (var subtype in type.subtypes) ..._expandSealedSubtypes(subtype)}
      .toList();
}

/// The main pattern for matching types and destructuring.
///
/// It has a type which determines the type of values it contains. The type may
/// be [StaticType.top] to indicate that it doesn't filter by type.
///
/// It may also contain zero or more named fields. The pattern then only matches
/// values where the field values are matched by the corresponding field
/// patterns.
class Pattern {
  /// The type of values the pattern matches.
  final StaticType type;

  /// Any field subpatterns the pattern matches.
  final Map<String, Pattern> fields;

  /// The path of getters that led from the original matched value to value
  /// matched by this pattern. Used to generate a human-readable witness.
  final List<String> path;

  Pattern(this.type, this.fields, this.path);
}

/// Describes a pattern that matches the value or a field accessed from it.
///
/// Used only to generate the witness description.
class Predicate {
  /// The path of getters that led from the original matched value to the value
  /// tested by this predicate.
  final List<String> path;

  /// The type this predicate tests.
  final StaticType type;

  Predicate(this.path, this.type);
}

/// Builds a human-friendly pattern-like string for the witness matched by
/// [predicates].
///
/// For example, given:
///
///     [] is U
///     ['w'] is T
///     ['w', 'x'] is B
///     ['w', 'y'] is B
///     ['z'] is T
///     ['z', 'x'] is C
///     ['z', 'y'] is B
///
/// Produces:
///
///     'U(w: T(x: B, y: B), z: T(x: C, y: B))'
String _witnessString(List<Predicate> predicates) {
  var witness = Witness();

  for (var predicate in predicates) {
    var here = witness;
    for (var field in predicate.path) {
      here = here.fields.putIfAbsent(field, () => Witness());
    }
    here.type = predicate.type;
  }

  var buffer = StringBuffer();
  witness.buildString(buffer);
  return buffer.toString();
}

/// Helper class used to turn a list of [Predicates] into a string.
class Witness {
  StaticType type = StaticType.top;
  final Map<String, Witness> fields = {};

  void buildString(StringBuffer buffer) {
    if (type != StaticType.top) {
      buffer.write(type);
    }

    if (fields.isNotEmpty) {
      buffer.write('(');
      var first = true;
      fields.forEach((name, field) {
        if (!first) buffer.write(', ');
        first = false;

        buffer.write(name);
        buffer.write(': ');
        field.buildString(buffer);
      });
      buffer.write(')');
    }
  }
}
