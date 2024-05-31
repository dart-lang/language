// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/delta.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';

extension type Message.fromJson(Map<String, Object?> node) {
  bool get isWatchRequest => node['type'] == 'watch';
  WatchRequest get asWatchRequest => this as WatchRequest;
  bool get isWatchResponse => node['type'] == 'watchResponse';
  WatchResponse get asWatchResponse => this as WatchResponse;

  bool get isQueryRequest => node['type'] == 'query';
  QueryRequest get asQueryRequest => this as QueryRequest;
  bool get isQueryResponse => node['type'] == 'queryResponse';
  QueryResponse get asQueryResponse => this as QueryResponse;

  bool get isAugmentRequest => node['type'] == 'augment';
  AugmentRequest get asAugmentRequest => this as AugmentRequest;
  bool get isAugmentResponse => node['type'] == 'augmentResponse';
  AugmentResponse get asAugmentResponse => this as AugmentResponse;
}

extension type QueryRequest.fromJson(Map<String, Object?> node)
    implements Message {
  QueryRequest(Query query)
      : this.fromJson({
          'type': 'query',
          'query': query.node,
        });

  Query get query => node['query'] as Query;
}

extension type QueryResponse.fromJson(Map<String, Object?> node)
    implements Message {
  QueryResponse(Model model)
      : this.fromJson({
          'type': 'queryResponse',
          'model': model.node,
        });

  Model get model => node['model'] as Model;
}

extension type WatchRequest.fromJson(Map<String, Object?> node)
    implements Message {
  WatchRequest({required Query query, required int id})
      : this.fromJson({
          'type': 'watch',
          'query': query.node,
          'id': id,
        });

  Query get query => node['query'] as Query;
  int get id => node['id'] as int;
}

extension type WatchResponse.fromJson(Map<String, Object?> node) {
  WatchResponse({required Delta delta, required int id})
      : this.fromJson({
          'type': 'watchResponse',
          'delta': delta.node,
          'id': id,
        });

  int get id => node['id'] as int;
  Delta get delta => node['delta'] as Delta;
}

extension type AugmentRequest.fromJson(Map<String, Object?> node)
    implements Message {
  AugmentRequest({
    required QualifiedName macro,
    required Map<String, String> augmentationsByUri,
  }) : this.fromJson({
          'type': 'augment',
          'macro': macro.toString(),
          'augmentationsByUri': augmentationsByUri,
        });

  QualifiedName get macro => QualifiedName.tryParse(node['macro'] as String)!;
  Map<String, String> get augmentationsByUri =>
      (node['augmentationsByUri'] as Map).cast();
}

extension type AugmentResponse.fromJson(Map<String, Object?> node) {
  AugmentResponse()
      : this.fromJson({
          'type': 'augmentResponse',
        });
}
