// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:benchmark/random.dart';
import 'package:benchmark/workspace.dart';

enum Strategy {
  manual,
  dartModel,
  macro,
  none;

  String annotation(String name) {
    switch (this) {
      case Strategy.manual:
      case Strategy.none:
        return '';
      case Strategy.macro:
      case Strategy.dartModel:
        return '@$name()';
    }
  }
}

class TrivialMacrosInputGenerator {
  final int fieldsPerClass;
  final int classesPerLibrary;
  final int librariesPerCycle;
  final Strategy strategy;

  TrivialMacrosInputGenerator(
      {required this.fieldsPerClass,
      required this.classesPerLibrary,
      required this.librariesPerCycle,
      required this.strategy});

  void generate(Workspace workspace) {
    // The "macros" experiment is needed for augmentations.
    if (strategy == Strategy.macro || strategy == Strategy.dartModel) {
      workspace.write('analysis_options.yaml', source: '''
analyzer:
  enable-experiment:
    - macros
''');
    }

    if (strategy == Strategy.macro) {
      workspace.write('lib/macros.dart',
          source: File('lib/trivial_macros/macros.dart').readAsStringSync());
    }

    if (strategy == Strategy.dartModel) {
      workspace.addPackage(
          name: 'test_macro_annotations', from: '../test_macro_annotations');
    }

    for (var i = 0; i != librariesPerCycle; ++i) {
      workspace.write('lib/a$i.dart', source: _generateLibrary(i));
    }
  }

  String _generateLibrary(int index,
      {bool topLevelCacheBuster = false, bool fieldCacheBuster = false}) {
    final buffer = StringBuffer();

    if (strategy == Strategy.macro) {
      buffer.writeln("import 'macros.dart';");
    }

    if (strategy == Strategy.dartModel) {
      buffer
          .writeln("import 'package:test_macro_annotations/annotations.dart';");
      buffer.writeln("import augment 'a$index.a.dart';");
    }

    if (librariesPerCycle != 1) {
      final nextLibrary = (index + 1) % librariesPerCycle;
      buffer.writeln('import "a$nextLibrary.dart" as next_in_cycle;');
      buffer.writeln('next_in_cycle.A0? referenceOther;');
    }

    if (topLevelCacheBuster) {
      buffer.writeln('int? cacheBuster$largeRandom;');
    }

    for (var j = 0; j != classesPerLibrary; ++j) {
      buffer.write(_generateClass(j, fieldCacheBuster: fieldCacheBuster));
    }

    return buffer.toString();
  }

  String _generateClass(int index, {required bool fieldCacheBuster}) {
    final className = 'A$index';
    String fieldName(int index) => 'a$index';

    final result = StringBuffer('''
${strategy.annotation('Equals')}
${strategy.annotation('HashCode')}
${strategy.annotation('ToString')}
''');

    result.writeln('class $className {');
    if (fieldCacheBuster) {
      result.writeln('int? b$largeRandom;');
    }
    for (var i = 0; i != fieldsPerClass; ++i) {
      result.writeln('int? ${fieldName(i)};');
    }

    if (strategy == Strategy.manual) {
      result.writeln([
        'operator==(other) => other is ',
        className,
        for (var i = 0; i != fieldsPerClass; ++i) ...[
          '&&',
          fieldName(i),
          ' == other.',
          fieldName(i),
        ],
        ";",
      ].join(''));

      result.writeln([
        'get hashCode {',
        'hashType<T>() => T.hashCode;',
        'return hashType<',
        className,
        '>()',
        for (var i = 0; i != fieldsPerClass; ++i) ...[
          ' ^ ',
          fieldName(i),
          '.hashCode',
        ],
        ";}",
      ].join(''));

      result.writeln([
        "toString() => '\${",
        className,
        '}(',
        for (var i = 0; i != fieldsPerClass; ++i) ...[
          fieldName(i),
          ': \$',
          fieldName(i),
          if (i != fieldsPerClass - 1) ', ',
        ],
        ")';",
      ].join(''));
    }

    result.writeln('}');
    return result.toString();
  }
}
