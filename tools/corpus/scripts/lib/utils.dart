import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';

final _client = http.Client();

/// Creates an empty directory at [dirPath].
///
/// If a directory is already there, removes it first.
void clean(String dirPath) {
  var directory = Directory(dirPath);
  if (directory.existsSync()) {
    print('Deleting $dirPath...');
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
}

Future<void> cloneGitHubRepo(String destination, String user, String repo,
    {String prefix = ''}) async {
  print('${prefix}Cloning $user/$repo...');
  try {
    var gitHubUri = 'https://github.com/$user/$repo.git';

    var outputDir = 'download/$destination/$user-$repo';
    var result = await Process.run(
        'git', ['clone', '--depth', '1', gitHubUri, outputDir]);
    if (result.exitCode != 0) {
      print('${prefix}Could not clone $gitHubUri:\n${result.stderr}');
    } else {
      print('${prefix}Cloned  $outputDir');
    }
  } catch (error) {
    print('${prefix}Error cloning $user/$repo:\n$error');
  }
}

/// Gets the body of the HTTP response to sending a GET to [uri].
Future<String> httpGet(String uri) async {
  return (await _client.get(Uri.parse(uri))).body;
}

/// Gets the body of the HTTP response to sending a GET to [uri].
Future<List<int>> httpGetBytes(String uri) async {
  return (await _client.get(Uri.parse(uri))).bodyBytes;
}

/// Gets the body of the HTTP response to sending a GET to [uri].
Future<dynamic> httpGetJson(String uri) async {
  return jsonDecode(await httpGet(uri));
}

class Downloader {
  /// The total number of resources that will be downloaded using this pool.
  final int _totalResources;

  /// The maximum number of concurrent downloads.
  final int _maxConcurrency;

  final Pool _pool;

  /// The number of operations that have finished.
  int _completedResources = 0;

  /// Which "slots" are currently in use for drawing the ongoing download bars.
  final _slots = <int>{};

  Downloader({required int totalResources, int concurrency = 20})
      : _totalResources = totalResources,
        _maxConcurrency = concurrency,
        _pool = Pool(concurrency);

  void log(String message) {
    _log(-1, '', message);
  }

  void withResource(Future<void> Function(Logger) callback) {
    var logger = Logger._(this);

    _pool.withResource(() async {
      await callback(logger);
    });
  }

  void cloneGitHubRepo(String destination, String user, String repo) {
    withResource((logger) async {
      logger.begin('Cloning $user/$repo...');
      try {
        var gitHubUri = 'https://github.com/$user/$repo.git';
        var outputDir = 'download/$destination/$user-$repo';
        var result = await Process.run(
            'git', ['clone', '--depth', '1', gitHubUri, outputDir]);
        if (result.exitCode != 0) {
          logger.end('Could not clone $gitHubUri:\n${result.stderr}');
        } else {
          logger.end('Cloned $outputDir');
        }
      } catch (error) {
        logger.end('Error cloning $user/$repo:\n$error');
      }
    });
  }

  void _log(int slot, String marker, String message) {
    var buffer = StringBuffer();

    // Show the overall progress.
    var width = _totalResources.toString().length;
    buffer.write('[');
    buffer.write(_completedResources.toString().padLeft(width));
    buffer.write('/');
    buffer.write(_totalResources.toString().padLeft(width));
    buffer.write(']');

    // Show the slot bars.
    for (var i = 0; i < _maxConcurrency; i++) {
      buffer.write(switch ((i == slot, _slots.contains(i))) {
        (true, _) => marker,
        (_, true) => '│',
        _ => ' '
      });
    }

    buffer.write(' ');
    buffer.write(message);
    print(buffer);
  }

  /// Find an unused slot for this operation.
  int _claimSlot() {
    for (var i = 0; i < _maxConcurrency; i++) {
      if (!_slots.contains(i)) {
        _slots.add(i);
        return i;
      }
    }

    throw StateError('Unreachable.');
  }

  void _releaseSlot(int slot) {
    _slots.remove(slot);
  }
}

class Logger {
  final Downloader _pool;
  late final int _slot;

  Logger._(this._pool);

  void begin(String message) {
    _slot = _pool._claimSlot();
    _pool._log(_slot, '┌', message);
  }

  void log(String message) {
    _pool._log(_slot, '├', message);
  }

  void end(String message) {
    _pool._completedResources++;
    _pool._log(_slot, '└', message);
    _pool._releaseSlot(_slot);
  }
}
