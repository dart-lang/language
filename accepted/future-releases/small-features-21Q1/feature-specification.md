# Dart "Small Features" 21Q1

## Changelog

- 2021-02-03: Initial version

## Specification
We have a [list](https://github.com/dart-lang/language/issues/1077) of smaller language enhancement features which are expected to be:

* Non-breaking.
* Localized (no expected cross-cutting concerns with other features).
* Already designed to a point where we expect no surprises.
* Fairly easy and cheap to implement (little-to-no back-end work expected).

For the first quarter of 2021, we schedule three of these:

1. Allow type arguments on annotations ([#1297](https://github.com/dart-lang/language/issues/1297)).
2. Allow generic function types as type arguments ([#496](https://github.com/dart-lang/language/issues/496)).
3. Allow `>>>` as an overridable operator ([#120](https://github.com/dart-lang/language/issues/120)).

Allowing type arguments for annotations removes an unnecessary historical restriction on annotation syntax, and the VM team have a vested interest in the feature for use in `dart:ffi`. This feature was chosen because of a pressing need for it.

Allowing generic functions as type arguments is a restriction originally introduced as a precautionary measure, because it wasn't clear that the type system wouldn't become undecidable without it. We don't *think* that's a problem, and it's been a tripwire for people writing, e.g., lists of generic functions, where the type inference would infer a type argument that the compiler then reported as invalid. This feature was chosen because it is related to the previous change, and is expected to be very minor in scope.

Reintroducing the `>>>` operator was intended for Dart 2.0, but was repeatedly postponed as not important. We do want it for the unsigned shift of integers, and it's been mostly implemented on some of our platforms already. This feature was chosen because it is already half-way implemented.

**Nothing new!** All the chosen changes remove non-orthogonal restrictions on existing features or introduce features analog to other existing features, which means that we do not expect to need a lot of new documentation or educational material. That leaves those who'd write such resources free to deal with the launch of null safety instead.

The changes, in more detail, are detailed below.

## Allow type arguments on annotations

We currently allow metadata to be a call to a constant constructor:

```dart
@Deprecated("Do not use this thing")
```

However, the *grammar* does not allow type arguments, meaning that it's not possible to write:

```dart
@TypeHelper<int>(42, "The meaning")
```

There is no technical reason for this restriction. It was just simpler, and probably didn't seem necessary at the time metadata was introduced. It does now.

The only change is in the grammar, from

```
<metadatum> ::= \gnewline{}
  <identifier> | <qualifiedName> | <constructorDesignation> <arguments>
```

to

```
<metadatum> ::= \gnewline{}
  <identifier> | <qualifiedName> | <constructorDesignation> <argumentPart>
```

The corresponding constructor invocation must still be valid, now including the type arguments.

The constructed constant, if accessible in any way, will contain the provided type arguments, exactly like if it had been created by a <code>\`const' \<constructorDesignation> \<argumentPart></code> production, and is canonicalized correspondingly.

The largest expected effort for this implementation is the analyzer adding a place to store the type arguments to its public AST. The remaining changes should be using existing functionality.

If type arguments are allowed and omitted, the types are inferred from the types of the arguments to the constructor, as for any other constant invocation. This already happens (checked in VM with `dart:mirrors`), so no change is necessary.

## Allow generic function types as type arguments

The language disallows generic function types as type arguments.

```dart
List<T Function<T>(T)> idFunctions; // INVALID
var callback = [foo<T>(T value) => value]; // Inferred as above, then invalid.
```

We remove that restriction, so a type argument *can* be a generic function type.

This requires no new syntax, and in some cases only the removal of a single check. There might be some platforms where the implementation currently assumes that generic function types cannot occur as the value of type variables (an proof-of-concept attempt hit an assert in the VM). Such assumptions will need to be flushed out with tests and fixed.

Because we already infer `List<T Function<T>(T)>` in the code above, this change will not affect type inference, it will just make the inferred type not be an error afterwards.

We do not expect the removal of this restriction to affect the feasibility of type inference. After all, it's already possible to have a generic function type occurring covariantly in a type argument, like `List<T Function<T>(T) Function()>`.

## Allow `>>>` as overridable operator

We reintroduce the `>>>` operator where it originally occurred in the Dart grammar (it's`\gtgtgt`):

```latex
<shiftOperator> ::= `\ltlt'
  \alt `\gtgtgt'
  \alt `\gtgt'
```

Because this makes `>>>` an `<operator>` and a `<binaryOpartor>`, it directly enables `#>>>` to be written a `Symbol` literal, and it allows declaring `operator >>>` as an instance member with a single positional argument. As for any other `<operator>`, you can do composite assignment as `x >>>= y`.

Further, the `Symbol` constructor must accept the string `">>>"` as argument and create a symbol equal to `#>>>` (identical if `const` invoked).

Some tests have already been committed, and the feature is currently under the `triple-shift` experiment flag.

Very little actual change is expected since the `>>>` operator behaves equivalently to `>>` and `<<`, so the same code paths should apply as soon as we are past lexical analysis.

When the operator has been enabled, we'll quickly (in the same dev-release series if possible, possibly early Q2) introduce:

```dart
int operator >>>(int shift);
```

on the `int` class, which will work similarly to `>>`, but will zero-extend instead of sign-extend. 

At that point, the `>>>` operator on `int` must be **valid in constant and potentially constant expressions**, so `0x40 >>> 3` is a compile-time constant expression with the value `8`, and `const C(int x) : y = 0xFFFFFFFF >>> x;` is valid (although potentially throwing if `x > 63`) as a constant constructor.

Backends may want to optimize this to use available bitwise shift operations (like `>>>` in JavaScript), and intrinsify the function if possible. This can be done at any later time, though.
