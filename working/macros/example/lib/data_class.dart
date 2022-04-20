// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// There is no public API exposed yet, the in progress api lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class DataClass
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const DataClass();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder context) async {
    await Future.wait([
      AutoConstructor().buildDeclarationsForClass(clazz, context),
      CopyWith().buildDeclarationsForClass(clazz, context),
      HashCode().buildDeclarationsForClass(clazz, context),
      Equality().buildDeclarationsForClass(clazz, context),
      ToString().buildDeclarationsForClass(clazz, context),
    ]);
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    await Future.wait([
      HashCode().buildDefinitionForClass(clazz, builder),
      Equality().buildDefinitionForClass(clazz, builder),
      ToString().buildDefinitionForClass(clazz, builder),
    ]);
  }
}

macro class AutoConstructor implements ClassDeclarationsMacro {
  const AutoConstructor();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    var constructors = await builder.constructorsOf(clazz);
    if (constructors.any((c) => c.identifier.name == 'gen')) {
      throw ArgumentError(
          'Cannot generate an unnamed constructor because one already exists');
    }

    var params = <Object>[];
    // Add all the fields of `declaration` as named parameters.
    var fields = await builder.fieldsOf(clazz);
    if (fields.isNotEmpty) {
      for (var field in fields) {
        var requiredKeyword = field.type.isNullable ? '' : 'required ';
        params.addAll(['\n${requiredKeyword}', field.identifier, ',']);
      }
    }

    // The object type from dart:core.
    var objectType = await builder.resolve(NamedTypeAnnotationCode(
        name:
            // ignore: deprecated_member_use
            await builder.resolveIdentifier(Uri.parse('dart:core'), 'Object')));

    // Add all super constructor parameters as named parameters.
    var superclass = (await builder.superclassOf(clazz))!;
    var superType = await builder
        .resolve(NamedTypeAnnotationCode(name: superclass.identifier));
    MethodDeclaration? superconstructor;
    if ((await superType.isExactly(objectType)) == false) {
      superconstructor = (await builder.constructorsOf(superclass))
          .firstWhereOrNull((c) => c.identifier.name == 'gen');
      if (superconstructor == null) {
        throw ArgumentError(
            'Super class $superclass of $clazz does not have an unnamed '
            'constructor');
      }
      // We convert positional parameters in the super constructor to named
      // parameters in this constructor.
      for (var param in superconstructor.positionalParameters) {
        var requiredKeyword = param.isRequired ? 'required' : '';
        params.addAll([
          '\n$requiredKeyword',
          param.type.code,
          ' ${param.identifier.name},',
        ]);
      }
      for (var param in superconstructor.namedParameters) {
        var requiredKeyword = param.isRequired ? '' : 'required ';
        params.addAll([
          '\n$requiredKeyword',
          param.type.code,
          ' ${param.identifier.name},',
        ]);
      }
    }

    bool hasParams = params.isNotEmpty;
    List<Object> parts = [
    // Don't use the identifier here because it should just be the raw name.
      clazz.identifier.name,
      '.gen(',
      if (hasParams) '{',
      ...params,
      if (hasParams) '}',
      ')',
    ];
    if (superconstructor != null) {
      parts.addAll([' : super.', superconstructor.identifier.name, '(']);
      for (var param in superconstructor.positionalParameters) {
        parts.add('\n${param.identifier.name},');
      }
      if (superconstructor.namedParameters.isNotEmpty) {
        for (var param in superconstructor.namedParameters) {
          parts.add('\n${param.identifier.name}: ${param.identifier.name},');
        }
      }
      parts.add(')');
    }
    parts.add(';');
    builder.declareInClass(DeclarationCode.fromParts(parts));
  }
}

