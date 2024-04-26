# Wildcards

Author: Bob Nystrom

Status: In-progress

Version 1.1

Pattern matching brings a new way to declare variables. Inside patterns, any
variable whose name is `_` is considered a "wildcard". It behaves like a
variable syntactically, but doesn't actually create a variable with that name.
That means you can use `_` multiple times in a pattern without a name collision.

This proposal extends that non-binding behavior to other variables in Dart
programs named `_`.

The name `_` is a well-established convention in Dart for a couple of uses:

*   **Unused callback parameters.** A higher-order function passes arguments to
    a callback, but the specific callback being used doesn't care about the
    value. For example:

    ```dart
    var hundredPenguins = List.generate(100, (_) => 'penguin');
    ```

*   **Unused method override parameters.** When a method overrides an inherited
    method, it must accept the same required parameters. If it doesn't use one,
    sometimes it gets named `_`. (In practice, it's more common to just use the
    same name as the inherited parameter.)

*   **Private constructors.** Often a class has a single canonical constructor
    that it wants to make private (so that the class can't be constructed
    externally or so that external users have to go through some other
    constructor). For example:

    ```dart
    class DownloadedValue {
      /// Downloading is asynchronous but we don't want to return an instance
      /// until it's fully initialized.
      static Future<DownloadedValue> download(String uri) async {
        var value = await downloadValue(uri);
        return DownloadedValue._(value);
      }

      final String _value;

      DownloadedValue._(this.value);
    }
    ```

Since `_` *is* a binding name in Dart today, you can only use this name once in
any given scope. If you want to ignore multiple callback parameters, the
convention is to use a series of underscores for each name: `_`, `__`, `___`,
etc.

Making `_` non-binding outside of patterns solves a few problems:

*   It makes other variable declarations consistent with how variable
    declarations in patterns behave.

*   It avoids the ugly hack of needing to use `__` and friends to avoid name
    collisions.

*   It prevents code from using a variable that wasn't intended to be used.

At the same time, we want to support the idiom of using `_` as the name of the
canonical private constructor, so we don't want *all* declarations named `_`
to be non-binding.

It seems that the natural line to draw is between declarations that are local
to a block scope versus those that are top-level declarations or members where
library privacy comes into play.

## Proposal

A *local declaration* is any of:

*   Function parameters. This includes top-level functions, local functions,
    function expressions ("lambdas"), instance methods, static methods,
    constructors, etc. It includes all parameter kinds: simple, field formals,
    and function-typed formals, etc.:

    ```dart
    Foo(_, this._, super._, void _(), {_}) {}

    list.where((_) => true);
    ```

*   Local variable declaration statement variables.

    ```dart
    main() {
      var _ = 1;
      int _ = 2;
    }
    ```

*   For loop variable declarations.

    ```dart
    for (int _ = 0;;) {}
    for (var _ in list) {}
    ```

*   Catch clause parameters.

    ```dart
    try {
      throw '!';
    } catch (_) {
      print('oops');
    }
    ```

*   Generic type and generic function type parameters.

    ```dart
    class T<_> {}
    void genericFunction<_>() {}

    takeGenericCallback(<_>() => true);
    ```

A local declaration whose name is `_` does not bind that name to anything. This
means you can have multiple local declarations named `_` in the same namespace
without a collision error. The initializer, if there is one, is still executed,
but the value is not accessible.

Other declarations: top-level variables, top-level function names, type names,
member names, etc. are unchanged. They can be named `_` as they are today.

We do not change how identifier *expressions* behave. Members can be named `_`
and you can access them from inside the class where the member is declared
without any leading `this.`:

```dart
class C {
  var _ = 'bound';

  test() {
    print(_); // Prints "bound".
  }
}
```

Likewise with a top-level declaration named `_`:

```dart
var _ = 'ok';

main() {
  print(_); // Prints "ok".
}
```

It's just that a local declaration named `_` doesn't bind that name to anything.

There are a few interesting corners and refinements:

### Assignment

The behavior of assignment expressions is unchanged. In a pattern assignment,
`_` is always a wildcard. This is valid:

```dart
int a;
(_, a) = (1, 2);
```

But in a non-pattern assignment, `_` is treated as a normal identifier. If it
resolves to something assignable (which now must mean a member or top-level
declaration), the assignment is valid. Otherwise it's an error:

```dart
main() {
  _ = 1; // Error.
}

class C {
  var _;

  test() {
    _ = 2; // OK.
  }
}
```

### Wildcards do not shadow

Here is an interesting example:

```dart
class C {
  var _ = 'field';

  test() {
    var _ = 'local';

    _ = 'assign';
  }
}
```

This program is valid and assigns to the *field*, not the local. This code is
quite confusing. In practice, we expect reasonable users will not name fields
`_` and thus not run into this problem.

### Initializing formals

