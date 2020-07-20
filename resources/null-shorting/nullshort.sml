(* This file contains an SML program which can be used to explore
 * the null-shorting mechanism which is specified as part of the
 * NNBD feature specification, e.g., in order to write language
 * tests or just to clarify the semantics.
 *
 * It models Dart syntax abstractly, as described below. As an example,
 * 'EQDF (EXP, NAME "f")' represents the Dart expression `<exp>?.f`, where
 * `<exp>` is a placeholder for all expressions that remain unchanged
 * during the null-shorting transformation. In order to transform that
 * expression, 'use' this file and evaluate 
 * 'showTransformation (EQDF (EXP, NAME "f"));'
 *)

open List;

(* ---------- Exceptions *)

(* Temporary: Used to report missing implementation *)
exception NotYet;

(* Term expressible by 'Exp' which is not derivable in the Dart grammar *)
exception NoSuchSyntax;

(* ---------- Model of Dart syntax *)

datatype Name = NAME of string;

(* 'Exp' models some Dart expressions. It omits modeling many forms,
 * because they are treated identically during the null-shorting
 * transformation. It includes a `let .. in ..` construct, because
 * it is needed in the desugared code.
 *
 * A special case is cascades. They are modeled as a constructor,
 * 'C' or 'CQ', that takes an expression and a function as arguments.
 * The expression is the cascade receiver (so in `e..s` it is `e`).
 * The function, let's call it 'f', has type `Exp -> Exp`, and it is
 * intended to model an expression with a hole, such that 'f x' will
 * yield the expression where the `x` has been inserted as the receiver.
 * The expression delivered by `f` should be the regular member access
 * corresponding to the cascade which is being modeled, no matter whether
 * the cascade is conditional or not. So if we are modeling `e..s` as
 * 'C (e, f1)' and `e?..s` as 'CQ (e, f2)' then 'f1 x' as well as 'f2 x'
 * should return `x.s`.
 *
 * This approach allows for modeling the cascades that the Dart grammar
 * can express. It also allows for modeling a large number of constructs
 * that we cannot express syntactically, but that isn't a problem in
 * this context.
 *)
datatype Exp =
         EXP (* "Other expressions": not transformed *)
       | NULL
       | ID of Name
       | COND of (Exp * Exp * Exp) (* e1 ? e2 : e3 *)
       | EQ of (Exp * Exp) (* e1 == e2 *)
       | LET of (Name * Exp * Exp) (* let x = e1 in e2 *)
       | EQDF of (Exp * Name) (* e?.f *)
       | EDF of (Exp * Name) (* e.f *)
       | EQDMA of (Exp * Name * Exp list) (* e?.m(args) *)
       | EDMA of (Exp * Name * Exp list) (* e.m(args) *)
       | EA of (Exp * Exp list) (* e(args) *)
       | EQDI of (Exp * Exp) (* e1?.[e2] *)
       | EI of (Exp * Exp) (* e1[e2] *)
       | EQDFA of (Exp * Name * Exp) (* e1?.f = e2 *)
       | EDFA of (Exp * Name * Exp) (* e1.f = e2 *)
       | EQDIA of (Exp * Exp * Exp) (* e1?.[e2] = e3 *)
       | EIA of (Exp * Exp * Exp) (* e1[e2] = e3 *)
       | C of (Exp * (Exp -> Exp)) (* e and `fn x => x.s`: e..s *)
       | CQ of (Exp * (Exp -> Exp)) (* e and `fn x => x.s`: e?..s *)
       ;

(* ---------- Model of null-shorting desugaring functions *)

val freshNameNumber = ref 0;

fun freshName () =
    let val number = !freshNameNumber;
        val _ = freshNameNumber := number + 1;
        val name = String.concat ["n", Int.toString number];
    in  NAME name
    end;

(* ID = fn[x : Exp] : Exp => x
 *
 * The trivial desugaring function. *)

fun id (x : Exp) = x;

(* SHORT = fn[r : Exp, c : Exp -> Exp] =>
 *             fn[k : Exp -> Exp] : Exp =>
 *                 let x = r in x == null ? null : k[c[x]]
 *
 * r:
 * c:
 * k: Continuation, what to do after "this task" has been completed.
 *
 * In general, the continuation remembers how to reconstruct the rest of the
 * method chain, and we just want to do that somewhere in the middle of an
 * expression that we've built along the way.
 *)
