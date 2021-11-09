import 'dart:async';

import 'builders.dart';
import 'introspection.dart';

/// The marker interface for all types of macros.
abstract class Macro {
  const Macro();

  external void buildTypes(FutureOr<void> Function(TypeBuilder) callback);

  external void buildDeclarations(
      FutureOr<void> Function(DeclarationBuilder) callback);
}

/// The interface for [Macro]s that can be applied to any top level function,
/// instance method, or static method.
abstract class FunctionMacro extends Macro {
  const FunctionMacro();

  FutureOr<void> visitFunction(FunctionDeclaration function);

  @override
  external void buildDeclarations(
      FutureOr<void> Function(DeclarationBuilder) callback);

  external void buildDefinition(
      FutureOr<void> Function(FunctionDefinitionBuilder) callback);
}

/// The interface for [Macro]s that can be applied to classes.
abstract class ClassMacro extends Macro {
  const ClassMacro();

  FutureOr<void> visitClass(ClassDeclaration clazz);

  @override
  external void buildDeclarations(
      FutureOr<void> Function(ClassDeclarationBuilder) callback);

  external void buildDefinitions(
      FutureOr<void> Function(ClassDefinitionBuilder) callback);
}

/// The interface for [Macro]s that can be applied to fields.
abstract class FieldMacro extends Macro {
  const FieldMacro();

  FutureOr<void> visitField(FieldDeclaration field);

  @override
  external void buildDeclarations(
      FutureOr<void> Function(ClassMemberDeclarationBuilder) callback);

  external void buildDefinition(
      FutureOr<void> Function(FieldDefinitionBuilder) callback);
}

/// The interface for [Macro]s that can be applied to methods.
abstract class MethodMacro extends Macro {
  const MethodMacro();

  FutureOr<void> visitMethod(MethodDeclaration method);

  @override
  external void buildDeclarations(
      FutureOr<void> Function(ClassMemberDeclarationBuilder) callback);

  external void buildDefinition(
      FutureOr<void> Function(FunctionDefinitionBuilder) callback);
}

/// The interface for [Macro]s that can be applied to constructors.
abstract class ConstructorMacro extends Macro {
  const ConstructorMacro();

  FutureOr<void> visitConstructor(ConstructorDeclaration constructor);

  @override
  external void buildDeclarations(
      FutureOr<void> Function(ClassMemberDeclarationBuilder) callback);

  external void buildDefinition(
      FutureOr<void> Function(ConstructorDefinitionBuilder) callback);
}
