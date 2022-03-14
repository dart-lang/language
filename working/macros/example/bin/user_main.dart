// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:macro_proposal/data_class.dart';

void main() {
  var rand = Random();
  var roger =
      User.gen(age: rand.nextInt(100), name: 'Roger', username: 'roger1337');
  print(roger);
  var joe = Manager.gen(
      age: rand.nextInt(100),
      name: 'Joe',
      username: 'joe1234',
      reports: [roger]);
  print(joe);

  var phoenix =
      joe.copyWith(name: 'Phoenix', age: rand.nextInt(100), reports: [joe]);
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
