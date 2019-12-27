(* Model a core of the Dart types that allows for investigating the combined
 * effect of declaration-site and use-site variance annotations on the type
 * of a member. See comments in `widen.sml` and `showWidening.sml` for more
 * detail.
 *)

(* D_LEGACY models a type parameter declaration with no variance modifier.
 * D_OUT models a type parameter declaration with modifier `out` (covariance),
 * D_INOUT models `inout` (invariance), and D_IN models `in` (contravariance).
 *)
datatype DeclarationVariance
  = D_LEGACY | D_OUT | D_INOUT | D_IN;

(* U_NONE models an actual type argument without any use-site variance
 * modifiers; U_OUT models `out` (covariance), U_INOUT models `inout`
 * (invariance), U_IN models `in` (contravariance), and U_STAR models
 * `*` (bivariance, that is, the actual type argument can be anything).
 *)
datatype UseVariance
  = U_NONE | U_OUT | U_INOUT | U_IN | U_STAR;

(* This is a minimal model of Dart types, just sufficient to make the 
 * important distinctions needed in order to specify the behavior of the
 * effective member signature computation. It models 4 different classes
 * with exactly one type parameter: `Cl` has a legacy type parameter, `Co`
 * has a covariant type parameter, `Ci` has an invariant type parameter,
 * an `Con` has a contravariant type parameter. Moreover, the significant
 * use-site modifiers are modelled: `CiOut` models `Ci` with an actual type
 * argument with an `out` modifier, `CiIn` models `Ci` with an actual type
 * argument with an `in` modifier, `CoInout` models `Co` with an actual type
 * argument with an `inout` modifier, and `ConInout` models `Con` with an
 * actual type argument with an `inout` modifier.
 * 
 * All other combinations are redundant or errors. For instance, `Co<out T>`
 * where the type parameter of `Co` is covariant is the same as `Co<T>`,
 * and `Con<out T>` where the type parameter of `Con` is contravariant is
 * an error. *)
datatype Type
  = T_Var of string (* A type variable *)
  | T_Cl of Type (* A class whose single type argument is legacy *)
  | T_Co of Type (* A class whose single type argument is `out` *)
  | T_Ci of Type (* A class whose single type argument is `inout` *)
  | T_Con of Type (* A class whose single type argument is `in` *)
  | T_CiOut of Type (* T_Ci with use-site modifier `out` *)
  | T_CiIn of Type (* T_Ci with use-site modifier `in` *)
  | T_CoInout of Type (* T_Co with use-site modifier `inout` *)
  | T_ConInout of Type (* T_Con with use-site modifier `inout` *)
  | T_Other; (* Any type that does not contain any type variables *)

(* ---------- Substitution (ignores capture: we do not model binders) *)

fun subst X T (S as T_Var Y) = if X = Y then T else S
  | subst X T (T_Cl t) = T_Cl (subst X T t)
  | subst X T (T_Co t) = T_Co (subst X T t)
  | subst X T (T_Ci t) = T_Ci (subst X T t)
  | subst X T (T_Con t) = T_Con (subst X T t)
  | subst X T (T_CiOut t) = T_CiOut (subst X T t)
  | subst X T (T_CiIn t) = T_CiIn (subst X T t)
  | subst X T (T_CoInout t) = T_CoInout (subst X T t)
  | subst X T (T_ConInout t) = T_ConInout (subst X T t)
  | subst X T T_Other = T_Other;

(* ---------- Queries about the occurrences of a type variable in a type *)

fun occurs X (T_Var Z) = X = Z
  | occurs X (T_Cl t) = occurs X t
  | occurs X (T_Co t) = occurs X t
  | occurs X (T_Ci t) = occurs X t
  | occurs X (T_Con t) = occurs X t
  | occurs X (T_CiOut t) = occurs X t
  | occurs X (T_CiIn t) = occurs X t
  | occurs X (T_CoInout t) = occurs X t
  | occurs X (T_ConInout t) = occurs X t
  | occurs X T_Other = false;

