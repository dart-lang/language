import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

typedef Pointer = int;

enum Type {
  string,
  bool,
  map,
}

final typeSize = 1;
final intSize = 4;

class JsonBuffer {
  List<String>? _keys;
  Object? Function(String)? _function;
  final Map<String, Pointer> _seenStrings = {};
  final Map<Pointer, String> _decodedStrings = {};

  Uint8List _buffer = Uint8List(1024);
  int _nextFree = 0;

  // TODO: add a keyFunction like the Map constructor.
  JsonBuffer(
      {required Iterable<String> keys,
      required Object? Function(String) function})
      : _keys = keys.toList(),
        _function = function;

  JsonBuffer.deserialize(this._buffer)
      : _keys = null,
        _function = null,
        _nextFree = _buffer.length;

  Uint8List serialize() {
    _evaluate();
    return _buffer.sublist(0, _nextFree);
  }

  void _evaluate() {
    if (_keys != null) {
      _add(_keys!, _function!);
      _keys = null;
      _function = null;
    }
  }

  void _add(Iterable<String> keys, Object? Function(String) function) {
    final keysList = keys.toList();
    final length = keysList.length;
    final start = _nextFree;
    _reserve(length * intSize * 2 + intSize);
    _writeInt(start, intSize, length);
    for (var i = 0; i != length; ++i) {
      final key = keysList[i];
      _writeInt(start + intSize + i * intSize * 2, intSize, _addString(key));
      final value = function(key);
      _writeInt(start + intSize + i * intSize * 2 + intSize, intSize,
          _addValue(value));
    }
  }

  void _reserve(int bytes) {
    _nextFree += bytes;
    while (_nextFree > _buffer.length) {
      _expand();
    }
  }

  void _expand() {
    final oldBuffer = _buffer;
    _buffer = Uint8List(_buffer.length * 2);
    _buffer.setRange(0, oldBuffer.length, oldBuffer);
  }

  Pointer _addValue(Object? value) {
    final start = _nextFree;
    if (value is String) {
      _reserve(typeSize);
      _buffer[start] = Type.string.index;
      _reserve(intSize);
      _writeInt(start + 1, intSize, _addString(value));
      return start;
    } else if (value is bool) {
      _reserve(typeSize);
      _buffer[start] = Type.bool.index;
      _addBool(value);
      return start;
    } else if (value is JsonBuffer) {
      _reserve(typeSize);
      _buffer[start] = Type.map.index;
      _add(value._keys!, value._function!);
      return start;
    } else {
      throw UnsupportedError('Unsupported value type: ${value.runtimeType}');
    }
  }

  Pointer _addString(String value) {
    final maybeResult = _seenStrings[value];
    if (maybeResult != null) return maybeResult;
    final start = _nextFree;
    final bytes = utf8.encode(value);
    final length = bytes.length;
    _reserve(intSize + length);
    _writeInt(start, intSize, length);
    _buffer.setRange(start + intSize, start + intSize + length, bytes);
    _seenStrings[value] = start;
    return start;
  }

  Pointer _addBool(bool value) {
    final start = _nextFree;
    _reserve(1);
    _buffer[start] = value ? 1 : 0;
    return start;
  }

  void _writeInt(Pointer pointer, int intSize, int value) {
    if (intSize == 1) {
      _buffer[pointer] = value;
    } else if (intSize == 2) {
      _buffer[pointer] = value & 0xff;
      _buffer[pointer + 1] = (value >> 8) & 0xff;
    } else if (intSize == 3) {
      _buffer[pointer] = value & 0xff;
      _buffer[pointer + 1] = (value >> 8) & 0xff;
      _buffer[pointer + 2] = (value >> 16) & 0xff;
    } else if (intSize == 4) {
      _buffer[pointer] = value & 0xff;
      _buffer[pointer + 1] = (value >> 8) & 0xff;
      _buffer[pointer + 2] = (value >> 16) & 0xff;
      _buffer[pointer + 3] = (value >> 24) & 0xff;
    } else {
      throw UnsupportedError('Integer size: $intSize');
    }
  }

  int _readInt(Pointer pointer, int intSize) {
    if (intSize == 1) {
      return _buffer[pointer];
    } else if (intSize == 2) {
      return _buffer[pointer] + (_buffer[pointer + 1] << 8);
    } else if (intSize == 3) {
      return _buffer[pointer] +
          (_buffer[pointer + 1] << 8) +
          (_buffer[pointer + 2] << 16);
    } else if (intSize == 4) {
      return _buffer[pointer] +
          (_buffer[pointer + 1] << 8) +
          (_buffer[pointer + 2] << 16) +
          (_buffer[pointer + 3] << 24);
    } else {
      throw UnsupportedError('Integer size: $intSize');
    }
  }

