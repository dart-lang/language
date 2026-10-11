module
public import DartSemantics.PrimitiveLaws

/-!
# Proof-mode tactics

Tactics for proving weakest preconditions of `LoweredExpr`s in iris-lean's proof mode, modeled on
iris-lean's HeapLang tactics (whose own `wp_*` tactics only work for HeapLang). HeapLang is the
small example language that comes with Iris, which most Iris material uses; its tactics are the
usual way to step through a program in a proof. (The README's "Reading the Iris parts" section
explains proof mode, and weakest preconditions.)

Each tactic takes one or more steps of the program in the goal, so that a proof follows the
program's execution:

- `wp_value`: when the expression has completed, replace its weakest precondition with the
  postcondition applied to its outcome.
- `wp_pure`: take one head step that doesn't depend on, or change, the state.
- `wp_bind`: focus on the subexpression in evaluation position, if it hasn't completed, by binding
  over one evaluation context item.
- `wp_pures`: repeat the three above until none applies. The goal is then either a postcondition,
  or a weakest precondition of an expression whose next step involves the state (or a run-time
  subtype check), wrapped in the evaluation context it came from.
- `wp_alloc ℓ H`: take the step of a declaration at the start of a block, introducing the new cell
  `ℓ` and its points-to `H`.
- `wp_load H`: take the step of reading a variable or an instance variable, using the points-to
  `H` for the cell read. The value's dynamic type is proved automatically for the null object,
  booleans, objects whose header is in the context, and values with a `HasDynamicType` hypothesis
  in the context. Pure side conditions (such as the subtype fact for the promotion check) are
  proved by `decide` or `rfl` when they can be, and otherwise left as goals after the main one.

Steps that involve a run-time subtype check (cast expressions and is-expressions) or a getter that
is user code are taken by applying the laws in `PrimitiveLaws.lean` directly.

