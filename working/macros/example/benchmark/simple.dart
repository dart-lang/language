// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Run this script to print out the generated augmentation library for an
// example class, created with fake data, and get some basic timing info:
//
//   dart benchmark/simple.dart
//
// You can also compile this benchmark to exe and run it as follows:
//
//   dart compile exe benchmark/simple.dart && ./benchmark/simple.exe
//
// Pass `--help` for usage and configuration options.
library language.working.macros.benchmark.simple;

import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_style/dart_style.dart';

// There is no public API exposed yet, the in progress api lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

// Private impls used actually execute the macro
import 'package:_fe_analyzer_shared/src/macros/bootstrap.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/serialization.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/isolated_executor.dart'
    as isolatedExecutor;
import 'package:_fe_analyzer_shared/src/macros/executor/process_executor.dart'
    as processExecutor;

final _watch = Stopwatch()..start();
void _log(String message) {
  print('${_watch.elapsed}: $message');
}

final argParser = ArgParser()
  ..addOption('serialization-strategy',
      allowed: ['bytedata', 'json'],
      defaultsTo: 'bytedata',
      help: 'The serialization strategy to use when talking to macro programs.')
  ..addOption('macro-execution-strategy',
      allowed: ['aot', 'isolate'],
      defaultsTo: 'aot',
      help: 'The execution strategy for precompiled macros.')
  ..addFlag('help', negatable: false, hide: true);

