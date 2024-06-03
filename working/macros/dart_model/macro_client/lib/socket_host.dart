// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:macro_protocol/host.dart';
import 'package:macro_protocol/message.dart';

class SocketHost implements Host {
  final Socket socket;
  final StreamController<Object?> messagesController =
      StreamController.broadcast();
  Stream<Object?> get messages => messagesController.stream;
  int _id = 0;
  final Map<int, StreamController<Round>> _roundStreams = {};

  SocketHost(this.socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((m) => _handle(json.decode(m) as Message));
  }

  @override
  Future<Stream<Round>> watch(Query query) async {
    ++_id;
    socket.writeln(json.encode(WatchRequest(query: query, id: _id)));
    final result = StreamController<Round>();
    _roundStreams[_id] = result;
    return result.stream;
  }

  void _handle(Message message) {
    if (message.isRound) {
      final response = message.asRound;
      _roundStreams[response.id]!.add(response);
    } else {
      messagesController.add(message);
    }
  }

  @override
  Future<void> augment({
    required QualifiedName macro,
    required int round,
    required Map<String, String> augmentationsByUri,
  }) async {
    socket.writeln(json.encode(AugmentRequest(
        macro: macro, round: round, augmentationsByUri: augmentationsByUri)));
  }
}
