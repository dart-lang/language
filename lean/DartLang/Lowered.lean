module
public import DartLang.Elements
public import DartLang.Types

namespace DartLang

open DartTypeRepr

variable {τ : Type} [Γ : DartTypeRepr τ]

local notation "Variable" => Variable (τ := τ)
local notation "Property" => Property (τ := τ)

/--
Lowered, fully type-checked AST form.

Note that we make no distinction between statements and expressions. This is for future
compatibility with the Iris framework.
-/
public inductive LoweredExpr where
  /--
  A reference to local variable or formal parameter `v`, whose static type (after any promotion)
  is `T`.
  -/
  | var (v : Variable) (T : τ)
  /-- An application of the null check operator, `m!`. -/
  | nullCheck (m : LoweredExpr)
  /-- A cast expression, `m as T`. -/
  | as (m : LoweredExpr) (T : τ)
  /-- An is-expression (a type test), `m is T`. -/
  | is (m : LoweredExpr) (T : τ)
  /-- The null literal, `null`. -/
  | null
  /--
  A local variable declaration of `v`, with type `T`. Its scope is the rest of the enclosing
  `block`.

  `startsNull` says whether the variable starts out holding the null object. Otherwise, it starts
  out unassigned, and it is an error to read it before it is assigned. Flow analysis sets
  `startsNull` to whether `T` is nullable, as Dart requires.
  -/
  | declare (v : Variable) (T : τ) (startsNull : Bool)
  /--
  A conditional: evaluates `m₂` if `m₁` evaluates to `true`, and `m₃` otherwise. Its static type
  is `T`.
  -/
  | cond (m₁ m₂ m₃ : LoweredExpr) (T : τ)
  /--
  A block statement, `{ m₁ … mₙ }`, which executes its elements in order. Since `LoweredExpr`
  doesn't distinguish statements from expressions, its value is the null object.
  -/
  | block (exprs : List LoweredExpr)
  /--
  A property extraction, `m.p`: a read of property `p` of the value of `m`, whose static type
  (after any promotion) is `T`.
  -/
  | propertyGet (m : LoweredExpr) (p : Property) (T : τ)
  deriving Repr, BEq

local notation "LoweredExpr" => LoweredExpr (τ := τ)

/-- The static type of an expression. -/
@[expose]
public def LoweredExpr.typeOf :
    LoweredExpr → τ
  | var _ T => T
  | nullCheck m => NonNull m.typeOf
  | as _ T => T
  | is _ _ => Γ.bool
  | null => Γ.Null
  | declare _ _ _ => Γ.Null
  | cond _ _ _ T => T
  | block _ => Γ.Null
  | propertyGet _ _ T => T

end DartLang
