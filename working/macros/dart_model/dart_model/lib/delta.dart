// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:collection/collection.dart';

import 'model.dart';

extension type Update.fromJson(List<Object?> node) {
  Update({
    required Path path,
    required Object? value,
  }) : this.fromJson([path, value]);

  Path get path => node[0] as Path;
  Object? get value => node[1];
}

extension type Removal.fromJson(List<Object?> node) {
  Removal({
    required Path path,
  }) : this.fromJson(path.path);

  Path get path => node as Path;
}

extension type Delta.fromJson(Map<String, Object?> node) {
  Delta({
    List<Update>? updates,
    List<Removal>? removals,
  }) : this.fromJson({
          'updates': updates ?? [],
          'removals': removals ?? [],
        });

  static Delta compute(Model previous, Model current) {
    final updates = <Update>[];
    final removals = <Removal>[];
    _compute(previous, current, Path([]), updates, removals);
    return Delta(updates: updates, removals: removals);
  }

  static void _compute(Model previous, Model current, Path path,
      List<Update> updates, List<Removal> removals) {
    for (final key
        in previous.node.keys.followedBy(current.node.keys).toSet()) {
      final keyIsInPrevious = previous.node.containsKey(key);
      final keyIsInCurrent = current.node.containsKey(key);

      if (keyIsInPrevious && !keyIsInCurrent) {
        removals.add(Removal(path: path.followedByOne(key)));
      } else if (keyIsInPrevious && keyIsInCurrent) {
        // It's either the same or a change.
        final previousValue = previous.node[key]!;
        final currentValue = current.node[key]!;

        if (currentValue is Map<String, Object?>) {
          if (previousValue is Map<String, Object?>) {
            _compute(previousValue as Model, currentValue as Model,
                path.followedByOne(key), updates, removals);
          } else {
            updates.add(
                Update(path: path.followedByOne(key), value: currentValue));
          }
        } else if (currentValue is String) {
          if (previousValue is! String || previousValue != currentValue) {
            updates.add(
                Update(path: path.followedByOne(key), value: currentValue));
          }
        } else if (currentValue is List) {
          if (previousValue is! List ||
              !const DeepCollectionEquality()
                  .equals(previousValue, currentValue)) {
            updates.add(
                Update(path: path.followedByOne(key), value: currentValue));
          }
        } else {
          throw 'Not sure what to do: $previousValue $currentValue';
        }
      } else {
        // It's new.
        updates.add(
            Update(path: path.followedByOne(key), value: current.node[key]));
      }
    }
  }

  bool get isEmpty => updates.isEmpty && removals.isEmpty;

  List<Update> get updates => (node['updates'] as List).cast();

  List<Removal> get removals => (node['removals'] as List).cast();

  String prettyPrint() => const JsonEncoder.withIndent('  ').convert(node);

  void update(Model previous) {
    for (final update in updates) {
      previous.updateAtPath(update.path, update.value);
    }
    for (final removal in removals) {
      previous.removeAtPath(removal.path);
    }
  }
}
