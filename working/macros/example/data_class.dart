import '../api/macros.dart';
import '../api/introspection.dart';
import '../api/builders.dart';
import '../api/code.dart';

const dataClass = _DataClass();

macro class _DataClass implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const _DataClass();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassDeclarationBuilder context) async {
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

macro class _AutoConstructor implements ClassDeclarationsMacro {
  const _AutoConstructor();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassDeclarationBuilder builder) async {
    var constructors = await builder.constructorsOf(clazz);
    if (constructors.any((c) => c.name == '')) {
      throw ArgumentError(
          'Cannot generate an unnamed constructor because one already exists');
    }

    var parts = [Code.fromString('${clazz.name}({')];
    // Add all the fields of `declaration` as named parameters.
    var fields = await builder.fieldsOf(clazz);
    for (var field in fields) {
      var requiredKeyword = field.type.isNullable ? '' : 'required ';
      parts.add(Code.fromString('\n${requiredKeyword}this.${field.name},'));
    }

    // Add all super constructor parameters as named parameters.
    var superclass = await builder.superclassOf(clazz);
    MethodDeclaration? superconstructor;
    if (superclass != null) {
      var superconstructor = (await builder.constructorsOf(superclass))
          .firstWhereOrNull((c) => c.name == '');
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
        parts.add(Code.fromParts([
          '\n$requiredKeyword${param.type.code} ${param.name}',
          defaultValue,
          ',',
        ]));
      }
      for (var param in superconstructor.namedParameters) {
        var requiredKeyword = param.isRequired ? '' : 'required ';
        var defaultValue = param.defaultValue == null
            ? ''
            : Code.fromParts([' = ', param.defaultValue!]);
        parts.add(Code.fromParts([
          '\n$requiredKeyword${param.type.code} ${param.name}',
          defaultValue,
          ',',
        ]));
      }
    }
    parts.add(Code.fromString('\n})'));
    if (superconstructor != null) {
      parts.add(Code.fromString(' : super('));
      for (var param in superconstructor.positionalParameters) {
        parts.add(Code.fromString('\n${param.name},'));
      }
      if (superconstructor.namedParameters.isNotEmpty) {
        parts.add(Code.fromString('{'));
        for (var param in superconstructor.namedParameters) {
          parts.add(Code.fromString('\n${param.name}: ${param.name},'));
        }
        parts.add(Code.fromString('\n}'));
      }
      parts.add(Code.fromString(')'));
    }
    parts.add(Code.fromString(';'));
    builder.declareInClass(DeclarationCode.fromParts(parts));
  }
}

const copyWith = _CopyWith();

// TODO: How to deal with overriding nullable fields to `null`?
macro class _CopyWith implements ClassDeclarationsMacro {
  const _CopyWith();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassDeclarationBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    if (methods.any((c) => c.name == 'copyWith')) {
      throw ArgumentError(
          'Cannot generate a copyWith method because one already exists');
    }
    var allFields = await clazz.allFields(builder).toList();
    var namedParams = [
      for (var field in allFields)
        ParameterCode.fromString('${field.type.code} ${field.name}'),
    ];
    var args = [
      for (var field in allFields)
        NamedArgumentCode.fromString(
            '${field.name}: ${field.name} ?? this.${field.name}'),
    ];
    builder.declareInClass(DeclarationCode.fromParts([
      clazz.instantiate().code,
      ' copyWith({',
      ...namedParams.joinAsCode(', '),
      ',})',
      // TODO: We assume this constructor exists, but should check
      '=> ', clazz.instantiate().code, '(',
      ...args.joinAsCode(', '),
      ', );',
    ]));
  }
}

const hashCode = _HashCode();

macro class _HashCode implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const _HashCode();

  @override
  void buildDeclarationsForClass(
      ClassDeclaration clazz, ClassDeclarationBuilder builder) {
    builder.declareInClass(DeclarationCode.fromString('''
@override
external int get hashCode;'''));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var hashCodeBuilder = builder.buildMethod('hashCode');
    var hashCodeExprs = [
      await for (var field in clazz.allFields(builder))
        ExpressionCode.fromString('${field.name}.hashCode')
    ].joinAsCode(' ^ ');
    hashCodeBuilder.augment(FunctionBodyCode.fromParts([
      ' => ',
      ...hashCodeExprs,
      ';',
    ]));
  }
}

const equality = _Equality();

macro class _Equality implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const _Equality();

  @override
  void buildDeclarationsForClass(
      ClassDeclaration clazz, ClassDeclarationBuilder builder) {
    builder.declareInClass(DeclarationCode.fromString('''
@override
external bool operator==(Object other);'''));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var equalsBuilder = builder.buildMethod('==');
    var equalityExprs = [
      await for (var field in clazz.allFields(builder))
        ExpressionCode.fromString('this.${field.name} == other.${field.name}'),
    ].joinAsCode(' && ');
    equalsBuilder.augment(FunctionBodyCode.fromParts([
      ' => other is ${clazz.instantiate().code} && ',
      ...equalityExprs,
      ';',
    ]));
  }
}

const toString = _ToString();

macro class _ToString implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const _ToString();

  @override
  void buildDeclarationsForClass(
      ClassDeclaration clazz, ClassDeclarationBuilder builder) {
    builder.declareInClass(DeclarationCode.fromString(
      '''
@override
external String toString();''',
    ));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    var toStringBuilder = builder.buildMethod('toString');
    var fieldExprs = [
      await for (var field in clazz.allFields(builder))
        Code.fromString('  ${field.name}: \${${field.name}}'),
    ].joinAsCode('\n');

    toStringBuilder.augment(FunctionBodyCode.fromParts([
      ' => """\${${clazz.name}} { ',
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
    while (next is ClassDeclaration && next.name != 'Object') {
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
  }
}
