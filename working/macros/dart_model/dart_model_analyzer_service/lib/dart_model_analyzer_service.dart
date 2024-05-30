// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/element/element.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/constant/value.dart';
import 'package:dart_model/delta.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:stream_transform/stream_transform.dart';

class DartModelAnalyzerService implements Service {
  final AnalysisContext? context;
  AnalysisSession? session;

  DartModelAnalyzerService({this.context, this.session});

  @override
  Future<Model> query(Query query) async {
    if (context != null) {
      session = context!.currentSession;
    }

    if (query.operations.first.isAnnotation) {
      final annotation = query.operations.first.annotationType;
      final model = Model();
      for (final file in Directory(context!.contextRoot.root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              // TODO(davidmorgan): exclude augmentation files in a better way.
              !f.path.endsWith('.a.dart'))) {
        final library = (await session!.getResolvedLibrary(file.path))
            as ResolvedLibraryResult;
        for (final classElement
            in library.element.topLevelElements.whereType<ClassElement>()) {
          final maybeModel = Model();
          _addInterfaceElement(maybeModel, classElement);
          final maybeLibrary = maybeModel.library(maybeModel.uris.first)!;
          final maybeName = maybeLibrary.names.first;
          if (maybeLibrary
              .scope(maybeName)!
              .asInterface!
              .annotations
              .any((a) => a.type == annotation)) {
            model.ensure(maybeModel.uris.first);
            model
                .library(maybeModel.uris.first)!
                .add(maybeName, maybeLibrary.scope(maybeName)!);
          }
        }
      }
      return model;
    } else {
      final uri = query.firstUri;
      await session!.getLibraryByUri(uri);
      return queryLibrary(
          (await session!.getLibraryByUri(uri) as LibraryElementResult).element,
          query);
    }
  }

  @override
  Future<Stream<Delta>> watch(Query query) async {
    if (context != null) {
      session = context!.currentSession;
    }
    // TODO(davidmorgan): watch recursivly.
    final changes = Directory('${context!.contextRoot.root.path}/lib').watch();
    Model previousModel = Model();
    return Stream.fromIterable(<FileSystemEvent?>[null])
        .followedBy(changes)
        .asyncMap((change) async {
          if (change != null) context!.changeFile(change.path);
          await context!.applyPendingFileChanges();
          final model = await this.query(query);
          var delta = Delta.compute(previousModel, model);
          // Round trip to check serialization works.
          // TODO(davidmorgan): add test coverage.
          delta = Delta.fromJson(json.decode(json.encode(delta)));
          previousModel = model;
          return delta.isEmpty ? null : delta;
        })
        .where((e) => e != null)
        .map((e) => e!)
        .asBroadcastStream();
  }

  Model queryLibrary(LibraryElement libraryElement, Query query) {
    final result = Model();
    if (query.firstName == null) {
      for (final classElement in libraryElement.topLevelElements
          .whereType<ClassElement>()
          .toList()) {
        _addInterfaceElement(result, classElement);
      }
    } else {
      final classElement = libraryElement.topLevelElements
          .whereType<ClassElement>()
          .where((e) => e.name == query.firstName)
          .single;
      _addInterfaceElement(result, classElement);
    }
    return result;
  }

  QualifiedName _addInterfaceElement(Model result, InterfaceElement element) {
    final uri = element.library.source.uri.toString();
    final name = element.displayName;
    result.ensure(uri);
    final supertype = element.supertype == null
        ? null
        : _addInterfaceElement(result, element.supertype!.element);
    final interfaces = element.interfaces
        .map((i) => _addInterfaceElement(result, i.element))
        .toList();
    final members = <String, Member>{};
    for (final field in element.fields) {
      members[field.name] = Member(
          abstract: field.isAbstract,
          method: false,
          field: true,
          getter: false,
          static: field.isStatic,
          synthetic: field.isSynthetic);
    }
    for (final method in element.methods) {
      members[method.name] = Member(
          abstract: method.isAbstract,
          method: true,
          field: false,
          getter: false,
          static: method.isStatic,
          synthetic: method.isSynthetic);
    }
    final annotations = <Annotation>[];
    for (final metadata in element.metadata) {
      annotations.add(_createAnnotation(metadata));
    }
    for (final accessor in element.accessors) {
      // TODO: maybe need a different namespace for these?
      if (!accessor.isSynthetic) {
        members[accessor.name] = Member(
            abstract: accessor.isAbstract,
            method: false,
            field: false,
            getter: accessor.isGetter,
            // TODO: setter
            static: accessor.isStatic,
            synthetic: accessor.isSynthetic);
      }
    }
    result.library(uri)!.add(
        name,
        Class(
            annotations: annotations,
            supertype: supertype,
            interfaces: interfaces,
            members: members,
            abstract: element is ClassElement && element.isAbstract));
    return QualifiedName(
        uri: element.source.uri.toString(), name: element.displayName);
  }

  Annotation _createAnnotation(ElementAnnotation element) {
    final value = element.computeConstantValue();
    if (value == null) {
      return Annotation(
          type: QualifiedName(uri: 'unresolved', name: 'unresolved'),
          value: null);
    }
    final qualifiedName = QualifiedName(
        uri: value.type!.element!.source!.uri.toString(),
        name: value.type!.getDisplayString(withNullability: false));
    return Annotation(
      type: qualifiedName,
      value: _createValue(value as DartObjectImpl),
    );
  }

  Value _createValue(DartObjectImpl object) {
    if (object.isNull) return Value.primitive(null);
    if (object.isBool) return Value.primitive(object.toBoolValue());
    if (object.isBoolNumStringOrNull) {
      // TODO(davidmorgan): other types.
      return Value.primitive(object.toStringValue());
    }
    if (object.isUserDefinedObject) {
      return Value.object(fields: {
        for (final field in object.fields!.entries)
          field.key: _createValue(field.value)
      });
    }
    return Value.fromJson(
        'package:code_model does not support value: ${object.toString()}');
  }
}