// Run this script to print out the generated augmentation library for an example class.
void main(List<String> args) async {
  var parsedArgs = argParser.parse(args);

  if (parsedArgs['help'] == true) {
    print(argParser.usage);
    return;
  }

  // Set up all of our options
  var parsedSerializationStrategy =
      parsedArgs['serialization-strategy'] as String;
  SerializationMode clientSerializationMode;
  SerializationMode serverSerializationMode;
  switch (parsedSerializationStrategy) {
    case 'bytedata':
      clientSerializationMode = SerializationMode.byteDataClient;
      serverSerializationMode = SerializationMode.byteDataServer;
      break;
    case 'json':
      clientSerializationMode = SerializationMode.jsonClient;
      serverSerializationMode = SerializationMode.jsonServer;
      break;
    default:
      throw ArgumentError(
          'Unrecognized serialization mode $parsedSerializationStrategy');
  }

  var macroExecutionStrategy = parsedArgs['macro-execution-strategy'] as String;
  var hostMode = Platform.script.path.endsWith('.dart') ||
          Platform.script.path.endsWith('.dill')
      ? 'jit'
      : 'aot';
  _log('''
Running with the following options:

Serialization strategy: $parsedSerializationStrategy
Macro execution strategy: $macroExecutionStrategy
Host app mode: $hostMode
''');

  // You must run from the `macros` directory, paths are relative to that.
  var dataClassFile = File('lib/data_class.dart');
  if (!dataClassFile.existsSync()) {
    print('This script must be ran from the `macros` directory.');
    exit(1);
  }
  var tmpDir = Directory.systemTemp.createTempSync('data_class_macro_example');
  try {
    var macroUri = Uri.parse('package:macro_proposal/data_class.dart');
    var macroName = 'DataClass';

    var bootstrapContent = bootstrapMacroIsolate({
      macroUri.toString(): {
        macroName: [''],
      }
    }, clientSerializationMode);

    var bootstrapFile = File(tmpDir.uri.resolve('main.dart').toFilePath())
      ..writeAsStringSync(bootstrapContent);
    var kernelOutputFile =
        File(tmpDir.uri.resolve('main.dart.dill').toFilePath());
    _log('Compiling DataClass macro');
    var buildSnapshotResult = await Process.run('dart', [
      'compile',
      macroExecutionStrategy == 'aot' ? 'exe' : 'jit-snapshot',
      '--packages=.dart_tool/package_config.json',
      '--enable-experiment=macros',
      '-o',
      kernelOutputFile.uri.toFilePath(),
      bootstrapFile.uri.toFilePath(),
    ]);

    if (buildSnapshotResult.exitCode != 0) {
      print('Failed to build macro boostrap isolate:\n'
          'stdout: ${buildSnapshotResult.stdout}\n'
          'stderr: ${buildSnapshotResult.stderr}');
      exit(1);
    }

    _log('Loading the macro executor');
    var executor = macroExecutionStrategy == 'aot'
        ? await processExecutor.start(
            serverSerializationMode,
            processExecutor.CommunicationChannel.socket,
            kernelOutputFile.uri.toFilePath())
        : await isolatedExecutor.start(
            serverSerializationMode, kernelOutputFile.uri);

    _log('Instantiating macro');
    var instanceId = await executor.instantiateMacro(
        macroUri, macroName, '', Arguments([], {}));

    _log('Running DataClass macro 100 times...');
    var results = <MacroExecutionResult>[];
    var macroExecutionStart = _watch.elapsed;
    late Duration firstRunEnd;
    late Duration first11RunsEnd;
    for (var i = 1; i <= 111; i++) {
      var _shouldLog = i == 1 || i == 11 || i == 111;
      if (_shouldLog) _log('Running DataClass macro for the ${i}th time');
      if (instanceId.shouldExecute(DeclarationKind.classType, Phase.types)) {
        if (_shouldLog) _log('Running types phase');
        var result = await executor.executeTypesPhase(
            instanceId, myClass, SimpleIdentifierResolver());
        if (i == 1) results.add(result);
      }
      if (instanceId.shouldExecute(
          DeclarationKind.classType, Phase.declarations)) {
        if (_shouldLog) _log('Running declarations phase');
        var result = await executor.executeDeclarationsPhase(
            instanceId,
            myClass,
            SimpleIdentifierResolver(),
            SimpleTypeDeclarationResolver(),
            SimpleTypeResolver(),
            SimpleTypeIntrospector());
        if (i == 1) results.add(result);
      }
      if (instanceId.shouldExecute(
          DeclarationKind.classType, Phase.definitions)) {
        if (_shouldLog) _log('Running definitions phase');
        var result = await executor.executeDefinitionsPhase(
            instanceId,
            myClass,
            SimpleIdentifierResolver(),
            SimpleTypeDeclarationResolver(),
            SimpleTypeResolver(),
            SimpleTypeIntrospector(),
            FakeTypeInferrer());
        if (i == 1) results.add(result);
      }
      if (_shouldLog) _log('Done running DataClass macro for the ${i}th time.');

      if (i == 1) {
        firstRunEnd = _watch.elapsed;
      } else if (i == 11) {
        first11RunsEnd = _watch.elapsed;
      }
    }
    var first111RunsEnd = _watch.elapsed;

    _log('Building augmentation library');
    var library = executor.buildAugmentationLibrary(
        results,
        (identifier) => identifier == myClass.identifier
            ? myClass
            : throw UnsupportedError('Can only resolve myClass'), (identifier) {
      if (['bool', 'Object', 'String', 'int'].contains(identifier.name)) {
        return ResolvedIdentifier(
            kind: IdentifierKind.topLevelMember,
            name: identifier.name,
            staticScope: null,
            uri: null);
      } else {
        return ResolvedIdentifier(
            kind: identifier.name == 'MyClass'
                ? IdentifierKind.topLevelMember
                : IdentifierKind.instanceMember,
            name: identifier.name,
            staticScope: null,
            uri: Uri.parse('package:app/main.dart'));
      }
    },
        (annotation) =>
            throw UnsupportedError('Omitted types are not supported!'));
    executor.close();
    _log('Formatting augmentation library');
    var formatted = DartFormatter()
        .format(library
            // comment out the `augment` keywords temporarily
            .replaceAll('augment', '/*augment*/'))
        .replaceAll('/*augment*/', 'augment');

    _log('Macro augmentation library:\n\n$formatted');
    _log('Time for the first run: ${macroExecutionStart - firstRunEnd}');
    _log('Average time for the next 10 runs: '
        '${(first11RunsEnd - firstRunEnd).dividedBy(10)}');
    _log('Average time for the next 100 runs: '
        '${(first111RunsEnd - first11RunsEnd).dividedBy(100)}');
  } finally {
    tmpDir.deleteSync(recursive: true);
  }
}

final boolIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'bool');
final intIdentifier = IdentifierImpl(id: RemoteInstance.uniqueId, name: 'int');
final objectIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Object');
final stringIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'String');

final boolType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    identifier: boolIdentifier,
    isNullable: false,
    typeArguments: const []);
final intType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    identifier: intIdentifier,
    isNullable: false,
    typeArguments: const []);
final stringType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    identifier: stringIdentifier,
    isNullable: false,
    typeArguments: const []);

final objectClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: objectIdentifier,
    interfaces: [],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: false,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null,
    typeParameters: []);

final myClassIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'MyClass');
final myClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: myClassIdentifier,
    interfaces: [],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: false,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: NamedTypeAnnotationImpl(
      id: RemoteInstance.uniqueId,
      isNullable: false,
      identifier: objectIdentifier,
      typeArguments: [],
    ),
    typeParameters: []);

