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

  /// Map from identifiers to their declarations.
  final Map<Identifier, Declaration> identifierDeclarations;
  late String library;

  BuildAugmentationLibraryBenchmark(
      this.executor, this.results, this.identifierDeclarations)
      : super('AugmentationLibrary');

  static void reportAndPrint(
    MacroExecutor executor,
    List<MacroExecutionResult> results,
    Map<Identifier, Declaration> identifierDeclarations,
  ) {
    final benchmark = BuildAugmentationLibraryBenchmark(
        executor, results, identifierDeclarations);
    benchmark.report();
    final formatBenchmark = FormatLibraryBenchmark(benchmark.library)..report();
    print('${formatBenchmark.formattedResult}');
  }

  void run() {
    library = executor.buildAugmentationLibrary(
        results,
        (identifier) =>
            identifierDeclarations[identifier] as TypeDeclaration? ??
            (throw UnsupportedError(
                'Can not resolve identifier ${identifier.name}')),
        (identifier) {
      if (['bool', 'Object', 'String', 'int'].contains(identifier.name)) {
        return ResolvedIdentifier(
            kind: IdentifierKind.topLevelMember,
            name: identifier.name,
            staticScope: null,
            uri: null);
      } else {
        final declaration = identifierDeclarations[identifier];
        String? staticScope;
        IdentifierKind kind;
        if (declaration is MemberDeclaration) {
          if (declaration.isStatic) {
            staticScope = declaration.definingType.name;
            kind = IdentifierKind.staticInstanceMember;
          } else {
            kind = IdentifierKind.instanceMember;
          }
        } else if (declaration is TypeDeclaration) {
          kind = IdentifierKind.topLevelMember;
        } else {
          // Assume it is a parameter or similar.
          kind = IdentifierKind.local;
        }
        return ResolvedIdentifier(
            kind: kind,
            name: identifier.name,
            staticScope: staticScope,
            uri: kind == IdentifierKind.topLevelMember ||
                    kind == IdentifierKind.staticInstanceMember
                ? Uri.parse('package:app/main.dart')
                : null);
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

abstract mixin class Fake {
  @override
  void noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Returns data as if everything was [myClass].
class SimpleTypeIntrospector implements TypeIntrospector {
  final Map<IntrospectableType, List<ConstructorDeclaration>> constructors;
  final Map<IntrospectableEnumDeclaration, List<EnumValueDeclaration>>
      enumValues;
  final Map<IntrospectableType, List<FieldDeclaration>> fields;
  final Map<IntrospectableType, List<MethodDeclaration>> methods;

  SimpleTypeIntrospector({
    required this.constructors,
    required this.enumValues,
    required this.fields,
    required this.methods,
  });

  @override
  Future<List<ConstructorDeclaration>> constructorsOf(
          IntrospectableType type) async =>
      constructors[type] ?? [];

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
  final Map<Uri, Map<String, Identifier>> knownIdentifiers;

  SimpleIdentifierResolver(this.knownIdentifiers);

  /// Just returns a new [Identifier] whose name is [name].
  @override
  Future<Identifier> resolveIdentifier(Uri library, String name) async =>
      knownIdentifiers[library]![name]!;
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

class FakeTypeInferrer extends Object with Fake implements TypeInferrer {
  const FakeTypeInferrer();
}

/// Only supports named types with no type arguments.
class SimpleTypeResolver implements TypeResolver {
  const SimpleTypeResolver();

  @override
  Future<SimpleNamedStaticType> resolve(TypeAnnotationCode type) async {
    if (type is! NamedTypeAnnotationCode) {
      throw UnsupportedError('Only named type annotations are supported');
    }
    return SimpleNamedStaticType(type.name.name,
        isNullable: type.isNullable,
        typeArguments: [
          for (final type in type.typeArguments) await resolve(type),
        ]);
  }
}

/// Only supports exact matching, and only goes off of the name and nullability.
class SimpleNamedStaticType implements NamedStaticType {
  final bool isNullable;
  final String name;
  final List<SimpleNamedStaticType> typeArguments;

  SimpleNamedStaticType(this.name,
      {this.isNullable = false, this.typeArguments = const []});

  @override
  Future<bool> isExactly(covariant SimpleNamedStaticType other) async {
    if (isNullable != other.isNullable ||
        name != other.name ||
        typeArguments.length != other.typeArguments.length) {
      return false;
    }
    for (var i = 0; i < typeArguments.length; i++) {
      if (!await typeArguments[i].isExactly(other.typeArguments[i])) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<bool> isSubtypeOf(covariant StaticType other) =>
      throw UnimplementedError();
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
final fooLibrary = LibraryImpl(
    id: RemoteInstance.uniqueId,
    languageVersion: LanguageVersionImpl(3, 0),
    uri: Uri.parse('package:foo/foo.dart'));

final objectClass = IntrospectableClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: objectIdentifier,
    library: fooLibrary,
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
