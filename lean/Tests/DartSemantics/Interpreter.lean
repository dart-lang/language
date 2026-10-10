module
import DartSemantics
import DartLang.SimpleTypes
meta import DartSemantics
meta import DartLang.SimpleTypes

/-!
# Tests of the interpreter

Runs programs on `SimpleType`. The programs include `LoweredExpr`s of the kind flow analysis
produces (some run with their local variable `x` replaced by a parameter, so that it can hold
something other than the null object), programs for each way a program can fail (throwing, and
getting stuck), and a program that runs out of fuel.

A block's value is the null object, so a program that is a block completes normally with the null
object, unless it throws or gets stuck.
-/

namespace DartSemantics.Tests.Interpreter

open DartLang SimpleType

local notation "LoweredExpr" => LoweredExpr (τ := SimpleType)
local notation "Variable" => Variable (τ := SimpleType)
local notation "Property" => Property (τ := SimpleType)
local notation "Value" => Value (τ := SimpleType)
local notation "State" => State (τ := SimpleType)

/--
The getter of every property that isn't backed by an instance variable returns the null object.
-/
def getterImpl : Property → Value → State → Option Value
  | _, _, _ => some .null

/-- The semantics with promotion checks. -/
@[instance_reducible]
def verify : SemanticParams SimpleType := ⟨.verify, getterImpl⟩

/-- The semantics without promotion checks. -/
@[instance_reducible]
def trust : SemanticParams SimpleType := ⟨.trust, getterImpl⟩

def x : Variable := ⟨"x", ObjectQ⟩
def y : Variable := ⟨"y", Object⟩

/-- A promotable property, backed by an instance variable of the object in `σx`. -/
def f : Property := ⟨"_f", ObjectQ, true⟩

/--
A property with the same name as `f` that flow analysis doesn't consider promotable. Whether a
property is promotable doesn't affect the semantics, so reading it reads the same instance
variable.
-/
def f' : Property := ⟨"_f", ObjectQ, false⟩

/-- A property that isn't backed by an instance variable of the object in `σx`. -/
def h : Property := ⟨"h", ObjectQ, false⟩

/--
A state for running a program with parameter `x`: `x` (at location 2) refers to an object (at
location 0) of type `int`, whose instance variable `_f` (at location 1) holds `true`.
-/
def σx : State :=
  ⟨#[.object int [("_f", ⟨1⟩)], .val (.bool true), .val (.obj ⟨0⟩)]⟩

/-- A summary of the result of a run, without the final state. -/
def summary : Interp.RunResult (τ := SimpleType) → Std.Format
  | .done o _ => "done: " ++ repr o
  | .stuck e _ => "stuck at: " ++ repr e
  | .outOfFuel e _ => "out of fuel at: " ++ repr e

/-- Run `m`, with parameter `x` bound to location 2 of `σx`. -/
def runWithX (P : SemanticParams SimpleType) (m : LoweredExpr) : Std.Format :=
  summary (Interp.run (P := P) 100 (m.bindVariables [(x, ⟨2⟩)]) σx)

/-- Run `m` from the empty state. -/
def runClosed (P : SemanticParams SimpleType) (m : LoweredExpr) : Std.Format :=
  summary (Interp.run (P := P) 100 m State.empty)

/-! ## Programs that flow analysis produces -/

-- `{ Object? x; x!; x }`: `x` is the null object, so `x!` throws.
/-- info: done: DartLang.Outcome.throwing (DartLang.Value.error (DartLang.DynamicError.typeError)) -/
#guard_msgs in
#eval runClosed verify
  (.block [.declare x ObjectQ true, .nullCheck (.var x ObjectQ), .var x Object])

-- `{ x!; x }`, where parameter `x` refers to an `int` (see `runWithX`), so `x!` succeeds, and the
-- promotion of `x` to `Object` is sound.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.null) -/
#guard_msgs in
#eval runWithX verify (.block [.nullCheck (.var x ObjectQ), .var x Object])

-- `{ Object? x; x as Object; x }`: `x` is the null object, so the cast throws.
/-- info: done: DartLang.Outcome.throwing (DartLang.Value.error (DartLang.DynamicError.typeError)) -/
#guard_msgs in
#eval runClosed verify
  (.block [.declare x ObjectQ true, .as (.var x ObjectQ) Object, .var x Object])

