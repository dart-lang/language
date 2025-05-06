# Augmentations

Author: rnystrom@google.com, jakemac@google.com, lrn@google.com <br>
Version: 1.35 (see [Changelog](#Changelog) at end)

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

This approach works well when the generated code consists of completely separate
declarations from the hand-authored code. But if a code generator wants to, say,
add a method to a hand-authored class, then the language is of little help. This
proposal addresses that limitation by adding *augmentations*.

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
    enums, add to the `with` or `implements` clauses, or provide bodies for
    members.

*   Function augmentations, which can provide a body.

These operations cannot be expressed today using only imports, exports, or
part files. Any Dart file (library file or part file) can contain
augmentation declarations. *In particular, an augmentation can augment a
declaration in the same file in which it occurs.*

An augmentation can fill in a body for a declared member that has no body, but
can't *replace* an existing body or add to it. In order to allow augmentations
to provide bodies for static methods and top-level functions, we allow
declarations of those to be "abstract" and lack a body as long as a body is
eventually provided by an augmentation declaration.

#### Design principle

When designing this feature, a challenging question is how much power to give
augmentations. Giving them more ability to change the introductory declaration
makes them more powerful and expressive. But the more an augmentation can
change, the less a reader can correctly assume from reading only the
introductory declaration. That can make code using augmentations harder to
understand and work with.

To balance those, the general principle of this feature is that augmentations
can *add new capabilities* to the declaration and *fill in implementation*, but
generally can't change any property a reader knows to be true from the
introductory declaration. In other words, if a program would work without the
augmentation being applied, it should generally still work after the
augmentation is applied. *Note that this a design principle and not a strict
guarantee.*

For example, if the introductory declaration of a function takes an int
parameter and returns a string, then any augmentation must also take an int and
return a string. That way a reader knows how to call the function and what
they'll get back without having to read the augmentations.

Likewise, if an introductory class declaration has a generative constructor,
then the reader assumes they can inherit from that class and call that as a
superclass constructor. Therefore, an augmentation of the class is prohibited
from changing the constructor to a factory.

## Syntax

The grammar changes are fairly simple. The grammar is modified to allow an
`augment` modifier before various declarations. Also, functions, getters, and
setters are allowed to have `;` bodies even when not instance members (except
for local functions, which must still have a real body).

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
  | 'augment'? functionSignature (functionBody | ';')
  | 'augment'? getterSignature (functionBody | ';')
  | 'augment'? setterSignature (functionBody | ';')
  | 'augment'? ('final' | 'const') type? initializedIdentifierList ';'
  | 'augment'? 'late' 'final' type? initializedIdentifierList ';'
  | 'augment'? 'late'? varOrType initializedIdentifierList ';'

classDeclaration ::= 'augment'? (classModifiers | mixinClassModifiers)
    'class' typeWithParameters superclass? interfaces?
    memberedDeclarationBody
  | 'augment'? classModifiers 'mixin'? 'class' mixinApplicationClass

mixinDeclaration ::= 'augment'? 'base'? 'mixin' typeIdentifier
  typeParameters? ('on' typeNotVoidNotFunctionList)? interfaces?
  memberedDeclarationBody

extensionDeclaration ::=
    'extension' typeIdentifierNotType? typeParameters? 'on' type
    memberedDeclarationBody
  | 'augment' 'extension' typeIdentifierNotType typeParameters?
    memberedDeclarationBody

extensionTypeDeclaration ::=
    'extension' 'type' 'const'? typeIdentifier
    typeParameters? representationDeclaration interfaces?
    memberedDeclarationBody
  | 'augment' 'extension' 'type' typeIdentifier typeParameters? interfaces?
    memberedDeclarationBody

enumType ::= 'augment'? 'enum' typeIdentifier
  typeParameters? mixins? interfaces?
  '{' enumEntry (',' enumEntry)* (',')?
  (';' memberDeclarations)? '}'

typeAlias ::= 'augment'? 'typedef' typeIdentifier typeParameters? '=' type ';'
  | 'augment'? 'typedef' functionTypeAlias

memberedDeclarationBody ::= '{' memberDeclarations '}'

memberDeclarations ::= (metadata memberDeclaration)*

memberDeclaration ::= declaration
  | 'augment'? methodSignature functionBody

enumEntry ::= metadata 'augment'? identifier argumentPart?
  | metadata 'augment'? identifier typeArguments?
    '.' identifierOrNew arguments

declaration ::= 'external'? factoryConstructorSignature ';'
  | 'augment'? 'external' constantConstructorSignature ';'
  | 'augment'? 'external' constructorSignature ';'
  | 'augment'? 'external'? 'static'? getterSignature ';'
  | 'augment'? 'external'? 'static'? setterSignature ';'
  | 'augment'? 'external'? 'static'? functionSignature ';'
  | 'external' ('static'? finalVarOrType | 'covariant' varOrType) identifierList ';'
  | 'augment'? 'external'? operatorSignature ';'
  | 'augment'? 'abstract' (finalVarOrType | 'covariant' varOrType) identifierList ';'
  | 'static' 'const' type? initializedIdentifierList ';'
  | 'static' 'final' type? initializedIdentifierList ';'
  | 'static' 'late' 'final' type? initializedIdentifierList ';'
  | 'static' 'late'? varOrType initializedIdentifierList ';'
  | 'covariant' 'late' 'final' type? identifierList ';'
  | 'covariant' 'late'? varOrType initializedIdentifierList ';'
  | 'late'? 'final' type? initializedIdentifierList ';'
  | 'late'? varOrType initializedIdentifierList ';'
  | redirectingFactoryConstructorSignature ';'
  | constantConstructorSignature (redirection | initializers)? ';'
  | 'augment' constantConstructorSignature initializers? ';'
  | constructorSignature (redirection | initializers)? ';'
  | 'augment' constructorSignature initializers? ';'
```

## Static semantics

### Declaration ordering relations

As part of the meta-programming and augmentation features, we expand the
[capabilities of part files][parts with imports]. With that feature, a part file
can now have its own `import` and `export` directives, and further nested `part`
files, with part files inheriting the imports and prefixes of their parent (part
or library) file.

[parts with imports]: parts_with_imports.md

Augmentation declarations interact with part files in restrictions on where an
augmenting declaration may occur relative to the declaration it augments. We
define the following relations on *declarations* based on the relations between
*files* of a library.

We say that a syntactic declaration *occurs in* a Dart file if the
declaration's source code occurs in that Dart file.

We say that a Dart file *contains* a declaration if the declaration occurs
in the file itself, or if any of the files included by the Dart file contain
the declaration. *That is, if the declaration occurs in a file in the subtree
of that Dart file.*

We then define two orderings of declarations in a library, one partial and one
complete.

#### "Is above"

A syntactic declaration *A* *is above* a syntactic declaration *B* if and only
if:

*   *A* and *B* occur in the same file, and the start of *A* is syntactically
    before the start of *B*, in source order, or

*   The file where *A* occurs includes the file where *B* occurs. *In other
    words, if there is a `part` chain from the file where A is declared to the
    file where B is declared, then A is above B.*

This is a partial order. If A and B occur in sibling part files where neither
declaration's file contains the other, then there is no is above relation
between the declarations.

#### "Is before" and "is after"

For any two syntactic declarations *A*, and *B*:

*   If *A* is above *B* then *A* is before *B*.

*   If *B* is above *A* then *B* is before *A*.

*   Otherwise, *A* and *B* are in sibling branches of the part tree:

    *   Let *F* be the least containing file for those two files. *Find the
        nearest root file in the part subtree that contains both A and B.
        Neither A nor B will occur directly in F because if it did, then A or B
        would be above the other and the previous clauses would have handled
        it.*

    *   If the `part` directive in *F* including the file that contains *A* is
        syntactically before the `part` directive in *F* including the file that
        contains *B* in source order, then *A* is before *B*.

    *   Otherwise *B* is before *A*.

Then *B* *is after* *A* if and only if *A* *is before* *B*.

*In short, we complete the partial "is above" order by taking the order of
`part` directives themselves into account when declarations are in sibling
branches of the part tree.*

This order is total (transitive, anti-symmetric, and irreflexive). It
effectively orders declarations by a pre-order depth-first traversal of the file
tree, visiting declarations of a file in source order, and then recursing on
`part` directives in source order.

### Declaration context

Prior to this proposal, an entity like a class or function is introduced by a
single syntactic declaration. With augmentations, an entity may be composed out
of multiple declarations, the introductory one and any number of augmentations.
We define a notion of a *context* to help us talk about the location where we
need to look to collect all of the declarations that define some entity.

* The context of a top-level declaration is the library and its associated tree
  of part files.

* The context of a member declaration in a type declaration named *N* is the set
  of type declarations (introductory and augmenting) named *N* in the enclosing
  set of Dart files.

*Note that context is only defined for the kinds of declarations that can be
augmented. We don't define a context for, say, local variable declarations,
because those aren't subject to augmentation.*

### Scoping

The static and instance member namespaces for a type or extension declaration,
augmenting or not, are lexical only. Only the declarations (augmenting or not)
declared inside the actual declaration are part of the lexical scope that
member declarations are resolved in.

_This means that a static or instance member declared in the augmented
declaration of a class is not *lexically* in scope in a corresponding
augmenting declaration of that class, just as an inherited instance member
is not in the lexical scope of a class declaration._

If a member declaration needs to reference a static or instance member
declared in another introductory or augmenting declaration of the same
type, it can use `this.name` for instance members and `TypeName.name` for
static members to be explicit. Or it can rely on the default if
`name` is not in the lexical scope at all, in which case it's interpreted
as `this.name` if it occurs inside a scope where a `this` is available. _This
approach is always potentially dangerous, since any
third-party import adding a declaration with the same name would break the
code. In practice that's almost never a problem, because instance members
and top-level declarations usually use different naming strategies._

Example:

```dart
// Main library "some_lib.dart":
import 'other_lib.dart';

part 'some_augment.dart';

const b = 37;

class C {
  static const int b = 42;
  bool isEven(int n) {
    if (n == 0) return true;
    return !_isOdd(n - 1);
  }
}

// Augmentation "some_augment.dart":
part of 'some_lib.dart';

import 'also_lib.dart';

augment class C {
  bool _isOdd(int n) => !this.isEven(n - 1);
  void printB() { print(b); }  // Prints 37
}
```

This code is fine. Code in `C.isEven` can refer to members added
in the augmentation like `_isOdd()` because there is no other `_isOdd` in
scope. Code in `C._isOdd` works too by explicitly using `this.isEven` to
ensure it calls the correct method.

You can visualize the namespace nesting sort of like this:

```
some_lib.dart         : some_augment.dart
                      :
.-------------------------------------------.
| library import scope:                     |
| other_lib imports                         |
'-------------------------------------------'
          ^           :          ^
          |           :          |
          |           : .-------------------.
          |           : | part import scope:|
          |           : | also_lib imports  |
          |           : '-------------------'
          |           :          ^
          |           :          |
.-------------------------------------------.
| top-level declaration scope:              |
| const b = 37                              |
| class C (fully augmented class)           |
'-------------------------------------------'
          ^           :          ^
          |           :          |
.-------------------. : .-------------------.
| class C:          | : | augment class C:  |
| const b = 42      | : | _isOdd()          |
| isEven()          | : |                   |
'-------------------' : '-------------------'
         ^            :          ^
         |            :          |
.-------------------. : .-------------------.
| C.isEven() body   | : | C._isOdd() body   |
'-------------------' : '-------------------'
```

Each part file has its own combined import scope, extending that of its
parent, and its own member declaration scopes for each declared member,
introducing a lexical scope for the declaration's contents. In the middle, each
passes through the shared library declaration namespaces for the top-level
instances themselves.

It's a **compile-time error** for both a static and instance member of the same
name to be defined on the same type, even if they live in different lexical
scopes. You cannot work around this restriction by moving the static member
out to an augmentation, even though it would result in an unambiguous resolution
for references to those members.

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

## Applying augmentations

An augmentation declaration *D* is a declaration marked with the built-in
identifier `augment`. We language version making `augment` a built-in
identifier, to avoid breaking pre-feature code.

*D* augments a declaration *I* with the same name and in the same context as
*D*. There may be multiple augmentations in the context of *D*. More precisely,
*I* is the declaration before *D* and after every other declaration before *D*.

It's a **compile-time error** if there is no matching declaration *I*. *In other
words, it's an error to have a declaration marked `augment` with no declaration
to apply it to.*

We say that *I* is the declaration which is *augmented by* *D*.

*In other words, take all of the declarations with the same name in some
context, order them according to after, and each augments the preceding one.
The first one must not be marked `augment` and all the subsequent ones must be.*

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

*   There is no initializer list. *Obviously, this only applies to constructor
    declarations.*

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
are applied is user-visible, so must be specified. Augmentations are ordered
using the *after* relation and are applied from least to greatest in that order.

*For example:*

```dart
enum E { a }
augment enum E { b }
augment enum E { c }
```

*The resulting enum has values `a`, `b`, and `c`, in that order.*

### Augmenting class-like declarations

A class, enum, extension, extension type, mixin, or mixin class declaration
can be marked with an `augment` modifier:

```dart
augment class SomeClass {
  // ...
}
```

A class, enum, extension type, mixin, or mixin class augmentation may
specify `extends`, `implements` and `with` clauses (when generally
supported). The types in these clauses are appended to the introductory
declarations' clauses of the same kind, and if that clause did not exist
previously, then it is added with the new types.

Instance or static members defined in the body of the augmenting type,
including enum values, are added to the instance or static namespace of the
corresponding type in the introductory declaration. *In other words, the
augmentation can add new members to an existing type.*

Instance and static members inside a class-like declaration may themselves
be augmentations. In that case, they augment the corresponding members in
the same context, according to the rules in the following subsections.

It's a **compile-time** error if:

*   The resulting clauses after being appended would be erroneous if declared
    directly. This means you can't end up with multiple `extends` clauses on a
    class, an `on` clause on an enum, etc.

*   A library contains two top-level declarations with the same name, and one of
    the declarations is a class-like declaration and the other is not of the
    same kind, meaning that either one is a class, mixin, enum, extension or
    extension type declaration, and the other is not the same kind of
    declaration.

*   The augmenting declaration and augmented declaration do not have all the
    same modifiers: `abstract`, `base`, `final`, `interface`, `sealed` and
    `mixin` for `class` declarations, and `base` for `mixin` declarations.

    *This is not a technical requirement, but follows our design principle that
    what is known from reading the introductory declaration will still be true
    after augmentation.*

*   An augmenting extension declares an `on` clause *(this is a syntax
    error)*. We also do not allow adding further restrictions to a `mixin`
    declaration, so no further types can be added to its `on` clause, if it
    even has one. *These restrictions could both be lifted later if we have a
    compelling use case.*

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

*   The function signature of the augmenting function does not exactly match the
    function signature of the augmented function. This means that:

    *   Any provided return types must be the same type.

    *   There must be same number or required and optional positional
        parameters, all with the same types (when provided), the same number of
        named parameters, each pairwise with the same name, same type (when
        provided) and same `required` and `covariant` modifiers.

    *   Any type parameters and their bounds (when provided) must be the same
        (like for type declarations).

    *Since repeating the signature is, by definition, redundant, this doesn't
    accomplish anything semantically. But it ensures that anyone reading the
    augmenting function can see the declarations of any parameters that it
    uses in its body.*

*   The augmenting function specifies any default values. *Default values are
    defined solely by the introductory function.*

*   A function is not complete after all augmentations are applied, unless it
    is in a context where it can be abstract. *Every function declaration
    eventually needs to have a body filled in unless it's an instance method
    that can be abstract. In that case, if no declaration provides a body, it
    is considered abstract.*

### Augmenting variables

A class-like augmentation can add *new* variables (i.e. instance or static
fields) to the type being augmented:

```dart
class C {}

augment class C {
  int x = 3;

  static int y = 4;
}
```

Variable declarations themselves can't be directly augmented, with the exception
of abstract fields.

*A variable declaration implicitly has code for the synthesized getter and
setter that access and modify the underlying backing storage. Since we don't
allow augmentations to replace code, that implies that augmentations can't
change variables. So we don't allow them to be augmented.*

#### Abstract fields

Dart supports `abstract` field declarations. They are syntactic sugar for
declaring an abstract getter with an optional abstract setter if the variable is
non-final. They don't actually declare a variable with any backing storage.

Because abstract variables are effectively abstract getter and setter
declarations, they can be augmented and used in augmentations just like function
declarations:

*Examples:*

```dart
class C {
  // Augment an abstract variable with a getter:
  abstract final int a;
  augment int get a => 1; // OK.

  // Augment an abstract variable with a getter and setter:
  abstract int b;
  augment int get b => 1; // OK.
  augment set b(int value) {} // OK.

  // Augment a getter with an abstract variable:
  int get c;

  @someMetadata
  augment abstract final int c; // (Not very useful, but valid.)
}
```

### Augmenting enum members

An augmentation of an enum type can add new members to the enum, including new
enum values. Enum values are appended in augmentation application order.

Enum values themselves can't be augmented since they are essentially constant
variables and variables can't be augmented.

It's a **compile-time error** if:

*   A declaration inside an augmenting enum declaration has the name `values`,
    `index`, `hashCode`, or `==`. *It has always been an error for an enum
    declaration to declare a member named `index`, `hashCode`, `==`, or
    `values`, and this rule just clarifies that this error is applicable for
    augmenting declarations as well.*

### Augmenting constructors

Augmenting constructors works similar to augmenting a function, with some extra
rules to handle features unique to constructors like initializer lists. Factory
constructors, generative constructors, and const constructors (factory and
generative) can be augmented. Redirecting constructors can't be augmented,
though a class-like augmentation can add *new* redirecting constructors.

*We could support augmenting redirecting constructors, but the use cases seem
rare. Supporting this would require a way to specify that a constructor is
redirecting without actually providing the redirection since the augmentation
needs to fill that in and can't replace an existing redirection in the
introductory declaration.*

It's a **compile-time error** if:

*   The signature of the constructor augmentation does not match the original
    constructor. It must have the same number of positional parameters, the same
    named parameters, and matching parameters must have the same type,
    optionality, and any `required` modifiers must match. Any initializing
    formals and super parameters must also be the same in both constructors.

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

### Augmenting extension types

When augmenting an extension type declaration, the parenthesized clause where
the representation type is specified is treated as a constructor that has a
single positional parameter, a single initializer from the parameter to the
representation field, and an empty body. The representation field clause must
be present on the declaration which introduces the extension type, and must be
omitted from all augmentations of the extension type.

This means that an augmentation can add a body to an extension type's implicit
constructor, which isn't otherwise possible. This is done by augmenting the
constructor in the body of the extension type. *Note that there is no
guarantee that any instance of an extension type will have necessarily executed
that body, since you can get instances of extension types through casts or other
conversions that sidestep the constructor.* For example:

```dart
extension type A(int b) {
  augment A(int b) {
    assert(b > 0);
  }
}
```

*This is designed in anticipation of supporting [primary constructors][] on
other types in which case the extension type syntax will then be understood by
users to be a primary constructor for the extension type.*

[primary constructors]:
https://github.com/dart-lang/language/blob/main/working/2364%20-%20primary%20constructors/feature-specification.md

The extension type's representation object is *not* a variable, even though it
looks and behaves much like one, and it cannot be augmented as such.

It's a **compile-time error** if:

*   An augmenting declaration has the same name as the representation object.

*   An extension type augmentation contains a representation field clause.

### Augmenting with metadata annotations

If an augmentation has metadata attached to it, these are appended to the
metadata of the declaration being augmented.

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

A class declaration stack, *C*, of a one non-augmenting and zero or more
augmenting class declarations, defines an *augmented interface* (member
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
    `abstract`, the *C* doe
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
    *   If *B* contains an expression of the form `augmented<TypeArgs>(args)`
        (type arguments omitted if empty), then:
        *   The static type of `augmented` is the augmented function type of
            *C<sub>rest</sub>*. The expression is type-inferred as a function
            value invocation of a function with that static type.
        *   To evaluate the expression, evaluate `args` to an argument list
            *A2*, invoke *C<sub>rest</sub>* with argument list *A2* and type
            arguments that are the types of `TypeArgs`. The result of
            `augmented<TypeArgs>(args)` is the same as the result of that
            invocation (returned value or thrown error).
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

### Path requirement lint suggestion

One issue with the augmentation application order is that it is not stable
under reordering of `part` directives. Sorting part directives can change the
order that augmentation applications in separate included sub-trees are applied
in.

To help avoiding issues, we want to introduce a *lint* which warns if a library
is susceptible to part file reordering changing augmentation application order.
A possible name could be `augmentation_ordering`.

Its effect would be to **report a warning** *if* for any two (top-level)
augmenting declarations with name *n*, one is not *above* the other.

If the lint is satisfied, then all augmenting declarations are ordered by
the *before* relation, which means that no two of them can be in different
sibling parts of the same file, and therefore all the augmenting
declarations occur along a single path down the part-file tree. _This
ensures that *part file directive ordering* has no effect on augmentation
application order._

The language specification doesn't specify lints or warnings, so this lint
suggestion is not normative. We wish to have the lint, and preferably
include it in the "recommended" lint set, because it can help users avoid
accidental problems. We want it as a lint instead of a language restriction
so that it doesn't interfere with macro-generated code, and so that users
can `// ignore:` it if they know what they're doing.

## Changelog

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
    [Parts with imports specification][parts_with_imports.md] moved into
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
