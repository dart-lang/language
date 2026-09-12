module
public import FlowAnalysis.PromotionChain.Basic
public import FlowAnalysis.Types
public import FlowAnalysis.WP
public import Lean
import Mathlib.Tactic.Order

open Std.Do

namespace FlowAnalysis.PromotionChain

variable {τ : Type} [DartTypeRepr τ]

local notation "PromotionChain" => PromotionChain (τ := τ)

/--
Lean model of the second half of the Dart method `PromotionModel.joinPromotedTypes` (the portion
after the input chains are re-ordered so that the first is no longer than the second).
-/
def joinPromotedTypesImpl' {m} [Monad m] (ts₁ ts₂ : List τ) : m (List τ) := do
  let mut i₁ := 0
  let mut i₂ := 0
  let mut T₁ := ts₁[0]!
  let mut T₂ := ts₂[0]!
  let mut result : Option (List τ) := none
  repeat do
    let mut advance_i₁ : Bool := false
    let mut advance_i₂ : Bool := false
    if T₁ = T₂ then
      result := result.map (· ++ [T₁])
      advance_i₁ := true
      advance_i₂ := true
    else if T₁ ≤ T₂ then
      advance_i₁ := false
      advance_i₂ := true
    else
      result := result <|> some (ts₁.take i₁)
      advance_i₁ := true
      advance_i₂ := false
    if advance_i₁ then
      i₁ := i₁ + 1
      if i₁ = ts₁.length then
        return match result with
          | some r => r
          | none => ts₁
      T₁ := ts₁[i₁]!
    if advance_i₂ then
      i₂ := i₂ + 1
      if i₂ = ts₂.length then
        return match result with
          | some r => r
          | none => if i₁ = ts₁.length then ts₁ else ts₁.take i₁
      T₂ := ts₂[i₂]!

/-- Lean model of the Dart method `PromotionModel.joinPromotedTypes`. -/
public def joinPromotedTypesImpl {m} [Monad m] (ts₁ ts₂ : List τ) : m (List τ) := do
  let mut ts₁ := ts₁
  let mut ts₂ := ts₂
  if ts₁ = [] then return ts₁
  if ts₂ = [] then return ts₂
  if ts₁.length > ts₂.length then
    let tmp := ts₁
    ts₁ := ts₂
    ts₂ := tmp
  joinPromotedTypesImpl' ts₁ ts₂

/--
Helper theorem for proving the correctness of `joinPromotedTypesImpl`:

Given a promotion chain `c`, index `i`, and type `T`, if `i` is a valid index into `c` and `T` is
the `i`th type in `c`, this theorem can be used to split the promotion chain at `T`, obtaining the
equivalence `c.drop i = T :: c.drop (i+1)`.
-/
theorem drop_eq_getElem_cons {i} {T : τ} {c : PromotionChain} (hrange : i < c.val.length)
    (hT : T = c.val[i] := by rfl) : ∃ hvalid, c.drop i = ⟨T :: c.drop (i+1), hvalid⟩ := by
  rcases c with ⟨ts, hvalid⟩; simp_all

