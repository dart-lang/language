import 'code.dart';

/// Type annotation introspection information.
///
/// These can be resolved using the `builder` classes depending on the phase
/// a macro is running in.
abstract class TypeAnnotation {
  /// Whether or not the type reference is explicitly nullable (contains a
  /// trailing `?`)
  bool get isNullable;

  /// The name of the type as it exists in the type annotation.
  String get name;

  /// The scope in which the type reference appeared in the program.
  ///
  /// This can be used to construct an [Identifier] that refers to this type
  /// regardless of the context in which it is emitted.
  Scope get scope;

  /// The type arguments, if applicable.
  Iterable<TypeAnnotation> get typeArguments;
}

/// Generic declaration introspection information.
abstract class Declaration {
  /// Whether this declaration has an `abstract` modifier.
  bool get isAbstract;

  /// Whether this declaration has an `external` modifier.
  bool get isExternal;

  /// The name of this declaration as it appears in the code.
  String get name;

  /// Emits a piece of code that concretely refers to the same type that is
  /// referred to by [this], regardless of where in the program it is placed.
  ///
  /// Effectively, this type reference has a custom scope (equal to [scope])
  /// instead of the standard lexical scope.
  Code get reference;

  /// The scope in which the type reference appeared in the program.
  Scope get scope;
}

/// Class (and enum) introspection information.
///
/// Information about fields, methods, and constructors must be retrieved from
/// the `builder` objects.
abstract class ClassDeclaration implements Declaration {
  /// The `extends` type annotation, if present.
  TypeAnnotation? get superclass;

  /// All the `implements` type annotations.
  Iterable<TypeAnnotation> get implements;

  /// All the `with` type annotations.
  Iterable<TypeAnnotation> get mixins;

  /// All the type arguments, if applicable.
  Iterable<TypeParameter> get typeParameters;
}

/// Enum introspection information.
abstract class EnumDeclaration implements Declaration {}

/// Function introspection information.
abstract class FunctionDeclaration implements Declaration {
  bool get isGetter;

  bool get isSetter;

  TypeAnnotation get returnType;

  Iterable<Parameter> get positionalParameters;

  Iterable<Parameter> get namedParameters;

  Iterable<TypeParameter> get typeParameters;
}

/// Method introspection information for [TypeMacro]s.
abstract class MethodDeclaration implements FunctionDeclaration {
  TypeAnnotation get definingClass;
}

/// Constructor introspection information for [TypeMacro]s.
abstract class ConstructorDeclaration implements MethodDeclaration {
  bool get isFactory;
}

/// Field introspection information ..
abstract class FieldDeclaration implements Declaration {
  TypeAnnotation get type;

  TypeAnnotation get definingClass;
}

/// Parameter introspection information.
abstract class Parameter {
  String get name;

  bool get required;

  TypeAnnotation get type;
}

/// Type parameter introspection information.
abstract class TypeParameter {
  TypeAnnotation? get bounds;

  String get name;
}
