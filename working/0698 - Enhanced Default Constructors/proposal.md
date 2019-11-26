# Dart Enhanced Default Constructors

Author: [lrn@google.com](mailto:lrn@google.com)
Version: 0.2 (draft)

## Background

See issue #698 for the feature discussion.

### Verbosity

Creating a class with a simple constructor is fairly short because of Dart's initializing formals, but it's still entirely boiler-plate code that repeats names that already exist elsewhere in the class declaration. You need to repeat the name at least once. Forwarding constructor parameters is even more verbose, especially for named parameters.

```dart
class Complex {
	final double real, imaginary;
  Complex({this.real, this.imaginary});
}
class ColorComplex extends Complex {
  final Color color;
  ColorComplex({double real, double imaginary, this.color})
      : super(real: real, imaginary: imaginary);
      // "real"/"imaginary" written three times.
}
```

It would be nice to have a simpler way to handle simple cases, without making anything harder for complex cases.

### Default Constructors

Dart adds a *default constructor* to any class which doesn't declare any constructors. The default constructor is an unnamed generative constructor which is equivalent to `ClassName() : super();`.

If that constructor would not be valid for the class, for example if the class declares a final instance variable with no initializer, or if the superclass does not have an unnamed generative constructor with no required parameters, then it's a compile-time error.

In most situations, there is no difference between declaring the constructor above explicitly and getting the default constructor. The only distinction is that you can extract a mixin from a class if it has `Object` as superclass and it declares no non-factory constructor.

### Mixin Application Forwarding Constructors

A *mixin application* receives corresponding forwarding constructors for all accessible generative constructors of the superclass. The forwarding constructor has the same basename (identifer after the class name for named constructors, empty for the unnamed constructor), the same parameter signature as the superclass constructor, including default values for optional parameters, and an initializer list with a `super`-invocation to the corresponding superclass constructor which forwards each parameter as an argument to the corresponding superclass constructor parameter. The forwarding constructor is `const` if the superclass constructor is `const` *and* the mixin declares no instance variables.

Since a mixin application class cannot contain static members, there is no risk of the introducing a conflict between a constructor name and a static member. 

### Goal

We want to allow classes with fields that can be constructed without having to write constructors. That is, we want *initializing default constructors* which takes parameters class fields (with some exceptions) and initializes the fields.

We want those constructors to be independent of the order of the fields in the class, so the constructor parameters will be *named*.

We want this feature to compose well, so if a superclass gets an initializing default constructor, then a subclass should also be able to have one, which means that the subclass constructor needs to forward parameters to the superclass (at least unless there is a naming conflict).

If possible, it would be nice to be able to forward other constructors as well, so that mixin applications are not the only way to forward constructors automatically when that's all you need.

If possible, it should be easy to migrate to and from using the feature. Having to rewrite significant parts of your class in order to move from default constructors to custom constructors is annoying. We will try to limit the amount of code you need to write when going from the simple case to a more complex case.

### Examples

The following class declarations could be made valid:

```dart
class Person {
  final String firstName;
  final String lastName;
  final int age;
}
class Fireman extends Person {
  final int yearsOfService;
}
```

You could then, perhaps, instantiate a `Fireman` as:

```dart
Fireman(firstName: "John", lastName: "Doe", age: 37, yearsOfService: 12)
```

It would automatically introduce an *initializing default constructor* which can initialize all the fields.

