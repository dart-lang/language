# Rethrow in switch expressions

**Related issue:** [#3097](https://github.com/dart-lang/language/issues/3097)

## Current behavior

Inside a `catch` clause, `rethrow` can be used to rethrow the caught exception while preserving its stack trace.
However, `rethrow` is a *statement*, not an *expression*.
Since the body of each case in a `switch expression` must be an *expression*, `rethrow` is not allowed there.

Example:

```dart
void main() {
  try {
    throw Exception('fail');
  } catch (e) {
    var result = switch (e) {
      Exception() => "caught",
      Error() => throw e, // Works, but analyzer suggests using `rethrow`.
      _ => rethrow,       // Compile-time error: "Undefined name 'rethrow'"
    };
    print(result);
  }
}
```

* `throw e` works because `throw` is an **expression**.
* `rethrow` fails with *Undefined name 'rethrow'* because it is a **statement**.

## Problem

This leads to a confusing situation:

* Analyzer warns: *"Use 'rethrow' to rethrow a caught exception."*
* But in a `switch expression`, using `rethrow` is not possible.

So developers face a conflict:

* Either use `throw e` (losing the original stack trace).
* Or avoid switch expressions and fall back to switch statements.

## Possible directions

1. **Allow `rethrow` in expression contexts** (language/spec change, requires discussion).
2. **Update analyzer/linter messages** to explain why `rethrow` is not available in `switch expressions`.
3. **Documentation update**: show recommended workarounds (e.g. use switch *statements* if `rethrow` is required).

---

This document captures the current state and motivates further discussion.
