(* Compute the effective signature of a member, based on the declaration-site
 * variance modifiers in the receiver class declaration, and the use-site
 * variance annotations in the receiver type, plus in the member signature
 * itself. The model considers only classes with exactly one type parameter.
 * The main functions are `widen` and `narrow`.
 *
 * `widen` receives an argument which is a configuration `(d, X, u, T, S)`;
 * `d` is the declaration-site variance, `X` is the name of the type variable
 * of the receiver class, `u` is the use-site variance in the receiver type,
 * `T` is the actual type argument in the receiver type, and `S` is the type
 * from the member signature. See the comments in `typeModel.sml` for more
 * details about the modeling of `d` (with constructors of the form D_..) 
 * and `u` (with constructors of the form U_..).
 *
 * `widen` will then compute a type which is a supertype of `[T/X]S` as
 * well as a supertype of `[T1/X]S` where `T1` is any possible dynamic
 * value of the type argument corresponding to `T`. The relationship between
 * the type argument `T` and the possible dynamic values corresponding to
 * `T` is determined by the given variances (declaration-site and use-site).
 *
 * For instance, if the receiver type is `Ci<out T>` where the type argument
 * of `Ci` is is `inout` then the receiver will be of type `Ci<inout T1>` 
 * at run-time, such that `T1 <: T`. Similarly, for `Ci<in T>` the known
 * relationship is `T <: T1`, and for `Ci<T>` it is known that `T1 == T`.
 *)

(* Raised when the given configuration is an error *)
exception Impossible;

fun boundOf X = T_Var (String.concat [X, ".bound"]);
val Never = T_Var "Never";

fun needsRecursion (T_Var _) = false
  | needsRecursion (T_Cl (T_Var _)) = false
  | needsRecursion (T_Co (T_Var _)) = false
  | needsRecursion (T_Ci (T_Var _)) = false
  | needsRecursion (T_Con (T_Var _)) = false
  | needsRecursion (T_CiOut (T_Var _)) = false
  | needsRecursion (T_CiIn (T_Var _)) = false
  | needsRecursion (T_CoInout (T_Var _)) = false
  | needsRecursion (T_ConInout (T_Var _)) = false
  | needsRecursion T_Other = false
  | needsRecursion _ = true;

local fun ws X Y T newT S = if X = Y then (T, newT) else (S, false) in
fun widenSubst X T newT (S as T_Var Y) = ws X Y T newT S
  | widenSubst X T newT (S as T_Cl (T_Var Y)) = ws X Y (T_Cl T) newT S
  | widenSubst X T newT (S as T_Co (T_Var Y)) = ws X Y (T_Co T) newT S
  | widenSubst X T newT (S as T_Ci (T_Var Y)) = ws X Y (T_CiOut T) true S
  | widenSubst X T newT (S as T_Con (T_Var Y)) = ws X Y (T_Con T) newT S
  | widenSubst X T newT (S as T_CiOut (T_Var Y)) = ws X Y (T_CiOut T) newT S
  | widenSubst X T newT (S as T_CiIn (T_Var Y)) = ws X Y (T_CiIn T) newT S
  | widenSubst X T newT (S as T_CoInout (T_Var Y)) = ws X Y (T_Co T) true S
  | widenSubst X T newT (S as T_ConInout (T_Var Y)) = ws X Y (T_Con T) true S
  | widenSubst _ _ _ _ = raise Impossible
end

local fun ns X Y T S = if X = Y then (T, true) else (S, false) in
fun narrowSubst X (S as T_Var Y) = ns X Y Never S
  | narrowSubst X (S as T_Cl (T_Var Y)) = ns X Y (T_Cl Never) S
  | narrowSubst X (S as T_Co (T_Var Y)) = ns X Y (T_Co Never) S
  | narrowSubst X (S as T_Ci (T_Var Y)) = ns X Y Never S
  | narrowSubst X (S as T_Con (T_Var Y)) = ns X Y (T_Con (boundOf X)) S
  | narrowSubst X (S as T_CiOut (T_Var Y)) = ns X Y (T_CiOut Never) S
  | narrowSubst X (S as T_CiIn (T_Var Y)) = ns X Y (T_CiIn (boundOf X)) S
  | narrowSubst X (S as T_CoInout (T_Var Y)) = ns X Y Never S
  | narrowSubst X (S as T_ConInout (T_Var Y)) = ns X Y Never S
  | narrowSubst _ _ = raise Impossible
end

fun eliminateRedundancy (D_OUT, X, U_OUT, T, S) = (D_OUT, X, U_NONE, T, S)
  | eliminateRedundancy (D_INOUT, X, U_INOUT, T, S) = (D_INOUT, X, U_NONE, T, S)
  | eliminateRedundancy (D_IN, X, U_IN, T, S) = (D_IN, X, U_NONE, T, S)
  | eliminateRedundancy c = c;

