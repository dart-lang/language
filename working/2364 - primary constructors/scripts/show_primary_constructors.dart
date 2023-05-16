#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

abstract final class Options {
  static bool identifyStyle = false;
  static bool explicitFinal = false;
  static bool includeBody = false;
  static bool showNormal = false;
  static bool showStruct = false;
  static bool showKeyword = false;
  static bool numberClassNames = false;
}

var classNameNumber = 1;

String get classNameNumberSuffix {
  return Options.numberClassNames ? '$classNameNumber' : '';
}

var helpPrintedAlready = false;

void help() {
  if (helpPrintedAlready) return;
  helpPrintedAlready = true;
  print('Usage: show_primary_constructors.dart [options] [file]...');
  print("""

Every option is off by default, and specifying it will have an effect.

Options:
  --help, -h: Print this help text.
  --identify-style, -i: Include comment `Normal`/`Struct`/`Keyword`.
  --explicit-final, -f: Include `final` even when it is implied.
  --include-body, -b: Include a class body (otherwise `;` is used if possible).
  --show-normal, -n: Show a normal constructor and explicit field declarations.
  --show-keyword, -k: Show the form that uses a keyword.
  --show-struct, -s: Show the form which was proposed along with structs.
  --show-all, -a: Show all forms; enabled if no other '--show' option is given.
  --number-class-names: Append number to class names, to avoid name clashes.
""");
}

Never fail() {
  print('\nStopping.');
  exit(-1);
}

bool processOption(String option) {
  if (option.startsWith('--')) {
    var optionName = option.substring(2);
    switch (optionName) {
      case 'help':
        help();
        return true;
      case 'identify-style':
        Options.identifyStyle = true;
        return true;
      case 'explicit-final':
        Options.explicitFinal = true;
        return true;
      case 'include-body':
        Options.includeBody = true;
        return true;
      case 'show-all':
        Options.showNormal = true;
        Options.showStruct = true;
        Options.showKeyword = true;
        return true;
      case 'show-normal':
        Options.showNormal = true;
        return true;
      case 'show-struct':
        Options.showStruct = true;
        return true;
      case 'show-keyword':
        Options.showKeyword = true;
        return true;
      case 'number-class-names':
        Options.numberClassNames = true;
        return true;
      default:
        return false;
    }
  } else if (option.startsWith('-')) {
    var optionString = option.substring(1);
    var usedTheOption = false;
    for (var c in optionString.split('')) {
      switch (c) {
        case 'h':
          help();
          usedTheOption = true;
        case 'i':
          Options.identifyStyle = true;
          usedTheOption = true;
        case 'f':
          Options.explicitFinal = true;
          usedTheOption = true;
        case 'b':
          Options.includeBody = true;
          usedTheOption = true;
        case 'a':
          Options.showNormal = true;
          Options.showStruct = true;
          Options.showKeyword = true;
          usedTheOption = true;
        case 'n':
          Options.showNormal = true;
          usedTheOption = true;
        case 's':
          Options.showStruct = true;
          usedTheOption = true;
        case 'k':
          Options.showKeyword = true;
          usedTheOption = true;
        default:
          print('Unknown option: -$c');
      }
    }
    return usedTheOption;
  }
  return false; // This was not an option.
}

List<String> processOptions(List<String> args) {
  var result = <String>[];
  for (var arg in args) {
    if (!processOption(arg)) result.add(arg);
  }
  return result;
}

class ClassSpec {
  final String provenance; // Identify where we got this class from.
  final String name;
  final String? constructorName;
  final bool isInline;
  final List<FieldSpec> fields;
  final bool isConst;
  final String? superinterfaces;
  final String? typeParameters;

  ClassSpec(
    this.provenance,
    this.name,
    this.constructorName,
    this.isInline,
    this.fields,
    this.isConst,
    this.typeParameters,
    this.superinterfaces,
  );

  factory ClassSpec.fromJson(String source, Map<String, dynamic> jsonSpec) {
    var name = jsonSpec['name']!;
    var constructorName = jsonSpec['constructorName'];
    var isInline = jsonSpec['isInline'] ?? false;
    var jsonFields = jsonSpec['fields']!;
    var isConst = jsonSpec['isConst'] ?? false;
    var typeParameters = jsonSpec['typeParameters'];
    var superinterfaces = jsonSpec['superinterfaces'];
    var fields = <FieldSpec>[];

    for (var jsonField in jsonFields) {
      var field = FieldSpec.fromJson(jsonField);
      fields.add(field);
    }
    return ClassSpec(
      source,
      name,
      constructorName,
      isInline,
      fields,
      isConst,
      typeParameters,
      superinterfaces,
    );
  }
}

