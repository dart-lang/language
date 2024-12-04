import 'package:corpus/utils.dart';

/// Match URIs that point to GitHub repos.
final _gitHubRepoPattern =
    RegExp(r'https://github.com/([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+)');

/// Download open source apps from itsallwidgets.com.
void main(List<String> arguments) async {
  clean("download/widgets");

  print('Getting page feed...');
  var feed =
      await httpGetJson('https://itsallwidgets.com/feed?open_source=true');

  var repos = <({String user, String repo})>{};
  for (var entry in (feed as List<Object?>)) {
    var entryMap = entry as Map<String, Object?>;
    if (entryMap['type'] != 'app') continue;

    var repo = entryMap['repo_url'] as String?;
    if (repo == null) continue;

    // Only know how to download from GitHub. There are a couple of BitBucket
    // ones in there.
    if (_gitHubRepoPattern.firstMatch(repo) case var match?) {
      repos.add((user: match[1]!, repo: match[2]!));
    }
  }

  var downloader = Downloader(totalResources: repos.length, concurrency: 10);
  for (var (:user, :repo) in repos) {
    downloader.cloneGitHubRepo('widgets', user, repo);
  }
}
