import 'package:corpus/utils.dart';

/// Match URIs that point to GitHub repos. Look for a trailing ")" (after an
/// allowed trailing "/") in order to only find Markdown link URIs that are
/// directly to repos and not to paths within them like the images in the
/// header.
final _gitHubRepoPattern =
    RegExp(r'https://github.com/([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+)/?\)');

const _readmeUri =
    'https://raw.githubusercontent.com/tortuvshin/open-source-flutter-apps/'
    'refs/heads/master/README.md';

/// Clones the GitHub repos listed on:
///
/// https://github.com/tortuvshin/open-source-flutter-apps
///
/// Downloads them to downloads/apps.
void main(List<String> arguments) async {
  clean('download/apps');

  print('Getting README.md...');
  var readme = await httpGet(_readmeUri);

  // Find all the repo URLs and remove the duplicates.
  var repoPaths = _gitHubRepoPattern
      .allMatches(readme)
      .map((match) => (user: match[1]!, repo: match[2]!))
      .toSet()
      .toList();

  // Skip the reference to the repo itself.
  repoPaths.remove((user: 'tortuvshin', repo: 'open-source-flutter-apps'));

  var downloader = Downloader(totalResources: repoPaths.length, concurrency: 5);
  for (var (:user, :repo) in repoPaths) {
    downloader.cloneGitHubRepo('apps', user, repo);
  }
}
