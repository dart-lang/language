// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:macro_client/macro.dart';

import 'socket_host.dart';

class MacroClient {
  final List<String> arguments;

  MacroClient(this.arguments);

  Future<void> run(List<Macro> macros) async {
    print('~~~ setup');
    print('Connect to localhost:26199.');
    Socket socket;
    try {
      socket = await Socket.connect('localhost', 26199);
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {
      print('Connection failed! Is `package:macro_host` running?');
      exit(1);
    }
    final host = SocketHost(socket);

    print('~~~ running macros');
    for (var i = 0; i != macros.length; ++i) {
      final macro = macros[i];
      print('${i + 1}. ${macro.name}');
      macro.start(host);
    }
  }
}
