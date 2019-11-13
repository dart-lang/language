(* Run this using `sml showWidening.sml` to get a printout of the systematic
 * iteration over all combinations of a small set of cases: Declare a class
 * `C` with a single type argument and a single member which is a getter `g`
 * or a method `m` (thus covering a covariant and a contravariant placement
 * of a type in a member signature). Next, declare a variable `c` whose type
 * annotation is `C<... T>` where `T` is a type which is not modeled in more
 * detail (any type would do), and `...` stands for a use-site variance
 * modifier (absent, `out`, `inout`, or `in`). Finally, the printout shows
 * the return type of the getter respectively the parameter type of the
 * method, indicating how the declaration-site and use-site variance
 * annotations give rise to an 'effective' member signature.
 *)

use "typeModel.sml";
use "widen.sml";
open List;

(* ---------- Validation *)

fun checkConfig (D_LEGACY, _, U_IN, _, _) = false
  | checkConfig (D_OUT, _, U_IN, _, _) = false
  | checkConfig (D_IN, _, U_OUT, _, _) = false
  | checkConfig (_, _, _, _, _) = true;

fun checkCovariantConfig c =
    let fun f (D_LEGACY, _, _, _, _) = true
          | f (D_OUT, X, _, _, T) = occursOnlyCovariantly X T
          | f (D_INOUT, _, _, _, _) = true
          | f (D_IN, X, _, _, T) = occursOnlyContravariantly X T
    in  checkConfig c andalso f c
    end;

fun checkContravariantConfig c =
    let fun f (D_LEGACY, _, _, _, _) = true
          | f (D_OUT, X, _, _, T) = occursOnlyContravariantly X T
          | f (D_INOUT, _, _, _, _) = true
          | f (D_IN, X, _, _, T) = occursOnlyCovariantly X T
    in  checkConfig c andalso f c
    end;

(* ---------- Auxiliary testing functions *)

val concat = String.concat;

fun resultToString NONE = "-"
  | resultToString (SOME true) = "true"
  | resultToString (SOME false) = "false";

fun boolToString true = "true"
  | boolToString false = "false";

fun classOfConfig c member comment =
    let val (d, X, u, T, _) = c
        val receiverClassString =
            case d of D_LEGACY => "Cl"
                    | D_OUT => "Co"
                    | D_INOUT => "Ci"
                    | D_IN => "Con"
        val typeParametersString =
            case d of D_LEGACY => concat ["<", X, ">"]
                    | D_OUT => concat ["<out ", X, ">"]
                    | D_INOUT => concat ["<inout ", X, ">"]
                    | D_IN => concat ["<in ", X, ">"]
        val typeArgumentsString =
            case u of U_NONE => "<T>"
                    | U_OUT => "<out T>"
                    | U_INOUT => "<inout T>"
                    | U_IN => "<in T>"
                    | U_STAR => "<*>"
    in  concat [
            "class ", receiverClassString, typeParametersString,
            " {\n  ", member, "\n}\n",
            receiverClassString,
            typeArgumentsString,
            " c; // ", comment, "\n\n"
        ]
    end;

(* ---------- Look at the outcome from `widen`, `narrow` *)

fun showGetter (c as (d, X, u, T, S)) =
    let val ok = checkCovariantConfig c
        val resultString =
            if ok then
                let val (widenResult, widened) = widen c
                in  concat [
                        "c.g ",
                        if widened then "widened" else "ok",
                        ": ",
                        typeToString widenResult
                    ]
                end
            else "Impossible"
        val (_, _, _, _, t) = c
        val member = concat [typeToString t, " get g => ...;"]
    in  print (classOfConfig c member resultString)
    end;

fun showMethod (c as (d, X, u, T, S)) =
    let val ok = checkContravariantConfig c
        val resultString =
            if ok then
                let val (narrowResult, narrowed) = narrow c
                in  concat ["c.m(_) ",
                            if narrowed then "narrowed" else "ok",
                            ": ",
                            typeToString narrowResult
                           ]
                end
            else "Impossible"
        val (_, _, _, _, t) = c
        val member = concat ["void m(", typeToString t, " arg) {}"]
    in  print (classOfConfig c member resultString)
    end;

val _ = print "---------- Show code plus {widen,narrow} outcome.\n";
val _ = map showGetter allConfigs;
val _ = map showMethod allConfigs;
