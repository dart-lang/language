import 'dart:async';

import '../../api/introspection.dart';
import '../../api/builders.dart';
import '../../api/code.dart';
import '../../api/macros.dart';

/// A very simple macro that annotates functions (or getters) with no arguments
/// and adds a print statement to the top of them.
class SimpleMacro implements FunctionDefinitionMacro {
  @override
  FutureOr<void> buildDefinitionForFunction(
      FunctionDeclaration method, FunctionDefinitionBuilder builder) {
    if (method.namedParameters
        .followedBy(method.positionalParameters)
        .isNotEmpty) {
      throw ArgumentError(
          'This macro can only be ran on functions with no arguments!');
    }
    builder.augment(FunctionBodyCode.fromString('''{
      print('Running ${method.name}!');
      return augment super();
    }'''));
  }
}
