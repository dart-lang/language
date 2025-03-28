# Metaobjects

Author: Erik Ernst

Status: Draft

Version: 1.0

Experiment flag: metaobjects

This document specifies the metaobjects feature, which is a feature that
allows a type `T` to be mapped into one or more kinds of objects known as
_metaobjects_ for that type. The main purpose of a metaobject is to serve
as a vehicle for late-bound invocations of selected static members and/or
constructors of the type `T`, but it is also possible to use the mechanism
for other purposes.

## Introduction

The _metaobjects_ feature maps a given type `T` to an object, known as a
_metaobject_, which allows features associated with the type `T` (such as
static members and constructors) to be invoked without depending on the
exact type itself.

Current Dart only allows static members and constructors to be invoked by
denoting the exact declaration (of a class, mixin, mixin class, extension
type, extension, or enum) that contains said static member or constructor
declaration. For example, if a class `A` declares a static method `foo`
then we can call it using `A.foo(...)`, but we cannot call it using
`X.foo(...)` where `X` is a type variable, even in the case where the value
of `X` at run time is `A`.

The metaobjects feature allows this restriction to be lifted. It introduces
support for new clauses on type-introducing membered declarations (e.g.,
classes and mixins), of the form `static implements T` or
`static extends T`, where `T` is an interface type (e.g., a class).

These clauses specify superinterfaces that the metaobject class must
implement respectively extend. That is, it specifies members that we can
call on the metaobject.

Here is an example:

```dart
// Define the interface that we wish to support.
abstract class PrettyPrintable<X> {
  String prettyPrint(X x);
}

// The `static implements` clause specifies that a
// metaobject for `A` supports the given interface.
class A static implements PrettyPrintable<A> {
  final String name;
  A(this.name);
  static String prettyPrint(A a) => a.name;
}

// Ditto.
class B static implements PrettyPrintable<B> {
  final int size;
  B(this.size);
  static String foo(B b) => "B of size ${b.size}";
}

// Does not depend on `A` or `B`, but is still type safe.
String doPrettyprint<X static extends PrettyPrintable<X>>(X x) {
  return X.prettyPrint(x);
}

void main() {
  print(doPrettyprint(A("MyA"));
  print(doPrettyprint(B(42)));
}
```

The type variable `X` is evaluated to an object when it is used as the
receiver in an expression like `X.prettyPrint(x)`, that is, it works
exactly like `(X).prettyPrint(x)`. In this expression, `(X)` will evaluate
the type `X` as an expression. In current Dart this yields an instance of
type `Type` that reifies the type which is the value of `X`. With the
metaobjects feature it still evaluates to a reified type object, but it is
now an instance of a class (the metaobject class) that has the specified
superinterfaces.

When the value of `X` is `A`, this means that `(X)` is a subtype of
`PrettyPrintable<A>`, and similarly for the case where `X` is `B`.

The _static bound_ on `X` which is specified as
`static extends PrettyPrintable<X>` provides a compile-time guarantee that
the actual argument that `X` is bound to in any given invocation of
`doPrettyprint` will be a type such that when it is evaluated as an
expression, the resulting metaobject will have a type which is a subtype of
`PrettyPrintable<X>`. In particular, it has a `prettyPrint` method that has
a positional parameter of type `X`, so we can safely call it as
`X.prettyPrint(x)`.

In main, it is statically ensured that the actual type argument of the two
invocations of `doPrettyPrint` satisfy this requirement: In the first
invocation the inferred type argument is `A`, and this is OK because it is
known that `A static implements PrettyPrintable<A>`. Similarly for the
second invocation with the actual type argument `B`.

The semantics that actually makes the invocation of `prettyPrint` call the
static method of `A` respectively `B` is established by an implicitly
induced class for each class that has a `static implements` clause, known
as the _metaobject class_. The metaobject class implements all members of
the specified interface by forwarding to a static member or a constructor
of the underlying class, mixin, mixin class, or enum declaration.

For example:

```dart
class MetaobjectForA implements Type, PrettyPrintable<A> {
  const MetaobjectForA(); // Every metaobject class must be const-able.
  String prettyPrint(A a) => A.prettyPrint(a);
  bool operator ==(Object other) => ...;
  int get hashCode => ...;
}

class MetaobjectForB implements Type, PrettyPrintable<B> {
  const MetaobjectForB(); // Must be const-able.
  String prettyPrint(B b) => B.prettyPrint(b);
  bool operator ==(Object other) => ...;
  int get hashCode => ...;
}
```

