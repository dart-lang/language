// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_model/query.dart';

import 'socket_client.dart';

class MacroHost {
  ServerSocket? serverSocket;
  Service host;

  MacroHost(this.host);

  Future<void> run() async {
    serverSocket = await ServerSocket.bind('localhost', 26199);
    print('macro_host listening on localhost:26199');

    await for (final socket in serverSocket!) {
      SocketClient(host, socket);
    }
  }

  void handle(Socket socket) {
    print('Got $socket');
  }
}