A positional initializing formal named `_` does still initialize a field 
named `_` (and you can still have a field with that name):

```dart
class C {
  var _;

  C(this._); // OK.
}
```

It is a compile-time error if a named initializing formal has the name `_`:

```dart
class C {
  var _;
  
  C({this._}); // Error.
}
```

But no *parameter* with that name is bound, which means `_` can't be accessed
inside the initializer list. In the body it is fine, since that refers to the
field, not the parameter:

```dart
class C {
  var _;
  var other;

  C(this._)
    : other = _ { // <-- Error, cannot access `this`.
    print(_); // OK. Prints the field.
  }
}
```

Even though the parameters no longer collide, it is still an error to have two
initializing formals named `_`:

```dart
class C {
  var _;
  C(this._, this._); // Error.
}
```

### Super parameters

An occurrence of `super._` as a declaration of a formal parameter in a
constructor is a compile-time error.

*It is not an error everywhere: In a method body it could be an invocation
of an inherited getter named `_`.*

*The desugared meaning of a super parameter includes a reference to the
parameter in the initializer list of the enclosing constructor declaration,
but such references are not possible when the parameter name is a
wildcard.*

### Extension types

An extension type declaration has a `<representationDeclaration>`
which is similar to a formal parameter list of a function declaration.

*It always declares exactly one mandatory positional parameter, and the
meaning of this declaration is that it introduces a formal parameter of a
constructor of the enclosing extension type as well as a final instance
variable declaration, also known as the representation variable of the
extension type.*

This parameter can have the declared name `_`. This means that the
representation variable is named `_`, and no formal parameter name is
introduced into any scopes.

*Currently that parameter is not in scope for any code anyway, but future
generalizations such as primary constructors could introduce it into a
scope, e.g., in order to be able to pass actual arguments to a
superconstructor.*

### Unused variable warnings

Dart tools currently warn if you have an unused local declaration. If the
declaration is named `_`, it now *can't* be used, so the tools should stop
showing the warning for that name.

### Multiple underscore lint and quick fix

Since `_` is binding today, when you need more than one, the convention to avoid
collisions is to use a series of underscores. With this proposal, that
convention is no longer needed.

It would be helpful if the linter would suggest that variables whose name is a
series of more than one `_` be renamed to just `_` now that it won't collide.
Likewise, a quick fix could perform that change automatically.

## Breaking change

This is a breaking change to code with parameters or other local declarations
named `_` that actually uses them. Fortunately, code doing that is rare.

I wrote [a script][scrape] to examine every identifier whose name consists only
of underscores in a large corpus of pub packages, Flutter widgets, and open
source Flutter applications (18,695,158 lines in 102,015 files):

[scrape]: https://gist.github.com/munificent/e03728874aae4d16a9760f207aecb16c

```
-- Declaration (33074 total) --
  21786 ( 65.870%): Parameter name
   8093 ( 24.469%): Constructor name
   2913 (  8.808%): Catch parameter
    236 (  0.714%): Local variable
     31 (  0.094%): Loop variable
      3 (  0.009%): Extension name
      2 (  0.006%): For loop variable
      2 (  0.006%): Static field
      2 (  0.006%): Type parameter
      2 (  0.006%): Instance field
      2 (  0.006%): Method name
      1 (  0.003%): Enum value name
      1 (  0.003%): Function name

-- Use (17356 total) --
  13289 ( 76.567%): Private constructor invocation                   =========
   2640 ( 15.211%): Private superclass constructor invocation        ==
    807 (  4.650%): Identifier expression                            =
    522 (  3.008%): Redirection to private constructor               =
     48 (  0.277%): Factory constructor redirecting to private name  =
     46 (  0.265%): Assignment target                                =
      3 (  0.017%): Field initializer                                =
      1 (  0.006%): Type annotation                                  =
```

As expected, most declarations named `_` (or longer) are parameters and
constructor names, the two main idioms. Catch clause parameters are fairly
common too. All other declarations named `_` are extremely rare, less than 1% of
the total when put together.

When code *uses* a declaration named `_` (or longer), over 95% are private
constructor calls, as expected. But there are a relatively small number of uses
where a variable named `_` is being accessed. My simple syntactic analysis can't
distinguish between whether those are accessing local variables (in which case
they will break) or instance or top-level members (in which case they're OK).
From skimming some of the examples, it does look like some users sometimes name
lambda parameters `_` and then use the parameter in the body.

Fixing these is easy: just rename the variable and its uses to something other
than `_`. Since this proposal doesn't affect the behavior of externally visible
members, these fixes can always be done locally without changing a library's
public API.

However, this *is* a breaking change. If this ships in the same version as
pattern matching, we can gate it behind a language version and only break code
when it upgrades to that version.

## Changelog

### 1.1

- Add rules about `super._` and about extension types.

### 1.0

- Initial version
