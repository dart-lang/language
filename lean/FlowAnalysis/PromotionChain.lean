module
import Aesop
import Batteries.Data.List.Basic
import Batteries.Data.List.Lemmas
public import FlowAnalysis.Types
public import Mathlib.Data.Finset.Basic
import Mathlib.Data.Set.Finite.Basic

namespace FlowAnalysis

-- Allows the use of `<+` notation for `List.Sublist`.
open scoped List

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
theorem nil : isPromotionChain ([] : List τ) := by
  simp [isPromotionChain]

/-- A list with just one element is a promotion chain. -/
@[simp]
theorem singleton : ∀ T : τ, isPromotionChain [T] := by
  simp [isPromotionChain]

/-- The tail of a promotion chain is also a promotion chain. -/
public theorem of_cons {T : τ} {ts : List τ} (hvalid : isPromotionChain (T::ts)) :
    isPromotionChain ts := by
  simp [iff_isChain] at hvalid ⊢
  exact List.IsChain.of_cons hvalid

/-- The head of a promotion chain is a strict supertype of every type in the tail. -/
public theorem lt_of_mem_tail {T : τ} {ts : List τ} (hvalid : isPromotionChain (T::ts)) :
    ∀ T' ∈ ts, T' < T := by
  simp [iff_pairwise] at hvalid
  aesop

/-- The head of a promotion chain is not in the tail. -/
public theorem head_not_mem_tail {T : τ} {ts : List τ} (hvalid : isPromotionChain (T::ts)) :
    T ∉ ts := by
  have := hvalid.lt_of_mem_tail T
  grind

/--
Consing a type onto a promotion chain produces a promotion chain, provided that the new head is a
strict supertype of all the other types.
-/
public theorem cons {T : τ} {ts : List τ} (hbounds : ∀ T' ∈ ts, T' < T)
    (hvalid : isPromotionChain ts) :
    isPromotionChain (T::ts) := by
  simp [iff_pairwise] at hvalid ⊢; grind

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

/--
Simplification theorem: `isPromotionChain` applied to the types in a `PromotionChain` is trivially
satisfied, since a `PromotionChain` can only be created if a witness to its validity is provided.
-/
@[simp]
public theorem prop (c : PromotionChain) : isPromotionChain c.val := c.property

/-- Extensionality: promotion chains may be proven equal by proving their lists equal. -/
public theorem ext {c₁ c₂ : PromotionChain} : c₁.val = c₂.val → c₁ = c₂ := by
  intro h; apply Subtype.ext; assumption

/-- Injection: if promotion chains are equal then their values are equal. -/
public theorem val_inj {c₁ c₂ : PromotionChain} : c₁ = c₂ → c₁.val = c₂.val := by
  intro rfl; rfl

/-- Equality of promotion chains may be rewritten to equality of values and vice versa. -/
public theorem ext_iff {c₁ c₂ : PromotionChain} : c₁ = c₂ ↔ c₁.val = c₂.val := by
  constructor
  · apply val_inj
  · apply ext

/-- The empty promotion chain. -/
public def empty : PromotionChain := ⟨[], by simp⟩

/-- Analogous to `List.take` but for promotion chains. -/
public def take (n : Nat) (c : PromotionChain) : PromotionChain := .mk (c.val.take n) <| by
  suffices h : c.val.take n <+ c.val by apply isPromotionChain.sublist h c.property
  exact List.take_sublist n c.val

/-- Simplification theorem relating the behavior of `PromotionChain.take` to that of `List.take`. -/
@[simp]
public theorem val_take {n : Nat} {c : PromotionChain} : (c.take n).val = c.val.take n := by rfl

/-- Simplification theorem relating the behavior of `PromotionChain.take` to that of `List.take`. -/
@[simp]
public theorem take_of_val {n : Nat} {c : PromotionChain}
    {hvalid : isPromotionChain (c.val.take n)} : ⟨c.val.take n, hvalid⟩ = c.take n := by rfl

/-- Analogous to `List.drop` but for promotion chains. -/
public def drop (n : Nat) (c : PromotionChain) :
    PromotionChain := .mk (c.val.drop n) <| by
  suffices h : c.val.drop n <+ c.val by apply isPromotionChain.sublist h c.property
  exact List.drop_sublist n c.val

/-- `PromotionChain.drop 0` has no effect. -/
@[simp]
public theorem drop_zero (c : PromotionChain) : drop 0 c = c := by rfl

/-- Simplification theorem relating the behavior of `PromotionChain.drop` to that of `List.drop`. -/
@[simp]
public theorem val_drop {n : Nat} {c : PromotionChain} : (c.drop n).val = c.val.drop n := by rfl

/-- Simplification theorem relating the behavior of `PromotionChain.drop` to that of `List.drop`. -/
@[simp]
public theorem drop_of_val {n : Nat} {c : PromotionChain}
    {hvalid : isPromotionChain (c.val.drop n)} :
    ⟨c.val.drop n, hvalid⟩ = c.drop n := by rfl

