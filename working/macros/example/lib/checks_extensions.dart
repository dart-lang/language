// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

// There is no public API exposed yet, the in-progress API lives here.
import 'package:_fe_analyzer_shared/src/macros/api.dart';

import 'util.dart';

/// Generates extensions for the `checks` package for a list of types.
///
/// The extensions will be "on" the type `Subject<SomeType>`, for each given
/// type.
///
/// Each extension will have a getter for each field in the type it is
/// targetting, of the form `Subject<SomeFieldType>
macro class ChecksExtensions implements LibraryTypesMacro {
  final List<TypeAnnotation> types;

  const ChecksExtensions(this.types);

  @override
  Future<void> buildTypesForLibrary(
      Library library, TypeBuilder builder) async {
    // ignore: deprecated_member_use
    final subject = await builder.resolveIdentifier(
        Uri.parse('package:checks/checks.dart'), 'Subject');
    // ignore: deprecated_member_use
    final checksExtension = await builder.resolveIdentifier(
        Uri.parse('package:macro_proposal/checks_extensions.dart'),
        'ChecksExtension');
    for (final type in types) {
      if (type is! NamedTypeAnnotation) {
        throw StateError('only named types are supported');
      }
      if (type.typeArguments.isNotEmpty) {
        throw StateError('Cannot generate checks extensions for types with '
            'explicit generics');
      }
      final name = '${type.identifier.name}Checks';
      builder.declareType(
          name,
          DeclarationCode.fromParts([
            '@',
            checksExtension,
            '()',
            'extension $name on ',
            NamedTypeAnnotationCode(name: subject, typeArguments: [type.code]),
            '{}',
          ]));
    }
  }
}

/// Adds getters to an extension on a `Subject` type which abstract away the
/// `has` calls for all the fields of the subject.
macro class ChecksExtension implements ExtensionDeclarationsMacro {
  const ChecksExtension();

  Future<void> buildDeclarationsForExtension(
      ExtensionDeclaration extension, MemberDeclarationBuilder builder) async {
    // ignore: deprecated_member_use
    final subject = await builder.resolveIdentifier(
        Uri.parse('package:checks/checks.dart'), 'Subject');
    final onType = extension.onType;
    if (onType is! NamedTypeAnnotation ||
        onType.identifier != subject ||
        onType.typeArguments.length != 1) {
      throw StateError(
          'The `on` type must be a Subject with an explicit type argument.');
    }

    // Find the real named type declaration for our on type, and ensure its a
    // real named type (ie: not a function or record type, etc);
    final onTypeDeclaration = await _namedTypeDeclarationOrThrow(
        onType.typeArguments.single, builder);

    // Ensure that our `on` type is coming from a null safe library, we don't
    // support legacy code.
    switch (onTypeDeclaration.library.languageVersion) {
      case LanguageVersion(:int major) when major < 2:
      case LanguageVersion(major: 2, :int minor) when minor < 12:
        throw InvalidCheckExtensions('must be imported in a null safe library');
    }

    // Generate the getters
    final fields =
        await builder.fieldsOf(onTypeDeclaration as IntrospectableType);
    for (final field in fields) {
      if (_isCheckableField(field))
        await _declareHasGetter(field, builder, subject);
    }
  }

  /// Find the named type declaration for [type], or throw if it doesn't refer
  /// to a named type.
  ///
  /// Type aliases are followed to their underlying types.
  Future<TypeDeclaration> _namedTypeDeclarationOrThrow(
      TypeAnnotation type, DeclarationBuilder builder) async {
    if (type is! NamedTypeAnnotation) {
      throw StateError('Got a non interface type: ${type.code.debugString()}');
    }
    var onTypeDeclaration = await builder.typeDeclarationOf(type.identifier);
    while (onTypeDeclaration is TypeAliasDeclaration) {
      final aliasedTypeAnnotation = onTypeDeclaration.aliasedType;
      if (aliasedTypeAnnotation is! NamedTypeAnnotation) {
        throw StateError(
            'Got a non interface type: ${type.code.debugString()}');
      }
      onTypeDeclaration =
          await (builder.typeDeclarationOf(aliasedTypeAnnotation.identifier));
    }
    return onTypeDeclaration;
  }

  /// Declares a getter for [field] that is a convenience method for calling
  /// `has` and extracting out the field.
  Future<void> _declareHasGetter(FieldDeclaration field,
      MemberDeclarationBuilder builder, Identifier subject) async {
    final name = field.identifier.name;
    builder.declareInType(DeclarationCode.fromParts([
      NamedTypeAnnotationCode(name: subject, typeArguments: [field.type.code]),
      // TODO: Use an identifier for `has`? It exists on `this` so it isn't
      // strictly necessary, this should always work.
      'get $name => has(',
      '(v) => v.$name,',
      "'$name'",
      ');',
    ]));
  }

  bool _isCheckableField(FieldDeclaration field) =>
      field.identifier.name != 'hashCode' && !field.isStatic;
}

class InvalidCheckExtensions extends Error {
  final String message;
  InvalidCheckExtensions(this.message);
  @override
  String toString() => 'Invalid `CheckExtensions` annotation: $message';
}
