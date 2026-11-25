module
public import DartLang.RuntimeTypes
public import DartSemantics.Resolve
public import DartSemantics.State

/-!
# The head-step relation

The small-step semantics of `LoweredExpr`. A *step* takes an expression `e`, in state `σ`, to an
expression `e'`, leaving state `σ'`. Each step does its work on one subexpression of `e`, the
*redex*: the part of `e` that evaluates next. The rest of `e`, the *evaluation context*, is left
alone. For example, in `(x as int)!`, the redex is `x`, and the evaluation context is `(□ as int)!`.
A step of an expression that is itself the redex (with an empty evaluation context) is a
*head step*.

This file defines head steps, as the relation `HeadStep e σ e' σ'`. That's all that's needed to
define the semantics: every step is a head step of the redex, inside its evaluation context.
iris-lean derives the steps from the head steps and evaluation context items (`EctxItem`); see
`Language.lean`. The interpreter (`Interp.primStep`) is proved to agree with the semantics.

## Run-time subtype checks

Is-expressions and cast expressions check at run time whether a value satisfies a type (whether its
dynamic type is a subtype of the type). The check is specified by the relation `RtSub` (see
`RuntimeTypes.lean`), which may give no answer, meaning that the check doesn't terminate. To model
a check that doesn't terminate as a computation that doesn't terminate, an expression whose check
gives no answer steps to itself, forever.

## Promotion checks

When flow analysis promotes a variable, it records the promoted type in each `var v T` that reads
the variable, and likewise for a promoted property in `propertyGet m p T`. The semantics can
check, as it reads any variable or property, that the value really has its recorded type `T`.
These *promotion checks* aren't part of Dart: they are how the semantics expresses that flow
analysis is sound. (The semantics doesn't know which properties flow analysis may promote, so it
checks every property read, as it checks every variable read.) When
`SemanticParams.promotionChecks` is `PromotionChecks.verify`, a read whose promotion check fails
gets stuck, so a proof that well-typed programs don't get stuck includes a proof that flow
analysis only promotes soundly. When `SemanticParams.promotionChecks` is `PromotionChecks.trust`,
there are no promotion checks, as in Dart implementations.

