// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:macros/macros.dart';

macro class Equals implements ClassDeclarationsMacro {
  const Equals();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    final fields = await builder.fieldsOf(clazz);
    builder.declareInType(DeclarationCode.fromParts([
      'operator==(other) => other is ',
      clazz.identifier,
      for (final field in fields) ...[
        '&&',
        field.identifier.name,
        ' == other.',
        field.identifier.name,
      ],
      ";",
    ]));
  }
}

macro class HashCode implements ClassDeclarationsMacro {
  const HashCode();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    final fields = await builder.fieldsOf(clazz);
    builder.declareInType(DeclarationCode.fromParts([
      'get hashCode {',
      'hashType<T>() => T.hashCode;',
      'return hashType<',
      clazz.identifier,
      '>()',
      for (final field in fields) ...[
        ' ^ ',
        field.identifier.name,
        '.hashCode',
      ],
      ";}",
    ]));
  }
}

macro class ToString implements ClassDeclarationsMacro {
  const ToString();

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    final fields = await builder.fieldsOf(clazz);
    builder.declareInType(DeclarationCode.fromParts([
      "toString() => '\${",
      clazz.identifier,
      '}(',
      for (final field in fields) ...[
        field.identifier.name,
        ': \$',
        field.identifier.name,
        if (field != fields.last) ', ',
      ],
      ")';",
    ]));
  }
}
