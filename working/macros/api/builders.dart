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
  void addTypeToLibary(DeclarationCode typeDeclaration);
}

/// The api used by [DeclarationMacro]s to contribute new (non-type)
/// declarations to the current library.
///
/// Can also be used to do subtype checks on types.
abstract class DeclarationBuilder implements Builder {
  /// Adds a new regular declaration to the surrounding library.
  ///
  /// Note that type declarations are not supported.
  void addToLibrary(DeclarationCode declaration);

  /// Returns true if [leftType] is a subtype of [rightType].
  bool isSubtypeOf(TypeAnnotation leftType, TypeAnnotation rightType);

  /// Retruns true if [leftType] is an identical type to [rightType].
  bool isExactly(TypeAnnotation leftType, TypeAnnotation rightType);
}

/// The api used by [DeclarationMacro]s to contribute new members to a class.
abstract class ClassMemberDeclarationBuilder implements DeclarationBuilder {
  /// Adds a new declaration to the surrounding class.
  void addToClass(DeclarationCode declaration);
}

/// The api used to introspect on a [ClassDeclaration].
abstract class ClassIntrospector {
  /// The fields available for [clazz].
  ///
  /// This may be incomplete if in the declaration phase and additional macros
  /// are going to run on this class.
  Stream<FieldDeclaration> fieldsOf(ClassDeclaration clazz);

  /// The methods available so far for the current class.
  ///
  /// This may be incomplete if additional declaration macros are running on
  /// this class.
  Stream<MethodDeclaration> methodsOf(ClassDeclaration clazz);

  /// The constructors available so far for the current class.
  ///
  /// This may be incomplete if additional declaration macros are running on
  /// this class.
  Stream<ConstructorDeclaration> constructorsOf(ClassDeclaration clazz);

  /// The class that is directly extended via an `extends` clause.
  Future<ClassDeclaration?> superclassOf(ClassDeclaration clazz);

  /// All of the classes that are mixed in with `with` clauses.
  Stream<ClassDeclaration> mixinsOf(ClassDeclaration clazz);
}

/// The api used by [DeclarationMacro]s to reflect on the currently available
/// members, superclass, and mixins for a given [ClassDeclaration]
abstract class ClassDeclarationBuilder
    implements ClassMemberDeclarationBuilder, ClassIntrospector {}

/// The api used by [DefinitionMacro] to get a [TypeDeclaration] for any given
/// [TypeAnnotation].
abstract class TypeIntrospector {
  Future<TypeDeclaration> typeDeclarationOf(TypeAnnotation annotation);
}

/// The base class for builders in the definition phase. These can convert
/// any [TypeAnnotation] into its corresponding [TypeDeclaration], and also
/// reflect more deeply on those.
abstract class DefinitionBuilder
    implements Builder, ClassIntrospector, TypeIntrospector {}

/// The apis used by [DefinitionMacro]s to define the body of a constructor
/// or wrap the body of an existing constructor with additional statements.
abstract class ConstructorDefinitionBuilder implements DefinitionBuilder {
  /// Augments an existing constructor body with [body].
  ///
  /// TODO: Link the library augmentations proposal to describe the semantics.
  void augment({FunctionBodyCode? body, List<Code>? initializers});
}

/// The apis used by [DefinitionMacro]s to augment functions or methods.
abstract class FunctionDefinitionBuilder implements DefinitionBuilder {
  /// Augments the function.
  ///
  /// TODO: Link the library augmentations proposal to describe the semantics.
  void augment(FunctionBodyCode body);
}

/// The api used by [DefinitionMacro]s to augment a field.
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
