// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:macro_client/macro_client.dart';
import 'package:test_macros/equals_macro.dart';
import 'package:test_macros/hash_code_macro.dart';
import 'package:test_macros/to_string_macro.dart';

Future<void> main(List<String> arguments) async {
  await MacroClient(arguments)
      .run([EqualsMacro(), HashCodeMacro(), ToStringMacro()]);
}
