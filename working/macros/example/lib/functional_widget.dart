// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// There is no public API exposed yet, the in progress api lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class FunctionalWidget implements FunctionTypesMacro {
  final Identifier? widgetIdentifier;

  const FunctionalWidget(
      {
      // Defaults to removing the leading `_` from the function name and calling
      // `toUpperCase` on the next character.
      this.widgetIdentifier});

  @override
  void buildTypesForFunction(
      FunctionDeclaration function, TypeBuilder builder) {
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
    builder.declareType(
        widgetName,
        DeclarationCode.fromParts([
          'class $widgetName extends StatelessWidget {',
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
          'Key? key,',
          '}',
          ') : super(key: key);',
          // Build method
          '''
          @override
          Widget build(BuildContext context) => ''',
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
