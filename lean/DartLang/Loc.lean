module

namespace DartLang

/--
A heap location: the address of a cell in the run-time heap. Locations are allocated sequentially
and never freed, so a location is the index of its cell.

Flow analysis never produces locations; they appear in `LoweredExpr`s only at run time (see
`LoweredExpr.varAt`).

**Local variables live in heap cells.** The semantics has no stack frames or environments.
Instead, declaring a local variable allocates a fresh heap cell for it, and replaces each
reference to the variable in its scope with a reference to the cell's location. Reads and writes
of the variable are then reads and writes of the cell. Each time a declaration is executed, it
allocates a new cell, so (once the semantics has function calls and loops) each call of a function,
and each iteration of a loop, gets its own cells for the variables it declares, and closures
created in different calls or iterations capture different cells. This is the usual way to model
local state in Iris-based semantics (it's how Iris's HeapLang handles mutable state), and it has
several advantages:
- Stack frames are an implementation technique of particular back ends, not part of Dart's
  meaning, so a precise definition of Dart doesn't need them.
- Variables captured by closures need no separate treatment: a closure created in the variable's
  scope refers to the same cell, and so shares it, as Dart requires. A semantics with stack frames
  would have to distinguish captured variables (which outlive their frame) from uncaptured ones.
- The program logic reasons about a variable with the same separation-logic points-to assertion
  (`ℓ ↦ v`) as about any other heap cell, so owning a local variable and owning an instance
  variable work the same way.
-/
public structure Loc where
  /-- The index of the location's cell in the heap. -/
  n : Nat
  deriving Repr, BEq, DecidableEq, Hashable, Inhabited

public instance : LawfulBEq Loc where
  rfl := by intro ⟨n⟩; simp [BEq.beq, instBEqLoc.beq]
  eq_of_beq := by
    rintro ⟨n⟩ ⟨n'⟩
    simp [BEq.beq, instBEqLoc.beq]

end DartLang
