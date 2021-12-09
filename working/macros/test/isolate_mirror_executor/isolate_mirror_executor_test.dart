import 'dart:io';

import '../../api/src/protocol/isolate_mirror_executor.dart';
import '../../api/expansion_protocol.dart';

import 'package:test/test.dart';

void main() {
  late MacroExecutor executor;

  setUp(() async {
    executor = await IsolateMirrorMacroExecutor.start();
  });

  test('can load macros and create instances', () async {
    var clazzId = await executor.loadMacro(
        File('test/isolate_mirror_executor/simple_macro.dart').absolute.uri,
        'SimpleMacro');
    expect(clazzId, isNotNull);

    var instanceId =
        await executor.instantiateMacro(clazzId, '', Arguments([], {}));
    expect(instanceId, isNotNull,
        reason: 'Can create an instance with no arguments.');

    instanceId =
        await executor.instantiateMacro(clazzId, '', Arguments([1, 2], {}));
    expect(instanceId, isNotNull,
        reason: 'Can create an instance with positional arguments.');

    instanceId = await executor.instantiateMacro(
        clazzId, 'named', Arguments([], {'x': 1, 'y': 2}));
    expect(instanceId, isNotNull,
        reason: 'Can create an instance with named arguments.');
  });
}
