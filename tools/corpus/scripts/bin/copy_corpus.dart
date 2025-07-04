import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// What percentage of files should be copied over. Used to take a random
/// sample of a corpus.
int _samplePercent = 100;

final _random = Random();

const _ignoreDirs = [
  'pkg/dev_compiler/gen/',
  'tests/co19/',
  'third_party/observatory_pub_packages/',
  'tools/sdks/',
  'out/',
  'xcodebuild/',

  // Redundant stuff in Flutter.
  'bin/cache/',

  // Redundant packages that are in the SDK.
  'analyzer-',
  'compiler_unsupported-',
  'dev_compiler-',
];

// Note! Assumes the Dart SDK and Flutter repos have been cloned in
// directories next to the corpus repo. Also assumes this script has been run
// from the root directory of this repo.
const _corpora = [
  ('apps', 'download/apps'),
  ('dart', '../../../dart/sdk'),
  ('flutter', '../../../flutter'),
  ('pub', 'download/pub'),
  ('widgets', 'download/widgets'),
];

final generatedSuffixes = ['.g.dart', '.freezed.dart'];

void main(List<String> arguments) async {
  var argParser = ArgParser();
  argParser.addFlag('omit-slow');
  argParser.addOption('sample', abbr: 's', defaultsTo: '100');

  var argResults = argParser.parse(arguments);
  _samplePercent = int.parse(argResults['sample']);

  for (var (name, directory) in _corpora) {
    if (arguments.contains(name)) await copyDir(directory, name);
  }
}

Future<void> copyDir(String fromDirectory, String toDirectory) async {
  // If we're taking a random sample, put that in a separate directory.
  if (_samplePercent != 100) {
    toDirectory += '-$_samplePercent';
  }

  var i = 0;
  var inDir = Directory(fromDirectory);

  await inDir.list(recursive: true, followLinks: false).listen((entry) async {
    var relative = p.relative(entry.path, from: inDir.path);

    if (entry is Link) return;
    if (entry is! File || !entry.path.endsWith('.dart')) return;

    // Skip redundant stuff.
    for (var ignore in _ignoreDirs) {
      if (relative.startsWith(ignore)) return;
    }

    if (_random.nextInt(100) >= _samplePercent) return;

    // If the path is in a subdirectory starting with '.', ignore it.
    var parts = p.split(relative);
    if (parts.any((part) => part.startsWith('.'))) return;

    var outPath = p.join('out', toDirectory, relative);

    var outDir = Directory(p.dirname(outPath));
    if (!await outDir.exists()) await outDir.create(recursive: true);

    await entry.copy(outPath);

    i++;
    if (i % 100 == 0) print(relative);
  }).asFuture();
}
