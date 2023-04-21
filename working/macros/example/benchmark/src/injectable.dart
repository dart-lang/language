import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:benchmark_harness/benchmark_harness.dart';

import 'shared.dart';

Future<void> runBenchmarks(MacroExecutor executor, Uri macroUri) async {
  final typeDeclarations = {
    objectClass.identifier: objectClass,
    heaterClass.identifier: heaterClass,
    electricHeaterClass.identifier: electricHeaterClass,
    pumpClass.identifier: pumpClass,
    thermosiphonClass.identifier: thermosiphonClass,
    coffeeMakerClass.identifier: coffeeMakerClass,
    dripCoffeeModuleClass.identifier: dripCoffeeModuleClass,
    dripCoffeeComponentClass.identifier: dripCoffeeComponentClass,
    providerType.identifier: providerType,
  };
  final typeIntrospector = SimpleTypeIntrospector(
    constructors: {
      coffeeMakerClass: coffeeMakerConstructors,
      dripCoffeeComponentClass: dripCoffeeComponentConstructors,
      electricHeaterClass: electricHeaterConstructors,
      thermosiphonClass: thermosiphonConstructors,
    },
    enumValues: {},
    fields: {
      coffeeMakerClass: coffeeMakerFields,
      thermosiphonClass: thermosiphonFields,
    },
    methods: {
      dripCoffeeModuleClass: dripCoffeeModuleMethods,
      dripCoffeeComponentClass: dripCoffeeComponentMethods,
    },
  );
  final typeDeclarationResolver =
      SimpleTypeDeclarationResolver(typeDeclarations);
  final identifierResolver = SimpleIdentifierResolver({
    Uri.parse('package:macro_proposal/injectable.dart'): {
      'Provider': providerIdentifier
    }
  });
  final instantiateBenchmark =
      InjectableInstantiateBenchmark(executor, macroUri);
  await instantiateBenchmark.report();
  final instanceId = instantiateBenchmark.instanceIdentifier;
  final typesBenchmark = InjectableTypesPhaseBenchmark(
      executor, macroUri, identifierResolver, instanceId);
  await typesBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, typesBenchmark.results, typeDeclarations);
  final declarationsBenchmark = InjectableDeclarationsPhaseBenchmark(
      executor,
      macroUri,
      identifierResolver,
      instanceId,
      typeIntrospector,
      typeDeclarationResolver);
  await declarationsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, declarationsBenchmark.results, typeDeclarations);
  final definitionsBenchmark = InjectableDefinitionPhaseBenchmark(
      executor,
      macroUri,
      identifierResolver,
      instanceId,
      typeIntrospector,
      typeDeclarationResolver);
  await definitionsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, definitionsBenchmark.results, typeDeclarations);
}

class InjectableInstantiateBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  late MacroInstanceIdentifier instanceIdentifier;

  InjectableInstantiateBenchmark(this.executor, this.macroUri)
      : super('InjectableInstantiate');

  Future<void> run() async {
    instanceIdentifier = await executor.instantiateMacro(
        macroUri, 'Injectable', '', Arguments([], {}));
  }
}

class InjectableTypesPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final IdentifierResolver identifierResolver;
  final MacroInstanceIdentifier instanceIdentifier;
  late List<MacroExecutionResult> results;

  InjectableTypesPhaseBenchmark(this.executor, this.macroUri,
      this.identifierResolver, this.instanceIdentifier)
      : super('InjectableTypesPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.types)) {
      for (var clazz in injectableClasses) {
        results.add(await executor.executeTypesPhase(
            instanceIdentifier, clazz, identifierResolver));
      }
    }
  }
}

class InjectableDeclarationsPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final IdentifierResolver identifierResolver;
  final MacroInstanceIdentifier instanceIdentifier;
  final TypeIntrospector typeIntrospector;
  final TypeDeclarationResolver typeDeclarationResolver;

  late List<MacroExecutionResult> results;

  InjectableDeclarationsPhaseBenchmark(
      this.executor,
      this.macroUri,
      this.identifierResolver,
      this.instanceIdentifier,
      this.typeIntrospector,
      this.typeDeclarationResolver)
      : super('InjectableDeclarationsPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.declarations)) {
      for (var clazz in injectableClasses) {
        results.add(await executor.executeDeclarationsPhase(
            instanceIdentifier,
            clazz,
            identifierResolver,
            typeDeclarationResolver,
            SimpleTypeResolver(),
            typeIntrospector));
      }
    }
  }
}

class InjectableDefinitionPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final IdentifierResolver identifierResolver;
  final MacroInstanceIdentifier instanceIdentifier;
  final TypeIntrospector typeIntrospector;
  final TypeDeclarationResolver typeDeclarationResolver;

  late List<MacroExecutionResult> results;

  InjectableDefinitionPhaseBenchmark(
      this.executor,
      this.macroUri,
      this.identifierResolver,
      this.instanceIdentifier,
      this.typeIntrospector,
      this.typeDeclarationResolver)
      : super('InjectableDefinitionPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.definitions)) {
      for (var clazz in injectableClasses) {
        results.add(await executor.executeDefinitionsPhase(
            instanceIdentifier,
            clazz,
            identifierResolver,
            typeDeclarationResolver,
            SimpleTypeResolver(),
            typeIntrospector,
            FakeTypeInferrer()));
      }
    }
  }
}

// All the classes that are maked @injectable
final injectableClasses = [
  electricHeaterClass,
  thermosiphonClass,
  coffeeMakerClass
];

// typedef Provider<T> = T Function();
final providerIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Provider');
final providerTypeIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'T');
final providerType = TypeAliasDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: providerIdentifier,
    typeParameters: [
      TypeParameterDeclarationImpl(
          id: RemoteInstance.uniqueId,
          identifier: providerTypeIdentifier,
          bound: null)
    ],
    aliasedType: FunctionTypeAnnotationImpl(
        id: RemoteInstance.uniqueId,
        isNullable: false,
        namedParameters: [],
        positionalParameters: [],
        returnType: NamedTypeAnnotationImpl(
            id: RemoteInstance.uniqueId,
            isNullable: false,
            identifier: providerTypeIdentifier,
            typeArguments: []),
        typeParameters: []));

// interface class Heater {}
final heaterIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Heater');
final heaterClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: heaterIdentifier,
    typeParameters: [],
    interfaces: [],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: true,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null);

// @Injectable()
// class ElectricHeater implements Heater {
//   // TODO: This is required for now.
//   ElectricHeater();
// }
final electricHeaterIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'ElectricHeater');
final electricHeaterClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: electricHeaterIdentifier,
    typeParameters: [],
    interfaces: [
      NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: heaterIdentifier,
          typeArguments: []),
    ],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: false,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null);
final electricHeaterConstructors = [
  ConstructorDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: ''),
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: electricHeaterIdentifier,
          typeArguments: []),
      typeParameters: [],
      definingType: electricHeaterIdentifier,
      isFactory: false)
];

// interface class Pump {}
final pumpIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Pump');
final pumpClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: pumpIdentifier,
    typeParameters: [],
    interfaces: [],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: true,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null);

// @Injectable()
// class Thermosiphon implements Pump {
//   final Heater heater;
//
//   Thermosiphon(this.heater);
// }
final thermosiphonIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Thermosiphon');
final thermosiphonClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: thermosiphonIdentifier,
    typeParameters: [],
    interfaces: [
      NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: pumpIdentifier,
          typeArguments: []),
    ],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: false,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null);
final thermosiphonFields = [
  FieldDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'heater'),
      isExternal: false,
      isFinal: true,
      isLate: false,
      type: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: heaterIdentifier,
          typeArguments: []),
      definingType: thermosiphonIdentifier,
      isStatic: false),
];
final thermosiphonConstructors = [
  ConstructorDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: ''),
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        for (var field in thermosiphonFields)
          ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: field.identifier,
            isNamed: false,
            isRequired: true,
            type: field.type,
          ),
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: thermosiphonIdentifier,
          typeArguments: []),
      typeParameters: [],
      definingType: thermosiphonIdentifier,
      isFactory: false)
];

