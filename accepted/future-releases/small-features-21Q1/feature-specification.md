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
2. Allow generic function types as type arguments and bounds ([#496](https://github.com/dart-lang/language/issues/496)).
3. Allow `>>>` as an overridable operator ([#120](https://github.com/dart-lang/language/issues/120)).

Allowing type arguments for annotations removes an unnecessary historical restriction on annotation syntax, and the VM team have a vested interest in the feature for use in `dart:ffi`. This feature was chosen because of a pressing need for it.

Allowing generic functions as type arguments and bounds is a restriction originally introduced as a precautionary measure, because it wasn't clear that the type system wouldn't become undecidable without it. We don't *think* that's a problem, and it's been a tripwire for people writing, e.g., lists of generic functions, where the type inference would infer a type argument that the compiler then reported as invalid. This feature was chosen because it is related to the previous change, and is expected to be very minor in scope.

Reintroducing the `>>>` operator was intended for Dart 2.0, but was repeatedly postponed as not important. We do want it for the unsigned shift of integers, and it's been mostly implemented on some of our platforms already. This feature was chosen because it is already half-way implemented.

**Nothing new!** All the chosen changes remove non-orthogonal restrictions on existing features or introduce features analog to other existing features, which means that we do not expect to need a lot of new documentation or educational material. That leaves those who'd write such resources free to deal with the launch of null safety instead.

The changes, in more detail, are detailed below.

## Allow type arguments on annotations

We currently allow metadata to be a call to a constant constructor:

```dart
@Deprecated("Do not use this thing")
```

However, it is not possible to pass type arguments to the constructor invocation:

```dart
@TypeHelper<int>(42, "The meaning")
```

There is no technical reason for this restriction. It was just simpler, and probably didn't seem necessary at the time metadata was introduced. It does now.

There is no change in the current grammar, it already allows the type arguments,
and we just need to stop reporting those type arguments as an error:

```
<metadatum> ::=
  <identifier> | <qualifiedName> | <constructorDesignation> <arguments>

<constructorDesignation> ::= ... |
  <typeName> <typeArguments> (‘.’ <identifier>)?
```

The constructed constant, if accessible in any way, will contain the provided type arguments, exactly like if it had been created by a <code>\`const' \<constructorDesignation> \<argumentPart></code> production, and is canonicalized correspondingly.

The largest expected effort for this implementation is the analyzer adding a place to store the type arguments to its public AST. The remaining changes should be using existing functionality.

If type arguments are allowed and omitted, the types are inferred from the types of the arguments to the constructor, as for any other constant invocation. This already happens (checked in VM with `dart:mirrors`), so no change is necessary.

## Allow generic function types as type arguments and bounds

The language disallows generic function types as type arguments and bounds.

```dart
late List<T Function<T>(T)> idFunctions; // INVALID.
var callback = [foo<T>(T value) => value]; // Inferred as above, then invalid.
late S Function<S extends T Function<T>(T)>(S) f; // INVALID.
```

We remove that restriction, so a type argument and a bound *can* be a generic function type.

This requires no new syntax, and in some cases only the removal of a single check. There might be some platforms where the implementation currently assumes that generic function types cannot occur as the value of type variables (an proof-of-concept attempt hit an assert in the VM). Such assumptions will need to be flushed out with tests and fixed.

Because we already infer `List<T Function<T>(T)>` in the code above, this change will not affect type inference, it will just make the inferred type not be an error afterwards.

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

## Mixed Mode Programs

Libraries using a language version prior to the introduction of these features (opted out libraries) 
interact with libraries using those features (opted in libraries) as follows.

In an opted out library:
* It is a compile-time error to declare an operator method named `>>>`, or to have `e1 >>> e2` as an expression.
* It is a compile-time error for an annotation constructor invocation to have an explicity type argument.
* It is a compile-time error to declare a type parameter with a generic function type (GFT) as bound.
* It is a compile-time error to use a GFT as a type argument anywhere. This includes:
    * Inferred types.
    * The implicit type arguments of an instantiated tear-off.
    * Types produced by instantiate to bounds.
    * Types produced by expanding references to type aliases into their aliased type.
    * The corresponding explicit extension invocation for an implicit extension invocation.
* It is *not* an error to refer to or use a symbol from an opted in library which uses a GFT as a type argument or bound.
  (That is, it's not an error to simply have an expression with a static type which includes GFT as a type argument or bound.)
* It is *not* an error to export a symbol from an opted in library which uses a GFT as a type argument or bound.

That is, there is no new expressiveness in an opted out library due to these features. 
Everything which was previously an error to write, explicitly or implicity, is still an error.

This does mean, since type parameter bounds are invariant, that if a class in an opted in library declares an instance
member with a GFT-bounded type parameter, an opted out library cannot implement that interface.
No existing classes declares such a bound, and changing the bound is a breaking change no matter what it's changed to, 
so that is not expected to be an issue. We have no plans to add GFT-bounds to existing platform library interfaces.
