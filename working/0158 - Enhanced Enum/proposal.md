# Dart Enhanced Enums

Author: lrn@google.com<br>Version: 1.1

## Background

Dart enums are very simple, and do not support adding values, members, and
other useful features.

As a consequence, developers often add functionality next to the enum, e.g.:

```dart
enum Time { 
  hour,
  day,
  week,
}

_timeToString(Time time){
  switch (time) {
    case Time.hour:
      return "1h";
    case Time.day:
      return "1d";
    case Time.week:
      return "1w";
  }
}
```

Some use extension methods to bring these closer in scope:

```dart
extension on Time {
  String get label => const <@exhaustive Time, String> {
    hour: "1h",
    day: "1d",
    week: "1w",
  }[this];
}
```

The current proposal extends Dart enums to support adding such functionality
directly on the enum:

```dart
enum Time2 {
  hour('1h'), 
  day('1d'), 
  week('1w');
  
  final String label;
    
  const Time2(this.label);
}

main() {
  var t = Time2.day;
  print("I'll see you in ${t.label}!");
}
```

## Proposal

Allow `enum` declarations to:

- Declare static methods and variables.
- Declare instance methods.
- Declare instance *variables*.
- Allow type arguments.
- Declare an unnamed const constructor initializing those fields and type arguments.
- Allow enums to implement interfaces. 
- *Stretch Goal*: Allow enums to mix in mixins.

Syntax example:

```dart
enum MyEnum<T extends num> implements Comparable<MyEnum> {
  // Elements go first.
  // Allows trailing comma in list. 
  // Requires a `;` if followed by *anything* other than `}`.
  foo<int>("a", 1), 
  bar<num>("b", 0), 
  baz<double>("c", 2.5); // Invokes constructor.
  
  // Instance fields, must be final since constructor is `const`.
  // Won't be implicitly added, you have to write the `final`, because it reads like
  // mutable fields without it.
  final String _field;
  final T value;
  
  // One unamed constructor *only*. Can use `MyEnum.new` as alias.
  // Must be generative. Must be non-redirecting. 
  // Must be constant (can omit `const`, it's implicit.)
  const MyEnum(this._field, this.value);

  // Any instance members (barring name conflicts).
  String get field => _field;
    
  // If `toString` is not declared, you get default implementation of => "MyEnum.$name".
  // You can declare your own instead.
  String toString() => "MyEnum.$name($_field)"; // (Assumes `.name` extension getter.)
    
  // Can refer to [index] declared by [Enum].
  int compareTo(MyEnum other) => index - other.index;
    
  // Any static member (barring name conflicst).
  static MyEnum byFieldValue(String value) => values.firstWhere((e) => e._field == value);
}
```

The argument part after the enum element names is optional, omitting it is equivalent to `()`, and is allowed if the constructor can be called with zero arguments (it can have optional arguments). You can’t write type arguments and omit the argument list, it’s either *nothing* or an argument part with an argument list and optional type arguments.

It’s a compile-time error to attempt to call the constructor of an `enum` declaration from anywhere, ditto for tearing it off. (And a run-time error to try doing it through mirrors, if you can even find the constructor.)

It’s a compile-time error to extend, implement or mix in an enum type.

An `enum` declaration desugars to a _corresponding class declaration_. (Here “desugars” means “has the same behavior as”, including it being a compile-time error if the corresponding class declaration would have a compile-time error.) A name starting with `_$` represents a guaranteed fresh name.

```dart
class MyEnum<T extends num> extends Enum implements Comparable<MyEnum> {
  static const MyEnum foo = MyEnum<int>._$(0, "foo", "a", 1);
  static const MyEnum bar = MyEnum<num>._$(1, "bar", "b", 0);
  static const MyEnum baz = MyEnum<double>._$(2, "baz", "c", 2.5);

  static const List<MyEnum> values = [foo, bar, baz];
    
  final int index;
  final String _$name; // Fresh name.
    
  final String _field;
  final T value;
  
  const MyEnum._$(this.index, this._$name, this._field, this.value);
    
  // Remaining instance and static members as written.
    
  // If no `toString` was declared, add:
  String toString() => "MyEnum.${_$name}";
}
```

Default equality is still identity, `hashCode` is the identity hash. You can override those, but then you can’t use that enum’s values in const maps/sets or as `switch` cases.

We need to allow implementing interfaces, even if for no other reason than to allow `Comparable`. If we don’t allow implementing interfaces, we’ll get requests for it immediately and consistently until we do.

You use the enum element values just like you’d use instances of the corresponding class:

