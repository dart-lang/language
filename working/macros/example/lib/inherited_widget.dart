// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:macros/macros.dart';

/// A macro that annotates a class and turns it into an inherited widget.
///
/// This will fill in any "holes" that do not have custom implementations,
/// specifically the following items will be added if they don't exist:
///
/// - Make the class extend `InheritedWidget`.
/// - Add a constructor that will initialize any fields that are defined, and
///   take `key` and `child` parameters which it forwards to the super
///   constructor.
/// - Add static `of` and `maybeOf` methods which take a build context and
///   return an instance of this class using `dependOnIheritedWidgetOfExactType`.
/// - Add an `updateShouldNotify` method which does checks for equality of all
///   fields.
macro class InheritedWidget implements ClassTypesMacro, ClassDeclarationsMacro {
  const InheritedWidget();

  @override
  void buildTypesForClass(ClassDeclaration clazz, ClassTypeBuilder builder) {
    if (clazz.superclass != null) return;
    // TODO: Add `extends InheritedWidget` once we have an API for that.
  }

  @override
  Future<void> buildDeclarationsForClass(
      ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    final fields = await builder.fieldsOf(clazz);
    final methods = await builder.methodsOf(clazz);
    if (!methods.any((method) => method is ConstructorDeclaration)) {
      builder.declareInType(DeclarationCode.fromParts([
        'const ${clazz.identifier.name}(',
        '{',
        for (var field in fields) ...[
          field.type.isNullable ? '' : 'required ',
          field.identifier,
          ',',
        ],
        'super.key,',
        'required super.child,',
        '});',
      ]));
    }

    final buildContext =
        // ignore: deprecated_member_use
        await builder.resolveIdentifier(
            Uri.parse('package:flutter/widgets.dart'), 'BuildContext');
    if (!methods.any((method) => method.identifier.name == "maybeOf")) {
      builder.declareInType(DeclarationCode.fromParts([
        'static ',
        clazz.identifier,
        '? maybeOf(',
        buildContext,
        ' context) => context.dependOnInheritedWidgetOfExactType<',
        clazz.identifier,
        '>();',
      ]));
    }

    if (!methods.any((method) => method.identifier.name == "of")) {
      builder.declareInType(DeclarationCode.fromParts([
        'static ',
        clazz.identifier,
        ' of(',
        buildContext,
        ''' context) {
          final result = this.maybeOf(context);
          assert(result != null, 'No ${clazz.identifier.name} found in context');
          return result!;
        }''',
      ]));
    }

    if (!methods
        .any((method) => method.identifier.name == 'updateShouldNotify')) {
      // ignore: deprecated_member_use
      final override = await builder.resolveIdentifier(
          Uri.parse('package:meta/meta.dart'), 'override');
      builder.declareInType(DeclarationCode.fromParts([
        '@',
        override,
        ' bool updateShouldNotify(',
        clazz.identifier,
        ' oldWidget) =>',
        ...[
          for (var field in fields)
            'oldWidget.${field.identifier.name} != this.${field.identifier.name}',
        ].joinAsCode(' || '),
        ';',
      ]));
    }
  }
}