final myClassFields = [
  FieldDeclarationImpl(
      definingType: myClassIdentifier,
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'myString'),
      isExternal: false,
      isFinal: true,
      isLate: false,
      isStatic: false,
      type: stringType),
  FieldDeclarationImpl(
      definingType: myClassIdentifier,
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'myBool'),
      isExternal: false,
      isFinal: true,
      isLate: false,
      isStatic: false,
      type: boolType),
];

final myClassMethods = [
  MethodDeclarationImpl(
    definingType: myClassIdentifier,
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: '=='),
    isAbstract: false,
    isExternal: false,
    isGetter: false,
    isOperator: true,
    isSetter: false,
    isStatic: false,
    namedParameters: [],
    positionalParameters: [
      ParameterDeclarationImpl(
        id: RemoteInstance.uniqueId,
        identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'other'),
        isNamed: false,
        isRequired: true,
        type: NamedTypeAnnotationImpl(
            id: RemoteInstance.uniqueId,
            identifier: objectIdentifier,
            isNullable: false,
            typeArguments: const []),
      )
    ],
    returnType: boolType,
    typeParameters: [],
  ),
  MethodDeclarationImpl(
    definingType: myClassIdentifier,
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'hashCode'),
    isAbstract: false,
    isExternal: false,
    isOperator: false,
    isGetter: true,
    isSetter: false,
    isStatic: false,
    namedParameters: [],
    positionalParameters: [],
    returnType: intType,
    typeParameters: [],
  ),
  MethodDeclarationImpl(
    definingType: myClassIdentifier,
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'toString'),
    isAbstract: false,
    isExternal: false,
    isGetter: false,
    isOperator: false,
    isSetter: false,
    isStatic: false,
    namedParameters: [],
    positionalParameters: [],
    returnType: stringType,
    typeParameters: [],
  ),
];

abstract class Fake {
  @override
  void noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Returns data as if everything was [myClass].
class SimpleTypeIntrospector implements TypeIntrospector {
  @override
  Future<List<ConstructorDeclaration>> constructorsOf(
          IntrospectableType type) async =>
      [];

  @override
  Future<List<FieldDeclaration>> fieldsOf(IntrospectableType type) async =>
      type == myClass ? myClassFields : [];

  @override
  Future<List<MethodDeclaration>> methodsOf(IntrospectableType type) async =>
      type == myClass ? myClassMethods : [];

  @override
  Future<List<EnumValueDeclaration>> valuesOf(
          IntrospectableEnumDeclaration type) async =>
      [];
}

/// This is a very basic identifier resolver, it does no actual resolution.
class SimpleIdentifierResolver implements IdentifierResolver {
  /// Just returns a new [Identifier] whose name is [name].
  @override
  Future<Identifier> resolveIdentifier(Uri library, String name) async =>
      IdentifierImpl(id: RemoteInstance.uniqueId, name: name);
}

class SimpleTypeDeclarationResolver implements TypeDeclarationResolver {
  @override
  Future<TypeDeclaration> declarationOf(covariant Identifier identifier) async {
    if (identifier == myClass.identifier) {
      return myClass;
    } else if (identifier == objectClass.identifier) {
      return objectClass;
    } else {
      throw UnsupportedError('Could not resolve identifier ${identifier.name}');
    }
  }
}

class FakeTypeInferrer extends Fake implements TypeInferrer {}

/// Only supports named types with no type arguments.
class SimpleTypeResolver implements TypeResolver {
  @override
  Future<StaticType> resolve(TypeAnnotationCode type) async {
    if (type is! NamedTypeAnnotationCode) {
      throw UnsupportedError('Only named type annotations are supported');
    }
    if (type.typeArguments.isNotEmpty) {
      throw UnsupportedError('Type arguments are not supported');
    }
    return SimpleNamedStaticType(type.name.name, isNullable: type.isNullable);
  }
}

/// Only supports exact matching, and only goes off of the name and nullability.
class SimpleNamedStaticType implements NamedStaticType {
  final bool isNullable;
  final String name;

  SimpleNamedStaticType(this.name, {this.isNullable = false});

  @override
  Future<bool> isExactly(covariant SimpleNamedStaticType other) async =>
      isNullable == other.isNullable && name == other.name;

  @override
  Future<bool> isSubtypeOf(covariant StaticType other) =>
      throw UnimplementedError();
}

extension _ on Duration {
  Duration dividedBy(int amount) =>
      Duration(microseconds: (this.inMicroseconds / amount).round());
}
