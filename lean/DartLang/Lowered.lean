module
public import DartLang.Elements
public import DartLang.Loc
public import DartLang.Types

namespace DartLang

open DartTypeRepr

variable {τ : Type} [Γ : DartTypeRepr τ]

local notation "Variable" => Variable (τ := τ)
local notation "Property" => Property (τ := τ)

/--
The kinds of dynamic error (in the specification's sense) that can occur in the subset of Dart
modeled so far.

This is a placeholder. The language specification says that when a dynamic error occurs, a
corresponding error object is thrown; for a dynamic type error, the thrown object implements
`TypeError`. Once the semantics can allocate objects of core library classes, a dynamic error
will throw such an object, and this type (with `Value.error`) will go away.
-/
public inductive DynamicError where
  /--
  A dynamic type error: a failed type check at run time, such as a null check (`e!`) finding the
  null object, or a failed cast (`e as T`).
  -/
  | typeError
  deriving Repr, BEq, DecidableEq

/-
`Value`, `LoweredExpr` and `EctxItem` are mutually inductive: a value may hold a captured
continuation (a list of evaluation context items), and evaluation context items hold the
expressions still to be evaluated.
-/
mutual

/--
A run-time value: in the specification's terms, an object. The null object, booleans and error
objects are represented directly; other objects live in the heap and are referred to by location.
-/
public inductive Value where
  /-- The null object. -/
  | null
  /-- The object `true` or `false`. -/
  | bool (b : Bool)
  /-- A reference to the object stored at location `ℓ`. -/
  | obj (ℓ : Loc)
  /-- The object thrown when dynamic error `e` occurs. -/
  | error (e : DynamicError)
  /--
  A captured continuation: the evaluation context items around a suspended computation,
  innermost first. Reserved for constructs that capture continuations (such as `await`); nothing
  creates one yet.
  -/
  | cont (k : List EctxItem)

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

/--
An evaluation context item: an expression with a hole in the position that evaluates next. See
`EctxItem.fill`.
-/
public inductive EctxItem where
  /-- `□!` -/
  | nullCheck
  /-- `□ as T` -/
  | as (T : τ)
  /-- `□ is T` -/
  | is (T : τ)
  /-- `cond(□, m₂, m₃)` (of type `T`) -/
  | cond (m₂ m₃ : LoweredExpr) (T : τ)
  /-- `□.p` (of type `T`) -/
  | propertyGet (p : Property) (T : τ)

end

deriving instance Repr for Value, LoweredExpr, EctxItem
deriving instance BEq for Value, LoweredExpr, EctxItem

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
