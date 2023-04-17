// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// There is no public API exposed yet, the in progress api lives here.
import 'dart:async';

import 'package:_fe_analyzer_shared/src/macros/api.dart';

/// A [Provider] is just a function with no arguments that returns something
/// of the desired type when invoked.
typedef Provider<T> = T Function();

abstract class Heater {}

@Injectable()
class ElectricHeater implements Heater {
  /// Generated, could be a separate class, extension etc
  static Provider<ElectricHeater> provider() => ElectricHeater.new;
}

abstract class Pump {}

@Injectable()
class Thermosiphon implements Pump {
  final Heater heater;

  Thermosiphon(this.heater);

  /// Generated, could be a separate class, extension etc
  static Provider<Thermosiphon> provider(Provider<Heater> provideHeater) =>
      () => Thermosiphon(provideHeater());
}

@Injectable()
class CoffeeMaker {
  final Heater heater;
  final Pump pump;

  CoffeeMaker(this.heater, this.pump);

  /// Generated, could be a separate class, extension etc
  static Provider<CoffeeMaker> provider(
          Provider<Heater> provideHeater, Provider<Pump> providePump) =>
      () => CoffeeMaker(provideHeater(), providePump());
}

class DripCoffeeModule {
  @Provides()
  Heater provideHeater(ElectricHeater impl) => impl;
  @Provides()
  Pump providePump(Thermosiphon impl) => impl;

  /// Generated, could be in a different class, extension, etc.
  Provider<Heater> provideHeaterProvider(
          Provider<ElectricHeater> provideElectricHeater) =>
      () => provideHeater(provideElectricHeater());

  Provider<Pump> providePumpProvider(
          Provider<Thermosiphon> provideThermosiphon) =>
      () => providePump(provideThermosiphon());
}

@Component(modules: [DripCoffeeModule])
class DripCoffeeComponent {
  external CoffeeMaker coffeeMaker();

  /// Generated
  final Provider<CoffeeMaker> _coffeeMakerProvider;

  DripCoffeeComponent._(this._coffeeMakerProvider);

  // The body of this has been filled in
  CoffeeMaker coffeeMaker() => _coffeeMakerProvider();

  factory DripCoffeeComponent(DripCoffeeModule dripCoffeeModule) {
    final electricHeaterProvider = ElectricHeater.provider();
    final heaterProvider =
        dripCoffeeModule.provideHeaterProvider(electricHeaterProvider);
    final thermosiphonProvider = Thermosiphon.provider(heaterProvider);
    final pumpProvider =
        dripCoffeeModule.providePumpProvider(thermosiphonProvider);
    final coffeeMakerProvider =
        CoffeeMaker.provider(heaterProvider, pumpProvider);

    return DripCoffeeComponent._(coffeeMakerProvider);
  }
}

/// Adds a static `provider` method, which is a factory for a Provider<T> where
/// T is the annotated class. It will take a Provider<T> parameter corresponding
/// to each argument of the constructor (there must be exactly one constructor).
class Injectable implements ClassDeclarationsMacro {
  const Injectable();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    if (clazz.typeParameters.isNotEmpty) {
      throw ArgumentError('Type parameters are not supported!');
    }
    // ignore: deprecated_member_use
    final providerIdentifier = await builder.resolveIdentifier(
        Uri.parse('package:macro_proposal/injectable.dart'), 'Provider');
    // Declare a static method which takes all required providers, and returns
    // a provider for this class.
    final parts = <Object>[
      'static ',
      NamedTypeAnnotationCode(
          name: providerIdentifier,
          typeArguments: [NamedTypeAnnotationCode(name: clazz.identifier)]),
      ' provider(',
    ];

    final constructor = (await builder.constructorsOf(clazz)).single;
    final allParameters = constructor.positionalParameters
        .followedBy(constructor.namedParameters);
    for (final parameter in allParameters) {
      final type = parameter.type;
      parts.addAll([
        NamedTypeAnnotationCode(
            name: providerIdentifier, typeArguments: [type.code]),
        ' ',
        parameter.identifier.name,
        'Provider, '
      ]);
    }

    parts.addAll([
      ') => () => ',
      constructor.identifier,
      '(',
      for (final parameter in allParameters) '${parameter.identifier.name}(), ',
      ')',
    ]);