fun occursOnlyCovariantly X (T_Var _) = true
  | occursOnlyCovariantly X (T_Cl t) = occursOnlyCovariantly X t
  | occursOnlyCovariantly X (T_Co t) = occursOnlyCovariantly X t
  | occursOnlyCovariantly X (T_Ci t) = not (occurs X t)
  | occursOnlyCovariantly X (T_Con t) = occursOnlyContravariantly X t
  | occursOnlyCovariantly X (T_CiOut t) = occursOnlyCovariantly X t
  | occursOnlyCovariantly X (T_CiIn t) = occursOnlyContravariantly X t
  | occursOnlyCovariantly X (T_CoInout t) = not (occurs X t)
  | occursOnlyCovariantly X (T_ConInout t) = not (occurs X t)
  | occursOnlyCovariantly X T_Other = true

and occursOnlyContravariantly X (T_Var Z) = X <> Z
  | occursOnlyContravariantly X (T_Cl t) = occursOnlyContravariantly X t
  | occursOnlyContravariantly X (T_Co t) = occursOnlyContravariantly X t
  | occursOnlyContravariantly X (T_Ci t) = not (occurs X t)
  | occursOnlyContravariantly X (T_Con t) = occursOnlyCovariantly X t
  | occursOnlyContravariantly X (T_CiOut t) = occursOnlyContravariantly X t
  | occursOnlyContravariantly X (T_CiIn t) = occursOnlyCovariantly X t
  | occursOnlyContravariantly X (T_CoInout t) = not (occurs X t)
  | occursOnlyContravariantly X (T_ConInout t) = not (occurs X t)
  | occursOnlyContravariantly X T_Other = true;

(* ---------- Pretty-printing *)

fun typeToString (T_Var Z) = Z
  | typeToString (T_Cl T) =
    String.concat ["Cl<", typeToString T, ">"]
  | typeToString (T_Co T) =
    String.concat ["Co<", typeToString T, ">"]
  | typeToString (T_Ci T) =
    String.concat ["Ci<", typeToString T, ">"]
  | typeToString (T_Con T) =
    String.concat ["Con<", typeToString T, ">"]
  | typeToString (T_CiOut T) =
    String.concat ["Ci<out ", typeToString T, ">"]
  | typeToString (T_CiIn T) =
    String.concat ["Ci<in ", typeToString T, ">"]
  | typeToString (T_CoInout T) =
    String.concat ["Co<inout ", typeToString T, ">"]
  | typeToString (T_ConInout T) =
    String.concat ["Con<inout ", typeToString T, ">"]
  | typeToString  T_Other = "Other";

fun declarationVarianceToString D_LEGACY = ""
  | declarationVarianceToString D_OUT = "out "
  | declarationVarianceToString D_INOUT = "inout "
  | declarationVarianceToString D_IN = "in ";

fun useVarianceToTypeArgumentString U_NONE T = T
  | useVarianceToTypeArgumentString U_OUT T = String.concat ["out ", T]
  | useVarianceToTypeArgumentString U_INOUT T = String.concat ["inout ", T]
  | useVarianceToTypeArgumentString U_IN T = String.concat ["in ", T]
  | useVarianceToTypeArgumentString U_STAR _ = "*";

(* Assuming that the actual type argument to the receiver is shown as "T" *)
fun configToString (d, X, u, T, t) =
    String.concat [
        "(",
        declarationVarianceToString d,
        X, ": ",
        useVarianceToTypeArgumentString u (typeToString T),
        ", ",
        typeToString t,
        ")"];

(* ---------- List all configurations *)