These classes are implicitly induced by the compiler and analyzer. We
can't refer to them in user code because the name is a fresh identifier
such that it doesn't coincide with any name that a developer has written.

However, when a type variable like `X` above is evaluated as an expression,
the resulting metaobject will be an instance of the class which is the
metaobject class for the run-time value of `X`.

These classes implement operator `==` and the getter `hashCode`, such that
they can behave the same as objects of type `Type` do today, when they are
obtained by evaluating a type literal as an expression.

The static type of the metaobject will be the metaobject class when the
type literal which is being evaluated as an expression is a compile-time
constant type (for example, `var myMetaObject = A;`). In the case where the
type literal is a type variable `X` that has a bound of the form
`static extends I`, the metaobject has a static type which is a subtype of
`Type` and a subtype of `I`. This implies that we can use the members of
`I` on that metaobject. E.g., we can call `X.prettyPrint(x)` in the example
above.

As a special case (ensuring that this feature does not break existing
code), the result of evaluating a type literal that denotes a class, a
mixin, a mixin class, or an enum declaration that does _not_ have a
`static implements` or `static extends` clause has static type `Type`, and
it works exactly the same as today. So does the result of evaluating a type
that isn't introduced by a declaration (that is, a function type, a record
type, special types like `dynamic`, union types like `T?`  and
`FutureOr<T>`, etc.)

The previous example showed how we can use metaobjects to provide access to
static members of a set of classes (or mixins, etc.) without depending on
the exact class (mixin, etc.) declaration. This basically means that we
have made the static members _late bound_, because we're calling them via
normal instance members of the metaobject. In contrast, regular invocations
of static members and constructors are bound to a specific call target at
compile time, which means that the call site depends on that declaration.

The next example illustrates how we can use metaobjects to call
constructors in a similar way (yielding 'late-bound constructors'):

```dart
abstract class SimpleCreation<X> {
  X call();
  X named(int _);
}

class C<Y> static implements SimpleCreation<C<Y>> {
  C();
  C.named(int _): this();
}

class D static implements SimpleCreation<D> {
  factory D() = _DImpl;
  D.named(int _);
}

class _DImpl implements D {...}

X create<X static extends SimpleCreation<X>>() => X();

void main() {
  C<int> c = create();
  D d = create();
}
```

This illustrates that we can perform creation of instances of the given
type argument (denoted by `X` in the declaration of `create`), in spite of
the fact that the class `C` is generic (and the type argument `X` has the
value `C<int>`, that is, it carries the actual type argument with it), and
the constructor in `C` that we're using is the generative constructor whose
name is `C`. In contrast, the constructor that we're using in `D` is a
redirecting factory constructor.

The only requirement for a class `C` to static implement
`SimpleCreation<C>` is that it must have a declaration which can be invoked
as an invocation of the type itself (`C()`), which is exactly what we get
the ability to do when the metaobject has a `call` method (that is, we can
do `X()` when `X` denotes an object that has a `call` method).

The constructors named `C.named` and `D.named` are treated similarly except
that they are named. They can be invoked using expressions like
`X.named(42)` when `X` is a type variable which is declared with the static
bound `static extends SimpleCreation<X>`.

When a class, mixin, mixin class, or enum declaration has a
`static implements I` clause, the metaobject class for said type will have
an `implements I` clause, and it is implemented by generating forwarding
instance members for each of the members of the interface of `I`.

It is also possible to use a `static extends T` clause, in which case the
metaobject class will have an `extends T` clause. This implies that the
metaobject class can inherit behaviors from `T` (and possibly implement
others as forwarders, with members which are not implemented otherwise).

For example:

```dart
sealed class Animal {}

class Fish extends Animal static extends AnimalStatics {
  static bool get swims => true;
}

class Bird extends Animal static extends AnimalStatics {
  static bool get flies => true;
  static bool get walks => true;
}

class Mammal extends Animal static extends AnimalStatics {
  static bool get walks => true;
  static bool get swims => true;
}

abstract class AnimalStatics {
  const AnimalStatics(); // Must allow const-able subclasses.
  bool get swims => false;
  bool get flies => false;
  bool get walks => false;
}

void showCapabilities<X extends Animal static extends AnimalStatics>(X x) {
  var capabilities = [
    if (X.walks) "walk",
    if (X.swims) "swim",
    if (X.flies) "fly",
  ];
  print("$x can do the following: $capabilities");
}

void main() {
  showCapabilities(Mammal());
}
```

