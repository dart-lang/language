// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:dart_model_analyzer_service/dart_model_analyzer_service.dart';
import 'package:test/test.dart';

void main() {
  final directory = Directory('goldens/lib');
  final dartFiles = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final contextBuilder = ContextBuilder();
  final contextRoot = ContextLocator()
      .locateRoots(includedPaths: [directory.absolute.path]).first;
  final analysisContext =
      contextBuilder.createContext(contextRoot: contextRoot);
  final service = DartModelAnalyzerService(context: analysisContext);

  for (final file in dartFiles) {
    final path = file.path.replaceAll('goldens/lib/', '');
    test(path, () async {
      final golden =
          File(file.path.replaceAll('.dart', '.json')).readAsStringSync();
      await service.changeFiles([file.absolute.path]);
      final model = await service.query(Query.uri('package:goldens/$path'));
      compare(path: path, model: model, golden: golden);
    });
  }
}

void compare(
    {required String path, required Model model, required String golden}) {
  final prettyEncoder = JsonEncoder.withIndent('  ');
  final modelJson = prettyEncoder.convert(model);
  final normalizedGoldenJson = prettyEncoder.convert(json.decode(golden));

  if (modelJson == normalizedGoldenJson) return;

  final jsonPath = path.replaceAll('.dart', '.json');
  print('''
=== current golden
$normalizedGoldenJson
=== actual output, with command to update golden
cat > goldens/lib/$jsonPath <<EOF
$modelJson
EOF
===
''');
  fail('Difference found for $path model compared to $jsonPath, see above.');
}
