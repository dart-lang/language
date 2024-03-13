// There is no public API exposed yet, the in progress API lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/code_optimizer.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:_fe_analyzer_shared/src/scanner/scanner.dart';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:dart_style/dart_style.dart';

/// A benchmark which only calls `run` once inside `excersize`.
class RunOnceBenchmarkBase extends BenchmarkBase {
  RunOnceBenchmarkBase(super.name);

  @override
  void exercise() {
    run();
  }
}

class BuildAugmentationLibraryBenchmark extends RunOnceBenchmarkBase {
  final MacroExecutor executor;
  final List<MacroExecutionResult> results;

  /// Map from identifiers to their declarations.
  final Map<Identifier, Declaration> identifierDeclarations;
  late String library;

  BuildAugmentationLibraryBenchmark(
      this.executor, this.results, this.identifierDeclarations)
      : super('AugmentationLibrary');

  static String reportAndPrint(
    MacroExecutor executor,
    List<MacroExecutionResult> results,
    Map<Identifier, Declaration> identifierDeclarations,
  ) {
    for (var result in results) {
      for (var diagnostic in result.diagnostics) {
        print(diagnostic.message.message);
      }
    }
    final benchmark = BuildAugmentationLibraryBenchmark(
        executor, results, identifierDeclarations);
    benchmark.report();
    return benchmark.library;
  }