class FieldSpec {
  String name;
  String type;
  bool isFinal;
  bool isOptional;
  bool isNamed;
  String? defaultValue;

  FieldSpec(
    this.name,
    this.type,
    this.isFinal,
    this.isOptional,
    this.isNamed,
    this.defaultValue,
  );

  factory FieldSpec.fromJson(Map<String, dynamic> jsonField) {
    var name = jsonField['name']!;
    var type = jsonField['type']!;
    var isFinal = jsonField['isFinal'] ?? false;
    var isOptional = jsonField['isOptional'] ?? false;
    var isNamed = jsonField['isNamed'] ?? false;
    var defaultValue = jsonField['defaultValue'];
    return FieldSpec(name, type, isFinal, isOptional, isNamed, defaultValue);
  }
}

String ppNormal(ClassSpec classSpec) {
  var className = '${classSpec.name}$classNameNumberSuffix';
  var fieldsSource = StringBuffer('');
  var parametersSource = StringBuffer('');
  var constructorSource = StringBuffer('');

  var first = true;
  var firstOptionalOrNamed = true;
  var hasOptionalsOrNamed = false;
  var optionalOrNamedMeansNamed = false;
  for (var field in classSpec.fields) {
    var fieldName = field.name;
    if (first) {
      first = false;
      fieldsSource.write('\n');
    } else {
      parametersSource.write(', ');
    }
    var finality = field.isFinal ? 'final ' : '';
    fieldsSource.write('  $finality${field.type} $fieldName;\n');
    if ((field.isOptional || field.isNamed) && firstOptionalOrNamed) {
      if (field.isNamed) {
        optionalOrNamedMeansNamed = true;
        parametersSource.write('{');
      } else {
        parametersSource.write('[');
      }
      hasOptionalsOrNamed = true;
    }
    bool isRequired = field.isNamed && !field.isOptional;
    var requiredness = isRequired ? 'required ' : '';
    parametersSource.write('${requiredness}this.$fieldName');
    if (field.isOptional) {
      var defaultValue = field.defaultValue;
      if (defaultValue != null) {
        parametersSource.write(' = $defaultValue');
      }
    }
  }
  if (hasOptionalsOrNamed) {
    if (optionalOrNamedMeansNamed) {
      parametersSource.write('}');
    } else {
      parametersSource.write(']');
    }
  }
  var constNess = classSpec.isConst ? 'const ' : '';

  var constructorName = className;
  var constructorNameSpec = classSpec.constructorName;
  if (constructorNameSpec != null) {
    constructorName = '$className.$constructorNameSpec';
  }

  constructorSource.write('  $constNess$constructorName($parametersSource);\n');

  var typeParameters = classSpec.typeParameters ?? '';
  String superinterfaces = '';
  var specSuperinterfaces = classSpec.superinterfaces;
  if (specSuperinterfaces != null) {
    superinterfaces = ' $specSuperinterfaces';
  }

  var inlinity = classSpec.isInline ? 'inline ' : '';

  var body = Options.includeBody ? '  // ...\n' : '';
  return "${inlinity}class $className$typeParameters$superinterfaces"
      " {$fieldsSource$constructorSource$body}";
}

String ppKeyword(ClassSpec classSpec) {
  var className = '${classSpec.name}$classNameNumberSuffix';
  var fields = classSpec.fields;
  var parametersSource = StringBuffer('');

  var first = true;
  var firstOptionalOrNamed = true;
  var hasOptionalsOrNamed = false;
  var optionalOrNamedMeansNamed = false;
  for (var field in fields) {
    if (first) {
      first = false;
    } else {
      parametersSource.write(', ');
    }
    var finality = '';
    if (field.isFinal) {
      if (classSpec.isConst || classSpec.isInline) {
        if (Options.explicitFinal) finality = 'final ';
      } else {
        finality = 'final ';
      }
    }
    if ((field.isOptional || field.isNamed) && firstOptionalOrNamed) {
      if (field.isNamed) {
        optionalOrNamedMeansNamed = true;
        parametersSource.write('{');
      } else {
        parametersSource.write('[');
      }
      hasOptionalsOrNamed = true;
    }
    bool isRequired = field.isNamed && !field.isOptional;
    var requiredness = isRequired ? 'required ' : '';
    parametersSource.write('$requiredness$finality${field.type} ${field.name}');
    if (field.isOptional) {
      var defaultValue = field.defaultValue;
      if (defaultValue != null) {
        parametersSource.write(' = $defaultValue');
      }
    }
  }
  if (hasOptionalsOrNamed) {
    if (optionalOrNamedMeansNamed) {
      parametersSource.write('}');
    } else {
      parametersSource.write(']');
    }
  }
  var keyword = classSpec.isConst ? 'const' : 'new';
  var typeParameters = classSpec.typeParameters ?? '';

  String superinterfaces = '';
  var specSuperinterfaces = classSpec.superinterfaces;
  if (specSuperinterfaces != null) {
    superinterfaces = ' $specSuperinterfaces\n   ';
  }

  String constructorPhrase = '$keyword';
  var constructorNameSpec = classSpec.constructorName;
  if (constructorNameSpec != null) {
    constructorPhrase = '$keyword.$constructorNameSpec';
  }

  var inlinity = classSpec.isInline ? 'inline ' : '';
  var classHeader = 
      "${inlinity}class $className$typeParameters$superinterfaces"
      " $constructorPhrase($parametersSource)";
  var body = Options.includeBody ? ' {\n  // ...\n\}' : ';';
  return "$classHeader$body";
}

