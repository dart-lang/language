// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

// There is no public API exposed yet, the in-progress API lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

import 'util.dart';

/// A [Provider] is just a function with no arguments that returns something
/// of the desired type when invoked.
typedef Provider<T> = T Function();

/// Adds a static `provider` method, which is a factory for a Provider<T> where
/// T is the annotated class. It will take a Provider parameter corresponding
/// to each argument of the constructor (there must be exactly one constructor).
///
/// So for example, given:
///
/// @Injectable()
/// class A {
///   final B b;
///   A(this.b);
/// }
///
/// It would generate this augmentation:
///
/// augment class A {
///   Provider<A> provider(Provider<B> bProvider) =>
///     () => A(bProvider());
/// }
///
/// These methods are later used by Component classes to inject dependencies.
macro class Injectable implements ClassDeclarationsMacro {
  const Injectable();

  @override
  Future<void> buildDeclarationsForClass(IntrospectableClassDeclaration clazz,
      MemberDeclarationBuilder builder) async {
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

    final constructors = await builder.constructorsOf(clazz);
    if (constructors.length != 1) {
      throw ArgumentError(
          'Injectable classes should have only one constructor but '
          '${clazz.identifier.name} has ${constructors.length}');
    }
    final constructor = constructors.single;
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
      // TODO: Remove once augmentaiton libraries are fixed for unnamed
      // constructors.
      constructor.identifier.name.isEmpty
          ? clazz.identifier
          : constructor.identifier,
      '(',
      for (final parameter in allParameters)
        '${parameter.identifier.name}Provider(), ',
      ');',
    ]);

    builder.declareInType(DeclarationCode.fromParts(parts));
  }
}

/// Annotate provider methods on your module class with this, and it will
/// generate Provider versions of those methods, for use in a component later
/// on. For example, given:
///
/// class MyModule {
///   @Provides()
///   A provideA(B b, C c) => A(b, c);
/// }
///
/// It will generate this augmentation:
///
/// augment class MyModule {
///   Provider<A> provideAProvider(Provider<B> b, Provider<C> c) =>
///       () => provideA(provideB(), provideC());
/// }
macro class Provides implements MethodDeclarationsMacro {
  const Provides();

  @override
  FutureOr<void> buildDeclarationsForMethod(
      MethodDeclaration method, MemberDeclarationBuilder builder) async {
    // ignore: deprecated_member_use
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
      for (final param in method.positionalParameters)
        'provide${param.identifier.name.capitalize}(), ',
      ');',
    ];
    builder.declareInType(new DeclarationCode.fromParts(parts));
  }
}

