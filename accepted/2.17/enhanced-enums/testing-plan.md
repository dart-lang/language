# Enum Testing Plan

## Valid code

### Declaration

* *Type parameters* (equivalent to `class` or `mixin` declaration)

  1. Enum declaration can have no type parameters, or one or more type parameters.

  2. Type parameters can have bounds.
     1. Bounds can refer to enum type and other type parameters.

* *Mixins* (equivalent to `class` or `mixin` declaration with `Enum` as `Extends` class)

  1. Can mix in no mixins, or one or more mixins.

  2. Mixins can have `on` types of `Enum` or of other, earlier, mixin.

  3. Mixins can access super-members `index` and `toString` to get default implementation.
  4. Mixins can override `index` and `toString`, and the mixins implementation shadows the default implementation.
  5. Mixins cannot have instance variable (because then we won’t get a constant forwarding constructor, which we need.)

* *Interfaces* (equivalent to `class` or `mixin` declaration)

     1. Can implement no interfaces, or one or more interfaces.
     2. Those interfaces can be generic, and can accept as type arguments:
        1. literal types
        2. type variables (of the enum declaration)
        3. the enum type itself ()

  * Enum declaration can contain all kinds of class members except:

        * Non-`const` generative constructors.
        * Non-final instance variables (since all generative constructors are constant)
          * Constant factory constructors (since they must be forwarding to a constant constructor, and they cannot refer to the generative constructors)

      So, that includes:

      1. static field (final, non-final, late), method, getter, setter
      2. instance field (final non-late only), method, operator, getter, setter
      3. constructor
         1. `const` non-redirecting generative
         2. `const` redirecting generative
         3. non-redirecting factory (necessarily non-`const`)
         4. redirecting factory (necessarily non-`const`, cannot redirect to generative constructor)

* Constuctors

     * Non-redirecting generative (necessarily `const`) constructors can have
          1. initializing formals
          2. a full initializer list except the superinvocation
             1. assignments to fields, with and without `this.`
             2. asserts (evaluated at compile-time since all invocations are constant)
     * Redirecting generative (necessarily `cosnt`) constructors
          1. can redirect to
             1. Non-redirecting generative constructors.
             2. Other redirecting generative constructors.
          2. has expressions that are potentially constant.
     * If no constructor declared, a default (unnamed, zero-argument) `const` constructor is added.

* Special instance members:

       * Enum declaration can override inherited `index` and `toString` from `Enum`.
       * Can override other members of `Object`
             * Can override `operator==` and `hashCode` (but then no longer has primitive equality/hash-code)
             * If overriding `noSuchMethod`, can omit implementations for interface members.
             * The default `runtimeType` returns the `Type` object representing the `enum` declaration‘s type.
       * Can implement  `call`, and if so, the enum elements are callback.

  * The `values` static constant list variable is introduced unless the class has another `values` (base)name in scope which would conflict with the static constant declaration. That means one of:

      1. `static` (in the enum declaration itself)
         1. getter named `values`
         2. setter named `values=`
         3. method named `values`

      2. declared instance member (in the enum declaration itself)
         1. getter named `values`
         2. setter named `values=`
         3. method named `values`

      3. implicit instance member (the enum declaration implements `noSuchMethod` and has an unimplemented interface method with base name `values`)
         1. Interface member declared abstract in the enum declaration itself
            1. getter named `values`
            2. setter named `values=`
            3. method named `values`
         2. inherited from a superinterface
            1. getter named `values`
            2. setter named `values`
            3. method named `values`

      4. Constructor named <code>*EnumName*.values</code>
      5. A type parameter named `values`

      5. An enum element named `values`
      6. Enum-declaration itself is named `values`.

#### Default `index`, `toString` or `values`.

The `Enum` superclass provides implementations of `index` and `toString`, and an extension getter `name`.

* `index`
  * Elements have indices that are consecutive integers starting from zero and incrementing by one for each element, in source order.
  * The `Enum.index` getter returns this index.
* `toString`
  * The `Enum.toString` method returns the string `EnumDecl.foo` for an element with declared name `foo` in an enum named `EnumDecl`.
* `name`
  * The `EnumName.name` extension getter returns the string `foo` for an enum element

#### Enum elements

* Comma separated
  * Can have trailing comma
  * Must have trailing `;` (after a trailing comma) if there is any other member declaration.
  * Can omit `;` if nothing but enum elements declared.

* Implicit constructor invocation creates object normally for such a constructor, but with new `index` for each, so no canonicalization into the same object for different enum elements.

  1. All enum element objects are distinct.

* Type arguments

  * Can infer omitted type arguments to class in constructor invocations from arguments.
  * An enum element of `foo<Types>.name(args)` or `foo.name(args)` performs type inference as a constructor invocation <Code>*EnumName*\<Types\>.name(args)</code> or <code>*EnumName*.name(args)</code> with no context type.

* Arguments

  1. Argument expressions are, and must be, constant expressions.

  2. Arguments can refer to other enum elements, but there cannot be a cyclic dependency, just like there can’t for other constant object creation expressions.

* Are instances of the `enum` declaration’s class, possibly instantiated if the `enum` declaration is generic.

