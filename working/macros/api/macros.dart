import 'dart:async';

import 'builders.dart';
import 'introspection.dart';

/// The marker interface for all types of macros.
abstract class Macro {}

/// The interface for [Macro]s that can be applied to any top level function,
/// instance method, or static method.
abstract class FunctionMacro implements Macro {
  /// Invoked for any function that is annotated with this macro.
  FutureOr<void> visitFunction(
      FunctionDeclaration function, FunctionBuilder builder);
}

/// The interface for [Macro]s that can be applied to classes.
abstract class ClassMacro implements Macro {
  /// Invoked for any class that is annotated with this macro.
  FutureOr<void> visitClass(ClassDeclaration clazz, ClassBuilder builder);
}

/// The interface for [Macro]s that can be applied to fields.
abstract class FieldMacro implements Macro {
  /// Invoked for any field that is annotated with this macro
  FutureOr<void> visitField(FieldDeclaration field, FieldBuilder builder);
}

/// The interface for [Macro]s that can be applied to methods.
abstract class MethodMacro implements Macro {
  /// Invoked for any method that is annotated with this macro.
  FutureOr<void> visitMethod(MethodDeclaration method, MethodBuilder builder);
}

/// The interface for [Macro]s that can be applied to constructors.
abstract class ConstructorMacro implements Macro {
  /// Invoked for each constructor annotated with this macro.
  FutureOr<void> visitConstructor(ConstructorDeclaration constructor);
}
