// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:dart_model_analyzer_service/dart_model_analyzer_service.dart';
import 'package:macro_host/macro_host.dart';

Future<void> main(List<String> arguments) async {
  final workspace = arguments[0];
  final contextBuilder = ContextBuilder();
  final analysisContext = contextBuilder.createContext(
      contextRoot:
          ContextLocator().locateRoots(includedPaths: [workspace]).first);
  final host = DartModelAnalyzerService(context: analysisContext);
  await MacroHost(host, (uri) {
    final path = analysisContext.currentSession.uriConverter.uriToPath(uri);
    if (path == null) return null;
    return File(path);
  }).run();
}
