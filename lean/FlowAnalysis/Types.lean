module
public import Mathlib.Logic.Unique
public import Mathlib.Order.Defs.PartialOrder

namespace FlowAnalysis

/--
The Lean model of flow analysis uses a typeclass to abstract the representation of Dart types. This
allows us to ignore tricky details that don't affect flow analysis (like f-boundedness and the
associated difficulties with proving termination of the subtype algorithm) without compromising the
generality of the model.

See the file `SimpleTypes.lean` for a concrete instantiation of this typeclass.
-/
public class DartTypeRepr (τ : Type) extends BEq τ, LawfulBEq τ, Preorder τ, Repr τ,
    ToString τ where
  decideEq : DecidableEq τ
  /--
  We use `≤` to represent non-strict subtyping, since this lets us use the `Preorder` typeclass,
  which gives us a lot of nice properties for free (like reflexivity, transitivity, etc). The spec
  spells this `<:`.
  -/
  decideLE : DecidableLE τ

  /--
  We use `<` to represent strict subtyping, since this is defined automatically by the `Preorder`
  typeclass as `T₁ < T₂ ↔ T₁ ≤ T₂ ∧ ¬T₂ ≤ T₁`. The spec spells this `<<:`.
  -/
  decideLT : DecidableLT τ

  NonNull : τ → τ
  bool : τ
  dynamic : τ
  int : τ
  Map (K : τ) (V : τ) : τ
  Null : τ
  Object : τ
  ObjectQ : τ

variable {τ : Type} [DartTypeRepr τ]

namespace DartTypeRepr

/-- Strict subtyping is irreflexive -/
theorem strict_subtype_irrefl : Std.Irrefl (LT.lt : τ → τ → Prop) :=
  inferInstance

/-- Strict subtyping is antisymmetric -/
theorem strict_subtype_antisymm : Std.Antisymm (LT.lt : τ → τ → Prop) :=
  inferInstance

/-- Strict subtyping is transitive -/
theorem strict_subtype_trans : IsTrans τ LT.lt := inferInstance

public instance instDecidableEq : DecidableEq τ := decideEq

public instance instDecidableLE : DecidableLE τ := decideLE

public instance instDecidableLT : DecidableLT τ := decideLT

end DartTypeRepr
end FlowAnalysis
