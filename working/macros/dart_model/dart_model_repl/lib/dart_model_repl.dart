// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:async/async.dart';
import 'package:dart_model/model.dart';
import 'package:dart_model/query.dart';
import 'package:dart_model_analyzer_service/dart_model_analyzer_service.dart';
import 'package:macro_host/macro_host.dart';

class DartModelRepl {
  final _stdinLines =
      StreamQueue(LineSplitter().bind(Utf8Decoder().bind(stdin)));
  MacroHost? host;

  Future<void> run() async {
    print(''''
Welcome to ${green}package:dart_model_repl$reset!
''');

    while (await readInput()) {}
  }

  Future<bool> readInput() async {
    if (host == null) {
      print('No host running; try "analyze <workspace>".');
    }

    stdout.write('> ');
    final line = await _stdinLines.next;
    if (line == 'exit') return false;
    if (line == 'help') {
      printHelp();
      return true;
    }

    if (line.startsWith('analyze ')) {
      createHost(line.substring('analyze '.length));
      return true;
    }

    if (line.startsWith('query ')) {
      final rest = line.substring('query '.length);
      final maybeQualifiedName = QualifiedName.tryParse(rest);
      final query = maybeQualifiedName == null
          ? Query.uri(rest)
          : Query.qualifiedName(
              uri: maybeQualifiedName.uri, name: maybeQualifiedName.name);
      final model = await host!.service.query(query);
      print(model.prettyPrint());
      return true;
    }

    if (line.startsWith('watch ')) {
      final rest = line.substring('watch '.length);
      final maybeQualifiedName = QualifiedName.tryParse(rest);
      final query = maybeQualifiedName == null
          ? Query.uri(rest)
          : Query.qualifiedName(
              uri: maybeQualifiedName.uri, name: maybeQualifiedName.name);
      final model = Model();
      host!.watch(query, 0, (round) {
        final delta = round.delta;
        delta.update(model);
        print('=== current model for $query');
        print(model.prettyPrint());
        print('=== due to delta for $query');
        print(delta.prettyPrint());
      });
      return true;
    }

    print('Unrecognized input. Try "help"?');
    return true;
  }

  void printHelp() {
    print('''
analyze <workspace path>
    Starts the analyzer query backend on <workspace path>.
query <URI>[#name]
    Queries the library at the specified URI. If specified, query for
    the scope called "name".
watch <URI>[#name]
    Like "query", but watches and prints changes.
''');
  }

  void createHost(String workspace) {
    final contextCollection =
        AnalysisContextCollection(includedPaths: [workspace]);
    final analysisContext = contextCollection.contextFor(workspace);
    final service = DartModelAnalyzerService(context: analysisContext);
    File? uriConverter(Uri uri) {
      final path = analysisContext.currentSession.uriConverter.uriToPath(uri);
      if (path == null) return null;
      return File(path);
    }

    host = MacroHost(workspace, service, uriConverter);

    // TOD0(davidmorgan): this is a hack to keep the REPL working after file
    // watching moved from the service to the host; consider whether it's worth
    // doing properly.
    unawaited(host!.run());
  }
}

final String reset = '\x1b[0m';
final String green = '\x1b[92;1m';