In this case the `static extends` feature is used to provide a default
implementation of a set of static members (`swims`, `flies`, `walks`).
The metaobject classes for the subclasses of `Animal` can declare any
subset of these static members if it wants to override their behavior, and
the rest are inherited from `AnimalStatics`.

`Mammal.walks` can be invoked according to today's rules about static
members (nothing new here). However, `Mammal.flies` can be invoked because
this means `(Mammal).flies`. In other words, even though the invocation
includes a metaobject, clients can consider `Mammal` to be a class that has
all of these static members even though only some of them are actually
declared as static members in `Mammal`. The rest are "inherited" from the
metaobject class.

In general, `static extends` offers developers greater expressive power
than `static implements` because it is possible for the metaobject to
inherit code that developers have written to do whatever they want. A
metaobject class which was induced by a `static implements` clause, on the
other hand, will only have methods whose implementation is a forwarding
invocation of a static member or constructor of the underlying type.

Here is an example where the metaobject is used to provide access to the
actual type arguments of a given object or type:

```dart
abstract class CallWithTypeParameters {
  const CallWithTypeParameters();
  int get numberOfTypeParameters;
  R callWithTypeParameter<R>(int number, R callback<X>());
}

class _EStaticHelper<X, Y> implements CallWithTypeParameters {
  const _EStaticHelper();
  int get numberOfTypeParameters => 2;
  R callWithTypeParameter<R>(int number, R callback<Z>()) {
    return switch (number) {
      1 => callback<X>(),
      2 => callback<Y>(),
      _ => throw ArgumentError("Expected 1 or 2, got $number."),
    };
  }
}

class E<X, Y> static extends _EStaticHelper<X, Y> {
  const E();
  void foo(X x, Y y) {}
}

void main() {
  final E<Object, Object> e = E<String, int>();

  // When we don't know the precise type arguments we can't call
  // `e.foo` safely. But `CallWithTypeParameters` can help!
  final Object? eType = e.runtimeType;
  eType.callWithTypeParameter(1, <X>() {
    eType.callWithTypeParameter(2, <Y>() {
      var potentialArgument1 = 'Hello';
      var potentialArgument2 = 42;
      if (potentialArgument1 is X && potentialArgument2 is Y) {
        a.foo(potentialArgument1, potentialArgument2); // Safe!
      }
    });
  });

  // If we didn't have this feature we could only do this:
  try {
    e.foo('Hello', 42); // May or may not throw.
  } catch (error) {
    // Some error recovery.
  }

  // We can also traverse the structure of a given type.
  List<Set<Object?>> createSets<X>() {
    final result = <Set<Object?>>[];
    result.add(<X>{});
    final Object metaX = X; // Enable promotions.
    if (metaX is CallWithTypeParameters) {
      final maxNumber = metaX.numberOfTypeParameters;
      for (int number = 1; number <= maxNumber; ++number) {
        metaX.callWithTypeParameter(number, <Y>() {
          result.addAll(createSets<Y>());
        });
      }
    }
  }
  
  // Returns a list containing the following sets:
  //   <E<E<E<String, int>, Symbol>, double>>{}
  //   <E<E<String, int>, Symbol>>{}
  //   <double>{}
  //   <E<String, int>>{}
  //   <Symbol>{}
  //   <String>{}
  //   <int>{}
  final sets = createSets<E<E<E<String, int>, Symbol>, double>>();
}
```

In this example, we're using it to provide a very basic kind of an
'existential open' operation. That is, we provide support for executing
code in a scope where the actual value of each type parameter can be
denoted. In the example we use this capability to test whether or not the
given arguments have the required types.

In the first part of `main` this is used to get access to the actual type
arguments of an existing object. In the last part, it is used to get access
to the type arguments of a given _type_. The first part can be expressed
today if we can add an instance member to the class, but the last part is
not expressible in current Dart.

Here is the corresponding implicitly induced metaobject class:

