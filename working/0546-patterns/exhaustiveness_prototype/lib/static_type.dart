// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO: Generics.

/// A static type in the type system.
class StaticType {
  /// Built-in top type that all types are a subtype of.
  static final top = StaticType('top', inherits: []);

  final String name;

  /// Whether this type is sealed. A sealed type is implicitly abstract and has
  /// a closed set of known subtypes. This means that every instance of the
  /// type must be an instance of one of those subtypes. Conversely, if an
  /// instance is *not* an instance of one of those subtypes, that it must not
  /// be an instance of this type.
  ///
  /// Note that subtypes of a sealed type do not themselves have to be sealed.
  /// Consider:
  ///
  ///      (A)
  ///      / \
  ///     B   C
  ///
  /// Here, A is sealed and B and C are not. There may be many unknown
  /// subclasses of B and C, or classes implementing their interfaces. That
  /// doesn't interfere with exhaustiveness checking because it's still the
  /// case that any instance of A must be either a B or C *or some subtype of
  /// one of those two types*.
  final bool isSealed;

  /// The static types of the fields this type exposes for record destructuring.
  ///
  /// Includes inherited fields.
  Map<String, StaticType> get fields {
    return {for (var supertype in supertypes) ...supertype.fields, ..._fields};
  }

  final Map<String, StaticType> _fields;

  final List<StaticType> supertypes = [];

  /// The immediate subtypes of this type.
  Iterable<StaticType> get subtypes => _subtypes;
  final List<StaticType> _subtypes = [];

  Iterable<StaticType> get allSupertypes sync* {
    for (var supertype in supertypes) {
      yield supertype;
      yield* supertype.allSupertypes;
    }
  }

  StaticType(this.name,
      {this.isSealed = false,
      List<StaticType>? inherits,
      Map<String, StaticType> fields = const {}})
      : _fields = fields {
    if (inherits != null) {
      for (var type in inherits) {
        supertypes.add(type);
        type._subtypes.add(this);
      }
    } else {
      supertypes.add(top);
    }

    var sealed = 0;
    for (var supertype in supertypes) {
      if (supertype.isSealed) sealed++;
    }

    // We don't allow a sealed type's subtypes to be shared with some other
    // sibling supertype, as in D here:
    //
    //   (A) (B)
    //   / \ / \
    //  C   D   E
    //
    // We could remove this restriction but doing so will require
    // expandTypes() to be more complex. In the example here, if we subtract
    // E from A, the result should be C|D. That requires knowing that B should
    // be expanded, which expandTypes() doesn't currently handle.
    if (sealed > 1) throw ArgumentError('Can only have one sealed supertype.');
  }

  bool isSubtypeOf(StaticType supertype) {
    if (this == supertype) return true;
    return allSupertypes.contains(supertype);
  }

  @override
  String toString() => name;
}