The program logic, and proofs of soundness built on it, are meant to hold for every setting of
`SemanticParams.promotionChecks`: whatever the setting, such a proof must show that each promoted
read produces a value of the promoted type. The setting only changes what the resulting safety
theorem (that well-typed programs don't get stuck) says on its own: with `PromotionChecks.verify`,
it expresses that flow analysis only promotes soundly, without reference to the program logic.

A promotion check that gives no answer gets stuck, rather than stepping to itself, so that an
unsound promotion can't be hidden by a check that doesn't terminate. A sound promotion always
passes its promotion check: the value satisfies the promoted type, and the
run-time subtype check always terminates when the answer is yes
(`DartRuntimeTypeRepr.rtSub_of_le`; see `PassesPromotionCheck.of_le`).
-/

namespace DartSemantics

open DartLang

/-- Whether the semantics performs promotion checks (see the module documentation). -/
public inductive PromotionChecks where
  /-- Perform promotion checks: a read whose promotion check fails gets stuck. -/
  | verify
  /--
  Don't perform promotion checks, but trust flow analysis's promotions, as the implementations do.
  -/
  | trust
  deriving Repr, BEq, DecidableEq

variable {τ : Type} [Γ : DartRuntimeTypeRepr τ]

local notation "Property" => Property (τ := τ)
local notation "Value" => Value (τ := τ)
local notation "LoweredExpr" => LoweredExpr (τ := τ)
local notation "EctxItem" => EctxItem (τ := τ)
local notation "Cell" => Cell (τ := τ)
local notation "State" => State (τ := τ)

variable (τ) in
/--
The parameters of the semantics: choices that a theorem may make, or quantify over.

This is a class so that the semantics can be an instance of iris-lean's language classes, which
must be found by instance resolution.
-/
public class SemanticParams where
  /-- Whether the semantics performs promotion checks. -/
  promotionChecks : PromotionChecks
  /--
  The implementation of getters that are user code (rather than the implicit getter of an instance
  variable): `getterImpl p v σ` is the result of reading property `p` of value `v` in state `σ`,
  or `none` if the read gets stuck.

  In Dart, a getter runs arbitrary code. Until the semantics has function calls, a getter is
  modeled as a pure function of the state: it can't change the state, throw, or fail to
  terminate. Theorems quantify over all implementations that are well-formed, in the sense that
  the result (if any) has the property's static type. This parameter is a placeholder. Once the
  semantics has function calls, reading a property whose getter is user code will invoke the
  getter like any other call, and `getterImpl` will be removed. Theorems will then quantify over
  programs instead, assuming that each getter is well typed.
  -/
  getterImpl : Property → Value → State → Option Value

variable [P : SemanticParams τ]

/--
The location of the cell holding instance variable `name` of the object that value `v` refers
to, if `v` refers to an object that has such an instance variable. Reading property `name` of such
an object runs the instance variable's implicit getter, which reads the cell. Reading any other
property runs a getter that is user code.

This lookup has two known gaps, which will be closed when the semantics has class declarations:
- In Dart, a subclass can override an inherited instance variable with a getter. Its objects
  still have the inherited instance variable, but reading the property runs the subclass's
  getter, not the implicit getter. The class declarations, not the object's instance variables,
  should decide which getter runs.
- Instance variables are matched by name, which disregards privacy. An object can have two
  distinct instance variables named `_foo`, declared in different libraries by different classes
  in its superclass chain. Which one a property read reads depends on the library that the code
  doing the reading is in. Reading a property whose getter is user code (and, later, calling a
  setter or method) depends on the library in the same way.
-/
@[expose]
public def State.instanceVariable? (σ : State) (v : Value) (name : String) : Option Loc :=
  match v with
  | .obj ℓ =>
    match σ.lookup ℓ with
    | some (.object _ fs) => fs.lookup name
    | _ => none
  | _ => none

/--
`PassesPromotionCheck σ v T` says that in state `σ`, value `v` passes the promotion check against
type `T` (see the module documentation). When `SemanticParams.promotionChecks` is
`PromotionChecks.trust`, every value passes.
-/
public inductive PassesPromotionCheck (σ : State) (v : Value) (T : τ) : Prop where
  /-- Without promotion checks, every value passes. -/
  | trust (h : P.promotionChecks = .trust)
  /-- With promotion checks, a value passes if it satisfies `T`. -/
  | verify {S : τ} (h : P.promotionChecks = .verify) (hS : σ.dynamicType v = some S)
      (hT : RtSub S T true)

/--
A value `v` that satisfies `T`, in that its dynamic type is `S` (`hS`), a subtype of `T` (`hT`),
passes the promotion check against `T`.
-/
public theorem PassesPromotionCheck.of_le {σ : State} {v : Value} {S T : τ}
    (hS : σ.dynamicType v = some S) (hT : S ≤ T) : PassesPromotionCheck σ v T := by
  cases h : P.promotionChecks
  · exact .verify h hS (DartRuntimeTypeRepr.rtSub_of_le hT)
  · exact .trust h

/--
`HeadStep e σ e' σ'` says that expression `e`, in state `σ`, takes a head step to `e'`, leaving
state `σ'`.

Every step is deterministic (`HeadStep.deterministic`). An expression that has completed (`val`
or `throwing`) takes no step. Any other expression with no step is *stuck*. An expression gets
stuck only when something that Dart's static checks (including flow analysis) are meant to
guarantee has failed, such as reading a variable that hasn't been assigned, or a value failing its
promotion check. Giving such an expression no step makes the failure loud: the interpreter reports
it, and the safety theorem (that well-typed programs don't get stuck) rules it out, so proving that
theorem proves the guarantee. Until the semantics covers more of Dart, an expression can also get
stuck because it uses something that isn't modeled yet.
-/
public inductive HeadStep : LoweredExpr → State → LoweredExpr → State → Prop where
  /-- The null literal evaluates to the null object. -/
  | null {σ : State} : HeadStep .null σ (.val .null) σ
  /--
  A local variable declaration outside a block is converted to a block containing just that
  declaration.
  -/
  | declare {v : Variable (τ := τ)} {T : τ} {startsNull : Bool} {σ : State} :
      HeadStep (.declare v T startsNull) σ (.block [.declare v T startsNull]) σ
  /-- An empty block completes normally. Its value is the null object. -/
  | blockNil {σ : State} : HeadStep (.block []) σ (.val .null) σ
  /--
  A block that starts with a declaration of local variable `v` allocates a cell for `v`, and
  resolves the references to `v` in the rest of the block to it. The cell starts out holding the
  null object if the declaration says so (which it does if `v`'s type is nullable), and
  uninitialized otherwise.
  -/
  | blockDeclare {v : Variable (τ := τ)} {T : τ} {startsNull : Bool} {ms : List LoweredExpr}
      {σ : State} :
      HeadStep (.block (.declare v T startsNull :: ms)) σ
        (.block (LoweredExpr.resolveBlock v σ.fresh ms))
        (σ.alloc (if startsNull then .val .null else .uninit))
  /-- A block that starts with anything else runs it, and then the rest of the block. -/
  | blockCons {m : LoweredExpr} {ms : List LoweredExpr} {σ : State}
      (h : ∀ v T startsNull, m ≠ .declare v T startsNull) :
      HeadStep (.block (m :: ms)) σ (.seq m (.block ms)) σ
  /-- Once the first part of a sequence completes normally, its value is discarded. -/
  | seq {v : Value} {m : LoweredExpr} {σ : State} : HeadStep (.seq (.val v) m) σ m σ
  /--
  A reference to a local variable evaluates to the value in its cell, if the value passes the
  promotion check against the variable's (possibly promoted) static type. Reading a variable that
  hasn't been assigned gets stuck.
  -/
  | varAt {x : Variable (τ := τ)} {T : τ} {ℓ : Loc} {v : Value} {σ : State}
      (hℓ : σ.lookup ℓ = some (.val v)) (hv : PassesPromotionCheck σ v T) :
      HeadStep (.varAt x T ℓ) σ (.val v) σ
  /-- A null check on the null object is a dynamic type error. -/
  | nullCheckNull {σ : State} :
      HeadStep (.nullCheck (.val .null)) σ (.throwing (.error .typeError)) σ
  /-- A null check on any other object evaluates to that object. -/
  | nullCheck {v : Value} {σ : State} (h : v ≠ .null) : HeadStep (.nullCheck (.val v)) σ (.val v) σ
  /-- A cast evaluates to its operand if the operand satisfies `T`. -/
  | asTrue {v : Value} {S T : τ} {σ : State} (hS : σ.dynamicType v = some S)
      (h : RtSub S T true) : HeadStep (.as (.val v) T) σ (.val v) σ
  /-- A cast whose operand doesn't satisfy `T` is a dynamic type error. -/
  | asFalse {v : Value} {S T : τ} {σ : State} (hS : σ.dynamicType v = some S)
      (h : RtSub S T false) : HeadStep (.as (.val v) T) σ (.throwing (.error .typeError)) σ
  /-- If a cast's subtype check doesn't terminate, neither does the cast. -/
  | asDiverge {v : Value} {S T : τ} {σ : State} (hS : σ.dynamicType v = some S)
      (h : ∀ b, ¬ RtSub S T b) : HeadStep (.as (.val v) T) σ (.as (.val v) T) σ
  /-- An is-expression evaluates to whether its operand satisfies `T`. -/
  | is {v : Value} {S T : τ} {σ : State} {b : Bool} (hS : σ.dynamicType v = some S)
      (h : RtSub S T b) : HeadStep (.is (.val v) T) σ (.val (.bool b)) σ
  /-- If an is-expression's subtype check doesn't terminate, neither does the is-expression. -/
  | isDiverge {v : Value} {S T : τ} {σ : State} (hS : σ.dynamicType v = some S)
      (h : ∀ b, ¬ RtSub S T b) : HeadStep (.is (.val v) T) σ (.is (.val v) T) σ
  /-- A conditional whose condition is `true` evaluates its first branch. -/
  | condTrue {m₂ m₃ : LoweredExpr} {T : τ} {σ : State} :
      HeadStep (.cond (.val (.bool true)) m₂ m₃ T) σ m₂ σ
  /-- A conditional whose condition is `false` evaluates its second branch. -/
  | condFalse {m₂ m₃ : LoweredExpr} {T : τ} {σ : State} :
      HeadStep (.cond (.val (.bool false)) m₂ m₃ T) σ m₃ σ
  /--
  Reading a property whose getter is the implicit getter of an instance variable (see
  `State.instanceVariable?`) reads the instance variable's cell, if the value passes the promotion
  check against the property's (possibly promoted) static type.
  -/
  | propertyGetField {v w : Value} {p : Property} {T : τ} {ℓf : Loc} {σ : State}
      (hf : σ.instanceVariable? v p.name = some ℓf) (hw : σ.lookup ℓf = some (.val w))
      (hc : PassesPromotionCheck σ w T) :
      HeadStep (.propertyGet (.val v) p T) σ (.val w) σ
  /--
  Reading any other property runs its getter, which is user code (see
  `SemanticParams.getterImpl`), if the result passes the promotion check against the property's
  (possibly promoted) static type.
  -/
  | propertyGetGetter {v w : Value} {p : Property} {T : τ} {σ : State}
      (hf : σ.instanceVariable? v p.name = none) (hg : P.getterImpl p v σ = some w)
      (hc : PassesPromotionCheck σ w T) :
      HeadStep (.propertyGet (.val v) p T) σ (.val w) σ
  /--
  An exception propagates outward one evaluation context item per step: whatever was to be done
  with the value of the hole is abandoned.

  Every evaluation context item so far propagates exceptions. Once the semantics has `try`
  statements, their context items will handle exceptions instead (running the matching `catch`
  clause, or the `finally` clause), so this rule will gain a hypothesis that `Ki` isn't one of
  them.
  -/
  | bubble {Ki : EctxItem} {v : Value} {σ : State} :
      HeadStep (Ki.fill (.throwing v)) σ (.throwing v) σ

/--
The semantics is deterministic: an expression takes at most one head step. If `e` takes head steps
to `e₁` (`h₁`) and `e₂` (`h₂`), they're the same (`e₁ = e₂ ∧ σ₁ = σ₂`).
-/
public theorem HeadStep.deterministic {e e₁ e₂ : LoweredExpr} {σ σ₁ σ₂ : State}
    (h₁ : HeadStep e σ e₁ σ₁) (h₂ : HeadStep e σ e₂ σ₂) : e₁ = e₂ ∧ σ₁ = σ₂ := by
  generalize hE : e = E at h₂
  cases h₁ <;> cases h₂
  all_goals
    (try cases ‹EctxItem›) <;> (try cases ‹EctxItem›) <;>
      (try simp only [EctxItem.fill, reduceCtorEq] at hE)
  all_goals (try simp_all)
  all_goals first
    | grind [rtSub_unique]
    | (cases ‹Bool› <;> grind)

end DartSemantics
