module
public import DartSemantics.Language
public import Mathlib.Logic.Relation

/-!
# The interpreter

An interpreter for the semantics, proved to agree with it. It runs on any type representation
with a run-time subtype check algorithm (`RtSubChecker`), such as `SimpleType`.

The semantics is a relation, because a run-time subtype check need not terminate (see
`HeadStep.lean`). The interpreter is a function, so it can't follow a check forever. Instead, it
takes *fuel*, a budget for each check: `primStep fuel e σ` is the step that `e` takes in state `σ`,
or `stuck` if `e` has none, or `outOfFuel` if a check didn't answer within the budget. Running out
of fuel is never reported as `stuck`, and given enough fuel, the interpreter finds every step
except one that a check that doesn't terminate would take, forever.

The interpreter follows two implementation rules:
- `primStep` is structurally recursive, so that the kernel can evaluate it. (Well-founded
  recursion would make it irreducible.)
- It uses the state *linearly*: it decides where the redex is before it touches the state, and
  then uses the state once. Otherwise, the state would still be shared when an allocation pushes
  a cell onto the heap, and every allocation would copy the heap.
-/

namespace DartSemantics.Interp

open DartLang Iris.ProgramLogic EctxItemLanguage Language.Notation PrimStep

variable {τ : Type} [Γ : DartRuntimeTypeRepr τ]

local notation "Value" => Value (τ := τ)
local notation "LoweredExpr" => LoweredExpr (τ := τ)
local notation "EctxItem" => EctxItem (τ := τ)
local notation "Outcome" => Outcome (τ := τ)
local notation "State" => State (τ := τ)

/-- The result of trying to take a step. -/
public inductive StepResult where
  /-- The step goes to expression `e` and state `σ`. -/
  | next (e : LoweredExpr) (σ : State)
  /-- There is no step. -/
  | stuck
  /-- A run-time subtype check didn't answer within the budget of fuel. -/
  | outOfFuel

local notation "StepResult" => StepResult (τ := τ)

/-- Apply `f` to the expression that a step goes to. -/
@[expose]
public def StepResult.map (f : LoweredExpr → LoweredExpr) : StepResult → StepResult
  | .next e σ => .next (f e) σ
  | .stuck => .stuck
  | .outOfFuel => .outOfFuel

/-- Plug the expression that a step goes to into the hole of context item `Ki`. -/
@[expose]
public def stepIn (Ki : EctxItem) (r : StepResult) : StepResult := r.map Ki.fill

variable [RtSubChecker τ]

/--
Run the run-time check of whether `S` is a subtype of `T`, within a budget of `fuel`, and continue
with `k` applied to the answer.
-/
@[expose]
public def withCheck (fuel : Nat) (S T : τ) (k : Bool → StepResult) : StepResult :=
  match RtSubChecker.check fuel S T with
  | some (b, _) => k b
  | none => .outOfFuel

variable [P : SemanticParams τ]

/--
Perform the promotion check of value `v` against type `T` (if the semantics performs promotion
checks), within a budget of `fuel`, and continue with `r` if it passes.
-/
@[expose]
public def promotionCheck (fuel : Nat) (σ : State) (v : Value) (T : τ) (r : StepResult) :
    StepResult :=
  match P.promotionChecks with
  | .trust => r
  | .verify =>
    match σ.dynamicType v with
    | some S => withCheck fuel S T fun b => if b then r else .stuck
    | none => .stuck

