// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:macro_proposal/data_class.dart';

void main() {
  var joe = User(age: 25, name: 'Joe', username: 'joe1234');
  print(joe);

  var phoenix = joe.copyWith(name: 'Phoenix', age: 23);
  print(phoenix);
}

@DataClass()
class User {
  final int age;
  final String name;
  final String username;
}

@DataClass()
class Manager extends User {
  final List<User> reports;
}
