import 'dart:io';

import 'package:corpus/utils.dart';

const _totalPackages = 2000;

void main(List<String> arguments) async {
  clean('download/pub');

  // Iterate through the pages (which are in most recent order) until we get
  // enough packages.
  var packagePage = 'http://pub.dartlang.org/api/packages';
  var downloaded = 1;

  var downloader = Downloader(totalResources: _totalPackages);
  for (;;) {
    downloader.log('Getting index page $downloaded...');
    var packages = await httpGetJson(packagePage);

    for (var package in packages['packages']) {
      downloader.withResource((logger) async {
        var name = package['name'] as String;
        var version = package['latest']['version'] as String;
        var archiveUrl = package['latest']['archive_url'] as String;

        try {
          logger.begin('Downloading $archiveUrl...');
          var archiveBytes = await httpGetBytes(archiveUrl);
          var tarFile = 'download/pub/$name-$version.tar.gz';
          await File(tarFile).writeAsBytes(archiveBytes);

          logger.log('Extracting $tarFile...');
          var outputDir = 'download/pub/$name-$version';
          await Directory(outputDir).create(recursive: true);
          var result =
              await Process.run('tar', ['-xf', tarFile, '-C', outputDir]);

          if (result.exitCode != 0) {
            logger.end('Could not extract $tarFile:\n${result.stderr}');
          } else {
            await File(tarFile).delete();
            logger.end('Finished $outputDir');
          }
        } catch (error) {
          logger.end('Error downloading $archiveUrl:\n$error');
        }
      });

      downloaded++;
      if (downloaded >= _totalPackages) return;
    }

    var nextUrl = packages['next_url'];
    if (nextUrl is! String) break;
    packagePage = nextUrl;
  }
}