public instance instEmptyCollection : EmptyCollection (PromotionChain) where
  emptyCollection := empty

@[simp]
public theorem eq_empty {h : isPromotionChain []} : (⟨[], h⟩ : PromotionChain) = ∅ :=
  by rfl

@[simp]
public theorem val_empty : (∅ : PromotionChain).val = [] := by rfl

public theorem empty_of_val_nil {c : PromotionChain} :
    c.val = [] → c = ∅ := by
  intro h; apply ext; simp_all

/-- A promotion chain containing a single type. -/
public def single (T : τ) : PromotionChain := ⟨[T], by simp⟩

@[simp]
public theorem val_single {T : τ} : (single T).val = [T] := by rfl

/-- A promotion chain `c` is strictly bounded by `T` iff `T::c` is a promotion chain. -/
public def strictly_bounded_by (c : PromotionChain) (T : τ) : Prop := isPromotionChain (T::c)

/-- Analogous to `List.filter` but for promotion chains. -/
public def filter (p : τ → Bool) (c : PromotionChain) : PromotionChain := .mk (c.val.filter p) <| by
  suffices h : c.val.filter p <+ c.val by apply isPromotionChain.sublist h c.property
  simp

/--
Simplification theorem relating the behavior of `PromotionChain.filter` to that of `List.filter`.
-/
@[simp]
public theorem val_filter {p : τ → Bool} {c : PromotionChain} :
    (c.filter p).val = c.val.filter p := by rfl

/--
Simplification theorem relating the behavior of `PromotionChain.filter` to that of `List.filter`.
-/
@[simp]
public theorem filter_of_val {p : τ → Bool} {c : PromotionChain}
    {hvalid : isPromotionChain (c.val.filter p)} :
    ⟨c.val.filter p, hvalid⟩ = c.filter p := by rfl

/--
Two promotion chains are equal iff membership in one implies membership in the other (and vice
versa).
-/
public theorem ext_iff_mem (c₁ c₂ : PromotionChain) :
    c₁ = c₂ ↔ ∀ T, T ∈ c₁.val ↔ T ∈ c₂.val := by
  constructor
  · intro rfl; simp
  · intro hmem
    apply ext
    apply List.Pairwise.eq_of_mem_iff (r := (fun T U => U < T))
    · rw [←isPromotionChain.iff_pairwise]; aesop
    · rw [←isPromotionChain.iff_pairwise]; aesop
    · assumption

/-- Two promotion chains are equal iff they contain the same set of types. -/
public theorem toFinset_inj (c₁ c₂ : PromotionChain) :
    c₁ = c₂ ↔ c₁.val.toFinset = c₂.val.toFinset := by
  simp [ext_iff_mem, Finset.ext_iff]

/--
The sublist relation holds between two promotion chains iff membership in the former implies
membership in the latter.
-/
public theorem sublist_iff_forall_mem (c₁ c₂ : PromotionChain) :
    c₁.val <+ c₂.val ↔ ∀ T, T ∈ c₁.val → T ∈ c₂.val := by
  constructor
  · intro hsublist T hT_in_c₁
    apply hsublist.mem; assumption
  · intro hsubset
    suffices c₁ = c₂.filter (· ∈ c₁.val) by rw [this]; simp
    simp_all [ext_iff_mem]

/-- Define the notion of a common sublist of two promotion chains. -/
public abbrev is_common_sublist (c c₁ c₂ : PromotionChain) : Prop :=
    c.val <+ c₁.val ∧ c.val <+ c₂.val

/--
Define the notion of the greatest common sublist of two promotion chains.

We define "greatest" in terms of the sublist operation (i.e., `c` is "greater" than `c'` iff `c'` is
a sublist of `c`), since that gives us the sublist relations we need in the proofs below. We could,
alternatively, have defined "greatest" strictly in terms of length, but that would have required
additional legwork in the proofs below.
-/
public abbrev is_greatest_common_sublist (c c₁ c₂ : PromotionChain) : Prop :=
  c.is_common_sublist c₁ c₂ ∧ ∀ c' : PromotionChain, c'.is_common_sublist c₁ c₂ → c'.val <+ c.val

/--
For computability, we define `c₁.join c₂` as a filter of `c₁`, removing any types that are not in
`c₂`.
-/
public def join (c₁ c₂ : PromotionChain) := c₁.filter (· ∈ c₂.val)

/-- A type is in the join of two promotion chains iff it is in both chains. -/
@[simp]
public theorem mem_join (c₁ c₂ : PromotionChain) (T : τ) :
    T ∈ (c₁.join c₂).val ↔ T ∈ c₁.val ∧ T ∈ c₂.val := by
  simp [join]

