import 'dart:async';

import 'builders.dart';
import 'introspection.dart';

/// The marker interface for all types of macros.
abstract class Macro {}

/// The marker interface for macros that are allowed to contribute new type
/// declarations into the program.
///
/// These macros run before all other types of macros.
///
/// In exchange for the power to add new type declarations, these macros have
/// limited introspections capabilities, since new types can be added in this
/// phase you cannot follow type references back to their declarations.
abstract class TypeMacro implements Macro {}

/// The marker interface for macros that are allowed to contribute new
/// declarations to the program, including both top level and class level
/// declarations.
///
/// These macros run after [TypeMacro]s, but before [DefinitionMacro]s.
///
/// These macros can resolve type annotations to specific declarations, and
/// inspect type hierarchies, but they cannot inspect the declarations on those
/// type annotations, since new declarations could still be added in this phase.
abstract class DeclarationMacro implements Macro {}

/// The marker interface for macros that are only allowed to implement or wrap
/// existing declarations in the program. They cannot introduce any new
/// declarations that are visible to the program, but are allowed to add
/// declarations that only they can see.
///
/// These macros run after all other types of macros.
///
/// These macros can fully reflect on the program since the static shape is
/// fully definied by the time they run.
abstract class DefinitionMacro implements Macro {}

/// The interface for [TypeMacro]s that can be applied to classes.
abstract class ClassTypeMacro implements TypeMacro {
  FutureOr<void> visitClassType(ClassDeclaration type, TypeBuilder builder);
}

/// The interface for [DeclarationMacro]s that can be applied to classes.
abstract class ClassDeclarationMacro implements DeclarationMacro {
  FutureOr<void> visitClassDeclaration(
      ClassDeclaration declaration, ClassDeclarationBuilder builder);
}

/// The interface for [TypeMacro]s that can be applied to fields.
abstract class FieldTypeMacro implements TypeMacro {
  FutureOr<void> visitFieldType(FieldDeclaration field, TypeBuilder builder);
}

/// The interface for [DeclarationMacro]s that can be applied to fields.
abstract class FieldDeclarationMacro implements DeclarationMacro {
  FutureOr<void> visitFieldDeclaration(
      FieldDeclaration declaration, ClassDeclarationBuilder builder);
}

/// The interface for [DefinitionMacro]s that can be applied to fields.
abstract class FieldDefinitionMacro implements DefinitionMacro {
  FutureOr<void> visitFieldDefinition(
      FieldDeclaration definition, FieldDefinitionBuilder builder);
}

/// The interface for [TypeMacro]s that can be applied to top level functions
/// or methods.
abstract class FunctionTypeMacro implements TypeMacro {
  FutureOr<void> visitFunctionType(
      FunctionDeclaration type, TypeBuilder builder);
}

/// The interface for [DeclarationMacro]s that can be applied to top level
/// functions or methods.
abstract class FunctionDeclarationMacro implements DeclarationMacro {
  FutureOr<void> visitFunctionDeclaration(
      FunctionDeclaration declaration, DeclarationBuilder builder);
}

/// The interface for [DefinitionMacro]s that can be applied to top level
/// functions or methods.
abstract class FunctionDefinitionMacro implements DefinitionMacro {
  FutureOr<void> visitFunctionDefinition(
      FunctionDeclaration definition, FunctionDefinitionBuilder builder);
}

/// The interface for [TypeMacro]s that can be applied to methods.
abstract class MethodTypeMacro implements TypeMacro {
  FutureOr<void> visitMethodType(MethodDeclaration type, TypeBuilder builder);
}

/// The interface for [DeclarationMacro]s that can be applied to methods.
abstract class MethodDeclarationMacro implements DeclarationMacro {
  FutureOr<void> visitMethodDeclaration(
      MethodDeclaration declaration, ClassDeclarationBuilder builder);
}

/// The interface for [DefinitionMacro]s that can be applied to methods.
abstract class MethodDefinitionMacro implements DefinitionMacro {
  FutureOr<void> visitMethodDefinition(
      MethodDeclaration definition, FunctionDefinitionBuilder builder);
}

/// The interface for [TypeMacro]s that can be applied to constructors.
abstract class ConstructorTypeMacro implements TypeMacro {
  FutureOr<void> visitConstructorType(
      ConstructorDeclaration type, TypeBuilder builder);
}

/// The interface for [DeclarationMacro]s that can be applied to constructors.
abstract class ConstructorDeclarationMacro implements DefinitionMacro {
  FutureOr<void> visitConstructorDeclaration(
      ConstructorDeclaration declaration, ClassDeclarationBuilder builder);
}

/// The interface for [DefinitionMacro]s that can be applied to constructors.
abstract class ConstructorDefinitionMacro implements DefinitionMacro {
  FutureOr<void> visitConstructorDefinition(
      ConstructorDeclaration definition, ConstructorDefinitionBuilder builder);
}