Each tactic works by applying a lemma whose conclusion is a proof-mode goal `Δ ⊢ WP e {{ Φ }}`
(where `Δ` is the proof mode's context of Iris hypotheses) for a particular shape of `e`, so that
Lean's unifier, rather than iris-lean's `iapply`, matches it against the goal. (`iapply` doesn't
unfold definitions such as `EctxItem.fill`.)

These macros are deliberately simple. If their error messages or performance become a problem once
there are significant proofs, a meta-level implementation (in the style of Rocq's HeapLang
tactics, with a `PureExec` class and a tactic that finds the redex in an evaluation context, or
tactics that build proof terms directly) may be worth the extra code.
-/

namespace DartSemantics

open DartLang Iris Iris.BI Iris.ProgramLogic Iris.Std

variable {τ : Type}

local notation "Variable" => Variable (τ := τ)
local notation "Property" => Property (τ := τ)
local notation "Value" => Value (τ := τ)
local notation "LoweredExpr" => LoweredExpr (τ := τ)
local notation "Cell" => Cell (τ := τ)

/-! Rewrite rules that `dart_wp_tidy` uses to tidy goals after a step. -/

public theorem tidy_toExpr_normal (v : Value) :
    (DartLang.Outcome.normal v).toExpr = LoweredExpr.val v := rfl
public theorem tidy_toExpr_throwing (v : Value) :
    (DartLang.Outcome.throwing v).toExpr = LoweredExpr.throwing v := rfl
public theorem tidy_fill_nullCheck (m : LoweredExpr) :
    (EctxItem.nullCheck (τ := τ)).fill m = .nullCheck m := rfl
public theorem tidy_fill_as (T : τ) (m : LoweredExpr) : (EctxItem.as T).fill m = .as m T := rfl
public theorem tidy_fill_is (T : τ) (m : LoweredExpr) : (EctxItem.is T).fill m = .is m T := rfl
public theorem tidy_fill_cond (m₂ m₃ : LoweredExpr) (T : τ) (m : LoweredExpr) :
    (EctxItem.cond m₂ m₃ T).fill m = .cond m m₂ m₃ T := rfl
public theorem tidy_fill_propertyGet (p : Property) (T : τ) (m : LoweredExpr) :
    (EctxItem.propertyGet p T).fill m = .propertyGet m p T := rfl
public theorem tidy_fill_seq (m₂ m : LoweredExpr) : (EctxItem.seq m₂).fill m = .seq m m₂ := rfl

variable [Γ : DartRuntimeTypeRepr τ]
variable {hlc : HasLC} {GF : BundledGFunctors} [DartGS τ hlc GF] [P : SemanticParams τ]
-- (The type of `Φ` is spelled out because a local notation doesn't work in a `variable` binder; see
-- the same binder in `PrimitiveLaws.lean`.)
variable {s : Stuckness} {E : CoPset} {Φ : DartLang.Outcome (τ := τ) → IProp GF}
variable {Δ : IProp GF}

include hlc

open Iris.ProofMode (Entails')

/-! The proof-mode goal `Δ ⊢ P` is `Entails' Δ P`, so the tactic lemmas are stated with it. -/

/--
The proof-mode form of `wp_val`: to prove that `.val v` satisfies `Φ` from the hypotheses `Δ`, prove
`Φ (.normal v)` (`H`).
-/
public theorem tac_wp_val {v : Value} (H : Entails' Δ (Φ (.normal v))) :
    Entails' Δ (WP (LoweredExpr.val v) @ s; E {{ Φ }}) :=
  (show Δ ⊢ _ from H).trans (wp_val v)

/--
The proof-mode form of `wp_throwing`: to prove that `.throwing v` satisfies `Φ` from the hypotheses
`Δ`, prove `Φ (.throwing v)` (`H`).
-/
public theorem tac_wp_throwing {v : Value} (H : Entails' Δ (Φ (.throwing v))) :
    Entails' Δ (WP (LoweredExpr.throwing v) @ s; E {{ Φ }}) :=
  (show Δ ⊢ _ from H).trans (wp_throwing v)

/--
The proof-mode form of `wp_pure_step`: to prove that `e₁` satisfies `Φ` from the hypotheses `Δ`,
where `e₁` hasn't completed (`hv`) and in every state takes a head step to `e₂` that leaves the
state unchanged (`h`), prove that `e₂` satisfies `Φ` one step later (`H`).
-/
public theorem tac_wp_pure {e₁ e₂ : LoweredExpr} (hv : e₁.toOutcome? = none)
    (h : ∀ σ, HeadStep e₁ σ e₂ σ) (H : Entails' Δ iprop(▷ WP e₂ @ s; E {{ Φ }})) :
    Entails' Δ (WP e₁ @ s; E {{ Φ }}) :=
  (show Δ ⊢ _ from H).trans (wp_pure_step hv h)

/--
The proof-mode form of `wp_bind_item`, for an evaluation context item `Ki` whose hole holds an
expression `e` that hasn't completed (`_he`): to prove that `Ki.fill e` satisfies `Φ` from the
hypotheses `Δ`, prove that `e` satisfies the postcondition that plugging its outcome `o` back into
`Ki` satisfies `Φ` (`H`).
-/
public theorem tac_wp_bind (Ki : EctxItem (τ := τ)) {e : LoweredExpr} (_he : e.toOutcome? = none)
    (H : Entails' Δ (WP e @ s; E {{ o, WP (Ki.fill o.toExpr) @ s; E {{ Φ }} }})) :
    Entails' Δ (WP (Ki.fill e) @ s; E {{ Φ }}) :=
  (show Δ ⊢ _ from H).trans (wp_bind_item Ki)

/--
The proof-mode form of `wp_blockDeclare`: to prove that a block that starts with a declaration of
`v` satisfies `Φ` from the hypotheses `Δ`, prove its premise (`H`).
-/
public theorem tac_wp_blockDeclare {v : Variable} {T : τ} {startsNull : Bool}
    {ms : List LoweredExpr}
    (H : Entails' Δ iprop(▷ (∀ ℓ, ℓ ↦ (if startsNull then .val .null else .uninit : Cell) -∗
        WP (LoweredExpr.block (LoweredExpr.resolveBlock v ℓ ms)) @ s; E {{ Φ }}))) :
    Entails' Δ (WP (LoweredExpr.block (.declare v T startsNull :: ms)) @ s; E {{ Φ }}) :=
  (show Δ ⊢ _ from H).trans wp_blockDeclare

/--
The proof-mode form of `wp_varAt`, with the subtype fact as a pure premise (`⌜S ≤ T⌝`), after the
dynamic type: to prove that reading `x`, resolved to the cell at `ℓ`, satisfies `Φ` from the
hypotheses `Δ`, prove `wp_varAt`'s premises (`H`).
-/
public theorem tac_wp_load {x : Variable} {T S : τ} {ℓ : Loc} {dq : DFrac} {v : Value}
    (H : Entails' Δ iprop(HasDynamicType v S ∗ ⌜S ≤ T⌝ ∗ ▷ (ℓ ↦{dq} (.val v : Cell)) ∗
        ▷ ((ℓ ↦{dq} (.val v : Cell)) -∗ Φ (.normal v)))) :
    Entails' Δ (WP (LoweredExpr.varAt x T ℓ) @ s; E {{ Φ }}) := by
  refine (show Δ ⊢ _ from H).trans ?_
  iintro ⟨#Hty, %hST, Hl, HΦ⟩
  iapply wp_varAt hST
  isplitr
  · iexact Hty
  isplitl [Hl]
  · iexact Hl
  · iexact HΦ

/--
The proof-mode form of `wp_propertyGetField`, with its pure facts as premises
(`⌜fs.lookup p.name = some ℓf⌝`, after the object's own cell, and `⌜S ≤ T⌝`, after the dynamic
type): to prove that reading property `p` of the object at `ℓ` satisfies `Φ` from the hypotheses
`Δ`, prove `wp_propertyGetField`'s premises (`H`).
-/
public theorem tac_wp_load_field {ℓ ℓf : Loc} {p : Property} {T C S : τ}
    {fs : List (String × Loc)} {dq : DFrac} {w : Value}
    (H : Entails' Δ iprop(ℓ ↦{.discard} (.object C fs : Cell) ∗ ⌜fs.lookup p.name = some ℓf⌝ ∗
        HasDynamicType w S ∗ ⌜S ≤ T⌝ ∗ ▷ (ℓf ↦{dq} (.val w : Cell)) ∗
        ▷ ((ℓf ↦{dq} (.val w : Cell)) -∗ Φ (.normal w)))) :
    Entails' Δ (WP (LoweredExpr.propertyGet (.val (.obj ℓ)) p T) @ s; E {{ Φ }}) := by
  refine (show Δ ⊢ _ from H).trans ?_
  iintro ⟨#Hobj, %hf, #Hty, %hST, Hl, HΦ⟩
  iapply wp_propertyGetField hf hST
  isplitr
  · iexact Hobj
  isplitr
  · iexact Hty
  isplitl [Hl]
  · iexact Hl
  · iexact HΦ

end DartSemantics

/-- Take a head step that doesn't depend on, or change, the state (for `wp_pure`). -/
syntax "dart_pure_head_step" : tactic

macro_rules
  | `(tactic| dart_pure_head_step) => `(tactic| first
    | exact DartSemantics.HeadStep.null
    | exact DartSemantics.HeadStep.declare
    | exact DartSemantics.HeadStep.blockNil
    | (refine DartSemantics.HeadStep.blockCons ?_; intro _ _ _ h; cases h)
    | exact DartSemantics.HeadStep.seq
    | exact DartSemantics.HeadStep.nullCheckNull
    | (refine DartSemantics.HeadStep.nullCheck ?_; intro h; cases h)
    | exact DartSemantics.HeadStep.condTrue
    | exact DartSemantics.HeadStep.condFalse
    | exact DartSemantics.HeadStep.bubble (Ki := .nullCheck)
    | exact DartSemantics.HeadStep.bubble (Ki := .as _)
    | exact DartSemantics.HeadStep.bubble (Ki := .is _)
    | exact DartSemantics.HeadStep.bubble (Ki := .cond _ _ _)
    | exact DartSemantics.HeadStep.bubble (Ki := .propertyGet _ _)
    | exact DartSemantics.HeadStep.bubble (Ki := .seq _))

/-- Tidy the goal after a step: reduce `Outcome.toExpr` and beta-reduce postconditions. -/
syntax "dart_wp_tidy" : tactic

macro_rules
  | `(tactic| dart_wp_tidy) =>
    `(tactic| try simp only [DartSemantics.tidy_toExpr_normal, DartSemantics.tidy_toExpr_throwing,
      DartSemantics.tidy_fill_nullCheck, DartSemantics.tidy_fill_as, DartSemantics.tidy_fill_is,
      DartSemantics.tidy_fill_cond, DartSemantics.tidy_fill_propertyGet,
      DartSemantics.tidy_fill_seq])

/--
When the expression has completed, replace its weakest precondition with the postcondition applied
to its outcome.
-/
syntax "wp_value" : tactic

macro_rules
  | `(tactic| wp_value) => `(tactic|
    ((first
      | refine DartSemantics.tac_wp_val ?_
      | refine DartSemantics.tac_wp_throwing ?_); dart_wp_tidy))

/-- Take one head step that doesn't depend on, or change, the state. -/
syntax "wp_pure" : tactic

macro_rules
  | `(tactic| wp_pure) => `(tactic|
    (apply DartSemantics.tac_wp_pure
     · rfl
     · intro _
       dart_pure_head_step
     inext
     dart_wp_tidy))

/-- Focus on the subexpression in evaluation position, if it hasn't completed. -/
syntax "wp_bind" : tactic

macro_rules
  | `(tactic| wp_bind) => `(tactic|
    ((first
      | refine DartSemantics.tac_wp_bind .nullCheck (by rfl) ?_
      | refine DartSemantics.tac_wp_bind (.as _) (by rfl) ?_
      | refine DartSemantics.tac_wp_bind (.is _) (by rfl) ?_
      | refine DartSemantics.tac_wp_bind (.cond _ _ _) (by rfl) ?_
      | refine DartSemantics.tac_wp_bind (.propertyGet _ _) (by rfl) ?_
      | refine DartSemantics.tac_wp_bind (.seq _) (by rfl) ?_); dart_wp_tidy))

/--
Take every step that doesn't involve the state: repeat `wp_value`, `wp_pure` and `wp_bind` until
none applies.
-/
syntax "wp_pures" : tactic

macro_rules
  | `(tactic| wp_pures) =>
    `(tactic| (dart_wp_tidy; repeat (first | wp_value | wp_pure | wp_bind)))

/--
`wp_alloc ℓ H` takes the step of a declaration at the start of a block, introducing the new cell
`ℓ` and its points-to `H`, and resolves the declared variable in the rest of the block.
-/
syntax "wp_alloc " ident ppSpace ident : tactic

macro_rules
  | `(tactic| wp_alloc $l $h) => `(tactic|
    (refine DartSemantics.tac_wp_blockDeclare ?_
     inext
     iintro %$l $h:ident
     simp (config := { decide := true }) only [DartLang.LoweredExpr.resolveBlock,
       DartLang.LoweredExpr.resolve, ite_true, ite_false, Bool.false_eq_true, ↓reduceIte]))

/-- Prove that a value has a dynamic type: the null object, a boolean, an object whose header
(a persistent points-to for its own cell) is in the context, or a value with a `HasDynamicType`
hypothesis in the context. -/
syntax "dart_dynamic_type" : tactic

macro_rules
  | `(tactic| dart_dynamic_type) => `(tactic| first
    | iapply DartSemantics.HasDynamicType.null
    | iapply DartSemantics.HasDynamicType.bool
    | (iapply DartSemantics.HasDynamicType.obj; iassumption)
    | iassumption)

/--
Prove a pure side condition of a load: a subtype fact, or the lookup of an instance variable. If
neither `decide` nor `rfl` proves it (for example, a subtype fact about types that aren't concrete),
it's left as a goal, after the remaining goals.
-/
syntax "dart_load_side_condition" : tactic

macro_rules
  | `(tactic| dart_load_side_condition) =>
    `(tactic| (ipureintro; first | decide | rfl | rotate_left))

/--
`wp_load H` takes the step of reading a variable, or an instance variable of an object, using the
points-to `H` for the cell read. The value's dynamic type comes from `dart_dynamic_type`, and the
pure side conditions (the subtype fact needed for the promotion check, and for an instance
variable, its lookup) from `dart_load_side_condition`; any it can't prove are left as goals after
the main one. Afterwards, `H` is back in the context.
-/
syntax "wp_load " ident : tactic

macro_rules
  | `(tactic| wp_load $h) => `(tactic|
    (first
      | (apply DartSemantics.tac_wp_load
         iframe $h:ident
         isplitr
         · dart_dynamic_type
         isplitr
         dart_load_side_condition)
      | (apply DartSemantics.tac_wp_load_field
         iframe $h:ident
         isplitr
         · iassumption
         isplitr
         dart_load_side_condition
         isplitr
         · dart_dynamic_type
         isplitr
         dart_load_side_condition)
     inext
     iintro $h:ident
     dart_wp_tidy))
