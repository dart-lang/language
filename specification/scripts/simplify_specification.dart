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

extension on List<String?> {
  static final _commentRegExp = RegExp(r"^%|[^%\\]%");
  static final _commentaryRationaleRegExp = RegExp(
    r"^ *\\(commentary|rationale){",
  );
  static final _bracesRegExp = RegExp(r"{.*}");

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

  static int _indentation(String text) {
    final length = text.length;
    for (int i = 0; i < length; ++i) {
      if (!_isWhitespace(text, i)) {
        return i;
      }
    }
    return length;
  }

  static String _lineStart(String line) {
    final indentation = _indentation(line);
    if (indentation > 0)
      print(
        '>>> indentation: $indentation. Returning: ${"${' ' * indentation}}"}',
      ); // DEBUG
    return "${' ' * indentation}}";
  }

  void removeComments() {
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue; // It isn't, but flow-analysis doesn't know.
      final match = _commentRegExp.firstMatch(line);
      if (match != null) {
        if (match.start == 0) {
          this[i] = null; // A comment-only line disappears entirely.
        } else {
          final cutPosition = match.start + 1;
          if (line.codeUnitAt(cutPosition) == 37) {
            // An indented comment-only line disappears entirely.
            this[i] = null;
          }
          final resultLine = line.substring(0, cutPosition);
          this[i] = resultLine;
        }
      } else if (line.startsWith("\\end{document}")) {
        // All text beyond `\end{document}` is a comment.
        for (int j = i + 1; j < length; ++j) this[j] = null;
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

  void removeNonNormative() {
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue;
      if (line.startsWith(r"\BlindDefineSymbol{")) {
        this[i] = null;
        continue;
      }
      final match = _commentaryRationaleRegExp.firstMatch(line);
      if (match != null) {
        final matchOneliner = _bracesRegExp.firstMatch(line);
        if (matchOneliner != null) {
          this[i] = null;
        } else {
          final lineStart = _lineStart(line);
          while (i < length && this[i]?.startsWith(lineStart) == false) {
            this[i] = null;
            ++i;
          }
          if (i < length) this[i] = null;
        }
      }
    }
  }

  void joinLines() {
    bool inFrontMatter = true;
    bool inParagraph = false;
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue;
      if (inFrontMatter) {
        if (line.startsWith(r"\begin{document}")) inFrontMatter = false;
        continue;
      }
      if (!inParagraph) {
        if (line.isNotEmpty &&
            !line.startsWith(r"\newcommand{") &&
            !line.startsWith(r"\section{") &&
            !line.startsWith(r"\subsection{") &&
            !line.startsWith(r"\subsubsection{") &&
            !line.startsWith(r"\begin{") &&
            !line.startsWith(r"\end{") &&
            !line.startsWith(r"\LMLabel{") &&
            !line.startsWith(r"\Index{") &&
            !line.startsWith(r"\IndexCustom{") &&
            !line.startsWith(r"\noindent") &&
            !line.contains(r"\item")) {
          inParagraph = true;
        }
      }
      if (inParagraph) {
        throw 0; // !!!
      }
    }
  }
}

void main() {
  final inputFile = File(specificationFilename);
  if (!inputFile.existsSync()) fail("Specification not found");
  final contents = inputFile.readAsLinesSync();
  final workingContents =
      List<String?>.from(contents, growable: false)
        ..removeComments()
        ..removeTrailingWhitespace()
        ..removeNonNormative() /*
        ..joinLines()*/;
  final simplifiedContents = workingContents.whereType<String>().toList();
  final outputFile = File(outputFilename);
  final outputSink = outputFile.openWrite();
  simplifiedContents.forEach(outputSink.writeln);
}
