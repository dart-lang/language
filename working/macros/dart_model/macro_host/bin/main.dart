// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:dart_model_analyzer_service/dart_model_analyzer_service.dart';
import 'package:macro_host/macro_host.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    _usage();
  }
  final workspace = arguments[0];
  if (!Directory(workspace).existsSync()) {
    _usage();
  }

  print('~~~ setup');
  print('Launching analyzer on: $workspace');
  final contextCollection =
      AnalysisContextCollection(includedPaths: [workspace]);
  final analysisContext = contextCollection.contextFor(workspace);
  final host = DartModelAnalyzerService(context: analysisContext);
  await MacroHost(workspace, host, (uri) {
    final path = analysisContext.currentSession.uriConverter.uriToPath(uri);
    if (path == null) return null;
    return File(path);
  }).run();
}

void _usage() {
  print('''
Usage: dart bin/main.dart <absolute path to workspace>

Hosts macros in a workspace, so they can react to changes in the workspace
and write updates to augmentations.
''');
  exit(1);
}
