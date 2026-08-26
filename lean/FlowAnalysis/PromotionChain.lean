module
import Aesop
import Batteries.Data.List.Basic
import Batteries.Data.List.Lemmas
public meta import FlowAnalysis.SimpleTypes
public import FlowAnalysis.Types
import Mathlib.Tactic.Order

namespace FlowAnalysis

-- Allows the use of `<+` notation for `List.Sublist`.
open scoped List

section

variable {τ : Type} [DartTypeRepr τ]

/-- A list of types `c` is a promotion chain iff, for all `i < c.length - 1`, `c[i + 1] < c[i]`. -/
public def isPromotionChain (c : List τ) : Prop :=
    ∀ i (h : i < c.length - 1), c[i + 1] < c[i]

namespace isPromotionChain

/--
Equivalent formulation of `isPromotionChain` in terms of Lean's built-in notation of a chain (which
is defined recursively, so it's a bit more convenient to use in proofs).
-/
theorem iff_isChain (c : List τ) :
    isPromotionChain c ↔ c.IsChain (fun T U => U < T) := by
  rw [isPromotionChain, List.isChain_iff_getElem]
  constructor
  · intro h i hi; apply h; omega
  · intro h i hi; apply h

lemma iff_pairwise (c : List τ) :
    isPromotionChain c ↔ c.Pairwise (fun T U => U < T) := by
  rw [iff_isChain, List.isChain_iff_pairwise]

/-- Equivalently, `c` is a promotion chain iff, for all `0 ≤ i < j < c.length`, `c[j] < c[i]`. -/
theorem iff_pairwise_getElem (c : List τ) :
    isPromotionChain c ↔ ∀ i j (hij : i < j) (hj : j < c.length), c[j] < c[i] := by
  rw [iff_pairwise, List.pairwise_iff_getElem]
  constructor
  · intro h i j hij hj; apply h; assumption
  · intro h i j hi hj hij; apply h; assumption

/-- The empty list is a promotion chain. -/
@[simp]
theorem empty : isPromotionChain ([] : List τ) := by
  simp [isPromotionChain]

/-- A list with just one element is a promotion chain. -/
@[simp]
theorem single : ∀ T : τ, isPromotionChain [T] := by
  simp [isPromotionChain]

/-- The tail of a promotion chain is also a promotion chain. -/
theorem tail_valid {ts : List τ} : isPromotionChain ts → isPromotionChain ts.tail := by
  simp [iff_isChain]
  intro h
  cases ts
  case nil => simp
  case cons T ts' => exact List.IsChain.of_cons h

/-- The head of a valid promotion chain is a strict supertype of every type in the tail. -/
lemma head_bounds {T : τ} {ts : List τ} (hvalid : isPromotionChain (T::ts)) :
    ∀ T', T' ∈ ts → T' < T := by
  simp [iff_pairwise] at hvalid
  aesop

/--
Any sublist of a promotion chain is also a promotion chain.

In the spec we use the term `subsequence` since `sublist` in programming usually implies contiguity.
We use the term `sublist` here to match Lean's terminology.
-/
public theorem sublist {ts₁ ts₂ : List τ} (hsublist : ts₁ <+ ts₂) (hvalid₂ : isPromotionChain ts₂) :
    isPromotionChain ts₁ := by
  simp [iff_pairwise] at hvalid₂ ⊢
  apply List.Pairwise.sublist hsublist
  assumption

end isPromotionChain

