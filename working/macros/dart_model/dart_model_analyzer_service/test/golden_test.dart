// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:dart_model/schemas.dart' as schemas;
import 'package:dart_model_analyzer_service/dart_model_analyzer_service.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

void main() {
  final looseSchema = JsonSchema.create(schemas.loose);

  // Doesn't validate due to https://github.com/Workiva/json_schema/issues/190.
  // final strictSchema = JsonSchema.create(schemas.strict);
  final strictSchema = null;

  final directory = Directory('goldens/lib');
  final dartFiles = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final contextCollection =
      AnalysisContextCollection(includedPaths: [directory.absolute.path]);
  final analysisContext = contextCollection.contextFor(directory.absolute.path);
  final service = DartModelAnalyzerService(context: analysisContext);

  for (final file in dartFiles) {
    final path = file.path.replaceAll('goldens/lib/', '');
    test(path, () async {
      final goldenFile = File(file.path.replaceAll('.dart', '.json'));
      final golden =
          goldenFile.existsSync() ? goldenFile.readAsStringSync() : null;
      await service.changeFiles([file.absolute.path]);
      final model = await service.query(Query.uri('package:goldens/$path'));
      verify(
          path: path,
          model: model,
          golden: golden,
          looseSchema: looseSchema,
          strictSchema: strictSchema);
    });
  }
}

void verify(
    {required String path,
    required Model model,
    String? golden,
    JsonSchema? looseSchema,
    JsonSchema? strictSchema}) {
  final prettyEncoder = JsonEncoder.withIndent('  ');
  final modelJson = prettyEncoder.convert(model);

  if (looseSchema != null) {
    final results = looseSchema.validate(modelJson, parseJson: true);
    if (!results.isValid) {
      // The actual toString has a bug.
      final resultsToString = '${results.errors.isEmpty ? 'VALID' : 'INVALID'}'
          '${results.errors.isNotEmpty ? ', Errors:\n${results.errors.join('\n')}' : ''}'
          '${results.warnings.isNotEmpty ? ', Warnings:\n${results.warnings.join('\n')}' : ''}';
      print('''
=== actual output fails schema check
$modelJson
===
''');
      fail('Output does not validate against schema!\n\n$resultsToString');
    }
  }

  if (strictSchema != null) {
    final results = strictSchema.validate(modelJson, parseJson: true);
    if (!results.isValid) {
      // The actual toString has a bug.
      final resultsToString = '${results.errors.isEmpty ? 'VALID' : 'INVALID'}'
          '${results.errors.isNotEmpty ? ', Errors:\n${results.errors.join('\n')}' : ''}'
          '${results.warnings.isNotEmpty ? ', Warnings:\n${results.warnings.join('\n')}' : ''}';
      print('''
=== actual output fails strict schema check
$modelJson
===
''');
      fail(
          'Output does not validate against strict schema!\n\n$resultsToString');
    }
  }

  if (golden != null) {
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
}