```dart
void somethingWithEnums<T extends Enum>(T value1, T value2) {
  if (value1 is Comparable<T>) { // Works for `MyEnum`
    if (value1.compareTo(value2)) print("Correctly ordered!"); // Printed.
  }
  print(value1); // Custom toString gives: "MyEnum.foo(a)"
}
// Prints:
// Correctly ordered!
// MyEnum.foo(a)
somethingWithEnums(MyEnum.foo, MyEnum.bar);
int x = MyEnum.foo.value + 1;    // MyEnum.foo.value is an int.
double y = MyEnum.baz.value + 1; // MyEnum.baz.value is a double.
var fields = [for (var v in MyEnum.values) v.field]; // ["a", "b", "c"].
```

### Implementing `Enum`

If an enum can implement an interface, you might also want that interface to itself implement `Enum`. One example is to allow defining extension methods on a *marker interface* on enums:

```dart
abstract class OrderedEnum implements Enum {}
extension OrderedEnumOrder<T extends OrderedEnum> on T {
  bool operator<(T other) => this.index < other.index;
  // ...
}
```

(An alternative is to add `int get index;` on the `OrderedEnum` interface, but that feels unnecessary and suggests it can be used on anything with an `index` integer, not just enums.)

So, to allow this, we *loosen* the restriction on implementing, extending or mixing-in the `Enum` class to:

> It's a compile-time error if a *non-abstract* class implements (directly or transitively) the interface `Enum` declared in `dart:core`, unless the class is declared by an  `enum` declaration.
>
> It's a compile-time error if the interface of a `mixin` declaration implements `Enum` (directly or transitively).  _(This covers the types of both the `implements` and `on` clauses of a `mixin` declaration since the mixin's own interface implements all of these.)_

This allows *abstract* classes to implement `Enum` and be used as interfaces implemented by `enum` classes.

If we choose to allow `enum` declarations to have mixin applications, we can also remove the second paragraph and allow mixins `on Enum` or implementing `Enum`. Those mixins can then *only* be applied to the superclass of an  `enum`  declaration. They can use `this.index` (but not `super.index`, because `index` is abstract in `Enum`, so it might be limited how useful such `on Enum` mixins are).

It never makes sense to implement an `enum` declared type, only the `Enum` type itself.

An abstract class implementing `Enum` should not have any non-abstract members. There is no possible way those members will ever occur on a non-abstract class, so they are unreachable.

## Stretches

### Mixins

Possibly allow:

```dart
enum MyEnum with SomeMixin, OtherMixin implements SomeInterface, OtherInterface {
  ...
}
```

which desugars to;

```dart
class MyEnum extends _Enum with SomeMixin, OtherMixin 
    implements SomeInterface, OtherInterface {
  ...
}
```

That can allow a default implementation of interfaces, like:

```dart
mixin EnumComparableByIndex<T extends Enum> on Enum implements Comparable<T> {
  int compareTo(T other) => this.index - other.index;
}
```

We do not allow *extending* a superclass because an `enum` extends `Enum` already (actually it’s because that will prevent our current `extends _Enum` implementation, we could have gotten away with just `implements Enum` since `Enum` has no instance members). We can’t do that with an `_Enum` mixin (not without serious kernel hacking, not something which can otherwise be written in Dart) because we need to initialize the `index` and `_name` fields.

I believe this could be genuinely useful and practical.

### More constructors

We could allow having more/other named constructors, and forwarding generative constructors forwarding between them.

Then you could write:

```dart
enum Point {
  origo.carthesian(0, 0),
  unitEast.polar(0, 1),
  unitNorth.polar(pi / 2, 1),
  unitWest.polar(pi, 1),
  unitSouth.polar(pi * 3 / 2, 1);
  
  final double x, y;
  Point.carthesian(this.x, this.y);
  Point.polar(th, r) : this.carthesian(sin(th) * r, cos(th) * r);
}
```

Might be useful. Might be hard to read too. Clearly speculative until we have more use cases.

(Will then only be a compile-time error to refer to an enum constructor *except* from a redirecting enum constructor, and enum elements need to be able to specify a constructor name too.)

## Grammar:

```ebnf
<enumDeclaration> ::=
  `enum` <identifier> <typeParameters>? (`with` <typeList>)? (`implements` <typeList>)? `{` 
     <enumElements> (`;` <enumMember>*)? 
  `}`

<enumElements> ::= <enumElement> (`,` <enumElements>)?
<enumElement> ::= <identifier> <argumentPart>?
```

where an `<enumMember>` is a normal class member declaration except that it’s a compile-time error if:

- A constructor is declared which is named, is not generative or is redirecting.
- The unnamed generative non-redirecting constructor is then implicitly `const` even if it’s not declared `const`.
- We define the “corresponding class declaration” for an `enum` declaration as above, and it’s a compile-time error for the `enum` declaration if there would be a compile-time error for the corresponding class declaration. That includes all name clashes.

## Versions

1.0: Initial version

1.0.1: Adds example, no functional change.

1.1: Suggests allowing interfaces to implement `Enum`.
