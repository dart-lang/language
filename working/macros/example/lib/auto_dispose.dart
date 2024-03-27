// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:macros/macros.dart';

// Interface for disposable things.
abstract class Disposable {
  void dispose();
}

macro class AutoDispose implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const AutoDispose();

  @override
  void buildDeclarationsForClass(
      ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    if (methods.any((d) => d.identifier.name == 'dispose')) {
      // Don't need to add the dispose method, it already exists.
      return;
    }

    builder.declareInType(DeclarationCode.fromParts([
      // TODO: Remove external once the CFE supports it.
      'external void dispose();',
    ]));
  }

  @override
  Future<void> buildDefinitionForClass(
      ClassDeclaration clazz, TypeDefinitionBuilder builder) async {
    var disposableIdentifier =
        // ignore: deprecated_member_use
        await builder.resolveIdentifier(
            Uri.parse('package:macro_proposal/auto_dispose.dart'),
            'Disposable');
    var disposableType = await builder
        .resolve(NamedTypeAnnotationCode(name: disposableIdentifier));

    var disposeCalls = <Code>[];
    var fields = await builder.fieldsOf(clazz);
    for (var field in fields) {
      var type = await builder.resolve(field.type.code);
      if (!await type.isSubtypeOf(disposableType)) continue;
      disposeCalls.add(RawCode.fromParts([
        '\n',
        field.identifier,
        if (field.type.isNullable) '?',
        '.dispose();',
      ]));
    }

    // Augment the dispose method by injecting all the new dispose calls after
    // either a call to `augmented()` or `super.dispose()`, depending on if
    // there already is an existing body to call.
    //
    // If there was an existing body, it is responsible for calling
    // `super.dispose()`.
    var disposeMethod = (await builder.methodsOf(clazz))
        .firstWhere((method) => method.identifier.name == 'dispose');
    var disposeBuilder = await builder.buildMethod(disposeMethod.identifier);
    disposeBuilder.augment(FunctionBodyCode.fromParts([
      '{\n',
      if (disposeMethod.hasExternal || !disposeMethod.hasBody)
        'super.dispose();'
      else
        'augmented();',
      ...disposeCalls,
      '}',
    ]));
  }
}