/-- The head step of `e` in state `σ` (see `HeadStep`), with a budget of `fuel` for each check. -/
@[expose]
public def headStep (fuel : Nat) (e : LoweredExpr) (σ : State) : StepResult :=
  match e with
  | .null => .next (.val .null) σ
  | .declare v T startsNull => .next (.block [.declare v T startsNull]) σ
  | .block [] => .next (.val .null) σ
  | .block (.declare v _ startsNull :: ms) =>
    .next (.block (LoweredExpr.resolveBlock v σ.fresh ms))
      (σ.alloc (if startsNull then .val .null else .uninit))
  | .block (m :: ms) => .next (.seq m (.block ms)) σ
  | .seq (.val _) m => .next m σ
  | .varAt _ T ℓ =>
    match σ.lookup ℓ with
    | some (.val v) => promotionCheck fuel σ v T (.next (.val v) σ)
    | _ => .stuck
  | .nullCheck (.val .null) => .next (.throwing (.error .typeError)) σ
  | .nullCheck (.val v) => .next (.val v) σ
  | .as (.val v) T =>
    match σ.dynamicType v with
    | some S =>
      withCheck fuel S T fun b =>
        if b then .next (.val v) σ else .next (.throwing (.error .typeError)) σ
    | none => .stuck
  | .is (.val v) T =>
    match σ.dynamicType v with
    | some S => withCheck fuel S T fun b => .next (.val (.bool b)) σ
    | none => .stuck
  | .cond (.val (.bool true)) m₂ _ _ => .next m₂ σ
  | .cond (.val (.bool false)) _ m₃ _ => .next m₃ σ
  | .propertyGet (.val v) p T =>
    match σ.instanceVariable? v p.name with
    | some ℓf =>
      match σ.lookup ℓf with
      | some (.val w) => promotionCheck fuel σ w T (.next (.val w) σ)
      | _ => .stuck
    | none =>
      match P.getterImpl p v σ with
      | some w => promotionCheck fuel σ w T (.next (.val w) σ)
      | none => .stuck
  | .nullCheck (.throwing v) => .next (.throwing v) σ
  | .as (.throwing v) _ => .next (.throwing v) σ
  | .is (.throwing v) _ => .next (.throwing v) σ
  | .cond (.throwing v) _ _ _ => .next (.throwing v) σ
  | .propertyGet (.throwing v) _ _ => .next (.throwing v) σ
  | .seq (.throwing v) _ => .next (.throwing v) σ
  | _ => .stuck

/--
The step that `e` takes in state `σ`, with a budget of `fuel` for each check: the head step of
the redex in evaluation position. The expression is decomposed one evaluation context item at a
time, as `EctxItem.fill` builds it up.
-/
@[expose]
public def primStep (fuel : Nat) (e : LoweredExpr) (σ : State) : StepResult :=
  match e with
  | .nullCheck m =>
    if m.toOutcome?.isSome then headStep fuel e σ else stepIn .nullCheck (primStep fuel m σ)
  | .as m T =>
    if m.toOutcome?.isSome then headStep fuel e σ else stepIn (.as T) (primStep fuel m σ)
  | .is m T =>
    if m.toOutcome?.isSome then headStep fuel e σ else stepIn (.is T) (primStep fuel m σ)
  | .cond m₁ m₂ m₃ T =>
    if m₁.toOutcome?.isSome then headStep fuel e σ
    else stepIn (.cond m₂ m₃ T) (primStep fuel m₁ σ)
  | .propertyGet m p T =>
    if m.toOutcome?.isSome then headStep fuel e σ
    else stepIn (.propertyGet p T) (primStep fuel m σ)
  | .seq m₁ m₂ =>
    if m₁.toOutcome?.isSome then headStep fuel e σ else stepIn (.seq m₂) (primStep fuel m₁ σ)
  | _ => headStep fuel e σ
termination_by structural e

/-- The result of running a program. -/
public inductive RunResult where
  /-- The program completed with outcome `o`, in state `σ`. -/
  | done (o : Outcome) (σ : State)
  /-- The program got stuck at expression `e`, in state `σ`. -/
  | stuck (e : LoweredExpr) (σ : State)
  /-- The program ran out of fuel at expression `e`, in state `σ`. -/
  | outOfFuel (e : LoweredExpr) (σ : State)
  deriving Repr

local notation "RunResult" => RunResult (τ := τ)

/--
Run expression `e` from state `σ`, for at most `fuel` steps, giving each step's checks a budget of
the fuel that remains.
-/
@[expose]
public def run (fuel : Nat) (e : LoweredExpr) (σ : State) : RunResult :=
  match e.toOutcome? with
  | some o => .done o σ
  | none =>
    match fuel with
    | 0 => .outOfFuel e σ
    | fuel + 1 =>
      match primStep fuel e σ with
      | .next e' σ' => run fuel e' σ'
      | .stuck => .stuck e σ
      | .outOfFuel => .outOfFuel e σ

/-! ## Agreement with the semantics -/

/--
`Converges f r`: as a function of the budget of fuel, `f` gives `r` once the budget is large
enough, and runs out of fuel otherwise.
-/
public def Converges (f : Nat → StepResult) (r : StepResult) : Prop :=
  (∀ fuel, f fuel = r ∨ f fuel = .outOfFuel) ∧ ∃ n, ∀ fuel, n ≤ fuel → f fuel = r

