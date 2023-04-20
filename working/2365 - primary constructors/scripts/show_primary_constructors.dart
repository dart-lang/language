#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

abstract final class Options {
  static bool implicitFinal = false;
}

void help() {
  print('Usage: show_primary_constructors.dart [options] [file]...');
  print("""

 Options:
   --help, -h: Print this help text.
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
  final String name;
  final String? constructorName;
  final bool isInline;
  final List<FieldSpec> fields;
  final bool isConst;
  final String? superinterfaces;
  final String? typeParameters;

  ClassSpec(
    this.name,
    this.constructorName,
    this.isInline,
    this.fields,
    this.isConst,
    this.typeParameters,
    this.superinterfaces,
  );

  factory ClassSpec.fromJson(Map<String, dynamic> jsonSpec) {
    var name = jsonSpec['name']!;
    var constructorName = jsonSpec['constructorName'];
    var isInline = jsonSpec['isInline'] || false;
    var jsonFields = jsonSpec['fields']!;
    var isConst = jsonSpec['isConst'] ?? false;
    var typeParameters = jsonSpec['typeParameters'];
    var superinterfaces = jsonSpec['superinterfaces'];
    var fields = <FieldSpec>[];

    for (var fieldName in jsonFields.keys) {
      var field = FieldSpec.fromJson(fieldName, jsonFields[fieldName]!);
      fields.add(field);
    }
    return ClassSpec(
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

  FieldSpec(this.name, this.type, this.isFinal);

  factory FieldSpec.fromJson(String name, Map<String, dynamic> jsonProperties) {
    var type = jsonProperties['type']!;
    var isFinal = jsonProperties['isFinal'] ?? false;
    return FieldSpec(name, type, isFinal);
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

  return "class $className$typeParameters$superinterfaces"
      " {$fieldsSource$constructorSource  ...\n}";
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
        Options.implicitFinal
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

  var classHeader = "class $className$typeParameters$superinterfaces"
      " $constructorPhrase($parametersSource)";
  return "$classHeader \{\n  ...\n\}\n\n$classHeader;";
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
    var finality = field.isFinal ? 'final ' : '';
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

  var classHeader = "class $constNess$constructorName$typeParameters"
      "($parametersSource)"
      "$superinterfaces";
  return "$classHeader \{\n  ...\n}\n\n$classHeader;";
}

void main(List<String> args) {
  // We expect arguments to be options or file paths.
  var filePaths = processOptions(args);
  if (filePaths.isEmpty) {
    help();
    exit(0);
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
    classSpecs.add(ClassSpec.fromJson(jsonSpec));
  }

  void show(String comment, String source) {
    print('// $comment.\n\n$source\n');
  }

  for (var classSpec in classSpecs) {
    show("Normal", ppNormal(classSpec));
    show("Struct style", ppStruct(classSpec));
    show("Rightmost, with keyword", ppKeyword(classSpec));
  }
}
