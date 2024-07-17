// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

final _random = Random.secure();
int get largeRandom =>
    _random.nextInt(0xFFFFFFFF) + (_random.nextInt(0x7FFFFFFF) << 32);
