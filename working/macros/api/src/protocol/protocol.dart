/// Defines the objects used for communication between the macro executor and
/// the isolate doing the work of macro loading and execution.
library protocol;

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
