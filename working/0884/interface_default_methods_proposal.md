# Dart Interface Default Members

Author: lrn@google.com<br>Version: 1.0

Adding a member to a Dart interface is a breaking change. Some other class might be *implementing* that interface, and since that existing class doesn't have an implementation of the new member, the class will fail to compile.

There are other ways things can break when adding new members to an interface, like already having a different member with the same name, but lack of implementation is the one most likely to occur in practice.

One solution to that issue, currently used by both [Java 8](https://docs.oracle.com/javase/tutorial/java/IandI/defaultmethods.html) and [C# 8.0](https://devblogs.microsoft.com/dotnet/default-implementations-in-interfaces/), is *interface default methods*.

An interface default method is a method *implementation* declared on an *interface*. Any class implementing the interface, and which does not implement that member already, automatically gets the default implementation added to the class.

## Proposal

### Declaration 

Dart introduces interface *default members* by allowing *instance members* in class or mixin declarations to be prefixed with `default`.

Any non-abstract, non-`external` instance method, getter, setter or variable declaration can be prefixed with `default`. This denotes the declaration as a *default member*. 
A normal instance member would add its implementation to the class and its signature to the implicit interface of the class. An interface default method adds its *implementation* to the *interface* as well as to the class.

Inside the body of a default member, the type of `super` is `Object`, so `super`-invocations can only target members of `Object`. *(The default member may be injected into another class with a different superclass, so it cannot assume anything about the available members on the superclass.)*

An interface is said to expose a default implementation for *id* if it declares a default member with *base name* *id*. So, a setter, getter or both will count as exposing a default implementations for that name.

### Application

Default members are applied to classes which need them, as long as they do not conflict with a user-written method.

When an interface *I* exposes a default implementation for *m*, then that implementation *applies* to a class *C* if:

* *C* is non-abstract and implements *I*.
* *C* does not declare a concrete member with base-name as *m*.
* *C* does not inherit a concrete member with base-name as *m*, or 
* *C* inherits a default-member with the same base name as *m*, which is declared on a superinterface of *I*.

When a non-abstract class implements the interface exposing default member declarations, directly or transitively, *and* it does not declare or inherit a concrete member with the same base name, then the default implementation is injected into the class. *This applies even if the member name is private to a different library. You can "inherit" private default implementations.* If more than one superinterface of a single class has applicable default members with the same base name, if precisely one of the superinterfaces is a subtype of all the remaining ones, then that interface's default method applies, otherwise it's a compile-time error.

It's a compile-time error if a single default method applies to a class, and that default method's function signature does not satisfy the interface of the class. This can occur if the class implements a different interface with a more specific signature for the same name.

Injecting the default member into a class works just as for a mixin application. The member is added to the new class, but the body retains its original lexical scope. A default instance variable added to a class will add its storage location to the class. Interface default members are like implicitly applied mixins, but on a per-member basis.

### Example

```dart
// Somewhere.
class Box<T> {
  T value;
  
  Box(this.value);
  
  default T replace(T newValue) {
    var oldValue = value;
    value = newValue;
    return oldValue;
  }
}

// Somewhere else.
class ObservableBox<T> implements Box<T> {
  T _value;
  final StreamController<ChangeEvent<T>> _controller =
      StreamController.broadcast(sync: true);

  ObservableBox(T value) : _value = value;
  
  Stream<ChangeEvent<T>> get onChange => _controller.stream;
  
  T get value => _value;
  
  set value(T value) {
    var old = _value;
    if (!identical(old, value)) {
	    _value = value; 
  	  _controller.add(ChangeEvent(old, value));
    }
  }
}
```

The author of this `Box` class wanted to add the `replace` method without breaking existing classes implementing `Box`. They did so by adding the method as an interface default method. The `ObservableBox` stays valid with this change, because it automatically gets a `replace` method implementation injected.

## Potential Issues

A feature like this introduces some amount of non-locality. It means that classes declared entirely outside of a library can have members private to the library. This is not new, any extensible class or any mixin would also allow library private names to be inherited, and a private default member is clearly *intended*  to be used that way.

Adding an interface default method is not completely non-breaking. There could potentially be a class implementing the original interface, and which has already added a member with the same name and an incompatible signature. Picking descriptive names reduces the risk somehow (it's less likely to get a conflict with `addFlooToBiff` than with `add`), but breakage can happen. On the other hand. because the member is virtual, unlike static extension methods, it's actually possible to add a default method to a superclass which is deliberately compatible with an existing member of a subclass. *(Languages with overloading, like Java, are much less susceptible to such conflicts.)*

We may want to not make default methods applicable to classes with a non-trivial `noSuchMethod` method. Those classes may be mocks. The traditional way to create a mock is `class Mock implements Interface {}`, and if that class automatically received the interface default methods of `Interface`, then it becomes impossible to mock those methods because you cannot *avoid* inheriting the interface default methods.

We may want to allow invoking the interface default method explicitly, in some way, so that an implementation can fall back to the default *explicitly*. Maybe doing `super.defaultMethod()` inside a class with no superclass implementation of `defaultMethod` would instead invoke the most specific interface default method among the superinterfaces of the class (if any). That may also apply to default methods themselves, which would allow them to do `super.something()` invocations other than on methods of `Object`.

