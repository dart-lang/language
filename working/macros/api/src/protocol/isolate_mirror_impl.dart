import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

import '../../code.dart';
import 'protocol.dart';
import '../../builders.dart';
import '../../expansion_protocol.dart';
import '../../introspection.dart';
import '../../macros.dart';

/// Spawns a new isolate for loading and executing macros.
void spawn(SendPort sendPort) {
  var receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  receivePort.listen((message) async {
    if (message is LoadMacroRequest) {
      var response = await _loadMacro(message);
      sendPort.send(response);
    } else if (message is InstantiateMacroRequest) {
      var response = await _instantiateMacro(message);
      sendPort.send(response);
    } else if (message is ExecuteDefinitionsPhaseRequest) {
      var response = await _executeDefinitionsPhase(message);
      sendPort.send(response);
    } else {
      throw StateError('Unrecognized event type $message');
    }
  });
}

/// Maps macro identifiers to class mirrors.
final _macroClasses = <_MacroClassIdentifier, ClassMirror>{};

/// Handles [LoadMacroRequest]s.
Future<GenericResponse<MacroClassIdentifier>> _loadMacro(
    LoadMacroRequest request) async {
  try {
    var identifier = _MacroClassIdentifier(request.library, request.name);
    if (_macroClasses.containsKey(identifier)) {
      throw UnsupportedError(
          'Reloading macros is not supported by this implementation');
    }
    var libMirror =
        await currentMirrorSystem().isolate.loadUri(request.library);
    var macroClass =
        libMirror.declarations[Symbol(request.name)] as ClassMirror;
    _macroClasses[identifier] = macroClass;
    return GenericResponse(response: identifier, requestId: request.id);
  } catch (e) {
    return GenericResponse(error: e, requestId: request.id);
  }
}

/// Maps macro instance identifiers to instances.
final _macroInstances = <_MacroInstanceIdentifier, Macro>{};

/// Handles [InstantiateMacroRequest]s.
Future<GenericResponse<MacroInstanceIdentifier>> _instantiateMacro(
    InstantiateMacroRequest request) async {
  try {
    var clazz = _macroClasses[request.macroClass];
    if (clazz == null) {
      throw ArgumentError('Unrecognized macro class ${request.macroClass}');
    }
    var instance = clazz.newInstance(
        Symbol(request.constructorName), request.arguments.positional, {
      for (var entry in request.arguments.named.entries)
        Symbol(entry.key): entry.value,
    }).reflectee as Macro;
    var identifier = _MacroInstanceIdentifier();
    _macroInstances[identifier] = instance;
    return GenericResponse<MacroInstanceIdentifier>(
        response: identifier, requestId: request.id);
  } catch (e) {
    return GenericResponse(error: e, requestId: request.id);
  }
}

Future<GenericResponse<MacroExecutionResult>> _executeDefinitionsPhase(
    ExecuteDefinitionsPhaseRequest request) async {
  try {
    var instance = _macroInstances[request.macro];
    if (instance == null) {
      throw StateError('Unrecognized macro instance ${request.macro}\n'
          'Known instances: $_macroInstances)');
    }
    var declaration = request.declaration;
    if (instance is FunctionDefinitionMacro &&
        declaration is FunctionDeclaration) {
      var builder = _FunctionDefinitionBuilder(
          declaration,
          request.typeResolver,
          request.typeDeclarationResolver,
          request.classIntrospector);
      await instance.buildDefinitionForFunction(declaration, builder);
      return GenericResponse(response: builder.result, requestId: request.id);
    } else {
      throw UnsupportedError(
          ('Only FunctionDefinitionMacros are supported currently'));
    }
  } catch (e) {
    return GenericResponse(error: e, requestId: request.id);
  }
}

/// Our implementation of [MacroClassIdentifier].
class _MacroClassIdentifier implements MacroClassIdentifier {
  final String id;

  _MacroClassIdentifier(Uri library, String name) : id = '$library#$name';

  operator ==(other) => other is _MacroClassIdentifier && id == other.id;

  int get hashCode => id.hashCode;
}

