This directory contains a package with scripts for downloading corpora of open
source Dart code for automated analysis. There are a few scripts for
downloading from various places:

*   `clone_flutter_apps.dart`: Clones GitHub repositories linked to from
    [github.com/tortuvshin/open-source-flutter-apps](https://github.com/tortuvshin/open-source-flutter-apps), which is a registry of open source Flutter apps.
    Downloads them to `download/apps`.

*   `clone_widgets.apps.dart`: Clones GitHub repositories referenced by
    [itsallwidgets.com](https://itsallwidgets.com/), which is a collection of
    open source Flutter apps and widgets. Downloads them to `download/widgets`.

*   `download_packages.dart`: Downloads recent packages from
    [pub.dev](https://pub.dev/). Downloads to `download/pub`.

Once a corpus is downloaded, there is another script that copies over just the
`.dart` files while discardinging "uninteresting" files like generated ones:

*   `copy_corpus.dart`: Copies `.dart` files from one of the download
    directories. Pass `apps`, `widgets`, `pub`, etc. Can also copy sources from
    the Dart SDK repo (`dart`) or Flutter repo (`flutter`). For that to work,
    those repos must be in directories next to the language repo.

    You can pass `--sample=<percent>` to take a random sample of a corpus. For
    example, `--sample=5` will copy over only 5% of the files, chosen randomly.
