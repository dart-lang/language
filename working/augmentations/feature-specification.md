# Augmentations

Author: rnystrom@google.com, jakemac@google.com, lrn@google.com

Version: 1.37 (see [Changelog](#Changelog) at end)

Experiment flag: augmentations

Augmentations allow splitting a declaration across multiple locations,
both within a single file and across multiple files. They can add new top-level
declarations, inject new members into classes, and provide bodies for functions.

## Motivation

Dart libraries are the unit of code reuse. When an API is too large to fit into
a single file, you can usually split it into multiple libraries and then have
one main library export the others. That works well when the functionality in
each file is made of separate top-level declarations.

However, sometimes a single declaration is too large to fit comfortably
in a file. Dart libraries and even part files are no help there. Because of
this, users have asked for something like partial classes in C# ([#252][] 71 👍,
[#678][] 18 👍). C# also supports splitting [the declaration and implementation
of methods into separate files][partial].

[#252]: https://github.com/dart-lang/language/issues/252
[#678]: https://github.com/dart-lang/language/issues/678
[partial]: https://github.com/jaredpar/csharplang/blob/partial/proposals/extending-partial-methods.md

### Generated code

Size isn't the only reason to split a library into multiple files. Code
generation is common in Dart. [AngularDart][] compiles HTML templates to Dart
files. The [freezed][] and [built_value][] packages generate Dart code to
implement immutable data structures.

[angulardart]: https://github.com/angulardart
[freezed]: https://pub.dev/packages/freezed
[built_value]: https://pub.dev/packages/built_value

In cases like this, it's important to have the hand-authored and
machine-generated code in separate files so that the code generator doesn't
inadvertently erase a user's code. AngularDart generates a separate library for
the component. The freezed and built_value packages generate part files.

Note that the relationship between the hand-authored and generated code can go
in both directions:

*   Often, a user hand-authors a skeleton declaration and then a code generator
    fills in implementation and adds capabilities to it. That's how freezed and
    built_value work.

*   Other times, a code generator produces code with default basic behavior and
    that a human author then wants to tweak or refine it. You see this sometimes
    with FFI where you a code generator provides a default API to some external
    system but where you want to layer on hand-authored code to provide a more
    natural Dart-like experience.

Having a mixture of hand-authored and generated code works well when the
generated code consists of completely separate declarations from the
hand-authored code. But if a code generator wants to, say, add a method to a
hand-authored class, or an author wants to add a method to a generated class,
then the language is of little help. This proposal addresses that limitation by
adding *augmentations*.

### Augmentation declarations

This feature introduces the modifier `augment` as the first token of many
kinds of declarations. These declarations are known as *augmentation
declarations*.

*In Dart without this feature there are no augmentation declarations. Now
that we are adding augmentation declarations we need to have a term that
denotes a declaration which is not an augmentation. That is, it is one of
the "normal" declarations that we've had all the time.*

We say that a declaration which is not an augmentation declaration is an
*introductory declaration*.

Augmentation declarations include:

*   Type augmentations, which can add new members to types, add new values to
    enums, or add to the `with` or `implements` clauses.

*   Function augmentations, which can provide a body.

These operations cannot be expressed today using only imports, exports, or
part files. Any Dart file (library file or part file) can contain
augmentation declarations. *In particular, an augmentation can augment a
declaration in the same file in which it occurs.*

An augmentation can fill in a body for a declared member that has no body, but
can't *replace* an existing body or add to it. In order to allow augmentations
to provide bodies for static methods and top-level functions, we allow
declarations of those to be "abstract" and lack a body as long as a body is
eventually provided by an augmenting declaration.

### Design principle

When designing this feature, a fundamental question is how much power to give
augmentations. Giving them more ability to change the introductory declaration
makes them more powerful and expressive. But the more an augmentation can
change, the less a reader can correctly assume from reading only the
introductory declaration. That can make code using augmentations harder to
understand and work with.

To balance those, the general principle of this feature is that augmentations
can *add new capabilities* to the declaration and *fill in implementation*, but
generally can't change any property a reader knows to be true from the
introductory declaration or any prior augmentation. In other words, if a program
would work without the augmentation being applied, it should generally still
work after the augmentation is applied. *Note that this a design principle and
not a strict guarantee.*

For example, if the introductory declaration of a function takes an `int`
parameter and returns a `String`, then any augmentation must also take an `int`
and return a `String`. That way a reader knows how to call the function and what
they'll get back without having to read the augmentations.

Likewise, if an introductory class declaration has a generative constructor,
then the reader assumes they can inherit from that class and call that as a
superclass constructor. Therefore, an augmentation of the class is prohibited
from changing the constructor to a factory.

## Syntax

The syntax changes are simple but fairly extensive and touch several parts of
the grammar so are broken out into separate sections.

### Top-level augmentations and incomplete top-level members

We allow an `augment` modifier before most top-level declarations.

Also, we allow incomplete declarations at the top level. This reuses the same
syntax used inside a class to declare abstract variables, methods, getters,
setters, and operators. For callable members, that means the body is `;`. For
variable declarations, that means using `abstract`. *Example:*

```dart
abstract int x;   // Incomplete top-level variable.
int get y;        // Incomplete top-level getter.
set z(int value); // Incomplete top-level setter.
```

The new top-level grammar is:

```
topLevelDeclaration ::= classDeclaration
  | mixinDeclaration
  | extensionTypeDeclaration
  | extensionDeclaration
  | enumType
  | typeAlias
  | 'augment'? 'external' functionSignature ';'
  | 'augment'? 'external' getterSignature ';'
  | 'augment'? 'external' setterSignature ';'
  | 'augment'? 'external' finalVarOrType identifierList ';'
  | 'augment'? 'abstract' finalVarOrType identifierList ';'
  | 'augment'? getterSignature (functionBody | ';')
  | 'augment'? setterSignature (functionBody | ';')
  | 'augment'? functionSignature (functionBody | ';')
  | 'augment'? ('final' | 'const') type? initializedIdentifierList ';'
  | 'augment'? 'late' 'final' type? initializedIdentifierList ';'
  | 'augment'? 'late'? varOrType initializedIdentifierList ';'
```

### Class-like declarations

We allow `augment` before class, extension type, and mixin declarations. *(Enums
and extensions are discussed in subsequent sections.)*

```
classDeclaration ::=
    'augment'? (classModifiers | mixinClassModifiers)
    'class' typeWithParameters superclass? interfaces?
    memberedDeclarationBody
  | classModifiers 'mixin'? 'class' mixinApplicationClass

mixinDeclaration ::=
    'base'? 'mixin' typeIdentifier typeParameters?
    ('on' typeNotVoidNotFunctionList)? interfaces? memberedDeclarationBody
  | 'augment' 'base'? 'mixin' typeIdentifier typeParameters?
    interfaces? memberedDeclarationBody

extensionTypeDeclaration ::=
    'extension' 'type' 'const'? typeIdentifier
    typeParameters? representationDeclaration interfaces?
    memberedDeclarationBody
  | 'augment' 'extension' 'type' 'const'? typeIdentifier
    typeParameters? interfaces?
    memberedDeclarationBody

memberedDeclarationBody ::= '{' memberDeclarations '}'

memberDeclarations ::= (metadata memberDeclaration)*

memberDeclaration ::= declaration
  | 'augment'? methodSignature functionBody

declaration ::=
    'augment'? 'external'? factoryConstructorSignature ';'
  | 'augment'? 'external' constantConstructorSignature ';'
  | 'augment'? 'external' constructorSignature ';'
  | 'augment'? 'external'? 'static'? getterSignature ';'
  | 'augment'? 'external'? 'static'? setterSignature ';'
  | 'augment'? 'external'? 'static'? functionSignature ';'
  | 'augment'? 'external'? operatorSignature ';'
  | 'external' ('static'? finalVarOrType | 'covariant' varOrType) identifierList ';'
  | 'augment'? 'abstract' (finalVarOrType | 'covariant' varOrType) identifierList ';'
  | 'static' 'const' type? initializedIdentifierList ';'
  | 'static' 'final' type? initializedIdentifierList ';'
  | 'static' 'late' 'final' type? initializedIdentifierList ';'
  | 'static' 'late'? varOrType initializedIdentifierList ';'
  | 'covariant' 'late' 'final' type? identifierList ';'
  | 'covariant' 'late'? varOrType initializedIdentifierList ';'
  | 'late'? 'final' type? initializedIdentifierList ';'
  | 'late'? varOrType initializedIdentifierList ';'
  | 'augment'? redirectingFactoryConstructorSignature ';'
  | 'augment'? constantConstructorSignature (redirection | initializers)? ';'
  | 'augment'? constructorSignature (redirection | initializers)? ';'
```

As with top-level declarations, we also reuse the abstract member syntax with a
`static` modifier to allow declaring incomplete static fields, methods, getters,
setters, and operators. *Example:*

```dart
class C {
  static abstract int x;   // Incomplete static variable (getter and setter).
  static int get y;        // Incomplete static getter.
  static set z(int value); // Incomplete static setter.
}
```

Note that the grammar for putting `augment` before an extension type declaration
doesn't allow also specifying a representation field. This is by design. An
extension type augmentation always inherits the representation field of the
introductory declaration and can't specify it.

Likewise, the grammar for an augmenting `mixin` declaration does not allow
specifying an `on` clause. Only the introductory declaration permits that. We
could relax this restriction if compelling use cases arise.

### Enums

For enum declarations, in addition to the `augment` modifier, we allow declaring
an enum (or augmentation of one) with no values. This is useful if the
introductory declaration wants to let the augmentation fill in all values, or if
the augmentation wants to add members but no values.

When there are no values, the enum still requires a leading `;` before the first
member to avoid ambiguity.

```
enumType ::= 'augment'? 'enum' typeIdentifier typeParameters?
    mixins? interfaces? '{' enumBody? '}'

enumBody ::= enumEntry (',' enumEntry)* (',')? (';' memberDeclarations)?
    | ';' memberDeclarations
```

*Note that an enum can also have neither values nor members and both `{}` and
`{;}` are valid.*

### Extensions

Extension declarations can be augmented:

```
extensionDeclaration ::=
    'extension' typeIdentifierNotType? typeParameters? 'on' type
    memberedDeclarationBody
  | 'augment' 'extension' typeIdentifierNotType typeParameters?
    memberedDeclarationBody
```

Note that only extensions *with names* allow a leading `augment`. Since
augmentations are matched with their introductory declaration by name, unnamed
extensions can't be augmented. *Doing so wouldn't accomplish anything anyway.
Just make two separate unnamed extensions.*

## Static semantics

### Augmentation context

Prior to this proposal, an entity like a class or function is introduced by a
single syntactic declaration. With augmentations, an entity may be composed out
of multiple declarations, the introductory one and any number of augmentations.
We define a notion of a *augmentation context* to help us talk about the
location where we need to look to collect all of the declarations that define
some entity.

* The augmentation context of a top-level declaration is the library and its
  associated tree of part files.

* The augmentation context of a member declaration in a type or extension
  declaration named *N* is the set of type declarations (introductory and
  augmenting) named *N* in the enclosing set of Dart files.

*Note that augmentation context is only defined for the kinds of declarations
that can be augmented. We don't define an augmentation context for, say, local
variable declarations, because those aren't subject to augmentation.*

### Scoping

The static and instance member namespaces for an augmented type or extension
declaration include the declarations of all members in the introductory and
augmenting declarations. Identifiers in the bodies of members are resolved
against that complete merged namespace. *In other words, augmentations are
applied before identifiers inside members are resolved.*

It is already a **compile-time error** for multiple declarations to have the
same name in the same scope. This error is checked *after* part files and
augmentations have been applied. *In other words, it's an error to declare the
same top-level name in a library and a part, the same top-level name in two
parts, the same static or instance name inside an introductory declaration and
an augmentation on that declaration, or the same static or instance name inside
two augmentations of the same declaration.*

*For example:*

```dart
// Library "main.dart":
part 'other.dart';

const name = 'top level';

class C {
  test() {
    print(name);
  }
}

main() {
  C().test();
}

// Part file "other.dart":
part of 'main.dart';

augment class C {
  String get name => 'member';
}
```

This program prints "member", not "top level". When `name` is resolved inside
`test()` it walks up to the instance member scope for `C`. Since that scope
contains the merged members of all applied augmentations, it finds the `name`
getter added by the augmentation and uses that instead of continuing and
finding the top level name.

You can visualize the namespace nesting sort of like this:

```
main.dart               : other.dart
                        :
.-----------------------------------------------.
| main.dart imports:                            |
'-----------------------------------------------'
           ^            :           ^
           |            :           |
           |            : .---------------------.
           |            : | other.dart imports: |
           |            : '---------------------'
           |            :           ^
           |            :           |
.-----------------------------------------------.
| top-level declarations:                       |
| const name                                    |
| class C                                       |
'-----------------------------------------------'
           ^            :           ^
           |            :           |
.-----------------------------------------------.
| class C instance members:                     |
| test()                                        |
| name                                          |
'-----------------------------------------------'
           ^            :           ^
           |            :           |
.---------------------. : .---------------------.
| test() body         | : | name body           |
'---------------------' : '---------------------'
```

The main library file has an import scope which is inherited by all of the part
files. Each part file then has its own import scope (which are inherited by that
part file's own further part files).

The main library and all part files share and contribute to a single top-level
declaration scope. Each type or extension declaration in there has a scope
shared across introductory and augmenting declarations of that type or
extension.

Then inside those types and extensions are scopes for the member bodies. Each
member has its own scope. When resolving an identifier inside a member, we look
in the member body, then up through the scopes whose declarations are merged
from all of the augmentations and parts, then through the import scopes which
may be different for each part file, and finally to the import scope of the main
library.

### Type annotation inheritance

An augmenting declaration may have no type annotations for a return type,
variable type, parameter type, or type parameter bound. In the last case,
that includes omitting the `extends` keyword. For a variable or parameter,
a `var` keyword may replace the type.

If the type annotation or type parameter bound is omitted in the augmenting
declaration, it is inferred to be the same as the corresponding type annotation
or type parameter bound in the declaration being augmented.

If the type annotation or type parameter bound is *not* omitted, then it's a
**compile-time error** if the type denoted by the augmenting declaration is not
the same type as the type in the corresponding declaration being augmented.

*In short, an augmenting declaration can omit type annotations, but if it
doesn't, it must repeat the type from the augmented definition.*

#### Inheriting combined getter setter signatures

An instance getter and instance setter can be augmented with an abstract
variable declaration because the latter is syntactic sugar for an abstract
getter and setter declaration. This leads to a tricky edge case where the
augmenting abstract variable may want to inherit a type but the getter and
setter it inherits from have different types:

```dart
class C {
  int get x => 1;
  set x(String value) {}

  @metadataToAdd
  augment abstract var x; // What type is inherited here?
}
```

It's a **compile-time error** if an abstract variable augments a getter and
setter that don't have a combined signature.

## Applying augmentations

An augmentation declaration *D* is a declaration marked with the built-in
identifier `augment`. We add `augment` as a built-in identifier as a language
versioned change, to avoid breaking pre-feature code.

*D* augments a declaration *I* with the same name and in the same augmentation
context as *D*. There may be multiple augmentations in the augmentation context
of *D*. More precisely, *I* is the declaration before *D* and after every other
declaration before *D*.

It's a **compile-time error** if there is no matching declaration *I*. *In other
words, it's an error to have a declaration marked `augment` with no declaration
to apply it to.*

We say that *I* is the declaration which is *augmented by* *D*.

*In other words, take all of the declarations with the same name in some
augmentation context, order them according to the "after" relation, and each
augments the result of all the prior augmentations applied to the original
declaration. The first one must not be marked `augment` and all the subsequent
ones must be.*

An augmentation declaration does not introduce a new name into the surrounding
scope. *We could say that it attaches itself to the existing name.*

### Complete and incomplete declarations

Augmentations aren't allowed to *replace* code, so they mostly add entirely new
declarations to the surrounding type. However, function and constructor
augmentations can fill in a body for an augmented declaration that is lacks one.

More precisely, a function or constructor declaration (introductory or
augmenting) is *incomplete* if all of:

*   The body syntax is `;`.

*   The function is not marked `external`. *An `external` function is considered
    to have a body, just not one that is visible as Dart code.*

*   There is no redirection, initializer list, initializing formals, or super
    parameters. *Obviously, this only applies to constructor declarations.*

If a declaration is not *incomplete* then it is *complete*.

It's a **compile-time error** if an augmentation is complete and any declaration
before it in the augmentation chain is also complete. *In other words, once a
declaration has acquired a body, no augmentation can replace it with another.*

*It is allowed to augment a complete declaration long as the augmentation itself
is incomplete. This can be useful for an augmentation to add metadata.*

*Examples:*

```dart
a() {}
augment a() {} // Error.

b();
augment b() {} // OK.

c() {}
@meta
augment c(); // OK.

d() {}
augment d(); // OK.
augment d() {} // Error.
```

*Note that the initializer list and body are not treated separately. If a
constructor declaration has an initializer list and `;` body, it is still
considered complete. Likewise, a constructor with no initializer list but a
non-`;` body is complete. Thus a constructor can't acquire an initializer
list in one declaration and a constructor body in another. For example:*

```dart
class C {
  C() : assert(true);
}

augment class C {
  augment C() { body; } // Error. C() is already complete.
}
```

### Application order

The same declaration can be augmented multiple times by separate augmentation
declarations. This occurs in the situation where an augmentation
declaration has an augmented declaration which is itself an augmentation
declaration, and so on, until an introductory declaration is reached.

In some cases (enum values, `with` clauses, etc.), the order that augmentations
are applied is user-visible, so must be specified. Within a single file, the
obvious order for applying augmentations is based on which appears first.
[Expanded part files][parts with imports] make that more complex: there may be
augmentations of the same declaration scattered across an entire tree of part
files.

[parts with imports]: ../parts-with-imports/feature-specification.md

Some terminology:

*   A syntactic declaration *occurs in* a Dart file if the declaration's source
    code occurs in that file.

*   A Dart file *includes* a part file, if the Dart file has a `part` directive
    with a URI denoting that part file.

*   A Dart file *contains* a declaration if the declaration occurs in the file
    itself or any of the part files it transitively includes.

For any two syntactic declarations *A*, and *B*:

*   If *A* and *B* occur in the same file:

    *   If *A*'s declared name is syntactically before *B*'s declared name,
        in source order, then *A* is before *B.* *This rule wouldn't work for
        unnamed extensions since there is no identifier to look at, but
        unnamed declarations can't be augmented, so this isn't a problem.*

    *   Otherwise *B* is before *A*.

*   Else if the file where *A* occurs includes the file where *B* occurs then
    *A* is before *B*.

*   Else if the file where *B* occurs includes the file where *A* occurs then
    *B* is before *A*.

    *In other words, if there is a `part` chain from the file where one
    augmentation is declared to the file where the other is, then the outer one
    comes first.*

*   Otherwise, *A* and *B* are in sibling branches of the part tree:

    *   Let *F* be the least containing file for those two files. *Find the
        nearest root file in the part subtree that contains both A and B.
        Neither A nor B will occur directly in F because if it did, then the
        previous clauses would have handled it.*

    *   If the `part` directive in *F* including the file that contains *A* is
        syntactically before the `part` directive in *F* including the file that
        contains *B* in source order, then *A* is before *B*.

    *   Otherwise *B* is before *A*.

    *In other words, augmentations in sibling branches are ordered by the `part`
    directive order in the file where the branches split off.*

We say that *B* *is after* *A* if and only if *A* *is before* *B*.

*In short, declarations are ordered by a pre-order depth-first traversal of the
file tree, visiting declarations of a file in source order, and then recursing
into `part` directives in source order.*

Augmentations are applied in least to greatest order using the *after* relation.

*For example:*

```dart
// main.dart:
part 'a.dart';
part 'b.dart';

enum E { v1 }
augment enum E { v2 }
augment enum E { v3 }

// a.dart:
augment enum E { v4 }

// b.dart:
augment enum E { v5 }
```

*The resulting enum has values `v1`, `v2`, `v3`, `v4`, and `v5`, in that order.*

### Augmenting class-like declarations

A class, enum, extension, extension type, mixin, or mixin class declaration
can be marked with an `augment` modifier:

```dart
augment class SomeClass {
  // ...
}
```

Mixin application classes can't be augmented.

A class, enum, extension type, mixin, or mixin class augmentation may
specify `extends`, `implements` and `with` clauses (when generally
supported). The types in these clauses are appended to the introductory
declarations' clauses of the same kind, and if that clause did not exist
previously, then it is added with the new types.

*Example:*

```dart
class C with M1 implements I1 {}
augment class C with M2 implements I2 {}

// Is equivalent to:
class C with M1, M2 implements I1, I2 {}
```

Instance or static members defined in the body of the augmenting type,
including enum values, are added to the instance or static namespace of the
corresponding type in the introductory declaration. *In other words, the
augmentation can add new members to an existing type.*

Instance and static members inside a class-like declaration may themselves
be augmentations. In that case, they augment the corresponding members in
the same augmentation context, according to the rules in the following
subsections.

It's a **compile-time** error if:

*   An augmentation declaration is applied to a declaration of a different kind.
    For example, augmenting a `class` with a `mixin`, an `enum` with a function,
    a method with a getter, a constructor with a static method, etc.

    The exception is that a variable declaration (introductory or augmenting) is
    treated as a getter declaration (and a setter declaration if non-final) for
    purposes of augmentation. These implicit declarations can augment and be
    augmented by other explicit getter and setter declarations. (See "Augmenting
    variables, getters, and setters" for more details.)

*   A library contains two top-level declarations with the same name, and one of
    the declarations is a class-like declaration and the other is not of the
    same kind, meaning that either one is a class, mixin, enum, extension or
    extension type declaration, and the other is not the same kind of
    declaration.

*   An augmenting class declaration has an `extends` clause and any prior
    declaration for the same class also has an `extends` clause.

*   The augmenting declaration and augmented declaration do not have all the
    same modifiers: `abstract`, `base`, `final`, `interface`, `sealed` and
    `mixin` for `class` declarations, and `base` for `mixin` declarations.

    *This is not a technical requirement, but follows our design principle that
    what is known from reading the introductory declaration will still be true
    after augmentation.*

*   The type parameters of the augmenting declaration do not match the
    augmented declarations's type parameters. This means there must be
    the same number of type parameters with the exact same type parameter
    names (same identifiers) and bounds if any (same *types*, even if they
    may not be written exactly the same in case one of the declarations
    needs to refer to a type using an import prefix).

    *Since repeating the type parameters is, by definition, redundant, this
    restriction doesn't accomplish anything semantically. It ensures that
    anyone reading the augmenting type can see the declarations of any type
    parameters that it uses in its body and avoids potential confusion with
    other top-level variables that might be in scope in the library
    augmentation.*

### Augmenting function and constructor signatures

[signature matching]: #augmenting-function-and-constructor-signatures

When augmenting a function (top level, static method, instance method, etc.) or
constructor (generative, factory, etc.) the parameter lists must be the same in
all meaningful ways. We say that an augmenting function or constructor's
signature *matches* if:

*   It has the same number of type parameters with the same type parameter names
    (same identifiers) and bounds (after type annotation inheritance), if any
    (same *types*, even if they may not be written exactly the same in case one
    of the declarations needs to refer to a type using an import prefix).

*   The return type (after type annotation inheritance) is the same as the
    augmented declaration's return type.

*   It has the same number of positional and optional parameters as the
    augmented declaration.

*   It has the same set of named parameter names as the augmented declaration.

*   For all corresponding pairs of parameters:

    *   They have the same type (after type annotation inheritance).

    *   They have the same `required` and `covariant` modifiers.

    *For constructors, we do not require parameters to match in uses of
    initializing formals or super parameters. In fact, they are implicitly
    _prohibited_ from doing so: if a constructor and its augmentation both have
    initializing formals or super parameters, they are both complete and it's an
    error to augment a complete constructor with another complete constructor.
    Instead, at most only one of the constructors can use initializing formals
    or super parameters and all other declarations for the same constructor
    must declare the corresponding parameters as regular parameters.*

*   For all positional parameters:

    *   The augmenting function's parameter name is `_`, or

    *   The augmenting function's parameter name is the same as the name of the
        corresponding positional parameter in every preceding declaration that
        doesn't have `_` as its name.

    *In other words, a declaration can ignore a positional parameter's name by
    using `_`, but all declarations in the chain that specify a name have to
    agree on it.*

    ```dart
    f1(int _) {}
    augment f1(int x) {} // OK.
    augment f1(int _) {} // OK.
    augment f1(int y) {} // Error, can't change name.
    augment f1(int _) {} // OK.
    ```

    *Note that this is a transitive property.*

    *If an augmentation uses `_` for a parameter name, the name is not
    "inherited" from a preceding declaration for use in the augmentation's
    body. The name of the parameter for that augmentation is `_`, which can't
    be used because it's a wildcard:*

    ```dart
    f(int x);
    augment f(int _) { print(x); } // Error.
    ```

### Augmenting functions

A top-level function, static method, instance method, operator, getter, or
setter may be augmented to provide a body or add metadata:

```dart
class Person {
  final String name;
  final int age;

  Map<String, Object?> toJson();
}

// Provide a body for `toJson()`:
augment class Person {
  augment toJson() => {'name': name, 'age': age};
}
```

It's a **compile-time** error if:

*   The signature of the augmenting function does not [match][signature
    matching] the signature of the augmented function.

*   The augmenting function specifies any default values. *Default values are
    defined solely by the introductory function.*

*   A function is not complete after all augmentations are applied, unless it's
    an instance member and the surrounding class is abstract. *Every function
    declaration eventually needs to have a body filled in unless it's an
    instance method that can be abstract. In that case, if no declaration
    provides a body, it is considered abstract.*

### Augmenting variables, getters, and setters

For purposes of augmentation, a variable declaration is treated as implicitly
defining a getter whose return type is the type of the variable. If the variable
is not `final`, or is `late` without an initializer, then the variable
declaration also implicitly defines a setter with a parameter named `_` whose
type is the type of the variable.

If the variable is `abstract`, then the getter and setter are incomplete,
otherwise they are complete. *For non-abstract variables, the compiler
synthesizes a getter that accesses the backing storage and a setter that updates
it, so these members have bodies.*

A getter can be augmented by another getter, and likewise a setter can be
augmented by a setter. This is true whether the getter or setter is explicitly
declared or implicitly declared using a variable declaration.

*Since non-abstract variables are complete, that implies that it is an error to
augment a non-abstract variable declaration with a complete getter, setter, or
variable declaration. Likewise, it is an error to augment a complete getter or
setter with a non-abstract variable declaration.*

It's a **compile-time error** if:

*   The signature of the augmenting getter or setter does not [match][signature
    matching] the signature of the augmented getter or setter.

*   A `const` variable declaration is augmented or augmenting.

*   A getter or setter (including one implicitly induced by a variable
    declaration) is not complete after all augmentations are applied, unless
    it's an instance member and the surrounding class is abstract. *Every getter
    or setter declaration eventually needs to have a body filled in unless it's
    an instance member that can be abstract. In that case, if no declaration
    provides a body, it is considered abstract.*

### Augmenting enums

An augmentation of an enum type can add new members to the enum, including new
enum values. Enum values are appended in augmentation application order.

Enum values themselves can't be augmented since they are essentially constant
variables and constant variables can't be augmented.

It's a **compile-time error** if:

*   A declaration inside an augmenting enum declaration has the name `values`,
    `index`, `hashCode`, or `==`. *It has always been an error for an enum
    declaration to declare a member named `index`, `hashCode`, `==`, or
    `values`, and this rule just clarifies that this error is applicable for
    augmenting declarations as well.*

*   An enum doesn't have any values after all augmentations are applied. *The
    grammar allows an enum declaration to not have any values so that other
    declarations of the same enum can add them, but ultimately the enum must
    end up with some.*

### Augmenting constructors

Augmenting constructors works similar to augmenting a function, with some extra
rules to handle features unique to constructors like redirections and
initializer lists.

It's a **compile-time error** if:

*   The signature of the augmenting function does not [match][signature
    matching] the signature of the augmented function.

*   The augmenting constructor parameters specify any default values.
    *Default values are defined solely by the introductory constructor.*

*   The introductory constructor is `const` and the augmenting constructor
    is not or vice versa. *An augmentation can't change whether or not a
    constructor is const because that affects whether users are allowed to use
    the constructor in a const context.*

*   The introductory constructor is marked `factory` and the augmenting
    constructor is not, or vice versa. *An augmentation can't change whether or
    not a constructor is generative because that affects whether users are
    allowed to call the constructor in a subclass's initializer list.*

An incomplete constructor can be completed by adding an initializer list and/or
a body, or by adding a redirection:

```dart
class C {
  C.generative();
  factory C.fact();

  C.other();
}

augment class C {
  augment C.generative() : this.other();
  factory augment C.fact() = C.other;
}
```

### Augmenting extension types

When augmenting an extension type declaration, the parenthesized clause where
the representation type is specified is treated as a constructor that has a
single positional parameter, a single initializer from the parameter to the
representation field, and an empty body. This constructor is complete.

The extension also introduces a complete getter for the representation variable.

*In other words, we treat the representation field clause as declaring an
implicit constructor and final field for the representation variable. Since they
are both complete, they can't be augmented with bodies. The representation
variable getter can be augmented, because it's a getter and not a field
declaration, but the augmentation can't add a body.*

### Augmenting with metadata annotations

An augmenting declaration can have metadata attached to it. The language doesn't
specify how metadata is used. Tools may choose to append metadata from
augmentations to the resulting combined declaration or allow inspecting the
metadata on the individual augmentations.

*In practice, most code generators use the [analyzer package][] to introspect
over code. Code generators introspecting on the _syntax_ of some code likely
want to see the metadata for each syntactic declaration separately. Code
generators introspecting over the resolved semantic model of the code (which is
more common) probably want to see the metadata of the introductory declaration
and all augmentations appended into a single list of metadata accessible from
the combined declaration.*

[analyzer package]: https://pub.dev/packages/analyzer

## Dynamic semantics

The application of augmentation declarations to an augmented declaration
produces something that looks and behaves like a single declaration: It has
a single name, a single type or function signature, and it's what all
references to the *name* refers to inside and outside of the library.

Unlike before, that single *semantic declaration* now consists of multiple
*syntactic* declarations (one introductory declaration, the rest augmenting
declarations, with a given augmentation application order), and the properties
of the combined semantic declaration can be derived from the syntactic
declarations.

We redefine a number of semantic functions to now work on a *stack* of
declarations (the declarations for a name in bottom to top order), so that
existing semantic definitions keep working.

### Example: Class declarations

#### Super-declarations

The specification of class modifiers introduced a number of predicates on
*declarations*, to check whether the type hierarchy is well formed and the
class modifiers are as required, before the static semantics have even
introduced *types* yet. We modify those predicates to apply to a stack of
augmenting declarations and an introductory declaration as follows:

*   A a non-empty *stack* of syntactic class declarations, *C*, has a
    declaration *D* as *declared super-class* if:
    *   *C* starts with an (augmenting or not) class declaration *C0* and either
        *   *C0* has an `extends` clause whose type clause denotes the
            declaration *D*, or
        *   *C0* is an augmenting declaration, so *C* continues with a
            non-empty *C<sub>rest</sub>*, and *C<sub>rest</sub>* has *D* as
            declared super-class.
*   A a non-empty *stack* of syntactic class declarations, *C*, has a
    declaration *D* as *declared super-interface* if:
    *   *C* starts with an (augmenting or not) class declaration *C0* and either
        *   *C0* has an `implements` clause with an entry whose type clause
            denotes the declaration *D*, or
        *   *C0* is an augmenting declaration, so *C* continues with a
            non-empty *C<sub>rest</sub>*, and *C<sub>rest</sub>* has *D* as
            declared super-interface.
*   A a non-empty *stack* of syntactic class declarations, *C*, has a
    declaration *D* as *declared super-mixin* if:
    *   *C* starts with an (augmenting or not) class declaration *C0* and either
        *   *C0* has a `with` clause with an entry whose type clause denotes
            the  declaration *D*, or
        *   *C0* is an augmenting declaration, so *C* continues with a
            non-empty *C<sub>rest</sub>*, and *C<sub>rest</sub>* has *D* as
            declared super-mixin.

#### Members

A class declaration stack, *C*, of an introductory declaration and zero or more
augmenting declarations, defines an *augmented interface* (member
signatures) and *augmented implementation* (instance members declarations)
based on the individual syntactic declarations.

A non-empty class declaration stack, *C*, has the following set of instance
member declarations:

*   Let *C<sub>top</sub>* be the latest declaration of the stack, and
    *C<sub>rest</sub>* the rest of the stack.
*   If *C<sub>top</sub>* is a non-augmenting declaration, the declarations of
    *C* is the set of syntactic instance member declarations of
    *C<sub>top</sub>*.
*   Otherwise let *P* be the set of member declarations of the non-empty stack
    *C<sub>rest</sub>*.
*   and the member declarations of *C* is the set *R* defined as containing
    only the following elements:
    *   A singleton stack of each syntactic instance member declaration *M* of
        *C<sub>top</sub>*, where *M* is a non-augmenting declaration.
    *   The elements *N* of *P* where *C<sub>top</sub>* does not contain an
        augmenting instance member declaration with the same name _(mutable
        variable declarations have both a setter and a getter name)_.
    *   The stacks of a declaration *M* on top of the stack *N*, where *N* is a
        member of *P*, *M* is an augmenting instance member declaration of
        *C<sub>top</sub>*, and *M* has the same name as *N*.

And we can whether such an instance member declaration stack, *C*, *defines an
abstract method* as:

*   Let *C<sub>top</sub>* be the latest element of the stack and
    *C<sub>rest</sub>* the rest of the stack.
*   If *C<sub>top</sub>* is a non-variable declaration, and is not declared
    abstract, the *C* doe
*   If *C<sub>top</sub>* declares a function body, then *C* does not define an
    abstract method.
*   Otherwise *C* defines an abstract method if *C<sub>rest</sub>* defines an
    abstract method.

(This is just for methods, we will define it more generally for members,
including variable declarations.)

### Example: Instance methods

#### Properties

Similarly we can define the properties of stacks of member declarations.

For example, we define the *augmented parameter list* of a non-empty stack,
*C*, of augmentations on an introductory function declaration as:

*   Let *C<sub>top</sub>* be the latest element of the stack and
    *C<sub>rest</sub>* the rest of the stack.
*   If *C<sub>top</sub>* is not an augmenting declaration, its augmented
    parameter list is its actual parameter list. _(And *C<sub>rest</sub>* is
    known to be empty.)_
*   Otherwise *C<sub>top</sub>* is an augmenting declaration with a parameter
    list which must have the same parameters (names, positions, optionality and
    types) as its augmented declaration, except that it is not allowed to
    declare default values for optional parameters.
    *   Let *P* be the augmented parameter list of *C<sub>rest</sub>*.
    *   The augmented parameter list of *C<sub>top</sub>* is then the parameter
        list of *C<sub>top</sub>*, updated by adding to each optional parameter
        the default value of the corresponding parameter in *P*, if any.

_This will usually be exactly the parameter list of the introductory
declaration, but the ordering of named parameters may differ. This is mostly
intended as an example, in practice the augmented parameter list can just be
the parameter list of the introductory declaration, but it's more
direct and clearly correct to use the actual parameter list of the declaration
when creating the parameter scope that its body will run in._

Similarly we define the _augmented function type_ of the declaration stack.
Because of the restrictions we place on augmentations, they will all have the
same function type as the introductory declaration, but again it's
simpler to assign a function type to every declaration.

#### Invocation

When invoking an instance member on an object, the current specification looks
up the corresponding implementation on the class of the runtime-type of the
receiver, traversing super-classes, until it it finds a non-abstract
declaration or needs to search past `Object`. The specification then defines
how to invoke that method declaration, with suitable contexts and bindings.

We still define the same thing, only the result of lookup is not a single
declaration, but a stack of augmenting declarations on top of an
introductory declaration, and while searching, we skip past *declaration
stacks* that define an abstract method. The resulting stack is the *member
definition*, or *semantic declaration*, which is derived from the syntactic
declarations in the source.

Invoking a *stack*, *C*, of instance method declarations on a receiver object
*o* with an argument list *A* and type arguments *T*, is then defined as
follows:

*   Let *C<sub>top</sub>* be the latest declaration on the stack (the last
    applied augmentation in augmentation application order), and
    *C*<sub>*rest*</sub> the rest of the stack.
*   If *C<sub>top</sub>* has a function body *B* then:
    *   Bind actuals to formals (using the usual definition of that), binding
        the argument list *A* and type arguments *T* to the *augmented
        parameter list* of *C*<sub>*top*</sub> and type parameters of
        *C<sub>top</sub>*. This creates a runtime parameter scope which has the
        runtime class scope as parent scope (the lexical scope of the class,
        except that type parameters of the class are bound to the runtime type
        arguments of those parameters for the instance *o*).
    *   Execute the body *B* in this parameter scope, with `this` bound to *o*.
    *   _There would have been a compile-time error if there is no earlier
        declaration with a body._
    *   The result of invoking *C* is the returned or thrown result of
        executing *B*.
*   Otherwise, the result of the invocation of *C* is the result of invoke
    *C<sub>rest</sub>* on *o* with argument list *A* and type arguments *T*.
    *   _This will eventually find a body to execute, otherwise *C* would have
        defined an abstract method, and would not have been invoked to begin
        with._

## Tooling

### Documentation comments

Documentation comments are allowed in all the standard places in library
augmentations. It is up to the tooling to decide how to present such
documentation comments to the user, but they should generally be considered to
be additive, and should not completely override the original comment. In other
words, it is not the expectation that augmentations should duplicate the
original documentation comments, but instead provide comments that are specific
to the augmentation.

### Part directive order

The order that augmentations are applied is sometimes user visible. That order
is in turn affected by the order of `part` file directives in the file.

That means that the order of `part` declarations in a file is now semantically
meaningful. Tools like IDEs should not assume it is always safe to, say,
automatically alphabetize them. However, in most cases, augmentation order
doesn't matter and it's *usually* safe to sort them if a user requests it.

For the `part` directive order to matter:

1.  There must be augmentations of the same declaration in multiple separate
    part files.

2.  The part files containing the augmentations must be siblings with neither
    a parent of the other.

3.  Those augmentations must have their application order be user visible. This
    isn't defined precisely, but includes adding `enum` values or mixins (`with`
    clause). Even then, the order is often not visible. Both augmentations would
    have to add enum values. If multiple augmentations add `with` clauses, the
    order is only visible if the applied mixins have overlapping members.

The first two are fairly simple to detect. The third is subtle (and may not be
fully captured by that paragraph). It's probably safest to be pessimistic
and assume the third point is always true.

## Changelog

### 1.37

*   Rename to "augmentations" (from "augmentation libraries") and define the
    experiment flag to be "augmentations" (was part of "macros").

### 1.36

*   Remove `augment` from typedef grammar since typedefs can no longer be
    augmented (#4388).
*   Allow augmenting variable declarations (#4387).

### 1.35

*   Reorganize sections.
*   Remove references to macros.
*   Don't allow augmentations to wrap or replace code. Remove support for
    `augmented` expressions. Disallow an augmentation from providing a body to
    a declaration that already has one.
*   Remove support for augmenting variables.
*   Simplify constructor augmentations: no concatenating initializers or merging
    initializers from one augmentation and a body from another.
*   Remove support for augmenting typedefs.
*   Remove support for augmenting redirecting constructors.
*   Allow a function augmentation to have an `external` body.
*   Rewrite "Scoping" section to be clearer.
*   Remove recommend path ordering lint. Commit to making `part` directive
    order meaningful and acceptable to rely on (#3849).
*   Allow enum declarations without values (#4356).
*   Specify signature matching for implicit setters from abstract variables
    (#4022).
*   Clarify that you can't augment an extension type constructor and add a body
    (#4047).
*   Don't allow augmenting mixin application classes (#4060).

### 1.34

*   Revert some errors introduced in version 1.28.

    *   An abstract variable can now be augmented with non-abstract getters and
        setters.
    *   External variables can now be augmented with abstract getters and
        setters.

### 1.33

*   Change the grammar to remove the primary constructor parts of an
    augmenting extension type declaration.

### 1.32

*   Specify that variables which require an initializer can have it defined
    in any augmentation.
*   Specify that the implicit null initialization is not applied until after
    augmentation.

### 1.31

*   Specify that it is an error to have a static and instance member with the
    same name in the fully merged declaration.

### 1.30

*   Simplify extension type augmentations, don't allow them to contain the
    representation type at all.

### 1.29

*   Simplify enum value augmentations, no longer allow altering the
    constructor invocation.

### 1.28

*   Explicitly disallow augmenting abstract variables with non-abstract
    variables, getters, or setters.
*   Explicitly disallow augmenting external declarations with abstract
    declarations.
*   Remove error when augmenting an abstract or external variable with a
    variable (allowed for adding comments/annotations).

### 1.27

*   Specify that representation objects for extension types cannot be augmented.

### 1.26

*   Recreate the change made in 1.23 (which was undone by accident).

### 1.25

*   Clarify that augmentations can occur in the same type-introducing
    declaration body, even in a non-augmenting declaration.
*   Update some occurrences of old terminology with new terms.

### 1.24

*   Allow augmentations which only alter the metadata and/or doc comments on
    various types, and specify behavior.

### 1.23

*   Change `augmented` operator invocation syntax to be function call syntax.

### 1.22

*   Unify augmentation libraries and parts.
    [Parts with imports][parts with imports] moved into
    separate document, as a stand-alone feature that is not linked to
    augmentations.
*   Augmentation declarations can occur in any file, whether a library or
    part file. Must occur "below" the introductory declaration (later in
    same file or sub-part) and "after" any prior applied augmentation that
    it modifies (below, or in a later sub-part of a shared ancestor).
*   Suggest a stronger ordering *lint*, where the augmentation must be "below"
    the augmentation it is applied after. That imples that all declarations with
    the same name are on the same path in the library file tree, so that
    reordering `part` directives does not change augmentation application order.
*   Change the lexical scope of augmenting class-like declarations to only
    contain the member declarations that are syntactically inside the same
    declaration, rather than collecting all member declarations from all
    augmenting or non-augmenting declarations with the same name, and making
    them all available in each declaration.
*   Avoid defining a syntactic merging, since it requires very careful scope
    management, which isn't necessary if we can just extend properties that are
    currently defined for single declarations to the combination of a
    declaration plus zero or more augmentations.

### 1.21

*   Add a compile-time errors for wrong usages of `augmented`.

### 1.20

*   Change the `extensionDeclaration` grammar rule such that an augmenting
    extension declaration cannot have an `on` clause. Adjust other rules
    accordingly.

### 1.19

*   Change the phrase 'augmentation library' to 'library augmentation',
    to be consistent with the rename which was done in 1.15.

### 1.18

*   Add a grammar rule for `enumEntry`, thus allowing them to have the
    keyword `augment`.

### 1.17

*   Introduce compile-time errors about wrong structures in the graph of
    libraries and augmentation libraries formed by directives like `import`
    and `import augment` (#3646).

### 1.16

*   Update grammar rules and add support for augmented type declarations of
    all kinds (class, mixin, extension, extension type, enum, typedef).

*   Specify augmenting extension types. Clarify that primary constructors
    (which currently only exist for extension types) can be augmented like
    other constructors (#3177).

### 1.15

*   Change `library augment` to `augment library`.

### 1.14

*   Change `augment super` to `augmented`.

### 1.13

*   Clarify which clauses are (not) allowed in augmentations of certain
    declarations.
*   Allow adding an `extends` clause in augmentations.

### 1.12

*   Update the behavior for variable augmentations.

### 1.11

*   Alter and clarify the semantics around augmenting external declarations.
*   Allow non-abstract classes to have implicitly abstract members which are
    implemented in an augmentation.

### 1.10

*   Make `augment` a built-in identifier.

### 1.9

*   Specify that documentation comments are allowed, and should be considered to
    be additive and not a complete override of the original comment. The rest of
    the behavior is left up to implementations and not specified.

### 1.8

*   Specify that augmented libraries and their augmentations must have the same
    language version.

*   Specifically call out that augmentations can add and augment enum values,
    and specify how that works.

### 1.7

*   Specify that augmentations must contain all the same keywords as the
    original declaration (and no more).

### 1.6

*   Allow class augmentations to use different names for type parameters. This
    isn't particular valuable, but is consistent with functions augmentations
    which are allowed to change the names of positional parameters.

*   Specify that a non-augmenting declaration must occur before any
    augmentations of it, in merge order.

*   Specify that augmentations can't have parts (#2057).

### 1.5

*   Augmentation libraries share the same top-level declaration and private
    scope with the augmented library and its other augmentations.

*   Now that enums have members, allow them to be augmented.

*   Compile-time error if a non-`late` augmenting instance variable calls the
    initializer for a `late` one.

### 1.4

*   When inferring the type of a variable, only the original variable's
    initializer is used.

### 1.3

*   Constructor and function augmentations can't define default values.

### 1.2

*   Specify that augmenting constructor initializers are inserted before the
    original constructor's super or redirecting initializer if present (#2062).
*   Specify that an augmenting type must replicate the original type's type
    parameters (#2058).
*   Allow augmenting declarations to add metadata annotations and macro
    applications (#2061).

### 1.1

*   Make it an error to apply the same augmentation multiple times (#1957).
*   Clarify type parameters and parameter modifiers in function signature
    matching (#2059).

### 1.0

Initial version.