val allConfigs =
    let val X = "X"
        val T = T_Var "T"
        val dVariances = [D_LEGACY, D_OUT, D_INOUT, D_IN]
        val uVariances = [U_NONE, U_OUT, U_INOUT, U_IN, U_STAR]
        val types = [
            T_Var X,
            T_Cl (T_Var X),
            T_Co (T_Var X),
            T_Ci (T_Var X),
            T_Con (T_Var X),
            T_CiOut (T_Var X),
            T_CiIn (T_Var X),
            T_CoInout (T_Var X),
            T_ConInout (T_Var X),

            T_Cl (T_Cl (T_Var X)),
            T_Cl (T_Co (T_Var X)),
            T_Cl (T_Ci (T_Var X)),
            T_Cl (T_Con (T_Var X)),
            T_Cl (T_CiOut (T_Var X)),
            T_Cl (T_CiIn (T_Var X)),
            T_Cl (T_CoInout (T_Var X)),
            T_Cl (T_ConInout (T_Var X)),

            T_Co (T_Cl (T_Var X)),
            T_Co (T_Co (T_Var X)),
            T_Co (T_Ci (T_Var X)),
            T_Co (T_Con (T_Var X)),
            T_Co (T_CiOut (T_Var X)),
            T_Co (T_CiIn (T_Var X)),
            T_Co (T_CoInout (T_Var X)),
            T_Co (T_ConInout (T_Var X)),

            T_Ci (T_Cl (T_Var X)),
            T_Ci (T_Co (T_Var X)),
            T_Ci (T_Ci (T_Var X)),
            T_Ci (T_Con (T_Var X)),
            T_Ci (T_CiOut (T_Var X)),
            T_Ci (T_CiIn (T_Var X)),
            T_Ci (T_CoInout (T_Var X)),
            T_Ci (T_ConInout (T_Var X)),

            T_Con (T_Cl (T_Var X)),
            T_Con (T_Co (T_Var X)),
            T_Con (T_Ci (T_Var X)),
            T_Con (T_Con (T_Var X)),
            T_Con (T_CiOut (T_Var X)),
            T_Con (T_CiIn (T_Var X)),
            T_Con (T_CoInout (T_Var X)),
            T_Con (T_ConInout (T_Var X)),

            T_CiOut (T_Cl (T_Var X)),
            T_CiOut (T_Co (T_Var X)),
            T_CiOut (T_Ci (T_Var X)),
            T_CiOut (T_Con (T_Var X)),
            T_CiOut (T_CiOut (T_Var X)),
            T_CiOut (T_CiIn (T_Var X)),
            T_CiOut (T_CoInout (T_Var X)),
            T_CiOut (T_ConInout (T_Var X)),

            T_CiIn (T_Cl (T_Var X)),
            T_CiIn (T_Co (T_Var X)),
            T_CiIn (T_Ci (T_Var X)),
            T_CiIn (T_Con (T_Var X)),
            T_CiIn (T_CiOut (T_Var X)),
            T_CiIn (T_CiIn (T_Var X)),
            T_CiIn (T_CoInout (T_Var X)),
            T_CiIn (T_ConInout (T_Var X)),

            T_CoInout (T_Cl (T_Var X)),
            T_CoInout (T_Co (T_Var X)),
            T_CoInout (T_Ci (T_Var X)),
            T_CoInout (T_Con (T_Var X)),
            T_CoInout (T_CiOut (T_Var X)),
            T_CoInout (T_CiIn (T_Var X)),
            T_CoInout (T_CoInout (T_Var X)),
            T_CoInout (T_ConInout (T_Var X)),

            T_ConInout (T_Cl (T_Var X)),
            T_ConInout (T_Co (T_Var X)),
            T_ConInout (T_Ci (T_Var X)),
            T_ConInout (T_Con (T_Var X)),
            T_ConInout (T_CiOut (T_Var X)),
            T_ConInout (T_CiIn (T_Var X)),
            T_ConInout (T_CoInout (T_Var X)),
            T_ConInout (T_ConInout (T_Var X)),

            T_Other,
            T_Cl T_Other,
            T_Co T_Other,
            T_Ci T_Other,
            T_Con T_Other,
            T_CiOut T_Other,
            T_CiIn T_Other,
            T_CoInout T_Other,
            T_ConInout T_Other
        ]
    in  List.concat
            (List.map
                 (fn typ =>
                     List.concat
                         (List.map
                              (fn uVar =>
                                  List.map
                                      (fn dVar => (dVar, X, uVar, T, typ))
                                      dVariances)
                              uVariances))
                 types)
    end;