/// Our implementation of [MacroInstanceIdentifier].
class _MacroInstanceIdentifier implements MacroInstanceIdentifier {
  static int _next = 0;

  final int id;

  _MacroInstanceIdentifier() : id = _next++;

  operator ==(other) => other is _MacroInstanceIdentifier && id == other.id;

  int get hashCode => id;
}

/// Our implementation of [MacroExecutionResult].
class _MacroExecutionResult implements MacroExecutionResult {
  @override
  final List<DeclarationCode> augmentations = <DeclarationCode>[];

  @override
  final List<DeclarationCode> imports = <DeclarationCode>[];
}

/// Custom implementation of [FunctionDefinitionBuilder].
class _FunctionDefinitionBuilder implements FunctionDefinitionBuilder {
  final TypeResolver typeResolver;
  final TypeDeclarationResolver typeDeclarationResolver;
  final ClassIntrospector classIntrospector;

  /// The declaration this is a builder for.
  final FunctionDeclaration declaration;

  /// The final result, will be built up over `augment` calls.
  final result = _MacroExecutionResult();

  _FunctionDefinitionBuilder(this.declaration, this.typeResolver,
      this.typeDeclarationResolver, this.classIntrospector);

  @override
  void augment(FunctionBodyCode body) {
    result.augmentations.add(DeclarationCode.fromParts([
      'augment ',
      declaration.returnType.code,
      ' ',
      declaration.name,
      if (declaration.typeParameters.isNotEmpty) ...[
        '<',
        for (var typeParam in declaration.typeParameters) ...[
          typeParam.name,
          if (typeParam.bounds != null) ...['extends ', typeParam.bounds!.code],
          if (typeParam != declaration.typeParameters.last) ', ',
        ],
        '>',
      ],
      '(',
      for (var positionalRequired
          in declaration.positionalParameters.where((p) => p.isRequired)) ...[
        ParameterCode.fromParts([
          positionalRequired.type.code,
          ' ',
          positionalRequired.name,
        ]),
        ', '
      ],
      if (declaration.positionalParameters.any((p) => !p.isRequired)) ...[
        '[',
        for (var positionalOptional in declaration.positionalParameters
            .where((p) => !p.isRequired)) ...[
          ParameterCode.fromParts([
            positionalOptional.type.code,
            ' ',
            positionalOptional.name,
          ]),
          ', ',
        ],
        ']',
      ],
      if (declaration.namedParameters.isNotEmpty) ...[
        '{',
        for (var named in declaration.namedParameters) ...[
          ParameterCode.fromParts([
            if (named.isRequired) 'required ',
            named.type.code,
            ' ',
            named.name,
            if (named.defaultValue != null) ...[
              ' = ',
              named.defaultValue!,
            ],
          ]),
          ', ',
        ],
        '}',
      ],
      ') ',
      body,
    ]));
  }

  @override
  Future<List<ConstructorDeclaration>> constructorsOf(ClassDeclaration clazz) =>
      classIntrospector.constructorsOf(clazz);

  @override
  Future<List<FieldDeclaration>> fieldsOf(ClassDeclaration clazz) =>
      classIntrospector.fieldsOf(clazz);

  @override
  Future<List<ClassDeclaration>> interfacesOf(ClassDeclaration clazz) =>
      classIntrospector.interfacesOf(clazz);

  @override
  Future<List<MethodDeclaration>> methodsOf(ClassDeclaration clazz) =>
      classIntrospector.methodsOf(clazz);

  @override
  Future<List<ClassDeclaration>> mixinsOf(ClassDeclaration clazz) =>
      classIntrospector.mixinsOf(clazz);

  @override
  Future<TypeDeclaration> declarationOf(NamedStaticType annotation) =>
      typeDeclarationResolver.declarationOf(annotation);

  @override
  Future<ClassDeclaration?> superclassOf(ClassDeclaration clazz) =>
      classIntrospector.superclassOf(clazz);

  @override
  StaticType resolve(TypeAnnotation typeAnnotation) =>
      typeResolver.resolve(typeAnnotation);
}
