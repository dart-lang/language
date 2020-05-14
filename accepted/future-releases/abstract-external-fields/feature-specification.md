# Abstract Fields and External Fields

Authors: lrn@google.com, eernst@google.com<br>
Version: 1.0

## Background and Motivation

Dart allows abstract instance methods, getters and setters to be declared in
classes and mixins. It allows external functions, methods, getters, setters and
constructors to be declared as top-level, static or instance declarations.

The syntax of an abstract member is simply a declaration with no body. The
syntax for an external declaration prefixes the declaration with the modifier
`external`.

There are two use-cases not supported by this:

1. Easily declaring an abstract "field" (a pair of an abstract getter and an
   abstract setter) inside an "interface" class. Currently that requires two
   declarations: `int get foo;set foo(int _);`. Users often mistakenly write
   `int foo;` which works until someone *extends* the class instead of
   implementing it. Then they get an extra field on every instance of the
   class.
2. Easily declaring an external "field". This has come up in `dart:ffi` where
   users write Dart classes as a way to describe native memory layout. All
   instances of the interface will be backed by native (external)
   code. Currently `dart:ffi` users simply declare the field as `int foo;`.

Using a non-abstract field declaration has "worked" for both situations until
Null Safety. It's not perfect, but it isn't *wrong*.

With Null Safety that approach no longer works. Declaring a field as `int foo;`
means that it must be initialized by a constructor since non-nullable fields
cannot be left uninitialized.

So, to provide a migration path for these uses, preferably a *better* one than
the current pre-Null Safety state, we introduce *abstract and external field
declarations*.

## Proposal

An instance variable can be declared abstract by prefixing it with the reserved
word `abstract`.

Currently variable declarations inside a class can have the "modifiers":

* `static` &mdash; makes the variable a class variable instead of an instance variable.
* `const` &mdash; makes the variable a compile-time constant.
* `covariant`&mdash; makes the implicit setter's parameter covariant.
* `late` &mdash; makes the variable "late initialized", allowing it to stay uninitialized after creation.
* `final` &mdash; makes there be no setter, unless the variable is late and has no initializer.
* `var` &mdash; makes the variable non-final.
* a type &mdash; the type of the variable.
* an initializer expression &mdash; initializes the variable to a specific value on creation or first read.

Not all combinations are allowed.

A `var` cannot be combined with `final` or a type.

The `final` and `covariant` are usually mutually exclusive, because `covariant`
modifies a setter and `final` prevents a setter from existing (unless the
variable is `late` and has no initializer).

The `covariant` modifier only applies to instance members, so it's incompatible
with `static`.

A `const` variable must be `static`, non-`late`, non-`final` (but implicitly
counts as final) and must have an initializer.

If the modifiers occur, they must occur in the order listed here.

To this we add the modifiers `abstract` and `external`, making the possible
modifiers:

* `external`
* `static`
* `const`
* `abstract`
* `covariant`
* `late`
* `final`
* `var`
* a type.

* initializer expression.

### Abstract Fields

An abstract instance variable is an instance variable with the `abstract`
modifier. That means a non-static variable declared inside a class or mixin
declaration.

It *must not* be `external`, `static` or `const`, so the declaration starts with
`abstract`. It must not be `late` or have an initializer expression.

That makes it a non-external instance variable with no initializer and not
`late`, which means that it can be represented by an abstract getter and, if not
`final`, an abstract setter.

Being `late` or `external` or having an initializer are *implementation*
details. An abstract variable (getter/setter) declaration must not have any
such. It can be `covariant` if it's not `final`.

The abstract instance variable declaration with type *T* means exactly the same
as an abstract getter declaration with the same name and return type *T* , and,
if not `final`, an abstract setter declaration with the same name and parameter
type *T*. As such, the abstract instance variable introduces only members into
the class interface, there is no implementation.

Examples:

```dart
abstract int x; &mapsto; int get x; set x(int x);
abstract final int x; &mapsto; int get x;
abstract covariant int x; &mapsto; int get x; set x(covariant int x);
abstract var x; &mapsto; get x; set x(x); // May inherit types.

```

A declaration of `abstract var x;` or `abstract final x;`, with no declared type, may inherit types from the super-interfaces of the class.

As a special rule for `abstract var x`, If the super-interfaces of the class has only a getter or only a setter, then that type is inherited by the abstract variable declaration and is used for both the implicit getter and setter.

Any metadata on the abstract instance variable declaration applies to both the setter and the getter.

### External Fields

An external field is a variable declaration starting with `external`.

An external variable declaration cannot be `const`, `abstract` or `late`, or
have an initializer expression. All of these are implementation choices (or
documented lack of it, for `abstract`), and external fields are considered
implemented externally, so all implementation details must be kept out of the
Dart declaration.

Both top-level and class-level variable declarations can be `external` and
class-level declarations can be `static`. It can be `covariant` only if it's an
instance variable (not static, not top-level). Local variables cannot be
external.

An external variable declaration is completely equivalent to an external getter
declaration and, if not `final`, an external setter declaration, both with the
same type and name.

This means that external instance variables need not (and must not) be
initialized by constructors. They are treated exactly as an instance
getter/setter pair for all static analysis purposes. The implementation will be
provided by the run-time system somehow.

A instance variable declaration of `external var x;` or `external final x;`,
with no declared type, may inherit types from the super-interfaces of the
class.

As a special rule for `external var x`, If the super-interfaces of the class has
only a getter or only a setter, then that type is inherited by the abstract
variable declaration and is used for both the implicit getter and setter.

Any metadata on the abstract instance variable declaration applies to both the
setter and the getter.

## Summary

We allow `abstract` to prefix an instance variable declaration which is not
`late` and has no initializer.

We allow `external` to prefix a top-level, static or instance variable
declaration which is not `abstract`, `const` or `late`, and has no initializer.

Both are equivalent to an abstract, respectively external, getter and (unless
`final`) setter declaration which has the same name, type (as return or
parameter type), and metadata.
