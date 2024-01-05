import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:benchmark_harness/benchmark_harness.dart';

import 'shared.dart';

Future<void> runBenchmarks(MacroExecutor executor, Uri macroUri) async {
  final introspector = SimpleDefinitionPhaseIntrospector(declarations: {
    myClass.identifier: myClass,
    objectClass.identifier: objectClass
  }, identifiers: {
    Uri.parse('dart:core'): {
      'bool': boolIdentifier,
      'int': intIdentifier,
      'Object': objectIdentifier,
      'String': stringIdentifier,
    }
  }, constructors: {}, enumValues: {}, fields: {
    myClass: myClassFields
  }, methods: {
    myClass: myClassMethods
  });
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
      DataClassInstantiateBenchmark(executor, macroUri);
  await instantiateBenchmark.report();
  final instanceId = instantiateBenchmark.instanceIdentifier;
  final typesBenchmark = DataClassTypesPhaseBenchmark(
      executor, macroUri, instanceId, introspector);
  await typesBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (typesBenchmark.result != null) typesBenchmark.result!],
      identifierDeclarations);
  final declarationsBenchmark = DataClassDeclarationsPhaseBenchmark(
      executor, macroUri, instanceId, introspector);
  await declarationsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (declarationsBenchmark.result != null) declarationsBenchmark.result!],
      identifierDeclarations);
  final definitionsBenchmark = DataClassDefinitionPhaseBenchmark(
      executor, macroUri, instanceId, introspector);
  await definitionsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (definitionsBenchmark.result != null) definitionsBenchmark.result!],
      identifierDeclarations);
}

class DataClassInstantiateBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  late MacroInstanceIdentifier instanceIdentifier;

  DataClassInstantiateBenchmark(this.executor, this.macroUri)
      : super('DataClassInstantiate');

  Future<void> run() async {
    instanceIdentifier = await executor.instantiateMacro(
        macroUri, 'DataClass', '', Arguments([], {}));
  }
}

class DataClassTypesPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final TypePhaseIntrospector introspector;
  MacroExecutionResult? result;

  DataClassTypesPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('DataClassTypesPhase');

  Future<void> run() async {
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.types)) {
      result = await executor.executeTypesPhase(
          instanceIdentifier, myClass, introspector);
    }
  }
}

class DataClassDeclarationsPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final DeclarationPhaseIntrospector introspector;

  MacroExecutionResult? result;

  DataClassDeclarationsPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('DataClassDeclarationsPhase');

  Future<void> run() async {
    result = null;
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.declarations)) {
      result = await executor.executeDeclarationsPhase(
          instanceIdentifier, myClass, introspector);
    }
  }
}

class DataClassDefinitionPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final DefinitionPhaseIntrospector introspector;

  MacroExecutionResult? result;

  DataClassDefinitionPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('DataClassDefinitionPhase');

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

final myClassMethods = [
  MethodDeclarationImpl(
    definingType: myClassIdentifier,
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: '=='),
    library: fooLibrary,
    metadata: [],
    hasBody: true,
    hasExternal: false,
    isGetter: false,
    isOperator: true,
    isSetter: false,
    isStatic: false,
    namedParameters: [],
    positionalParameters: [
      ParameterDeclarationImpl(
        id: RemoteInstance.uniqueId,
        identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'other'),
        library: fooLibrary,
        metadata: [],
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
    library: fooLibrary,
    metadata: [],
    hasBody: true,
    hasExternal: false,
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
    library: fooLibrary,
    metadata: [],
    hasBody: true,
    hasExternal: false,
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
