# Instructions for agents working on the Lean formalization

Read [`README.md`](README.md) first: it describes the goals, the layout, and how to build and test
(`lake build`, `lake test`). This file collects the conventions that every change in this directory
must follow, so that they are maintained as the code grows.

## Audience

The code is maintained by the Dart team, whose members aren't necessarily Lean or Iris experts (see
[Documentation conventions](README.md#documentation-conventions)). Write comments for a Dart
engineer: explain Lean 4, Mathlib and iris-lean idioms, syntax and tactics that a specialist would
find obvious.

## Doc comments

- **Every declaration has a doc comment** (`/-- … -/`), theorems included. A group of trivial
  helper lemmas may share one comment above the group instead.
- **Every file has a module doc** (`/-! … -/`) after its imports, explaining what the file is for,
  and any design decisions a reader needs to understand it.
- **A theorem's doc comment states the theorem in English, with the Lean terms in parentheses**
  after each hypothesis and each part of the conclusion, so that a reviewer can check that the
  theorem says what its documentation claims. Refer to named hypotheses by name. For example:

  ```lean
  /--
  The run-time subtype check has at most one answer: if it answers both `b₁` (`h₁`) and `b₂` (`h₂`),
  they're the same (`b₁ = b₂`).
  -/
  public theorem rtSub_unique {τ : Type} [DartRuntimeTypeRepr τ] {S T : τ} {b₁ b₂ : Bool}
      (h₁ : RtSub S T b₁) (h₂ : RtSub S T b₂) : b₁ = b₂ := by
  ```

- **Long statements become bulleted lists**: the conclusion, then "if:", then one bullet per
  hypothesis (ending in `;`, with `and` before the last).
- **Don't pad trivial statements.** If the English already is the Lean term (for example,
  "`isSubtype` is reflexive (`T.isSubtype T = true`)"), one short sentence is enough.
- **Keep doc comments in sync with the code, in the same commit.** When a change adds, removes or
  renames a parameter or hypothesis, or changes what a theorem says, update its doc comment (and
  any module doc or README text that describes it). A doc comment must only mention names that
  exist in the declaration it documents.
- **Describe what exists.** Don't describe the model as lacking a feature it now has. Phrases like
  "not yet" or "until the semantics has …" are for features that are really still missing.

## Terminology

Follow the terminology of the language specification (for example: dynamic type, instance variable,
completes normally, null object, cast expression, is-expression). In addition:

- a value *satisfies* a type `T` if its dynamic type is a subtype of `T` ("is a subtype of" is kept
  for the relation between two types);
- a type representation, or other structure, *obeys* laws (for example, the laws that a type
  class requires of its instances).

Files that introduce their own terms define them in their module docs. Use those terms
consistently, and add new ones there (not ad hoc in individual doc comments).

## Mechanics

- A doc comment goes before the declaration's attributes (`/-- … -/` then `@[simp]`), not after
  them, which doesn't parse. It may go after `omit … in`.
- Lines are at most 100 characters long. Count characters, not bytes: much of the code uses Unicode
  symbols.
- No `sorry`, `admit` or `axiom`.
- `lake build` and `lake test` must pass after every commit, not just at the end of a series.
