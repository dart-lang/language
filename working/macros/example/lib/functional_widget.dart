// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:macros/macros.dart';

/// A macro that annotates a function, which becomes the build method for a
/// generated stateless widget.
///
/// The function must have at least one positional parameter, which is of type
/// BuildContext (and this must be the first parameter).
///
/// Any additional function parameters are turned into fields on the stateless
/// widget.
macro class FunctionalWidget implements FunctionTypesMacro {
  final Identifier? widgetIdentifier;

  const FunctionalWidget(
      {
      // Defaults to removing the leading `_` from the function name and calling
      // `toUpperCase` on the next character.
      this.widgetIdentifier});

  @override
  Future<void> buildTypesForFunction(
      FunctionDeclaration function, TypeBuilder builder) async {
    if (!function.identifier.name.startsWith('_')) {
      throw ArgumentError(
          'FunctionalWidget should only be used on private declarations');
    }
    if (function.positionalParameters.isEmpty ||
        // TODO: A proper type check here.
        (function.positionalParameters.first.type as NamedTypeAnnotation)
                .identifier
                .name !=
            'BuildContext') {
      throw ArgumentError(
          'FunctionalWidget functions must have a BuildContext argument as the '
          'first positional argument');
    }

    var widgetName = widgetIdentifier?.name ??
        function.identifier.name
            .replaceRange(0, 2, function.identifier.name[1].toUpperCase());
    var positionalFieldParams = function.positionalParameters.skip(1);
    // ignore: deprecated_member_use
    var statelessWidget = await builder.resolveIdentifier(
        Uri.parse('package:flutter/widgets.dart'), 'StatelessWidget');
    // ignore: deprecated_member_use
    var buildContext = await builder.resolveIdentifier(
        Uri.parse('package:flutter/widgets.dart'), 'BuildContext');
    // ignore: deprecated_member_use
    var widget = await builder.resolveIdentifier(
        Uri.parse('package:flutter/widgets.dart'), 'Widget');
    builder.declareType(
        widgetName,
        DeclarationCode.fromParts([
          'class $widgetName extends ', statelessWidget, ' {',
          // Fields
          for (var param
              in positionalFieldParams.followedBy(function.namedParameters))
            DeclarationCode.fromParts([
              'final ',
              param.type.code,
              ' ',
              param.identifier.name,
              ';',
            ]),
          // Constructor
          'const $widgetName(',
          for (var param in positionalFieldParams)
            'this.${param.identifier.name}, ',
          '{',
          for (var param in function.namedParameters)
            '${param.isRequired ? 'required ' : ''}this.${param.identifier.name}, ',
          'super.key,',
          '});',
          // Build method
          '@override ',
          widget,
          ' build(',
          buildContext,
          ' context) => ',
          function.identifier,
          '(context, ',
          for (var param in positionalFieldParams) '${param.identifier.name}, ',
          for (var param in function.namedParameters)
            '${param.identifier.name}: ${param.identifier.name}, ',
          ');',
          '}',
        ]));
  }
}