```dart
class MetaobjectForE<X, Y> extends _EStaticHelper<X, Y>
    implements Type {
  const MetaobjectForE();

  // All member implementations are inherited, except for the
  // support for `Type` equality. So we only have the following:
  bool operator ==(Object other) => ...;
  int get hashCode => ...;
}
```

In general, the static clauses and the regular subtype relationships are
independent. It is possible for two classes to have a subtype relationship,
and both of them may have a `static implements` or `static extends` clause,
but it is still possible for those static supertypes to be unrelated. Or
vice versa: the classes in the first example, `A` and `B`, are unrelated
classes, but they have the same static supertype.

This means that it is meaningful to have a regular bound on a type variable
as well as a static bound, because none of them is a consequence of the
other: `X extends SomeType static extends SomeOtherType`. This just means
that `X` is a subtype of `SomeType`, and a metaobject which is obtained by
evaluating `X` as an expression will be an object whose run-time type is a
subtype of `SomeOtherType`. However, even if we know that `Y extends X`,
we cannot conclude that `Y static extends SomeOtherType`.

Note that the latter could never be true: If `Y extends X` and
`X static extends SomeOtherType` would actually imply that
`Y static extends SomeOtherType` then the object which is obtained by
evaluating `Never` as an expression would have to have all types
because we can always write `X static extends C` for any class `C`,
so a metaobject for `Never` must, essentially, be an instance of
`Never`, and that _must_ be impossible (`Never` corresponds to the empty
set, so we can't promise that we can deliver an element that belongs to
this set).

In summary, this feature can be said to introduce support for late-bound
static members, late-bound constructors, a kind of inheritance of static
members, plus type related behaviors including the ones that rely on having
explicit access to the actual type arguments of the given type.

## Specification

### Syntax

The grammar is adjusted as follows. The modifications extend some
type-introducing declarations (the exception is extension types) such that
they include `<staticSuperTypes>?`. Moreover, type parameters are extended
to include the corresponding static bound.

```ebnf
<staticSupertypes> ::= // New.
    ('static' 'extends' <typeNotVoidNotFunction> 
    ('with' <typeNotVoidNotFunctionList>)?)?
    ('static' 'implements' <typeNotVoidNotFunctionList>)?

<classDeclaration> ::= // Modified.
    (<classModifiers> | <mixinClassModifiers>)
    'class' <typeWithParameters> <superclass>?
    <interfaces>? <staticSupertypes>?
    '{' (<metadata> <classMemberDeclaration>)* '}'
  | <classModifiers> 'mixin'? 'class' <mixinApplicationClass>

<mixinApplicationClass> ::= // Unchanged, included for readability
    <typeWithParameters> '=' <mixinApplication> ';'

<mixinApplication> ::= // Modified.
    <typeNotVoidNotFunction> <mixins>
    <interfaces>? <staticSupertypes>?

<mixinDeclaration> ::= // Modified.
    'base'? 'mixin' <typeWithParameters>
    ('on' <typeNotVoidNotFunctionList>)?
    <interfaces>? <staticSupertypes>?
    '{' (<metadata> <mixinMemberDeclaration>)* '}'

<enumType> ::= // Modified.
    'enum' <typeWithParameters> <mixins>?
    <interfaces>? <staticSupertypes>?
    '{' <enumEntry> (',' <enumEntry>)* (',')?
    (';' (<metadata> <classMemberDeclaration>)*)? '}'

<typeParameter> ::= // Modified.
    <metadata> <typeIdentifier>
    ('extends' <typeNotVoid>)?
    ('static' 'extends' <typeNotVoidNotFunction>)
```

### Static Analysis

A _metaobject capable_ declaration is a class, mixin, or enum declaration.

Assume that _D_ is a metaobject capable declaration which has a clause
of the form `static implements T1 .. Tk`. In this case we say that each of
`T1 .. Tk` is a direct static superinterface and a declared static
superinterface of _D_.

Assume that _D_ is a metaobject capable declaration which has a clause of
the form `static extends T with M1 .. Mk`. In this case we say that each of
`T` and `M1 .. Mk` is a declared static superinterface, and the class
denoted by `T with M1 .. Mk` is the direct static superclass of _D_.

A compile-time error occurs if a metaobject capable declaration _D_ has a
declared static superinterface that denotes a type which is not an
interface type.

