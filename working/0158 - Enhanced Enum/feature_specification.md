# MOVED TO ACCEPTED

Further development happens in [../../accepted/future-releases/enhanced-enums/feature_specification.md].

# Dart Enhanced Enum Classes

Author: lrn@google.com<br>Version: 1.4<br>Tracking issue [#158](https://github.com/dart-lang/language/issues/158)

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
enum Name<T extends Object?> with Mixin1, Mixin2 implements Interface1, Interface2 {
  id1<int>(args1), id2<String>(args2), id3<bool>(args3);
  memberDeclaration*
  const Name(params) : initList;
}
```

where `memberDeclaration*` is almost any sequence of static and instance member declarations, or constructors, 
with some necessary restrictions specified below.

The `;` after the identifier list is optional if there is nothing else in the declaration, required if there is any member declaration after it. The identifier list may have a trailing comma (like now).

The superclass of the mixin applications is the `Enum` class (which has an *abstract* `index` getter, so the only valid `super` invocations on that superclass are those valid on `Object`, `super.index` must be an error).

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

_We_ can _allow omitting the `const` on constructors since it’s required, so we could just assume it’s always there. 
That’s a convenience we can also add at any later point. For now we require it._

It is a compile-time error if the initializer list of a non-redirecting generative constructor includes a `super` constructor invocation.

_We will introduce the necessary super-invocation ourselves. We could allow `super()`, which will be the constructor of `Enum`, but it's 
simpler to just disallow it._

It is a compile-time error to refer to a declared or default generative constructor of an `enum` declaration in any way, other than:
* As the target of a redirecting generative constructor of the same `enum`, or
* Implicitly in the enum value declarations of the same `enum`.

_No-one is allowed to invoke a generative constructor and create another instance of the `enum`. 
That also means that a redirecting *factory* constructor cannot redirect to a generative constructor of an `enum`,
and therefore no factory constructor of an `enum` declaration can be `const`, because a `const` factory constructor 
must redirect to a generative constructor._

## Semantics

First we will add a `const Enum();` constructor to the `Enum` class, so that it can validly be a superclass of `enum` classes. _(The `Enum` class currently has a non-`const` default constructor that no-one can use because the class is abstract and cannot be extended, and in practice `enum` classes implement it instead. We now need to, at least pretend to, extend it so that mixins `on Enum` can be applied.)_

The semantics of such an enum declaration is defined as being equivalent to *rewriting into a corresponding class declaration* as follows:

- Declare a class with the same name and type parameters as the `enum` declaration.

- Add `extends Enum`, where `Enum` refers to the type declared in `dart:core`.

- Further add the mixins and interfaces of the `enum` declaration.

- Add `final int index;` and `final String _$name;` instance variable declarations to the class. 
  (We’ll represent fresh names by prefixing with `_$` here and below, and `int` and `String` both refer to the type declared in `dart:core`).

- For each member declaration:

  - If the member declaration is a (necessarily `const`) generative constructor, 
    introduce a similar named constructor on the class with a fresh name, 
    which takes two extra leading positional arguments (`Name.foo(...):...;` &mapsto; `Name._$foo(int .., String .., ...):...`,
    `Name(...):...;` &mapsto; `Name._$(int .., String .., ...):...`). 
    If the constructor is non-redirecting, make the two arguments `this.index` and `this._$name`. 
    If the constructor is redirecting, make them `int _$index` and `String _$name`, 
    then change the target of the redirection to its corresponding freshly-renamed constructor 
    and pass `_$index` and `_$name` as two extra initial positional arguments.
  - Otherwise include the member as written.

- If no generative constructors were declared, and no unnamed factory constructor was added,
  a default generative constructor `const Name._$(this.index, this._$name);` is added.

- If no `toString` member overriding `Object.toString` was declared or inherited _(from mixin applications)_,
  A `String toString() => “Name.${_$name}”;` instance method is added.

- For each `<enumEntry>` with name `id` and index *i* in the comma-separated list of enum entries, a static constant is added as follows:

  - `id` &mapsto;  `static const id = Name._$(i, "id");` &mdash; equivalent to `id()`.
  - `id(args)` &mapsto; `static const id = Name._$(i, "id", args);`
  - `id<types>(args)` &mapsto; `static const id = Name<types>._$(i, "id", args);`
  - `id.named(args)` &mapsto; `static const id = Name._$named(i, "id", args);`
  - `id<types>.named(args)` &mapsto; `static const id = Name<types>._$named(i, "id", args);`

  We expect type inference to be applied to the resulting declarations and generic constructor invocations where necessary,
  and the type of the constant variable is inferred from the static type of the constant object creation expression.

- A static constant named `values` is added as `static const List<Name> values = [id1, …, idn];`
  where `id1`…`idn` are the names of the enum entries of the `enum` declaration in source/index order.
  If `Name` is generic, the `List<Name>` instantiates it to bounds as usual.

If the resulting class would have any naming conflicts, or other compile-time errors, the `enum` declaration is invalid and a compile-time error occurs. Such errors include, but are not limited to:

- Declaring or inheriting (from `Enum` or from a declared mixin or interface) any member with the same basename as an enum value, 
  or the name `values`, or declaring an enum value with name `values`. _(The introduced static declarations would have a conflict.)_

- Inheriting a member signature with basename `index`, from a mixin or interface, which is not validly overridden by an implementation with signature 
  `int get index;`. _(The introduced `index` getter would not be a valid implementation of that interface signature.)_

- Inheriting a member signature with basename `toString`, but no implementation, 
  from a mixin or interface, which is not validly overridden by an implementation with signature 
  `String toString();`. _(The introduced `toString()` method would not be a valid implementation of that interface signature.)_

- Declaring any members or enum values with basename `index` or `values`.

- Declaring a type parameter on the `enum` which does not have a valid well-bounded or super-bounded instantiate-to-bounds result 
  (because the introduced `static const List<EnumName> values` requires a valid instantiate-to-bounds result which is at least super-bounded).

- The type parameters of the enum not having a well-bounded instantiate-to-bounds result *and* an enum element omitting the type arguments
  and not having arguments which valid type arguments can be inferred from (because an implicit `EnumName._$(0, "foo", unrelatedArgs)` 
  constructor invocation requires an well-bound inferred type arguments for a generic `EnumName` enum).

- Declaring an enum value where the desugared constructor invocation is not a valid `const` generative constructor invocation.

- Referring to a generative constructor of the `enum` exceit in a redirecting generative constructor or the enum values,
  _(because the constructor is renamed to a fresh name, and only those two occurrences use the new name)._

Otherwise the `enum` declaration has an interface and behavior which is equivalent to that class declaration, which we’ll refer to as the *corresponding class declaration* of the `enum` declaration. *(We don’t require the implementation to be that class declaration, there might be other helper classes involved in the implementation, and different private members, but the publicly visible interface and behavior should match.)*

That is, if the corresponding class declaration of an `enum` declaration is valid, the `enum` declaration introduces the same *public interface* and *type* that the corresponding class declaration would introduce if declared in the same location. _There are, however, restrictions on how that class and interface can be used, listed in the next section._

This `enum` declaration above is therefore defined to behave equivalently to the corresponding class declaration:

```dart
class Name<T extends Object?> extends Enum with Mixin1, Mixin2 
    implements Interface1, Interface2 {
  static const id1 = Name<int>._$(0, "id1", args1);
  static const id2 = Name<String>._$(1, "id2", args2);
  static const id3 = Name<bool>._$(2, "id3", args3);
  static const List<Name> values = [id1, id2, id3];

  final int index;
  final String _$name;

  Name._$(this.index, this._$name, params) : initList;

  memberDeclarations*

  String toString() => "Name.${_$name}"; // Unless defined by memberDeclarations.
}
```

Further, the `EnumName` extension in `dart:core` will extract the `_$name` value from any enum value.

### Implementing `Enum` and enum types

It’s currently a compile-time error for a class to implement, extend or mix-in the `Enum` class.

Because we want to allow interfaces and mixins that are intended to be applied to `enum` declarations, and therefore to assume `Enum` to be a superclass, we loosen that restriction to:

- It’s a compile-time error if a *non-abstract* class has `Enum` as a superinterface unless it is the corresponding class declaration of an `enum` declaration.

- It is a compile-time error if a class implements, extends or mixes-in the class or interface introduced by an `enum` declaration.

Those restrictions allows abstract classes (interfaces) which implements `Enum` in order to have the `int index;` getter member available, and it allows `mixin` declarations to use `Enum` as an `on` type because `mixin` declarations cannot be instantiated directly.

This restriction still ensure  `enum` values are the only object instances which implements `Enum`, while making it valid to declare `abstract class MyInterface implements Enum` and `mixin MyMixin on Enum` for interfaces and mixins intended to be used in declaring `enum` classes.

## Formatting

The recommended formatting of an `enum` declaration is to format the header (before the first `{`) just like a class declaration. Then, if the enum entries have arguments (if they are anything but single identifiers), then put each entry on a line by its own. If there is no trailing comma, put the semicolon after the last entry. If there is a trailing comma, put the semicolon on the next line, by itself. Then have an empty line before the member declarations, which are formatted just like they would be in a class declaration.

If the enum entries have no arguments, they can be listed on one line where it fits, like they are today.

## Summary

We let `enum` declarations be much more like classes, just classes with a fixed number of known constant instances. We allow the class to apply mixins (applicable to a supertype of `Enum`) and implement interfaces. We allow any static or instance member declaration, and any generative `const` constructor declaration (so instance variables must be final, including those added by mixins, otherwise the mixin application constructor forwarders to the superclass `const Enum()` constructor won’t be `const`).

The enum values can call the declared constructors, or the default unnamed zero-argument `const` constructor which is added if no other constructor is declared. The syntax looks like a constructor invocation except that the enum value name replaces the class name. If no type arguments or value arguments are needed, and the constructor invoked is unnamed, the enum value can still be a plain identifier.

Enum instances are objects like any other object, and with this change they can implement interfaces and inherit members from mixins. The main difference between an `enum` declaration and a hand-written “equivalent class” using the enum pattern is that:

- The `enum` types implement `Enum`. The `Enum` type is otherwise sealed against instantiation, so no other objects than enum entries can implement it.
- The `enum` types themselves are completely sealed. No other class can implement an `enum` type.

- Because of that, `enum` types support exhaustiveness checking in `switch` cases in the language _(meaning that flow-control can see that an exhaustive switch over enum values cannot pass through without executing at least one `case`, which can then affect variable promotion)_.
- The `EnumName.name` extension member works on `enum` values.

If the *restrictions* (the type is sealed, there is only a finite, enumerable number of instances, and the class  implements `Enum`, so it must have an `int index` getter), are acceptable, there should no longer be any reason to *not* make your enum class a language-based `enum`.

## Examples:

### Plain, existing syntax

```dart
enum Plain {
  foo, bar, baz
}
```

has corresponding class declaration:

```dart
class Plain extends Enum {
  static const Plain foo = Plain._$(0, "foo");
  static const Plain bar = Plain._$(1, "bar");
  static const Plain baz = Plain._$(2, "baz");
  static const List<Plain> values = [foo, bar, baz];

  final int index;
  final String _$name;

  const Plain._$(this.index, this._$name) : super._();

  String toString() => "Plain.${_$name}";
}
```

### Complex, one with everything

```dart
mixin EnumComparable<T extends Enum> on Enum implements Comparable<T> {
  int compareTo(T other) => this.index - other.index;
}

// With type parameter, mixin and interface.
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

has corresponding class declaration:

```dart
class Complex<T extends Pattern> extends Enum with EnumComparable<Complex>
    implements Pattern {
  static const whitespace =
      Complex<RegExp>._$(0, "whitespace", r"\s+", RegExp.new);
  static const alphanum =
      Complex<RegExp>._$captured(1, "alphanum", r"\w+", RegExp.new);
  static const anychar = Complex<Glob>._$(2, "anychar", "?", Glob.new);
  static const List<Complex> values = [whitespace, alphanum, anychar];

  static final List<Pattern?> _patterns = List<Pattern?>.filled(3, null);

  final int index;
  final String _$name;
  final String _patternSource;
  final T Function(String) _factory;

  const Complex._$(this.index, this._$name, String pattern, T Function(String) factory)
      : _patternSource = pattern, _factory = factory, super._();

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
  const MySingleton._$(this.index, this._$name, ...) : ..., super._();
  // Normal class declarations.
  // toString if needed.
}
```

There is a chance that people will start using `enum` declarations to declare singleton classes. It has a little overhead, but it’s finite (and the `values` getter can likely be tree-shaken).

## Implementation

The existing enums are implemented as extending a private `_Enum` class which holds the `final int index;` declaration and a `final String _name;` declaration (used by the the `EnumName.name` getter), and both fields are initialized by a constructor.

Since this proposal allows mixin applications which can, potentially, shadow a superclass `index` getter, we likely need to change some parts of the implementation.

- Make the actual implementation class for an `enum` extend `_Enum` instead of `Enum`, and forward the index and name values to the superclass constructor.
- Not have `index` and `_$name` instance variables in the implementation class.

- Make the `final int index;` field in `_Enum` be private (`final int _index;`).
- Add an `int get index => this.<dart:core::_index>;` to the actual implementation class for the `enum` to dodge overrides of `index` in mixins. (The `<dart:core::_index>` syntax represents accessing the library private `_index` member from `dart:core` through compiler magic.)

That makes the actual implementation of the `Plain` enum above likely to be something like:

```dart
class Plain extends _Enum {
  static const Plain foo = Plain._$(0, "foo");
  static const Plain bar = Plain._$(1, "bar");
  static const Plain baz = Plain._$(2, "baz");
  static const List<Plain> values = [foo, bar, baz];

  const Plain._$(int _$index, String _$name) : super(_$index, _$name);

  int get index => this.<dart:core::_index>;

  String toString() => "Plain.${<date:core::_name>}";
}
```

This should allow a reasonable implementation which still supports `EnumName`. We currently implement the `toString` using such compiler-magic to access the `_name` field of `_Enum`, so all we need is to add a similar `index` getter to each enum class.

## Versions

1.0: Initial version.
1.1, 2021-10-11: Add missing `const` to some constructor declarations.
1.2, 2021-10-25: Tweak some wordings and ambiguities.
1.3, 2021-10-27: Add examples of potential errors in the corresponding class declaration.
1.4, 2021-10-28: Say that it's an error to refer to generative constructors, and make the `Enum` constructor public.