  Object? _readValue(Pointer pointer) {
    final type = Type.values[_buffer[pointer]];
    switch (type) {
      case Type.string:
        return _readString(_readPointer(pointer + typeSize));
      case Type.bool:
        return _readBool(pointer + typeSize);
      case Type.map:
        return JsonBufferMap._(this, pointer + typeSize);
    }
  }

  Pointer _readPointer(Pointer pointer) {
    return _readInt(pointer, intSize);
  }

  String _readString(Pointer pointer) {
    final maybeResult = _decodedStrings[pointer];
    if (maybeResult != null) return maybeResult;
    final length = _readInt(pointer, intSize);
    return _decodedStrings[pointer] ??= utf8
        .decode(_buffer.sublist(pointer + intSize, pointer + intSize + length));
  }

  bool _readBool(Pointer pointer) {
    final value = _buffer[pointer];
    if (value == 1) return true;
    if (value == 0) return false;
    throw StateError('Unexpcted bool value: $value');
  }

  late final Map<String, Object?> asMap = _createMap();

  Map<String, Object?> _createMap() {
    _evaluate();
    return JsonBufferMap._(this, 0);
  }

  @override
  String toString() => _buffer.toString();
}

class JsonBufferMap
    with MapMixin<String, Object?>
    implements Map<String, Object?> {
  final JsonBuffer _buffer;
  final Pointer _pointer;

  JsonBufferMap._(this._buffer, this._pointer);

  Uint8List serialize() => _buffer.serialize();

  @override
  Object? operator [](Object? key) {
    final iterator = entries.iterator as JsonBufferMapEntryIterator;
    while (iterator.moveNext()) {
      if (iterator.current.key == key) return iterator.current.value;
    }
    return null;
  }

  @override
  void operator []=(String key, Object? value) {
    throw UnsupportedError('JsonBufferMap is readonly.');
  }

  @override
  void clear() {
    throw UnsupportedError('JsonBufferMap is readonly.');
  }

  @override
  late Iterable<String> keys =
      JsonBufferMapEntryIterable(_buffer, _pointer, readValues: false)
          .map((e) => e.key);

  @override
  late Iterable<Object?> values =
      JsonBufferMapEntryIterable(_buffer, _pointer, readKeys: false)
          .map((e) => e.value);

  @override
  late Iterable<MapEntry<String, Object?>> entries =
      JsonBufferMapEntryIterable(_buffer, _pointer);

  @override
  Object? remove(Object? key) {
    throw UnsupportedError('JsonBufferMap is readonly.');
  }
}

class JsonBufferMapEntryIterable
    with IterableMixin<MapEntry<String, Object?>>
    implements Iterable<MapEntry<String, Object?>> {
  final JsonBuffer _buffer;
  final Pointer _pointer;
  final bool readKeys;
  final bool readValues;

  JsonBufferMapEntryIterable(this._buffer, this._pointer,
      {this.readKeys = true, this.readValues = true});

  @override
  Iterator<MapEntry<String, Object?>> get iterator =>
      JsonBufferMapEntryIterator(_buffer, _pointer);
}

class JsonBufferMapEntryIterator
    implements Iterator<MapEntry<String, Object?>> {
  final JsonBuffer _buffer;
  Pointer _pointer;
  final Pointer _last;
  final bool readKeys;
  final bool readValues;

  JsonBufferMapEntryIterator(this._buffer, Pointer pointer,
      {this.readKeys = true, this.readValues = true})
      : _last = pointer +
            intSize +
            _buffer._readInt(pointer, intSize) * 2 * intSize,
        _pointer = pointer - intSize;

  @override
  MapEntry<String, Object?> get current => MapEntry(
      readKeys ? _buffer._readString(_buffer._readPointer(_pointer)) : '',
      readValues
          ? _buffer._readValue(_buffer._readPointer(_pointer + intSize))
          : null);

  @override
  bool moveNext() {
    if (_pointer == _last) return false;
    if (_pointer > _last) throw StateError('Moved past _last!');
    _pointer += intSize * 2;
    return _pointer != _last;
  }
}
