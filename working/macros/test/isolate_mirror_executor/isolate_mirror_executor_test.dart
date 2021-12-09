import 'dart:io';

import '../../api/src/protocol/isolate_mirror_executor.dart';
import '../../api/expansion_protocol.dart';

import 'package:test/test.dart';

void main() {
  late MacroExecutor executor;

  setUp(() async {
    executor = await IsolateMirrorMacroExecutor.start();
  });

  test('can load macros and get back an ID', () async {
    var id = await executor.loadMacro(
        File('test/isolate_mirror_executor/simple_macro.dart').absolute.uri,
        'SimpleMacro');
    expect(id, isNotNull);
  });
}
