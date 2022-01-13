# Dart Enhanced Enum Classes

Author: lrn@google.com<br>Version: 1.5<br>Tracking issue [#158](https://github.com/dart-lang/language/issues/158)

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

The `;` after the identifier list is optional if there is nothing else in the declaration (for backwards compatibility), and required if there is any member declaration after it. The identifier list may have a trailing comma in either case (like now).

The superclass of the mixin applications is the `Enum` class (which has a concrete `index` getter and otherwise only the members of `Object`, so the only valid `super` invocations on that superclass are those valid on `Object` and `super.index`).

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

It is a **compile-time error** if the enum declaration contains any generative constructor which is not `const`.

_We_ could _allow omitting the `const` on constructors, since it’s required, so we could just assume it’s always there. That’s a convenience we can also add at any later point. For now we require the `const`._

It is a **compile-time error** if the initializer list of a non-redirecting generative constructor includes a `super` constructor invocation.

_We will introduce the necessary super-invocation ourselves as an implementation detail. From the user’s perspective, they extend `Enum` which has no public constructors. We could allow `super()`, which would then be a constructor of `Enum`, but it's simpler to just disallow super invocations entirely._

It is a **compile-time error** to refer to a declared or default generative constructor of an `enum` declaration in any way, other than:
* As the target of a redirecting generative constructor of the same `enum`, or
* Implicitly in the enum value declarations of the same `enum`.

_No-one is allowed to invoke a generative constructor and create another instance of the `enum`. 
That also means that a redirecting *factory* constructor cannot redirect to a generative constructor of an `enum`,
and therefore no factory constructor of an `enum` declaration can be `const`, because a `const` factory constructor 
must redirect to a generative constructor._

## Semantics

The `Enum` class behaves as if it was declared as:

```dart
class Enum {
  // No default constructor.
  external int get index;
  external String toString();
}
```

We intend to (at least pretend to) let `enum` classes extend `Enum`, and let mixins and members access the default `index` and `toString()` through `super.`. _(In practice, we may use a different class implementing `Enum` as the superclass, but for checking the validity of `super.index`/`super.toString()`, we analyze against `Enum` itself, so it must have non-abstract implementations.)_

This all makes it look as if `Enum` would be a valid superclass for the mixin applications and methods of the enhanced `enum` class.

The semantics of such an enum declaration, *E*, is defined as introducing a (semantic) *class*, *C*, just like a similar `class` declaration.

* **Name**: The name of the class *C* and its implicit interface is the name of the `enum` declaration.

* **Superclass**: The superclass of *C* is an implementation-specific built-in class *`EnumImpl`*, with the mixins declared by *E* applied. _(The `EnumImpl` class may be the `Enum` class itself or it may be another class which extends or implements `Enum`, but as seen from a non-platform library the interface of *`EnumImpl`* is the same as that of `Enum`, and its methods work as specified for `Enum` )_

  * If *E* is declared as `enum Name with Mixin1, Mixin2 …` then the superclass of *C* is the mixin application <Code>*EnumImpl* with Mixin1, Mixin2</code>.

  It’s a **compile-time error** if such a mixin application introduces any instance variables. _We need to be able to call an implementation specific superclass `const` constructor of `Enum`, and a mixin application of a mixin with a field does not make its forwarding constructor `const`. Currently that’s the only restriction, but if we add further restrictions on mixin applications having `const` forwarding constructors, those should also apply here._

* **Superinterfaces**: The immediate superinterfaces of *C* are the interface of the superclass and the interfaces declared by *E*.
  
  * If `E` is declared as `enum Name with Mixin1, Mixin2 implements Type1, Type2 { … }` then the immediate superinterfaces of *C* are the interfaces of `Name with Mixin1, Mixin2`, `Type1` and `Type2`.

- **Declared members**: For each member declaration of the `enum` declaration *E*, the same member is added to the class *C*. This includes constructors (which must be `const` generative or non-`const` factory constructors.)

- **Default constructor**: If no generative constructors were declared, and no unnamed factory constructor was added,
  a default generative constructor is added:

  ```dart
  const Name();
  ```
  
  _(This differs from the default constructor of a normal `class` declaration by being constant.)_
  
- **Enum values**: For each `<enumEntry>` with name `id` and index *i* in the comma-separated list of enum entries, a constant value is created, and a static constant variable named `id` is created in *C* with that value. All the constant values are associated, in some implementation dependent way, with 
  
- their name `id` as a string `"id"`, 
  - their index *i* as an `int`, and
  - their `enum` class’s name as a string, `"Name"`,
  
  all of which is accessible to the `toString` and `index` member of `Enum`, and to the `EnumName.name` extension getter. The values are computed as follows.
  
  - `id` &mapsto; `Name()` (no arguments, equivalent to empty argument list)
  - `id(args)` &mapsto; `Name(args)`
  - `id<types>(args)` &mapsto; `Name<types>(args)`
  - `id.named(args)` &mapsto; `Name._$named(args)`
  - `id<types>.named(args)` &mapsto; `Name<types>._$named(args)`
  
  where `args` are considered as occurring in a `const` context, and it’s a **compile-time error** if they are then not compile-time constants.
  
  Type inference is applied to the resulting constructor invocations, with no context type, where necessary, so omitted type arguments to a generic `enum` class are filled in by type inference, using the type of arguments, if any, and then the type of the constant variable is the static type of the constant object creation expression.
  
  The objects created here are *not canonicalized* like other constant object creations. _(In practice, the index value is considered part of the object, so no two objects will have the same state.)_
  
- **Static `values` list**: If the class does not declare or inherit a member with base-name `values`, a static constant variable named `values` is added as by the declaration  `static const List<Name> values = [id1, …, idn];`
  where `id1`…`idn` are the names of the enum entries of the `enum` declaration in source/index order.
  If `Name` is generic, the `List<Name>` instantiates `Name` to its bounds.



If the resulting class would have any naming conflicts, or other compile-time errors, the `enum` declaration is invalid and a compile-time error occurs. Such errors include, but are not limited to:

- Declaring or inheriting (from `Enum` or from a declared mixin or interface) any member with the same basename as an enum value which is not a static setter. _(The introduced static declarations would have a conflict.)_
- Declaring or mixing in a member which is not a valid override of a super-interface member declaration, including, but not limited to, the `index` and `toString` members of `Enum`.
- Declaring or inheriting an member signature with no corresponding implementation. _(For example declaring an abstract `Never get index` or `String toString([int optional])`, but not providing an implementation.)
- Declaring a type parameter on the `enum` which does not have a valid well-bounded or super-bounded instantiate-to-bounds result *and* not declaring or inheriting a member with base-name `values` _(because the then automatically introduced `static const List<EnumName> values` requires a valid instantiate-to-bounds result which is at least super-bounded, and a value declaration may require a well-bounded instantiation)_.
- The type parameters of the enum not having a well-bounded instantiate-to-bounds result *and* an enum element omitting the type arguments and not having arguments which valid type arguments can be inferred from (because an implicit `EnumName(0, "foo", unrelatedArgs)`  constructor invocation requires a well-bound inferred type arguments for a generic `EnumName` enum).
- Using a non-constant expression as argument of an enum value.
- Declaring a static member and inheriting an instance member with the same base-name.

If not invalid, the semantics denoted by the `enum` declaration is that class, which we’ll refer to as the *corresponding class* of the `enum` declaration. *(We don’t require the implementation to be exactly such a class declaration, there might be other helper classes involved in the implementation, and different private members, but the publicly visible interface and behavior should match.)*

That is, if the corresponding class of an `enum` declaration is valid, the `enum` declaration introduces the *public interface* and *type* of the corresponding class. _There are, however, restrictions on how that class and interface can be used, listed in the next section._

### Implementing `Enum` and enum types

It’s currently a compile-time error for a class to implement, extend or mix-in the `Enum` class.

Because we want to allow interfaces and mixins that are intended to be applied to `enum` declarations, and therefore to assume `Enum` to be a superclass, we loosen that restriction to:

- It’s a compile-time error if a *non-abstract* class has `Enum` as a superinterface (directly or transitively) unless it is the corresponding class of an `enum` declaration.

- It is a compile-time error if a class implements, extends or mixes-in the class or interface introduced by an `enum` declaration. _(An enum class can’t be used as a mixin since it is not a `mixin` declaration and the class has a superclass other than `Object`, but we include “mixes-in” for completeness.)_

Those restrictions allows abstract classes (interfaces) which implements `Enum` in order to have the `int index;` getter member available, and it allows `mixin` declarations to use `Enum` as an `on` type because `mixin` declarations cannot be instantiated directly.

This restriction still ensure  `enum` values are the only object instances which implements `Enum`, while making it valid to declare `abstract class MyInterface implements Enum` and `mixin MyMixin on Enum` for interfaces and mixins intended to be used in declaring `enum` classes.

## Formatting

The recommended formatting of an `enum` declaration is to format the header (before the first `{`) just like a class declaration. Then, if the enum entries have arguments (if they are anything but single identifiers), then put each entry on a line by its own. If there is no trailing comma, put the semicolon after the last entry. If there is a trailing comma, put the semicolon on the next line, by itself. Then have an empty line before the member declarations, which are formatted just like they would be in a class declaration.

If the enum entries have no arguments, they can be listed on one line where it fits, like they are today.

## Implementation

The specification here does not specify *how* the index and name of an enum is associated with the enum instances. In practice it’s possible to desugar an `enum` declaration to a `class` declaration, as long as the desugaring can access private names from other libraries (`dart:core` in particular).

The existing enums are implemented as desugaring into a class extending a private `_Enum` class which holds the `final int index;` declaration and a `final String _name;` declaration (used by the the `EnumName.name` getter), and both fields are initialized by a constructor. 

In practice, the implementation of the enhanced enums will likely be something similar.

Either first declare `Enum` as:

```dart
abstract class Enum {
  Enum._(this.index, this._name);  
  final int index;
  final String _name;
  String _$enumToString();
  String toString() => _$enumToString();
}
```

*or* retain the current `_Enum` class and make that the actual superclass of `enum` classes. Either works, I’ll use `Enum` as the superclass directly in the following.

Then desugar an `enum` declaration to an actual `class` declaration and rewrite every generative constructor of the `enum` declaration to take two extra leading positional arguments. 

The `enum` declaration:

```dart
enum LogPriority with LogPriorityMixin implements Comparable<LogPriority> {
  warning(2, "Warning"),
  error(1, "Error"),
  log.unknown("Log"),
  ;
 
  LogPriority(this.priority, this.prefix);
  LogPriority.unknown(String prefix) : this(-1, prefix);
    
  final String prefix;
  final int priorty;
  int compareTo(Log other) => priority - other.priority;
}
```

would then desugar to something like:

```dart
class LogPriority extends Enum with LogriorityMixin implements Comparable<LogPriority> {
  static const warning = LogPriority(0, "warning", 2, "Warning");
  static const error = LogPriority(1, "error", 1, "Error");
  static const log = LogPriority._$unknown(2, "log", "Log");
  
  LogPriority(int _$index, String _$name, this.priority, this.prefix) 
        : super._(_$index, _$name);
  LogPriority._$unknown(int _$index, String _$name, String prefix) : 
        : this(_$index, _$name, prefix, -1);
    
  final String prefix;
  final int priorty;
  int compareTo(Log other) => priority - other.priority;
    
  static const List<LogPriority> values = [warning, error, log];
    
  // Refers to privates in dart:core.
  String _$enumToString() => "LogPriority.${_$name}";
}
```

In practice, we may choose to have a subclass of `Enum` as the actual superclass of the `enum` class, rather than use `Enum` directly. We’ll have to make sure that it makes no difference wrt. which declarations are valid (at least outside of `dart:core`, and for `enum`s declared inside `dart:core` it’s our own responsibility to not conflict with names used by the enum implementation.)

## Summary

We let `enum` declarations be much more like the classes they are, with the only restriction now being that it’s classes with a fixed number of known constant instances. We allow the class to apply mixins (applicable to a supertype of `Enum`) and implement interfaces. We allow any static or instance member declaration, and any generative `const` constructor declaration (so instance variables must be final, including those added by mixins, otherwise the mixin application constructor forwarders to the superclass `const Enum()` constructor won’t be `const`).

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

would have a corresponding class desugaring of:

```dart
class Plain extends Enum {
  static const Plain foo = Plain(0, "foo");
  static const Plain bar = Plain(1, "bar");
  static const Plain baz = Plain(2, "baz");
  static const List<Plain> values = [foo, bar, baz];

  const Plain(int _$index, String_ $name) : super._(_$index, $_name);

  // Private names from `dart:core`.
  String _$enumToString() => "Plain.${_$name}";
}
```

### Simple but comparable

```dart
enum Ordering with EnumIndexOrdering<Ordering> {
  zero,
  few,
  many;
}

mixin EnumIndexOrdering<T extends Enum> on Enum implements Comparable<T> {
  int compareTo(T other) => this.index - other.index;
}
```

would have a  corresponding class desugaring of:

```dart
class Ordering extends Enum with EnumIndexOrdering<Ordering> {
  static const zero = Ordering(0, "zero");
  static const few = Ordering(1, "few");
  static const many = Ordering(2, "many");
  static const List<Ordering> values = [zero, few, many];
  
  // Default constructor desugared:
  Ordering(int _$index, String _$name): super._(_$index, _$name);
  
  // Private names from `dart:core`.
  String _$enumToString() => "Ordering.${_$name}";
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

would have a corresponding class desugaring of:

```dart
class Complex<T extends Pattern> extends Enum with EnumComparable<Complex>
    implements Pattern {
  static const whitespace =
      Complex<RegExp>(0, "whitespace", r"\s+", RegExp.new);
  static const alphanum =
      Complex<RegExp>._$captured(1, "alphanum", r"\w+", RegExp.new);
  static const anychar = Complex<Glob>._$(2, "anychar", "?", Glob.new);
  static const List<Complex> values = [whitespace, alphanum, anychar];

  static final List<Pattern?> _patterns = List<Pattern?>.filled(3, null);

  final String _patternSource;
  final T Function(String) _factory;

  const Complex(int _$index, String _$name, String pattern, T Function(String) factory)
      : _patternSource = pattern, _factory = factory, super._(_$index, _$name);

  factory Complex.matching(String text) {
    for (var value in values) {
      if (value.allMatches(text).isNotEmpty && value is Complex<T>) {
        return value;
      }
    }
    throw UnsupportedError("No pattern matching: $text");
  }

  const Complex._$captured(int _$index, String _$name, String regexpPattern)
      : this(_$index, _$name, "($regexpPattern)", RegExp);

  String get name => EnumName(this).name;

  Pattern get pattern => _patterns[this.index] ??= _factory(_patternSource);

  Iterable<Match> allMatches(String input, [int start = 0]) =>
      pattern.allMatches(input, start);

  Match? matchAsPrefix(String input, [int start = 0]) =>
      pattern.matchAsPrefix(input, start);

  // Private names from `dart:core`.
  String _$enumToString() => "Complex.$_name";
    
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

would have a corresponding class desugaring of:

```dart
class MySingleton extends Enum implements Whatever {
  static const MySingleton instance = MySingleton(0, "instance");
  static const List<MySingleton> values = [instance];
  const MySingleton(int _$index, String _$name, ...) : ..., super._(_$index, _$name);
  // Normal class declarations.
  
  // Private names from `dart:core`.
  String _$enumToString() => "MySingleton.${_$name}";
}
```

There is a chance that people will start using `enum` declarations to declare singleton classes. It has a little overhead, but it’s finite (and the `values` getter can likely be tree-shaken).

## Versions

1.0: Initial version.
1.1, 2021-10-11: Add missing `const` to some constructor declarations.
1.2, 2021-10-25: Tweak some wordings and ambiguities.
1.3, 2021-10-27: Add examples of potential errors in the corresponding class declaration.
1.4, 2021-10-28: Say that it's an error to refer to generative constructors, and make the `Enum` constructor public.
1.5, 2021-12-07: Say that `index` and `toString` are inherited from the superclass, `values` is omitted if it would conflict. Rephrase specification in terms of defining a semantic class, not a syntactic one.