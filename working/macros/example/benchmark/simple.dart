// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Run this script to print out the generated augmentation library for an
// example class, created with fake data, and get some basic timing info:
//
//   dart benchmark/simple.dart
//
// You can also compile this benchmark to exe and run it as follows:
//
//   dart compile exe benchmark/simple.dart && ./benchmark/simple.exe
//
// Pass `--help` for usage and configuration options.
library language.working.macros.benchmark.simple;

import 'dart:io';

import 'package:args/args.dart';

// Private impls used actually execute the macro
import 'package:_fe_analyzer_shared/src/macros/bootstrap.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/serialization.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/isolated_executor.dart'
    as isolatedExecutor;
import 'package:_fe_analyzer_shared/src/macros/executor/process_executor.dart'
    as processExecutor;
import 'package:_fe_analyzer_shared/src/macros/executor/multi_executor.dart'
    as multiExecutor;

import 'src/data_class.dart' as data_class;
import 'src/injectable.dart' as injectable;

final _watch = Stopwatch()..start();
void _log(String message) {
  print('${_watch.elapsed}: $message');
}

final argParser = ArgParser()
  ..addOption('serialization-strategy',
      allowed: ['bytedata', 'json'],
      defaultsTo: 'bytedata',
      help: 'The serialization strategy to use when talking to macro programs.')
  ..addOption('macro-execution-strategy',
      allowed: ['aot', 'isolate'],
      defaultsTo: 'aot',
      help: 'The execution strategy for precompiled macros.')
  ..addOption('communication-channel',
      allowed: ['socket', 'stdio'],
      defaultsTo: 'stdio',
      help: 'The communication channel to use when running as a separate'
          ' process.')
  ..addOption('macro', allowed: ['DataClass', 'Injectable'], mandatory: true)
  ..addFlag('help', negatable: false, hide: true);

// Run this script to print out the generated augmentation library for an example class.
void main(List<String> args) async {
  var parsedArgs = argParser.parse(args);

  if (parsedArgs['help'] == true) {
    print(argParser.usage);
    return;
  }

  // Set up all of our options
  var parsedSerializationStrategy =
      parsedArgs['serialization-strategy'] as String;
  SerializationMode serializationMode;
  switch (parsedSerializationStrategy) {
    case 'bytedata':
      serializationMode = SerializationMode.byteData;
      break;
    case 'json':
      serializationMode = SerializationMode.json;
      break;
    default:
      throw ArgumentError(
          'Unrecognized serialization mode $parsedSerializationStrategy');
  }

  var macroExecutionStrategy = parsedArgs['macro-execution-strategy'] as String;
  var hostMode = Platform.script.path.endsWith('.dart') ||
          Platform.script.path.endsWith('.dill')
      ? 'jit'
      : 'aot';

  var macro = parsedArgs['macro'] as String;

  var communicationChannel = parsedArgs['communication-channel'] == 'stdio'
      ? processExecutor.CommunicationChannel.stdio
      : processExecutor.CommunicationChannel.socket;
  _log('''
Running with the following options:

Serialization strategy: $parsedSerializationStrategy
Macro execution strategy: $macroExecutionStrategy
Host app mode: $hostMode
Macro: $macro
''');

  // You must run from the `macros` directory, paths are relative to that.
  var macroFile = switch (macro) {
    'DataClass' => File('lib/data_class.dart'),
    'Injectable' => File('lib/injectable.dart'),
    _ => throw UnsupportedError('Unrecognized macro $macro'),
  };
  if (!macroFile.existsSync()) {
    print('This script must be ran from the `macros` directory.');
    exit(1);
  }
  var tmpDir = Directory.systemTemp.createTempSync('macro_benchmark');
  try {
    var macroUri = switch (macro) {
      'DataClass' => Uri.parse('package:macro_proposal/data_class.dart'),
      'Injectable' => Uri.parse('package:macro_proposal/injectable.dart'),
      _ => throw UnsupportedError('Unrecognized macro $macro'),
    };
    var macroConstructors = switch (macro) {
      'DataClass' => {
          'DataClass': ['']
        },
      'Injectable' => {
          'Injectable': [''],
          'Provides': [''],
          'Component': [''],
        },
      _ => throw UnsupportedError('Unrecognized macro $macro'),
    };

    var bootstrapContent = bootstrapMacroIsolate({
      macroUri.toString(): macroConstructors,
    }, serializationMode);

    var bootstrapFile = File(tmpDir.uri.resolve('main.dart').toFilePath())
      ..writeAsStringSync(bootstrapContent);
    var kernelOutputFile =
        File(tmpDir.uri.resolve('main.dart.dill').toFilePath());
    _log('Compiling $macro macro');
    var buildSnapshotResult = await Process.run('dart', [
      'compile',
      macroExecutionStrategy == 'aot' ? 'exe' : 'jit-snapshot',
      '--packages=.dart_tool/package_config.json',
      '--enable-experiment=macros',
      '-o',
      kernelOutputFile.uri.toFilePath(),
      bootstrapFile.uri.toFilePath(),
    ]);

    if (buildSnapshotResult.exitCode != 0) {
      print('Failed to build macro boostrap isolate:\n'
          'stdout: ${buildSnapshotResult.stdout}\n'
          'stderr: ${buildSnapshotResult.stderr}');
      exit(1);
    }

    _log('Loading the macro executor');
    var executorImpl = macroExecutionStrategy == 'aot'
        ? await processExecutor.start(serializationMode, communicationChannel,
            kernelOutputFile.uri.toFilePath())
        : await isolatedExecutor.start(serializationMode, kernelOutputFile.uri);
    var executor = multiExecutor.MultiMacroExecutor()
      ..registerExecutorFactory(() => executorImpl, {macroUri});

    _log('Running benchmark');
    await switch (macro) {
      'DataClass' => data_class.runBenchmarks(executor, macroUri),
      'Injectable' => injectable.runBenchmarks(executor, macroUri),
      _ => throw UnsupportedError('Unrecognized macro $macro'),
    };
    await executor.close();
  } finally {
    tmpDir.deleteSync(recursive: true);
  }
}
