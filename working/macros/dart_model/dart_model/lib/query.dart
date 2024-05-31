// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'model.dart';

extension type Query.fromJson(Map<String, Object?> node) {
  Query({List<Operation>? operations})
      : this.fromJson({'operations': operations ?? <Object?>[]});

  Query.uri(String uri)
      : this(operations: [
          Operation.include([
            Path([uri])
          ])
        ]);

  Query.qualifiedName({required String uri, required String name})
      : this(operations: [
          Operation.include([
            Path([uri, name])
          ])
        ]);

  Query.annotation(QualifiedName qualifiedName)
      : this(operations: [Operation.annotation(qualifiedName)]);

  List<Operation> get operations => (node['operations'] as List).cast();

  Model query(Model model) {
    Model result = Model();

    for (final operation in operations) {
      if (operation.isInclude) {
        for (final path in operation.paths) {
          if (model.hasPath(path)) {
            final node = model.getAtPath(path);
            result.updateAtPath(path, node);
          }
        }
      } else if (operation.isExclude) {
        for (final path in operation.paths) {
          model.removeAtPath(path);
        }
      } else if (operation.isFollow) {
        // TODO(davidmorgan): implement.
      }
    }

    return result;
  }

  // TODO(davidmorgan): implement properly.
  String get firstUri =>
      operations.firstWhere((o) => o.isInclude).paths[0].path.first;

  String? get firstName {
    final operation = operations.firstWhere((o) => o.isInclude);
    final path = operation.paths[0];
    return path.path.length > 1 ? path.path[1] : null;
  }
}

extension type Operation.fromJson(Map<String, Object?> node) {
  // TODO(davidmorgan): this should be expessable as a general query, not
  // special cased.
  Operation.annotation(QualifiedName qualifiedName)
      : this.fromJson(
            {'type': 'annotation', 'annotationType': qualifiedName.toString()});

  Operation.include(List<Path> include)
      : this.fromJson({'type': 'include', 'paths': include});

  Operation.exclude(List<Path> exclude)
      : this.fromJson({'type': 'exclude', 'paths': exclude});

  Operation.followTypes(int times)
      : this.fromJson({'type': 'followTypes', 'times': times});

  bool get isAnnotation => node['type'] == 'annotation';
  QualifiedName get annotationType =>
      QualifiedName.tryParse((node['annotationType'] as String))!;

  bool get isInclude => node['type'] == 'include';
  bool get isExclude => node['type'] == 'exclude';
  bool get isFollow => node['type'] == 'follow';

  List<Path> get paths => (node['paths'] as List).cast();
}

abstract interface class Service {
  Future<Model> query(Query query);
  Future<void> changeFiles(Iterable<String> files);
}
