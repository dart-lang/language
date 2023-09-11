import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:benchmark_harness/benchmark_harness.dart';

import 'shared.dart';

Future<void> runBenchmarks(MacroExecutor executor, Uri macroUri) async {
  final introspector = SimpleTypePhaseIntrospector(identifiers: {
    Uri.parse('dart:core'): {
      'int': intIdentifier,
      'String': stringIdentifier,
    },
    Uri.parse('package:flutter/flutter.dart'): {
      'BuildContext': buildContextIdentifier,
      'Widget': widgetIdentifier,
    }
  });
  final identifierDeclarations = <Identifier, Declaration>{};
  final instantiateBenchmark =
      FunctionalWidgetInstantiateBenchmark(executor, macroUri);
  await instantiateBenchmark.report();
  final instanceId = instantiateBenchmark.instanceIdentifier;
  final typesBenchmark = FunctionalWidgetTypesPhaseBenchmark(
      executor, macroUri, instanceId, introspector);
  await typesBenchmark.report();
  BuildAugmentationLibraryBenchmark.reportAndPrint(
      executor,
      [if (typesBenchmark.result != null) typesBenchmark.result!],
      identifierDeclarations);
}

class FunctionalWidgetInstantiateBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  late MacroInstanceIdentifier instanceIdentifier;

  FunctionalWidgetInstantiateBenchmark(this.executor, this.macroUri)
      : super('FunctionalWidgetInstantiate');

  Future<void> run() async {
    instanceIdentifier = await executor.instantiateMacro(
        macroUri, 'FunctionalWidget', '', Arguments([], {}));
  }
}

class FunctionalWidgetTypesPhaseBenchmark extends AsyncBenchmarkBase {
  final MacroExecutor executor;
  final Uri macroUri;
  final MacroInstanceIdentifier instanceIdentifier;
  final TypePhaseIntrospector introspector;
  MacroExecutionResult? result;

  FunctionalWidgetTypesPhaseBenchmark(
      this.executor, this.macroUri, this.instanceIdentifier, this.introspector)
      : super('FunctionalWidgetTypesPhase');

  Future<void> run() async {
    if (instanceIdentifier.shouldExecute(
        DeclarationKind.function, Phase.types)) {
      result = await executor.executeTypesPhase(
          instanceIdentifier, myFunction, introspector);
    }
  }
}

final buildContextIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'BuildContext');
final buildContextType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    isNullable: false,
    identifier: buildContextIdentifier,
    typeArguments: []);
final widgetIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Widget');
final widgetType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    isNullable: false,
    identifier: widgetIdentifier,
    typeArguments: []);
final myFunction = FunctionDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: IdentifierImpl(id: RemoteInstance.uniqueId, name: '_myWidget'),
    library: fooLibrary,
    metadata: [],
    hasAbstract: false,
    hasBody: true,
    hasExternal: false,
    isGetter: false,
    isOperator: false,
    isSetter: false,
    namedParameters: [
      ParameterDeclarationImpl(
          id: RemoteInstance.uniqueId,
          identifier:
              IdentifierImpl(id: RemoteInstance.uniqueId, name: 'title'),
          isNamed: true,
          isRequired: true,
          library: fooLibrary,
          metadata: [],
          type: stringType),
    ],
    positionalParameters: [
      ParameterDeclarationImpl(
          id: RemoteInstance.uniqueId,
          identifier:
              IdentifierImpl(id: RemoteInstance.uniqueId, name: 'context'),
          isNamed: false,
          isRequired: true,
          library: fooLibrary,
          metadata: [],
          type: buildContextType),
      ParameterDeclarationImpl(
          id: RemoteInstance.uniqueId,
          identifier:
              IdentifierImpl(id: RemoteInstance.uniqueId, name: 'count'),
          isNamed: false,
          isRequired: true,
          library: fooLibrary,
          metadata: [],
          type: intType),
    ],
    returnType: widgetType,
    typeParameters: []);
