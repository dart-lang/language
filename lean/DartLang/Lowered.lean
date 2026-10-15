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
  /-
  The remaining constructors are *run-time-only* forms: flow analysis never produces them. They
  appear only as a program runs.
  -/
  /-- An expression that has completed normally, evaluating to `v`. -/
  | val (v : Value)
  /-- An expression that has thrown exception object `v`, propagating outward. -/
  | throwing (v : Value)
  /--
  A reference to local variable or formal parameter `v`, whose static type (after any promotion)
  is `T`, resolved to the heap cell at `ℓ`. Declaring a variable resolves each `var v T` in its
  scope to `varAt v T ℓ`.
  -/
  | varAt (v : Variable) (T : τ) (ℓ : Loc)
  /-- Evaluate `m₁`, discard its value, then evaluate `m₂`. A block runs as a sequence. -/
  | seq (m₁ m₂ : LoweredExpr)

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
  /-- `seq(□, m₂)` -/
  | seq (m₂ : LoweredExpr)

end

deriving instance Repr for Value, LoweredExpr, EctxItem
deriving instance BEq for Value, LoweredExpr, EctxItem

local notation "Value" => Value (τ := τ)
local notation "LoweredExpr" => LoweredExpr (τ := τ)

/--
A static type for a value, for `LoweredExpr.typeOf`: the most precise type that doesn't depend
on the heap. (An object's class is in the heap, so an object reference just gets `Object`.)
-/
@[expose]
public def Value.typeOf : Value → τ
  | .null => Γ.Null
  | .bool _ => Γ.bool
  | .obj _ => Γ.Object
  | .error _ => Γ.Object
  | .cont _ => Γ.ObjectQ

/--
The static type of an expression.

For the run-time-only forms, which flow analysis never sees, the types are chosen only to make
this function total, and no proof relies on them. In particular, `throwing` would best be typed
`Never`, which `DartTypeRepr` doesn't have; it gets the top type `Object?` instead.
-/
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
  | val v => v.typeOf
  | throwing _ => Γ.ObjectQ
  | varAt _ T _ => T
  | seq _ m₂ => m₂.typeOf

local notation "EctxItem" => EctxItem (τ := τ)

/--
How an expression's evaluation (or a statement's execution) *completes*, in the sense of the
language specification's "Statement Completion" section: normally, evaluating to an object, or by
throwing an exception object. Stack traces aren't modeled.

The specification has three more kinds of completion: breaking and continuing (each with or
without a label), and returning. Variants for them will be added here when the semantics supports
`break`, `continue` and `return` statements.
-/
public inductive Outcome where
  /-- Completes normally, evaluating to `v`. -/
  | normal (v : Value)
  /-- Throws exception object `v`. -/
  | throwing (v : Value)
  deriving Repr, BEq

local notation "Outcome" => Outcome (τ := τ)

/-- The expression that has completed with outcome `o`. -/
@[expose]
public def Outcome.toExpr : Outcome → LoweredExpr
  | .normal v => .val v
  | .throwing v => .throwing v

/-- How `m` completed, if it has. -/
@[expose]
public def LoweredExpr.toOutcome? : LoweredExpr → Option Outcome
  | .val v => some (.normal v)
  | .throwing v => some (.throwing v)
  | _ => none

omit Γ in
public theorem Outcome.toOutcome?_toExpr (o : Outcome) : o.toExpr.toOutcome? = some o := by
  cases o <;> rfl

omit Γ in
public theorem LoweredExpr.toExpr_of_toOutcome? {m : LoweredExpr} {o : Outcome}
    (h : m.toOutcome? = some o) : o.toExpr = m := by
  cases m <;> simp only [toOutcome?, reduceCtorEq, Option.some.injEq] at h <;> subst h <;> rfl

/-- Plug `m` into the hole of context item `Ki`. -/
@[expose]
public def EctxItem.fill : EctxItem → LoweredExpr → LoweredExpr
  | .nullCheck, m => .nullCheck m
  | .as T, m => .as m T
  | .is T, m => .is m T
  | .cond m₂ m₃ T, m => .cond m m₂ m₃ T
  | .propertyGet p T, m => .propertyGet m p T
  | .seq m₂, m => .seq m m₂

omit Γ in
/-- An expression with a hole plugged hasn't completed. -/
public theorem EctxItem.toOutcome?_fill (Ki : EctxItem) (m : LoweredExpr) :
    (Ki.fill m).toOutcome? = none := by
  cases Ki <;> rfl

/--
Plug `m` into the hole of the evaluation context `k`, a list of context items, innermost first.
-/
@[expose]
public def fillCtx (k : List EctxItem) (m : LoweredExpr) : LoweredExpr :=
  k.foldl (fun m Ki => Ki.fill m) m

end DartLang