/--
An equivalent definition, which we use in the spec (and in proofs below) is that the join of two
promotion chains is their unique greatest common sublist.
-/
public theorem join_is_greatest_common_sublist (c₁ c₂ : PromotionChain) :
    (c₁.join c₂).is_greatest_common_sublist c₁ c₂ := by
  simp [is_greatest_common_sublist, is_common_sublist, sublist_iff_forall_mem]
  aesop

/--
The computable definition of `join` above proves that a greatest common sublist always exists.
-/
public theorem exists_is_greatest_common_sublist (c₁ c₂ : PromotionChain) :
    ∃ c : PromotionChain, c.is_greatest_common_sublist c₁ c₂ :=
  ⟨c₁.join c₂, join_is_greatest_common_sublist c₁ c₂⟩

/-- The join is the unique greatest common sublist. -/
public theorem is_greatest_common_sublist.unique {c c₁ c₂ : PromotionChain}
    (h : c.is_greatest_common_sublist c₁ c₂) : c = c₁.join c₂ := by
  have hc' := join_is_greatest_common_sublist c₁ c₂
  rw [ext_iff_mem]; grind

/--
The join of two promotion chains is equal to `c` iff all types `T` satisfy the `mem_join` relation
above.
-/
public theorem join_eq_iff_mem (c c₁ c₂ : PromotionChain) :
    c₁.join c₂ = c ↔ ∀ T, T ∈ c₁.val ∧ T ∈ c₂.val ↔ T ∈ c.val := by
  constructor
  · intro rfl T; simp
  · rw [ext_iff_mem]; simp

/-- If `c₁` is a sublist of `c₂`, their join is `c₁`. -/
@[simp]
public theorem join_eq_left_of_sublist {c₁ c₂ : PromotionChain} (h : c₁.val <+ c₂.val) :
    c₁.join c₂ = c₁ := by
  rw [join_eq_iff_mem]; intro T; grind

/-- If `c₂` is a sublist of `c₁`, their join is `c₂`. -/
@[simp]
public theorem join_eq_right_of_sublist {c₁ c₂ : PromotionChain} (h : c₂.val <+ c₁.val) :
    c₁.join c₂ = c₂ := by
  rw [join_eq_iff_mem]; intro T; grind

/-- The join operation is idempotent (`join c c = c`). -/
@[simp]
public theorem join_self (c : PromotionChain) : c.join c = c := by
  rw [join_eq_iff_mem]; grind

public instance join.instIdempotentOp :
    Std.IdempotentOp (join (τ := τ)) where
  idempotent := join_self

/-- The join operation is commutative (`c₁.join c₂ = c₂.join c₁`). -/
public theorem join_comm (c₁ c₂ : PromotionChain) : c₁.join c₂ = c₂.join c₁ := by
  rw [ext_iff_mem]; simp; aesop

public instance join.instCommutative : Std.Commutative (join (τ := τ)) where
  comm := join_comm

/-- The join operation is associative (`(c₁.join c₂).join c₃ = c₁.join (c₂.join c₃)`) -/
public theorem join_assoc (c₁ c₂ c₃ : PromotionChain) :
    (c₁.join c₂).join c₃ = c₁.join (c₂.join c₃) := by
  rw [ext_iff_mem]; simp; aesop

public instance join.instAssociative : Std.Associative (join (τ := τ)) where
  assoc := join_assoc

/-- Joining with an empty promotion chain produces the empty promotion chain. -/
@[simp]
public theorem empty_join (c : PromotionChain) : (∅ : PromotionChain).join c = ∅ := by
  rw [join_eq_iff_mem]; simp

/-- Joining with an empty promotion chain produces the empty promotion chain. -/
@[simp]
public theorem join_empty (c : PromotionChain) : c.join ∅ = ∅ := by
  rw [join_eq_iff_mem]; simp

/--
If a promotion chain is not empty, then its list of types is not empty.

This helps with grind-based proofs because it allows case splitting on whether `c = ∅`.
-/
@[grind =>]
public theorem val_ne_nil_of_ne_empty {c : PromotionChain} : ¬c = ∅ → ¬c.val = [] := by
  contrapose; rcases c; simp; intro rfl; simp

/--
If `c₁` contains no types, then `c₁.join c₂` is the empty chain.

Variant of `empty_join` for use when emptiness is expressed as `c₁.val = []` rather than `c₁ = ∅`.
-/
@[simp]
public theorem join_eq_empty_of_val_nil_left {c₁ c₂ : PromotionChain} :
    c₁.val = [] → c₁.join c₂ = ∅ := by
  intro h; simp [show c₁ = ∅ by grind]

/--
If `c₂` contains no types, then `c₁.join c₂` is the empty chain.

Variant of `join_empty` for use when emptiness is expressed as `c₂.val = []` rather than `c₂ = ∅`.
-/
@[simp]
public theorem join_eq_empty_of_val_nil_right {c₁ c₂ : PromotionChain} :
    c₂.val = [] → c₁.join c₂ = ∅ := by
  intro h; simp [show c₂ = ∅ by grind]

end «PromotionChain»
