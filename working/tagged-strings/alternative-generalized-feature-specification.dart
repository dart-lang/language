# Dart Tagged Strings (generalized)

Author: @lrhn<br>Version: 1.0

## Problem statement

String interpolations are awesome. With [interpolation elements][] allowing `if`/`for`/etc.-elements inside an interpolation, maybe even comma separated expressions, string interpolations will be even better!

Sometimes you need to build something that is not a string, but where a string template with embedded values would be a useful format, but string interpolations can only create strings.

Taking inspiration from other languages, this is a proposal for “tagged strings”, or “tagged interpolations”, which is a language feature that allows something looking like a string literal or string interpolation to be interpreted by user code by prefixing it with a value, called the “tag” because it’s often a single identifier, and that expressions’ value get access to the individual string parts and expression values of the interpolation expression.

This is a *generalization* of [Munificent’s feature specification](feature-specification.md "Feature specification"), allowing *interpolation elements* inside interpolations, and allowing any (primary) *expression* as the tag.

[interpolation elements]: https://github.com/dart-lang/language/issues/1478 "String interpolation elements issue"

## Proposal

### Grammar

The grammar is updated by moving some of the the current `<primary>` productions to `<primaryOrTag>` which can produce everything the current `<primary>` can, except `<literal>` and `<functionExpression>`, and then adding the following new `<primary>` production:

