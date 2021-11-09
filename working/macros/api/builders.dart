import 'dart:async';

import 'code.dart';
import 'introspection.dart';
import 'macros.dart'; // For dart docs :(

abstract class Builder {
  /// Used to construct a [TypeAnnotation] to a runtime type available to the
  /// the macro implementation code.
  ///
  /// This can be used to emit a reference to it in generated code, or do
  /// subtype checks (depending on support in the current phase).
  TypeAnnotation typeAnnotationOf<T>();
}

/// The api used by [TypeMacro]s to contribute new type declarations to the
/// current library, and get [TypeAnnotation]s from runtime [Type] objects.
abstract class TypeBuilder implements Builder {
  /// Adds a new type declaration to the surrounding library.
  void declareType(DeclarationCode typeDeclaration);
}

/// The api used by [DeclarationMacro]s to contribute new (non-type)
/// declarations to the current library.
///
/// Can also be used to do subtype checks on types.
abstract class DeclarationBuilder implements Builder {
  /// Adds a new regular declaration to the surrounding library.
  ///
  /// Note that type declarations are not supported.
  Declaration declareInLibrary(DeclarationCode declaration);

  /// Returns true if [leftType] is a subtype of [rightType].
  bool isSubtypeOf(TypeAnnotation leftType, TypeAnnotation rightType);

  /// Retruns true if [leftType] is an identical type to [rightType].
  bool isExactly(TypeAnnotation leftType, TypeAnnotation rightType);
}

/// The api used by [DeclarationMacro]s to contribute new members to a class.
abstract class ClassMemberDeclarationBuilder implements DeclarationBuilder {
  /// Adds a new declaration to the surrounding class.
  void declareInClass(DeclarationCode declaration);
}

/// The api used to introspect on a [ClassDeclaration].
abstract class ClassIntrospector {
  /// The fields available for [clazz].
  ///
  /// This may be incomplete if in the declaration phase and additional macros
  /// are going to run on this class.
  Future<List<FieldDeclaration>> fieldsOf(ClassDeclaration clazz);

  /// The methods available so far for the current class.
  ///
  /// This may be incomplete if additional declaration macros are running on
  /// this class.
  Future<List<MethodDeclaration>> methodsOf(ClassDeclaration clazz);

  /// The constructors available so far for the current class.
  ///
  /// This may be incomplete if additional declaration macros are running on
  /// this class.
  Future<List<ConstructorDeclaration>> constructorsOf(ClassDeclaration clazz);

  /// The class that is directly extended via an `extends` clause.
  Future<ClassDeclaration?> superclassOf(ClassDeclaration clazz);

  /// All of the classes that are mixed in with `with` clauses.
  Future<List<ClassDeclaration>> mixinsOf(ClassDeclaration clazz);
}

/// The api used by [Macro]s to reflect on the currently available
/// members, superclass, and mixins for a given [ClassDeclaration]
abstract class ClassDeclarationBuilder
    implements ClassMemberDeclarationBuilder, ClassIntrospector {}

/// The api used by [Macro] to get a [TypeDeclaration] for any given
/// [TypeAnnotation].
abstract class TypeIntrospector {
  /// TODO: Figure out how to deal with `FutureOr<T>`, function types, and
  /// other non-nominal types.
  Future<TypeDeclaration> resolve(TypeAnnotation annotation);
}

/// The base class for builders in the definition phase. These can convert
/// any [TypeAnnotation] into its corresponding [TypeDeclaration], and also
/// reflect more deeply on those.
abstract class DefinitionBuilder
    implements Builder, ClassIntrospector, TypeIntrospector {}

/// The apis used by [Macro]s that run on classes, to fill in the definitions
/// of any external declarations within that class.
abstract class ClassDefinitionBuilder implements DefinitionBuilder {
  /// Retrieve a [FieldDefinitionBuilder] for a field by [name].
  ///
  /// Throws an [ArgumentError] if there is no field by that name.
  Future<void> buildField(String name,
      FutureOr<void> Function(FieldDefinitionBuilder builder) callback);

  /// Retrieve a [FunctionDefinitionBuilder] for a method by [name].
  ///
  /// Throws an [ArgumentError] if there is no method by that name.
  Future<void> buildMethod(String name,
      FutureOr<void> Function(FunctionDefinitionBuilder builder) callback);

  /// Retrieve a [ConstructorDefinitionBuilder] for a constructor by [name].
  ///
  /// Throws an [ArgumentError] if there is no constructor by that name.
  Future<void> buildConstructor(String name,
      FutureOr<void> Function(ConstructorDefinitionBuilder builder) callback);
}

/// The apis used by [Macro]s to define the body of a constructor
/// or wrap the body of an existing constructor with additional statements.
abstract class ConstructorDefinitionBuilder implements DefinitionBuilder {
  /// Augments an existing constructor body with [body].
  ///
  /// TODO: Link the library augmentations proposal to describe the semantics.
  void augment({FunctionBodyCode? body, List<Code>? initializers});
}

/// The apis used by [Macro]s to augment functions or methods.
abstract class FunctionDefinitionBuilder implements DefinitionBuilder {
  /// Augments the function.
  ///
  /// TODO: Link the library augmentations proposal to describe the semantics.
  void augment(FunctionBodyCode body);
}

/// The api used by [Macro]s to augment a field.
abstract class FieldDefinitionBuilder implements DefinitionBuilder {
  /// Augments the field.
  ///
  /// TODO: Link the library augmentations proposal to describe the semantics.
  void augment({
    DeclarationCode? getter,
    DeclarationCode? setter,
    ExpressionCode? initializer,
  });
}
