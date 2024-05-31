// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:macro_protocol/message.dart';

abstract interface class Host {
  Future<Stream<Round>> watch(Query query);

  Future<void> augment({
    required QualifiedName macro,
    required int round,
    required Map<String, String> augmentationsByUri,
  });
}
