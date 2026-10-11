module
import DartSemantics
import DartLang.SimpleTypes

/-!
# Specs proved with the program logic

Weakest preconditions for small programs, on `SimpleType`, for every choice of `SemanticParams`.
They exercise the primitive laws and the proof-mode tactics (see `ProofMode.lean`).

The spec of `{ x._f!; x._f }` is proved twice, to compare: once applying the laws for its four
reads by hand (45 lines of tactics, not counting comments), and once with `wp_load` (11 lines).
The program takes 10 steps; `wp_pures` takes the pure ones in both proofs.
-/

namespace DartSemantics.Tests.Specs

open DartLang SimpleType Iris Iris.BI Iris.ProgramLogic

local notation "LoweredExpr" => LoweredExpr (τ := SimpleType)
local notation "Variable" => Variable (τ := SimpleType)
local notation "Value" => Value (τ := SimpleType)
local notation "Outcome" => Outcome (τ := SimpleType)
local notation "Cell" => Cell (τ := SimpleType)

variable {hlc : HasLC} {GF : BundledGFunctors} [DartGS SimpleType hlc GF]
variable [SemanticParams SimpleType]

include hlc

/-- `{ null!; null }` throws, without touching the state. -/
example : ⊢@{IProp GF} WP (LoweredExpr.block (τ := SimpleType) [.nullCheck .null, .null]) {{ o,
    ⌜o = DartLang.Outcome.throwing (.error .typeError)⌝ }} := by
  iintro
  wp_pures
  ipureintro
  trivial

def x : Variable := ⟨"x", ObjectQ⟩

/-- `{ Object? x; x! }` throws: a declared nullable variable starts out null. -/
example : ⊢@{IProp GF} WP (LoweredExpr.block (τ := SimpleType)
    [.declare x ObjectQ true, .nullCheck (.var x ObjectQ)]) {{ o,
    ⌜o = DartLang.Outcome.throwing (.error .typeError)⌝ }} := by
  iintro
  wp_alloc ℓ Hl
  wp_pures
  wp_load Hl
  wp_pures
  ipureintro
  trivial

/-- A promotable property. -/
def f : Property (τ := SimpleType) := ⟨"_f", ObjectQ, true⟩

/--
`{ x._f!; x._f }`, where parameter `x` (at `ℓ`) refers to an object of type `int` (at `ℓo`) whose
instance variable `_f` (at `ℓf`) holds `true`, completes normally, and leaves the cells as they
were. The second read is promoted to `Object`, which the promotion check verifies.
-/
example (ℓ ℓo ℓf : Loc) :
    {{ ℓ ↦ (.val (.obj ℓo) : Cell) ∗ ℓo ↦{.discard} (.object int [("_f", ℓf)] : Cell) ∗
        ℓf ↦ (.val (.bool true) : Cell) }}
      (LoweredExpr.block (τ := SimpleType)
        [.nullCheck (.propertyGet (.varAt x ObjectQ ℓ) f ObjectQ),
          .propertyGet (.varAt x ObjectQ ℓ) f Object])
    {{ RET .normal .null; ℓ ↦ (.val (.obj ℓo) : Cell) ∗ ℓf ↦ (.val (.bool true) : Cell) }} := by
  iintro %Φ ⟨Hl, #Ho, Hf⟩ HΦ
  wp_pures
  -- Read `x`.
  iapply DartSemantics.wp_varAt (v := .obj ℓo) (S := int) (by decide)
  isplitr
  · iapply HasDynamicType.obj
    iexact Ho
  isplitl [Hl]
  · iexact Hl
  inext
  iintro Hl
  wp_pures
  -- Read `x._f`, of static type `Object?`.
  iapply DartSemantics.wp_propertyGetField (fs := [("_f", ℓf)]) (w := .bool true)
    (S := SimpleType.bool) rfl (by decide)
  isplitr
  · iexact Ho
  isplitr
  · iapply HasDynamicType.bool
  isplitl [Hf]
  · iexact Hf
  inext
  iintro Hf
  -- `true!`, then the rest of the block.
  wp_pures
  -- Read `x` again.
  iapply DartSemantics.wp_varAt (v := .obj ℓo) (S := int) (by decide)
  isplitr
  · iapply HasDynamicType.obj
    iexact Ho
  isplitl [Hl]
  · iexact Hl
  inext
  iintro Hl
  wp_pures
  -- Read `x._f`, promoted to `Object`.
  iapply DartSemantics.wp_propertyGetField (fs := [("_f", ℓf)]) (w := .bool true)
    (S := SimpleType.bool) rfl (by decide)
  isplitr
  · iexact Ho
  isplitr
  · iapply HasDynamicType.bool
  isplitl [Hf]
  · iexact Hf
  inext
  iintro Hf
  wp_pures
  iapply HΦ
  iframe Hl
  iexact Hf

