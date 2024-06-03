// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

class Workspace {
  final String name;
  final List<String> _addedPackages = [];

  Directory get directory =>
      Directory('${Directory.systemTemp.path}/dart_model_benchmark/$name');
  String get packagePath => '${directory.path}/package_under_test';
  String get packageUri => '${directory.uri}/package_under_test';

  Workspace(this.name) {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);
  }

  void write(String path, {required String source}) {
    final file = File('$packagePath/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(source);
  }

  void delete(String path) {
    File('$packagePath/$path').deleteSync();
  }

  void addPackage({required String name, required String from}) {
    _addedPackages.add(name);
    final result = Process.runSync('cp', ['-a', from, directory.path]);
    if (result.exitCode != 0) throw '${result.stdout} ${result.stderr}';
  }

  Future<void> pubGet() async {
    final moreDependencies = StringBuffer();
    final moreDependencyOverrides = StringBuffer();
    for (final package in _addedPackages) {
      moreDependencies.writeln('  $package: any');
      moreDependencyOverrides.writeln('  $package:');
      moreDependencyOverrides.writeln('    path: ../$package');
    }

    write('pubspec.yaml', source: '''
name: package_under_test
publish_to: none

environment:
  sdk: ^3.4.0

dependencies:
  macros: ^0.1.0
$moreDependencies

dev_dependencies:
  build_runner: any

dependency_overrides:
  _macros:
    sdk: dart
    version: any
$moreDependencyOverrides
''');
    final result = await Process.run('dart', ['pub', 'get'],
        workingDirectory: packagePath);
    if (result.exitCode != 0) throw result.stderr;
  }
}
