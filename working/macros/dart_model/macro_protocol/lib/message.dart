// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/delta.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';

extension type Message.fromJson(Map<String, Object?> node) {
  bool get isWatchRequest => node['type'] == 'watch';
  WatchRequest get asWatchRequest => this as WatchRequest;

  bool get isRound => node['type'] == 'round';
  Round get asRound => this as Round;

  bool get isAugmentRequest => node['type'] == 'augment';
  AugmentRequest get asAugmentRequest => this as AugmentRequest;
  bool get isAugmentResponse => node['type'] == 'augmentResponse';
  AugmentResponse get asAugmentResponse => this as AugmentResponse;
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

extension type Round.fromJson(Map<String, Object?> node) {
  Round({required int round, required int id, required Delta delta})
      : this.fromJson({
          'type': 'round',
          'round': round,
          'id': id,
          'delta': delta.node,
        });

  int get round => node['round'] as int;
  int get id => node['id'] as int;
  Delta get delta => node['delta'] as Delta;
}

extension type AugmentRequest.fromJson(Map<String, Object?> node)
    implements Message {
  AugmentRequest({
    required QualifiedName macro,
    required int round,
    required Map<String, String> augmentationsByUri,
  }) : this.fromJson({
          'type': 'augment',
          'macro': macro.toString(),
          'round': round,
          'augmentationsByUri': augmentationsByUri,
        });

  QualifiedName get macro => QualifiedName.tryParse(node['macro'] as String)!;
  int get round => node['round'] as int;
  Map<String, String> get augmentationsByUri =>
      (node['augmentationsByUri'] as Map).cast();
}

extension type AugmentResponse.fromJson(Map<String, Object?> node) {
  AugmentResponse()
      : this.fromJson({
          'type': 'augmentResponse',
        });
}