omit Γ [RtSubChecker τ] P in
/-- If `f` gives `r` regardless of its budget of fuel (`h`), then `f` converges to `r`. -/
theorem Converges.of_eq {f : Nat → StepResult} {r : StepResult} (h : ∀ fuel, f fuel = r) :
    Converges f r :=
  ⟨fun fuel => .inl (h fuel), 0, fun fuel _ => h fuel⟩

omit Γ [RtSubChecker τ] P in
/--
If two functions of fuel `f` and `g` always produce the same result (`h`), and `g` converges to `r`
(`hg`), then `f` does too.
-/
theorem Converges.congr {f g : Nat → StepResult} {r : StepResult} (h : ∀ fuel, f fuel = g fuel)
    (hg : Converges g r) : Converges f r :=
  funext h ▸ hg

omit Γ [RtSubChecker τ] P in
/--
Applying `g` to the expression that each step goes to preserves convergence: if `f` converges to
`r` (`h`), then `f` followed by `StepResult.map g` converges to `r.map g`.
-/
theorem Converges.map {f : Nat → StepResult} {r : StepResult} (g : LoweredExpr → LoweredExpr)
    (h : Converges f r) : Converges (fun fuel => (f fuel).map g) (r.map g) := by
  obtain ⟨h₁, n, h₂⟩ := h
  refine ⟨fun fuel => ?_, n, fun fuel hn => by simp only [h₂ fuel hn]⟩
  rcases h₁ fuel with h | h <;> simp [h, StepResult.map]

omit Γ [RtSubChecker τ] P in
/-- If `f` converges to both `r₁` (`h₁`) and `r₂` (`h₂`), then they're the same (`r₁ = r₂`). -/
public theorem Converges.unique {f : Nat → StepResult} {r₁ r₂ : StepResult} (h₁ : Converges f r₁)
    (h₂ : Converges f r₂) : r₁ = r₂ := by
  obtain ⟨-, n₁, h₁⟩ := h₁
  obtain ⟨-, n₂, h₂⟩ := h₂
  rw [← h₁ (max n₁ n₂) (Nat.le_max_left _ _), ← h₂ (max n₁ n₂) (Nat.le_max_right _ _)]

omit P in
/--
If the run-time check of `S` against `T` answers `b` (`h`), and `k b` is `r` (`hk`), then
`withCheck` converges to `r`: it finds the answer once its budget of fuel is large enough.
-/
theorem withCheck_converges {S T : τ} {b : Bool} {k : Bool → StepResult} {r : StepResult}
    (h : RtSub S T b) (hk : k b = r) : Converges (fun fuel => withCheck fuel S T k) r := by
  subst hk
  constructor
  · intro fuel
    cases hc : RtSubChecker.check fuel S T with
    | none => exact .inr (by simp [withCheck, hc])
    | some p =>
      obtain ⟨b', fuel'⟩ := p
      exact .inl (by simp [withCheck, hc, rtSub_unique (RtSubChecker.check_sound hc) h])
  · obtain ⟨n, fuel', hc⟩ := RtSubChecker.check_complete h
    refine ⟨n, fun fuel hn => ?_⟩
    obtain ⟨j, rfl⟩ := Nat.exists_eq_add_of_le hn
    simp [withCheck, RtSubChecker.check_mono j hc]