fun short (r: Exp, c: Exp -> Exp) (k: Exp -> Exp) =
    let val x = freshName();
    in  LET (x, r, COND (EQ (ID x, NULL), NULL, (k o c) (ID x)))
    end;

(* PASSTHRU = fn[F : (Exp -> Exp) -> Exp, c : Exp -> Exp] =>
 *                fn[k : Exp -> Exp] : Exp => F[fn[x] => k[c[x]]]
 *
 * F: Level 2 desugaring function (result of other translation).
 * c: Desugaring function.
 * k: Continuation.
 *)
fun passthru (F : (Exp -> Exp) -> Exp, c : Exp -> Exp) (k : Exp -> Exp) =
    F (fn x => k (c x));

(* TERM = fn[r : Exp] => fn[k : Exp -> Exp] : Exp => k[r]
 *
 * r: Expression.
 * k: Continuation.
 *)
fun term (r : Exp) (k : Exp -> Exp) = k r;

(* EXP = fn[x: Exp] => (xlate x) ID *)
fun exp (x: Exp) : Exp = (xlate x) id

(* ARGS *)
and mapexp (args: Exp list) = map exp args

(* Not named in feature spec, is the main translation routine.
 * Exp -> ((Exp -> Exp) -> Exp)
 *)

and xlate (EQDF (e, f)) =
    (* A property access e?.f translates to:
     * SHORT[EXP(e), fn[x] => x.f] *)
    short (exp e, fn x => EDF (x, f))

  | xlate (EDF (e, f)) =
    (* If e translates to F then e.f translates to:
     * PASSTHRU[F, fn[x] => x.f] *)
    passthru (xlate e, fn x => EDF (x, f))

  | xlate (EQDMA (e, m, args)) =
    (* A null aware method call e?.m(args) translates to:
     * SHORT[EXP(e), fn[x] => x.m(ARGS(args))] *)
    short (exp e, fn x => EDMA (x, m, mapexp args))

  | xlate (EDMA (e, m, args)) =
    (* If e translates to F then e.m(args) translates to:
     * PASSTHRU[F, fn[x] => x.m(ARGS(args))] *)
    passthru (xlate e, fn x => EDMA (x, m, mapexp args))

  | xlate (EA (e, args)) =
    (* If e translates to F then e(args) translates to:
     * PASSTHRU[F, fn[x] => x(ARGS(args))] *)
    passthru (xlate e, fn x => EA (x, mapexp args))

  | xlate (EQDI (e1, e2)) =
    (* If e1 translates to F then e1?.[e2] translates to:
     * SHORT[EXP(e1), fn[x] => x[EXP(e2)]] *)
    short (exp e1, fn x => EI (x, exp e2))

  | xlate (EI (e1, e2)) =
    (* If e1 translates to F then e1[e2] translates to:
     * PASSTHRU[F, fn[x] => x[EXP(e2)]] *)
    passthru (xlate e1, fn x => EI (x, exp e2))

  | xlate (EQDFA (e1, f, e2)) =
    (* The assignment e1?.f = e2 translates to:
     * SHORT[EXP(e1), fn[x] => x.f = EXP(e2)]
     * The other assignment operators are handled equivalently. *)
    short (exp e1, fn x => EDFA (x, f, exp e2))

  | xlate (EDFA (e1, f, e2)) =
    (* If e1 translates to F then e1.f = e2 translates to:
     * PASSTHRU[F, fn[x] => x.f = EXP(e2)]
     * The other assignment operators are handled equivalently. *)
     passthru (xlate e1, fn x => EDFA (x, f, exp e2))

  | xlate (EQDIA (e1, e2, e3)) =
    (* If e1 translates to F then e1?.[e2] = e3 translates to:
     * SHORT[EXP(e1), fn[x] => x[EXP(e2)] = EXP(e3)]
     * The other assignment operators are handled equivalently. *)
    short (exp e1, fn x => EIA (x, exp e2, exp e3))

  | xlate (EIA (e1, e2, e3)) =
    (* If e1 translates to F then e1[e2] = e3 translates to:
     * PASSTHRU[F, fn[x] => x[EXP(e2)] = EXP(e3)]
     * The other assignment operators are handled equivalently. *)
    passthru (xlate e1, fn x => EIA (x, exp e2, exp e3))

    (* A cascade expression e..s translates as follows,
     * where F is the translation of e
     * and x and y are fresh object level variables:
     *     fn[k : Exp -> Exp] : Exp =>
     *        F[fn[r : Exp] : Exp => let x = r in
     *                               let y = EXP(x.s)
     *                               in k[x]
     *        ]
     *)
  | xlate (C (e, f)) =
    let val F = xlate e
        val x = freshName()
        val y = freshName()
    in  fn k => F (fn r => LET (x, r, LET (y, exp (f (ID x)), k (ID x))))
    end

    (* A null-shorting cascade expression e?..s translates as follows,
     * where x and y are fresh object level variables.
     *    fn[k : Exp -> Exp] : Exp =>
     *        let x = EXP(e) in x == null ? null : let y = EXP(x.s) in k(x) *)
  | xlate (CQ (e, f)) =
    let val x = freshName()
        val y = freshName()
    in  fn k => LET (x,
                     exp e,
                     COND (EQ (ID x, NULL),
                           NULL,
                           LET (y, exp (f (ID x)), k (ID x))))
    end

    (* All other expressions are translated compositionally using the
     * TERM combinator. Examples:
     * An identifier x translates to TERM[x]
     * A list literal [e1, ..., en] translates to TERM[ [EXP(e1), ..., EXP(en)] ]
     * A parenthesized expression (e) translates to TERM[(EXP(e))]
     *)
  | xlate (ID name) =
    term (ID name)

  | xlate e =
    term e;