* Can have static setter with the same base-name as enum element.

#### Class hierarchy and types

* The `enum` declaration contains all the static members declared in the declaration, and the static constant members introduced by the enum element delarations, and a static constant `values` declaration if one would not cause a conflict.
  * Those static members can be accessed.

* The class introduced by the enum declaration
  * has the `Enum` class as superclass if there is no `with` clause in the declaration, or
  * has `Enum with M1, …, Mn` as superclass if the enum declaration had a `with M1, …, Mn` clause.
  * The class is not abstract (but can’t be instantiated normally because the constructors are considered inaccessible).
  * It inherits member implementations from the superclass (from mixins or from `Enum`), where not overridden,
  * and has the instance members declared in the `enum` declaration as well.
  * The enum elements are instances of this type.

* The *interface* introduced by the enum declaration has the following direct superinterfaces:
  1. Every interface in the `implements` clause
  2. The interface of the superclass (see above).
  3. It has the member signatures introduced by instance member declarations in the `enum` declaration, and the member declarations inherited from the direct superinterfaces.
     1. The signatures of locally declared members take precedence over in inherited signatures.
     2. Multiple inherited signatures for the same basename are resolved as for classes.

* The *type* introduced by the enum declaration is a subtype of:

  1. The type of the `Enum` class (and of its superclass, `Object`).

  2. The type of any interface declared with `implements`, and of their superinterfaces,

  3. The type of any mixins declared with `with`, and of their superinterfaces.
  4. Itself.

#### Extensions on `enum` types

* Are allowed.
* Can be declared `on` `Enum` or `on` an enum  type.

## Errors

### Members

* Constructors

     1. Generative constructors
        1. A non-constant generative constructor is a compile-time error, whether the constructor is used or not.

        2. A non-redirecting generative constructor

           1. must not leave any field uninitialized.

             2. must not reference itself, directly or indirectly (possibly through the enum elements).

                 ```dart
                 enum Foo {
                   foo(),
                   bar.tricky(foo);
                   baz.wrong(foo);
                 
                   final bool isFirst;
                   Foo() : isFirst = true;
                   Foo.tricky(Foo value) : isFirst = identical(value, foo);
                   Foo.wrong(Foo value) : isFirst = !identical(baz, value);  // Cycle!
                 }
                 ```

          3. No super-invocation in non-redirecting generative constructor initializer lists.

       2. No referencing generative constructors from almost anywhere, except implictly in the enum element declarations or as the target of a redirecting generative constructor.
           1. No direct invocation, no tear-off, no redirection from factory constructor.
           2. Whether directly or true a type alias.
           3. Not even inside argument lists of enum element declarations or redirecting generative constructor redirections.

     3. Factory constructors cannot be `const` - a const factory constructor must redirect to another const constructor, and they

        1. cannot refer to generative constructors, and
        2. cannot be cyclic.

  * Same errors as similar class constructs:
      * No cyclic redirecting constructors, whether factory or generative.
   * Naming conflicts. All declaration name conflicts that would affect a similar class.

  1. Any two declarations with the same base-name where the two are not a getter and a setter, and either both or neither being static.
     * Includes named constructors, where the basename is the identifier after the `.`.
  2. Any static declaration with the same base-name as an inherited instance member.
  3. Any declaration with a basename that is the same as the enum declaration’s name, as a type parameter’s name.

* If overriding `operator ==` (directly or in a mixin), enum elements can no long be used in `switch` cases.

* If overriding `operator ==` or `hashCode` (directly or in a mixin), enum elements can no longer be used as constant map keys or constant set elements.

#### Enum elements

* Must have at least one enum element. Both `enum X {;}` and `enum X {,}` are invalid.
* Each element must refer to a generative constructor.
  * Must therefore have at least one generative constructor (if no constructor is declared, a default constructor is added).
* Must not have a name which would conflict with any member or declaration of the class (the way a static constant of that name would).
  1. Static getter, setter or method with same base-name.
  2. Instance getter, setter or method with the same base-name declared.
  3. Instance getter, setter or method with the same base-name inherited (whether concrete).
  4. Named constructor, enum declaration itself or type parameter with the same base-name.

#### Class hierarchy

* Enum cannot be declared `abstract`.
* The syntax is `enum Name ...`. Not `enum class Name` or anything clever.
* Class is sealed.
    * Cannot be implemented
      * Cannot be extended (also cannot refer to the generative constructors).
        * Cannot be mixed in (never extends `Object`).
          * Cannot be used as `on` type of a `mixin` declaration. **NEED TO ADD TO SPEC.**
* Other classes can extend or implement `Enum` (not mix it in, it has a constructor)
  * But not if they are non-`abstract`.
* Mixins can use `Enum` as `on` type or interface.
* The `enum` type itself cannot be extended, implemented or mixed-in by any other class, and cannot be used as `on` type of a `mixin` declaration.
* Must have implementation for all interface members (unless overriding `noSuchMethod`).
* If multiple superinterfaces contain declarations for a name, and there is no local declaration of that name, it’s a compile-time error if a most specific signature cannot be chosen from among those superinterface signatures. (Usually only possible in a non-`abstract` class if it overrides `noSuchMethod`.)

