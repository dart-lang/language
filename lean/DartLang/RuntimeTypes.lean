module
public import DartLang.Types

/-!
# The run-time view of Dart types

The run-time semantics needs one thing from a type representation beyond what flow analysis
needs: the run-time subtype check, which is-expressions and cast expressions perform. The
semantics also uses it for *promotion checks*: checks that a variable's value has the promoted
type that flow analysis recorded for it. Promotion checks aren't part of Dart. The semantics can
make them so that an unsound promotion makes a program get stuck, which turns the soundness of
flow analysis into a safety property: a proof that the semantics is type safe (with promotion
checks enabled) includes a proof that flow analysis is sound, and one can't be proved without the
other.

Subtyping in Dart is undecidable in general, so a run-time subtype check need not terminate. The
semantics therefore uses a *specification* of the check, the relation `RtSub`, rather than an
algorithm. The check may fail to terminate only when the answer would be no, though
(`DartRuntimeTypeRepr.rtSub_of_le`). In particular, the promotion check of a sound promotion always
passes. Running programs additionally needs an algorithm that implements the specification; that
is `RtSubChecker`, which only the interpreter requires.

Each concrete type representation provides instances of both classes next to its definition (see
`SimpleTypes.lean`).
-/

namespace DartLang

/--
A representation of Dart types that the run-time semantics can use.

Besides the declarative subtype relation `≤` (from `DartTypeRepr`), it has `RtSub S T b`, which
says that the run-time check of whether `S` is a subtype of `T` terminates with answer `b`. If
`RtSub S T b` holds for no `b`, the check doesn't terminate. Whenever the check answers, it must
agree with `≤`, and whenever `S ≤ T`, it must answer (`rtSub_of_le`). So `RtSub S T true` is
equivalent to `S ≤ T` (`rtSub_true_iff`), and the check can fail to terminate only when `S` isn't a
subtype of `T`.

The last requirement says that the check doesn't loop when the answer is yes. An algorithm that
tries the alternatives of a rule such as "`S <: T?` if `S <: T` or `S <: Null`" one at a time could
loop on the first even though the second holds, and wouldn't meet it. Where a Dart implementation's
check loops on a pair of types today, though, no reasonable program can depend on the answer, so
the declarative relation can count such a pair as not being a subtype, and the requirement holds.
-/
public class DartRuntimeTypeRepr (τ : Type) extends DartTypeRepr τ where
  /-- The run-time check of whether `S` is a subtype of `T` terminates with answer `b`. -/
  RtSub : τ → τ → Bool → Prop
  /-- If the run-time check says `S` is a subtype of `T`, it is. -/
  rtSub_true {S T : τ} : RtSub S T true → S ≤ T
  /-- If the run-time check says `S` isn't a subtype of `T`, it isn't. -/
  rtSub_false {S T : τ} : RtSub S T false → ¬ S ≤ T
  /-- If `S` is a subtype of `T`, the run-time check terminates, and says so. -/
  rtSub_of_le {S T : τ} : S ≤ T → RtSub S T true

export DartRuntimeTypeRepr (RtSub)

/-- The run-time subtype check answers yes (`RtSub S T true`) exactly when `S ≤ T`. -/
public theorem rtSub_true_iff {τ : Type} [DartRuntimeTypeRepr τ] {S T : τ} :
    RtSub S T true ↔ S ≤ T :=
  ⟨DartRuntimeTypeRepr.rtSub_true, DartRuntimeTypeRepr.rtSub_of_le⟩

/--
The run-time subtype check has at most one answer: if it answers both `b₁` (`h₁`) and `b₂` (`h₂`),
they're the same (`b₁ = b₂`).
-/
public theorem rtSub_unique {τ : Type} [DartRuntimeTypeRepr τ] {S T : τ} {b₁ b₂ : Bool}
    (h₁ : RtSub S T b₁) (h₂ : RtSub S T b₂) : b₁ = b₂ := by
  cases b₁ <;> cases b₂
  · rfl
  · exact absurd (DartRuntimeTypeRepr.rtSub_true h₂) (DartRuntimeTypeRepr.rtSub_false h₁)
  · exact absurd (DartRuntimeTypeRepr.rtSub_true h₁) (DartRuntimeTypeRepr.rtSub_false h₂)
  · rfl

/--
An algorithm for the run-time subtype check, which the interpreter uses. It is bounded by fuel,
a budget of work: `check fuel S T` is `some (b, fuel')` if the check answers `b` within the
budget, leaving `fuel'` unused, and `none` if the budget runs out first.

The algorithm must be *sound* (every answer satisfies `RtSub`) and *complete* (every answer that
`RtSub` allows is found with enough fuel). Soundness makes every step that the interpreter takes a
step of the semantics, and completeness makes the interpreter find every step that the semantics
takes, given enough fuel. More fuel must never change an answer (`check_mono`), so that a single
budget large enough for every check in a run can be found.
-/
public class RtSubChecker (τ : Type) [DartRuntimeTypeRepr τ] where
  /-- Runs the run-time subtype check of `S` against `T`, with a budget of `fuel`. -/
  check (fuel : Nat) (S T : τ) : Option (Bool × Nat)
  /-- The check never uses more fuel than it's given. -/
  check_fuel_le {fuel : Nat} {S T : τ} {b : Bool} {fuel' : Nat} :
    check fuel S T = some (b, fuel') → fuel' ≤ fuel
  /-- Extra fuel doesn't change the answer, and is left over unused. -/
  check_mono {fuel : Nat} {S T : τ} {b : Bool} {fuel' : Nat} (k : Nat) :
    check fuel S T = some (b, fuel') → check (fuel + k) S T = some (b, fuel' + k)
  /-- Every answer of the check is allowed by `RtSub`. -/
  check_sound {fuel : Nat} {S T : τ} {b : Bool} {fuel' : Nat} :
    check fuel S T = some (b, fuel') → RtSub S T b
  /-- Every answer allowed by `RtSub` is found, given enough fuel. -/
  check_complete {S T : τ} {b : Bool} :
    RtSub S T b → ∃ fuel fuel', check fuel S T = some (b, fuel')

end DartLang
