module
public import DartLang.Lowered

/-!
# The run-time state

The state of a running program: for now, just the heap.
-/

namespace DartSemantics

open DartLang

variable {τ : Type} [Γ : DartTypeRepr τ]

local notation "Value" => Value (τ := τ)

/--
The contents of a heap cell.

A cell is either the storage for a variable (a local variable, or an instance variable of an
object), or an object's own cell, which records its class and where its instance variables are
stored. Keeping instance variables in cells of their own means that the program logic can reason
about each instance variable separately, with the same points-to assertion as for a local
variable.

This type is separate from `Value`: values never refer to cells, only to locations.
-/
public inductive Cell where
  /--
  The storage for a variable whose value is `v`. The variable is either a local variable or an
  instance variable of an object (see `object`).
  -/
  | val (v : Value)
  /--
  A local variable that has been declared but not yet assigned. Only variables whose type isn't
  nullable start out this way; the others are initialized to the null object.
  -/
  | uninit
  /--
  An object (an instance of a class), whose dynamic type is `dynamicType`. Its instance variables
  are stored in other cells: `fields` maps the name of each instance variable to its cell's
  location.
  -/
  | object (dynamicType : τ) (fields : List (String × Loc))
  deriving Repr, BEq

local notation "Cell" => Cell (τ := τ)

/--
The state of a running program.

This is a structure, rather than just a heap, so that more components can be added as the
semantics grows (for example, the queue of pending tasks that asynchronous code needs).
-/
public structure State where
  /--
  The heap: the cell at location `ℓ` is `heap[ℓ.n]`. Cells are allocated sequentially and never
  freed, so the heap is an array that only grows. Allocating a cell is a `push`, which keeps the
  interpreter fast (provided the state is used linearly; see `Interp.primStep`).
  -/
  heap : Array Cell
  deriving Repr

local notation "State" => State (τ := τ)

/-- The state of a program that hasn't allocated anything. -/
@[expose]
public def State.empty : State := ⟨#[]⟩

/-- The cell at location `ℓ`, if it has been allocated. -/
@[expose]
public def State.lookup (σ : State) (ℓ : Loc) : Option Cell := σ.heap[ℓ.n]?

/-- The location that the next allocation will use. -/
@[expose]
public def State.fresh (σ : State) : Loc := ⟨σ.heap.size⟩

/-- Allocate a new cell, at location `σ.fresh`, holding `c`. -/
@[expose]
public def State.alloc (σ : State) (c : Cell) : State := { σ with heap := σ.heap.push c }

/--
The dynamic type of value `v`, in the specification's sense: the class of the object that `v`
represents.

The dynamic type of an exception object (`Value.error`) isn't defined yet. The specification
leaves its class unspecified, except that it implements `TypeError`, and the type representation
has no type for that yet. Nothing in the subset of Dart modeled so far can inspect an exception
object, since there is no way to catch one. A captured continuation (`Value.cont`) isn't a Dart
object, so it has no dynamic type.
-/
@[expose]
public def State.dynamicType (σ : State) : Value → Option τ
  | .null => some Γ.Null
  | .bool _ => some Γ.bool
  | .obj ℓ =>
    match σ.lookup ℓ with
    | some (.object T _) => some T
    | _ => none
  | .error _ => none
  | .cont _ => none

omit Γ in
/-- A newly allocated cell holds what it was allocated with. -/
@[simp]
public theorem State.lookup_alloc_fresh (σ : State) (c : Cell) :
    (σ.alloc c).lookup σ.fresh = some c := by
  simp [State.lookup, State.alloc, State.fresh]

end DartSemantics
