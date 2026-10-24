module
public import DartLang.Lowered

/-!
# Resolving variables to heap cells

Local variables live in heap cells (see `Loc`). When a local variable is declared, the semantics
allocates a cell for it and *resolves* each reference `var v T` in the variable's scope to the
run-time-only form `varAt v T ℓ`, which refers to the cell at `ℓ` directly.

Here a variable's scope is the rest of the enclosing block, after its declaration. This departs from
the language specification, where every declaration in a block is in scope throughout the block,
and it's a compile-time error to refer to a local variable before its declaration. So a program
such as `int x; { x; int x; }` is an error in Dart, but here the first inner read of `x` reads the
outer `x`. This only matters for programs that Dart rejects, which the elaborator should reject
before they get here.
-/

namespace DartLang

variable {τ : Type} [DartTypeRepr τ]

local notation "Variable" => Variable (τ := τ)
local notation "LoweredExpr" => LoweredExpr (τ := τ)

mutual

/--
Resolve each reference to variable `x` in `m` to the cell at `ℓ`: replace each `var x T` that `x`
isn't shadowed for with `varAt x T ℓ`.

Values (in `val` and `throwing`) are left alone, since they contain no variable references.
-/
@[expose]
public def LoweredExpr.resolve (x : Variable) (ℓ : Loc) : LoweredExpr → LoweredExpr
  | .var v T => if v = x then .varAt v T ℓ else .var v T
  | .nullCheck m => .nullCheck (m.resolve x ℓ)
  | .as m T => .as (m.resolve x ℓ) T
  | .is m T => .is (m.resolve x ℓ) T
  | .null => .null
  | .declare v T startsNull => .declare v T startsNull
  | .cond m₁ m₂ m₃ T => .cond (m₁.resolve x ℓ) (m₂.resolve x ℓ) (m₃.resolve x ℓ) T
  | .block ms => .block (LoweredExpr.resolveBlock x ℓ ms)
  | .propertyGet m p T => .propertyGet (m.resolve x ℓ) p T
  | .val v => .val v
  | .throwing v => .throwing v
  | .varAt v T ℓ' => .varAt v T ℓ'
  | .seq m₁ m₂ => .seq (m₁.resolve x ℓ) (m₂.resolve x ℓ)

/--
Resolve each reference to variable `x` in the elements `ms` of a block to the cell at `ℓ`, as
`LoweredExpr.resolve` does. A declaration of `x` among the elements shadows the outer `x` for the
rest of the block, so resolution stops there.
-/
@[expose]
public def LoweredExpr.resolveBlock (x : Variable) (ℓ : Loc) :
    List LoweredExpr → List LoweredExpr
  | [] => []
  | m :: ms =>
    match m with
    | .declare v _ _ => if v = x then m :: ms else m :: resolveBlock x ℓ ms
    | _ => m.resolve x ℓ :: resolveBlock x ℓ ms

end

/--
Bind free variables (such as formal parameters) to cells: resolve each variable in `bindings` to
its cell, as if it had been declared around `m`. Running an expression that has free variables
starts with binding them to cells allocated in the initial state.
-/
@[expose]
public def LoweredExpr.bindVariables (bindings : List (Variable × Loc)) (m : LoweredExpr) :
    LoweredExpr :=
  bindings.foldl (fun m (x, ℓ) => m.resolve x ℓ) m

end DartLang
