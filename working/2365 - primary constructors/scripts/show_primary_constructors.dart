#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

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
    }
    return false;
  } else if (option.startsWith('-')) {
    var optionString = option.substring(1);
    for (var c in optionString.split('')) {
      switch (c) {
        case 'h':
          help();
          return true;
      }
      return false;
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

String ppNormal(Map<String, dynamic> jsonSpec) {
  var className = jsonSpec['name']!;
  var fields = jsonSpec['fields']!; 

  for (var field in fields.keys) {
    var properties = fields[field]!;
    
  }

  return """
class $name {
$fieldsSource
$constructorSource
}
""";
}


void main(List<String> args) {
  // We expect arguments to be options or file paths.
  var filePaths = processOptions(args);
  if (filePaths.isEmpty) {
    help();
    exit(0);
  }
  
  var jsonSpecs = <Map<String, dynamic>>[];
  for (var filePath in filePaths) {
    String source;
    try {
      source = File(filePath).readAsStringSync();
    } catch (_) {
      print("Could not read '$filePath'.");
      fail();
    }
    jsonSpecs.add(jsonDecode(source));
  }

  
  print(var jsonSpec in jsonSpecs) {
    
  }
}
