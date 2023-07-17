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
  final declarations = <Identifier, Declaration>{};
  final introspector = SimpleDefinitionPhaseIntrospector(
    declarations: declarations,
    identifiers: {
      Uri.parse('package:macro_proposal/injectable.dart'): {
        'Provider': providerIdentifier
      }
    },
    constructors: {
      coffeeMakerClass: coffeeMakerConstructors,
      dripCoffeeComponentClass: dripCoffeeComponentConstructors,
      electricHeaterClass: electricHeaterConstructors,
      thermosiphonClass: thermosiphonConstructors,
    },
    enumValues: {},
    fields: {
      coffeeMakerClass: coffeeMakerFields,
      dripCoffeeComponentClass: [],
      thermosiphonClass: thermosiphonFields,
    },
    methods: {
      coffeeMakerClass: [],
      dripCoffeeModuleClass: dripCoffeeModuleMethods,
      dripCoffeeComponentClass: dripCoffeeComponentMethods,
      electricHeaterClass: [],
      thermosiphonClass: [],
    },
  );
  declarations.addAll({
    ...typeDeclarations,
    for (final constructors in introspector.constructors.values)
      for (final constructor in constructors)
        constructor.identifier: constructor,
    for (final methods in introspector.methods.values)
      for (final method in methods) method.identifier: method,
    for (final fields in introspector.fields.values)
      for (final field in fields) field.identifier: field,
  });
  final instantiateBenchmark =
      InjectableInstantiateBenchmark(executor, macroUri);
  await instantiateBenchmark.report();
  final injectableInstanceIdentifier =
      instantiateBenchmark.injectableInstanceIdentifier;
  final providesInstanceIdentifier =
      instantiateBenchmark.providesInstanceIdentifier;
  final componentInstanceIdentifier =
      instantiateBenchmark.componentInstanceIdentifier;
  final typesBenchmark = InjectableTypesPhaseBenchmark(
      executor,
      macroUri,
      componentInstanceIdentifier,
      injectableInstanceIdentifier,
      providesInstanceIdentifier,
      introspector);
  await typesBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, typesBenchmark.results, declarations);
  final declarationsBenchmark = InjectableDeclarationsPhaseBenchmark(
      executor,
      macroUri,
      componentInstanceIdentifier,
      injectableInstanceIdentifier,
      providesInstanceIdentifier,
      introspector);
  await declarationsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, declarationsBenchmark.results, declarations);

  // Manually add in the generated declarations from the declarations phase.
  introspector.methods[coffeeMakerClass]!.addAll(generatedCoffeeMakerMethods);
  introspector.methods[dripCoffeeModuleClass]!
      .addAll(generatedDripCoffeeModuleMethods);
  introspector.methods[electricHeaterClass]!
      .addAll(generatedElectricHeaterMethods);
  introspector.methods[thermosiphonClass]!.addAll(generatedThermosiphonMethods);
  introspector.fields[dripCoffeeComponentClass]!
      .addAll(generatedDripCoffeeComponentFields);
  introspector.constructors[dripCoffeeComponentClass]!
      .addAll(generatedDripCoffeeComponentConstructors);
  declarations.addAll({
    for (final constructors in introspector.constructors.values)
      for (final constructor in constructors)
        constructor.identifier: constructor,
    for (final fields in introspector.fields.values)
      for (final field in fields) field.identifier: field,
    for (final methods in introspector.methods.values)
      for (final method in methods) method.identifier: method,
  });

  final definitionsBenchmark = InjectableDefinitionPhaseBenchmark(
      executor,
      macroUri,
      componentInstanceIdentifier,
      injectableInstanceIdentifier,
      providesInstanceIdentifier,
      introspector);
  await definitionsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor, definitionsBenchmark.results, declarations);
}

class InjectableInstantiateBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  late MacroInstanceIdentifier injectableInstanceIdentifier;
  late MacroInstanceIdentifier providesInstanceIdentifier;
  late MacroInstanceIdentifier componentInstanceIdentifier;

  InjectableInstantiateBenchmark(this.executor, this.macroUri)
      : super('InjectableInstantiate');

  Future<void> run() async {
    injectableInstanceIdentifier = await executor.instantiateMacro(
        macroUri, 'Injectable', '', Arguments([], {}));
    providesInstanceIdentifier = await executor.instantiateMacro(
        macroUri, 'Provides', '', Arguments([], {}));
    componentInstanceIdentifier = await executor.instantiateMacro(
        macroUri, 'Component', '', Arguments([], {}));
  }
}

class InjectableTypesPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier componentInstanceIdentifier;
  final MacroInstanceIdentifier injectableInstanceIdentifier;
  final MacroInstanceIdentifier providesInstanceIdentifier;
  final TypePhaseIntrospector introspector;
  late List<MacroExecutionResult> results;

  InjectableTypesPhaseBenchmark(
    this.executor,
    this.macroUri,
    this.componentInstanceIdentifier,
    this.injectableInstanceIdentifier,
    this.providesInstanceIdentifier,
    this.introspector,
  ) : super('InjectableTypesPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (injectableInstanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.types)) {
      for (var clazz in injectableClasses) {
        results.add(await executor.executeTypesPhase(
            injectableInstanceIdentifier, clazz, introspector));
      }
    }
    for (var method in dripCoffeeModuleMethods) {
      if (providesInstanceIdentifier.shouldExecute(
          DeclarationKind.method, Phase.types)) {
        results.add(await executor.executeTypesPhase(
            providesInstanceIdentifier, method, introspector));
      }
    }
    if (componentInstanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.types)) {
      results.add(await executor.executeTypesPhase(
          componentInstanceIdentifier, dripCoffeeComponentClass, introspector));
    }
  }
}

class InjectableDeclarationsPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier componentInstanceIdentifier;
  final MacroInstanceIdentifier injectableInstanceIdentifier;
  final MacroInstanceIdentifier providesInstanceIdentifier;
  final DeclarationPhaseIntrospector introspector;

  late List<MacroExecutionResult> results;

  InjectableDeclarationsPhaseBenchmark(
      this.executor,
      this.macroUri,
      this.componentInstanceIdentifier,
      this.injectableInstanceIdentifier,
      this.providesInstanceIdentifier,
      this.introspector)
      : super('InjectableDeclarationsPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (injectableInstanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.declarations)) {
      for (var clazz in injectableClasses) {
        results.add(await executor.executeDeclarationsPhase(
            injectableInstanceIdentifier, clazz, introspector));
      }
    }
    for (var method in dripCoffeeModuleMethods) {
      if (providesInstanceIdentifier.shouldExecute(
          DeclarationKind.method, Phase.declarations)) {
        results.add(await executor.executeDeclarationsPhase(
            providesInstanceIdentifier, method, introspector));
      }
    }
    if (componentInstanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.declarations)) {
      results.add(await executor.executeDeclarationsPhase(
          componentInstanceIdentifier, dripCoffeeComponentClass, introspector));
    }
  }
}

class InjectableDefinitionPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier componentInstanceIdentifier;
  final MacroInstanceIdentifier injectableInstanceIdentifier;
  final MacroInstanceIdentifier providesInstanceIdentifier;
  final DefinitionPhaseIntrospector introspector;

  late List<MacroExecutionResult> results;

  InjectableDefinitionPhaseBenchmark(
      this.executor,
      this.macroUri,
      this.componentInstanceIdentifier,
      this.injectableInstanceIdentifier,
      this.providesInstanceIdentifier,
      this.introspector)
      : super('InjectableDefinitionPhase');

  Future<void> run() async {
    results = <MacroExecutionResult>[];
    if (injectableInstanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.definitions)) {
      for (var clazz in injectableClasses) {
        results.add(await executor.executeDefinitionsPhase(
            injectableInstanceIdentifier, clazz, introspector));
      }
    }
    for (var method in dripCoffeeModuleMethods) {
      if (providesInstanceIdentifier.shouldExecute(
          DeclarationKind.method, Phase.definitions)) {
        results.add(await executor.executeDefinitionsPhase(
            providesInstanceIdentifier, method, introspector));
      }
    }
    if (componentInstanceIdentifier.shouldExecute(
        DeclarationKind.classType, Phase.definitions)) {
      results.add(await executor.executeDefinitionsPhase(
          componentInstanceIdentifier, dripCoffeeComponentClass, introspector));
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
    library: fooLibrary,
    metadata: [],
    typeParameters: [
      TypeParameterDeclarationImpl(
          id: RemoteInstance.uniqueId,
          identifier: providerTypeIdentifier,
          library: fooLibrary,
          metadata: [],
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
    library: fooLibrary,
    metadata: [],
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
    library: fooLibrary,
    metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
final generatedElectricHeaterMethods = [
  // Generated in the declarations phase, looks like:
  // static Provider<ElectricHeater> provider() => () => ElectricHeater();
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'provider'),
      library: fooLibrary,
      metadata: [],
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
          identifier: providerIdentifier,
          typeArguments: [
            NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: electricHeaterIdentifier,
                typeArguments: [])
          ]),
      typeParameters: [],
      definingType: electricHeaterIdentifier,
      isStatic: true),
];