// @Injectable()
// class CoffeeMaker {
//   final Heater heater;
//   final Pump pump;

//   CoffeeMaker(this.heater, this.pump);
// }
final coffeeMakerIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'CoffeeMaker');
final coffeeMakerClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: coffeeMakerIdentifier,
    typeParameters: [],
    interfaces: [],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: false,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null);
final coffeeMakerFields = [
  FieldDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'heater'),
      isExternal: false,
      isFinal: true,
      isLate: false,
      type: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: heaterIdentifier,
          typeArguments: []),
      definingType: coffeeMakerIdentifier,
      isStatic: false),
  FieldDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'pump'),
      isExternal: false,
      isFinal: true,
      isLate: false,
      type: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: pumpIdentifier,
          typeArguments: []),
      definingType: coffeeMakerIdentifier,
      isStatic: false),
];
final coffeeMakerConstructors = [
  ConstructorDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: ''),
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        for (var field in coffeeMakerFields)
          ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: field.identifier,
            isNamed: false,
            isRequired: true,
            type: field.type,
          ),
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: coffeeMakerIdentifier,
          typeArguments: []),
      typeParameters: [],
      definingType: coffeeMakerIdentifier,
      isFactory: false),
];

// class DripCoffeeModule {
//   @Provides()
//   Heater provideHeater(ElectricHeater impl) => impl;
//   @Provides()
//   Pump providePump(Thermosiphon impl) => impl;
// }
final dripCoffeeModuleIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'DripCoffeeModule');
final dripCoffeeModuleClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: dripCoffeeModuleIdentifier,
    typeParameters: [],
    interfaces: [],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: false,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null);
final dripCoffeeModuleMethods = [
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier:
          IdentifierImpl(id: RemoteInstance.uniqueId, name: 'provideHeater'),
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier:
                IdentifierImpl(id: RemoteInstance.uniqueId, name: 'impl'),
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: electricHeaterIdentifier,
                typeArguments: [])),
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: heaterIdentifier,
          typeArguments: []),
      typeParameters: [],
      definingType: dripCoffeeModuleIdentifier,
      isStatic: false),
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier:
          IdentifierImpl(id: RemoteInstance.uniqueId, name: 'providePump'),
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier:
                IdentifierImpl(id: RemoteInstance.uniqueId, name: 'impl'),
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: thermosiphonIdentifier,
                typeArguments: [])),
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: pumpIdentifier,
          typeArguments: []),
      typeParameters: [],
      definingType: dripCoffeeModuleIdentifier,
      isStatic: false),
];

// @Component(modules: [])
// class DripCoffeeComponent {
//   external CoffeeMaker coffeeMaker();

//   // TODO: Generate this from the modules given above once macro args are
//   // supported.
//   external factory DripCoffeeComponent(DripCoffeeModule dripCoffeeModule);
// }
final dripCoffeeComponentIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'DripCoffeeComponent');
final dripCoffeeComponentClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: dripCoffeeComponentIdentifier,
    typeParameters: [],
    interfaces: [],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: false,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null);
final dripCoffeeComponentMethods = [
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier:
          IdentifierImpl(id: RemoteInstance.uniqueId, name: 'coffeeMaker'),
      isAbstract: false,
      isExternal: true,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: coffeeMakerIdentifier,
          typeArguments: []),
      typeParameters: [],
      definingType: dripCoffeeComponentIdentifier,
      isStatic: false),
];
final dripCoffeeComponentConstructors = [
  ConstructorDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: ''),
      isAbstract: false,
      isExternal: true,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: IdentifierImpl(
                id: RemoteInstance.uniqueId, name: 'dripCoffeeModule'),
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: dripCoffeeModuleIdentifier,
                typeArguments: [])),
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: dripCoffeeComponentIdentifier,
          typeArguments: []),
      typeParameters: [],
      definingType: dripCoffeeComponentIdentifier,
      isFactory: true),
];
