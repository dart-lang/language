// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// There is no public API exposed yet, the in-progress API lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

// Interface for disposable things.
abstract class Disposable {
  void dispose();
}

macro class AutoDispose implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const AutoDispose();

  @override
  void buildDeclarationsForClass(
      IntrospectableClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    var methods = await builder.methodsOf(clazz);
    if (methods.any((d) => d.identifier.name == 'dispose')) {
      // Don't need to add the dispose method, it already exists.
      return;
    }

    builder.declareInType(DeclarationCode.fromParts([
      'external void dispose();',
    ]));
  }

  @override
  Future<void> buildDefinitionForClass(
      IntrospectableClassDeclaration clazz, TypeDefinitionBuilder builder) async {
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
    // the call to `augment super()`, which should be calling `super.dispose()`
    // already.
    var disposeMethod = (await builder.methodsOf(clazz))
        .firstWhere((method) => method.identifier.name == 'dispose');
    var disposeBuilder = await builder.buildMethod(disposeMethod.identifier);
    disposeBuilder.augment(FunctionBodyCode.fromParts([
      '{\n',
      if (disposeMethod.hasExternal) 'super.dispose();' else 'augment super();',
      ...disposeCalls,
      '}',
    ]));
  }
}