A member access *(for example, a method, setter, or getter invocation such
as `r.foo()`)* whose receiver is a type variable (`X.foo()`) is treated as
the same member access where the receiver is parenthesized (`(X).foo()`).

*This implies that the member access is treated as a member access on the
result of evaluating the type literal as an expression.*

Consider a member access whose receiver is a possibly qualified identifier
that denotes a class, mixin, mixin class, or enum declaration _D_ (e.g.,
`C.foo()` or `prefix.C.foo()`). If the accessed member is not declared as a
static member or constructor in _D_ then the member access is treated as
the same member access where the receiver is parenthesized
(`(C).foo()` respectively `(prefix.C).foo()`).

*This implies that a member of the statically implemented or extended
interface which isn't shadowed by a static member or a constructor can be
invoked as if it had been a static member or a constructor of D itself. You
could say that the static member or constructor is added to D in a way that
resembles the addition of extension instance members to an object.*

A member access whose receiver is a parameterized type (e.g.,
`prefix.C<T>.foo()`) is treated as the same member access where the
receiver is parenthesized (`(prefix.C<T>).foo()`).

*This means that members in the interface of the metaobject class can be
invoked as if they were static members or constructors, but passing actual
type arguments. Thoese type arguments are available to the members of the
metaobject, so we could say that this introduces "static members that have
access to the type parameters or the enclosing class".*

#### Deriving the Metaobject Class

Assume that _D_ is a metaobject capable declaration named `C` which
declares the formal type parameters `X1 extends B1 .. Xk extends Bk` and
has static superinterfaces *(that is, it has a clause of the form 
`static implements ...` and/or a clause of the form `static extends ...`)*.

The metaobject class for _D_ is a class _M_ with a fresh name _N_. The
class _M_ has the same type parameter list as _D_, if any.

If _T_ is a declared static interface of _D_, then the interface type
denoted by _T_, with type parameters of _D_ replaced by the corresponding
type parameters of _M_, is an immediate super-interface of _M_.

The interface of the `Type` class is also a super-interface of _M_. If _T_
is a declared static superclass of _D_ then the class denoted by _T_, with
type parameters of _D_ replaced by the corresponding type parameters of
_M_, is the superclass of _M_.

The class _M_ has a constant non-redirecting generative constructor
with the name _N_. This constructor declares no formal parameters, has no
initializer list, and uses the superinitializer `super()`.

The class _M_ overrides the getter `hashCode` and the operator `==` such
that an instance of _M_ with actual type arguments `T1 .. Tk` has the same
behavior with respect to those two members as a `Type` instance that
reifies the underlying type `C<T1 .. Tk>` in current Dart.

The class _M_ also declares a forwarding implementation of each member
named `m` of the interface of _M_ for which there is a static member of `C`
whose name is `m` or a constructor whose name is `C.m`.

The derivation of forwarding members is specified in the next section.

A compile-time error occurs if the metaobject class derived from _D_ has
any compile-time errors.

*For example, it is an error on the `static implements I` or
`static extends I` clause if `I` has a member signature `String bar(int)`,
and there is a derived member whose name is `bar`, but it has signature
`int bar()`, which is not a correct override.*

*Note that with `static extends C`, it is an error if `C` does not have a
constant constructor whose name is `C`. This implies that metaobjects can
be constant. This is possible in every case when the underlying type is
non-generic, and it is possible in some cases when the underlying type
is generic. In particular, it is possible in all cases where a type literal
is used as a constant expression because all type arguments are then
constant type expressions as well.*

A compile-time error occurs if `C` does not declare a set of static members
and/or constructors such that every unimplemented member of `T` can obtain
a correctly overriding implementation by implicitly inducing a forwarding
member to a static member or constructor of `C`.

#### Deriving Metaobject Class Members

Assume that _D_ is a class declaration named `C` which declares the type
parameters `X1 extends B1 .. Xk extends Bk` and has declared static
superinterfaces `T1 .. Tn`.

The implicitly induced members of the metaobject class _M_ of _D_ are
derived from the static members of _D_ as follows:

If `static R get g ...` is a static getter of _D_ then _M_ has an instance
getter named `g` whose return type is the type denoted by `R`.
When invoked, the getter will invoke the static getter named `g` of _D_
and return the result of that invocation.

If `static set s(T id) ...` is a static setter of _D_ where `id` is an
identifier, then _M_ has an instance setter named `s=` whose parameter type
is the type denoted by `T`. When invoked, the setter will invoke the static
setter named `s=` of _D_ with the actual argument `id`.