```ebnf
<primaryOrTag> ::= 
    <thisExpression>
  | `super' <unconditionalAssignableSelector>
  | `super' <argumentPart>
  | <identifier>
  | <newExpression>
  | <constObjectExpression>
  | <constructorInvocation>
  | `(' <expression> `)'

<primary> ::= 
    <primaryOrTag>
  | <functionExpression>
  | <literal>
  | <primaryOrTag> <stringLiteral>   -- aka. tagged string.
```

_(This avoids adjacent `<stringLiteral>`s because a `<stringLiteral>` can itself consist of multiple `<singleLineString>` and/or `<multiLineString>`s, so adjacent `<stringLiteral>`s would be ambiguous.)_

This updated grammar is incremental and  unambiguous. A string literal can occur *as* a `<primary>` or *after* one non-string-literal. The former is the same as the existing grammar, and the latter is not allowed in the existing grammar, so all new syntax was previously invalid syntax, and all existing syntax is still valid and parses the same way.

### Static semantics

All `<primary>` productions that were also allowed by the existing grammar are parsed and treated the same way as the corresponding existing production.

Type inference of `e s` where `e` is a `<primaryNoString>` and `s` is a `<stringLiteral>`, in with context type scheme `C` proceeds as follows:

* Perform horizontal type inference on `e` and the interpolation elements, `e1` … `en`, of `s`, *as if* inferring types for an invocation `apply(e, [e1, …, en])` in context `C` where `apply` has signature

  ```dart
  R Function</*out*/ R, /*in*/ E>(StringInterpolation<R, E> e, List<E> es)
  ```

  _We want the type of elements to be able to affect inference of the string interpolation object, and vice versa, so we use the one kind of inference we have that allows inference direction to depend on available information._

* Let the elaborated expression `e'` with static type `S` be the type inference result for `e`, and elaborated elements `e1’`…`en’` with static element types `S1`…,`Sn` the type inference results for the elements `e1`…`en`. Let `R` and `E` be the inferred type arguments to `apply`.

* It’s a compile-time error if *S* is not a subtype of `StringInterpolation<Object?, Object?>`. (If `e` would have type `dynamic`, type inference has downcast it to `StringInterpolation<R1, E1>` for some types `R1` an `E1`).

* If `S` implements `StringInterpolation<R1, E1>` for some types `R1`, `E1`, then let `R1`, `E1` be those types.

* Otherwise `S`  is a bottom type. Then let let `E1` be `dynamic` and `R1` be `Never`.

* It’s a compile-time error if any of the types `S1`…`Sn` is not a subtype of `E1`.

* The inference result of `e s` is `e' s'` where `s'` is `s` with each interpolation expression `e1`…,`en` replaced by the corresponding elaborated expression `e1'`…`en'`. The static element type of `s'` is `U`, and with static type *T*, which is `R1` coerced to `C` if necessary.

### Runtime semantics

Evaluation of `e s` where `e` has static type `S` proceeds as follows:

* Evaluate `e` to a value *v*. By soundness `S` must not be a bottom type, so it implements `Interpolation<R1, E1>` for some types `R1` and `E1`, and therefore _v_ must implement `Interpolation<R2, E2>` with `R2` \<: `R1` and `E2` \<: `E1` (the latter only until we get variance annotations, then the direction switches.)

* For each single-line or multi-line string, `si`, in `s` in source order:

  1. Let *p0* be the start of the string literal. _For a multi-line string with only whitespace on the first line, that position is at the start of the next line._

  2. Let *p1* be the position of the `$` of the first interpolation in the string literal after *p0*, or the end of the string literal if there are no further string interpolations _(always the case for a raw string)_.

  3. If *p0* \< *p1*:

     * Let *s* be a string containing the characters denoted by the string literal content from *p0* to *p1*.
     * Invoke the `addString` member of *v* with the value *s*.

  4. If *p1* is not at the end of the string

     * Let *ei* be the interpolation element of the interpolation starting at *p1*.

     * Execute *ei* as an element, and for each yielded value *w*, invoke the `add` member of *v* with the value *w*.

     * Let *p0* be the position after the interpolation starting at *p1*. _The position after the identifier or closing `}`._
     * Goto 2.

* Invoke the `close` method of *v* with no arguments, and let *r* be the returned value.

* Then `e s` evaluates to *r*.

### Support class

This supposes an interface definition in the platform libraries (in `dart:core` most likely):

```dart
abstract interface class StringInterpolation</*out*/ R, /*in*/ E> {
  void addString(String string);
  void add(E value);
  R close();
}
```

An instance of this class should support having `addString` and `add` invoked any number of times in any order, and then a final invocation of `close` should produce a result from those strings and values. Any further calls after calling `close` are allowed to fail.

## Alternatives and considerations

### Formatting

I would suggest formatting a tagged string interpolation with no space between the tax and the string.

```dart
var x = color"FF8080";
var y = hex"DEADBEEF";
Uint8List z = utf8"☃️";
var w = Template<B>(defaultB: const B(42))"this is a template<${inject<B>()}> or something";
```

(This shows that one might want some character `Encoding`s to implement `StringInterpolation`. Or maybe other types that can accept a `String` in some way. Not all of them make sense, but the ones that are mainly conversions, and where it may make sense to apply them to a literal, might.)

In general, being a primary expression suggests not having internal whitespace.

### Can’t use `r` as tag.

Since `r”a”` is a single string, the identifier `r` cannot be used as a tag name without parentheses. Parentheses are allowed since it’s a primary expression, so `(r)"tag${content}"` will work.

### Not using a live object as tag

Instead of using the active interpolation as the “tag” value, which likely implies the “tag name” being a getter producing a new value for each use, a tag could be a constant with a factory function creating the actual collector object.

Nothing much is gained from that, it just postpones the allocation and introduces an extra interface, and an extra step at each tag interpolation.

On the other hand, asking for a method instead of an interface to create the live value collector object *could* allow an extension method on a non-traditional object:

```dart
extension Nyah on int {
  StringBuilder<int, int> get stringBuilder => _IntEval();
}
void main() {
  print(5"+${4}-${3}"}); // Prints 6.
}
```

Not sure anything *good* can come from allowing that.

### Providing an iterator instead of calling `add` methods

Rather than calling `add` methods on a live object, a single method could be called with an iterable that iterates through the strings and values of the interpolation, then the tag implementation can iterate as far as it needs.

That would complicate the evaluation massively, requiring the implementation to be suspendable after each value of an element. It would effectively introduce iterable literals as `iter"${...[ iterable elements here ]...}"`.

The only extra power is the ability to stop evaluation early, which is likely just making code less readable. Neither list literals nor string interpolations are lazy, we don’t need it here either.

###  Evaluating all interpolation elements before creating the tag.

Instead of an iterator, the context could eagerly evaluate all the values, then pass a list of strings and values as a single argument.

That requires extra allocation that isn’t necessarily needed. If a tag implementation wants a list of all elements and strings, it can build one. If it doesn’t, it can choose not to. By the interpolation not doing anything other than providing the string or value *as soon as possible*, the tag implementation has maximal control and minimal overhead.

### Works with async

If the function is `async`, then any interpolation element expression can `await`. That just works, the tag implementation doesn’t do anything when not invoked, it can wait as long as it takes for the next value or a `close`.

It’s not possible to have a delay inside an interpolation *other* than by using `await`.

### The tag implementation cannot be async

The `add` and `addString` methods are not asynchronous. There is no way to *delay* the execution of a string interpolation, once it starts, it runs to completion unless the element expressions themselves use `await`. If combining the values requires time, the result type must itself be a future, a `StringInterpolation<Future<R>, E>`.

### Allowing more than just identifiers as tags

By allowing many non-literal primary expression as the “tag”, a some mistakes that would be syntax errors become type errors instead. Forgetting a comma in a list can leave `Banana() "banana"`, which gets the error “A 'Banana' value does not implement ’StringInterpolation’ .”. That *is* worse than the current “Expected to find ','.”

On the other hand, we could probably allow `<primary> <selector+> <stringLiteral>`, making a string literal a *selector*

It can probably safely be restricted to not allow literals or function expressions. Those are incapable of implementing `StringInterpolation` anyway.

### Similarity to “tagged collections”

If Dart introduces a way to generalize collection literals, then the syntax *could* be something like;

```dart
var c1 = MyCollection<int>(capacity: 24){1, for (var i = 2; i <= 23; i+= 3) i, 26};
// or
var c2 = myCollectionTag{1, 2, ...more};
```

That would be similar to the the format for tagged string interpolations containing elements. (And without tagged collections, one could do `var c3 = myCollection"${1, 2, …more}";` and get away with it. Which suggests that maybe the two features should be developed together.)

## Versions

* 1.0 (2024-06-27): Initial version