// interface class Pump {}
final pumpIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Pump');
final pumpClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: pumpIdentifier,
    library: fooLibrary,
    metadata: [],
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
    library: fooLibrary,
    metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
            library: fooLibrary,
            metadata: [],
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
final generatedThermosiphonMethods = [
  // Generated in the declarations phase, looks like:
  // static Provider<Thermosiphon> provider(Provider<Heater> heaterProvider) =>
  //     () => Thermosiphon(heaterProvider());
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'provider'),
      library: fooLibrary,
      metadata: [],
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: IdentifierImpl(
                id: RemoteInstance.uniqueId, name: 'heaterProvider'),
            library: fooLibrary,
            metadata: [],
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: providerIdentifier,
                typeArguments: [
                  NamedTypeAnnotationImpl(
                      id: RemoteInstance.uniqueId,
                      isNullable: false,
                      identifier: heaterIdentifier,
                      typeArguments: []),
                ]))
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: providerIdentifier,
          typeArguments: [
            NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: thermosiphonIdentifier,
                typeArguments: [])
          ]),
      typeParameters: [],
      definingType: thermosiphonIdentifier,
      isStatic: true),
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
    library: fooLibrary,
    metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
            library: fooLibrary,
            metadata: [],
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
final generatedCoffeeMakerMethods = [
  // Generated in the declarations phase, looks like
  // static Provider<CoffeeMaker> provider(
  //   Provider<Heater> heaterProvider,
  //   Provider<Pump> pumpProvider) =>
  //     () => CoffeeMaker(heaterProvider(), pumpProvider());
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'provider'),
      library: fooLibrary,
      metadata: [],
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: IdentifierImpl(
                id: RemoteInstance.uniqueId, name: 'heaterProvider'),
            library: fooLibrary,
            metadata: [],
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: providerIdentifier,
                typeArguments: [
                  NamedTypeAnnotationImpl(
                      id: RemoteInstance.uniqueId,
                      isNullable: false,
                      identifier: heaterIdentifier,
                      typeArguments: [])
                ])),
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: IdentifierImpl(
                id: RemoteInstance.uniqueId, name: 'pumpProvider'),
            library: fooLibrary,
            metadata: [],
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: providerIdentifier,
                typeArguments: [
                  NamedTypeAnnotationImpl(
                      id: RemoteInstance.uniqueId,
                      isNullable: false,
                      identifier: pumpIdentifier,
                      typeArguments: [])
                ])),
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: providerIdentifier,
          typeArguments: [
            NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: coffeeMakerIdentifier,
                typeArguments: [])
          ]),
      typeParameters: [],
      definingType: coffeeMakerIdentifier,
      isStatic: true)
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
    library: fooLibrary,
    metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
            library: fooLibrary,
            metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
            library: fooLibrary,
            metadata: [],
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
final generatedDripCoffeeModuleMethods = [
  // Generated in the declarations phase, they look like:
  // Provider<Heater> provideHeaterProvider(Provider<ElectricHeater> provideImpl)
  //     => this.provideHeater(provideImpl());
  // Provider<Pump> providePumpProvider(Provider<Thermosiphon> provideImpl)
  //     => this.providePump(provideImpl());
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(
          id: RemoteInstance.uniqueId, name: 'provideHeaterProvider'),
      library: fooLibrary,
      metadata: [],
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: IdentifierImpl(
                id: RemoteInstance.uniqueId, name: 'provideImpl'),
            library: fooLibrary,
            metadata: [],
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: providerIdentifier,
                typeArguments: [
                  NamedTypeAnnotationImpl(
                      id: RemoteInstance.uniqueId,
                      isNullable: false,
                      identifier: electricHeaterIdentifier,
                      typeArguments: [])
                ]))
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: providerIdentifier,
          typeArguments: [
            NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: heaterIdentifier,
                typeArguments: [])
          ]),
      typeParameters: [],
      definingType: dripCoffeeModuleIdentifier,
      isStatic: false),
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(
          id: RemoteInstance.uniqueId, name: 'providePumpProvider'),
      library: fooLibrary,
      metadata: [],
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: IdentifierImpl(
                id: RemoteInstance.uniqueId, name: 'provideImpl'),
            library: fooLibrary,
            metadata: [],
            isNamed: false,
            isRequired: true,
            type: NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: providerIdentifier,
                typeArguments: [
                  NamedTypeAnnotationImpl(
                      id: RemoteInstance.uniqueId,
                      isNullable: false,
                      identifier: thermosiphonIdentifier,
                      typeArguments: [])
                ]))
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: providerIdentifier,
          typeArguments: [
            NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: pumpIdentifier,
                typeArguments: [])
          ]),
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
    library: fooLibrary,
    metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
      library: fooLibrary,
      metadata: [],
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
            library: fooLibrary,
            metadata: [],
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
// Generated in the declarations phase from the external methods, looks like:
//
// DripCoffeeComponent._(this._coffeeMaker);
final generatedDripCoffeeComponentConstructors = [
  ConstructorDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: '_'),
      library: fooLibrary,
      metadata: [],
      isAbstract: false,
      isExternal: false,
      isGetter: false,
      isOperator: false,
      isSetter: false,
      namedParameters: [],
      positionalParameters: [
        ParameterDeclarationImpl(
            id: RemoteInstance.uniqueId,
            identifier: generatedDripCoffeeComponentFields.first.identifier,
            library: fooLibrary,
            metadata: [],
            isNamed: false,
            isRequired: true,
            type: generatedDripCoffeeComponentFields.first.type),
      ],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: dripCoffeeComponentIdentifier,
          typeArguments: []),
      typeParameters: [],
      definingType: dripCoffeeComponentIdentifier,
      isFactory: false),
];
// Generated in the declarations phase from the external methods, looks like:
//
// final Provider<CoffeeMaker> _coffeeMakerProvider;
final generatedDripCoffeeComponentFields = [
  FieldDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(
          id: RemoteInstance.uniqueId, name: '_coffeeMakerProvider'),
      library: fooLibrary,
      metadata: [],
      isExternal: false,
      isFinal: true,
      isLate: false,
      type: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: providerIdentifier,
          typeArguments: [
            NamedTypeAnnotationImpl(
                id: RemoteInstance.uniqueId,
                isNullable: false,
                identifier: coffeeMakerIdentifier,
                typeArguments: [])
          ]),
      definingType: dripCoffeeComponentIdentifier,
      isStatic: false)
];
