import 'dart:io';

/// Reads the "dartLangSpec.tex" and prints out all of the grammar rules it
/// contains as plaintext.

/// Matches Tex keyword references like:
///
///     \LATE
///     \FINAL{}
final keywordRegExp = RegExp(r'\\([A-Z]+)(\{\})?');

/// Matches non-terminals like:
///
///     <declaredIdentifier>
final ruleRegExp = RegExp(r'<(\w+)>');

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    print("Usage: dart plaintext_grammar.dart <path to dartLangSpec.tex>");
    exit(1);
  }

  var specFile = File(arguments[0]);

  var inGrammar = false;
  for (var line in specFile.readAsLinesSync()) {
    line = line.trimRight();

    if (line == r'\begin{grammar}') {
      inGrammar = true;
    } else if (line == r'\end{grammar}') {
      print('');
      inGrammar = false;
    } else if (inGrammar) {
      line = line
          .replaceAll('`', "'")
          .replaceAll(r'\alt', '|')
          .replaceAll(r' \gnewline{}', '')
          .replaceAll(r'\gtilde{}', '~')
          .replaceAll(r'\_', '_')
          .replaceAll(r'\{', '{')
          .replaceAll(r'\}', '}')
          .replaceAll(r'\&', '&')
          .replaceAll(r'\%', '%')
          .replaceAll(r'\gtgtgt', '>>>')
          .replaceAll(r'\gtgt', '>>')
          .replaceAll(r'\ltltlt', '<<<')
          .replaceAll(r'\ltlt', '<<')
          .replaceAll(r'\\b', r'\b')
          .replaceAll(r'\\f', r'\f')
          .replaceAll(r'\\n', r'\n')
          .replaceAll(r'\\r', r'\r')
          .replaceAll(r'\\t', r'\t')
          .replaceAll(r'\\u', r'\u')
          .replaceAll(r'\\v', r'\v')
          .replaceAll(r'\\x', r'\x')
          .replaceAll(r'\sqsqsq', r"\'\'\'")
          .replaceAll(r'\sqsq', r"\'\'")
          .replaceAll(r'\sq', r"\'")
          .replaceAll(r'\\', r'\')
          .replaceAll(r'\FUNCTION{}', "'Function'")
          .replaceAllMapped(
              keywordRegExp, (match) => "'${match[1]!.toLowerCase()}'")
          .replaceAllMapped(ruleRegExp, (match) => match[1]!);
      print(line);
    }
  }
}