(This is still verbose, because of the named arguments, but it's consistent and easy to write.)

Maybe you can extend classes with non-default constructors too and forward implicitly to those as well:

```dart
class ColorBox extends Rectangle<int> {
  final Color color;
}
  ... ColorBox(0, 10, 0, 10, color: Color.red) ...
```

This will require some constraints on the superclass constructors, though. For example, we can't have both optional positional parameters and named parameters on the same class.

It is still a very useful feature when you simply add methods to a class, and no new fields:

```dart
class MyRectangle extends Rectangle<int> {
  MyRectangle affineTransform(int a, int b, int c, int d) =>
      MyRectangle(a * left + b * top, c * left + d * top,
                  a * right + b * bottom, c * right + d * bottom);
}
```

Here you could implicitly "inherit" all constructors from the superclass without having to rewrite them.

## Proposal

We will introduce *initializing* and *forwarding* constructors, and have *default constructors* be both.

### Initializing Constructor

An initializing constructor for a class *C* is a generative constructor with *implicitly* introduced named initializing formals without default values for each instance variable declared in *C* which is not declared `late` and which does not have an initializer expression. The named parameter is required if the instance variable's type is potentially non-nullable. In NNBD-legacy code, the parameter is required if the instance variable is final.

A constructor can be made initializing by writing `default` as a modifier before the constructor, after any `const` modifier.

Such a constructor must not declare any optional positional parameters. It may declare other parameters, and then an initializing formal is not introduced for an instance variable when the constructor declares another parameter with the same name. This allows users to explicitly initialize some fields and still have default initialization for the remaining fields.

#### Example

The class `Person` above could be given an initializing constructor by declaring a constructor of the form:

```dart
  default Person();
```

This would expand to the constructor:

```dart
  Person({required this.firstName, required this.lastName, required this.age}) : super();
```

An initializing constructor of the form:

```dart
  default Person(this.lastName);
```

would expand to;

```dart
  Person(this.lastName, {required this.firstName, required this.age}) : super()

```

because the explicitly supplied `lastName` parameter takes precedence over inserting an initializing formal parameter for that field.

### Forwarding Constructor

A forwarding constructor for a class *C* is a generative constructor with *implicitly* introduced formal parameters and a super constructor invocation forwarding those parameters to a the superclass constructor.

A forwarding constructor with no other parameters will have the same parameter signature as the superclass constructor, including default value for optional parameters, and will forward all parameters to the superclass constructor in the initializer list.

A constructor can be made forwarding by writing a reference to a super-constructor (`super` or `super.id`) in a in place of a required positional parameter in the constructor parameter list *and* omitting the super-invocation in the initializer list. 

The super-constructor entry is expanded to add a number of *forwarded parameters* to the forwarding constructor's parameter list. One positional forwarded parameter is added for each positional parameter of the referenced superconstructor, in order, at the position of the constructor reference in the forwarding constructor parameter list, and one named forwarded parameter is added for each named parameter of the superconstructor, with the following modifications:

- If the forwarding constructor is also an initializing constructor, then the field-initializing parameters from that are added to the forwarding constructor before considering forwarding.
- If the forwarding constructor declares a parameter (including initializing constructor parameters introduced above) with the same name as a required named superconstructor parameter, it is a *compile-time error*.
- If the forwarding constructor declares a parameter (including initializing constructor parameters introduced above) with the same name as an optional named superconstructor parameter, then the superconstructor parameter is ignored and no corresponding parameter is introduced in the forwarding constructor
- If the forwarding constructor declares a parameter (including initializing constructor parameters introduced above) with the same name as a positional superconstructor parameter, call it *originalName*, then, for documentation purposes, the corresponding forwarding constructor parameter uses the name *originalName_n* where *n* is a decimal integer representing for the smallest integer greater than zero which makes the name different from any parameter name declared by the forwarding constructor or by the superconstructor.
- If the forwarding constructor declares any named parameters, including if it is an initializing constructor, then all optional positional superconstructor parameters are ignored.
- If the forwarding constructor declares any positional parameters after the superconstructor reference entry, then all positional superconstructor-derived parameters are ignored.
- Otherwise the forwarded parameters are optional if they are optional in the superconstructor, and if so, they have the same default value, if any.

Then a super-invocation is added to the initializer list where each such forwarded parameter is forwarded as a corresponding superconstructor argument.

#### Example

The class `Fireman`above could be given an initializing constructor by writing:

```dart
  default Fireman(super);

```

This would expand to the constructor:

```dart
  Fireman({required this.yearsOfService, required String firstName,
           required String lastName, required int age})
      : super(firstName: firstName, lastName: lastName, age: age);

```

It's also possible to have other parameters in the parameter list, before or after the forwarded positional parameters:

```dart
class Point {
  final int x, y;
  Point(this.x, this.y);
}
class ColorPoint extends Point {
  final Color color;
  Point(this.color, super); // Expands to: Point(this.color, int x, int y) : super(x, y);
}

```

### Default Constructors

A default constructor is a constructor which is automatically inserted if a class declares *no* constructors.

Let *C* be a class declaration with name `C` and superclass *S* with name `S` 

It is a compile-time error if:

- *C* declares a private-named, non-`late`, and potentially non-nullable instance variable with no initializer expressions. 
- Or in **NNBD-legacy mode**, *C* declares a private-named and final instance variable with no initializer expression.

Otherwise, for each constructor *s* of the superclass, named `S` or `S.id`, satisfying all of the following:

- If *s* is a named constructor with name `S.id` then:
  - *s* is accessible ( `id` is not a private identifier or *S* is not declared in a different library), and
  - *C* does not declare a static member named *id*.
- The *s* constructor is a generative constructor.
- *C* does not declare an instance variable with no initializer expression and with the same basename as a required named parameter of *s*.

add a generative initializing and forwarding default constructor *c* to *C* with the corresponding name `C` or `C.id`, and the following declaration:

```dart
default C(super);

```

or

```dart
default C.id(super.id);

```

It is a *compile-time error* if there are no superclass constructors satisfying these requirements. (This is not a necessity, it's completely valid for a class to have no generative constructors, which is what currently happens if a class declares only factory constructors. We require the author to explicitly opt in to this behavior because *if* it is unintentional, it is a very hard-to-spot error.)

The constructor *c* is not  `const`. It's possible to declare a const initializing and forwarding constructor by explicitly writing:

```dart
const default C(super);

```

### Mixin Application Forwarding Constructors

The forwarding constructors introduced by mixin applications are now simply forwarding constructors.

They are not default constructors because they are not initializing. This would be a breaking change in case a mixin declares a field with the same name as a superclass constructor named parameter.

So, for mixin application, `MA = Super with Mixin`, we add a *forwarding* constructor `MA(super);` or `MA.id(super.id);` for each accessible constructor in the superclass. The constructor is declared `const` if the superclass constructor is `const` and the mixin declares no instance variables.

### Rationale

All the field initializers are named parameters. We do not want to make them positional parameters for two reasons: Primarily because it means that we have to pick an order, and alphabetical order is arbitrary, while source order makes the code unstable in the face of refactoring (and any other order is even more arbitrary). Secondarily because it makes it even harder to consistently forward to superclass constructors which also have named parameters.

In NNBD libraries, we do not make parameters corresponding to *final* instance variables required. They will be *initialized* anyway because we store the value of the optional parameter to them. We do require that *potentially non-nullable* variables are provided because we have on default values. We could require that final field values are explicitly passed as arguments, but it's very reasonable to treat being *nullable* as meaning being optional.

An instance variable in a subclass will always shadow a named parameter of the same name in a superclass constructor when both initializing and forwarding. That's why we do not let default constructors forward to superclass constructors which have a required named parameter with such a name, and make it a compile-time error for an explicitly written forwarding constructor. As usual, naming conflicts must be handled by the user when there is no good default.

Superclass constructors with optional positional parameters are hard to forward to. It would be wonderful if it was possible to have both optional positional parameters and named parameters on the same function. We ignore the optional parameters when they would occur in a constructor where they cannot be optional, either because there are also named parameters, or because there are later required parameters, like you would get for `Foo(default, this.x)`, or where they are followed by other optional parameters. The last case is to avoid adding an optional parameter to a superclass constructor from being a breaking change. The alternative would be to make the parameter required, which would also make adding an *optional* parameter to a superclass constructor a breaking change. This feature is about doing the right thing easily in simple cases. In cases with conflicts and incompatible parameter lists, it will still be necessary (or at least better) to write the constructor by hand.

You only get default constructors when you declare *no* constructors. If you want to forward ten superclass constructors, and change the eleventh just a bit, or add an eleventh factory constructor, then you have to write all of the other ten, but at least you only need to write `default Foo.bar(super.bar);` and not repeat every parameter. 

It's always possible to write exactly the same constructors manually, so this change does not introduce any new expressive power. It's always possible to move away from default constructors to explicitly written constructors (except for classes used as mixins, which are always going to be highly restricted). As such, the feature has no back-end impact, it can be implemented entirely in the front-end. Back-ends may want to tree-shake unused constructors, or unused constructors parameters, though.

## Consequences

The change is *non-breaking* for default constructors. Any existing valid class that gets a default constructor with the new specification would also get a default constructor in the existing language. It will have a superclass with an unnamed constructor accepting zero arguments, and it will have no fields requiring initialization, so it too will have an unnamed constructor accepting zero arguments. Calling that constructor with no arguments will initialize any instance variable with no initializer to  `null`  and call the superclass unnamed constructor with the same result as calling it with zero arguments. That is exactly the same behavior as currently defined for the default constructor. 

The change is non-breaking for mixin application because the semantics of forwarding constructors match the existing behavior when there are no further parameters declared.

The added features, initializing constructors, forwarding constructors and initializing and forwarding default constructors, do introduce new ways to cause errors. We have attempted to minimize such cases, but whenever there is an implicit connection between two classes, a change to one may change the other without anybody meaning to.

### Breaking Changes

A number of changes to a class or superclass can be breaking.

Anything which changes an existing valid constructor invocation to be invalid is a breaking change, as it has always been. That would include adding a non-nullable field without an initializer to a class. That would currently be a compile-time error because the field is not initialized, and with this change it becomes a compile-time error because no existing call to the constructor passes the corresponding required parameter.

Most other changes have been designed around, so they reduce the usefulness of forwarding rather than introduce new breaking changes.

Adding an optional positional parameter to a superclass constructor to a class would have been a breaking change if we allowed any positional parameter after the forwarded optional parameter in the subclass constructor because it would change the position of an existing parameter. We deliberately avoided that at the cost of adding restrictions on when we can forward optional positional parameters.

Adding a static member to a class may suppress a default constructor. If the class author is not aware of that default constructor (perhaps it was added to the superclass after the subclass was written), this can come as a surprise. It may break downstream code using the constructor, even if the author doesn't get any errors. That suggests that maybe having all the forwarding constructors by default is not a good idea anyway.

## Variants

This proposal goes about as far as possible in forwarding to superclass constructors, in part because it can then subsume mixin application constructor forwarding, and in part because it's very useful when extending classes without introducing new fields.

This means that we *can* choose to do *less* and still be useful.

We may also want to allow forwarding constructors declared on mixins, which currently do not allow constructors. That would allow a significant number of use-cases.

## Summary

Default constructors now have named initializing formal parameters for each public instance variable declared in the class, unless the variable has an initializer. The parameter is required if the variable is potentially non-nullable (it has to be when its type is potentially non-nullable).

Default constructors forward to superclass generative constructors where possible, not just to the unnamed zero-argument superclass constructor. It's not possible when the superclass constructor is not accessible, or it has a required named argument with the same name as a subclass instance variable without an initializer (the ones that initializing formals are added for). 

This works for all classes that do not declare a constructor. Mixin applications are just a special case of this, and they get the same forwarding constructors as now. In theory, all class declarations are mixin applications, sometimes just with a mixin literal, and now we treat them all the same.
