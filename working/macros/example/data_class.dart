// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// There is no public API exposed yet, the in progress api lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

// TODO: support loading macros by const instance reference.
const dataClass = DataClass();

/*macro*/ class DataClass
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const DataClass();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder context) async {
    await autoConstructor.buildDeclarationsForClass(clazz, context);
    await copyWith.buildDeclarationsForClass(clazz, context);
    hashCode.buildDeclarationsForClass(clazz, context);
    equality.buildDeclarationsForClass(clazz, context);
    toString.buildDeclarationsForClass(clazz, context);
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    await hashCode.buildDefinitionForClass(clazz, builder);
    await equality.buildDefinitionForClass(clazz, builder);
    await toString.buildDefinitionForClass(clazz, builder);
  }
}

const autoConstructor = _AutoConstructor();

/*macro*/ class _AutoConstructor implements ClassDeclarationsMacro {
  const _AutoConstructor();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    var constructors = await builder.constructorsOf(clazz);
    if (constructors.any((c) => c.identifier.name == '')) {
      throw ArgumentError(
          'Cannot generate an unnamed constructor because one already exists');
    }

    var parts = <Object>[clazz.identifier.name, '({'];
    // Add all the fields of `declaration` as named parameters.
    var fields = await builder.fieldsOf(clazz);
    for (var field in fields) {
      var requiredKeyword = field.type.isNullable ? '' : 'required ';
      parts.addAll(['\n${requiredKeyword}this.', field.identifier.name, ',']);
    }

    // Add all super constructor parameters as named parameters.
    var superclass = (await builder.superclassOf(clazz))!;
    MethodDeclaration? superconstructor;
    // TODO: Compare against Object identifier once we can get it.
    if (superclass.identifier.name != 'Object') {
      var superconstructor = (await builder.constructorsOf(superclass))
          .firstWhereOrNull((c) => c.identifier.name == '');
      if (superconstructor == null) {
        throw ArgumentError(
            'Super class $superclass of $clazz does not have an unnamed '
            'constructor');
      }
      // We convert positional parameters in the super constructor to named
      // parameters in this constructor.
      for (var param in superconstructor.positionalParameters) {
        var requiredKeyword = param.isRequired ? 'required' : '';
        var defaultValue = param.defaultValue == null
            ? ''
            : Code.fromParts([' = ', param.defaultValue!]);
        parts.addAll([
          '\n$requiredKeyword',
          param.type.code,
          ' ${param.identifier.name},',
          defaultValue,
          ',',
        ]);
      }
      for (var param in superconstructor.namedParameters) {
        var requiredKeyword = param.isRequired ? '' : 'required ';
        var defaultValue = param.defaultValue == null
            ? ''
            : Code.fromParts([' = ', param.defaultValue!]);
        parts.addAll([
          '\n$requiredKeyword',
          param.type.code,
          ' ${param.identifier.name}',
          defaultValue,
          ',',
        ]);
      }
    }
    parts.add('\n})');
    if (superconstructor != null) {
      parts.add(' : super(');
      for (var param in superconstructor.positionalParameters) {
        parts.add('\n${param.identifier.name},');
      }
      if (superconstructor.namedParameters.isNotEmpty) {
        parts.add('{');
        for (var param in superconstructor.namedParameters) {
          parts.add('\n${param.identifier.name}: ${param.identifier.name},');
        }
        parts.add('\n}');
      }
      parts.add(')');
    }
    parts.add(';');
    builder.declareInClass(DeclarationCode.fromParts(parts));
  }
}

const copyWith = _CopyWith();

// TODO: How to deal with overriding nullable fields to `null`?
/*macro*/ class _CopyWith implements ClassDeclarationsMacro {
  const _CopyWith();

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
        ParameterCode.fromParts(
            [field.type.code, '? ${field.identifier.name}']),
    ];
    var args = [
      for (var field in allFields)
        NamedArgumentCode.fromString(
            '${field.identifier.name}: ${field.identifier.name} '
            '?? this.${field.identifier.name}'),
    ];
    builder.declareInClass(DeclarationCode.fromParts([
      clazz.identifier,
      ' copyWith({',
      ...namedParams.joinAsCode(', '),
      ',})',
      // TODO: We assume this constructor exists, but should check
      '=> ', clazz.identifier, '(',
      ...args.joinAsCode(', '),
      ', );',
    ]));
  }
}

const hashCode = _HashCode();

/*macro*/ class _HashCode
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const _HashCode();

  @override
  void buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) {
    builder.declareInClass(DeclarationCode.fromString('''
@override
external int get hashCode;'''));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    var hashCodeBuilder = await builder.buildMethod(
        methods.firstWhere((m) => m.identifier.name == 'hashCode').identifier);
    var hashCodeExprs = [
      await for (var field in clazz.allFields(builder))
        ExpressionCode.fromString('${field.identifier.name}.hashCode')
    ].joinAsCode(' ^ ');
    hashCodeBuilder.augment(FunctionBodyCode.fromParts([
      ' => ',
      ...hashCodeExprs,
      ';',
    ]));
  }
}

const equality = _Equality();

/*macro*/ class _Equality
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const _Equality();

  @override
  void buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) {
    builder.declareInClass(DeclarationCode.fromString('''
@override
external bool operator==(Object other);'''));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    var equalsBuilder = await builder.buildMethod(
        methods.firstWhere((m) => m.identifier.name == '==').identifier);
    var equalityExprs = [
      await for (var field in clazz.allFields(builder))
        ExpressionCode.fromString(
            'this.${field.identifier.name} == other.${field.identifier.name}'),
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

const toString = _ToString();

/*macro*/ class _ToString
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const _ToString();

  @override
  void buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) {
    builder.declareInClass(DeclarationCode.fromString(
      '''
@override
external String toString();''',
    ));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    var toStringBuilder = await builder.buildMethod(
        methods.firstWhere((m) => m.identifier.name == 'toString').identifier);
    var fieldExprs = [
      await for (var field in clazz.allFields(builder))
        Code.fromString(
            '  ${field.identifier.name}: \${${field.identifier.name}}'),
    ].joinAsCode('\n');

    toStringBuilder.augment(FunctionBodyCode.fromParts([
      ' => """\${${clazz.identifier.name}} { ',
      ...fieldExprs,
      '}""";',
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