/// Given a component with external methods for the types it wants to provide,
/// and an external factory method that lists the modules used to provide
/// its dependencies as parameters, this will generate a private constructor,
/// along with some private fields, and fill in the body of the external members
/// using those.
///
/// For example, give this full-ish example:
///
/// @Injectable()
/// class A {
///   final B b;
///   A(this.B);
/// }
///
/// interface class B {}
///
/// @Injectable()
/// class BImpl implements B {}
///
/// class ADepsModule {
///   @Provides
///   B provideB(BImpl impl) => impl;
/// }
///
/// @Component()
/// class AComponent {
///   external A a();
///
///   external factory A(ADepsModule aDepsModule);
/// }
///
/// It would generate roughly this augmentation for the component:
///
/// augment class AComponet {
///   final Provider<A> _aProvider;
///   AComponent._(this._aProvider);
///
///   augment A a() => _aProvider();
///
///   augment factory A(ADepsModule aDepsModule) {
///     final bImplProvider = BImpl.provider();
///     final bProvider = aDepsModule.provideBProvider(bImplProvider);
///     final aProvider = A.provider(bProvider);
///     return A._(aProvider);
///   }
/// }
macro class Component implements ClassDeclarationsMacro, ClassDefinitionMacro {
  final List<Identifier> modules;

  // TODO: Require modules here and generate the constructor once supported.
  const Component({this.modules = const []});

  @override
  FutureOr<void> buildDeclarationsForClass(IntrospectableClassDeclaration clazz,
      MemberDeclarationBuilder builder) async {
    // ignore: deprecated_member_use
    final providerIdentifier = await builder.resolveIdentifier(
        Uri.parse('package:macro_proposal/injectable.dart'), 'Provider');
    final methods = await builder.methodsOf(clazz);
    final fieldNames = <String>[];
    for (final method in methods) {
      // We are filling in just the external methods.
      if (!method.isExternal) continue;

      // We use the method name because it is always a valid field name.
      final fieldName = '_${method.identifier.name}Provider';
      fieldNames.add(fieldName);
      // Add a field for the provider of each returned type.
      builder.declareInType(DeclarationCode.fromParts([
        'final ',
        NamedTypeAnnotationCode(
            name: providerIdentifier, typeArguments: [method.returnType.code]),
        '$fieldName;',
      ]));
    }

    // Add a private constructor to initialize all the fields from the higher
    // level providers.
    builder.declareInType(DeclarationCode.fromParts([
      clazz.identifier.name,
      '._(',
      for (final field in fieldNames) 'this.$field, ',
      ');',
    ]));

    // TODO: Always do this, once the impls support macro arguments
    if (modules.isNotEmpty) {
      // Declare a public factory constructor which we will fill in later, this
      // takes all the specified modules as arguments.
      builder.declareInType(new DeclarationCode.fromParts([
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
  }

  @override
  FutureOr<void> buildDefinitionForClass(IntrospectableClassDeclaration clazz,
      TypeDefinitionBuilder builder) async {
    // ignore: deprecated_member_use
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
            'Expected the field ${field.identifier.name} to be a '
            'Provider<${method.returnType.code.debugString()}> but it was a '
            '${field.type.code.debugString()}');
      }
      methodBuilder.augment(FunctionBodyCode.fromParts([
        ' => ',
        field.identifier,
        '();',
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

    for (final param in factoryConstructor.positionalParameters
        .followedBy(factoryConstructor.namedParameters)) {
      final module = (param.type as NamedTypeAnnotation).identifier;
      final moduleClass =
          await builder.typeDeclarationOf(module);
      for (final method in await builder.methodsOf(moduleClass)) {
        final returnType = method.returnType;
        if (returnType is! NamedTypeAnnotation) continue;
        if (returnType.identifier != providerIdentifier) continue;
        providerProviderMethods[
            (returnType.typeArguments.single as NamedTypeAnnotation)
                .identifier] = method;
        providerProviderParameters[method] = param.identifier;
      }
    }

    /// The private constructor (generated earlier), that we actually want to
    /// invoke. This will have only Providers as its parameters, one for each
    /// external method on the class.
    final privateConstructor = constructors
        .singleWhere((constructor) => constructor.identifier.name == '_');
    // Map of Type identifiers to local variable names for zero argument
    // provider methods.
    final localProviders = <Identifier, String>{};
    final arguments = await _satisfyParameters(
        privateConstructor,
        builder,
        localProviders,
        providerIdentifier,
        providerProviderMethods,
        providerProviderParameters,
        parts);
    parts.addAll([
      'return ',
      privateConstructor.identifier,
      '($arguments);}',
    ]);
    constructorBuilder.augment(body: FunctionBodyCode.fromParts(parts));
  }

  // TODO: Identify cycles and fail nicely.
  // TODO: Support generics for provided types.
  Future<String> _satisfyParameters(
      MethodDeclaration method,
      TypeDefinitionBuilder builder,
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
      var paramType = param.type;
      if (paramType is OmittedTypeAnnotation) {
        paramType = await builder.inferType(paramType);
      }
      if (paramType is! NamedTypeAnnotation ||
          paramType.identifier != providerIdentifier) {
        throw ArgumentError('All arguments should be providers, but got a '
            '${param.type.code.debugString()}');
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
      TypeDefinitionBuilder builder,
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
      final clazz = await builder.typeDeclarationOf(type);
      if (clazz is! IntrospectableType) {
        throw UnsupportedError('Only classes are automatically injectable.');
      }
      for (final method in await builder.methodsOf(clazz)) {
        if (!method.isStatic) continue;
        final returnType = method.returnType;
        if (returnType is! NamedTypeAnnotation) continue;
        if (returnType.identifier != providerIdentifier) continue;
        final typeArgument = returnType.typeArguments.single;
        if (typeArgument is! NamedTypeAnnotation) continue;
        if (typeArgument.identifier != type) continue;
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
    final name = '${type.name.uncapitalize}Provider';
    codeParts.addAll([
      'final $name = ',
      // If it isn't a static method, it must be coming from a parameter.
      if (!providerProvider.isStatic) ...[
        providerProviderParameters[providerProvider]!,
        '.',
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
  String get uncapitalize => '${this[0].toLowerCase()}${substring(1)}';
}
