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
class DeclarationCode extends Code {
  DeclarationCode.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  DeclarationCode.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid element.
///
/// Should not include any trailing commas,
class ElementCode extends Code {
  ElementCode.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  ElementCode.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid expression.
class ExpressionCode extends Code {
  ExpressionCode.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  ExpressionCode.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid function body.
///
/// This includes any and all code after the parameter list of a function,
/// including modifiers like `async`.
///
/// Both arrow and block function bodies are allowed.
class FunctionBodyCode extends Code {
  FunctionBodyCode.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  FunctionBodyCode.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid identifier.
class IdentifierCode extends Code {
  IdentifierCode.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  IdentifierCode.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code identifying a named argument.
///
/// This should not include any trailing commas.
class NamedArgumentCode extends Code {
  NamedArgumentCode.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  NamedArgumentCode.fromParts(List<Object> parts, {Scope? scope})
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
class ParameterCode extends Code {
  ParameterCode.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  ParameterCode.fromParts(List<Object> parts, {Scope? scope})
      : super.fromParts(parts, scope: scope);
}

/// A piece of code representing a syntactically valid statement.
///
/// Should always end with a semicolon.
class StatementCode extends Code {
  StatementCode.fromString(String code, {Scope? scope})
      : super.fromString(code, scope: scope);

  StatementCode.fromParts(List<Object> parts, {Scope? scope})
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
