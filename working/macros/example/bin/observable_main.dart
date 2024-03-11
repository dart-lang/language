// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:macro_proposal/observable.dart';

void main() {
  var jack = ObservableUser(age: 10, name: 'jack');
  jack.age = 12;
  jack.name = 'john';
}

class ObservableUser {
  @Observable()
  int _age;

  @Observable()
  String _name;

  ObservableUser({
    required int age,
    required String name,
  })  : _age = age,
        _name = name;
}
