import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:benchmark_harness/benchmark_harness.dart';

import 'checks_extensions.dart';
import 'shared.dart';

Future<void> runBenchmarks(MacroExecutor executor, Uri macroUri) async {
  final introspector = SimpleDefinitionPhaseIntrospector(declarations: {
    myClass.identifier: myClass,
    objectClass.identifier: objectClass,
    boolClass.identifier: boolClass,
    intClass.identifier: intClass,
    stringClass.identifier: stringClass,
  }, identifiers: {
    Uri.parse('dart:core'): {
      'bool': boolIdentifier,
      'int': intIdentifier,
      'dynamic': dynamicIdentifeir,
      'String': stringIdentifier,
      'Map': mapIdentifier,
      'Object': objectIdentifier,
    }
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
  final instantiateBenchmark =
      JsonSerializableInstantiateBenchmark(executor, macroUri);
  await instantiateBenchmark.report();
  final instanceId = instantiateBenchmark.instanceIdentifier;
  final typesBenchmark = JsonSerializableTypesPhaseBenchmark(
      executor, macroUri, instanceId, introspector);
  await typesBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (typesBenchmark.result != null) typesBenchmark.result!],
      identifierDeclarations);
  final declarationsBenchmark = JsonSerializableDeclarationsPhaseBenchmark(
      executor, macroUri, instanceId, introspector);
  await declarationsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (declarationsBenchmark.result != null) declarationsBenchmark.result!],
      identifierDeclarations);
  introspector.constructors[myClass] = myClassConstructors;
  final definitionsBenchmark = JsonSerializableDefinitionPhaseBenchmark(
      executor, macroUri, instanceId, introspector);
  await definitionsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (definitionsBenchmark.result != null) definitionsBenchmark.result!],
      identifierDeclarations);
}

class JsonSerializableInstantiateBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  late MacroInstanceIdentifier instanceIdentifier;

  JsonSerializableInstantiateBenchmark(this.executor, this.macroUri)
      : super('JsonSerializableInstantiate');

  Future<void> run() async {
    instanceIdentifier = await executor.instantiateMacro(
        macroUri, 'JsonSerializable', '', Arguments([], {}));
  }
}

class JsonSerializableTypesPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final TypePhaseIntrospector introspector;
  MacroExecutionResult? result;

  JsonSerializableTypesPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('JsonSerializableTypesPhase');

  Future<void> run() async {
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.types)) {
      result = await executor.executeTypesPhase(
          instanceIdentifier, myClass, introspector);
    }
  }
}

class JsonSerializableDeclarationsPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final DeclarationPhaseIntrospector introspector;

  MacroExecutionResult? result;

  JsonSerializableDeclarationsPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('JsonSerializableDeclarationsPhase');

  Future<void> run() async {
    result = null;
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.declarations)) {
      result = await executor.executeDeclarationsPhase(
          instanceIdentifier, myClass, introspector);
    }
  }
}

class JsonSerializableDefinitionPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final DefinitionPhaseIntrospector introspector;

  MacroExecutionResult? result;

  JsonSerializableDefinitionPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('JsonSerializableDefinitionPhase');

  Future<void> run() async {
    result = null;
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.definitions)) {
      result = await executor.executeDefinitionsPhase(
          instanceIdentifier, myClass, introspector);
    }
  }
}

final myClassIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'MyClass');
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
      hasExternal: false,
      hasFinal: true,
      hasLate: false,
      isStatic: false,
      type: stringType),
  FieldDeclarationImpl(
      definingType: myClassIdentifier,
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'myBool'),
      library: fooLibrary,
      metadata: [],
      hasAbstract: false,
      hasExternal: false,
      hasFinal: true,
      hasLate: false,
      isStatic: false,
      type: boolType),
];

final myClassConstructors = [
  ConstructorDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'fromJson'),
      library: fooLibrary,
      metadata: [],
      hasBody: false,
      hasExternal: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier:
                IdentifierImpl(id: RemoteInstance.uniqueId, name: 'json'),
            library: fooLibrary,
            metadata: [],
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: mapIdentifier,
                typeArguments: [stringType, dynamicType]))
      ],
      returnType: myClassType,
      typeParameters: [],
      definingType: myClass.identifier,
      isFactory: true),
];
