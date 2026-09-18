module
public import Lean

open Std.Do

namespace FlowAnalysis

/--
Helper theorem for proving the weakest precondition of a monadic program whose next operation is an
if/then/else ("ite") test.

(The standard Lean approach to such proofs is to use `simp` to move the if/then/else to a point
where it can be split using the `split` tactic, but there doesn't appear to be a way to do this
without `simp` doing a bunch of other rewrites that make the monadic code hard to read. This theorem
avoids the need for `simp` in this situation.)
-/
public theorem WP_ite [Monad m] [WP m ps] {t e : m α} [Decidable c]
    (hifTrue : c → P ⊢ₛ wp⟦t⟧ Q) (hifFalse : ¬c → P ⊢ₛ wp⟦e⟧ Q) :
    P ⊢ₛ wp⟦if c then t else e⟧ Q := by
  mintro hP
  split
  case isTrue h => apply hifTrue h
  case isFalse h => apply hifFalse h

public abbrev stateIs {σs} (s : SVal.StateTuple σs) : SPred σs := SVal.curry (fun s' => ⟨s' = s⟩)

@[simp]
public theorem curry_evalsTo_pure :
    (((SVal.curry fun _ => ULift.up v)).evalsTo (ULift.up v') : SPred σs) = ⌜v = v'⌝ := by
  apply SPred.bientails.to_eq
  induction σs
  case nil => grind
  case cons σ σs' ih => intro s; simp; assumption
