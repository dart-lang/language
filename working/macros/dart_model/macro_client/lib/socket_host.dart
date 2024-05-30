// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_model/delta.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:macro_protocol/host.dart';
import 'package:macro_protocol/message.dart';

class SocketHost implements Service, Host {
  final Socket socket;
  final StreamController<Object?> messagesController =
      StreamController.broadcast();
  Stream<Object?> get messages => messagesController.stream;
  int _id = 0;
  final Map<int, StreamController<Delta>> _deltaStreams = {};

  SocketHost(this.socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((m) => _handle(json.decode(m) as Message));
  }

  @override
  Future<Model> query(Query query) async {
    socket.writeln(json.encode(QueryRequest(query)));
    return Model.fromJson((await messages.first) as Map<String, Object?>);
  }

  @override
  Future<Stream<Delta>> watch(Query query) async {
    ++_id;
    socket.writeln(json.encode(WatchRequest(query: query, id: _id)));
    final result = StreamController<Delta>();
    _deltaStreams[_id] = result;
    return result.stream;
  }

  void _handle(Message message) {
    if (message.isWatchResponse) {
      final response = message.asWatchResponse;
      _deltaStreams[response.id]!.add(response.delta);
    } else {
      messagesController.add(message);
    }
  }

  @override
  Service get service => this;

  @override
  Future<void> augment(
      {required QualifiedName macro,
      required String uri,
      required String augmentation}) async {
    socket.writeln(json.encode(
        AugmentRequest(macro: macro, uri: uri, augmentation: augmentation)));
  }
}
