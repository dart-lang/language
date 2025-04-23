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
    r"^ *\(?\\(commentary|rationale){",
  );
  static final _bracesRegExp = RegExp(r"\\[a-zA-Z]*{.*}");
  static final _parenBracesRexExp = RegExp(r"\(\\[a-zA-Z]*{.*}\)");

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
    return "${' ' * indentation}}";
  }

  // Eliminate comment-only lines. Reduce other comments to `%`.
  void removeComments() {
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue; // It isn't, but flow-analysis doesn't know.
      final match = _commentRegExp.firstMatch(line);
      if (match != null) {
        if (match.start == 0) {
          this[i] = null; // A comment-only line disappears entirely.
        } else {
          final cutPosition = match.start + 2; // Include the `%`.
          if (line.trimLeft().codeUnitAt(0) == 37) {
            // An indented comment-only line disappears entirely.
            this[i] = null;
          } else {
            final resultLine = line.substring(0, cutPosition);
            assert(i < length - 1);
            this[i] = resultLine;
          }
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
        final matchParenthesizedOneliner = _parenBracesRexExp.firstMatch(line);
        if (matchParenthesizedOneliner != null) {
          if (matchParenthesizedOneliner.start == 0 &&
              matchParenthesizedOneliner.end == line.length) {
            this[i] = null;
          } else {
            this[i] = line.replaceRange(
              matchParenthesizedOneliner.start,
              matchParenthesizedOneliner.end,
              '',
            );
          }
        } else {
          final matchOneliner = _bracesRegExp.firstMatch(line);
          if (matchOneliner != null) {
            if (matchOneliner.start == 0 && matchOneliner.end == line.length) {
              this[i] = null;
            } else {
              this[i] = line.replaceRange(
                matchOneliner.start,
                matchOneliner.end,
                '',
              );
            }
          } else {
            final lineStart = _lineStart(line);
            while (i < length && this[i]?.startsWith(lineStart) != true) {
              this[i] = null;
              ++i;
            }
            if (i < length) this[i] = null;
          }
        }
      }
    }
  }

  void joinLines() {
    bool inFrontMatter = true;
    TopLoop:
    for (var lineIndex = 0; lineIndex < length; ++lineIndex) {
      final line = this[lineIndex]; // Invariant.
      if (line == null) continue;
      if (inFrontMatter) {
        if (line.startsWith(r"\begin{document}")) inFrontMatter = false;
        continue;
      }
      if (line.startsWith(r"\LMHash{}")) {
        final longLineIndex = lineIndex;
        final buffer = StringBuffer('');
        var firstInParagraph = true;
        for (
          var gatherIndex = longLineIndex + 1;
          gatherIndex < length;
          ++gatherIndex
        ) {
          var gatherLine = this[gatherIndex]; // Invariant.
          if (gatherLine == null) continue;
          if (gatherLine.isEmpty) {
            this[longLineIndex] = buffer.toString();
            lineIndex = gatherIndex;
            continue TopLoop; // Restores the `line` invariant.
          }
          if (firstInParagraph) {
            firstInParagraph = false;
          } else {
            buffer.write(' ');
          }
          buffer.write(gatherLine);
          this[gatherIndex] = gatherLine = null;
        }
        assert(lineIndex < length);
      } else if (line.startsWith(r"\begin{itemize}")) {
        var itemIndex = lineIndex + 1;
        InnerLoop:
        while (true) {
          var itemLine = this[itemIndex]; // Invariant.
          while (itemIndex < length &&
              itemLine?.trimLeft().startsWith(r"\item") != true) {
            ++itemIndex;
            itemLine = this[itemIndex];
          }
          assert(itemIndex < length);
          // `itemLine == this[itemIndex]` matches `r"^ *\\item"`.
          var buffer = StringBuffer(itemLine!);
          for (
            var gatherIndex = itemIndex + 1;
            gatherIndex < length;
            ++gatherIndex
          ) {
            var gatherLine = this[gatherIndex]; // Invariant.
            if (gatherLine == null) continue;
            final trimmedGatherLine = gatherLine.trimLeft();
            if (trimmedGatherLine.startsWith(r"\begin{itemize}")) {
              // We do not gather a nested itemized list into the current item.
              this[itemIndex] = buffer.toString();
              itemIndex = gatherIndex + 1;
              continue InnerLoop; // Restores the `itemLine` invariant.
            }
            if (gatherLine.startsWith(r"\end{itemize}")) {
              // At the end of the outermost itemized list.
              lineIndex = gatherIndex + 1;
              continue TopLoop; // Restores the `line` invariant.
            }
            final foundItem = trimmedGatherLine.startsWith(r"\item");
            final foundEnd = trimmedGatherLine.startsWith(r"\end{itemize}");
            if (foundItem || foundEnd) {
              // Current `\item` has ended, transfer the data.
              this[itemIndex] = buffer.toString();
              if (foundItem) {
                buffer = StringBuffer(gatherLine);
                itemIndex = gatherIndex;
                itemLine = this[itemIndex]; // Restore the `itemLine` invariant.
                continue;
              }
              if (foundEnd) {
                // Gather lines after the nested itemized list, if any.
                itemIndex = gatherIndex + 1;
                itemLine = this[itemIndex]; // Restore the `itemLine` invariant.
                while (itemIndex < length &&
                    (itemLine == null || itemLine.trim().isEmpty)) {
                  ++itemIndex;
                  itemLine = this[itemIndex]; // Restore the invariant.
                }
                assert(itemIndex < length);
                // `itemLine` contains some non-whitespace text.
                if (itemLine!.startsWith(r"\end{itemize}")) {
                  // No text occurs after the nested itemized list.
                  lineIndex = itemIndex + 1;
                  continue TopLoop; // Restores the `line` invariant.
                }
                // The outermost `\item` continues after the nested itemized
                // list. Gather this text into a single line.
                buffer = StringBuffer(itemLine);
                gatherIndex = itemIndex;
                continue; // Restores the `gatherLine` invariant.
              }
            }
            // `gatherLine` is text belonging to the current `\item`.
            this[gatherIndex] = null;
            buffer.write(' ');
            buffer.write(gatherLine);
          }
          assert(lineIndex < length);
        }
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
        ..removeNonNormative()
        ..joinLines();
  final simplifiedContents = workingContents.whereType<String>().toList();
  final outputFile = File(outputFilename);
  final outputSink = outputFile.openWrite();
  simplifiedContents.forEach(outputSink.writeln);
}
