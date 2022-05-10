// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:macro_proposal/auto_dispose.dart';
import 'package:macro_proposal/data_class.dart';
import 'package:macro_proposal/observable.dart';
import 'package:macro_proposal/json_serializable.dart';

void main() {
  var rand = Random();
  var rogerJson = {
    'age': rand.nextInt(100),
    'name': 'Roger',
    'username': 'roger1337'
  };
  var roger = User.fromJson(rogerJson);
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

  var observableUser = ObservableUser(age: 10, name: 'Georgio');
  observableUser
    ..age = 11
    ..name = 'Greg';

  var state = MyState.gen(a: ADisposable(), b: BDisposable(), c: 'hello world');
  state.dispose();

  var father = Father.fromJson({
    'age': roger.age + 25,
    'name': 'Rogers Dad',
    'username': 'dadJokesAreCool123',
    'child': rogerJson,
  });
  print(father);
}

@DataClass()
@JsonSerializable()
class User {
  final int age;
  final String name;
  final String username;
}

@DataClass()
class Manager extends User {
  final List<User> reports;
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

// TODO: remove @AutoConstructor once we can, today it is required.
@AutoConstructor()
class State {
  void dispose() {
    print('disposing of State $this');
  }
}

@AutoDispose()
@AutoConstructor()
class MyState extends State {
  final ADisposable a;
  final ADisposable? a2;
  final BDisposable b;
  final String c;
}

class ADisposable implements Disposable {
  void dispose() {
    print('disposing of ADisposable');
  }
}

class BDisposable implements Disposable {
  void dispose() {
    print('disposing of BDisposable');
  }
}

@DataClass()
@JsonSerializable()
class Father implements User {
  final int age;
  final String name;
  final String username;
  final User child;
}
