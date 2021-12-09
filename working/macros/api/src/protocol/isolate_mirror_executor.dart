import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

import 'isolate_mirror_impl.dart';
import 'protocol.dart';
import '../../builders.dart';
import '../../expansion_protocol.dart';
import '../../introspection.dart';
import '../../macros.dart';

/// A [MacroExecutor] implementation which relies on [IsolateMirror.loadUri]
/// in order to load macros libraries.
///
/// All actual work happens in a separate [Isolate], and this class serves as
/// a bridge between that isolate and the language frontends.
class IsolateMirrorMacroExecutor implements MacroExecutor {
  /// The actual isolate doing macro loading and execution.
  final Isolate _macroIsolate;

  /// The channel used to send requests to the [_macroIsolate].
  final SendPort _sendPort;

  /// The stream of responses from the [_macroIsolate].
  final Stream<GenericResponse> _responseStream;

  /// The completer for the next response to come along the stream.
  var _nextResponseCompleter = Completer<GenericResponse>();

  IsolateMirrorMacroExecutor._(
      this._macroIsolate, this._sendPort, this._responseStream) {
    _responseStream.listen((event) {
      _nextResponseCompleter.complete(event);
      _nextResponseCompleter = Completer<GenericResponse>();
    });
  }

  /// Initialize an [IsolateMirrorMacroExecutor] and return it once ready.
  ///
  /// Spawns the macro isolate and sets up a communication channel.
  static Future<MacroExecutor> start() async {
    var receivePort = ReceivePort();
    var sendPortCompleter = Completer<SendPort>();
    var responseStreamController =
        StreamController<GenericResponse>(sync: true);
    receivePort.listen((message) {
      if (!sendPortCompleter.isCompleted) {
        sendPortCompleter.complete(message as SendPort);
      } else {
        responseStreamController.add(message as GenericResponse);
      }
    }).onDone(responseStreamController.close);
    var macroIsolate = await Isolate.spawn(spawn, receivePort.sendPort);

    return IsolateMirrorMacroExecutor._(macroIsolate,
        await sendPortCompleter.future, responseStreamController.stream);
  }

  @override
  Future<String> buildAugmentationLibrary(
      Iterable<MacroExecutionResult> macroResults) {
    // TODO: implement buildAugmentationLibrary
    throw UnimplementedError();
  }

  @override
  Future<MacroExecutionResult> executeDeclarationsPhase(
      MacroInstanceIdentifier macro,
      Declaration declaration,
      TypeComparator typeComparator,
      ClassIntrospector classIntrospector) {
    // TODO: implement executeDeclarationsPhase
    throw UnimplementedError();
  }

  @override
  Future<MacroExecutionResult> executeDefinitionsPhase(
      MacroInstanceIdentifier macro,
      Declaration declaration,
      TypeComparator typeComparator,
      ClassIntrospector classIntrospector,
      TypeIntrospector typeIntrospector) {
    // TODO: implement executeDefinitionsPhase
    throw UnimplementedError();
  }

  @override
  Future<MacroExecutionResult> executeTypesPhase(
      MacroInstanceIdentifier macro, Declaration declaration) {
    // TODO: implement executeTypesPhase
    throw UnimplementedError();
  }

  @override
  Future<MacroInstanceIdentifier> instantiateMacro(
      MacroClassIdentifier macroClass,
      String constructor,
      Arguments arguments) {
    // TODO: implement instantiateMacro
    throw UnimplementedError();
  }

  @override
  Future<MacroClassIdentifier> loadMacro(Uri library, String name) async {
    _sendPort.send(LoadMacroRequest(library, name));
    return _handleResponse(await _nextResponse());
  }

  T _handleResponse<T>(GenericResponse<T> response) {
    var result = response.response;
    if (result != null) return result;
    throw response.error!;
  }

  /// Gets a future for the next response, and casts it to a GenericResponse<T>.
  Future<GenericResponse<T>> _nextResponse<T>() =>
      _nextResponseCompleter.future as Future<GenericResponse<T>>;
}
