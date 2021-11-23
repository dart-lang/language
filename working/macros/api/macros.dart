import 'dart:async';

import 'builders.dart';
import 'introspection.dart';

/// The marker interface for all types of macros.
abstract class Macro {}

/// The interface for [Macro]s that can be applied to any top level function,
/// instance method, or static method, and wants to contribute new type
/// declarations to the program.
abstract class FunctionTypesMacro implements Macro {
  FutureOr<void> buildTypesForFunction(
      FunctionDeclaration function, TypeBuilder builder);
}

/// The interface for [Macro]s that can be applied to any top level function,
/// instance method, or static method, and wants to contribute new non-type
/// declarations to the program.
abstract class FunctionDeclarationsMacro implements Macro {
  FutureOr<void> buildDeclarationsForFunction(
      FunctionDeclaration function, DeclarationBuilder builder);
}

/// The interface for [Macro]s that can be applied to any top level function,
/// instance method, or static method, and wants to augment the function
/// definition.
abstract class FunctionDefinitionMacro implements Macro {
  FutureOr<void> buildDefinitionForFunction(
      FunctionDeclaration function, FunctionDefinitionBuilder builder);
}

/// The interface for [Macro]s that can be applied to any top level variable or
/// instance field, and wants to contribute new type declarations to the
/// program.
abstract class VariableTypesMacro implements Macro {
  FutureOr<void> buildTypesForVariable(
      VariableDeclaration variable, TypeBuilder builder);
}

/// The interface for [Macro]s that can be applied to any top level variable or
/// instance field and wants to contribute new non-type declarations to the
/// program.
abstract class VariableDeclarationsMacro implements Macro {
  FutureOr<void> buildDeclarationsForVariable(
      VariableDeclaration variable, DeclarationBuilder builder);
}

/// The interface for [Macro]s that can be applied to any top level variable
/// or instance field, and wants to augment the variable definition.
abstract class VariableDefinitionMacro implements Macro {
  FutureOr<void> buildDefinitionForFunction(
      VariableDeclaration variable, VariableDefinitionBuilder builder);
}

/// The interface for [Macro]s that can be applied to any class, and wants to
/// contribute new type declarations to the program.
abstract class ClassTypesMacro implements Macro {
  FutureOr<void> buildTypesForClass(
      ClassDeclaration clazz, TypeBuilder builder);
}

/// The interface for [Macro]s that can be applied to any class, and wants to
/// contribute new non-type declarations to the program.
abstract class ClassDeclarationsMacro implements Macro {
  FutureOr<void> buildDeclarationsForClass(
      ClassDeclaration clazz, ClassDeclarationBuilder builder);
}

/// The interface for [Macro]s that can be applied to any class, and wants to
/// augment the definitions of members on the class.
abstract class ClassDefinitionMacro implements Macro {
  FutureOr<void> buildDefinitionForClass(
      ClassDeclaration clazz, ClassDefinitionBuilder builder);
}

/// The interface for [Macro]s that can be applied to any field, and wants to
/// contribute new type declarations to the program.
abstract class FieldTypesMacro implements Macro {
  FutureOr<void> buildTypesForField(
      FieldDeclaration field, TypeBuilder builder);
}

/// The interface for [Macro]s that can be applied to any field, and wants to
/// contribute new type declarations to the program.
abstract class FieldDeclarationsMacro implements Macro {
  FutureOr<void> buildTypesForField(
      FieldDeclaration field, ClassMemberDeclarationBuilder builder);
}

/// The interface for [Macro]s that can be applied to any field, and wants to
/// augement the field definition.
abstract class FieldDefinitionsMacro implements Macro {
  FutureOr<void> buildDefinitionForField(
      FieldDeclaration field, VariableDefinitionBuilder builder);
}

/// The interface for [Macro]s that can be applied to any method, and wants to
/// contribute new type declarations to the program.
abstract class MethodTypesMacro implements Macro {
  FutureOr<void> buildTypesForMethod(
      MethodDeclaration method, TypeBuilder builder);
}

/// The interface for [Macro]s that can be applied to any method, and wants to
/// contribute new non-type declarations to the program.
abstract class MethodDeclarationDeclarationsMacro implements Macro {
  FutureOr<void> buildDeclarationsForMethod(
      MethodDeclaration method, ClassMemberDeclarationBuilder builder);
}

/// The interface for [Macro]s that can be applied to any method, and wants to
/// augment the function definition.
abstract class MethodDefinitionMacro implements Macro {
  FutureOr<void> buildDefinitionForMethod(
      MethodDeclaration method, FunctionDefinitionBuilder builder);
}

/// The interface for [Macro]s that can be applied to any constructor, and wants
/// to contribute new type declarations to the program.
abstract class ConstructorTypesMacro implements Macro {
  FutureOr<void> buildTypesForConstructor(
      ConstructorDeclaration method, TypeBuilder builder);
}

/// The interface for [Macro]s that can be applied to any constructors, and
/// wants to contribute new non-type declarations to the program.
abstract class ConstructorDeclarationDeclarationsMacro implements Macro {
  FutureOr<void> buildDeclarationsForConstructor(
      ConstructorDeclaration method, ClassMemberDeclarationBuilder builder);
}

/// The interface for [Macro]s that can be applied to any constructor, and wants
/// to augment the function definition.
abstract class ConstructorDefinitionMacro implements Macro {
  FutureOr<void> buildDefinitionForConstructor(
      ConstructorDeclaration method, ConstructorDefinitionBuilder builder);
}
