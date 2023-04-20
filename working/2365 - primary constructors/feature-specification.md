# Primary Constructors

Author: Erik Ernst

Status: Draft

Version: 1.0

Experiment flag: primary-constructors

This document specifies _primary constructors_. This is a feature that allows
one constructor and a set of instance variables to be specified in a concise
form in the header of the declaration. In order to use this feature, the given
constructor must satisfy certain constraints, e.g., it cannot have a body.

One variant of this feature has been proposed in the [struct proposal][],
several other proposals have appeared elsewhere, and prior art exists in
languages like [Kotlin][kotlin primary constructors] and Scala (with
specification [here][scala primary constructors] and some examples
[here][scala primary constructor examples]). Many discussions about the 
feature have taken place in github issues marked with the 
[primary-constructors label][].

[struct proposal]: https://github.com/dart-lang/language/blob/master/working/extension_structs/overview.md
[kotlin primary constructors]: https://kotlinlang.org/docs/classes.html#constructors
[scala primary constructors]: https://www.scala-lang.org/files/archive/spec/2.11/05-classes-and-objects.html#constructor-definitions
[scala primary constructor examples]: https://www.geeksforgeeks.org/scala-primary-constructor/
[primary-constructors label]: https://github.com/dart-lang/language/issues?q=is%3Aissue+is%3Aopen+primary+constructor+label%3Aprimary-constructors

## Motivation

Primary constructors is a conciseness feature. It does not provide any new
semantics at all, it just allows us to express something which is already
possible in Dart using a less verbose notation.

TODO: write several examples.

## Specification

### Syntax



### Static processing



### Changelog

1.0

* First version of this document released.
