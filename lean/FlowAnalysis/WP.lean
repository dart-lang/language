module
public import Lean

/-!
# Helpers for reasoning about monadic programs

The Lean models of Dart algorithms (such as `FlowAnalysis.PromotionChain.JoinImpl`) are written as
monadic programs, so that they can mirror the loops and mutable variables of the Dart code. Their
correctness is stated and proved using Lean's `Std.Do` framework, as Hoare triples
(`⦃P⦄ prog ⦃Q⦄`) whose pre- and postconditions are assertions about the program's state. This file
collects helpers for writing such proofs.
-/

open Std.Do

namespace FlowAnalysis

/--
Helper theorem for proving the weakest precondition of a monadic program whose next operation is an
if/then/else ("ite") test: `P` entails the weakest precondition of `if c then t else e` for `Q` if
it entails that of `t` when `c` holds (`hifTrue`), and that of `e` when it doesn't (`hifFalse`).

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

/--
`stateIs s` is the assertion that the program's state is exactly `s`. In a Hoare triple, a
precondition `stateIs s₀` paired with a postcondition that includes `stateIs s₀` says that the
program leaves its state unchanged.
-/
public abbrev stateIs {σs} (s : SVal.StateTuple σs) : SPred σs := SVal.curry (fun s' => ⟨s' = s⟩)

/--
A state-independent value `v` (`SVal.curry fun _ => ULift.up v`) evaluates to `v'` (`evalsTo`)
exactly when `v = v'` (`⌜v = v'⌝`).
-/
@[simp]
public theorem curry_evalsTo_pure :
    (((SVal.curry fun _ => ULift.up v)).evalsTo (ULift.up v') : SPred σs) = ⌜v = v'⌝ := by
  apply SPred.bientails.to_eq
  induction σs
  case nil => grind
  case cons σ σs' ih => intro s; simp; assumption
