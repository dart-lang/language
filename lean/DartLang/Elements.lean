module
public import DartLang.Types

namespace DartLang

variable {τ : Type} [DartTypeRepr τ]

/-- A local variable or formal parameter. -/
public structure Variable where
  /-- The variable's name. -/
  name : String
  /-- The variable's declared type. -/
  type : τ
  deriving Repr, BEq, DecidableEq

local notation "Variable" => Variable (τ := τ)

/--
Variables hash by name only. This is consistent with `BEq`, since equal variables have equal names.
-/
public instance Variable.instHashable : Hashable Variable where
  hash v := hash v.name

/-- `BEq` on variables is lawful, so variables can be used as hash map keys. -/
public instance Variable.instLawfulBEq : LawfulBEq Variable where
  rfl := by
    intro v
    simp [BEq.beq, instBEqVariable.beq]

  eq_of_beq := by
    rintro ⟨n, T⟩ ⟨n', T'⟩
    simp [BEq.beq, instBEqVariable.beq]

/-- Hashing variables is lawful, so variables can be used as hash map keys. -/
public instance Variable.instLawfulHashable : LawfulHashable Variable where
  hash_eq := by simp_all

/--
A property (a getter, or an instance variable, read through its implicit getter) that can be read
from an object. Mirrors the `propertyMember` passed to the flow analysis implementation's
`propertyGet`, together with the information flow analysis needs about it.
-/
public structure Property where
  /-- The property's name. -/
  name : String
  /-- The static type of the property. -/
  type : τ
  /--
  Whether the property is promotable. Mirrors Dart's
  `operations.isPropertyPromotable(propertyMember) && fieldPromotionEnabled`.
  -/
  isPromotable : Bool
  deriving Repr, BEq, DecidableEq

end DartLang
