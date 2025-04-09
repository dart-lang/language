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

extension _RemoveCommentsExtension on List<String> {
  static final commentRegexp = RegExp("[^%\\]%\|^%");

  List<String> get removeComments {
    final result = List<String>.from(this);
    final length = this.length;
    for (int index = 0; index < length; ++index) {
      final line = result[index];
      final match = commentRegexp.firstMatch(line);
      if (match != null) {
        final cutPosition = match.start == 0 ? 0 : match.start + 1;
        final resultLine = line.substring(0, cutPosition);
        print('>>> line $index: "${line.substring(cutPosition, line.length)}"');
      } else if (line.startsWith("\\end{document}")) {
        // All text beyond `\end{document}` is a comment.
        result.removeRange(index, result.length);
        break;
      }
    }
    return result;
  }
}

void main() {
  final inputFile = File(specificationFilename);
  if (!inputFile.existsSync()) fail("Specification not found");
  final contents = inputFile.readAsLinesSync();
  final simplifiedContents = contents.removeComments; /*
          .removeTrailingWhitespace
          .removeCommentary
          .removeRationale
          .joinLines;*/

  final outputFile = File(outputFilename);
  final outputSink = outputFile.openWrite();
  simplifiedContents.forEach(outputSink.writeln);
}
