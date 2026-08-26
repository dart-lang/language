module
public import FlowAnalysis.Types

namespace FlowAnalysis

/--
A minimal type system sufficient for studying flow analysis.

TODO(paulberry): expand on this as needed.
-/
public inductive SimpleType where
  | Object : SimpleType
  | ObjectQ : SimpleType
  | dynamic : SimpleType
  | Null : SimpleType
  | Never : SimpleType
  | int : SimpleType
  | bool : SimpleType
  | List (elementType : SimpleType) : SimpleType
  | Map (key value : SimpleType) : SimpleType
  deriving Repr, BEq, DecidableEq, Repr

namespace SimpleType

public theorem instLawfulBEq_rfl {T : SimpleType} : (T == T) = true := by
  cases T <;> simp [BEq.beq, instBEqSimpleType.beq]
  case List T' => apply instLawfulBEq_rfl
  case Map K V =>
    constructor
    · apply instLawfulBEq_rfl
    · apply instLawfulBEq_rfl

public theorem instLawfulBEq_eq_of_beq {T₁ T₂ : SimpleType} :
    instBEqSimpleType.beq T₁ T₂ = true → T₁ = T₂ := by
  cases T₁ <;> cases T₂ <;> simp [instBEqSimpleType.beq]
  case List.List T₁' T₂' => apply instLawfulBEq_eq_of_beq
  case Map.Map K₁ V₁ K₂ V₂ =>
    intro hK hV
    simp [instLawfulBEq_eq_of_beq hK, instLawfulBEq_eq_of_beq hV]

@[expose]
public def isSubtype : SimpleType -> SimpleType -> Bool
  | Never,     _         => true
  | _,         ObjectQ   => true
  | _,         dynamic   => true
  | Object,    Object    => true
  | Null,      Null      => true
  | int,       int       => true
  | int,       Object    => true
  | bool,      bool      => true
  | bool,      Object    => true
  | List _,    Object    => true
  | List T,    List U    => isSubtype T U
  | Map _ _,   Object    => true
  | Map K₁ V₁, Map K₂ V₂ => isSubtype K₁ K₂ && isSubtype V₁ V₂
  | _,         _         => false

public theorem isSubtype_refl (T : SimpleType) : T.isSubtype T = true := by
  cases T <;> try simp [isSubtype]
  case List T' => apply isSubtype_refl
  case Map K V => constructor <;> apply isSubtype_refl

public theorem isSubtype_trans :
    ∀ (T U V : SimpleType), T.isSubtype U = true → U.isSubtype V = true → T.isSubtype V = true := by
  intro T U V
  cases T <;> cases U <;> cases V <;> try simp [isSubtype]
  case List.List.List T' U' V' => apply isSubtype_trans
  case Map.Map.Map K₁ V₁ K₂ V₂ K₃ V₃ =>
    intro hK₁₂ hV₁₂ hK₂₃ hV₂₃
    constructor
    · apply isSubtype_trans K₁ K₂ K₃ (by assumption) (by assumption)
    · apply isSubtype_trans V₁ V₂ V₃ (by assumption) (by assumption)

public def NonNull : SimpleType -> SimpleType
  | ObjectQ => Object
  | Object  => Object
  | dynamic => dynamic
  | Null    => Never
  | Never   => Never
  | int     => int
  | bool    => bool
  | List T' => List T'
  | Map K V => Map K V

public instance instSimpleTypeRepr : DartTypeRepr SimpleType where
  rfl := instLawfulBEq_rfl
  eq_of_beq := instLawfulBEq_eq_of_beq
  le T U := isSubtype T U = true
  le_refl := isSubtype_refl
  le_trans := isSubtype_trans
  toString T := (repr T).pretty
  decideEq T U := inferInstance
  decideLE T U :=
    if h : T.isSubtype U then
      isTrue $ by simp_all [LE.le]
    else
      isFalse $ by simp_all [LE.le]
  decideLT T U :=
    if hrev : U.isSubtype T then
      isFalse $ by simp_all [LT.lt]
    else if h : T.isSubtype U then
      isTrue $ by simp_all [LT.lt]
    else
      isFalse $ by simp_all [LT.lt]
  NonNull := NonNull
  bool := bool
  dynamic := dynamic
  int := int
  Map := Map
  Null := Null
  Object := Object
  ObjectQ := ObjectQ

namespace instSimpleTypeRepr

@[simp]
public theorem le.iff {T U : SimpleType} : T ≤ U ↔ T.isSubtype U := by rfl

@[simp]
public theorem lt.iff {T U : SimpleType} :
    T < U ↔ T.isSubtype U ∧ ¬U.isSubtype T := by rfl

@[simp]
public theorem dynamic.eq :
    (inferInstance : DartTypeRepr SimpleType).dynamic = dynamic := by rfl

@[simp]
public theorem int.eq :
    (inferInstance : DartTypeRepr SimpleType).int = int := by rfl

@[simp]
public theorem Map.eq :
    (inferInstance : DartTypeRepr SimpleType).Map = Map := by rfl

@[simp]
public theorem Object.eq :
    (inferInstance : DartTypeRepr SimpleType).Object = Object := by rfl

@[simp]
public theorem ObjectQ.eq :
    (inferInstance : DartTypeRepr SimpleType).ObjectQ = ObjectQ := by rfl

end instSimpleTypeRepr
end SimpleType
end FlowAnalysis
