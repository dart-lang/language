import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:benchmark_harness/benchmark_harness.dart';

import 'shared.dart';

Future<void> runBenchmarks(MacroExecutor executor, Uri macroUri) async {
  final introspector = SimpleDefinitionPhaseIntrospector(declarations: {
    myClass.identifier: myClass,
    objectClass.identifier: objectClass,
    myExtension.identifier: myExtension,
  }, identifiers: {
    Uri.parse('dart:core'): {
      'bool': boolIdentifier,
      'int': intIdentifier,
      'Object': objectIdentifier,
      'String': stringIdentifier,
    },
    Uri.parse('package:checks/checks.dart'): {
      'Subject': subjectIdentifier,
    },
    Uri.parse('package:macro_proposal/checks_extensions.dart'): {
      'ChecksExtension': checksExtensionIdentifier,
    },
  }, constructors: {}, enumValues: {}, fields: {
    myClass: myClassFields
  }, methods: {});
  final identifierDeclarations = {
    ...introspector.declarations,
    for (final constructors in introspector.constructors.values)
      for (final constructor in constructors)
        constructor.identifier: constructor,
    for (final methods in introspector.methods.values)
      for (final method in methods) method.identifier: method,
    for (final fields in introspector.fields.values)
      for (final field in fields) field.identifier: field,
  };
  final checksExtensionsInstantiateBenchmark =
      ChecksExtensionsInstantiateBenchmark(executor, macroUri);
  await checksExtensionsInstantiateBenchmark.report();
  final checksExtensionsInstanceId =
      checksExtensionsInstantiateBenchmark.instanceIdentifier;
  final typesBenchmark = ChecksExtensionsTypesPhaseBenchmark(
      executor, macroUri, checksExtensionsInstanceId, introspector);
  await typesBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (typesBenchmark.result != null) typesBenchmark.result!],
      identifierDeclarations);

  final checksExtensionInstantiateBenchmark =
      ChecksExtensionInstantiateBenchmark(executor, macroUri);
  await checksExtensionInstantiateBenchmark.report();
  final checksExtensionInstanceId =
      checksExtensionInstantiateBenchmark.instanceIdentifier;
  final declarationsBenchmark = ChecksExtensionDeclarationsPhaseBenchmark(
      executor, macroUri, checksExtensionInstanceId, introspector);
  await declarationsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (declarationsBenchmark.result != null) declarationsBenchmark.result!],
      identifierDeclarations);
}

class ChecksExtensionsInstantiateBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  late MacroInstanceIdentifier instanceIdentifier;

  ChecksExtensionsInstantiateBenchmark(this.executor, this.macroUri)
      : super('ChecksExtensionsInstantiate');

  Future<void> run() async {
    instanceIdentifier = await executor.instantiateMacro(
        macroUri,
        'ChecksExtensions',
        '',
        Arguments([
          ListArgument([TypeAnnotationArgument(myClassType)],
              [ArgumentKind.typeAnnotation])
        ], {}));
  }
}

class ChecksExtensionsTypesPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final TypePhaseIntrospector introspector;
  MacroExecutionResult? result;

  ChecksExtensionsTypesPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('ChecksExtensionsTypesPhase');

  Future<void> run() async {
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.library, Phase.types)) {
      result = await executor.executeTypesPhase(
          instanceIdentifier, fooLibrary, introspector);
    }
  }
}

class ChecksExtensionInstantiateBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  late MacroInstanceIdentifier instanceIdentifier;

  ChecksExtensionInstantiateBenchmark(this.executor, this.macroUri)
      : super('ChecksExtensionsInstantiate');

  Future<void> run() async {
    instanceIdentifier = await executor.instantiateMacro(
        macroUri, 'ChecksExtension', '', Arguments([], {}));
  }
}

class ChecksExtensionDeclarationsPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final DeclarationPhaseIntrospector introspector;

  MacroExecutionResult? result;

  ChecksExtensionDeclarationsPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('ChecksExtensionDeclarationsPhase');

  Future<void> run() async {
    result = null;
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.extension, Phase.declarations)) {
      result = await executor.executeDeclarationsPhase(
          instanceIdentifier, myExtension, introspector);
    }
  }
}

final myClassIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'MyClass');
final myClassType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    isNullable: false,
    identifier: myClassIdentifier,
    typeArguments: const []);
final myClass = ClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: myClassIdentifier,
    library: fooLibrary,
    metadata: [],
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
    library: fooLibrary,
    metadata: [],
    hasAbstract: false,
    hasConst: false,
    hasExternal: false,
    hasFinal: true,
    hasInitializer: false,
    hasLate: false,
    hasStatic: false,
    type: stringType,
  ),
  FieldDeclarationImpl(
    definingType: myClassIdentifier,
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'myBool'),
    library: fooLibrary,
    metadata: [],
    hasAbstract: false,
    hasConst: false,
    hasExternal: false,
    hasFinal: true,
    hasInitializer: false,
    hasLate: false,
    hasStatic: false,
    type: boolType,
  ),
];

final myExtension = ExtensionDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier:
        IdentifierImpl(id: RemoteInstance.uniqueId, name: 'MyClassChecks'),
    library: fooLibrary,
    metadata: const [],
    typeParameters: const [],
    onType: NamedTypeAnnotationImpl(
        id: RemoteInstance.uniqueId,
        isNullable: false,
        identifier: subjectIdentifier,
        typeArguments: [myClassType]));

final subjectIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Subject');
final checksExtensionIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'ChecksExtension');