/--
For convenience, define `PromotionChain` as a subtype of `List τ`.
-/
public abbrev PromotionChain := {ts : List τ // isPromotionChain ts}

local notation "PromotionChain" => PromotionChain (τ := τ)

namespace «PromotionChain»

/-- Extensionality: promotion chains may be proven equal by proving their lists equal. -/
public theorem ext {c₁ c₂ : PromotionChain} : c₁.val = c₂.val → c₁ = c₂ := by
  intro h; apply Subtype.ext; assumption

/-- The empty promotion chain. -/
public def empty : PromotionChain := ⟨[], by simp⟩

public def drop (n : Nat) (c : PromotionChain) :
    PromotionChain := .mk (c.val.drop n) $ by
  suffices h : c.val.drop n <+ c.val by apply isPromotionChain.sublist h c.property
  exact List.drop_sublist n c.val

@[simp]
public theorem drop.val {n : Nat} {c : PromotionChain} :
    (c.drop n).val = c.val.drop n := by rfl

public instance instEmptyCollection : EmptyCollection (PromotionChain) where
  emptyCollection := empty

@[simp]
public theorem eq_empty {h : isPromotionChain []} : (⟨[], h⟩ : PromotionChain) = ∅ :=
  by rfl

@[simp]
public theorem empty_types : (∅ : PromotionChain).val = [] := by rfl

public theorem empty_if_empty_types {c : PromotionChain} :
    c.val = [] → c = ∅ := by
  intro h; apply ext; simp_all

/-- A promotion chain containing a single type. -/
public def single (T : τ) : PromotionChain := ⟨[T], by simp⟩

@[simp]
public theorem single_types {T : τ} : (single T).val = [T] := by rfl

/-- A promotion chain `c` is strictly bounded by `T` iff `T::c` is a promotion chain. -/
public def strictlyBoundedBy (c : PromotionChain) (T : τ) : Prop := isPromotionChain (T::c)

@[expose]
public def joinPromotedTypes (ts₁ ts₂ : List τ) : List τ :=
  match ts₁, ts₂ with
    | T₁::ts₁', T₂::ts₂' => if T₁ = T₂ then
        T₁ :: joinPromotedTypes ts₁' ts₂'
      else match decide (T₁ ≤ T₂), decide (T₂ ≤ T₁) with
        | true,  true  => joinPromotedTypes ts₁' ts₂'
        | true,  false => joinPromotedTypes (T₁::ts₁') ts₂'
        | false, true  => joinPromotedTypes ts₁' (T₂::ts₂')
        | false, false => []
    | _, _ => []

@[simp]
theorem joinPromotedTypes.idempotent (ts : List τ) :
    joinPromotedTypes ts ts = ts := by
  induction ts <;> simp [joinPromotedTypes]
  case cons T ts' ih => assumption

@[simp]
public theorem joinPromotedTypes_left_empty {ts : List τ} :
    joinPromotedTypes [] ts = [] := by
  simp [joinPromotedTypes]

@[simp]
public theorem joinPromotedTypes_right_empty {ts : List τ} :
    joinPromotedTypes ts [] = [] := by
  simp [joinPromotedTypes]

theorem joinPromotedTypes.commutative (ts₁ ts₂ : List τ) :
    joinPromotedTypes ts₁ ts₂ = joinPromotedTypes ts₂ ts₁ := by
  (cases ts₁ <;> try simp); case cons T₁ ts₁' =>
  (cases ts₂ <;> try simp); case cons T₂ ts₂' =>
  simp [joinPromotedTypes]
  by_cases T₁ = T₂
  case pos heq => subst heq; simp; apply commutative
  case neg hne =>
  simp [hne, Ne.symm hne]
  by_cases T₁ ≤ T₂ <;> by_cases T₂ ≤ T₁ <;> simp_all <;> apply commutative

instance joinPromotedTypes.instCommutative :
    Std.Commutative (joinPromotedTypes (τ := τ)) where
  comm := joinPromotedTypes.commutative

@[simp]
lemma joinPromotedTypes_sublist_left {ts₁ ts₂ : List τ} :
    joinPromotedTypes ts₁ ts₂ <+ ts₁ := by
  cases ts₁ <;> try simp_all
  case cons T₁ ts₁' =>
  cases ts₂ <;> try simp_all
  case cons T₂ ts₂' =>
  simp [joinPromotedTypes]
  by_cases T₁ = T₂
  case pos heq => simp [heq]; apply joinPromotedTypes_sublist_left
  case neg hne =>
  simp [hne]
  by_cases T₂ ≤ T₁
  case pos hge =>
    simp [hge]
    by_cases h : T₁ ≤ T₂ <;> simp [h] <;> calc
      _ <+ ts₁' := by apply joinPromotedTypes_sublist_left
      _ <+ T₁ :: ts₁' := by simp
  case neg hnotGe =>
    simp [hnotGe]
    by_cases T₁ ≤ T₂
    case pos hle => simp [hle]; apply joinPromotedTypes_sublist_left
    case neg hnotLe => simp [hnotLe]

@[simp]
lemma joinPromotedTypes_sublist_right {ts₁ ts₂ : List τ} :
    joinPromotedTypes ts₁ ts₂ <+ ts₂ := by
  cases ts₁ <;> try simp_all
  case cons T₁ ts₁' =>
  cases ts₂ <;> try simp_all
  case cons T₂ ts₂' =>
  simp [joinPromotedTypes]
  by_cases T₁ = T₂
  case pos heq => simp [heq]; apply joinPromotedTypes_sublist_right
  case neg hne =>
  simp [hne]
  by_cases T₂ ≤ T₁
  case pos hge =>
    simp [hge]
    by_cases T₁ ≤ T₂
    case pos hle => simp [hle]; calc
      _ <+ ts₂' := by apply joinPromotedTypes_sublist_right
      _ <+ T₂ :: ts₂' := by simp
    case neg hnotLe => simp [hnotLe]; apply joinPromotedTypes_sublist_right
  case neg hnotGe =>
    simp [hnotGe]
    by_cases T₁ ≤ T₂
    case pos hle => simp [hle]; calc
      _ <+ ts₂' := by apply joinPromotedTypes_sublist_right
      _ <+ T₂ :: ts₂' := by simp
    case neg hnotLe => simp [hnotLe]

theorem isPromotionChain_join {ts₁ ts₂ : List τ} :
    isPromotionChain ts₁ → isPromotionChain ts₂ →
    isPromotionChain (joinPromotedTypes ts₁ ts₂) := by
  intro hvalid₁ hvalid₂
  apply isPromotionChain.sublist
  case hsublist => exact joinPromotedTypes_sublist_left
  case hvalid₂ => assumption

public def join (c₁ c₂ : PromotionChain) :
    PromotionChain :=
  let ts := joinPromotedTypes c₁.val c₂.val
  have hvalid : isPromotionChain ts := by
    refine isPromotionChain_join c₁.property c₂.property
  ⟨ts, hvalid⟩

@[simp]
public theorem join_idempotent (c : PromotionChain) :
    c.join c = c := by
  simp [join]

@[simp]
public theorem join.types {c₁ c₂ : PromotionChain} :
    (c₁.join c₂).val = joinPromotedTypes c₁.val c₂.val := by
  simp [join]

/-- The join operation is idempotent (`join c c = c`). -/
public instance instIdempotentOp_join :
    Std.IdempotentOp (join (τ := τ)) where
  idempotent := join_idempotent

@[simp]
public theorem join_left_empty :
    ∀ c : PromotionChain, (∅ : PromotionChain).join c = ∅ := by
  rintro ⟨ts, hvalid⟩
  simp [join]

@[simp]
public theorem join_right_empty : ∀ c : PromotionChain, c.join ∅ = ∅ := by
  rintro ⟨ts, hvalid⟩
  simp [join]

lemma bounded_skip_right {ts₁ ts₂' : List τ} {T₂ : τ}
    (hbound : ∀ U, U ∈ ts₁ → U < T₂) :
    joinPromotedTypes ts₁ (T₂ :: ts₂') = joinPromotedTypes ts₁ ts₂' := by
  cases ts₁
  case nil => simp
  case cons T₁ ts₁' =>
    specialize hbound T₁ (by simp)
    simp [joinPromotedTypes.eq_1, show T₁ ≠ T₂ by order, show T₁ ≤ T₂ by order,
      show ¬T₂ ≤ T₁ by order]

/--
Equivalent formation of joinPromotedTypes, to match the current implementation. TODO(paulberry):
make the implementation align with the definition.
-/
public theorem joinPromotedTypes.equiv {T₁ T₂ : τ} {ts₁' ts₂' : List τ}
    (hvalid₁ : isPromotionChain (T₁::ts₁')) :
    joinPromotedTypes (T₁ :: ts₁') (T₂ :: ts₂') =
      if T₁ = T₂ then T₁ :: joinPromotedTypes ts₁' ts₂'
      else
        match decide (T₁ ≤ T₂), decide (T₂ ≤ T₁) with
        | true, true => joinPromotedTypes ts₁' (T₂ :: ts₂')
        | true, false => joinPromotedTypes (T₁ :: ts₁') ts₂'
        | false, true => joinPromotedTypes ts₁' (T₂ :: ts₂')
        | false, false => []
    := by
  simp [joinPromotedTypes]
  by_cases T₁ = T₂
  case pos heq => simp [heq]
  case neg hne =>
  simp [hne]
  by_cases T₁ ≤ T₂
  case neg => split <;> simp_all
  case pos hle =>
  simp [hle]
  by_cases T₂ ≤ T₁
  case neg => simp_all
  case pos hge =>
  simp [hge]
  suffices h : ∀ U, U ∈ ts₁' → U < T₂ by rw [bounded_skip_right h]
  intro U U_in_ts₁'
  calc
    _ < T₁ := isPromotionChain.head_bounds hvalid₁ U U_in_ts₁'
    _ ≤ T₂ := by assumption

end «PromotionChain»
end

section

/-- The join operation is *not* associative. -/
public theorem PromotionChain.join_not_associative :
    ¬∀ (τ : Type) [DartTypeRepr τ] (c₁ c₂ c₃ : PromotionChain (τ := τ)),
      (c₁.join c₂).join c₃ = c₁.join (c₂.join c₃) := by
  let Γ : DartTypeRepr SimpleType := inferInstance
  let c₁ : PromotionChain := ⟨[Γ.Map Γ.ObjectQ Γ.int, Γ.Map Γ.int Γ.int],
    by simp [isPromotionChain.iff_isChain, SimpleType.isSubtype]⟩
  let c₂ : PromotionChain := ⟨[Γ.Map Γ.dynamic Γ.int, Γ.Map Γ.int Γ.int],
    by simp [isPromotionChain.iff_isChain, SimpleType.isSubtype]⟩
  let c₃ : PromotionChain := ⟨[Γ.Map Γ.int Γ.Object, Γ.Map Γ.int Γ.int],
    by simp [isPromotionChain.iff_isChain, SimpleType.isSubtype]⟩
  let c₁₂ : PromotionChain := ⟨[Γ.Map Γ.int Γ.int], by simp⟩
  intro h
  specialize h SimpleType c₁ c₂ c₃
  rw [show c₁.join c₂ = c₁₂ by simp [c₁, c₂, c₁₂, PromotionChain.join,
    PromotionChain.joinPromotedTypes, SimpleType.isSubtype]] at h
  rw [show c₁₂.join c₃ = c₁₂ by simp [c₁₂, c₃, PromotionChain.join,
    PromotionChain.joinPromotedTypes, SimpleType.isSubtype]] at h
  rw [show c₂.join c₃ = ∅ by simp [c₂, c₃, PromotionChain.join,
    PromotionChain.joinPromotedTypes, SimpleType.isSubtype]] at h
  rw [show c₁.join ∅ = ∅ by simp] at h
  injection h; contradiction

end