String ppStruct(ClassSpec classSpec) {
  var className = '${classSpec.name}$classNameNumberSuffix';
  var fields = classSpec.fields;
  var parametersSource = StringBuffer('');

  var first = true;
  var firstOptionalOrNamed = true;
  var hasOptionalsOrNamed = false;
  var optionalOrNamedMeansNamed = false;
  for (var field in fields) {
    if (first) {
      first = false;
    } else {
      parametersSource.write(', ');
    }
    var finality = '';
    if (field.isFinal) {
      if (classSpec.isConst || classSpec.isInline) {
        if (Options.explicitFinal) finality = 'final ';
      } else {
        finality = 'final ';
      }
    }
    if ((field.isOptional || field.isNamed) && firstOptionalOrNamed) {
      if (field.isNamed) {
        optionalOrNamedMeansNamed = true;
        parametersSource.write('{');
      } else {
        parametersSource.write('[');
      }
      hasOptionalsOrNamed = true;
    }
    bool isRequired = field.isNamed && !field.isOptional;
    var requiredness = isRequired ? 'required ' : '';
    parametersSource.write('$requiredness$finality${field.type} ${field.name}');
    if (field.isOptional) {
      var defaultValue = field.defaultValue;
      if (defaultValue != null) {
        parametersSource.write(' = $defaultValue');
      }
    }
  }
  if (hasOptionalsOrNamed) {
    if (optionalOrNamedMeansNamed) {
      parametersSource.write('}');
    } else {
      parametersSource.write(']');
    }
  }
  var constNess = classSpec.isConst ? 'const ' : '';
  var typeParameters = classSpec.typeParameters ?? '';

  String superinterfaces = '';
  var specSuperinterfaces = classSpec.superinterfaces;
  if (specSuperinterfaces != null) {
    superinterfaces = '\n    $specSuperinterfaces';
  }

  String constructorNamePart = '$className';
  var constructorNameSpec = classSpec.constructorName;
  if (constructorNameSpec != null) {
    constructorNamePart = '$className.$constructorNameSpec$typeParameters';
  } else {
    constructorNamePart = '$className$typeParameters';
  }

  var inlinity = classSpec.isInline ? 'inline ' : '';
  var classHeader =
      "${inlinity}class $constNess$constructorNamePart"
      "($parametersSource)"
      "$superinterfaces";
  var body = Options.includeBody ? ' {\n  // ...\n\}' : ';';
  return "$classHeader$body";
}

void main(List<String> args) {
  // We expect arguments to be options or file paths.
  var filePaths = processOptions(args);
  if (filePaths.isEmpty) {
    help();
    exit(0);
  }
  if (!Options.showNormal && !Options.showStruct && !Options.showKeyword) {
    // Default is to show all formats.
    Options.showNormal = Options.showStruct = Options.showKeyword = true;
  }

  var classSpecs = <ClassSpec>[];
  for (var filePath in filePaths) {
    String source;
    try {
      source = File(filePath).readAsStringSync();
    } catch (_) {
      print("Could not read '$filePath'.");
      fail();
    }
    var jsonSpec = jsonDecode(source);
    classSpecs.add(ClassSpec.fromJson(filePath, jsonSpec));
  }


  void show(String comment, String source) {
    if (Options.identifyStyle){
      print('// $comment.\n\n$source\n');
    } else {
      print('$source\n');
    }
  }

  for (var classSpec in classSpecs) {
    print('// ------------------------------ ${classSpec.provenance}\n');
    if (Options.showNormal) {
      show("Normal", ppNormal(classSpec));
      ++classNameNumber;
    }
    if (Options.showStruct) {
      show("Struct style", ppStruct(classSpec));
      ++classNameNumber;
    }
    if (Options.showKeyword) {
      show("Rightmost, with keyword", ppKeyword(classSpec));
      ++classNameNumber;
    }
  }
}
