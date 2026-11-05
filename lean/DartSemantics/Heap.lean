module
public import DartSemantics.State
public import Iris.Std.HeapInstances

/-!
# The heap as a finite map

The run-time heap is an array (see `State.heap`), which keeps the interpreter fast. iris-lean's
ghost heap (`gen_heap`) needs a lawful finite map instead. This file defines that view of the heap,
`State.toMap`, and the facts about it that the program logic uses.
-/

namespace DartSemantics

open DartLang Iris.Std

/-- Locations are ordered by their index, so that they can be keys of a tree map. -/
public instance Loc.instOrd : Ord Loc where
  compare ℓ₁ ℓ₂ := compare ℓ₁.n ℓ₂.n

public instance Loc.instTransOrd : Std.TransOrd Loc where
  eq_swap {ℓ₁ ℓ₂} := Nat.instTransOrd.eq_swap (a := ℓ₁.n) (b := ℓ₂.n)
  isLE_trans {ℓ₁ ℓ₂ ℓ₃} := Nat.instTransOrd.isLE_trans (a := ℓ₁.n) (b := ℓ₂.n) (c := ℓ₃.n)

public instance Loc.instLawfulEqOrd : Std.LawfulEqOrd Loc where
  eq_of_compare {ℓ₁ ℓ₂} h := by
    obtain ⟨n₁⟩ := ℓ₁
    obtain ⟨n₂⟩ := ℓ₂
    have : n₁ = n₂ := Std.LawfulEqOrd.eq_of_compare h
    rw [this]

variable {τ : Type}

local notation "Cell" => Cell (τ := τ)
local notation "State" => State (τ := τ)

/-- Finite maps from locations, the kind of map iris-lean's ghost heap is built on. -/
public abbrev LocMap := fun V => Std.ExtTreeMap Loc V compare

/--
The finite map that puts the cells `cs` at consecutive locations, starting at index `k`: `cs[0]`
at location `k`, `cs[1]` at location `k + 1`, and so on.
-/
@[expose]
public def listToLocMap (cs : List Cell) (k : Nat) : LocMap Cell :=
  match cs with
  | [] => ∅
  | c :: cs' => insert (listToLocMap cs' (k + 1)) ⟨k⟩ c

/--
Looking up location `ℓ` in `listToLocMap cs k`, which puts `cs[0]` at location `k`, `cs[1]` at
location `k + 1`, and so on: if `ℓ` comes before location `k` (`¬k ≤ ℓ.n`), there is no cell
there; otherwise the cell there is `cs[ℓ.n - k]`, or none if that's past the end of `cs` (indexing
using `[...]?` takes care of this).
-/
theorem get?_listToLocMap (cs : List Cell) (k : Nat) (ℓ : Loc) :
    get? (listToLocMap cs k) ℓ = if k ≤ ℓ.n then cs[ℓ.n - k]? else none := by
  induction cs generalizing k with
  | nil => simp [listToLocMap, LawfulPartialMap.get?_empty]
  | cons c cs ih =>
    simp only [listToLocMap]
    by_cases h : (⟨k⟩ : Loc) = ℓ
    · subst h
      rw [LawfulPartialMap.get?_insert_eq rfl]
      simp
    · rw [LawfulPartialMap.get?_insert_ne h, ih]
      have hn : k ≠ ℓ.n := fun e => h (by cases ℓ; simp_all)
      by_cases hk : k + 1 ≤ ℓ.n
      · have : ℓ.n - k = ℓ.n - (k + 1) + 1 := by omega
        simp [hk, show k ≤ ℓ.n by omega, this]
      · simp [hk, show ¬ k ≤ ℓ.n by omega]

/-- The heap, as a finite map from locations to cells. -/
@[expose]
public def State.toMap (σ : State) : LocMap Cell := listToLocMap σ.heap.toList 0

/-- The finite-map view of the heap agrees with `State.lookup`. -/
public theorem State.get?_toMap (σ : State) (ℓ : Loc) : get? σ.toMap ℓ = σ.lookup ℓ := by
  simp [State.toMap, get?_listToLocMap, State.lookup]

/-- The next location to be allocated isn't allocated yet. -/
public theorem State.lookup_fresh (σ : State) : σ.lookup σ.fresh = none := by
  simp [State.lookup, State.fresh]

/--
Allocating a cell `c` adds it at `σ.fresh` (`some c`), and leaves the other cells alone
(`σ.lookup ℓ`).
-/
public theorem State.lookup_alloc (σ : State) (c : Cell) (ℓ : Loc) :
    (σ.alloc c).lookup ℓ = if σ.fresh = ℓ then some c else σ.lookup ℓ := by
  obtain ⟨n⟩ := ℓ
  simp only [State.lookup, State.alloc, State.fresh, Loc.mk.injEq, Array.getElem?_push]
  split <;> split <;> simp_all

/--
Allocating a cell `c` is an insertion into the finite-map view of the heap, at `σ.fresh`
(`insert σ.toMap σ.fresh c`).
-/
public theorem State.toMap_alloc (σ : State) (c : Cell) :
    (σ.alloc c).toMap = insert σ.toMap σ.fresh c := by
  apply LawfulPartialMap.equiv_iff_eq.1
  intro ℓ
  rw [State.get?_toMap, State.lookup_alloc, LawfulPartialMap.get?_insert, State.get?_toMap]

/-- The state of a program that hasn't allocated anything. -/
public instance State.instInhabited : Inhabited State := ⟨State.empty⟩

end DartSemantics
