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

  /// Gather the text in lines `paragraphIndex + 1` into
  /// a single line and store it at [paragraphIndex].
  int _gatherParagraph(final int paragraphIndex) {
    final length = this.length;
    final buffer = StringBuffer('');
    var insertSpace = false;
    for (
      var gatherIndex = paragraphIndex + 1;
      gatherIndex < length;
      ++gatherIndex
    ) {
      var gatherLine = this[gatherIndex]; // Invariant.
      if (gatherLine == null) continue;
      if (gatherLine.isEmpty) {
        // End of paragraph, finalize.
        this[paragraphIndex] = buffer.toString();
        return gatherIndex;
      }
      if (insertSpace) {
        buffer.write(' ');
      }
      final endsInPercent = gatherLine.endsWith('%');
      final String addLine;
      if (endsInPercent) {
        addLine = gatherLine.substring(0, gatherLine.length - 1);
        insertSpace = false;
      } else {
        addLine = gatherLine;
        insertSpace = true;
      }
      buffer.write(addLine.trimLeft());
      this[gatherIndex] = null;
    }
    throw "Internal error: _gatherParagraph reached end of text";
  }

  /// Return the index of the first line, starting with [startIndex],
  /// that contains the command `\item`. Note that this implies
  /// `this[i] != null` where `i` is the returned value.
  ///
  /// This method does not attempt to balance `\begin{}`/`\end{}`
  /// pairs,
  int _findItem(final int startIndex) {
    final length = this.length;
    for (int searchIndex = startIndex; searchIndex < length; ++searchIndex) {
      final line = this[searchIndex];
      if (line == null) continue;
      final trimmedLine = line.trimLeft();
      if (trimmedLine.startsWith(r"\end{itemize}")) {
        throw "_findItem did not find any items";
      }
      if (trimmedLine.startsWith(r"\item")) {
        return searchIndex;
      }
    }
    throw "_findItem reached end of text";
  }

  /// Return the index of the first non-empty line after [startIndex].
  int _findText(final int startIndex) {
    final length = this.length;
    for (int searchIndex = startIndex; searchIndex < length; ++searchIndex) {
      final line = this[searchIndex];
      if (line == null) continue;
      final trimmedLine = line.trim();
      if (trimmedLine.isNotEmpty) {
        return searchIndex;
      }
    }
    throw "_findText reached end of text";
  }

  /// Starting from the line with index [listIndex], which is assumed
  /// to start with `\begin{itemize}`, search for `\item` commands and
  /// gather the subsequent lines for each item into a single line.
  /// Also handle nested itemized lists (no attempt to balance them, we
  /// just rely on finding `\end{itemize}` at the beginning of a line).
  /// Return the index of the first line after the itemized list.
  int _gatherItems(final int listIndex) {
    final length = this.length;
    var itemIndex = _findItem(listIndex + 1);
    var itemLine = this[itemIndex]; // Invariant.
    var buffer = StringBuffer(itemLine!.trimRight());
    var insertSpace = true;

    for (var gatherIndex = itemIndex + 1; gatherIndex < length; ++gatherIndex) {
      var gatherLine = this[gatherIndex]; // Invariant.
      if (gatherLine == null) continue;
      final trimmedGatherLine = gatherLine.trimLeft();
      if (trimmedGatherLine.startsWith(r"\begin{itemize}")) {
        // We do not gather a nested itemized list into the current item.
        // Finalize the current item.
        this[itemIndex] = buffer.toString();
        // Set up the first item of the nested itemized list.
        itemIndex = _findItem(gatherIndex + 1);
        itemLine = this[itemIndex];
        buffer = StringBuffer(itemLine!);
        gatherIndex = itemIndex + 1;
        gatherLine = this[gatherIndex]; // Restore the invariant.
        if (gatherLine == null) continue;
      }
      if (gatherLine.startsWith(r"\end{itemize}")) {
        // At the end of the outermost itemized list: Done.
        this[itemIndex] = buffer.toString();
        return gatherIndex + 1;
      }
      final foundItem = trimmedGatherLine.startsWith(r"\item");
      final foundEnd = trimmedGatherLine.startsWith(r"\end{itemize}");
      if (foundItem || foundEnd) {
        // Current `\item` has ended, transfer the data.
        this[itemIndex] = buffer.toString();
        if (foundItem) {
          // Another `\item` coming, set up.
          buffer = StringBuffer(gatherLine);
          itemIndex = gatherIndex;
          itemLine = this[itemIndex]; // Restore the `itemLine` invariant.
          continue;
        } else {
          // `foundEnd` is true.
          // Gather lines after the nested itemized list, if any. Note
          /// that `itemLine` does not contain `\item`, but it's treated
          /// as if it did contain `\item`.
          itemIndex = _findText(gatherIndex + 1);
          itemLine = this[itemIndex]; // Restore the `itemLine` invariant.
          gatherIndex = itemIndex + 1;
          continue;
        }
      }
      // `gatherLine` is text belonging to the current `\item`.
      if (insertSpace) {
        buffer.write(' ');
      }
      final endsInPercent = gatherLine.endsWith('%');
      final String addLine;
      if (endsInPercent) {
        addLine = gatherLine.substring(0, gatherLine.length - 1);
        insertSpace = false;
      } else {
        addLine = gatherLine;
        insertSpace = true;
      }
      buffer.write(addLine.trimLeft());
      this[gatherIndex] = null;
    }
    throw "_gatherItems reached end of text";
  }

  void joinLines() {
    bool inFrontMatter = true;
    for (var lineIndex = 0; lineIndex < length; ++lineIndex) {
      final line = this[lineIndex]; // Invariant.
      if (line == null) continue;
      if (inFrontMatter) {
        if (line.startsWith(r"\begin{document}")) inFrontMatter = false;
        continue;
      }
      if (line.startsWith(r"\LMHash{}")) {
        lineIndex = _gatherParagraph(lineIndex);
      } else if (line.startsWith(r"\begin{itemize}")) {
        lineIndex = _gatherItems(lineIndex);
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
