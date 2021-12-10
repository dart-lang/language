import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

import 'isolate_mirror_impl.dart';
import 'protocol.dart';
import '../../builders.dart';
import '../../expansion_protocol.dart';
import '../../introspection.dart';

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

  /// A map of response completers by request id.
  final _responseCompleters = <int, Completer<GenericResponse>>{};

  /// A function that should be invoked when shutting down this executor
  /// to perform any necessary cleanup.
  final void Function() _onClose;

  IsolateMirrorMacroExecutor._(
      this._macroIsolate, this._sendPort, this._responseStream, this._onClose) {
    _responseStream.listen((event) {
      var completer = _responseCompleters.remove(event.requestId);
      if (completer == null) {
        throw StateError(
            'Got a response for an unrecognized request id ${event.requestId}');
      }
      completer.complete(event);
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

    return IsolateMirrorMacroExecutor._(
        macroIsolate,
        await sendPortCompleter.future,
        responseStreamController.stream,
        receivePort.close);
  }

  @override
  Future<String> buildAugmentationLibrary(
      Iterable<MacroExecutionResult> macroResults) {
    // TODO: implement buildAugmentationLibrary
    throw UnimplementedError();
  }

  @override
  void close() {
    _onClose();
    _macroIsolate.kill();
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
          TypeIntrospector typeIntrospector) =>
      _sendRequest(ExecuteDefinitionsPhaseRequest(macro, declaration,
          typeComparator, classIntrospector, typeIntrospector));

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
          Arguments arguments) =>
      _sendRequest(InstantiateMacroRequest(macroClass, constructor, arguments));

  @override
  Future<MacroClassIdentifier> loadMacro(Uri library, String name) =>
      _sendRequest(LoadMacroRequest(library, name));

  /// Sends a request and returns the response, casting it to the expected
  /// type.
  Future<T> _sendRequest<T>(Request request) async {
    _sendPort.send(request);
    var completer = Completer<GenericResponse<T>>();
    _responseCompleters[request.id] = completer;
    var response = await completer.future;
    var result = response.response;
    if (result != null) return result;
    throw response.error!;
  }
}
