// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Create a simplified version of 'dartLangSpec.tex'.
///
/// This script creates a version of 'dartLangSpec.tex' that does not
/// contain comments, commentary text, or rationale text. It eliminates
/// all newline characters in a paragraph (that is, each paragraph is
/// entirely on the same line).
///
/// The purpose of this transformation is that the output can be grepped
/// more effectively (the original version may have a newline in the
/// middle of the phrase that we're looking for), and more precisely
/// (the originl version could have hits in comments, commentary, etc,
/// and it is assumed that we only want to find normative text).
///
/// The script should be executed with '..' as the current directory,
/// that is, the directory where 'dartLangSpec.tex' is located.
library;

import 'dart:io';

const specificationFilename = 'dartLangSpec.tex';
const outputFilename = 'dartLangSpec-simple.tex';

void fail(String message) {
  print("simplify_specification error: $message");
  exit(-1);
}

extension on List<String> {
  List<String?> get setup => List<String?>.from(this, growable: false);
}

extension on List<String?> {
  static final _commentRegexp = RegExp("[^%\\\\]%\|^%");
  static final _commentaryRationaleRegexp = RegExp(
    r"^\\\(commentary\|rationale\){",
  );

  static bool _isWhitespace(String text, int index) {
    int codeUnit = text.codeUnitAt(index);
    return codeUnit == 0x09 || // Tab
        codeUnit == 0x0A || // Line Feed
        codeUnit == 0x0B || // Vertical Tab
        codeUnit == 0x0C || // Form Feed
        codeUnit == 0x0D || // Carriage Return
        codeUnit == 0x20 || // Space
        codeUnit == 0xA0 || // No-Break Space
        codeUnit == 0x1680 || // Ogham Space Mark
        (codeUnit >= 0x2000 && codeUnit <= 0x200A) || // En Space to Hair Space
        codeUnit == 0x202F || // Narrow No-Break Space
        codeUnit == 0x205F || // Medium Mathematical Space
        codeUnit == 0x3000 || // Ideographic Space
        codeUnit == 0xFEFF; // Zero Width No-Break Space (BOM)
  }

  void removeComments() {
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue; // It isn't, but flow-analysis doesn't know.
      final match = _commentRegexp.firstMatch(line);
      if (match != null) {
        final cutPosition = match.start == 0 ? 0 : match.start + 1;
        final resultLine = line.substring(0, cutPosition);
        this[i] = resultLine;
      } else if (line.startsWith("\\end{document}")) {
        // All text beyond `\end{document}` is a comment.
        for (int j = i; j < length; ++j) this[j] = null;
        break;
      }
    }
  }

  void removeTrailingWhitespace() {
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue;
      if (line.isNotEmpty && _isWhitespace(line, line.length - 1)) {
        this[i] = line.trimRight();
      }
    }
  }

  void removeCommentaryAndRationale() {
    print(_commentaryRationaleRegexp);
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue;
      final match = _commentaryRationaleRegexp.firstMatch(line);
      if (match != null) {
        final lineStart = '${line.substring(0, match.start - 1)}}';
        print('>>> line: $line, lineStart: $lineStart'); // DEBUG
        while (i < length && !line.startsWith(lineStart)) {
          this[i] = null;
        }
      }
    }
  }
}

void main() {
  final inputFile = File(specificationFilename);
  if (!inputFile.existsSync()) fail("Specification not found");
  final contents = inputFile.readAsLinesSync();
  final simplifiedContents =
      contents.setup
        ..removeComments()
        ..removeTrailingWhitespace()
        ..removeCommentaryAndRationale(); /*
        ..joinLines;*/

  final outputFile = File(outputFilename);
  final outputSink = outputFile.openWrite();
  simplifiedContents.whereType<String>().forEach(outputSink.writeln);
}
