import 'package:macros/macros.dart';
import 'package:macros/src/executor/introspection_impls.dart';

extension DebugCodeString on Code {
  StringBuffer debugString([StringBuffer? buffer]) {
    buffer ??= StringBuffer();
    for (var part in parts) {
      if (part is Code) {
        part.debugString(buffer);
      } else if (part is IdentifierImpl) {
        buffer.write(part.name);
      } else if (part is String) {
        buffer.write(part);
      } else {
        buffer.write(part);
      }
    }
    return buffer;
  }
}
