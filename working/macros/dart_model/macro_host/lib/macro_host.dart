// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:macro_protocol/host.dart';

import 'socket_client.dart';

class MacroHost implements Host {
  @override
  final Service service;
  final File? Function(Uri) uriConverter;
  ServerSocket? serverSocket;
  final Map<String, Map<QualifiedName, String>> _augmentationsByMacroByUri = {};
  final Set<String> _augmentationsToWrite = {};

  int _augmentationCounter = 0;
  bool _flushing = false;

  MacroHost(this.service, this.uriConverter);

  Future<void> run() async {
    serverSocket = await ServerSocket.bind('localhost', 26199);
    print('Listening on localhost:26199.');
    print('~~~ hosting');
    await for (final socket in serverSocket!) {
      print('Incoming connection.');
      socket.setOption(SocketOption.tcpNoDelay, true);
      SocketClient(this, socket);
    }
  }

  @override
  Future<void> augment({
    required QualifiedName macro,
    required Map<String, String> augmentationsByUri,
  }) async {
    final size =
        augmentationsByUri.values.map((v) => v.length).fold(0, (a, b) => a + b);
    print(
        '  ${macro.name} augments ${augmentationsByUri.length} uri(s), $size char(s).');
    for (final uri in augmentationsByUri.keys) {
      if (_augmentationsByMacroByUri[uri] == null) {
        _augmentationsByMacroByUri[uri] = {};
      }
      final augmentations = _augmentationsByMacroByUri[uri]!;
      augmentations[macro] = augmentationsByUri[uri]!;
      _augmentationsToWrite.add(uri);
    }

    // Give other augmentations a chance to arrive before flushing.
    if (_flushing) return;
    ++_augmentationCounter;
    final augmentationCounter = _augmentationCounter;
    unawaited(Future.delayed(Duration(milliseconds: 20)).then<void>((_) async {
      if (_augmentationCounter != augmentationCounter) return;
      _flushing = true;
      while (_augmentationsToWrite.isNotEmpty) {
        await flushAugmentations();
      }
      _flushing = false;
    }));
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
}
