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
    } else if (message is InstantiateMacroRequest) {
      var response = await _instantiateMacro(message);
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
      throw UnsupportedError(
          'Reloading macros is not supported by this implementation');
    }
    var libMirror =
        await currentMirrorSystem().isolate.loadUri(request.library);
    var macroClass =
        libMirror.declarations[Symbol(request.name)] as ClassMirror;
    _macroClasses[identifier] = macroClass;
    return GenericResponse(response: identifier);
  } catch (e) {
    return GenericResponse(error: e);
  }
}

/// Maps macro instance identifiers to instances.
final _macroInstances = <_MacroInstanceIdentifier, Macro>{};

/// Handles [InstantiateMacroRequest]s.
Future<GenericResponse<MacroInstanceIdentifier>> _instantiateMacro(
    InstantiateMacroRequest request) async {
  try {
    var clazz = _macroClasses[request.macroClass];
    if (clazz == null) {
      throw ArgumentError('Unrecognized macro class ${request.macroClass}');
    }
    var instance = clazz.newInstance(
        Symbol(request.constructorName), request.arguments.positional, {
      for (var entry in request.arguments.named.entries)
        Symbol(entry.key): entry.value,
    }).reflectee as Macro;
    var identifier = _MacroInstanceIdentifier();
    _macroInstances[identifier] = instance;
    return GenericResponse<MacroInstanceIdentifier>(response: identifier);
  } catch (e) {
    return GenericResponse(error: e);
  }
}

/// Our implementation of [MacroClassIdentifier].
class _MacroClassIdentifier implements MacroClassIdentifier {
  final String id;

  _MacroClassIdentifier(Uri library, String name) : id = '$library#$name';

  operator ==(other) => other is _MacroClassIdentifier && id == other.id;

  int get hashCode => id.hashCode;
}

/// Our implementation of [MacroInstanceIdentifier].
class _MacroInstanceIdentifier implements MacroInstanceIdentifier {}
