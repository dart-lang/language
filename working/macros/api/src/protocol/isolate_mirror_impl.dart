import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

import 'protocol.dart';
import '../../builders.dart';
import '../../expansion_protocol.dart';
import '../../introspection.dart';
import '../../macros.dart';

/// Spawns a new isolate for loading and executing macros.
void spawn(SendPort sendPort) {
  var receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  receivePort.listen((message) async {
    if (message is LoadMacroRequest) {
      var response = await _loadMacro(message);
      sendPort.send(response);
    } else {
      throw StateError('Unrecognized event type $message');
    }
  });
}

/// Maps macro identifiers to class mirrors.
final _macroClasses = <_MacroClassIdentifier, ClassMirror>{};

/// Handles [LoadMacroRequest]s.
Future<GenericResponse<MacroClassIdentifier>> _loadMacro(
    LoadMacroRequest request) async {
  try {
    var identifier = _MacroClassIdentifier(request.library, request.name);
    if (_macroClasses.containsKey(identifier)) {
      return GenericResponse(
          error: UnsupportedError(
              'Reloading macros is not supported by this implementation'));
    }
    var libMirror =
        await currentMirrorSystem().isolate.loadUri(request.library);
    var macroClass =
        libMirror.declarations[Symbol(request.name)] as ClassMirror;
    _macroClasses[identifier] = macroClass;
    return GenericResponse(response: identifier);
  } catch (e, s) {
    return GenericResponse(
        error: StateError(
            'Failed to load macro ${request.library}#${request.name}\n$e\n$s'));
  }
}

/// Our implementation of [MacroClassIdentifier].
class _MacroClassIdentifier implements MacroClassIdentifier {
  final String id;

  _MacroClassIdentifier(Uri library, String name) : id = '$library#$name';

  operator ==(other) => other is _MacroClassIdentifier && id == other.id;

  int get hashCode => id.hashCode;
}