omit P in
/--
If the run-time check of `S` against `T` gives no answer (`h`: it doesn't terminate), then
`withCheck` runs out of fuel (`.outOfFuel`), however much fuel it has.
-/
theorem withCheck_diverge {fuel : Nat} {S T : τ} {k : Bool → StepResult}
    (h : ∀ b, ¬ RtSub S T b) : withCheck fuel S T k = .outOfFuel := by
  unfold withCheck
  cases hc : RtSubChecker.check fuel S T with
  | none => rfl
  | some p => exact absurd (RtSubChecker.check_sound hc) (h _)

omit P in
/--
If `withCheck` produces a step (`h`), then the run-time check gave some answer `b` that `RtSub`
allows (`RtSub S T b`), and the step is `k b` (`k b = .next e σ`).
-/
theorem withCheck_eq_next {fuel : Nat} {S T : τ} {k : Bool → StepResult} {e : LoweredExpr}
    {σ : State} (h : withCheck fuel S T k = .next e σ) : ∃ b, RtSub S T b ∧ k b = .next e σ := by
  unfold withCheck at h
  cases hc : RtSubChecker.check fuel S T with
  | none => simp [hc] at h
  | some p =>
    obtain ⟨b, fuel'⟩ := p
    simp only [hc] at h
    exact ⟨b, RtSubChecker.check_sound hc, h⟩

/--
If `v` passes the promotion check against `T` (`h`), then `promotionCheck` converges to `r`: it
lets the step go ahead once its budget of fuel is large enough.
-/
theorem promotionCheck_converges {σ : State} {v : Value} {T : τ} (h : PassesPromotionCheck σ v T)
    (r : StepResult) : Converges (fun fuel => promotionCheck fuel σ v T r) r := by
  cases h with
  | trust h => exact Converges.of_eq fun fuel => by simp [promotionCheck, h]
  | verify h hS hT =>
    refine Converges.congr (fun fuel => ?_) (withCheck_converges (k := fun b => if b then r
      else .stuck) hT rfl)
    simp [promotionCheck, h, hS]

/--
If `promotionCheck` lets a step go ahead (`h`), then `v` passes the promotion check against `T`
(`PassesPromotionCheck σ v T`), and the step is `r` (`r = .next e σ'`).
-/
theorem promotionCheck_eq_next {fuel : Nat} {σ σ' : State} {v : Value} {T : τ} {r : StepResult}
    {e : LoweredExpr} (h : promotionCheck fuel σ v T r = .next e σ') :
    PassesPromotionCheck σ v T ∧ r = .next e σ' := by
  unfold promotionCheck at h
  split at h
  · exact ⟨.trust ‹_›, h⟩
  · split at h
    · obtain ⟨b, hb, hk⟩ := withCheck_eq_next h
      cases b
      · simp at hk
      · exact ⟨.verify ‹_› ‹_› hb, hk⟩
    · simp at h

/--
Completeness of `headStep`: if `e` takes a head step to `e'` (`h`), then either:
- `headStep` finds it, given enough fuel, and never reports that `e` is stuck
  (`Converges (headStep · e σ) (.next e' σ')`); or
- the step is one that a check that doesn't terminate takes, which goes nowhere
  (`e' = e ∧ σ' = σ`), and `headStep` runs out of fuel there, however much it has
  (`∀ fuel, headStep fuel e σ = .outOfFuel`).
-/
theorem headStep_complete {e e' : LoweredExpr} {σ σ' : State} (h : HeadStep e σ e' σ') :
    Converges (headStep · e σ) (.next e' σ') ∨
      (e' = e ∧ σ' = σ ∧ ∀ fuel, headStep fuel e σ = .outOfFuel) := by
  cases h with
  | null | declare | blockNil | blockDeclare | seq | nullCheckNull | condTrue | condFalse =>
    exact .inl (Converges.of_eq fun _ => rfl)
  | @blockCons m ms σ h =>
    cases m
    case declare v T startsNull => exact absurd rfl (h v T startsNull)
    all_goals exact .inl (Converges.of_eq fun _ => rfl)
  | @varAt x T ℓ v σ hℓ hv =>
    exact .inl (Converges.congr (fun fuel => by simp [headStep, hℓ])
      (promotionCheck_converges hv _))
  | @nullCheck v σ h =>
    cases v
    case null => exact absurd rfl h
    all_goals exact .inl (Converges.of_eq fun _ => rfl)
  | asTrue hS h | asFalse hS h | «is» hS h =>
    exact .inl (Converges.congr (fun fuel => by simp only [headStep, hS]; rfl)
      (withCheck_converges h (by rfl)))
  | asDiverge hS h | isDiverge hS h =>
    exact .inr ⟨rfl, rfl, fun fuel => by simp only [headStep, hS]; exact withCheck_diverge h⟩
  | propertyGetField hf hw hc =>
    exact .inl (Converges.congr (fun fuel => by simp [headStep, hf, hw])
      (promotionCheck_converges hc _))
  | propertyGetGetter hf hg hc =>
    exact .inl (Converges.congr (fun fuel => by simp [headStep, hf, hg])
      (promotionCheck_converges hc _))
  | @bubble Ki v σ =>
    cases Ki <;> exact .inl (Converges.of_eq fun _ => rfl)

/--
Soundness of `headStep`: every step that it finds (`h`) is a head step (`HeadStep e σ e' σ'`).
-/
theorem headStep_sound {fuel : Nat} {e e' : LoweredExpr} {σ σ' : State}
    (h : headStep fuel e σ = .next e' σ') : HeadStep e σ e' σ' := by
  unfold headStep at h
  repeat' split at h
  all_goals first
    | (cases h; done)
    | (obtain ⟨rfl, rfl⟩ := StepResult.next.inj h
       first
         | (constructor <;> assumption)
         | (rename_i hb
            first
              | (subst hb; exact .blockDeclare)
              | (simp only [Bool.not_eq_true] at hb; subst hb; exact .blockDeclare))
         | exact .bubble (Ki := .nullCheck)
         | exact .bubble (Ki := .as _)
         | exact .bubble (Ki := .is _)
         | exact .bubble (Ki := .cond _ _ _)
         | exact .bubble (Ki := .propertyGet _ _)
         | exact .bubble (Ki := .seq _))
    | (obtain ⟨hc, hr⟩ := promotionCheck_eq_next h
       obtain ⟨rfl, rfl⟩ := StepResult.next.inj hr
       first
         | exact .varAt ‹_› hc
         | exact .propertyGetField ‹_› ‹_› hc
         | exact .propertyGetGetter ‹_› ‹_› hc)
    | (obtain ⟨b, hb, hk⟩ := withCheck_eq_next h
       first
         | (obtain ⟨rfl, rfl⟩ := StepResult.next.inj hk
            exact .is ‹_› hb)
         | (cases b <;> simp only [Bool.false_eq_true, ite_true, ite_false] at hk <;>
            obtain ⟨rfl, rfl⟩ := StepResult.next.inj hk
            · exact .asFalse ‹_› hb
            · exact .asTrue ‹_› hb))

/--
If the expression `e` in the hole of `Ki` hasn't completed (`he`), then `primStep` on `Ki.fill e`
takes `e`'s step, and plugs the result back into the hole (`stepIn Ki (primStep fuel e σ)`).
-/
theorem primStep_fill (fuel : Nat) {Ki : EctxItem} {e : LoweredExpr} (σ : State)
    (he : e.toOutcome? = none) : primStep fuel (Ki.fill e) σ = stepIn Ki (primStep fuel e σ) := by
  cases Ki <;> simp [EctxItem.fill, primStep, he]

/--
If the expression `e` in the hole of evaluation context `K` hasn't completed (`he`), then
`primStep` on `fillCtx K e` takes `e`'s step, and plugs the result back into the context
(`(primStep fuel e σ).map (fillCtx K)`).
-/
theorem primStep_fillCtx (fuel : Nat) (K : List EctxItem) {e : LoweredExpr} (σ : State)
    (he : e.toOutcome? = none) :
    primStep fuel (fillCtx K e) σ = (primStep fuel e σ).map (fillCtx K) := by
  induction K generalizing e with
  | nil => change primStep fuel e σ = _; cases primStep fuel e σ <;> rfl
  | cons Ki K ih =>
    change primStep fuel (fillCtx K (Ki.fill e)) σ = _
    rw [ih (EctxItem.toOutcome?_fill Ki e), primStep_fill fuel σ he]
    cases primStep fuel e σ <;> rfl

/--
At a redex `e`, one that takes a head step (`h`), `primStep` takes the head step
(`primStep fuel e σ = headStep fuel e σ`).
-/
theorem primStep_of_headStep {e e' : LoweredExpr} {σ σ' : State} (h : HeadStep e σ e' σ')
    (fuel : Nat) : primStep fuel e σ = headStep fuel e σ := by
  have hin : ∀ (Ki : EctxItem) (e₁ : LoweredExpr), e = Ki.fill e₁ → e₁.toOutcome?.isSome := by
    rintro Ki e₁ rfl
    exact h.isSome_toOutcome?_of_fill
  cases e with
  | nullCheck m => simp [primStep, hin .nullCheck m rfl]
  | «as» m T => simp [primStep, hin (.as T) m rfl]
  | «is» m T => simp [primStep, hin (.is T) m rfl]
  | cond m₁ m₂ m₃ T => simp [primStep, hin (.cond m₂ m₃ T) m₁ rfl]
  | propertyGet m p T => simp [primStep, hin (.propertyGet p T) m rfl]
  | seq m₁ m₂ => simp [primStep, hin (.seq m₂) m₁ rfl]
  | _ => rfl

omit [RtSubChecker τ] in
/--
If every step that `r` reports is a step of `e` (`hr`), then every step that `stepIn Ki r` reports
(`h`) is a step of `Ki.fill e`. `primStep_sound` uses this to carry soundness from the hole of `Ki`
out to the whole expression.
-/
theorem stepIn_sound {Ki : EctxItem} {e e' : LoweredExpr} {σ σ' : State} {r : StepResult}
    (hr : ∀ {e'' σ''}, r = .next e'' σ'' → (e, σ) -<[]>-> (e'', σ'', []))
    (h : stepIn Ki r = .next e' σ') : (Ki.fill e, σ) -<[]>-> (e', σ', []) := by
  cases r with
  | next e'' σ'' =>
    simp only [stepIn, StepResult.map, StepResult.next.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    exact primStep_fillItem (hr rfl)
  | stuck | outOfFuel => cases h

/--
**Soundness of the interpreter**: every step that `primStep` takes
(`primStep fuel e σ = .next e' σ'`) is a step of the semantics (`(e, σ) -<[]>-> (e', σ', [])`).
-/
public theorem primStep_sound {fuel : Nat} : ∀ (e : LoweredExpr) {σ : State} {e' : LoweredExpr}
    {σ' : State}, primStep fuel e σ = .next e' σ' → (e, σ) -<[]>-> (e', σ', [])
  | e, σ, e', σ', h => by
    rw [primStep.eq_def] at h
    cases e <;> dsimp only at h <;>
      repeat' first
        | exact (headStep_sound h).primStep
        | (have := stepIn_sound (primStep_sound _) h; exact this)
        | split at h

/--
**Completeness of the interpreter**: if `e` takes a step to `e'` (`h`), then the step makes no
observations and forks no threads (`obs = [] ∧ efs = []`), and either:
- `primStep` finds it, given enough fuel, and never reports that `e` is stuck
  (`Converges (primStep · e σ) (.next e' σ')`); or
- the step is one that a run-time subtype check that doesn't terminate takes, which goes nowhere
  (`e' = e ∧ σ' = σ`), and `primStep` runs out of fuel there, however much it has
  (`∀ fuel, primStep fuel e σ = .outOfFuel`).
-/
public theorem primStep_complete {e e' : LoweredExpr} {σ σ' : State} {obs : List Obs}
    {efs : List LoweredExpr} (h : (e, σ) -<obs>-> (e', σ', efs)) :
    obs = [] ∧ efs = [] ∧
      (Converges (primStep · e σ) (.next e' σ') ∨
        (e' = e ∧ σ' = σ ∧ ∀ fuel, primStep fuel e σ = .outOfFuel)) := by
  obtain ⟨hbase⟩ := h
  rename_i e₁ e₂ K
  obtain ⟨hbase, rfl, rfl⟩ := hbase
  refine ⟨rfl, rfl, ?_⟩
  have heq : ∀ fuel, primStep fuel (fill K e₁) σ = (headStep fuel e₁ σ).map (fillCtx K) := by
    intro fuel
    rw [fill_eq_fillCtx, primStep_fillCtx fuel K σ hbase.toOutcome?_eq_none,
      primStep_of_headStep hbase]
  rcases headStep_complete hbase with hc | ⟨rfl, rfl, hd⟩
  · exact .inl (Converges.congr heq (hc.map _))
  · exact .inr ⟨rfl, rfl, fun fuel => by rw [heq, hd]; rfl⟩

/-- If `primStep` reports that `e` is stuck (`h`), it is: `e` takes no step (`Irreducible`). -/
public theorem primStep_stuck {fuel : Nat} {e : LoweredExpr} {σ : State}
    (h : primStep fuel e σ = .stuck) : Irreducible (e, σ) := by
  intro obs e' σ' efs hstep
  obtain ⟨-, -, hc | ⟨-, -, hd⟩⟩ := primStep_complete hstep
  · rcases hc.1 fuel with h' | h' <;> simp only [h] at h' <;> cases h'
  · rw [hd fuel] at h
    cases h

/--
`Steps (e, σ) (e', σ')` says that expression `e`, in state `σ`, reaches expression `e'` and state
`σ'` by zero or more steps of the semantics. Each step is a step as iris-lean defines it (a head
step of the redex inside its evaluation context; see `Language.lean`), making no observations and
forking no threads. This is the reflexive transitive closure of the step relation, used to state
what `run` computes (`run_done` and `run_stuck`).
-/
public abbrev Steps : LoweredExpr × State → LoweredExpr × State → Prop :=
  Relation.ReflTransGen fun (e, σ) (e', σ') => (e, σ) -<[]>-> (e', σ', [])

/--
Running an expression that has already completed with outcome `o` (`h`) gives its outcome, without
taking a step (`.done o σ`).
-/
theorem run_of_toOutcome? {fuel : Nat} {e : LoweredExpr} {σ : State} {o : Outcome}
    (h : e.toOutcome? = some o) : run fuel e σ = .done o σ := by
  cases fuel <;> simp [run, h]

/--
Running an expression that hasn't completed (`h`), with no fuel left, runs out of fuel
(`.outOfFuel e σ`).
-/
theorem run_zero {e : LoweredExpr} {σ : State} (h : e.toOutcome? = none) :
    run 0 e σ = .outOfFuel e σ := by
  simp [run, h]

/--
Running an expression that hasn't completed (`h`), with fuel left, takes one step with `primStep`
and runs the result with one less unit of fuel.
-/
theorem run_succ {fuel : Nat} {e : LoweredExpr} {σ : State} (h : e.toOutcome? = none) :
    run (fuel + 1) e σ =
      match primStep fuel e σ with
      | .next e' σ' => run fuel e' σ'
      | .stuck => .stuck e σ
      | .outOfFuel => .outOfFuel e σ := by
  rw [run]
  simp [h]

/--
If `run` says that a program completes with outcome `o` in state `σ'` (`h`), it does: it steps there
(`Steps (e, σ) (o.toExpr, σ')`).
-/
public theorem run_done {fuel : Nat} {e : LoweredExpr} {σ σ' : State} {o : Outcome}
    (h : run fuel e σ = .done o σ') : Steps (e, σ) (o.toExpr, σ') := by
  induction fuel generalizing e σ with
  | zero =>
    cases ho : e.toOutcome? with
    | some o' =>
      rw [run_of_toOutcome? ho] at h
      cases h
      rw [LoweredExpr.toExpr_of_toOutcome? ho]
    | none =>
      rw [run_zero ho] at h
      cases h
  | succ fuel ih =>
    cases ho : e.toOutcome? with
    | some o' =>
      rw [run_of_toOutcome? ho] at h
      cases h
      rw [LoweredExpr.toExpr_of_toOutcome? ho]
    | none =>
      rw [run_succ ho] at h
      cases hs : primStep fuel e σ <;> simp only [hs] at h
      · exact .head (primStep_sound _ hs) (ih h)
      · cases h
      · cases h

/--
If `run` says that a program gets stuck at `e'` in state `σ'` (`h`), it does: it steps there
(`Steps (e, σ) (e', σ')`), and gets stuck (`Stuck (e', σ')`).
-/
public theorem run_stuck {fuel : Nat} {e e' : LoweredExpr} {σ σ' : State}
    (h : run fuel e σ = .stuck e' σ') : Steps (e, σ) (e', σ') ∧ Stuck (e', σ') := by
  induction fuel generalizing e σ with
  | zero =>
    cases ho : e.toOutcome? with
    | some o' =>
      rw [run_of_toOutcome? ho] at h
      cases h
    | none =>
      rw [run_zero ho] at h
      cases h
  | succ fuel ih =>
    cases ho : e.toOutcome? with
    | some o' =>
      rw [run_of_toOutcome? ho] at h
      cases h
    | none =>
      rw [run_succ ho] at h
      cases hs : primStep fuel e σ <;> simp only [hs] at h
      · obtain ⟨hsteps, hstuck⟩ := ih h
        exact ⟨.head (primStep_sound _ hs) hsteps, hstuck⟩
      · cases h
        exact ⟨.refl, by simpa using ho, primStep_stuck hs⟩
      · cases h

end DartSemantics.Interp
