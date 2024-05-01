// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:macro_proposal/json_serializable.dart';

void main() {
  var rand = Random();
  var rogerJson = {
    'age': rand.nextInt(100),
    'name': 'Roger',
    'username': 'roger1337'
  };
  var user = User.fromJson(rogerJson);
  print(user);
  print(user.toJson());
}

@JsonSerializable()
class User {
  final int age;
  final String name;
  final String username;

  User({required this.age, required this.name, required this.username});
}
