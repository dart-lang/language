import '../api/macros.dart';
import '../api/introspection.dart';
import '../api/builders.dart';
import '../api/code.dart';

const dataClass = _DataClass();

class _DataClass implements ClassMacro {
  const _DataClass();

  @override
  void visitClass(ClassDeclaration clazz, ClassContext context) {
    autoConstructor.visitClass(clazz, context);
    copyWith.visitClass(clazz, context);
    hashCode.visitClass(clazz, context);
    equality.visitClass(clazz, context);
    toString.visitClass(clazz, context);
  }
}

const autoConstructor = _AutoConstructor();

class _AutoConstructor implements ClassMacro {
  const _AutoConstructor();

  @override
  void visitClass(ClassDeclaration clazz, ClassContext context) {
    context.buildDeclarations((builder) async {
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
            '\n$requiredKeyword${param.type.toCode()} ${param.name}',
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
            '\n$requiredKeyword${param.type.toCode()} ${param.name}',
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
    });
  }
}

const copyWith = _CopyWith();

// TODO: How to deal with overriding nullable fields to `null`?
class _CopyWith implements ClassMacro {
  const _CopyWith();

  @override
  void visitClass(ClassDeclaration clazz, ClassContext context) {
    context.buildDeclarations((builder) async {
      var methods = await builder.methodsOf(clazz);
      if (methods.any((c) => c.name == 'copyWith')) {
        throw ArgumentError(
            'Cannot generate a copyWith method because one already exists');
      }
      var allFields = await clazz.allFields(builder).toList();
      var namedParams = [
        for (var field in allFields)
          ParameterCode.fromString(
              '${field.type.toCode()}${field.type.isNullable ? '' : '?'} '
              '${field.name}'),
      ];
      var args = [
        for (var field in allFields)
          NamedArgumentCode.fromString(
              '${field.name}: ${field.name} ?? this.${field.name}'),
      ];
      builder.declareInClass(DeclarationCode.fromParts([
        clazz.instantiate().toCode(),
        ' copyWith({',
        ...namedParams.joinAsCode(', '),
        ',})',
        // TODO: We assume this constructor exists, but should check
        '=> ', clazz.instantiate().toCode(), '(',
        ...args.joinAsCode(', '),
        ', );',
      ]));
    });
  }
}

const hashCode = _HashCode();

class _HashCode implements ClassMacro {
  const _HashCode();

  @override
  void visitClass(ClassDeclaration clazz, ClassContext context) {
    context.buildDeclarations((builder) {
      builder.declareInClass(DeclarationCode.fromString('''
@override
external int get hashCode;'''));
    });

    context.buildDefinitions((builder) async {
      await builder.buildMethod('hashCode', (builder) async {
        var hashCodeExprs = [
          await for (var field in clazz.allFields(builder))
            ExpressionCode.fromString('${field.name}.hashCode')
        ].joinAsCode(' ^ ');
        builder.augment(FunctionBodyCode.fromParts([
          ' => ',
          ...hashCodeExprs,
          ';',
        ]));
      });
    });
  }
}

const equality = _Equality();

class _Equality implements ClassMacro {
  const _Equality();

  @override
  void visitClass(ClassDeclaration clazz, ClassContext context) {
    context.buildDeclarations((builder) async {
      builder.declareInClass(DeclarationCode.fromString('''
@override
external bool operator==(Object other);'''));
    });

    context.buildDefinitions((builder) async {
      await builder.buildMethod('==', (builder) async {
        var equalityExprs = [
          await for (var field in clazz.allFields(builder))
            ExpressionCode.fromString(
                'this.${field.name} == other.${field.name}'),
        ].joinAsCode(' && ');
        DeclarationCode.fromParts([
          ' => other is ${clazz.instantiate().toCode()} && ',
          ...equalityExprs,
          ';',
        ]);
      });
    });
  }
}

const toString = _ToString();

class _ToString implements ClassMacro {
  const _ToString();

  @override
  void visitClass(ClassDeclaration clazz, ClassContext context) {
    context.buildDeclarations((builder) async {
      builder.declareInClass(DeclarationCode.fromString(
        '''
@override
external String toString();''',
      ));
    });

    context.buildDefinitions((builder) async {
      await builder.buildMethod('toString', (builder) async {
        var fieldExprs = [
          await for (var field in clazz.allFields(builder))
            Code.fromString('  ${field.name}: \${${field.name}}'),
        ].joinAsCode('\n');

        builder.augment(FunctionBodyCode.fromParts([
          ' => """\${${clazz.name}} { ',
          ...fieldExprs,
          '}""";',
        ]));
      });
    });
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

extension _ToCode on TypeAnnotation {
  Code toCode() => Code.fromString(this.name, scope: this.scope);
}
