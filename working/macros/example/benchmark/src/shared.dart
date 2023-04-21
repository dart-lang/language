// There is no public API exposed yet, the in progress api lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:dart_style/dart_style.dart';

class BuildAugmentationLibraryBenchmark extends BenchmarkBase {
  final MacroExecutor executor;
  final List<MacroExecutionResult> results;
  final Map<Identifier, TypeDeclaration> typeDeclarations;
  late String library;

  BuildAugmentationLibraryBenchmark(
      this.executor, this.results, this.typeDeclarations)
      : super('AugmentationLibrary');

  static void reportAndPrint(
      MacroExecutor executor,
      List<MacroExecutionResult> results,
      Map<Identifier, TypeDeclaration> typeDeclarations) {
    final benchmark =
        BuildAugmentationLibraryBenchmark(executor, results, typeDeclarations);
    benchmark.report();
    final formatBenchmark = FormatLibraryBenchmark(benchmark.library)..report();
    print('${formatBenchmark.formattedResult}');
  }

  void run() {
    library = executor.buildAugmentationLibrary(
        results,
        (identifier) =>
            typeDeclarations[identifier] ??
            (throw UnsupportedError('Can only resolve myClass')), (identifier) {
      if (['bool', 'Object', 'String', 'int'].contains(identifier.name)) {
        return ResolvedIdentifier(
            kind: IdentifierKind.topLevelMember,
            name: identifier.name,
            staticScope: null,
            uri: null);
      } else {
        return ResolvedIdentifier(
            kind: identifier.name == 'MyClass'
                ? IdentifierKind.topLevelMember
                : IdentifierKind.instanceMember,
            name: identifier.name,
            staticScope: null,
            uri: Uri.parse('package:app/main.dart'));
      }
    },
        (annotation) =>
            throw UnsupportedError('Omitted types are not supported!'));
  }
}

class FormatLibraryBenchmark extends BenchmarkBase {
  final formatter = DartFormatter();
  final String library;
  late String formattedResult;

  FormatLibraryBenchmark(this.library) : super('FormatLibrary');

  void run() {
    formattedResult = formatter
        .format(library
            // comment out the `augment` keywords temporarily
            .replaceAll('augment', '/*augment*/'))
        .replaceAll('/*augment*/', 'augment');
  }
}

abstract class Fake {
  @override
  void noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Returns data as if everything was [myClass].
class SimpleTypeIntrospector implements TypeIntrospector {
  final Map<IntrospectableType, List<FieldDeclaration>> fields;
  final Map<IntrospectableType, List<MethodDeclaration>> methods;
  final Map<IntrospectableEnumDeclaration, List<EnumValueDeclaration>>
      enumValues;

  SimpleTypeIntrospector(this.fields, this.methods, this.enumValues);

  @override
  Future<List<ConstructorDeclaration>> constructorsOf(
          IntrospectableType type) async =>
      [];

  @override
  Future<List<FieldDeclaration>> fieldsOf(IntrospectableType type) async =>
      fields[type] ?? [];

  @override
  Future<List<MethodDeclaration>> methodsOf(IntrospectableType type) async =>
      methods[type] ?? [];

  @override
  Future<List<EnumValueDeclaration>> valuesOf(
          IntrospectableEnumDeclaration type) async =>
      enumValues[type] ?? [];
}

/// This is a very basic identifier resolver, it does no actual resolution.
class SimpleIdentifierResolver implements IdentifierResolver {
  /// Just returns a new [Identifier] whose name is [name].
  @override
  Future<Identifier> resolveIdentifier(Uri library, String name) async =>
      IdentifierImpl(id: RemoteInstance.uniqueId, name: name);
}

class SimpleTypeDeclarationResolver implements TypeDeclarationResolver {
  final Map<Identifier, TypeDeclaration> _knownDeclarations;

  SimpleTypeDeclarationResolver(this._knownDeclarations);

  @override
  Future<TypeDeclaration> declarationOf(
          covariant Identifier identifier) async =>
      _knownDeclarations[identifier] ??
      (throw UnsupportedError(
          'Could not resolve identifier ${identifier.name}'));
}

class FakeTypeInferrer extends Fake implements TypeInferrer {}

/// Only supports named types with no type arguments.
class SimpleTypeResolver implements TypeResolver {
  @override
  Future<StaticType> resolve(TypeAnnotationCode type) async {
    if (type is! NamedTypeAnnotationCode) {
      throw UnsupportedError('Only named type annotations are supported');
    }
    if (type.typeArguments.isNotEmpty) {
      throw UnsupportedError('Type arguments are not supported');
    }
    return SimpleNamedStaticType(type.name.name, isNullable: type.isNullable);
  }
}

/// Only supports exact matching, and only goes off of the name and nullability.
class SimpleNamedStaticType implements NamedStaticType {
  final bool isNullable;
  final String name;

  SimpleNamedStaticType(this.name, {this.isNullable = false});

  @override
  Future<bool> isExactly(covariant SimpleNamedStaticType other) async =>
      isNullable == other.isNullable && name == other.name;

  @override
  Future<bool> isSubtypeOf(covariant StaticType other) =>
      throw UnimplementedError();
}

extension _ on Duration {
  Duration dividedBy(int amount) =>
      Duration(microseconds: (this.inMicroseconds / amount).round());
}

final boolIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'bool');
final intIdentifier = IdentifierImpl(id: RemoteInstance.uniqueId, name: 'int');
final objectIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Object');
final stringIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'String');

final boolType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    identifier: boolIdentifier,
    isNullable: false,
    typeArguments: const []);
final intType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    identifier: intIdentifier,
    isNullable: false,
    typeArguments: const []);
final stringType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    identifier: stringIdentifier,
    isNullable: false,
    typeArguments: const []);

final objectClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: objectIdentifier,
    interfaces: [],
    hasAbstract: false,
    hasBase: false,
    hasExternal: false,
    hasFinal: false,
    hasInterface: false,
    hasMixin: false,
    hasSealed: false,
    mixins: [],
    superclass: null,
    typeParameters: []);
