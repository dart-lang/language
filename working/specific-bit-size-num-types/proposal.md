
# Dart Number Types with specific bit size

Author: xzzulz@gmail.com<br>Version: 1.0

## Motivation

Dart number types are simple. Making the language easy to use. 

However, in many use cases, these are not enough. Many scenarios require number types of specific bit-size. To make Dart useful in these scenarios, additional number types are needed. This can be solved. Adding the usual C number types.

By preserving the current easy to use number types, the language will continue to be easy to use. The extra number types would be relevant only for scenarios where the additional complexity is required. The documentation will keep focus, on the current (simple) number types.

Also this would allow better interoperability with C, and other languages. And would make Dart useful in many use cases. That currently is not covering.

## Current situation

Simple number types:

```dart

  num a = 3;
  int b = 5;
  double c = 7.0;
  
```

## Proposal

The additional number types would be bit-size scpecific versions of: 

* integers
* integers, unsigned
* floats

```dart

  f16 a = 3.0;
  f32 b = 5.0;
  f64 c = 7.0;
 
  i16 d = 3;
  i32 e = 3;
  i64 f = 3;
  u16 g = 3;
  u32 h = 3;
  u64 i = 3;
  
  i128 j = 3;
  u128 k = 3;

```

## Versions

1.0: Initial version

