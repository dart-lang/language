// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

var enabled = false;

final _counts = <String, int>{};

void count(String name, [String? subname]) {
  if (!enabled) return;
  _counts.putIfAbsent(name, () => 0);
  _counts[name] = _counts[name]! + 1;

  if (subname != null) {
    count('$name/$subname');
  }
}

void run(void Function() callback) {
  reset();
  try {
    callback();
  } finally {
    log();
    reset();
  }
}

void reset() {
  _counts.clear();
}

void log() {
  var names = _counts.keys.toList();
  names.sort();
  var nameLength =
      names.fold<int>(0, (length, name) => max(length, name.length));
  var countLength = _counts.values
      .fold<int>(0, (length, count) => max(length, count.toString().length));

  for (var name in names) {
    print('${name.padRight(nameLength)} = '
        '${_counts[name].toString().padLeft(countLength)}');
  }
}
