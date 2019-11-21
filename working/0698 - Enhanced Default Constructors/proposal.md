# Dart Default Constructor Enhancement

Author: lrn@google.com
Version: 0.1 (draft)

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
      : super(real: real, imaginary: imaginary);  // "real"/"imaginary" written three times.
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

We combine the forwarding constructor feature with default constructors and automatic initialization of declared instance variables. This *unifies* default constructors and mixin application forwarding constructors *and* adds more power to the default constructor for simple classes.

We expect this to happen after non-nullable types have been added to the language, so the proposal is written in terms of that, with a few guidelines for how legacy libraries work where nullability matters.

## Proposal

Let *C* be a class declaration with name `C` and superclass *S* with name `S` and which *declares* no constructor.

It is a compile-time error if:

- *C* declares a private-named and potentially non-nullable instance variable with no initializer expressions. 
- Or in **NNBD-legacy mode**,  *C* declares a private-named and final instance variable with no initializer expression.

Otherwise, for each constructor *s* of the superclass, named `S` or `S.id`, satisfying all of the following:

1. If *s* is a named constructor with name `S.id` then:
   1.  *s* is accessible ( `id` is not a private identifier or *S* is not declared in a different library), and
   2.  *C* does not declare a static member named *id*.
2. The *s* constructor is a generative constructor.
3. *C* does not declare an instance variable with no initializer expression and with the same basename as a required named parameter of *s*.
4. Either *C* does not declare any instance variables or *s* does not have any optional positional parameters (required because we can't declare a constructor with both optional position parameters and named parameters).

add a generative default constructor *c* to *C* with the corresponding name `C` or `C.id`, the following parameters:

- For each non-private instance variable with no initializer expression declared by *C*, where `v` is the name of the instance variable, the constructor has a named initializing formal parameter `this.v` with no default value. The named parameter is *required* if the instance variable has a potentially non-nullable type.
- For each named parameter of *s*, *c* has a corresponding parameter with the same name, type, optionality and default value (if optional), unless a named initializing formal parameter with the same name was declared above (in which case the parameter of *s* must be optional per requirement 4. above).
- For each positional parameter of *s*, whether optional or not, $c$ has a corresponding positional parameter with the same position, type, optionality and default value (if optional). For documentation purposes, the parameter will have the same name as the corresponding positional parameter of *s* unless that conflicts with one of the named initializing formals added in the previous point. In that case, the name will be modified by adding a `$` and a positive decimal integer numeral with no leading zeros after the name, where the numeral represents the smallest positive (&ge; 1) integer sufficient to make the name not be the same as any of the named parameters of the constructor, not the same as the name of any later positional parameter of *s*, and not the same as any earlier positional parameter of *c*.

and with an initializer list consisting of a single `super` invocation of either `super`, if *s* is named `S`, or `super.id`, if *s* is named `S.id`, with one argument for each parameter of *c* corresponding to a parameter of *s*, forwarding the value of the *c* parameter as an argument to the corresponding *s* parameter.

The constructor *c* is `const` if *s* is `const` and *C* does not declare *any* instance variables.

It is a *compile-time error* if there are no superclass constructors satisfying the requirements. (This is not a necessity, it's completely valid for a class to have no generative constructors, which is what currently happens if a class declares only factory constructors. We require the author to explicitly opt in to this behavior because *if* it is unintentional, it is a very hard-to-spot error.)

It is a *compile-time error* to derive a mixin from a class unless its superclass is `Object`, it declares no generative constructors, and it declares no potentially non-nullable instance members without an initializer expression. (For NNBD-legacy code, it must declare no final fields without initializer expressions.)

### Examples

The following class declarations will be valid:

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

You can instantiate a `Fireman` as:

```dart
 Fireman(firstName: "John", lastName: "Doe", age: 37, yearsOfService: 12)
```

This is still verbose, because of the named arguments.

You can extend classes with non-default constructors and forward implicitly to those as well:

```dart
class ColorBox extends Rectangle<int> {
  final Color color;
}
... ColorBox(0, 10, 0, 10, color: Color.red) ...
```

This is not always as useful as it seems because it doesn't work when the superclass constructor has optional positional parameters. You cannot usefully extend `DateTime` the same way because the only constructor which doesn't have optional positional parameters is `DateTime.now`.

It is still a very useful feature when you simply add methods to a class:

```dart
class MyRectangle extends Rectangle<int> {
  MyRectangle affineTransform(int a, int b, int c, int d) => 
      MyRectangle(a * left + b * top, c * left + d * top, 
                  a * right + b * bottom, c * right + d * bottom);
}
```

Here you implicitly "inherit" all constructors from the superclass without having to rewrite them.

## Notes

All the field initializers are named parameters. We do not want to make them positional parameters for two reasons: Primarily because it means that we have to pick an order, and alphabetical order is arbitrary, while source order makes the code unstable in the face of refactoring (and any other order is even more arbitrary). Secondarily because it makes it even harder to consistently forward to superclass constructors which also have named parameters.

In NNBD libraries, we do not require that *final* instance variables are always initialized, but we do require that *potentially non-nullable* variables are. We could require that final fields are initialized, but it's very reasonable to treat being *nullable* as meaning being optional. Given that there is an initializing formal parameter for the field, it will definitely be initialized

An instance variable in a subclass will always shadow a named parameter of the same name in a superclass constructor. That's why we do not forward to superclass constructors which have a required named parameter with such a name.

Superclass constructors with optional positional parameters are hard to forward to. It would be wonderful if it was possible to have both optional positional parameters and named parameters on the same function.

Existing mixin-application class forwarding constructors are just a special case of the general constructor forwarding functionality.

We make constructors `const` only when the subclass declares no instance variables. We could allow final instance variables with no initializer expression (because then the constructor must initialize it) or with an initializer expression which is constant (because then it's valid in a `const` constructor class). The latter requirement is particularly fragile and useless. Changing the initializer expression of a variable from `final int x = a + 2;` to `final int x = a + b;` where `a` is a constant variable and  `b` is a non-constant variable with the value `2` will change the constructors of the class from constant to non-constant. Also, a final instance variable initialized to a constant value should probably just be a getter. We want to avoid accidentally making a class have constant constructors, because that may become a support burden for the author, so we only make constructors constant when the subclass is particularly simple, and where the current mixin application constructor forwarding makes the constructor constant. (It is not a *breaking* change to make more constructors constant in the future, but it is a *bad* change for library owners which intended a class to have non-constant constructors).

You only get default constructors when you write *no* constructors. If you want to forward ten superclass constructors, and change the eleventh just a bit, or add an eleventh factory constructor, then you have to write all of the other ten in full. If this is too annoying, we may be able to add brief syntax for forwarding a constructor verbatim, say `Foo.bar = super.bar`.

It's always possible to write exactly the same constructors manually, so this change does not introduce any new power. It's always possible to move away from default constructors to explicitly written constructors (except for classes used as mixins, which are always going to be highly restricted). As such, feature has no back-end impact, it can be implemented entirely in the front-end. Back-ends may want to tree-shake unused constructors, or unused constructors parameters, though.

The change is *non-breaking*. Any existing valid class that gets a default constructor with the new specification would also get a default constructor in the existing language. It will have a superclass unnamed constructor accepting zero arguments, and it will have no fields requiring initialization, so it too will have an unnamed constructor accepting zero arguments. Calling that constructor with no arguments will initialize any instance variable with no initializer to  `null`  and call the superclass unnamed constructor with the same result as calling it with zero arguments. That is exactly the same behavior as currently defined for the default constructor.

## Variants

This proposal goes about as far as possible in forwarding to superclass constructors, in part because it can then subsume mixin application constructor forwarding, and in part because it's very useful when extending classes without introducing new fields.

This means that we *can* choose to do *less* and still be useful.

We could say that we only allow forwarding to a default constructor, or to `Object()`, when the class declares any instance variable which requires initialization. That would split the classes into those with *default* initializing constructors and those with *forwarding* constructors. It would make it less complex to build the default constructors because you would only either compose named parameters of default constructors, or inherit the super-constructor signature precisely for forwarding constructors. It would also not be as powerful, for example it would not allow the `ColorBox` class example above.

We could reduce the feature even further and not do constructor forwarding at all. It's still a feature for mixin applications, but default constructors only forward to other default constructors or to `Object()`, and only have named parameters. That would not allow the `MyRectangle` example above.

## Summary

Default constructors now have named initializing formal parameters for each public instance variable declared in the class, unless the variable has an initializer. The parameter is required if the variable is potentially non-nullable (it has to be when its type is potentially non-nullable).

Default constructors forward to superclass generative constructors where possible, not just to the unnamed zero-argument superclass constructor. It's not possible when the superclass constructor is not accessible, or it has a required named argument with the same name as a subclass instance variable without an initializer (the ones that initializing formals are added for). 

The constructor is const if the superclass constructor is const and the subclass introduces no new state.

This works for all classes that do not declare a constructor. Mixin applications are just a special case of this, and they get the same forwarding constructors as now. In theory, all class declarations are mixin applications, sometimes just with a mixin literal, and now we treat them all the same.

