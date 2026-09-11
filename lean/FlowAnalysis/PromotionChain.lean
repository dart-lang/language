module
import Aesop
import Batteries.Data.List.Basic
import Batteries.Data.List.Lemmas
public import FlowAnalysis.Types
public import Mathlib.Data.Finset.Dedup
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
lemma head_not_mem_tail {T : τ} {ts : List τ} (hvalid : isPromotionChain (T::ts)) : T ∉ ts := by
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
public def take (n : Nat) (c : PromotionChain) : PromotionChain := .mk (c.val.take n) $ by
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
    PromotionChain := .mk (c.val.drop n) $ by
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
public def filter (p : τ → Bool) (c : PromotionChain) : PromotionChain := .mk (c.val.filter p) $ by
  rcases c with ⟨ts, hvalid⟩
  rw [isPromotionChain.iff_pairwise]
  apply List.Pairwise.filter
  rw [←isPromotionChain.iff_pairwise]
  simp [hvalid]

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
If two promotion chains contain the same the set of types, then they are equal.

We prove this as a private lemma, since clients will want to rewrite using `toFinset_inj`, below.
-/
lemma eq_of_toFinset_eq : ∀ (c₁ c₂ : PromotionChain),
    c₁.val.toFinset = c₂.val.toFinset → c₁ = c₂ := by
  rintro ⟨ts₁, hvalid₁⟩ ⟨ts₂, hvalid₂⟩; simp
  cases ts₁
  case nil => simp; intro h; rw [←List.toFinset_eq_empty_iff]; aesop
  case cons T₁ ts₁' =>
    cases ts₂
    case nil => simp
    case cons T₂ ts₂' =>
      simp
      by_cases T₁ = T₂
      case pos heq =>
        subst heq
        intro hinsert
        suffices h : ts₁'.toFinset = ts₂'.toFinset by
          have := eq_of_toFinset_eq ⟨ts₁', hvalid₁.of_cons⟩ ⟨ts₂', hvalid₂.of_cons⟩
          simp_all
        simp [Finset.ext_iff] at hinsert ⊢
        intro T; specialize hinsert T
        by_cases T = T₁
        case neg hne => simp [hne] at hinsert; assumption
        case pos heq => grind [hvalid₁.head_not_mem_tail, hvalid₂.head_not_mem_tail]
      case neg hne =>
        simp [hne]; intro hcontra; simp [Finset.ext_iff] at hcontra
        have hT₁_lt_T₂ : T₁ < T₂ := by grind [isPromotionChain.lt_of_mem_tail hvalid₂]
        have hT₂_lt_T₁ : T₂ < T₁ := by grind [isPromotionChain.lt_of_mem_tail hvalid₁]
        grind

/-- Two promotion chains are equal iff they contain the same set of types. -/
public theorem toFinset_inj (c₁ c₂ : PromotionChain) :
    c₁ = c₂ ↔ c₁.val.toFinset = c₂.val.toFinset := by
  constructor
  · intro rfl; rfl
  · apply eq_of_toFinset_eq

/--
Two promotion chains are equal iff membership in one implies membership in the other (and vice
versa).
-/
public theorem ext_iff_mem (c₁ c₂ : PromotionChain) :
    c₁ = c₂ ↔ ∀ T, T ∈ c₁.val ↔ T ∈ c₂.val := by
  rw [toFinset_inj, Finset.ext_iff]; simp

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

/-- For computability, we define `c₁ join c₂` as a filter of `c₁`, removing any types that are not in `c₂`. -/
public def join (c₁ c₂ : PromotionChain) := c₁.filter (· ∈ c₂.val)

/--
An equivalent definition, which we use in the spec (and in proofs below) is that the join of two
promotion chains is their unique greatest common sublist.
-/
public theorem join_is_greatest_common_sublist (c₁ c₂ : PromotionChain) :
    (c₁.join c₂).is_greatest_common_sublist c₁ c₂ := by
  simp [join]
  constructor
  · constructor
    · simp
    · rw [sublist_iff_forall_mem]; simp
  · rintro c' ⟨hc'_sublist_c₁, hc'_sublist_c₂⟩
    rw [sublist_iff_forall_mem] at hc'_sublist_c₁ hc'_sublist_c₂ ⊢
    intro T hT_in_c'
    simp [hc'_sublist_c₁ T hT_in_c', hc'_sublist_c₂ T hT_in_c']

