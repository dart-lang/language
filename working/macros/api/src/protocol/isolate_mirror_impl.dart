import 'dart:isolate';
import 'dart:mirrors';

import 'package:package_config/package_config.dart';

import '../../builders.dart';
import '../../expansion_protocol.dart';
import '../../introspection.dart';

/// A [MacroExecutor] implementation which relies on [IsolateMirror.loadUri]
/// in order to load macros libraries.
///
/// All actual work happens in a separate [Isolate], and this class serves as
/// a bridge between that isolate and the language frontends.
class IsolateMirrorMacroExecutor implements MacroExecutor {
  final PackageConfig packageConfig;

  IsolateMirrorMacroExecutor(this.packageConfig);

  @override
  Future<String> buildAugmentationLibrary(
      Iterable<MacroExecutionResult> macroResults) {
    // TODO: implement buildAugmentationLibrary
    throw UnimplementedError();
  }

  @override
  Future<MacroExecutionResult> executeDeclarationsPhase(
      MacroInstanceIdentifier macro,
      Declaration declaration,
      TypeComparator typeComparator,
      ClassIntrospector classIntrospector) {
    // TODO: implement executeDeclarationsPhase
    throw UnimplementedError();
  }

  @override
  Future<MacroExecutionResult> executeDefinitionsPhase(
      MacroInstanceIdentifier macro,
      Declaration declaration,
      TypeComparator typeComparator,
      ClassIntrospector classIntrospector,
      TypeIntrospector typeIntrospector) {
    // TODO: implement executeDefinitionsPhase
    throw UnimplementedError();
  }

  @override
  Future<MacroExecutionResult> executeTypesPhase(
      MacroInstanceIdentifier macro, Declaration declaration) {
    // TODO: implement executeTypesPhase
    throw UnimplementedError();
  }

  @override
  Future<MacroInstanceIdentifier> instantiateMacro(
      MacroClassIdentifier macroClass,
      String constructor,
      Arguments arguments) {
    // TODO: implement instantiateMacro
    throw UnimplementedError();
  }

  @override
  Future<MacroClassIdentifier> loadMacro(Uri library, String name) {
    // TODO: implement loadMacro
    throw UnimplementedError();
  }
}
