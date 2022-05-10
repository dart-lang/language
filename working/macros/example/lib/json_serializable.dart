// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// ignore_for_file: deprecated_member_use

// There is no public API exposed yet, the in progress api lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

final dartCore = Uri.parse('dart:core');

// TODO: Support `toJson`, collections, and probably some other things :).
macro class JsonSerializable
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const JsonSerializable();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    var constructors = await builder.constructorsOf(clazz);
    if (constructors.any((c) => c.identifier.name == 'fromJson')) {
      throw ArgumentError('There is already a `fromJson` constructor for '
          '`${clazz.identifier.name}`, so one could not be added.');
    }

    var map = await builder.resolveIdentifier(dartCore, 'Map');
    var string = NamedTypeAnnotationCode(
        name: await builder.resolveIdentifier(dartCore, 'String'));
    var dynamic = NamedTypeAnnotationCode(
        name: await builder.resolveIdentifier(dartCore, 'dynamic'));
    var mapStringDynamic =
        NamedTypeAnnotationCode(name: map, typeArguments: [string, dynamic]);
    builder.declareInClass(DeclarationCode.fromParts([
      'external ',
      clazz.identifier.name,
      '.fromJson(',
      mapStringDynamic,
      ' json);',
    ]));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    // TODO: support extending other classes.
    if (clazz.superclass != null) {
      throw UnsupportedError(
          'Serialization of classes that extend other classes is not supported.');
    }

    var constructors = await builder.constructorsOf(clazz);
    var fromJson =
        constructors.firstWhere((c) => c.identifier.name == 'fromJson');
    var fromJsonBuilder = await builder.buildConstructor(fromJson.identifier);
    var fields = await builder.fieldsOf(clazz);
    var jsonParam = fromJson.positionalParameters.single.identifier;
    fromJsonBuilder.augment(initializers: [
      for (var field in fields)
        Code.fromParts([
          field.identifier,
          ' = ',
          await _convertField(field, jsonParam, builder),
        ]),
    ], body: FunctionBodyCode.fromString('{}'));
  }

  // TODO: Support nested List, Map, etc conversion, including deep casting.
  Future<Code> _convertField(FieldDeclaration field, Identifier jsonParam,
      DefinitionBuilder builder) async {
    var fieldType = field.type;
    if (fieldType is! NamedTypeAnnotation) {
      throw ArgumentError(
          'Only fields with named types are allowed on serializable classes, '
          'but `${field.identifier.name}` was not a named type.');
    }
    var fieldTypeDecl = await builder.declarationOf(fieldType.identifier);
    while (fieldTypeDecl is TypeAliasDeclaration) {
      var aliasedType = fieldTypeDecl.aliasedType;
      if (aliasedType is! NamedTypeAnnotation) {
        throw ArgumentError(
            'Only fields with named types are allowed on serializable classes, '
            'but `${field.identifier.name}` did not resolve to a named type.');
      }
    }
    if (fieldTypeDecl is! ClassDeclaration) {
      throw ArgumentError(
          'Only classes are supported in field types for serializable classes, '
          'but the field `${field.identifier.name}` does not have a class '
          'type.');
    }

    var fieldConstructors = await builder.constructorsOf(fieldTypeDecl);
    var fieldTypeFromJson = fieldConstructors
        .firstWhereOrNull((c) => c.identifier.name == 'fromJson')
        ?.identifier;
    if (fieldTypeFromJson != null) {
      return Code.fromParts([
        fieldTypeFromJson,
        '(',
        jsonParam,
        '["${field.identifier.name}"])',
      ]);
    } else {
      return Code.fromParts([
        jsonParam,
        // TODO: support nested serializable types.
        '["${field.identifier.name}"] as ',
        field.type.code,
      ]);
    }
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) compare) {
    for (var item in this) {
      if (compare(item)) return item;
    }
    return null;
  }
}
