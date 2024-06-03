// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/model.dart';
import 'package:macro_protocol/host.dart';

abstract interface class Macro {
  QualifiedName get name;
  void start(Host host) {}
}
