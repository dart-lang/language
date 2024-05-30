// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_model/query.dart';
import 'package:macro_protocol/host.dart';

import 'socket_client.dart';

class MacroHost implements Host {
  @override
  final Service service;
  final File? Function(Uri) uriConverter;
  ServerSocket? serverSocket;
  final Map<String, Map<Object, String>> _augmentationsByUri = {};

  MacroHost(this.service, this.uriConverter);

  Future<void> run() async {
    serverSocket = await ServerSocket.bind('localhost', 26199);
    print('macro_host listening on localhost:26199');

    await for (final socket in serverSocket!) {
      SocketClient(this, socket);
    }
  }

  void handle(Socket socket) {
    print('Got $socket');
  }

  @override
  Future<void> augment(
      {required Object macro,
      required String uri,
      required String augmentation}) async {
    print('Augment: $uri $augmentation');
    final baseFile = uriConverter(Uri.parse(uri))!;
    final baseName =
        baseFile.path.substring(baseFile.path.lastIndexOf('/') + 1);
    final augmentationFile = File(baseFile.path.replaceAll('.dart', '.a.dart'));

    print(_augmentationsByUri);
    if (_augmentationsByUri[uri] == null) {
      print('create map');
      _augmentationsByUri[uri] = Map.identity();
    }
    final augmentations = _augmentationsByUri[uri]!;
    augmentations[macro] = augmentation;
    print(_augmentationsByUri);

    // TODO(davidmorgan): write async? Needs locking.
    augmentationFile.writeAsStringSync('''
augment library '$baseName';

${augmentations.values.join('\n\n')}
''');
  }
}
