import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:benchmark_harness/benchmark_harness.dart';

import 'shared.dart';

Future<void> runBenchmarks(MacroExecutor executor, Uri macroUri) async {
  final typeDeclarations = {
    myClass.identifier: myClass,
    objectClass.identifier: objectClass
  };
  final typeIntrospector = SimpleTypeIntrospector(
      constructors: {},
      enumValues: {},
      fields: {myClass: myClassFields},
      methods: {myClass: myClassMethods});
  final typeDeclarationResolver =
      SimpleTypeDeclarationResolver(typeDeclarations);
  final identifierResolver = SimpleIdentifierResolver({
    Uri.parse('dart:core'): {
      'bool': boolIdentifier,
      'int': intIdentifier,
      'Object': objectIdentifier,
      'String': stringIdentifier,
    }
  });
  final identifierDeclarations = {
    ...typeDeclarations,
    for (final constructors in typeIntrospector.constructors.values)
      for (final constructor in constructors)
        constructor.identifier: constructor,
    for (final methods in typeIntrospector.methods.values)
      for (final method in methods) method.identifier: method,
    for (final fields in typeIntrospector.fields.values)
      for (final field in fields) field.identifier: field,
  };
  final instantiateBenchmark =
      DataClassInstantiateBenchmark(executor, macroUri);
  await instantiateBenchmark.report();
  final instanceId = instantiateBenchmark.instanceIdentifier;
  final typesBenchmark = DataClassTypesPhaseBenchmark(
      executor, macroUri, identifierResolver, instanceId);
  await typesBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, typesBenchmark.results, identifierDeclarations);
  final declarationsBenchmark = DataClassDeclarationsPhaseBenchmark(
      executor,
      macroUri,
      identifierResolver,
      instanceId,
      typeIntrospector,
      typeDeclarationResolver);
  await declarationsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, declarationsBenchmark.results, identifierDeclarations);
  final definitionsBenchmark = DataClassDefinitionPhaseBenchmark(
      executor,
      macroUri,
      identifierResolver,
      instanceId,
      typeIntrospector,
      typeDeclarationResolver);
  await definitionsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, definitionsBenchmark.results, identifierDeclarations);
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
  final IdentifierResolver identifierResolver;
  final MacroInstanceIdentifier instanceIdentifier;
  late List<MacroExecutionResult> results;

  DataClassTypesPhaseBenchmark(this.executor, this.macroUri,
      this.identifierResolver, this.instanceIdentifier)
      : super('DataClassTypesPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.types)) {
      var result = await executor.executeTypesPhase(
          instanceIdentifier, myClass, identifierResolver);
      results.add(result);
    }
  }
}

class DataClassDeclarationsPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final IdentifierResolver identifierResolver;
  final MacroInstanceIdentifier instanceIdentifier;
  final TypeIntrospector typeIntrospector;
  final TypeDeclarationResolver typeDeclarationResolver;

  late List<MacroExecutionResult> results;

  DataClassDeclarationsPhaseBenchmark(
      this.executor,
      this.macroUri,
      this.identifierResolver,
      this.instanceIdentifier,
      this.typeIntrospector,
      this.typeDeclarationResolver)
      : super('DataClassDeclarationsPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.declarations)) {
      var result = await executor.executeDeclarationsPhase(
          instanceIdentifier,
          myClass,
          identifierResolver,
          typeDeclarationResolver,
          SimpleTypeResolver(),
          typeIntrospector);
      results.add(result);
    }
  }
}

class DataClassDefinitionPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final IdentifierResolver identifierResolver;
  final MacroInstanceIdentifier instanceIdentifier;
  final TypeIntrospector typeIntrospector;
  final TypeDeclarationResolver typeDeclarationResolver;

  late List<MacroExecutionResult> results;

  DataClassDefinitionPhaseBenchmark(
      this.executor,
      this.macroUri,
      this.identifierResolver,
      this.instanceIdentifier,
      this.typeIntrospector,
      this.typeDeclarationResolver)
      : super('DataClassDefinitionPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.definitions)) {
      var result = await executor.executeDefinitionsPhase(
          instanceIdentifier,
          myClass,
          identifierResolver,
          typeDeclarationResolver,
          SimpleTypeResolver(),
          typeIntrospector,
          FakeTypeInferrer());
      results.add(result);
    }
  }
}

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
