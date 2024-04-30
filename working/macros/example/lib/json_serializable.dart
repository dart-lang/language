// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// ignore_for_file: deprecated_member_use

import 'package:macros/macros.dart';

// TODO: Support collections, extending serializable classes, and more.
macro class JsonSerializable implements ClassDeclarationsMacro {
  const JsonSerializable();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    var constructors = await builder.constructorsOf(clazz);
    if (constructors.any((c) => c.identifier.name == 'fromJson')) {
      throw ArgumentError('There is already a `fromJson` constructor for '
          '`${clazz.identifier.name}`, so one could not be added.');
    }

    var map = await builder.resolveIdentifier(_dartCore, 'Map');
    var string = NamedTypeAnnotationCode(
        name: await builder.resolveIdentifier(_dartCore, 'String'));
    var dynamic = NamedTypeAnnotationCode(
        name: await builder.resolveIdentifier(_dartCore, 'dynamic'));
    var mapStringDynamic =
        NamedTypeAnnotationCode(name: map, typeArguments: [string, dynamic]);

    builder.declareInType(DeclarationCode.fromParts([
      '@',
      await builder.resolveIdentifier(_thisLibrary, 'FromJson'),
      // TODO(language#3580): Remove/replace 'external'?
      '()\n  external ',
      clazz.identifier.name,
      '.fromJson(',
      mapStringDynamic,
      ' json);',
    ]));

    builder.declareInType(DeclarationCode.fromParts([
      '@',
      await builder.resolveIdentifier(_thisLibrary, 'ToJson'),
      // TODO(language#3580): Remove/replace 'external'?
      '()\n  external ',
      mapStringDynamic,
      ' toJson();',
    ]));
  }
}

/// A macro applied to a fromJson constructor, which fills in the initializer list.
macro class FromJson implements ConstructorDefinitionMacro {
  const FromJson();

  @override
  Future<void> buildDefinitionForConstructor(ConstructorDeclaration constructor,
      ConstructorDefinitionBuilder builder) async {
    // TODO: Validate we are running on a valid fromJson constructor.

    // TODO: support extending other classes.
    final clazz = (await builder.typeDeclarationOf(constructor.definingType))
        as ClassDeclaration;
    var object = await builder.resolve(NamedTypeAnnotationCode(
        name: await builder.resolveIdentifier(_dartCore, 'Object')));
    if (clazz.superclass != null &&
        !await (await builder.resolve(
                NamedTypeAnnotationCode(name: clazz.superclass!.identifier)))
            .isExactly(object)) {
      throw UnsupportedError(
          'Serialization of classes that extend other classes is not supported.');
    }

    var fields = await builder.fieldsOf(clazz);
    var jsonParam = constructor.positionalParameters.single.identifier;
    builder.augment(initializers: [
      for (var field in fields)
        RawCode.fromParts([
          field.identifier,
          ' = ',
          await _convertFieldFromJson(field, jsonParam, builder),
        ]),
    ]);
  }

  // TODO: Support nested collections.
  Future<Code> _convertFieldFromJson(FieldDeclaration field,
      Identifier jsonParam, DefinitionBuilder builder) async {
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
      return RawCode.fromParts([
        fieldTypeFromJson,
        '(',
        jsonParam,
        '["${field.identifier.name}"])',
      ]);
    } else {
      return RawCode.fromParts([
        jsonParam,
        // TODO: support nested serializable types.
        '["${field.identifier.name}"] as ',
        field.type.code,
      ]);
    }
  }
}

/// A macro applied to a toJson instance method, which fills in the body.
macro class ToJson implements MethodDefinitionMacro {
  const ToJson();

  @override
  Future<void> buildDefinitionForMethod(
      MethodDeclaration method, FunctionDefinitionBuilder builder) async {
    // TODO: Validate we are running on a valid toJson method.

    // TODO: support extending other classes.
    final clazz = (await builder.typeDeclarationOf(method.definingType))
        as ClassDeclaration;
    var object = await builder.resolve(NamedTypeAnnotationCode(
        name: await builder.resolveIdentifier(_dartCore, 'Object')));
    if (clazz.superclass != null &&
        !await (await builder.resolve(
                NamedTypeAnnotationCode(name: clazz.superclass!.identifier)))
            .isExactly(object)) {
      throw UnsupportedError(
          'Serialization of classes that extend other classes is not supported.');
    }

    var fields = await builder.fieldsOf(clazz);
    builder.augment(FunctionBodyCode.fromParts([
      ' => {',
      for (var field in fields)
        RawCode.fromParts([
          '\n    \'',
          field.identifier.name,
          '\'',
          ': ',
          await _convertFieldToJson(field, builder),
          ',',
        ]),
      '\n  };',
    ]));
  }

  // TODO: Support nested collections.
  Future<Code> _convertFieldToJson(
      FieldDeclaration field, DefinitionBuilder builder) async {
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

    var fieldTypeMethods = await builder.methodsOf(fieldTypeDecl);
    var fieldToJson = fieldTypeMethods
        .firstWhereOrNull((c) => c.identifier.name == 'toJson')
        ?.identifier;
    if (fieldToJson != null) {
      return RawCode.fromParts([
        field.identifier,
        '.toJson()',
      ]);
    } else {
      // TODO: Check that it is a valid type we can serialize.
      return RawCode.fromParts([
        field.identifier,
      ]);
    }
  }
}

final _dartCore = Uri.parse('dart:core');
final _thisLibrary = Uri.parse('package:macro_proposal/json_serializable.dart');

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) compare) {
    for (var item in this) {
      if (compare(item)) return item;
    }
    return null;
  }
}