// TODO: How to deal with overriding nullable fields to `null`?
macro class CopyWith implements ClassDeclarationsMacro {
  const CopyWith();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    if (methods.any((c) => c.identifier.name == 'copyWith')) {
      throw ArgumentError(
          'Cannot generate a copyWith method because one already exists');
    }
    var allFields = await clazz.allFields(builder).toList();
    var namedParams = [
      for (var field in allFields)
        ParameterCode(
            name: field.identifier.name,
            type: field.type.code.asNullable,
            keywords: const [],
            defaultValue: null),
    ];
    var args = [
      for (var field in allFields)
        Code.fromParts([
          '${field.identifier.name}: ${field.identifier.name} ?? ',
          field.identifier,
        ]),
    ];
    var hasParams = namedParams.isNotEmpty;
    builder.declareInClass(DeclarationCode.fromParts([
      clazz.identifier,
      ' copyWith(',
      if (hasParams) '{',
      ...namedParams.joinAsCode(', '),
      if (hasParams) '}',
      ')',
      // TODO: We assume this constructor exists, but should check
      '=> ', clazz.identifier, '.gen(',
      ...args.joinAsCode(', '),
      ');',
    ]));
  }
}

macro class HashCode
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const HashCode();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    builder.declareInClass(DeclarationCode.fromParts([
      'external ',
      // ignore: deprecated_member_use
      await builder.resolveIdentifier(Uri.parse('dart:core'), 'int'),
      ' get hashCode;',
    ]));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    var hashCodeBuilder = await builder.buildMethod(
        methods.firstWhere((m) => m.identifier.name == 'hashCode').identifier);
    var hashCodeExprs = [
      await for (var field in clazz.allFields(builder))
        ExpressionCode.fromParts([field.identifier, '.hashCode']),
    ].joinAsCode(' ^ ');
    hashCodeBuilder.augment(FunctionBodyCode.fromParts([
      ' => ',
      ...hashCodeExprs,
      ';',
    ]));
  }
}

macro class Equality
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const Equality();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    builder.declareInClass(DeclarationCode.fromParts([
      'external ',
      // ignore: deprecated_member_use
      await builder.resolveIdentifier(Uri.parse('dart:core'), 'bool'),
      ' operator==(',
      // ignore: deprecated_member_use
      await builder.resolveIdentifier(Uri.parse('dart:core'), 'Object'),
      ' other);',
    ]));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    var equalsBuilder = await builder.buildMethod(
        methods.firstWhere((m) => m.identifier.name == '==').identifier);
    var equalityExprs = [
      await for (var field in clazz.allFields(builder))
        ExpressionCode.fromParts([
          field.identifier,
          ' == other.',
          // Shouldn't be prefixed with `this.` due to having a receiver.
          field.identifier,
        ]),
    ].joinAsCode(' && ');
    equalsBuilder.augment(FunctionBodyCode.fromParts([
      ' => other is ',
      clazz.identifier,
      ' && ',
      ...equalityExprs,
      ';',
    ]));
  }
}


macro class ToString
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const ToString();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    builder.declareInClass(DeclarationCode.fromParts([
      'external ',
      // ignore: deprecated_member_use
      await builder.resolveIdentifier(Uri.parse('dart:core'), 'String'),
      ' toString();',
    ]));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    var toStringBuilder = await builder.buildMethod(
        methods.firstWhere((m) => m.identifier.name == 'toString').identifier);
    var fieldExprs = [
      await for (var field in clazz.allFields(builder))
        Code.fromParts([
          '  ${field.identifier.name}: \${',
          field.identifier,
          '}',
        ]),
    ].joinAsCode('\n');

    toStringBuilder.augment(FunctionBodyCode.fromParts([
      ' => """\${${clazz.identifier.name}} {\n',
      ...fieldExprs,
      '\n}""";',
    ]));
  }
}

extension _AllFields on ClassDeclaration {
  // Returns all fields from all super classes.
  Stream<FieldDeclaration> allFields(ClassIntrospector introspector) async* {
    for (var field in await introspector.fieldsOf(this)) {
      yield field;
    }
    var next = await introspector.superclassOf(this);
    // TODO: Compare against actual Object identifer once we provide a way to
    // get it.
    while (next is ClassDeclaration && next.identifier.name != 'Object') {
      for (var field in await introspector.fieldsOf(next)) {
        yield field;
      }
      next = await introspector.superclassOf(next);
    }
  }
}

extension _<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (var item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
