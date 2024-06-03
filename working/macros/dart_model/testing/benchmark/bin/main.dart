// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:benchmark/trivial_macros/input_generator.dart';
import 'package:benchmark/workspace.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    print('''
Creates packages to benchmark macro performance. Usage:

  dart bin/main.dart <workspace name> <macro|dartModel|manual|none> <# libraries>
''');
    exit(1);
  }

  final workspaceName = arguments[0];
  final strategy = Strategy.values.where((e) => e.name == arguments[1]).single;
  final libraryCount = int.parse(arguments[2]);

  print('Creating under: /tmp/dart_model_benchmark/$workspaceName');
  final workspace = Workspace(workspaceName);
  final inputGenerator = TrivialMacrosInputGenerator(
      fieldsPerClass: 100,
      classesPerLibrary: 10,
      librariesPerCycle: libraryCount,
      strategy: strategy);
  inputGenerator.generate(workspace);
  await workspace.pubGet();
}