    builder.declareInClass(DeclarationCode.fromParts(parts));
  }
}

class Provides implements MethodDeclarationsMacro {
  const Provides();

  @override
  FutureOr<void> buildDeclarationsForMethod(
      MethodDeclaration method, ClassMemberDeclarationBuilder builder) async {
    final providerIdentifier = await builder.resolveIdentifier(
        Uri.parse('package:macro_proposal/injectable.dart'), 'Provider');
    if (method.namedParameters.isNotEmpty) {
      throw ArgumentError(
          '@Provides methods should only have positional parameters');
    }
    final parts = [
      NamedTypeAnnotationCode(
          name: providerIdentifier, typeArguments: [method.returnType.code]),
      ' ${method.identifier.name}Provider(',
      for (final param in method.positionalParameters) ...[
        NamedTypeAnnotationCode(
            name: providerIdentifier, typeArguments: [param.type.code]),
        ' provide${param.identifier.name.capitalize}, ',
      ],
      ') => ',
      method.identifier,
      '(',
      for (final param in method.positionalParameters) ...[
        param.identifier,
        '(), ',
      ],
      ');',
    ];
    builder.declareInClass(new DeclarationCode.fromParts(parts));
  }
}

class Component implements ClassDeclarationsMacro, ClassDefinitionMacro {
  final List<Identifier> modules;

  const Component({required this.modules});

