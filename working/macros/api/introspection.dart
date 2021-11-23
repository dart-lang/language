import 'code.dart';

/// An unresolved reference to a type.
///
/// These can be resolved to a [TypeDeclaration] using the `builder` classes
/// depending on the phase a macro is running in.
abstract class TypeAnnotation {
  /// Whether or not the type annotation is explicitly nullable (contains a
  /// trailing `?`)
  bool get isNullable;

  /// The name of the type as it exists in the type annotation.
  String get name;

  /// The scope in which the type annotation appeared in the program.
  ///
  /// This can be used to construct an [IdentifierCode] that refers to this type
  /// regardless of the context in which it is emitted.
  Scope get scope;

  /// The type arguments, if applicable.
  Iterable<TypeAnnotation> get typeArguments;
}

//// The base class for all declarations.
abstract class Declaration {
  /// The name of this type declaration
  String get name;

  /// The scope in which this type declaration is defined.
  ///
  /// This can be used to construct an [IdentifierCode] that refers to this type
  /// regardless of the context in which it is emitted.
  Scope get scope;
}

/// A declaration that defines a new type in the program.
abstract class TypeDeclaration implements Declaration {
  /// The type parameters defined for this type declaration.
  Iterable<TypeParameterDeclaration> get typeParameters;

  /// Create a type annotation representing this type with [typeArguments].
  TypeAnnotation instantiate({List<TypeAnnotation> typeArguments});
}

/// Class (and enum) introspection information.
///
/// Information about fields, methods, and constructors must be retrieved from
/// the `builder` objects.
abstract class ClassDeclaration implements TypeDeclaration {
  /// Whether this class has an `abstract` modifier.
  bool get isAbstract;

  /// Whether this class has an `external` modifier.
  bool get isExternal;

  /// The `extends` type annotation, if present.
  TypeAnnotation? get superclass;

  /// All the `implements` type annotations.
  Iterable<TypeAnnotation> get implements;

  /// All the `with` type annotations.
  Iterable<TypeAnnotation> get mixins;

  /// All the type arguments, if applicable.
  Iterable<TypeParameterDeclaration> get typeParameters;
}

/// Function introspection information.
abstract class FunctionDeclaration implements Declaration {
  /// Whether this function has an `abstract` modifier.
  bool get isAbstract;

  /// Whether this function has an `external` modifier.
  bool get isExternal;

  /// Whether this function is actually a getter.
  bool get isGetter;

  /// Whether this function is actually a setter.
  bool get isSetter;

  /// The return type of this function.
  TypeAnnotation get returnType;

  /// The positional parameters for this function.
  Iterable<ParameterDeclaration> get positionalParameters;

  /// The named parameters for this function.
  Iterable<ParameterDeclaration> get namedParameters;

  /// The type parameters for this function.
  Iterable<TypeParameterDeclaration> get typeParameters;
}

/// Method introspection information.
abstract class MethodDeclaration implements FunctionDeclaration {
  /// The class that defines this method.
  TypeAnnotation get definingClass;
}

/// Constructor introspection information.
abstract class ConstructorDeclaration implements MethodDeclaration {
  /// Whether or not this is a factory constructor.
  bool get isFactory;
}

/// Cariable introspection information.
abstract class VariableDeclaration implements Declaration {
  /// Whether this function has an `abstract` modifier.
  bool get isAbstract;

  /// Whether this function has an `external` modifier.
  bool get isExternal;

  /// The type of this field.
  TypeAnnotation get type;

  /// A [Code] object representing the initializer for this field, if present.
  Code? get initializer;
}

/// Field introspection information ..
abstract class FieldDeclaration implements VariableDeclaration {
  /// The class that defines this method.
  TypeAnnotation get definingClass;
}

/// Parameter introspection information.
abstract class ParameterDeclaration {
  /// The name of the parameter.
  String get name;

  /// The type of this parameter.
  TypeAnnotation get type;

  /// Whether or not this is a named parameter.
  bool get isNamed;

  /// Whether or not this parameter is either a non-optional positional
  /// parameter or an optional parameter with the `required` keyword.
  bool get isRequired;

  /// A [Code] object representing the default value for this parameter, if
  /// present. Can be used to copy default values to other parameters.
  Code? get defaultValue;
}

/// Type parameter introspection information.
abstract class TypeParameterDeclaration {
  /// The bounds for this type parameter, if it has any.
  TypeAnnotation? get bounds;
}
