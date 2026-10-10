module
public import DartLang
public import DartSemantics.HeadStep
public import DartSemantics.Language
public import DartSemantics.Resolve
public import DartSemantics.State

/-!
# The Dart run-time semantics

This library will hold a small-step semantics for Dart (or for the `LoweredExpr`s that flow
analysis produces), built on iris-lean, the Lean port of the Iris separation-logic framework,
together with an interpreter for it and a program logic for reasoning about programs.

The syntax and the type representations that it shares with flow analysis are in `DartLang`.
-/
