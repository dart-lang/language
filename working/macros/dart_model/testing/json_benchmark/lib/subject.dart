import 'dart:typed_data';

abstract class Subject {
  String get name;

  Map<String, Object?> createData({required int libraryCount});

  Map<String, Object?> deepCopyIn(Map<String, Object?> data);

  Map<String, Object?> deepCopyOut(Map<String, Object?> data);

  Uint8List serialize(Map<String, Object?> data);
  Map<String, Object?> deserialize(Uint8List data);
}