/-- Specification (and correctness proof) for `joinPromotedTypesImpl'`. -/
theorem joinPromotedTypesImpl'_correct [Monad m] [Lean.Order.MonadTail m]
    [WPMonad m ps] (c₁ c₂ : PromotionChain) :
    0 < c₁.val.length → c₁.val.length ≤ c₂.val.length →
    ⦃stateIs s₀⦄ (joinPromotedTypesImpl' c₁.val c₂.val : m _)
    ⦃⇓ r => stateIs s₀ ∧ ⌜r = (c₁.join c₂).val⌝⦄ := by
  intro hc₁_nonEmpty hc₁_smaller
  mintro hstate
  unfold joinPromotedTypesImpl'
  simp
  mspec Spec.forIn_loop
  -- Decreasing measure (for proof of termination): c₁.val.length + c₂.val.length - i₁ - i₂
  case measure => exact fun vars => SVal.curry fun _ => ⟨match vars with
    | ⟨_, i₁, i₂, _⟩ => c₁.val.length + c₂.val.length - i₁ - i₂
  ⟩
  case inv => exact (⇓ cursor => (match cursor with
    -- Loop invariants:
    -- - Monadic state is unchanged.
    -- - No value has been returned yet (the loop is still running).
    -- - T₁ is the i₁th element of c₁.
    -- - T₂ is the i₂th element of c₂.
    -- - The full result will equal the result accumulated so far (or `c₁.take i₁`, if no result
    --   accumulator has been allocated yet), concatenated with the join of `c₁.drop i₁` and
    --   `c₂.drop i₂`.
    | .inl (retval, i₁, i₂, T₁, T₂, result) =>
      spred(stateIs s₀ ∧ ⌜retval = none ∧ (∃ hrange₁ : i₁ < c₁.val.length, T₁ = c₁.val[i₁]) ∧
        (∃ hrange₂ : i₂ < c₂.val.length, T₂ = c₂.val[i₂]) ∧
        (c₁.join c₂).val =
          result.getD (c₁.val.take i₁) ++ (c₁.drop i₁).join (c₂.drop i₂)⌝)
    -- Loop exit state:
    -- - Monadic state is unchanged
    -- - The returned value is the join of the input chains.
    | .inr (retval, i₁, i₂, T₁, T₂, result) =>
      spred(stateIs s₀ ∧ ⌜retval = some (c₁.join c₂).val⌝)
    ))
  -- Proof that each iteration of the loop:
  -- - Decreases the decreasing measure.
  -- - Either preserves the loop invariant or establishes the loop exit state.
  case step =>
    simp; intro retval i₁ i₂ T₁ T₂ result mb
    mintro h; mcases h with ⟨hmb, hstate, h⟩; rcases h with
      ⟨rfl, ⟨hrange₁, hT₁⟩, ⟨hrange₂, hT₂⟩, hjoin⟩
    split
    case isTrue heq =>
      subst heq
      -- T₁ belongs in the output, so we can rewrite hjoin.
      have hT₁_belongs : (c₁.drop i₁).join (c₂.drop i₂) =
          T₁ :: (c₁.drop (i₁+1)).join (c₂.drop (i₂+1)) := by
        obtain ⟨hvalid_drop₁, hdrop₁⟩ := drop_eq_getElem_cons hrange₁ hT₁; rw [hdrop₁]
        obtain ⟨hvalid_drop₂, hdrop₂⟩ := drop_eq_getElem_cons hrange₂ hT₂; rw [hdrop₂]
        simp
      rw [hT₁_belongs] at hjoin; clear hT₁_belongs
      split
      case isTrue hdone₁ =>
        rw [hdone₁] at hjoin; simp at hjoin ⊢
        mconstructor; massumption; mpure_intro; cases result <;> simp_all
      case isFalse hrange₁ =>
        replace hrange₁ : i₁ + 1 < c₁.val.length := by grind
        split
        case isTrue hdone₂ =>
          rw [hdone₂] at hjoin; simp at hjoin ⊢
          mconstructor; massumption; mpure_intro; cases result <;> simp_all
        case isFalse hrange₂ =>
          replace hrange₂ : i₂ + 1 < c₂.val.length := by grind
          simp
          mexists c₁.val.length + c₂.val.length - (i₁ + 1) - (i₂ + 1); simp
          mconstructor; · mpure_intro; trivial
          mconstructor; · mpure_intro; grind
          mconstructor; massumption; mpure_intro
          constructor; · exists hrange₁; simp_all
          constructor; exists hrange₂; simp_all
          cases result
          case none =>
            simp at hjoin ⊢
            rw [show c₁.val.take (i₁+1) = c₁.val.take i₁ ++ [T₁] by simp_all]; simp; assumption
          case some result => simp at hjoin ⊢; assumption
    case isFalse hne =>
      split
      case isTrue hle =>
        -- T₂ does not belong in the output, so we can rewrite hjoin.
        have hT₂_notBelongs : (c₁.drop i₁).join (c₂.drop i₂) =
            (c₁.drop i₁).join (c₂.drop (i₂+1)) := by
          obtain ⟨hvalid_drop₁, hdrop₁⟩ := drop_eq_getElem_cons hrange₁ hT₁; rw [hdrop₁]
          obtain ⟨hvalid_drop₂, hdrop₂⟩ := drop_eq_getElem_cons hrange₂ hT₂; rw [hdrop₂]
          simp [hne, hle]
        rw [hT₂_notBelongs] at hjoin; clear hT₂_notBelongs
        split
        case isTrue hdone₂ =>
          rw [hdone₂] at hjoin; simp at hjoin ⊢
          mconstructor; massumption; mpure_intro; cases result <;> simp_all
        case isFalse hrange₂ =>
          replace hrange₂ : i₂ + 1 < c₂.val.length := by grind
          simp
          mexists c₁.val.length + c₂.val.length - i₁ - (i₂ + 1)
          mconstructor; · mpure_intro; trivial
          mconstructor; · mpure_intro; grind
          mconstructor; massumption; mpure_intro
          constructor; · exists hrange₁
          constructor; · exists hrange₂; simp_all
          cases result
          case none => simp at hjoin ⊢; assumption
          case some result => simp at hjoin ⊢; assumption
      case isFalse hnotLe =>
        -- T₁ does not belong in the output, so we can rewrite hjoin.
        have hT₁_notBelongs : (c₁.drop i₁).join (c₂.drop i₂) =
            (c₁.drop (i₁+1)).join (c₂.drop i₂) := by
          obtain ⟨hvalid_drop₁, hdrop₁⟩ := drop_eq_getElem_cons hrange₁ hT₁; rw [hdrop₁]
          obtain ⟨hvalid_drop₂, hdrop₂⟩ := drop_eq_getElem_cons hrange₂ hT₂; rw [hdrop₂]
          simp [hne, hnotLe]
        rw [hT₁_notBelongs] at hjoin; clear hT₁_notBelongs
        split
        case isTrue hdone₁ =>
          rw [hdone₁] at hjoin; simp at hjoin ⊢
          mconstructor; massumption; mpure_intro; aesop
        case isFalse hrange₁ =>
          replace hrange₁ : i₁ + 1 < c₁.val.length := by grind
          simp
          mexists c₁.val.length + c₂.val.length - (i₁ + 1) - i₂
          mconstructor; · mpure_intro; trivial
          mconstructor; · mpure_intro; grind
          mconstructor; massumption; mpure_intro
          constructor; · exists hrange₁; simp_all
          constructor; · exists hrange₂
          cases result
          case none => simp at hjoin ⊢; assumption
          case some result => simp at hjoin ⊢; assumption
  -- Proof that the loop invariant is satisfied at the point of entry to the loop.
  case pre => simp; mconstructor; massumption; mpure_intro; grind
  -- Proof that the non-exceptional postcondition is satisfied by the loop exit state.
  case post.success r =>
    simp; mrename_i h; mcases h with ⟨hstate, hresult⟩; rw [hresult]; simp
    mconstructor; massumption; mpure_intro; trivial
  -- Proof that the exceptional postcondition is satisfied.
  case post.except => simp

/-- Specification (and correctness proof) for `joinPromotedTypesImpl`. -/
public theorem joinPromotedTypesImpl_correct [Monad m] [Lean.Order.MonadTail m]
    [WPMonad m ps] (c₁ c₂ : PromotionChain) :
    ⦃stateIs s₀⦄ (joinPromotedTypesImpl c₁.val c₂.val : m _)
    ⦃⇓ r => stateIs s₀ ∧ ⌜r = (c₁.join c₂).val⌝⦄ := by
  unfold joinPromotedTypesImpl
  apply WP_ite
  case hifTrue =>
    intro hempty₁; simp [hempty₁]; mintro hstate; mconstructor; massumption; mpure_intro; trivial
  case hifFalse =>
  intro hnotEmpty₁; apply WP_ite
  case hifTrue =>
    intro hempty₂; simp [hempty₂]; mintro hstate; mconstructor; massumption; mpure_intro; trivial
  case hifFalse =>
  intro hnotEmpty₂
  apply WP_ite
  case hifTrue =>
    intro hc₁_longer; mintro hstate; simp; mspec joinPromotedTypesImpl'_correct
    · grind
    · order
    · rename_i r; mrename_i h; mcases h with ⟨hstate, hresult⟩
      mconstructor; massumption; mpure_intro
      rw [join_comm]; assumption
  case hifFalse =>
    intro hc₁_shorter; mintro hstate; simp; mspec joinPromotedTypesImpl'_correct
    · grind
    · order

end FlowAnalysis.PromotionChain