fun contradiction (D_LEGACY, U_IN) = true
  | contradiction (D_OUT, U_IN) = true
  | contradiction (D_IN, U_OUT) = true
  | contradiction _ = false;

fun widen c =
    let val (d, X, u, T, S) = eliminateRedundancy c
        val _ = if contradiction (d, u) then raise Impossible else ()
        fun wrongPosition (D_OUT, S as T_Ci (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_Con (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_CiIn (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_CoInout (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_ConInout (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_Var Y) = true
          | wrongPosition (D_IN, S as T_Cl (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_Co (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_Ci (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_CiOut (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_CoInout (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_ConInout (T_Var Y)) = true
          | wrongPosition (d, S) = false
        val _ = if wrongPosition (d, S) then raise Impossible else ()
        fun doWidenToBound (D_INOUT, U_IN, T_Var _) = true
          | doWidenToBound (D_INOUT, U_IN, T_Cl (T_Var _)) = true
          | doWidenToBound (D_INOUT, U_IN, T_Co (T_Var _)) = true
          | doWidenToBound (D_INOUT, U_IN, T_Ci (T_Var _)) = true
          | doWidenToBound (D_INOUT, U_IN, T_CiOut (T_Var _)) = true
          | doWidenToBound (D_INOUT, U_IN, T_CoInout (T_Var _)) = true
          | doWidenToBound (_, U_STAR, T_Var _) = true
          | doWidenToBound (_, U_STAR, T_Cl (T_Var _)) = true
          | doWidenToBound (_, U_STAR, T_Co (T_Var _)) = true
          | doWidenToBound (_, U_STAR, T_Ci (T_Var _)) = true
          | doWidenToBound (_, U_STAR, T_CiOut (T_Var _)) = true
          | doWidenToBound (_, U_STAR, T_CoInout (T_Var _)) = true
          | doWidenToBound _ = false
        fun doWidenToT (D_LEGACY, U_NONE, T_Ci (T_Var Y)) = true
          | doWidenToT (D_LEGACY, U_NONE, T_CoInout (T_Var Y)) = true
          | doWidenToT (D_LEGACY, U_OUT, T_Ci (T_Var Y)) = true
          | doWidenToT (D_LEGACY, U_OUT, T_CoInout (T_Var Y)) = true
          | doWidenToT (D_INOUT, U_OUT, T_Ci (T_Var Y)) = true
          | doWidenToT (D_INOUT, U_OUT, T_CoInout (T_Var Y)) = true
          | doWidenToT (D_INOUT, U_IN, T_ConInout (T_Var Y)) = true
          | doWidenToT _ = false
        fun doWidenToNever (D_LEGACY, U_NONE, T_Con (T_Var Y)) = true
          | doWidenToNever (D_LEGACY, U_NONE, T_CiIn (T_Var Y)) = true
          | doWidenToNever (D_LEGACY, U_NONE, T_ConInout (T_Var Y)) = true
          | doWidenToNever (D_LEGACY, U_OUT, T_Con (T_Var Y)) = true
          | doWidenToNever (D_LEGACY, U_OUT, T_CiIn (T_Var Y)) = true
          | doWidenToNever (D_LEGACY, U_OUT, T_ConInout (T_Var Y)) = true
          | doWidenToNever (D_INOUT, U_OUT, T_Con (T_Var Y)) = true
          | doWidenToNever (D_INOUT, U_OUT, T_CiIn (T_Var Y)) = true
          | doWidenToNever (D_INOUT, U_OUT, T_ConInout (T_Var Y)) = true
          | doWidenToNever (_, U_STAR, T_Con (T_Var Y)) = true
          | doWidenToNever (_, U_STAR, T_CiIn (T_Var Y)) = true
          | doWidenToNever (_, U_STAR, T_ConInout (T_Var Y)) = true
          | doWidenToNever _ = false
        fun wrap (d, u, U) transform wrapper =
            let val (U1, transformed) = transform (d, X, u, T, U)
            in  (wrapper (U1, transformed), transformed)
            end
        fun recur (d, u, T_Cl U) =
            wrap (d, u, U) widen (fn (U1, _) => T_Cl U1)
          | recur (d, u, T_Co U) =
            wrap (d, u, U) widen (fn (U1, _) => T_Co U1)
          | recur (d, u, T_Ci U) =
            let fun wrapper (U1, widened) =
                    if widened then T_CiOut U1 else T_Ci U1
            in  wrap (d, u, U) widen wrapper
            end
          | recur (d, u, T_Con U) =
            wrap (d, u, U) narrow (fn (U1, _) => T_Con U1)
          | recur (d, u, T_CiOut U) =
            wrap (d, u, U) widen (fn (U1, _) => T_CiOut U1)
          | recur (d, u, T_CiIn U) =
            wrap (d, u, U) narrow (fn (U1, _) => T_CiIn U1)
          | recur (d, u, T_CoInout U) =
            let fun wrapper (U1, widened) = if widened
                                            then T_Co U1
                                            else T_CoInout U1
            in  wrap (d, u, U) widen wrapper
            end
          | recur (d, u, T_ConInout U) =
            let fun wrapper (U1, narrowed) = if narrowed
                                             then T_Con U1
                                             else T_ConInout U1
            in  wrap (d, u, U) narrow wrapper
            end
    in  if needsRecursion S then recur (d, u, S) else
        if doWidenToBound (d, u, S) then widenSubst X (boundOf X) true S else
        if doWidenToT (d, u, S) then widenSubst X T false S else
        if doWidenToNever (d, u, S) then widenSubst X Never true S else
        (subst X T S, false)
    end

and narrow c =
    let val (d, X, u, T, S) = eliminateRedundancy c
        val _ = if contradiction (d, u) then raise Impossible else ()
        fun wrongPosition (D_IN, S as T_Ci (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_Con (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_CiIn (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_CoInout (T_Var Y)) = true
          | wrongPosition (D_IN, S as T_ConInout (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_Var Y) = true
          | wrongPosition (D_OUT, S as T_Cl (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_Co (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_Ci (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_CiOut (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_CoInout (T_Var Y)) = true
          | wrongPosition (D_OUT, S as T_ConInout (T_Var Y)) = true
          | wrongPosition _ = false
        val _ = if wrongPosition (d, S) then raise Impossible else ()
        fun doNarrow (D_LEGACY, U_NONE, T_Ci (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_NONE, T_CiOut (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_NONE, T_Cl (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_NONE, T_Co (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_NONE, T_CoInout (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_NONE, T_ConInout (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_NONE, T_Var Y) = true
          | doNarrow (D_LEGACY, U_OUT, T_Ci (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_OUT, T_CiOut (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_OUT, T_Cl (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_OUT, T_Co (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_OUT, T_CoInout (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_OUT, T_ConInout (T_Var Y)) = true
          | doNarrow (D_LEGACY, U_OUT, T_Var Y) = true
          | doNarrow (D_INOUT, U_OUT, T_Ci (T_Var Y)) = true
          | doNarrow (D_INOUT, U_OUT, T_CiOut (T_Var Y)) = true
          | doNarrow (D_INOUT, U_OUT, T_Cl (T_Var Y)) = true
          | doNarrow (D_INOUT, U_OUT, T_Co (T_Var Y)) = true
          | doNarrow (D_INOUT, U_OUT, T_CoInout (T_Var Y)) = true
          | doNarrow (D_INOUT, U_OUT, T_ConInout (T_Var Y)) = true
          | doNarrow (D_INOUT, U_OUT, T_Var Y) = true
          | doNarrow (D_INOUT, U_IN, T_Ci (T_Var Y)) = true
          | doNarrow (D_INOUT, U_IN, T_CiIn (T_Var Y)) = true
          | doNarrow (D_INOUT, U_IN, T_CoInout (T_Var Y)) = true
          | doNarrow (D_INOUT, U_IN, T_Con (T_Var Y)) = true
          | doNarrow (D_INOUT, U_IN, T_ConInout (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_Ci (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_CiIn (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_CiOut (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_Cl (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_Co (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_CoInout (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_Con (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_ConInout (T_Var Y)) = true
          | doNarrow (_, U_STAR, T_Var Y) = true
          | doNarrow _ = false
        fun wrap (d, u, U) transform wrapper =
            let val (U1, transformed) = transform (d, X, u, T, U)
            in  (wrapper (U1, transformed), transformed)
            end
        fun recur (d, u, T_Cl U) =
            wrap (d, u, U) narrow (fn (U1, _) => T_Cl U1)
          | recur (d, u, T_Co U) =
            wrap (d, u, U) narrow (fn (U1, _) => T_Co U1)
          | recur (d, u, T_Ci U) =
            let fun wrapper (U1, narrowed) = if narrowed
                                             then Never
                                             else T_Ci U1
            in  wrap (d, u, U) narrow wrapper
            end
          | recur (d, u, T_Con U) =
            wrap (d, u, U) widen (fn (U1, _) => T_Con U1)
          | recur (d, u, T_CiOut U) =
            wrap (d, u, U) narrow (fn (U1, _) => T_CiOut U1)
          | recur (d, u, T_CiIn U) =
            wrap (d, u, U) widen (fn (U1, _) => T_CiIn U1)
          | recur (d, u, T_CoInout U) =
            let fun wrapper (U1, narrowed) = if narrowed
                                             then Never
                                             else T_CoInout U1
            in  wrap (d, u, U) narrow wrapper
            end
          | recur (d, u, T_ConInout U) =
            let fun wrapper (U1, narrowed) = if narrowed
                                             then Never
                                             else T_ConInout U1
            in  wrap (d, u, U) widen wrapper
            end
    in  if needsRecursion S then recur (d, u, S) else
        if doNarrow (d, u, S) then narrowSubst X S else
        (subst X T S, false)
    end;
