/// Defines the objects used for communication between the macro executor and
/// the isolate doing the work of macro loading and execution.
library protocol;

import '../../expansion_protocol.dart';

/// A generic response object that is either an instance of [T] or an error.
class GenericResponse<T> {
  final T? response;
  final Object? error;

  GenericResponse({this.response, this.error})
      : assert(response != null || error != null),
        assert(response == null || error == null);
}

/// A request to load a macro in this isolate.
class LoadMacroRequest {
  final Uri library;
  final String name;

  LoadMacroRequest(this.library, this.name);
}

/// A request to instantiate a macro instance.
class InstantiateMacroRequest {
  final MacroClassIdentifier macroClass;
  final String constructorName;
  final Arguments arguments;

  InstantiateMacroRequest(
      this.macroClass, this.constructorName, this.arguments);
}
