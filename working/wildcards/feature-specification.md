TODO: link

Pattern matching brings a new way to declare variables. Inside patterns, any
variable whose name is `_` is considered a "wildcard". It behaves like a
variable syntactically, but it doesn't actually create a variable with that
name. That means you can use `_` multiple times in a pattern without a name
collision, and you can't use it as an expression to access the matched value.

This proposal extends that non-binding behavior to other variables in Dart
programs named `_`.

The name `_` is a well-established convention in Dart for a couple of uses:

*   **Unused callback parameters.** A higher-order function passes arguments to
    a callback, but the specific callback being used doesn't care about the
    value. For example:

    ```dart
    var hundredPenguins = List.generate(100, (_) => 'penguin');
    ```

*   **Used method override parameters.** When a method overrides an inherited
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
etc. In practice, these are all "wildcard" names.

Making `_` actually non-binding solves a few problems:

*   It makes other variable declarations consistent with how variable
    declarations in patterns behave.

*   It avoids the ugly hack of needing to use `__` and friends to avoid name
    collisions.

*   It prevents code from using a variable that wasn't intended to be used.

At the same time, we want to *not* prevent the idiom of using `_` as the name
of the canonical private constructor. This means making `_` non-binding for
*variables*, but not for *members*. Getters and setters make the line between
those somewhat fuzzy.

## Proposal

TODO: should silence unused variable warnings

## Breaking change

This is a breaking change to code that declares variables named `_` and actually
uses them.

TODO: stats

## Semantics

We do not change how identifier *expressions* behave. Members can be named `_`
and you can access them from inside the class where the member is declared
without any leading `this.`. If the member is a method tear-off, it's possible
for a `_` expression to be meaningful:

```dart
class C {
  static C _() => C();

  static C test() {
    var tearOff = _; // <-- Valid.
    return tearOff();
  }
}
```

todo: should we allow instance or static fields? no: will be inconsistent if
later allow patterns there

todo: should we allow getters and setters? no: inconsistent with vars.

todo: should we allow methods? yes: constructors and static methods mostly
interchangeable. allowing static methods without instance methods would be
weird.
