// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Run this script to print out the generated augmentation library for an
// example class.
//
// This is primarily for illustration purposes, so we can get an idea of how
// things would work on a real-ish example.
library language.working.macros.example.run;

import 'dart:io';
import 'dart:isolate';

import 'package:dart_style/dart_style.dart';

// There is no public API exposed yet, the in progress api lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

// Private impls used actually execute the macro
import 'package:_fe_analyzer_shared/src/macros/bootstrap.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:_fe_analyzer_shared/src/macros/executor_shared/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor_shared/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/isolated_executor/isolated_executor.dart'
    as isolatedExecutor;

final _watch = Stopwatch()..start();
void _log(String message) {
  print('${_watch.elapsed}: $message');
}

// Run this script to print out the generated augmentation library for an example class.
void main() async {
  _log('Preparing to run macros.');
  // You must run from the `macros` directory, paths are relative to that.
  var thisFile = File('example/data_class.dart');
  if (!thisFile.existsSync()) {
    print('This script must be ran from the `macros` directory.');
    exit(1);
  }
  var executor = await isolatedExecutor.start();
  var tmpDir = Directory.systemTemp.createTempSync('data_class_macro_example');
  try {
    var macroUri = thisFile.absolute.uri;
    var macroName = 'DataClass';

    var bootstrapContent = bootstrapMacroIsolate({
      macroUri.toString(): {
        macroName: [''],
      }
    });

    var bootstrapFile = File(tmpDir.uri.resolve('main.dart').toFilePath())
      ..writeAsStringSync(bootstrapContent);
    var kernelOutputFile =
        File(tmpDir.uri.resolve('main.dart.dill').toFilePath());
    _log('Compiling DataClass macro');
    var buildSnapshotResult = await Process.run(Platform.resolvedExecutable, [
      '--snapshot=${kernelOutputFile.uri.toFilePath()}',
      '--snapshot-kind=kernel',
      '--packages=${(await Isolate.packageConfig)!}',
      bootstrapFile.uri.toFilePath(),
    ]);

    if (buildSnapshotResult.exitCode != 0) {
      print('Failed to build macro boostrap isolate:\n'
          'stdout: ${buildSnapshotResult.stdout}\n'
          'stderr: ${buildSnapshotResult.stderr}');
      exit(1);
    }

    _log('Loading DataClass macro');
    var clazzId = await executor.loadMacro(macroUri, macroName,
        precompiledKernelUri: kernelOutputFile.uri);
    var instanceId =
        await executor.instantiateMacro(clazzId, '', Arguments([], {}));

    _log('Running DataClass macro 100 times...');
    var results = <MacroExecutionResult>[];
    for (var i = 1; i < 101; i++) {
      var _shouldLog = i == 1 || i == 10 || i == 100;
      if (_shouldLog) _log('Running DataClass macro for the ${i}th time');
      if (instanceId.shouldExecute(DeclarationKind.clazz, Phase.types)) {
        if (_shouldLog) _log('Running types phase');
        var result = await executor.executeTypesPhase(instanceId, myClass);
        if (i == 1) results.add(result);
      }
      if (instanceId.shouldExecute(DeclarationKind.clazz, Phase.declarations)) {
        if (_shouldLog) _log('Running declarations phase');
        var result = await executor.executeDeclarationsPhase(
            instanceId, myClass, FakeTypeResolver(), FakeClassIntrospector());
        if (i == 1) results.add(result);
      }
      if (instanceId.shouldExecute(DeclarationKind.clazz, Phase.definitions)) {
        if (_shouldLog) _log('Running definitions phase');
        var result = await executor.executeDefinitionsPhase(
            instanceId,
            myClass,
            FakeTypeResolver(),
            FakeClassIntrospector(),
            FakeTypeDeclarationResolver());
        if (i == 1) results.add(result);
      }
      if (_shouldLog) _log('Done running DataClass macro for the ${i}th time.');
    }

    _log('Building augmentation library');
    var library = executor.buildAugmentationLibrary(results, (identifier) {
      if (identifier == boolIdentifier ||
          identifier == objectIdentifier ||
          identifier == stringIdentifier ||
          identifier == intIdentifier) {
        return Uri(scheme: 'dart', path: 'core');
      } else {
        return File('example/data_class.dart').absolute.uri;
      }
    });
    executor.close();
    _log('Formatting augmentation library');
    var formatted = DartFormatter()
        .format(library
            // comment out the `augment` keywords temporarily
            .replaceAll('augment', '/*augment*/'))
        .replaceAll('/*augment*/', 'augment');

    _log('Macro augmentation library:\n\n$formatted');
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
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'bool');

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

final objectClass = ClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: objectIdentifier,
    interfaces: [],
    isAbstract: false,
    isExternal: false,
    mixins: [],
    superclass: null,
    typeParameters: []);

final myClassIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'MyClass');
final myClass = ClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: myClassIdentifier,
    interfaces: [],
    isAbstract: false,
    isExternal: false,
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
      definingClass: myClassIdentifier,
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'myString'),
      initializer: null,
      isExternal: false,
      isFinal: true,
      isLate: false,
      type: stringType),
  FieldDeclarationImpl(
      definingClass: myClassIdentifier,
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'myBool'),
      initializer: null,
      isExternal: false,
      isFinal: true,
      isLate: false,
      type: boolType),
];

final myClassMethods = [
  MethodDeclarationImpl(
    definingClass: myClassIdentifier,
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: '=='),
    isAbstract: false,
    isExternal: false,
    isGetter: false,
    isOperator: true,
    isSetter: false,
    namedParameters: [],
    positionalParameters: [
      ParameterDeclarationImpl(
        defaultValue: null,
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
    definingClass: myClassIdentifier,
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'hashCode'),
    isAbstract: false,
    isExternal: false,
    isOperator: false,
    isGetter: true,
    isSetter: false,
    namedParameters: [],
    positionalParameters: [],
    returnType: intType,
    typeParameters: [],
  ),
  MethodDeclarationImpl(
    definingClass: myClassIdentifier,
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'toString'),
    isAbstract: false,
    isExternal: false,
    isGetter: false,
    isOperator: false,
    isSetter: false,
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

class FakeClassIntrospector extends Fake implements ClassIntrospector {
  @override
  Future<List<ConstructorDeclaration>> constructorsOf(
          covariant ClassDeclaration clazz) async =>
      [];

  @override
  Future<List<FieldDeclaration>> fieldsOf(
          covariant ClassDeclaration clazz) async =>
      myClassFields;

  @override
  Future<List<MethodDeclaration>> methodsOf(
          covariant ClassDeclaration clazz) async =>
      myClassMethods;

  @override
  Future<ClassDeclaration?> superclassOf(
          covariant ClassDeclaration clazz) async =>
      clazz == myClass ? objectClass : null;
}

class FakeTypeDeclarationResolver extends Fake
    implements TypeDeclarationResolver {}

class FakeTypeResolver extends Fake implements TypeResolver {}
