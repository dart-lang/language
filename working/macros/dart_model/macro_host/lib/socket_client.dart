// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:dart_model/query.dart';
import 'package:macro_protocol/message.dart';

class SocketClient {
  final Service host;
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

    if (message.isQueryRequest) {
      final response = await host.query(message.asQueryRequest.query);
      socket.writeln(json.encode(QueryResponse(response)));
    } else if (message.isWatchRequest) {
      final request = message.asWatchRequest;
      final response = await host.watch(request.query);
      response.listen((delta) {
        socket
            .writeln(json.encode(WatchResponse(id: request.id, delta: delta)));
      });
    }
  }
}
