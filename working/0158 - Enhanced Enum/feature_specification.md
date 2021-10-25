# Dart Enhanced Enum Classes

Author: lrn@google.com<br>Version: 1.1<br>Tracking issue [#158](https://github.com/dart-lang/language/issues/158)

This is a formal proposal for a language feature which allows `enum` declarations to declare classes with fields, methods and const constructors initializing those fields. Further, `enum` declarations can implement interfaces and, as an optional feature, apply mixins.

## Grammar

Dart enum declarations are currently restricted to:

```dart
enum Name {
  id1, id2, id3
}
```

That is: `enum`, a single identifier for the name, and a block containing a comma separated list of identifiers.

We propose the following to also be allowed:

```dart
enum Name<T> with Mixin1, Mixin2 implements Interface1, Interface2 {
  id1<int>(args1), id2<String>(args2), id3<bool>(args3);
  memberDeclaration*
  const Name(params) : initList;
}
```

where `memberDeclaration*` is any sequence of static and instance member declarations and/or an unnamed generative `const` constructor declaration.

The `;` after the identifier list is optional if there is nothing else in the declaration, required if there is any member declaration after it. The identifier list may have a trailing comma (like now).

The superclass of the mixin applications is the `Enum` class (which has an *abstract* `index` getter, so the only valid `super` invocations are those valid on `Object`).

The grammar of the `enum` declaration becomes:

```ebnf
<enumType> ::=
  `enum' <identifier> <typeParameters>? <mixins>? <interfaces>? `{'
     <enumEntry> (`,' <enumEntry>)* (`,')? (`;'
     (<metadata> <classMemberDefinition>)*
     )?
  `}'

<enumEntry> ::= <metadata> <identifier> <argumentPart>?
  | <metadata> <identifier> <typeArguments>? `.' <identifier> <arguments>
```

It is a compile-time error if the enum declaration contains any generative constructor which is not `const`.

_We_ can _allow omitting the `const` on constructors since it’s required, so we can just assume it’s there. That’s a convenience we can also add at any later point._

## Semantics

The semantics of such an enum declaration is defined by *rewriting into a class declaration* as follows:

- Declare a class with the same name and type parameters as the `enum` declaration.

- Add `extends Enum`.

- Further add the mixins and interfaces of the `enum` declaration.

- Add `final int index;` and `final String _$name;` instance variable declarations to the class. (We’ll represent fresh names by prefixing with `_$` here and below).

- For each member declaration:

  - If the member declaration is a (necessarily `const`) generative constructor, introduce a similar named constructor on the class with a fresh name, which takes two extra leading positional arguments (`Name.foo(...)` &mapsto; `Name._$foo(int .., String .., ...)`, `Name(...)` &mapsto; `Name._$(int .., String .., ...)`). If the constructor is non-redirecting, make the two arguments `this.index` and `this._$name`. If the constructor is redirecting, make them `int _$index` and `String _$name`, then change the target of the redirection to the corresponding freshly-renamed constructor and pass `_$index` and `_$name` as two extra initial positional arguments.
  - Otherwise include the member as written.

- If no generative constructors were declared, and no unnamed factory constructor was added, a default generative constructor `const Name._$(this.index, this._$name);` is added.

- If no `toString` member was declared, add `String toString() => “Name.${_$name}”;`.

- For each `<enumEntry>` with name `id` and index *i* in the comma-separated list of enum entries, a static constant is added as follows:

  - `id` &mapsto;  `static const Name id = Name._$(i, "id");` &mdash; equivalent to `id()`.
  - `id(args)` &mapsto; `static const Name id = Name._$(i, “id”, args);` &mdash; if `Name` is not generic
  - `id<types>(args)` &mapsto; `static const Name<types> id = Name<types>._$(i, “id”, args);`
  - `id.named(args)` &mapsto; `static const Name id = Name._$named(i, “id”, args);`  &mdash; if `Name` is not generic
  - `id<types>.named(args)` &mapsto; `static const Name<types> id = Name<types>._$named(i, “id”, args);`

  (We expect type inference to have been applied to the generic constructor invocations where necessary, so generic class constructor invocations have their type arguments.)

- Also a static constant named `values` is added as:

  - `static const List<Name> values = [id1, …, idn];`
    where `id1`…`idn` are the names of the enum entries of the `enum` declaration in source/index order. If `Name` is generic, the `List<Name>` instantiates it to bounds.

If the resulting class would have any naming conflicts, or other compile-time errors, the `enum` declaration is invalid and a compile-time error occurs. Otherwise the `enum` declaration has an interface and behavior which is equivalent to that class declaration. (We don’t require it to *be* that class declaration, there might be other helper classes involved in the implementation, but the interface and behavior should match.)

This `enum` declaration above is therefore defined to be extensionally equivalent to:

```dart
class Name<T> extends Enum with Mixin1, Mixin2 implements Interface1, Interface2 {
  static const Name<int> id1 = Name<int>._$(0, "id1", args1);
  static const Name<String> id2 = Name<String>._$(1, "id2", args2);
  static const Name<bool> id3 = Name<bool>._$(2, "id3", args3);
  static const List<Name<Object?>> values = [id1, id2, id3];

  final int index;
  final String _name;

  Name._$(this.index, this._name, params) : initList

  memberDeclarations*

  String toString() => "Name.$_name"; // Unless defined by memberDeclarations.
}
```

### Implementing `Enum`

It’s currently a compile-time error for a class to implement, extend or mix-in the `Enum` class.

Because we want to allow interfaces and mixins that are intended to be applied to `enum` declarations, and therefore to assume `Enum` to be a superclass, we loosen that restriction to:

> It’s a compile-time error if a *non-abstract* class implements `Enum` unless it is the implicit class of an `enum` declaration.
>
> It is a compile-time error if a class implements, extends or mixes-in a class declared by an `enum` declaration.

That allows abstract classes (interfaces) which implements `Enum` in order to have the `int index;` getter member available, and it allows `mixin` declarations to use `Enum` as an `on` type because `mixin` declarations cannot be instantiated directly.

This restriction still ensure  `enum` values are the only object instances which implements `Enum`, while making it valid to declare `abstract class MyInterface implements Enum` and `mixin MyMixin on Enum` for interfaces and mixins intended to be used in declaring `enum` classes.

## Formatting

The recommended formatting of an `enum` declaration is to format the header (before the first `{`) just like a class declaration. Then, if the enum entries have arguments (if they are anything but single identifiers), then put each entry on a line by its own. If there is no trailing comma, put the semicolon after the last entry. If there is a trailing comma, put the semicolon on the next line, by itself. Then have an empty line before the member declarations, which are formatted just they would be in a class declaration.

## Summary

We let `enum` declarations be much more like classes, just classes with a fixed number of known constant instances. We allow the class to apply mixins (applicable to a supertype of `Enum`) and implement interfaces. We allow any static or instance member declaration, and any generative `const` constructor declaration (so instance variables must be final, including those added by mixins, otherwise the mixin application constructor forwarders to the superclass `const Enum()` constructor won’t be `const`).

The enum values can call the declared constructors, or the default unnamed zero-argument `const` constructor which is added if no other constructor is declared. The syntax looks like a constructor invocation except that the enum value name replaces the class name. If no type arguments or value arguments are needed, and the constructor invoked is unnamed, the enum value can still be a plain identifier.

The only differences between an `enum` declared class and a hand-written “equivalent class” is that:

- `enum` classes support exhaustiveness checks in switch cases.
- The `EnumName.name` extension member works on `enum` values.

## Examples:

### Plain, existing syntax

```dart
enum Plain {
  foo, bar, baz
}
```

has equivalent class:

```dart
class Plain extends Enum {
  static const Plain foo = Plain._$(0, "foo");
  static const Plain bar = Plain._$(1, "bar");
  static const Plain baz = Plain._$(2, "baz");
  static const List<Plain> values = [foo, bar, baz];

  final int index;
  final String _$name;

  const Plain._$(this.index, this._$name);

  String toString() => "Plain,${_$name}";
}
```

### Complex, one with everything

```dart
mixin EnumComparable<T extends Enum> on Enum implements Comparable<T> {
  int compareTo(T other) => this.index - other.index;
}

// With type argument, mixin and interface.
enum Complex<T extends Pattern> with EnumComparable<Complex> implements Pattern {
  whitespace<RegExp>(r"\s+", RegExp.new),
  alphanum<RegExp>.captured(r"\w+", RegExp.new),
  anychar<Glob>("?", Glob.new),
  ;

  // Static variables. (Could use Expando, this is more likely efficient.)
  static final List<Pattern?> _patterns = List<Pattern?>.filled(3, null);

  // Final instance variables.
  final String _patternSource;
  final T Function(String) _factory;

  // Unnamed constructor. Non-redirecting.
  const Complex(String pattern, T Function(String) factory)
      : _patternSource = pattern, _factory = factory;

  // Factory constructor.
  factory Complex.matching(String text) {
    for (var value in values) {
      if (value.allMatches(text).isNotEmpty && value is Complex<T>) {
        return value;
      }
    }
    throw UnsupportedError("No pattern matching: $text");
  }

  // Named constructor. Redirecting.
  const Complex.captured(String regexpPattern)
      : this("($regexpPattern)", RegExp);

  // Can expose the implicit name.
  String get name => EnumName(this).name;

  // Instance getter.
  Pattern get pattern => _patterns[this.index] ??= _factory(_patternSource);

  // Instance methods.
  Iterable<Match> allMatches(String input, [int start = 0]) =>
      pattern.allMatches(input, start);

  Match? matchAsPrefix(String input, [int start = 0]) =>
      pattern.matchAsPrefix(input, start);

  // Specifies `toString`.
  String toString() => "Complex<$T>($_patternSource)";
}
```

has equivalent class:

```dart
class Complex<T extends Pattern> extends Enum with EnumComparable<Complex>
    implements Pattern {
  static const Complex<RegExp> whitespace =
      Complex<RegExp>(r"\s+", RegExp.new);
  static const Complex<RegExp> alphanum =
      Complex<RegExp>.captured(r"\w+", RegExp.new);
  static const Complex<Glob> anychar = Complex<Glob>("?", Glob.new);
  static const List<Complex<Pattern>> values = [whitespace, alphanum, anychar];

  static final List<Pattern?> _patterns = List<Pattern?>.filled(3, null);

  final int index;
  final String _$name;
  final String _patternSource;
  final T Function(String) _factory;

  const Complex._$(this.index, this._$name, String pattern, T Function(String) factory)
      : _patternSource = pattern, _factory = factory;

  factory Complex.matching(String text) {
    for (var value in values) {
      if (value.allMatches(text).isNotEmpty && value is Complex<T>) {
        return value;
      }
    }
    throw UnsupportedError("No pattern matching: $text");
  }

  const Complex.captured(int _$index, String _$name, String regexpPattern)
      : this(_$index, _$name, "($regexpPattern)", RegExp);

  String get name => EnumName(this).name;

  Pattern get pattern => _patterns[this.index] ??= _factory(_patternSource);

  Iterable<Match> allMatches(String input, [int start = 0]) =>
      pattern.allMatches(input, start);

  Match? matchAsPrefix(String input, [int start = 0]) =>
      pattern.matchAsPrefix(input, start);

  String toString() => "Complex<$T>($_patternSource)";
}
```

### Singleton

```dart
enum MySingleton implements Whatever {
  instance;

  const MySingleton(...) : ...;
  // Normal class declarations.
}
```

has equivalent class

```dart
class MySingleton extends Enum implements Whatever {
  static const MySingleton instance = MySingleton._$(0, "instance");
  static const List<MySingleton> values = [instance];
  final int index;
  final String _$name;
  const MySingleton._$(this.index, this._$name, ...) : ...;
  // Normal class declarations.
}
```

There is a chance that people will start using `enum` declarations to declare singleton classes. It has a little overhead, but it’s finite (and the `values` getter can likely be tree-shaken).

## Versions

1.0: Initial version.
1.1, Oct 11 2021: Add missing `const` to some constructor declarations.