/--
The computable definition of `join` above proves that a greatest common sublist always exists.
-/
lemma exists_is_greatest_common_sublist (c₁ c₂ : PromotionChain) :
    ∃ c : PromotionChain, c.is_greatest_common_sublist c₁ c₂ := by
  exists c₁.filter (· ∈ c₂.val)
  apply join_is_greatest_common_sublist

/-- The join is the unique greatest common sublist. -/
public theorem is_greatest_common_sublist.unique (c₁ c₂ : PromotionChain) :
    ∀ c : PromotionChain, c.is_greatest_common_sublist c₁ c₂ → c = c₁.join c₂ := by
  intro c hc
  let c' := c₁.join c₂
  have hc' := join_is_greatest_common_sublist c₁ c₂
  rw [ext_iff_mem]; grind

/-- A type is in the join of two promotion chains iff it is in both chains. -/
@[simp]
public theorem mem_join (c₁ c₂ : PromotionChain) (T : τ) :
    T ∈ (c₁.join c₂).val ↔ T ∈ c₁.val ∧ T ∈ c₂.val := by
  obtain ⟨⟨hjoin_sublist_c₁, hjoin_sublist_c₂⟩, hgreatest⟩ := join_is_greatest_common_sublist c₁ c₂
  rw [PromotionChain.sublist_iff_forall_mem] at hjoin_sublist_c₁ hjoin_sublist_c₂
  constructor
  · grind
  · simp; intro hT_in_c₁ hT_in_c₂
    specialize hgreatest (.single T) (by simp_all [is_common_sublist])
    rw [PromotionChain.sublist_iff_forall_mem] at hgreatest; simp at hgreatest; assumption

/--
The join of two promotion chains is equal to `c` iff all types `T` satisfy the `mem_join` relation
above.
-/
public theorem join_eq_iff_mem (c c₁ c₂ : PromotionChain) :
    c₁.join c₂ = c ↔ ∀ T, T ∈ c₁.val ∧ T ∈ c₂.val ↔ T ∈ c.val := by
  constructor
  · intro rfl T; simp
  · rw [ext_iff_mem]; simp

/-- Joining a promotion chain with a sublist produces the sublist. -/
@[simp]
public theorem join_eq_left_of_sublist (c₁ c₂ : PromotionChain) :
    c₁.val <+ c₂.val → c₁.join c₂ = c₁ := by
  intro h; rw [join_eq_iff_mem]; intro T; grind

/-- Joining a promotion chain with a sublist produces the sublist. -/
@[simp]
public theorem join_eq_right_of_sublist (c₁ c₂ : PromotionChain) :
    c₂.val <+ c₁.val → c₁.join c₂ = c₂ := by
  intro h; rw [join_eq_iff_mem]; intro T; grind

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
public theorem empty_join :
    ∀ c : PromotionChain, (∅ : PromotionChain).join c = ∅ := by
  intro c; rw [join_eq_iff_mem]; simp

/-- Joining with an empty promotion chain produces the empty promotion chain. -/
@[simp]
public theorem join_empty : ∀ c : PromotionChain, c.join ∅ = ∅ := by
  intro c; rw [join_eq_iff_mem]; simp

/--
If a promotion chain is not empty, then its list of types is not empty.

This helps with grind-based proofs because it allows case splitting on whether `c = ∅`.
-/
@[grind =>]
public theorem val_ne_nil_of_ne_empty {c : PromotionChain} : ¬c = ∅ → ¬c.val = [] := by
  contrapose; rcases c; simp; intro rfl; simp

/--
If a promotion chain contains no types, then joining it with another chain produces the empty chain.
-/
@[simp]
public theorem join_eq_empty_of_val_nil_left {c₁ c₂ : PromotionChain} :
    c₁.val = [] → c₁.join c₂ = ∅ := by
  intro h; simp [show c₁ = ∅ by grind]

/--
If a promotion chain contains no types, then joining it with another chain produces the empty chain.
-/
@[simp]
public theorem join_eq_empty_of_val_nil_right {c₁ c₂ : PromotionChain} : c₂.val = [] → c₁.join c₂ = ∅ := by
  intro h; simp [show c₂ = ∅ by grind]

end «PromotionChain»