/-- The same spec, proved with the `wp_load` tactic for the reads. -/
example (ℓ ℓo ℓf : Loc) :
    {{ ℓ ↦ (.val (.obj ℓo) : Cell) ∗ ℓo ↦{.discard} (.object int [("_f", ℓf)] : Cell) ∗
        ℓf ↦ (.val (.bool true) : Cell) }}
      (LoweredExpr.block (τ := SimpleType)
        [.nullCheck (.propertyGet (.varAt x ObjectQ ℓ) f ObjectQ),
          .propertyGet (.varAt x ObjectQ ℓ) f Object])
    {{ RET .normal .null; ℓ ↦ (.val (.obj ℓo) : Cell) ∗ ℓf ↦ (.val (.bool true) : Cell) }} := by
  iintro %Φ ⟨Hl, #Ho, Hf⟩ HΦ
  wp_pures
  wp_load Hl
  wp_load Hf
  wp_pures
  wp_load Hl
  wp_load Hf
  wp_pures
  iapply HΦ
  iframe Hl
  iexact Hf

/--
`x is int ? x : null`, where parameter `x` refers to an object of type `int`, evaluates to `x`,
read in the first branch with `x` promoted to `int`.
-/
example (ℓ ℓo : Loc) (fs : List (String × Loc)) :
    {{ ℓ ↦ (.val (.obj ℓo) : Cell) ∗ ℓo ↦{.discard} (.object int fs : Cell) }}
      (LoweredExpr.cond (τ := SimpleType) (.is (.varAt x ObjectQ ℓ) int) (.varAt x int ℓ) .null
        ObjectQ)
    {{ RET .normal (.obj ℓo); ℓ ↦ (.val (.obj ℓo) : Cell) }} := by
  iintro %Φ ⟨Hl, #Ho⟩ HΦ
  wp_pures
  wp_load Hl
  -- The is-expression's run-time check.
  iapply DartSemantics.wp_is (S := int) (b := true) rfl
  isplitr
  · iapply HasDynamicType.obj
    iexact Ho
  inext
  wp_pures
  wp_load Hl
  iapply HΦ
  iexact Hl

end DartSemantics.Tests.Specs

namespace DartSemantics.Tests.Specs.Generic

open DartLang Iris Iris.BI Iris.ProgramLogic

variable {τ : Type} [DartRuntimeTypeRepr τ]
variable {hlc : HasLC} {GF : BundledGFunctors} [DartGS τ hlc GF] [SemanticParams τ]

include hlc

/--
Reading a variable of static type `T` whose value has dynamic type `S`, for an arbitrary type
representation, where `decide` can't prove `S ≤ T`: `wp_load` leaves that goal for afterwards.
-/
example (x : DartLang.Variable (τ := τ)) (S T : τ) (hST : S ≤ T) (ℓ : Loc)
    (v : DartLang.Value (τ := τ)) :
    {{ ℓ ↦ (.val v : DartSemantics.Cell (τ := τ)) ∗ HasDynamicType v S }}
      (LoweredExpr.varAt x T ℓ)
    {{ RET .normal v; ℓ ↦ (.val v : DartSemantics.Cell (τ := τ)) }} := by
  iintro %Φ ⟨Hl, #Hty⟩ HΦ
  wp_load Hl
  · iapply HΦ
    iexact Hl
  · exact hST

end DartSemantics.Tests.Specs.Generic