-- `{ x as Object; x }`, where parameter `x` refers to an `int` (see `runWithX`), so the cast
-- succeeds.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.null) -/
#guard_msgs in
#eval runWithX verify (.block [.as (.var x ObjectQ) Object, .var x Object])

-- `{ null }`
/-- info: done: DartLang.Outcome.normal (DartLang.Value.null) -/
#guard_msgs in
#eval runClosed verify (.block [.null])

-- `{ x! as int; x }`, where parameter `x` refers to an `int` (see `runWithX`), so the null check
-- and the cast succeed.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.null) -/
#guard_msgs in
#eval runWithX verify (.block [.as (.nullCheck (.var x ObjectQ)) int, .var x Object])

-- `{ (x as Object) as int; x }`, where parameter `x` refers to an `int` (see `runWithX`), so both
-- casts succeed.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.null) -/
#guard_msgs in
#eval runWithX verify (.block [.as (.as (.var x ObjectQ) Object) int, .var x Object])

-- `{ x._f!; x._f }`, where parameter `x` refers to an object whose `_f` holds `true` (see
-- `runWithX`), so `x._f!` succeeds, and the promotion of the second `x._f` to `Object` is sound.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.null) -/
#guard_msgs in
#eval runWithX verify
  (.block [.nullCheck (.propertyGet (.var x ObjectQ) f ObjectQ),
    .propertyGet (.var x ObjectQ) f Object])

/-! ## Other programs that complete normally -/

-- `x._f`, promoted to `Object`, where parameter `x` refers to an object whose `_f` holds `true`
-- (see `runWithX`), so the promotion is sound.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.bool true) -/
#guard_msgs in
#eval runWithX verify (.propertyGet (.var x ObjectQ) f Object)

-- `x.h`, where parameter `x` refers to an object with no instance variable `h` (see `runWithX`),
-- so the read runs the getter of `h`, which is user code (and returns the null object).
/-- info: done: DartLang.Outcome.normal (DartLang.Value.null) -/
#guard_msgs in
#eval runWithX verify (.propertyGet (.var x ObjectQ) h ObjectQ)

-- `x._f`, where flow analysis doesn't consider `_f` promotable, still reads the instance variable
-- `_f` of the object that parameter `x` refers to, which holds `true` (see `runWithX`).
/-- info: done: DartLang.Outcome.normal (DartLang.Value.bool true) -/
#guard_msgs in
#eval runWithX verify (.propertyGet (.var x ObjectQ) f' ObjectQ)

-- `x is int ? x : null`, where the first branch's `x` is promoted to `int`. Parameter `x` refers
-- to an `int` (see `runWithX`), so the first branch runs, and the promotion is sound.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.obj { n := 0 }) -/
#guard_msgs in
#eval runWithX verify (.cond (.is (.var x ObjectQ) int) (.var x int) .null ObjectQ)

-- `x is bool ? x : null`, where the first branch's `x` is promoted to `bool`. Parameter `x`
-- refers to an `int` (see `runWithX`), so the second branch runs.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.null) -/
#guard_msgs in
#eval runWithX verify (.cond (.is (.var x ObjectQ) bool) (.var x bool) .null ObjectQ)

-- `{ Object? x; } x!`: a declaration in a nested block doesn't shadow `x` after the block. So
-- `x!` reads parameter `x`, which refers to an `int` (see `runWithX`), not the null object.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.obj { n := 0 }) -/
#guard_msgs in
#eval runWithX verify (.seq (.block [.declare x ObjectQ true]) (.nullCheck (.var x ObjectQ)))

/-! ## Programs that throw -/

-- `null!`
/-- info: done: DartLang.Outcome.throwing (DartLang.Value.error (DartLang.DynamicError.typeError)) -/
#guard_msgs in
#eval runClosed verify (.nullCheck .null)

-- `x as bool`, where parameter `x` refers to an `int` (see `runWithX`), so the cast fails.
/-- info: done: DartLang.Outcome.throwing (DartLang.Value.error (DartLang.DynamicError.typeError)) -/
#guard_msgs in
#eval runWithX verify (.as (.var x ObjectQ) bool)

