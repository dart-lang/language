// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:macro_client/macro.dart';

import 'socket_service.dart';

class MacroClient {
  final List<String> arguments;

  MacroClient(this.arguments);

  Future<void> host(List<Macro> macros) async {
    final socket = await Socket.connect('localhost', 26199);
    final host = SocketService(socket);
    for (final macro in macros) {
      macro.start(host);
    }
  }
}