  @override
  FutureOr<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassMemberDeclarationBuilder builder) async {
    final providerIdentifier = await builder.resolveIdentifier(
        Uri.parse('package:macro_proposal/injectable.dart'), 'Provider');
    final methods = await builder.methodsOf(clazz);
    final fieldNames = <String>[];
    for (final method in methods) {
      // We are filling in just the external methods.
      if (!method.isExternal) continue;

      // We use the method name because it is always a valid field name.
      final fieldName = '_${method.identifier.name}Provider;';
      fieldNames.add(fieldName);
      // Add a field for the provider of each returned type.
      builder.declareInClass(DeclarationCode.fromParts([
        'final ',
        NamedTypeAnnotationCode(
            name: providerIdentifier, typeArguments: [method.returnType.code]),
        fieldName,
      ]));
    }

    // Add a private constructor to initialize all the fields from the higher
    // level providers.
    builder.declareInClass(DeclarationCode.fromParts([
      clazz.identifier,
      '._(',
      for (final field in fieldNames) 'this.$field, ',
      ');',
    ]));

    // Declare a public factory constructor which we will fill in later, this
    // takes all the specified modules as arguments.
    builder.declareInClass(new DeclarationCode.fromParts([
      'external factory ',
      clazz.identifier,
      '(',
      for (final module in modules) ...[
        module,
        ' ${module.name}, ',
      ],
      ')',
    ]));
  }

  @override
  FutureOr<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    final providerIdentifier = await builder.resolveIdentifier(
        Uri.parse('package:macro_proposal/injectable.dart'), 'Provider');
    final methods = await builder.methodsOf(clazz);
    final fields = await builder.fieldsOf(clazz);

    // For each external method, find the field we declared in the last step,
    // and fill in the body of the method to just invoke it.
    for (final method in methods) {
      if (!method.isExternal) continue;
      final methodBuilder = await builder.buildMethod(method.identifier);
      final field = fields.firstWhere((field) =>
          field.identifier.name == '_${method.identifier.name}Provider');
      if (!await (await builder.resolve(field.type.code)).isExactly(
          await builder.resolve(NamedTypeAnnotationCode(
              name: providerIdentifier,
              typeArguments: [method.returnType.code])))) {
        throw ArgumentError(
            'Expected the field ${field.identifier.name} to be a Provider<${method.returnType.code}>');
      }
      methodBuilder.augment(FunctionBodyCode.fromParts([
        ' => ',
        field.identifier,
        '()',
      ]));
    }

    // Lastly, fill in the external factory constructor we declared earlier.
    final constructors = await builder.constructorsOf(clazz);
    final factoryConstructor = constructors.singleWhere((constructor) =>
        constructor.isFactory &&
        constructor.isExternal &&
        constructor.identifier.name == '');
    final constructorBuilder =
        await builder.buildConstructor(factoryConstructor.identifier);
    final parts = <Object>[
      '{',
    ];

    /// For each parameter to the factory, we add a map from the type provided
    /// to the providerProvider method.
    final providerProviderMethods = <Identifier, MethodDeclaration>{};

    /// For each providerProvider, the parameter that it came from.
    final providerProviderParameters = <MethodDeclaration, Identifier>{};
    for (final module in modules) {
      final moduleClass =
          await builder.declarationOf(module) as ClassDeclaration;
      for (final method in await builder.methodsOf(moduleClass)) {
        final returnType = method.returnType;
        if (returnType is! NamedTypeAnnotation) continue;
        if (returnType.identifier != providerIdentifier) continue;
        providerProviderMethods[
            (returnType.typeArguments.single as NamedTypeAnnotation)
                .identifier] = method;
      }
    }

    // Map of Type identifiers to local variable names for zero argument
    // provider methods.
    final localProviders = <Identifier, String>{};
    final arguments = await _satisfyParameters(
        factoryConstructor,
        builder,
        localProviders,
        providerIdentifier,
        providerProviderMethods,
        providerProviderParameters,
        parts);
    parts.addAll([
      'return ',
      factoryConstructor,
      '($arguments);}',
    ]);
    constructorBuilder.augment(body: FunctionBodyCode.fromParts(parts));
  }

  // TODO: Identify cycles and fail nicely.
  // TODO: Support generics for provided types.
  Future<String> _satisfyParameters(
      MethodDeclaration method,
      ClassDefinitionBuilder builder,
      Map<Identifier, String> localProviders,
      Identifier providerIdentifier,
      Map<Identifier, MethodDeclaration> providerProviderMethods,
      Map<MethodDeclaration, Identifier> providerProviderParameters,
      List<Object> codeParts) async {
    final args = StringBuffer();
    if (method.namedParameters.isNotEmpty) {
      throw StateError('Only positional parameters are supported');
    }
    for (final param in method.positionalParameters) {
      final paramType = param.type;
      if (paramType is! NamedTypeAnnotation ||
          paramType.identifier != providerIdentifier) {
        throw ArgumentError('All arguments should be providers');
      }
      final providedType =
          paramType.typeArguments.single as NamedTypeAnnotation;
      final argument = await _provideType(
          providedType.identifier,
          builder,
          localProviders,
          providerIdentifier,
          providerProviderMethods,
          providerProviderParameters,
          codeParts);
      args.write('$argument, ');
    }
    return args.toString();
  }

  Future<String> _provideType(
      Identifier type,
      ClassDefinitionBuilder builder,
      Map<Identifier, String> localProviders,
      Identifier providerIdentifier,
      Map<Identifier, MethodDeclaration> providerProviderMethods,
      Map<MethodDeclaration, Identifier> providerProviderParameters,
      List<Object> codeParts) async {
    // If we have a local provider, just invoke it.
    if (localProviders.containsKey(type)) return '${localProviders[type]}()';

    var providerProvider = providerProviderMethods[type];
    if (providerProvider == null) {
      // If we have no explicit provider from any module, check if the type is
      // injectable.
      final clazz = await builder.declarationOf(type);
      if (clazz is! ClassDeclaration) {
        throw UnsupportedError('Only classes are automatically injectable.');
      }
      for (final method in await builder.methodsOf(clazz)) {
        if (!method.isStatic) continue;
        final returnType = method.returnType;
        if (returnType is! NamedTypeAnnotation) continue;
        if (returnType.identifier != providerIdentifier) continue;
        if (returnType.typeArguments.single != type) continue;
        providerProvider = method;
        break;
      }
    }
    if (providerProvider == null) {
      throw StateError('No provider for type ${type.name}');
    }

    final arguments = await _satisfyParameters(
        providerProvider,
        builder,
        localProviders,
        providerIdentifier,
        providerProviderMethods,
        providerProviderParameters,
        codeParts);
    final name = '${type.name}Provider';
    codeParts.addAll([
      'final $name = ',
      // If it isn't a static method, it must be coming from a parameter.
      if (!providerProvider.isStatic) ...[
        providerProviderParameters[providerProvider]!,
        '.'
      ],
      providerProvider.identifier,
      '($arguments);',
    ]);
    localProviders[type] = name;
    return name;
  }
}

extension _ on String {
  String get capitalize => '${this[0].toUpperCase()}${substring(1)}';
}
