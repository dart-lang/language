/// A scope in which to resolve a chunk of code.
///
/// TODO: Handle more deeply nested scopes (such as a scope specific to a class
/// or method body).
class Scope {
  /// Identifiers should be resolved as if they existed in this library.
  final Uri libraryUri;

  Scope(this.libraryUri);
}

/// The base class representing an arbitrary chunk of Dart code, which may or
/// may not be syntacically or semantically valid yet.
class Code {
  /// The scope in which to resolve anything from [parts] that does not have its
  /// own scope already defined.
  final Scope? scope;

  /// All the chunks of [Code] or raw [String]s that comprise this [Code]
  /// object.
  final List<Object> parts;

  Code.fromString(String code, {this.scope}) : parts = [code];

  Code.fromParts(this.parts, {this.scope});
}

/// A piece of code representing a syntactically valid declaration.
class Declaration extends Code {
  Declaration.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  Declaration.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid element.
///
/// Should not include any trailing commas,
class Element extends Code {
  Element.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  Element.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid expression.
class Expression extends Code {
  Expression.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  Expression.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid function body.
///
/// This includes any and all code after the parameter list of a function,
/// including modifiers like `async`.
///
/// Both arrow and block function bodies are allowed.
class FunctionBody extends Code {
  FunctionBody.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  FunctionBody.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid identifier.
class Identifier extends Code {
  Identifier.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  Identifier.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code identifying a named argument.
///
/// This should not include any trailing commas.
class NamedArgument extends Code {
  NamedArgument.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  NamedArgument.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code identifying a syntactically valid function parameter.
///
/// This should not include any trailing commas, but may include modifiers
/// such as `required`, and default values.
///
/// There is no distinction here made between named and positional parameters,
/// nor between optional or required parameters. It is the job of the user to
/// construct and combine these together in a way that creates valid parameter
/// lists.
class Parameter extends Code {
  Parameter.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  Parameter.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid statement.
///
/// Should always end with a semicolon.
class Statement extends Code {
  Statement.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  Statement.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

extension Join<T extends Code> on List<T> {
  /// Joins all the items in [this] with [separator], and returns
  /// a new list.
  List<Code> joinAsCode(String separator) => [
        for (var i = 0; i < length - 1; i++) ...[
          this[i],
          Code.fromString(separator),
        ],
        last,
      ];
}
