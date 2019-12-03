# Zero-cost Static Wrapper Types

Status: Strawman Proposal for discussion

An inspiration is Haskell [newtypes](https://wiki.haskell.org/Newtype).
Similar is the Rust [newtype pattern](https://doc.rust-lang.org/1.0.0/style/features/types/newtype.html).

This relates to what is proposed as [Static Extension Types](https://github.com/dart-lang/language/issues/42),
but differs in that the new type is statically completely separate from the type it wraps.

This proposal can be implemented as a kernel transformation.

## Motivation:

Consider the toy API:
```dart
Bytes generateKey() => ...;
/// [plainText] should always be padded.
/// [key] should be generated with [generateKey()]
Bytes encrypt(Bytes key, Bytes plainText) => ...
Bytes decrypt(Bytes key, Bytes encyption) => ...
Bytes pad(Bytes text) => ...
Bytes unpad(Bytes padded) => ...
```
This interface does not ensure `key` and `plaintext` is constructed correctly, or even that you 
don't mix them up.

Introducing wrapper types:
```dart
import 'raw.dart' as raw;

newtype Key wraps Bytes {
  RSAKey() : _value = raw.generateKey();
}

newtype PaddedPlainText wraps Bytes {
  PaddedPlainText(Bytes plainText) : _value = raw.pad(Bytes);
  Bytes unpadded() => raw.unpad(_value);
}

newtype Encryption wraps Bytes {
  // Constructor is private. Can only be constructed by encrypt.
  Encryption._(this._value);
}

Encryption encrypt(Key key, PaddedPlainText plaintext) => Encryption._(raw.encrypt(key._value, plaintext._value));
PaddedPlainText decrypt(Key key, Encryption key) => PaddedPlainText(raw.decrypt(key._value, key._value));
```

Now everything can only be plugged in the right place.

This could have been done with wrapper classes, but this feature is designed with the promise of 
erasing the wrapper types at runtime leaving no runtime overhead.

More motivation: 
- Providing self-documenting interfaces. 
- Maintaining invariants: using a wrapper around a list can ensure it stays sorted, or has
  heap-property. Non-negative integers, Escaped Strings...
- Low-overhead deserialization: provides a way of giving a typed interface to deserialized storage
  without wrapping in interface objects. (Think json, protobuf)
  (Disclaimer: This is the scratch I'm personally trying to itch).

## Syntax
We add the following construction to the grammar:
``` dart
newtype <identifier> wraps <typeParameter> {
  (<metadata> <classMemberDefinition>)*
}
```

The specifics are by no means set in stone. A few points I have considered though:
- I don't like the term `extension types` for this. These types specifically do not extend others.
- I prefer not to use `this` instead of `_value` for the implicit field. It would make it hard to
  reason about if you are referring to the wrappee or the wrapper. I would like a better name/syntax for 
  the concept though.

## Static semantics
```
newtype W wraps T {
  W() : _value = ... {}
  W.unsafe(this._value);

}
```

- Declares a new static type named `W`.
- `T` can be any type, it does not have to be a class. You could even wrap a `dynamic`.
- `W` is incompatible with any other type.  No implicit or explicit up or downcasts. This includes
  `Object` (I'm willing to discuss this last point :).
- `W` is not compatible with dynamic. You cannot do dynamic invocations on a `W` or store it in a 
  variable of type `dynamic`.
- methods, getters and constructors can refer to a pseudo-field called `_value`.
  This behaves as a final field of type `T` (ie any constructors in `W` must initialize it).
- methods can also refer to `this`. It will have static type `W`.
- You cannot declare fields in `W`.
- You cannot do `is W` (always a trivial question) or `as W` (forbidden).


These restrictions should ensure that we can do the lowering described in the next section.

## Runtime semantics

The runtime semantics can be seen as a lowering transformation.
- `W` gets lowered to `T` everywhere.
- A constructor gets lowered to a static method returning `_value` after running.
- All other methods can be lowered to static extension methods of `T`.

The intention is that the wrapper type completely disappears at runtime (Though see below).
 
## Generics
Wrapper types can take generic arguments.

Wrapper types can be used as generic arguments, they are erased as part of the lowering.

A `List<W>` is a `List<T>` at runtime. This unfortunately breaks the encapsulation that wrapper
types tries to enable:

```dart
newtype NonNegativeInt wraps int {
  NonNegativeInt(this._value) {
    if (_value < 0) throw ArgumentError();
  }
}

int leakValue<P>(P a) {return a as Int;}
  
P constructInvalidInstance<P>(int a) => a as P;

main() {
  NonNegativeInt p = constructInvalidInstance<NonNegativeInt>(-42);
  int a = leakValue<NonNegativeInt>(NonNegativeInt(42));
}
``` 
  
I don't see any way around this. But I think the proposed feature still provides value.

## Questions

### Infinite types
Do we allow:
```dart
newtype Infinite wraps List<Infinite> {}
```
?

### Debug-printing

Given an object `w` with static type `W` it seems tedious that you cannot `print(w)` because `W` is
incompatible with `Object`.

We could consider allowing string interpolation `'$w'` to invoke `w.toString()` if it defines such a
method.

### Code sharing

Two related wrapper types might want to share some implementation.
(eg. two different protobuf message types both wrapping the same underlying storage class might want
to declare the same `verify` method).

One could imagine some kind of mix-in mechanism for this. This has not been fleshed out.
We could probably get really far with just deferring to static methods. 

### Deriving methods from the wrappee

One could imagine a syntax for 'deriving' methods from the wrappee.

```dart
newtype Heap<T> wraps List<T> derive isEmpty {
}
```

would mean the same as:
```dart
newtype Heap<T> wraps List<T>{
  bool isEmpty() => _value.isEmpty();
}
```
