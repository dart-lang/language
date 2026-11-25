module
public import DartSemantics.HeadStep
public import Iris.ProgramLogic.EctxiLanguage

/-!
# The semantics as an iris-lean language

This file makes the semantics an instance of iris-lean's `EctxItemLanguage`: a language given by
a head-step relation (`HeadStep`) and evaluation context items (`EctxItem`). iris-lean derives
from it the full step relation (a head step inside any evaluation context), and the program logic
built on it.

iris-lean writes a step of a program as `(e, σ) -<obs>-> (e', σ', efs)`: in state `σ`, the
expression `e` takes one step (a head step inside some evaluation context) to `e'`, leaving state
`σ'`, making the observations `obs` (see `Obs`) and forking the threads `efs`. The semantics makes
no observations and forks no threads, so both lists are always empty.

iris-lean's *values* are `Outcome`s: an expression that has thrown an exception counts as a value,
as well as one that has completed normally. This is what makes propagating exceptions by head
steps lawful. iris-lean requires that if `Ki.fill e` takes a head step, then `e` is a value
(`base_ctx_step_val`), and propagating an exception (`HeadStep.bubble`) is a head step of
`Ki.fill (throwing v)`. Once the semantics has `return`, `break` and `continue` statements, they
will complete abruptly in the same way, with new kinds of `Outcome` that propagate outward one
evaluation context item at a time until they reach the construct that handles them.
-/

namespace DartSemantics

open DartLang Iris.ProgramLogic

variable {τ : Type} [Γ : DartRuntimeTypeRepr τ]

local notation "Value" => Value (τ := τ)
local notation "LoweredExpr" => LoweredExpr (τ := τ)
local notation "EctxItem" => EctxItem (τ := τ)
local notation "Outcome" => Outcome (τ := τ)
local notation "State" => State (τ := τ)

/-- An expression's iris-lean value is its outcome, if it has completed. -/
public instance instToVal : ToVal LoweredExpr Outcome where
  toVal := LoweredExpr.toOutcome?
  ofVal := Outcome.toExpr
  coe_of_toVal_eq_some := LoweredExpr.toExpr_of_toOutcome?
  toVal_coe := Outcome.toOutcome?_toExpr

omit Γ in
/-- iris-lean's `toVal` is `LoweredExpr.toOutcome?`. -/
@[simp]
public theorem toVal_eq (e : LoweredExpr) : toVal e = e.toOutcome? := rfl

omit Γ in
/-- iris-lean's `ofVal` is `Outcome.toExpr`. -/
@[simp]
public theorem ofVal_eq (o : Outcome) : ToVal.ofVal (Expr := LoweredExpr) o = o.toExpr := rfl

variable [P : SemanticParams τ]

/--
An expression `e` that takes a head step (`h`) hasn't completed (`e.toOutcome? = none`): an
expression that has completed takes no head step.
-/
public theorem HeadStep.toOutcome?_eq_none {e e' : LoweredExpr} {σ σ' : State}
    (h : HeadStep e σ e' σ') : e.toOutcome? = none := by
  cases h <;> first | rfl | exact EctxItem.toOutcome?_fill _ _