  void run() {
    library = executor.buildAugmentationLibrary(
        fooLibrary.uri,
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
            uri: dartCore);
      } else {
        final declaration = identifierDeclarations[identifier];
        String? staticScope;
        IdentifierKind kind;
        if (declaration is MemberDeclaration) {
          if (declaration.hasStatic) {
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

  static final dartCore = Uri.parse('dart:core');
}

class FormatLibraryBenchmark extends RunOnceBenchmarkBase {
  final formatter = DartFormatter();
  final String library;
  late String _formattedResult;

  String get formattedResult => _formattedResult
      .replaceAll('/*augment*/', 'augment')
      .replaceAll('on FakeTypeForFormatting {', '{');

  FormatLibraryBenchmark._(String library)
      : library = _prepareLibrary(library),
        super('FormatLibrary');

  /// Converts [original] such that it can be formatted even though
  /// augmentations are not yet supported.
  static String _prepareLibrary(String original) {
    var formattableLibrary = original
        // comment out the `augment` keywords temporarily
        .replaceAll('augment', '/*augment*/');

    var extensionMatch = extensionRegex.firstMatch(formattableLibrary);
    while (extensionMatch != null) {
      // Add a fake on type temporarily, so we can format it.
      formattableLibrary = formattableLibrary.replaceRange(
          extensionMatch.end - 1,
          extensionMatch.end,
          'on FakeTypeForFormatting {');
      extensionMatch = extensionRegex.firstMatch(formattableLibrary);
    }
    return formattableLibrary;
  }

  static final extensionRegex = RegExp(r'extension [a-zA-Z]+ {');

  void run() {
    _formattedResult = formatter.format(library);
  }

  static String reportAndPrint(String library) {
    final formatBenchmark = FormatLibraryBenchmark._(library)..report();
    print('${formatBenchmark.formattedResult}');
    return formatBenchmark.formattedResult;
  }
}

class CodeOptimizerBenchmark extends RunOnceBenchmarkBase {
  final String library;
  final Set<String> libraryDeclarationNames;
  final BenchmarkCodeOptimizer optimizer;
  late String optimizedLibrary;

  CodeOptimizerBenchmark(
      this.library, this.libraryDeclarationNames, this.optimizer)
      : super('CodeOptimizer');

  void run() {
    optimizedLibrary = Edit.applyList(
        optimizer.optimize(library,
            libraryDeclarationNames: libraryDeclarationNames,
            scannerConfiguration: ScannerConfiguration(
                enableExtensionMethods: true,
                enableNonNullable: true,
                enableTripleShift: true,
                forAugmentationLibrary: true)),
        library);
  }

  void reportAndPrint() {
    report();
    print(optimizedLibrary);
  }
}

class BenchmarkCodeOptimizer extends CodeOptimizer {
  final Map<Uri, Map<String, Identifier>> identifiers;

  BenchmarkCodeOptimizer({required this.identifiers});

  @override
  Set<String> getImportedNames(String uriStr) {
    return (identifiers[Uri.parse(uriStr)] ?? {}).keys.toSet();
  }
}

abstract mixin class Fake {
  @override
  void noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// This is a very basic identifier resolver, it does no actual resolution.
class SimpleTypePhaseIntrospector implements TypePhaseIntrospector {
  final Map<Uri, Map<String, Identifier>> identifiers;

  SimpleTypePhaseIntrospector({required this.identifiers});

  /// Looks up an identifier in [identifiers] using [library] and [name].
  ///
  /// Throws if it does not exist.
  @override
  Future<Identifier> resolveIdentifier(Uri library, String name) async =>
      identifiers[library]![name]!;
}

class SimpleDeclarationPhaseIntrospector extends SimpleTypePhaseIntrospector
    implements DeclarationPhaseIntrospector {
  final Map<Identifier, Declaration> declarations;
  final Map<TypeDeclaration, List<ConstructorDeclaration>> constructors;
  final Map<EnumDeclaration, List<EnumValueDeclaration>> enumValues;
  final Map<TypeDeclaration, List<FieldDeclaration>> fields;
  final Map<TypeDeclaration, List<MethodDeclaration>> methods;

  SimpleDeclarationPhaseIntrospector({
    required super.identifiers,
    required this.declarations,
    required this.constructors,
    required this.enumValues,
    required this.fields,
    required this.methods,
  });

  @override
  Future<TypeDeclaration> typeDeclarationOf(
          covariant Identifier identifier) async =>
      declarations[identifier] as TypeDeclaration? ??
      (throw UnsupportedError(
          'Could not resolve identifier ${identifier.name}'));

  @override
  Future<List<ConstructorDeclaration>> constructorsOf(
          TypeDeclaration type) async =>
      constructors[type] ?? [];

  @override
  Future<List<FieldDeclaration>> fieldsOf(TypeDeclaration type) async =>
      fields[type] ?? [];

  @override
  Future<List<MethodDeclaration>> methodsOf(TypeDeclaration type) async =>
      methods[type] ?? [];

  @override
  Future<List<EnumValueDeclaration>> valuesOf(EnumDeclaration type) async =>
      enumValues[type] ?? [];

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

  @override
  Future<List<TypeDeclaration>> typesOf(Library library) async => [
        for (var declaration in declarations.values)
          if (declaration is TypeDeclaration) declaration,
      ];
}

class SimpleDefinitionPhaseIntrospector
    extends SimpleDeclarationPhaseIntrospector
    implements DefinitionPhaseIntrospector {
  SimpleDefinitionPhaseIntrospector(
      {required super.identifiers,
      required super.declarations,
      required super.constructors,
      required super.enumValues,
      required super.fields,
      required super.methods});

  @override
  Future<Declaration> declarationOf(Identifier identifier) async =>
      declarations[identifier]!;

  @override
  Future<TypeAnnotation> inferType(OmittedTypeAnnotation omittedType) =>
      throw UnimplementedError();

  @override
  Future<List<Declaration>> topLevelDeclarationsOf(Library library) async =>
      declarations.values.toList(growable: false);

  @override
  Future<TypeDeclaration> typeDeclarationOf(Identifier identifier) async =>
      (await super.typeDeclarationOf(identifier));
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
final dynamicIdentifeir =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'dynamic');
final intIdentifier = IdentifierImpl(id: RemoteInstance.uniqueId, name: 'int');
final mapIdentifier = IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Map');
final objectIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'Object');
final stringIdentifier =
    IdentifierImpl(id: RemoteInstance.uniqueId, name: 'String');

final boolType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    identifier: boolIdentifier,
    isNullable: false,
    typeArguments: const []);
final dynamicType = NamedTypeAnnotationImpl(
    id: RemoteInstance.uniqueId,
    identifier: dynamicIdentifeir,
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

final dartCoreLibrary = LibraryImpl(
    id: RemoteInstance.uniqueId,
    languageVersion: LanguageVersionImpl(3, 0),
    metadata: [],
    uri: Uri.parse('dart:core'));
final fooLibrary = LibraryImpl(
    id: RemoteInstance.uniqueId,
    languageVersion: LanguageVersionImpl(3, 0),
    metadata: [],
    uri: Uri.parse('package:foo/foo.dart'));

final boolClass = ClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: boolIdentifier,
    library: dartCoreLibrary,
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
    superclass: null,
    typeParameters: []);
final intClass = ClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: intIdentifier,
    library: dartCoreLibrary,
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
    superclass: null,
    typeParameters: []);
final objectClass = ClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: objectIdentifier,
    library: dartCoreLibrary,
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
    superclass: null,
    typeParameters: []);
final stringClass = ClassDeclarationImpl(
    id: RemoteInstance.uniqueId,
    identifier: stringIdentifier,
    library: dartCoreLibrary,
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
    superclass: null,
    typeParameters: []);
