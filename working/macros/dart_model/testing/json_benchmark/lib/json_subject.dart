import 'dart:convert';
import 'dart:typed_data';

import 'subject.dart';

class JsonSubject implements Subject {
  @override
  String get name => 'JSON';

  @override
  Map<String, Object?> createData({required int libraryCount}) {
    final result = <String, Object?>{};

    for (var i = 0; i != libraryCount; ++i) {
      final packageName = 'package:json_benchmark/library$i.dart';
      result[packageName] = _createLibrary(classCount: 10);
    }

    return result;
  }

  @override
  Map<String, Object?> deepCopyIn(Map<String, Object?> data) {
    final result = <String, Object?>{};
    for (final entry in data.entries) {
      final key = entry.key;
      var value = entry.value;
      if (value is Map<String, Object?>) value = deepCopyIn(value);
      result[key] = value;
    }
    return result;
  }

  @override
  Map<String, Object?> deepCopyOut(Map<String, Object?> data) =>
      deepCopyIn(data);

  @override
  Uint8List serialize(Map<String, Object?> data) =>
      utf8.encode(json.encode(data));
  @override
  Map<String, Object?> deserialize(List<int> data) =>
      json.decode(utf8.decode(data));

  Map<String, Object?> _createLibrary({required int classCount}) {
    final result = <String, Object?>{};
    for (var i = 0; i != classCount; ++i) {
      final className = 'A$i';
      result[className] = _createClass(fieldCount: 10);
    }
    return result;
  }

  Map<String, Object?> _createClass({required int fieldCount}) {
    final result = <String, Object?>{};
    for (var i = 0; i != fieldCount; ++i) {
      final fieldName = 'f$i';
      result[fieldName] = _createField();
    }
    return result;
  }

  Map<String, Object?> _createField() {
    return {
      'type': 'int',
      'properties': {'abstract': true, 'final': true, 'static': false}
    };
  }
}
