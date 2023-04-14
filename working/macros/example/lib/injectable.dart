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

class Component implements ClassDefinitionMacro {
  final List<Identifier> modules;

  const Component({required this.modules});

  @override
  FutureOr<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder) async {
    // TODO: implement buildDefinitionForClass
    throw UnimplementedError();
  }
}

extension _ on String {
  String get capitalize => '${this[0].toUpperCase()}${substring(1)}';
}