/--
If `Ki.fill e` takes a head step (`h`), then `e` has completed (`e.toOutcome?.isSome`): each head
step of an expression with a hole either uses the completed value in the hole, or propagates the
exception thrown there.
-/
public theorem HeadStep.isSome_toOutcome?_of_fill {Ki : EctxItem} {e e' : LoweredExpr}
    {σ σ' : State} (h : HeadStep (Ki.fill e) σ e' σ') : e.toOutcome?.isSome := by
  generalize hE : Ki.fill e = E at h
  cases h with
  | bubble =>
    rename_i Ki' _
    cases Ki <;> cases Ki' <;> simp_all [EctxItem.fill, LoweredExpr.toOutcome?]
  | _ => cases Ki <;> simp_all [EctxItem.fill, LoweredExpr.toOutcome?]

/--
Observations, which iris-lean uses to support *prophecy variables*: a proof technique for programs
whose correctness depends on a choice they'll make later (typically a nondeterministic one), in
which the proof predicts the choice and uses the prediction before the choice is made. Each step of
an iris-lean language records the observations that such predictions refer to.

The semantics doesn't make any observations yet: no proof so far needs to predict a choice that a
program makes later. That may change once the semantics models nondeterminism, such as the order in
which asynchronous code runs. `Obs` is `Unit`, and every step's list of observations is empty (see
`BaseStepRel`).
-/
public abbrev Obs := Unit

/-- iris-lean's head-step relation: a `HeadStep` that makes no observations and forks nothing. -/
@[expose]
public def BaseStepRel : LoweredExpr × State → List Obs → LoweredExpr × State × List LoweredExpr →
    Prop
  | (e, σ), obs, (e', σ', efs) => HeadStep e σ e' σ' ∧ obs = [] ∧ efs = []

/--
The semantics as an iris-lean language.

The fields after `fillItem` are the laws that iris-lean requires of a language given by head steps
and evaluation context items. It uses them to show that the full step relation is well behaved:
for example, that an expression can be split into an evaluation context and a subexpression that
takes a head step in at most one way.
-/
public instance instEctxItemLanguage : EctxItemLanguage LoweredExpr EctxItem State Obs Outcome where
  -- The head-step relation is `HeadStep`, with no observations and no forked threads.
  baseStep := BaseStepRel
  -- Plugging an expression into the hole of an evaluation context item.
  fillItem := EctxItem.fill
  -- Plugging two different expressions into the same item gives two different expressions.
  fillItem_inj {Ki} := by
    intro e₁ e₂ h
    cases Ki <;> simp_all [EctxItem.fill]
  -- If plugging `e` into an item gives a completed expression (a value, for iris-lean), then `e`
  -- has completed. This holds trivially, because plugging an expression into an item never gives a
  -- completed expression: the result is a null check, a cast, and so on, which still has a step to
  -- take, whatever `e` is. (Only `val` and `throwing` expressions are completed.)
  fillItem_val e Ki h := by
    simp [EctxItem.toOutcome?_fill] at h
  -- An expression can be split into an item and a subexpression that hasn't completed in at most
  -- one way: evaluation order is deterministic.
  fillItem_no_val_inj Ki₁ Ki₂ hv₁ hv₂ heq := by
    cases Ki₁ <;> cases Ki₂ <;> simp_all [EctxItem.fill]
  -- A completed expression takes no head step.
  val_stuck {e σ obs e' σ' eₜ} h := by
    obtain ⟨h, -, -⟩ := h
    simpa using h.toOutcome?_eq_none
  -- If `Ki.fill e` takes a head step, then `e` has completed (normally, or by throwing). Head steps
  -- act only on expressions whose subexpressions in evaluation position have finished; a step
  -- inside an unfinished `e` is a head step of some part of `e`, inside a larger evaluation
  -- context.
  base_ctx_step_val {Ki e σ obs e' σ' eₜ} h := by
    obtain ⟨h, -, -⟩ := h
    simpa using h.isSome_toOutcome?_of_fill

/-- iris-lean's `fill` is `fillCtx`. -/
@[simp]
public theorem fill_eq_fillCtx (K : List EctxItem) (e : LoweredExpr) :
    EctxItemLanguage.fill (Expr := LoweredExpr) K e = fillCtx K e := rfl

open EctxItemLanguage Language.Notation

/--
A head step (`h`) is a step: a step in the empty evaluation context, with no observations and no
forked threads (`(e, σ) -<[]>-> (e', σ', [])`; see the module doc for the notation).
-/
public theorem HeadStep.primStep {e e' : LoweredExpr} {σ σ' : State} (h : HeadStep e σ e' σ') :
    (e, σ) -<[]>-> (e', σ', []) := by
  have := BaseStep.ContextStep.intro (Ectx := List EctxItem) (K := []) (obs := []) (eₜ := [])
    (σ₁ := σ) (σ₂ := σ') (e₁ := e) (e₂ := e') (show BaseStepRel (e, σ) [] (e', σ', []) from
      ⟨h, rfl, rfl⟩)
  simp only [fill_nil] at this
  exact this

/--
Steps are closed under evaluation context items: if `e` steps to `e'` (`h`), then `Ki.fill e` steps
to `Ki.fill e'`, with the same observations and forked threads.
-/
public theorem primStep_fillItem {Ki : EctxItem} {e e' : LoweredExpr} {σ σ' : State}
    {obs : List Obs} {efs : List LoweredExpr} (h : (e, σ) -<obs>-> (e', σ', efs)) :
    (Ki.fill e, σ) -<obs>-> (Ki.fill e', σ', efs) := by
  obtain ⟨hbase⟩ := h
  rename_i e₁ e₂ K
  have h₁ : Ki.fill (fill K e₁) = fill (K ++ [Ki]) e₁ := by simp; rfl
  have h₂ : Ki.fill (fill K e₂) = fill (K ++ [Ki]) e₂ := by simp; rfl
  rw [h₁, h₂]
  exact .intro hbase

end DartSemantics
