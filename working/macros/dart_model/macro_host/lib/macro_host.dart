// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_model/delta.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:macro_protocol/message.dart';
import 'package:stream_transform/stream_transform.dart';

import 'socket_client.dart';

class MacroHost {
  final String workspace;

  final Service service;
  final File? Function(Uri) uriConverter;
  ServerSocket? serverSocket;
  final Map<String, Map<QualifiedName, String>> _augmentationsByMacroByUri = {};
  final Set<String> _augmentationsToWrite = {};

  final List<Watch> _watches = [];

  int round = 0;
  int pendingResponses = 0;

  MacroHost(this.workspace, this.service, this.uriConverter);

  Future<void> run() async {
    _watch();
    _listen();
  }

  void _watch() async {
    // TODO(davidmorgan): watch recursivly.
    print('Watching for file changes: $workspace');
    final changeLists = Directory('$workspace/lib')
        .watch()
        .asBroadcastStream()
        .debounceBuffer(Duration(milliseconds: 20));
    await for (final changeList in changeLists) {
      _changeFiles(changeList);
    }
  }

  void _changeFiles(List<FileSystemEvent> changeList) async {
    final changes = changeList.map((e) => e.path).toSet().toList()..sort();
    print('${changes.length} file(s) changed: ${changes.take(3)}');
    final stopwatch = Stopwatch()..start();
    await service.changeFiles(changes);

    final futures = <Future>[];
    for (final watch in _watches) {
      futures.add(() async {
        final model = await service.query(watch.query);
        final delta = Delta.compute(watch.previousModel, model);
        watch.previousModel = model;
        watch.delta = delta;
      }());
    }
    await Future.wait(futures);
    print('Requeried in ${stopwatch.elapsedMilliseconds}ms.');

    if (_watches.every((w) => w.delta!.isEmpty)) {
      print('No changes relevant to macros, not starting new round.');
    } else {
      ++round;
      print('Entered round $round, sending to ${_watches.length} watches.');
      pendingResponses = _watches.length;
      for (final watch in _watches) {
        watch.sender(Round(round: round, id: watch.id, delta: watch.delta!));
        watch.delta = null;
      }
    }
  }

  void _listen() async {
    serverSocket = await ServerSocket.bind('localhost', 26199);
    print('Listening on: localhost:26199');

    print('~~~ hosting');
    await for (final socket in serverSocket!) {
      print('Incoming connection.');
      socket.setOption(SocketOption.tcpNoDelay, true);
      SocketClient(this, socket);
      // Send first data without waiting for file changes.
      // TODO(davidmorgan): better way of doing this.
      unawaited(Future.delayed(Duration(seconds: 1)).then((_) {
        _changeFiles([]);
      }));
    }
  }

  Future<void> augment({
    required QualifiedName macro,
    required int round,
    required Map<String, String> augmentationsByUri,
  }) async {
    final size =
        augmentationsByUri.values.map((v) => v.length).fold(0, (a, b) => a + b);
    print('  ${macro.name} augments ${augmentationsByUri.length} uri(s),'
        ' $size char(s), round $round.');
    for (final uri in augmentationsByUri.keys) {
      if (_augmentationsByMacroByUri[uri] == null) {
        _augmentationsByMacroByUri[uri] = {};
      }
      final augmentations = _augmentationsByMacroByUri[uri]!;
      augmentations[macro] = augmentationsByUri[uri]!;
      _augmentationsToWrite.add(uri);
    }

    // TODO(davidmorgan): coordinate this better so as to e.g. time out when
    // no response arrives.
    --pendingResponses;
    if (pendingResponses == 0) {
      await flushAugmentations();
    }
  }

  Future<void> flushAugmentations() async {
    final augmentationsToWrite = _augmentationsToWrite.toList();
    _augmentationsToWrite.clear();
    final futures = <Future>[];
    for (final uri in augmentationsToWrite) {
      final augmentations = _augmentationsByMacroByUri[uri]!;
      final baseFile = uriConverter(Uri.parse(uri))!;
      final baseName =
          baseFile.path.substring(baseFile.path.lastIndexOf('/') + 1);
      final augmentationFile =
          File(baseFile.path.replaceAll('.dart', '.a.dart'));
      print('Write: ${augmentationFile.path}');
      futures.add(augmentationFile.writeAsString('''
augment library '$baseName';

${augmentations.values.join('\n\n')}
'''));
    }
    await Future.wait(futures);
  }

  void watch(Query query, int id, void Function(Round) sender) async {
    print('Watching: $query');
    _watches.add(Watch(query, id, sender));
  }
}

class Watch {
  final Query query;
  final int id;
  void Function(Round) sender;
  Model previousModel = Model();
  bool first = true;
  Delta? delta;

  Watch(this.query, this.id, this.sender);
}
