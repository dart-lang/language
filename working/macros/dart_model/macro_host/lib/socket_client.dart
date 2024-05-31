// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:macro_protocol/message.dart';

import 'macro_host.dart';

class SocketClient {
  final MacroHost host;
  final Socket socket;

  SocketClient(this.host, this.socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handle);
  }

  void handle(String line) async {
    final message = Message.fromJson(json.decode(line));

    if (message.isWatchRequest) {
      final request = message.asWatchRequest;
      void send(Round round) {
        socket.writeln(json.encode(round));
      }

      host.watch(request.query, request.id, send);
    } else if (message.isAugmentRequest) {
      final request = message.asAugmentRequest;
      unawaited(host.augment(
          macro: request.macro,
          round: request.round,
          augmentationsByUri: request.augmentationsByUri));
    }
  }
}
