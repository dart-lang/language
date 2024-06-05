import 'dart:typed_data';

import 'json_buffer.dart';
import 'subject.dart';

class JsonBufferSubject implements Subject {
  @override
  String get name => 'JsonBuffer';

  @override
  Map<String, Object?> createData({required int libraryCount}) {
    final buffer = JsonBuffer(
      keys: [
        for (var i = 0; i != libraryCount; ++i)
          'package:json_benchmark/library$i.dart'
      ],
      function: (_) => _createLibrary(classCount: 10),
    );
    return buffer.asMap;
  }

  @override
  Map<String, Object?> deepCopyIn(Map<String, Object?> data) {
    return _deepCopyIn(data).asMap;
  }

  JsonBuffer _deepCopyIn(Map<String, Object?> data) {
    return JsonBuffer(
        keys: data.keys,
        function: (key) {
          final value = data[key];
          if (value is Map<String, Object?>) {
            return _deepCopyIn(value);
          } else {
            return value;
          }
        });
  }

  @override
  Map<String, Object?> deepCopyOut(Map<String, Object?> data) {
    final result = <String, Object?>{};
    for (final entry in data.entries) {
      final key = entry.key;
      var value = entry.value;
      if (value is Map<String, Object?>) value = deepCopyOut(value);
      result[key] = value;
    }
    return result;
  }

  @override
  Uint8List serialize(Map<String, Object?> data) =>
      (data as JsonBufferMap).serialize();

  @override
  Map<String, Object?> deserialize(Uint8List data) =>
      JsonBuffer.deserialize(data).asMap;

  JsonBuffer _createLibrary({required int classCount}) {
    return JsonBuffer(
        keys: [for (var i = 0; i != classCount; ++i) 'A$i'],
        function: (_) => _createClass(fieldCount: 10));
  }

  JsonBuffer _createClass({required int fieldCount}) {
    return JsonBuffer(
        keys: [for (var i = 0; i != fieldCount; ++i) 'f$i'],
        function: (_) => _createField());
  }

  JsonBuffer _createField() {
    return JsonBuffer(
        keys: ['type', 'properties'],
        function: (key) {
          switch (key) {
            case 'type':
              return 'int';
            case 'properties':
              return JsonBuffer(
                  keys: ['abstract', 'static', 'final'],
                  function: (key) {
                    switch (key) {
                      case 'abstract':
                        return true;
                      case 'final':
                        return false;
                      case 'static':
                        return false;
                      default:
                        throw StateError(key);
                    }
                  });
            default:
              throw StateError(key);
          }
        });
  }
}
