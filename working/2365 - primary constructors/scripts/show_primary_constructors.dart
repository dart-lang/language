#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

abstract final class Options {
  static bool showNormal = false;
  static bool showStruct = false;
  static bool showKeyword = false;
  static bool implicitFinal = false;
}

void help() {
  print('Usage: show_primary_constructors.dart [options] [file]...');
  print("""

 Options:
   --help, -h: Print this help text.
   --implicit-final: Omit `final` where possible.
   --show-normal: Show a normal constructor and explicit field declarations.
   --show-keyword: Show the form that uses a keyword.
   --show-struct: Show the form which was proposed along with structs.
""");
}

Never fail() {
  print('\nStopping.');
  exit(-1);
}

bool processOption(String option) {
  if (option.startsWith('--')) {
    var optionName = option.substring(2);
    switch (option.substring(2)) {
      case 'help':
        help();
        return true;
      case 'implicit-final':
        Options.implicitFinal = true;
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
      default:
        return false;
    }
  } else if (option.startsWith('-')) {
    var optionString = option.substring(1);
    for (var c in optionString.split('')) {
      switch (c) {
        case 'h':
          help();
          return true;
        default:
          return false;
      }
    }
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

  FieldSpec(this.name, this.type, this.isFinal, this.isOptional);

  factory FieldSpec.fromJson(Map<String, dynamic> jsonField) {
    var name = jsonField['name']!;
    var type = jsonField['type']!;
    var isFinal = jsonField['isFinal'] ?? false;
    var isOptional = jsonField['isOptional'] ?? false;
    return FieldSpec(name, type, isFinal, isOptional);
  }
}

String ppNormal(ClassSpec classSpec) {
  var className = classSpec.name;
  var fieldsSource = StringBuffer('');
  var parametersSource = StringBuffer('');
  var constructorSource = StringBuffer('');

  var first = true;
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
    parametersSource.write('this.$fieldName');
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

  return "${inlinity}class $className$typeParameters$superinterfaces"
      " {$fieldsSource$constructorSource  // ...\n}";
}

String ppKeyword(ClassSpec classSpec) {
  var className = classSpec.name;
  var fields = classSpec.fields;
  var parametersSource = StringBuffer('');

  var first = true;
  for (var field in fields) {
    if (first) {
      first = false;
    } else {
      parametersSource.write(', ');
    }
    var finality = '';
    if (field.isFinal) {
      if (classSpec.isConst || classSpec.isInline) {
        if (!Options.implicitFinal) finality = 'final ';
      } else {
        finality = 'final ';
      }
    }
    parametersSource.write('$finality${field.type} ${field.name}');
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
  return "$classHeader \{\n  // ...\n\}\n\n$classHeader;";
}

String ppStruct(ClassSpec classSpec) {
  var className = classSpec.name;
  var fields = classSpec.fields;
  var parametersSource = StringBuffer('');

  var first = true;
  for (var field in fields) {
    if (first) {
      first = false;
    } else {
      parametersSource.write(', ');
    }
    var finality = '';
    if (field.isFinal) {
      if (classSpec.isConst || classSpec.isInline) {
        if (!Options.implicitFinal) finality = 'final ';
      } else {
        finality = 'final ';
      }
    }
    parametersSource.write('$finality${field.type} ${field.name}');
  }
  var constNess = classSpec.isConst ? 'const ' : '';
  var typeParameters = classSpec.typeParameters ?? '';

  String superinterfaces = '';
  var specSuperinterfaces = classSpec.superinterfaces;
  if (specSuperinterfaces != null) {
    superinterfaces = '\n    $specSuperinterfaces';
  }

  String constructorName = '$className';
  var constructorNameSpec = classSpec.constructorName;
  if (constructorNameSpec != null) {
    constructorName = '$className.$constructorNameSpec';
  } else {
    constructorName = className;
  }

  var inlinity = classSpec.isInline ? 'inline ' : '';
  var classHeader =
      "${inlinity}class $constNess$constructorName$typeParameters"
      "($parametersSource)"
      "$superinterfaces";
  return "$classHeader \{\n  // ...\n}\n\n$classHeader;";
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
    print('// $comment.\n\n$source\n');
  }

  for (var classSpec in classSpecs) {
    print('// ------------------------------ ${classSpec.provenance}\n');
    if (Options.showNormal) {
      show("Normal", ppNormal(classSpec));
    }
    if (Options.showStruct) {
      show("Struct style", ppStruct(classSpec));
    }
    if (Options.showKeyword) {
      show("Rightmost, with keyword", ppKeyword(classSpec));
    }
  }
}
