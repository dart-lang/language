// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:collection/collection.dart';

Map<Object, Model> _roots = Map.identity();
Map<Object, String> _names = Map.identity();

final class QualifiedName {
  final String uri;
  final String name;

  QualifiedName({required this.uri, required this.name});

  static QualifiedName? tryParse(String qualifiedName) {
    final index = qualifiedName.indexOf('#');
    if (index == -1) return null;
    return QualifiedName(
        uri: qualifiedName.substring(0, index),
        name: qualifiedName.substring(index + 1));
  }

  @override
  bool operator ==(Object other) =>
      other is QualifiedName && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;

  @override
  String toString() => '$uri#$name';
}

extension type Model.fromJson(Map<String, Object?> node) {
  Model() : this.fromJson({});

  Iterable<String> get uris => node.keys;
  Iterable<Library> get libraries => node.values.cast();

  Library? library(String uri) => node[uri] as Library?;
  Scope? scope(QualifiedName qualifiedName) =>
      library(qualifiedName.uri)?.scope(qualifiedName.name);

  void ensure(String name) {
    if (node.containsKey(name)) return;
    add(name, Library());
  }

  void add(String name, Library library) {
    if (node.containsKey(name)) throw ArgumentError('Already present: $name');
    _names[library] = name;
    _roots[library] = this;
    node[name] = library;
  }

  bool hasPath(Path path) {
    if (path.path.length == 1) {
      return node.containsKey(path.path.first);
    } else {
      final next = node[path.path.first];
      if (next is Map<String, Object?>) {
        return (next as Model).hasPath(path.skipOne());
      } else {
        return false;
      }
    }
  }

  Object? getAtPath(Path path) {
    if (path.path.length == 1) {
      return node[path.path.first];
    } else {
      final next = node[path.path.first];
      if (next is Map<String, Object?>) {
        return (next as Model).getAtPath(path.skipOne());
      } else {
        throw ArgumentError('Model does not have path: $path');
      }
    }
  }

  void updateAtPath(Path path, Object? value) {
    if (path.path.length == 1) {
      final name = path.path.single;
      node[path.path.single] = value;

      if (value is Map<String, Object?>) {
        _updateNames(name, value);
      }
    } else {
      if (!node.containsKey(path.path.first)) {
        node[path.path.first] = <String, Object?>{};
      }
      (node[path.path.first] as Model).updateAtPath(path.skipOne(), value);
    }
  }

  void _updateNames(String name, Map<String, Object?> value) {
    _names[value] = name;
    for (final entry in value.entries) {
      if (entry.value is Map<String, Object?>) {
        _updateNames(entry.key, entry.value as Map<String, Object?>);
      }
    }
  }

  void removeAtPath(Path path) {
    if (path.path.length == 1) {
      node.remove(path.path.single);
    } else {
      final first = path.path.first;
      final rest = path.skipOne();
      if (first == '*') {
        for (final key in node.keys) {
          final next = node[key];
          if (next is Map<String, Object?>) {
            (next as Model).removeAtPath(rest);
          }
        }
      } else {
        (node[path.path.first] as Model).removeAtPath(rest);
      }
    }
  }

  bool equals(Model other) =>
      const DeepCollectionEquality().equals(node, other.node);

  String prettyPrint() => const JsonEncoder.withIndent('  ').convert(node);
}

extension type Library.fromJson(Map<String, Object?> node) implements Object {
  Library() : this.fromJson({});

  Iterable<String> get names => node.keys;
  Iterable<Scope> get scopes => node.values.cast();

  Scope? scope(String uri) => node[uri] as Scope?;

  void add(String name, Scope scope) {
    _names[scope] = name;
    _roots[scope] = _roots[this]!;
    node[name] = scope;
  }
}

extension type Scope.fromJson(Map<String, Object?> node) implements Object {
  Scope() : this.fromJson({});

  String get name => _names[this]!;

  Interface? get asInterface => Interface.fromJson(node);
}

extension type Class.fromJson(Map<String, Object?> node) implements Scope {
  Class(
      {bool? abstract,
      List<Annotation>? annotations,
      QualifiedName? supertype,
      Iterable<QualifiedName>? interfaces,
      Map<String, Member>? members})
      : this.fromJson({
          'properties': ['class', if (abstract == true) 'abstract'],
          if (annotations != null) 'annotations': annotations.toList(),
          if (supertype != null) 'supertype': supertype.toString(),
          if (interfaces != null)
            'interfaces': interfaces.map((i) => i.toString()).toList(),
          if (members != null) 'members': members,
        });

  String get name => _names[this]!;
}

extension type Interface.fromJson(Map<String, Object?> node) implements Scope {
  String get name => _names[this]!;

  bool get isClass => (node['properties'] as List).contains('class');
  bool get isAbstract => (node['properties'] as List).contains('abstract');

  Interface? get supertype {
    if (!node.containsKey('supertype')) return null;
    final name = QualifiedName.tryParse(node['supertype'] as String);
    if (name == null) return null;
    return _roots[this]!.scope(name)?.asInterface;
  }

  List<Annotation> get annotations => (node['annotations'] as List).cast();

  Map<String, Member> get members => (node['members'] as Map).cast();

  Iterable<Interface> get interfaces {
    final result = <Interface>[];
    for (final interface in (node['interfaces'] as List).cast<String>()) {
      final name = QualifiedName.tryParse(interface)!;
      result.add(_roots[this]!.scope(name)!.asInterface!);
    }
    return result;
  }

  Iterable<Interface> get allSupertypes sync* {
    if (supertype != null) {
      yield supertype!;
      yield* supertype!.allSupertypes;
    }
    yield* interfaces;
  }
}

extension type Member.fromJson(Map<String, Object?> node) {
  Member(
      {required bool getter,
      required bool abstract,
      required bool method,
      required bool field,
      required bool static,
      required bool synthetic})
      : this.fromJson({
          'properties': [
            if (abstract) 'abstract',
            if (getter) 'getter',
            if (method) 'method',
            if (field) 'field',
            if (static) 'static',
            if (synthetic) 'synthetic'
          ]
        });

  String get name => _names[this]!;

  bool get isAbstract => (node['properties'] as List).contains('abstract');
  bool get isField => (node['properties'] as List).contains('field');
  bool get isGetter => (node['properties'] as List).contains('getter');
  bool get isMethod => (node['properties'] as List).contains('method');
  bool get isStatic => (node['properties'] as List).contains('static');
  bool get isSynthetic => (node['properties'] as List).contains('synthetic');
}

extension type Annotation.fromJson(Map<String, Object?> node) {
  Annotation({required QualifiedName type, Value? value})
      : this.fromJson({
          'type': type.toString(),
          if (value != null) 'value': value,
        });

  QualifiedName get type => QualifiedName.tryParse(node['type'] as String)!;

  Value get value => node['value'] as Value;
}

extension type Value.fromJson(Object? value) {
  // TODO(davidmorgan): check type.
  Value.primitive(Object? value) : this.fromJson(value);
  Value.object({
    required Map<String, Value> fields,
  }) : this.fromJson(fields);

  Value? field(String name) => (value as Map<String, Value>)[name];
}

extension type Path.fromJson(List<Object?> node) {
  Path(List<String> path) : this.fromJson(path);

  List<String> get path => (node as List).cast();

  String? get uri => path.isEmpty ? null : path.first;

  Path followedByOne(String element) =>
      Path(path.followedBy([element]).toList());

  Path skipOne() => Path(path.skip(1).toList());
}