-- `{ null!; x }`: the exception propagates out of the rest of the block, so `x` is never read.
/-- info: done: DartLang.Outcome.throwing (DartLang.Value.error (DartLang.DynamicError.typeError)) -/
#guard_msgs in
#eval runWithX verify (.block [.nullCheck .null, .var x ObjectQ])

-- `{ Object? x; x! }`: the declared `x` (which is null) shadows the parameter `x`.
/-- info: done: DartLang.Outcome.throwing (DartLang.Value.error (DartLang.DynamicError.typeError)) -/
#guard_msgs in
#eval runWithX verify (.block [.declare x ObjectQ true, .nullCheck (.var x ObjectQ)])

/-! ## Programs that get stuck -/

-- `{ Object y; y }` reads `y` before it is assigned.
/--
info: stuck at: DartLang.LoweredExpr.seq
  (DartLang.LoweredExpr.varAt
    { name := "y", type := DartLang.SimpleType.Object }
    (DartLang.SimpleType.Object)
    { n := 0 })
  (DartLang.LoweredExpr.block [])
-/
#guard_msgs in
#eval runClosed verify (.block [.declare y Object false, .var y Object])

-- `x`, wrongly promoted to `bool`: parameter `x` refers to an `int` (see `runWithX`), so the
-- promotion check fails.
/--
info: stuck at: DartLang.LoweredExpr.varAt
  { name := "x", type := DartLang.SimpleType.ObjectQ }
  (DartLang.SimpleType.bool)
  { n := 2 }
-/
#guard_msgs in
#eval runWithX verify (.var x bool)

-- The same program runs without promotion checks.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.obj { n := 0 }) -/
#guard_msgs in
#eval runWithX trust (.var x bool)

-- `x._f`, wrongly promoted to `int`: the object that parameter `x` refers to has `true` in its
-- `_f` (see `runWithX`), so the promotion check fails.
/--
info: stuck at: DartLang.LoweredExpr.propertyGet
  (DartLang.LoweredExpr.val (DartLang.Value.obj { n := 0 }))
  { name := "_f", type := DartLang.SimpleType.ObjectQ, isPromotable := true }
  (DartLang.SimpleType.int)
-/
#guard_msgs in
#eval runWithX verify (.propertyGet (.var x ObjectQ) f int)

-- The same program runs without promotion checks.
/-- info: done: DartLang.Outcome.normal (DartLang.Value.bool true) -/
#guard_msgs in
#eval runWithX trust (.propertyGet (.var x ObjectQ) f int)

-- `x.h`, typed as `int`: the object that parameter `x` refers to has no instance variable `h`
-- (see `runWithX`), so the read runs the getter, which returns the null object, and that fails the
-- promotion check.
/--
info: stuck at: DartLang.LoweredExpr.propertyGet
  (DartLang.LoweredExpr.val (DartLang.Value.obj { n := 0 }))
  { name := "h", type := DartLang.SimpleType.ObjectQ, isPromotable := false }
  (DartLang.SimpleType.int)
-/
#guard_msgs in
#eval runWithX verify (.propertyGet (.var x ObjectQ) h int)

-- A variable that isn't bound to a cell can't be read.
/--
info: stuck at: DartLang.LoweredExpr.var { name := "x", type := DartLang.SimpleType.ObjectQ } (DartLang.SimpleType.ObjectQ)
-/
#guard_msgs in
#eval runClosed verify (.var x ObjectQ)

/-! ## A program that runs out of fuel -/

-- `{ x!; x }`, with parameter `x` as in `runWithX`, given fuel for only one step: the block becomes
-- a sequence, and then the run stops.
/--
info: out of fuel at: DartLang.LoweredExpr.seq
  (DartLang.LoweredExpr.nullCheck
    (DartLang.LoweredExpr.varAt
      { name := "x", type := DartLang.SimpleType.ObjectQ }
      (DartLang.SimpleType.ObjectQ)
      { n := 2 }))
  (DartLang.LoweredExpr.block
    [DartLang.LoweredExpr.varAt
       { name := "x", type := DartLang.SimpleType.ObjectQ }
       (DartLang.SimpleType.Object)
       { n := 2 }])
-/
#guard_msgs in
#eval summary
  (Interp.run (P := verify) 1
    ((LoweredExpr.block [.nullCheck (.var x ObjectQ), .var x Object]).bindVariables [(x, ⟨2⟩)])
    σx)

end DartSemantics.Tests.Interpreter
