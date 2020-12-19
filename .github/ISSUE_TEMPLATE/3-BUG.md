---
name: I found a bug in the spec or documentation
labels: bug
about: There is an error in the spec or one of the feature implementation
  documents.

---

Include a permanent link to the error if possible.

https://help.github.com/en/articles/getting-permanent-links-to-files


name: I found a bug in dart input
import 'dart:io';

void main() {
  stdout.writeln('Type something');
  String input = stdin.readLineSync();
  stdout.writeln('You typed: $input');
}