*Note that the setter in _M_ may be covariant if it overrides a setter with
the same name in a superinterface whose parameter has the `covariant`
modifier. In this case, each invocation of this setter will give rise to
a run-time type check on the actual argument.*

*Static variable declarations are covered as setters and/or getters.*

If `static R m(parms)` is a static method of `C` where `parms` is derived
from `<formalParameterList>`, then _M_ declares an instance method named
`m` with a return type which is denoted by `R` and a formal parameter list
with the same shape and names, and type annotations denoting the same types
as the corresponding type annotation of the static method `C.m`.  For each
parameter in `C.m` that has a default value, the corresponding parameter
has the same default value in the `m` which is declared by _M_.  When
invoked, the `m` in _M_ calls `C.m` with its positional parameters in
declaration order as positional arguments, plus named arguments of the form
`id: id` for each of its named parameters.

Similarly, if `static R m<typeParms>(parms)` is a static method of `C`
where `typeParms` is derived from `<typeParameter> (',' <typeParameter>)*`
and `parms` is derived from `<formalParameterList>`, then _M_ declares an
instance method named `m` with a return type which is denoted by `R`, type
parameters with the same names and in the same order as in `typeParms` and
with bounds denoting the same type assuming that the type variables have
the same binding, and a formal parameter list with the same shape and
names, and type annotations denoting the same types as the corresponding
type annotation of the static method `C.m`.  For each parameter in `C.m`
that has a default value, the corresponding parameter has the same default
value in the `m` which is declared by _M_.  When invoked, the `m` in _M_
calls `C.m` with its type parameters in declaration order, with its
positional parameters in declaration order as positional arguments, and
with named arguments of the form `id: id` for each of its named parameters.

If `C(parms) ...` or `factory C(parms) ...` is a constructor declared by `C`
then _M_ declares an instance method named `call` with return type
`C<X1 .. Xk>` and a formal parameter list with the same shape and
names *(note that the name of `this.p` and `super.p` is `p`)*, and type
annotations denoting the same types as the corresponding type annotation of
the underlying constructor named `C` *(these type annotation in `C` may be
inferred based on the rules about initializing formals and
superparameters)*. When invoked, the `call` method returns the result of
invoking the constructor named `C` with actual type arguments `X1 .. Xk`
and values arguments corresponding to the parameter declarations.

Similarly, if `C.name(parms) ...` or `factory C.name(parms) ...` is a
constructor declared by `C` then _M_ declares an instance method named
`name` with return type `C<X1 .. Xk>` and a formal parameter list with the
same shape and names, and type annotations denoting the same types as the
corresponding type annotation of the underlying constructor named `C`.
When invoked, the `name` method returns the result of invoking the
constructor named `C` with actual type arguments `X1 .. Xk` and value
arguments corresponding to the parameter declarations.

### Dynamic Semantics

It is allowed, but not required, for every metaobject to be constant, if
possible. With respect to canonicalization of metaobjects, the same rules
apply as the ones that specify canonicalization of reified type objects in
current Dart.

Assume that `o` is an object whose run-time type is `C<T1 .. Tk>`. Assume
that `C` has static superinterfaces. In this case, the implementation of
the getter `runtimeType` in `Object` with the receiver `o` returns an
instance of the metaobject class for `C` with the same type arguments 
`T1 .. Tk`.

*For example, `C<int, String>().runtimeType` returns `MetaC<int, String>()`
(or a canonicalized object obtained from such an instance creation) if `C`
has the clause `static implements SomeInterface` and `MetaC` is the
implicitly induced metaobject class for `C`.*

In the case where a type `T` is introduced by a declaration that has a
static superinterface, the step whereby this type is evaluated as an
expression yields the corresponding metaobject, that is, an instance of the
metaobject class for `T`, passing the same actual type arguments as the
ones which are part of `T`.

*For example, if we are evaluating a type parameter `X` as an expression,
and the value of `X` is a type `C<S1, S2>` that has a metaobject class
`MetaC` then the result will be an instance of `MetaC<S1, S2>`.*

The metaobject has standard semantics, everything follows the normal rules
of Dart based on the metaobject class declaration.

### Changelog

1.0 - Mar 28, 2025

* First version of this document released.