(* ---------- Printing *)

fun commafy [] = ""
  | commafy (x :: nil) = x
  | commafy (x :: xs)  = String.concat [x, ", ", commafy xs];

fun expToString EXP = "<exp>"
  | expToString NULL = "null"
  | expToString (ID (NAME n)) = (* n *)
    n
  | expToString (COND (e1, e2, e3)) = (* e1 ? e2 : e3 *)
    String.concat
        [expToString e1, " ? ", expToString e2, " : ", expToString e3]
  | expToString (EQ (e1, e2)) = (* e1 == e2 *)
    String.concat [expToString e1, " == ", expToString e2]
  | expToString (LET (NAME x, e1, e2)) = (* let x = e1 in e2 end *)
    String.concat
        ["let ", x, " = ", expToString e1, " in ", expToString e2, " end"]
  | expToString (EQDF (e1, NAME f)) = (* e?.f *)
    String.concat [expToString e1, "?.", f]
  | expToString (EDF (e1, NAME f)) = (* e.f *)
    String.concat [expToString e1, ".", f]
  | expToString (EQDMA (e, NAME m, args)) = (* e?.m(args) *)
    String.concat
        [expToString e, "?.", m, "(", commafy (map expToString args), ")"]
  | expToString (EDMA (e, NAME m, args)) = (* e.m(args) *)
    String.concat
        [expToString e, ".", m, "(", commafy (map expToString args), ")"]
  | expToString (EA (e, args)) = (* e(args) *)
    String.concat [expToString e, "(", commafy (map expToString args), ")"]
  | expToString (EQDI (e1, e2)) = (* e1?.[e2] *)
    String.concat [expToString e1, "?.[", expToString e2, "]"]
  | expToString (EI (e1, e2)) = (* e1[e2] *)
    String.concat [expToString e1, "[", expToString e2, "]"]
  | expToString (EQDFA (e1, NAME f, e2)) = (* e1?.f = e2 *)
    String.concat [expToString e1, "?.", f, " = ", expToString e2]
  | expToString (EDFA (e1, NAME f, e2)) = (* e1.f = e2 *)
    String.concat [expToString e1, ".", f, " = ", expToString e2]
  | expToString (EQDIA (e1, e2, e3)) = (* e1?.[e2] = e3 *)
    String.concat
        [expToString e1, "?.[", expToString e2, "] = ", expToString e3]
  | expToString (EIA (e1, e2, e3)) = (* e1[e2] = e3 *)
    String.concat
        [expToString e1, "[", expToString e2, "] = ", expToString e3]
  | expToString (C (e, f)) =
    String.concat [expToString e, ".", expToString (f (ID (NAME "")))]
  | expToString (CQ (e, f)) =
    String.concat [expToString e, "?.", expToString (f (ID (NAME "")))];

(* Transform an expression, printing both the before and after form *)

fun showTransformation e =
    let val src = expToString e
        val expSrc = expToString (exp e)
        val _ = print (String.concat [src, " -->\n", expSrc, "\n"])
    in  ()
    end;
