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
    },
    jsonSerializableUri: {
      'FromJson': fromJsonMacroIdentifier,
      'ToJson': toJsonMacroIdentifier,
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
  final instantiateBenchmark =
      InstantiateBenchmark(executor, macroUri, 'JsonSerializable');
  await instantiateBenchmark.report();
  final instanceId = instantiateBenchmark.instanceIdentifier;
  final declarationsBenchmark = JsonSerializableDeclarationsPhaseBenchmark(
      executor, macroUri, instanceId, introspector);
  await declarationsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (declarationsBenchmark.result != null) declarationsBenchmark.result!],
      identifierDeclarations);

  introspector.constructors[myClass] = myClassConstructors;
  introspector.methods[myClass] = myClassMethods;

  final fromJsonInstantiateBenchmark =
      InstantiateBenchmark(executor, macroUri, 'FromJson');
  await fromJsonInstantiateBenchmark.report();
  final fromJsonDefinitionsBenchmark = FromJsonDefinitionPhaseBenchmark(
      executor,
      macroUri,
      fromJsonInstantiateBenchmark.instanceIdentifier,
      introspector);
  await fromJsonDefinitionsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [
        if (fromJsonDefinitionsBenchmark.result != null)
          fromJsonDefinitionsBenchmark.result!
      ],
      identifierDeclarations);

  final toJsonInstantiateBenchmark =
      InstantiateBenchmark(executor, macroUri, 'ToJson');
  await toJsonInstantiateBenchmark.report();
  final toJsonDefinitionsBenchmark = ToJsonDefinitionPhaseBenchmark(executor,
      macroUri, toJsonInstantiateBenchmark.instanceIdentifier, introspector);
  await toJsonDefinitionsBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [
        if (toJsonDefinitionsBenchmark.result != null)
          toJsonDefinitionsBenchmark.result!
      ],
      identifierDeclarations);
}

class InstantiateBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  late MacroInstanceIdentifier instanceIdentifier;
  final String macroName;

  InstantiateBenchmark(this.executor, this.macroUri, this.macroName)
      : super('${macroName}Instantiate');

  Future<void> run() async {
    instanceIdentifier = await executor.instantiateMacro(
        macroUri, macroName, '', Arguments([], {}));
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

class FromJsonDefinitionPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final DefinitionPhaseIntrospector introspector;

  MacroExecutionResult? result;

  FromJsonDefinitionPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('FromJsonDefinitionPhase');

  Future<void> run() async {
    result = null;
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.constructor, Phase.definitions)) {
      result = await executor.executeDefinitionsPhase(
          instanceIdentifier, myClassConstructors.single, introspector);
    }
  }
}

class ToJsonDefinitionPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final DefinitionPhaseIntrospector introspector;

  MacroExecutionResult? result;

  ToJsonDefinitionPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('ToJsonDefinitionPhase');

  Future<void> run() async {
    result = null;
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.method, Phase.definitions)) {
      result = await executor.executeDefinitionsPhase(
          instanceIdentifier, myClassMethods.single, introspector);
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

final myClassMethods = [
  MethodDeclarationImpl(
      id: RemoteInstance.uniqueId,
      identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: 'toJson'),
      isGetter: false,
      isOperator: false,
      isSetter: false,
      isStatic: false,
      library: fooLibrary,
      metadata: [],
      hasBody: false,
      hasExternal: false,
      namedParameters: [],
      positionalParameters: [],
      returnType: NamedTypeAnnotationImpl(
          id: RemoteInstance.uniqueId,
          isNullable: false,
          identifier: mapIdentifier,
          typeArguments: [stringType, dynamicType]),
      typeParameters: [],
      definingType: myClass.identifier),
];

final jsonSerializableUri =
    Uri.parse('package:macro_proposal/json_serializable.dart');

final fromJsonMacroIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'FromJson');
final toJsonMacroIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'ToJson');
