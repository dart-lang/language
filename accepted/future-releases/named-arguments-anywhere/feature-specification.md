# Dart Named Arguments Anywhere

Author: cstefantsova@google.com, lrn@google.com<br>Version: 1.0<br>Specifiction for issue [#1072](https://github.com/dart-lang/language/issues/1072)

## Motivation

Dart requires named arguments to come after positional arguments in a function invocation. Named arguments can be placed in any order, because they are matched by name, not position, but are still required to be placed after positional arguments.

Thats an unnecessary restriction. A compiler is perfectly capable of recognizing named arguments (they have a name followed by a `:`) and count positional arguments independently of the named arguments.

Allowing named arguments to be placed anywhere in the argument list, even before positional ones, allows some APIs to be much more convenient. Example:

```dart
expect(something, expectAsync1((x) {
  something;
  something.more();
  test(x);  
}, count: 2));
```

is less readable than:

```dart
expect(something, expectAsync1(count: 2, (x) {
  something;
  something.more();
  test(x);  
}));
```

because the `count` argument is closer to the method name it belongs to, and not separated by a longer function body.

## Specification

### Grammar

The language grammar is changed to allow named arguments before positional arguments.

The grammar:

> ```latex
> \begin{grammar}
> <arguments> ::= `(' (<argumentList> `,'?)? `)'
> 
> <argumentList> ::= <namedArgument> (`,' <namedArgument>)*
> \alt <expressionList> (`,' <namedArgument>)*
> 
> <namedArgument> ::= <label> <expression>
> \end{grammar}
> ```

becomes

> ```latex
> \begin{grammar}
> <arguments> ::= `(' (<argumentList> `,'?)? `)'
> 
> <argumentList> ::= <argument> (`,' <argument>)*
> 
> <argument> ::= <label>? <expression>
> \end{grammar}
> ```

Any place the language specification assumes an argument list has positional arguments before named arguments, it should be changed to assume arguments in any order, and if necessary, be rewritten to depend on the semantics given for argument lists in the _Actual Argument Lists_ section, as modified below, instead of doing anything directly.

### Static semantics

The current language specification is underspecified since all the real complexity is in the type inference, which hasn't been formally specified yet.

To update the current specification, the section:

> ```latex
> \LMHash{}%
> Let $L$ be an argument list of the form
> \code{($e_1 \ldots,\ e_m,\ y_{m+1}$: $e_{m+1} \ldots,\ y_{m+p}$: $e_{m+p}$)}
> and assume that the static type of $e_i$ is $S_i$, $i \in 1 .. m+p$.
> The \Index{static argument list type} of $L$ is then
> \code{($S_1 \ldots,\ S_m,\ S_{m+1}\ y_{m+1} \ldots,\ S_{m+p}\ y_{m+p}$)}.
> ```

becomes:

> Let *L* be an arguments list of the form <code>(*p*<sub>1</sub>, ... , *p*<sub>*k*</sub>)</code> with *m* positional arguments, *p*<sub>*q*<sub>1</sub></sub>, ... , *p*<sub>*q*<sub>m</sub></sub> (in source order) and *n* named arguments, *p*<sub>*d*<sub>1</sub></sub>, ... , *p*<sub>*d*<sub>n</sub></sub> (also in source order), so that *k = m + n*.
>
> A positional argument *p*<sub>*i*</sub> has the form <code>*e*<sub>*i*</sub></code> and a named argument *p*<sub>*i*</sub> has the form <code>*y*<sub>i</sub>: *e*<sub>*i*</sub></code>.
>
> Assume that the static type of <code>_e_<sub>*i*</sub></code> is *S*<sub>*i*</sub>, *i* &in; {1, ... ,  *k*}.
>
> The static argument list type of *L* is then <code>(*S*<sub>*q*<sub>1</sub></sub>, ... , *S*<sub>*q*<sub>m</sub></sub>, *S*<sub>*d*<sub>1</sub></sub> *y*<sub>*d*<sub>1</sub></sub>, ... , *S*<sub>*d*<sub>n</sub></sub> *y*<sub>*d*<sub>n</sub></sub>)</code>

_That is, we canonicalize the ordering for the type, and then proceed as we previously did._

**Type inference** also needs to be updated. It must match positional arguments with positional parameters in the called functions static type in order to provide a context type for the argument. This is done by matching named arguments against named parameters, as usual, and matching positional arguments against positional parameters *based on the number of earlier positional arguments* instead of just using the position in the argument list. Then expression types are inferred in source order like they are now. _Order is important since type inference of one expression may affect variable promotion for later expressions in the argument list._

### Runtime semantics

Evaluation of argument expressions is in source order. Then the *Actual Argument List Evaluation* algorithm is changed to account for named arguments occurring out of order, and the position of a positional argument not necessarily being its index in the argument list. Like above, we specify the evaluation as happening in source order, the canonicalize the ordering for the result.

The section containing:

> ```latex
> \LMHash{}%
> Evaluation of an actual argument part of the form
> 
> \noindent
> \code{<$A_1, \ldots,\ A_r$>($a_1, \ldots,\ a_m,\ q_1$: $a_{m+1}, \ldots,\ q_l$: $a_{m+l}$)}
> proceeds as follows:
> 
> \LMHash{}%
> The type arguments $A_1, \ldots, A_r$ are evaluated
> in the order they appear in the program,
> producing types $t_1, \ldots, t_r$.
> The arguments $a_1, \ldots, a_{m+l}$ are evaluated
> in the order they appear in the program,
> producing objects $o_1, \ldots, o_{m+l}$.
> 
> \commentary{%
> Simply stated, an argument part consisting of $s$ type arguments,
> $m$ positional arguments, and $l$ named arguments is
> evaluated from left to right.
> Note that the type argument list is omitted when $r = 0$
> (\ref{generics}).%
> }
> ```

becomes

> Evaluation of an actual argument part of the form <code>\<*A*<sub>1</sub>, ... , *A*<sub>*r*</sub>\>(*p*<sub>1</sub>, ... , *p*<sub>*m+l*</sub>)</code> with positional arguments *p*<sub>*v*<sub>1</sub></sub>, ... , *p*<sub>*v*<sub>*m*</sub></sub> of the form <code>*e*<sub>*v*<sub>*i*</sub></sub></code> and named arguments *p*<sub>*d*<sub>1</sub></sub>, ... , *p*<sub>*d*<sub>*l*</sub></sub> of the form <code>*q*<sub>*d*<sub>*i*</sub></sub>: *e*<sub>*d*<sub>*i*</sub></sub></code>, proceeds as follows:
>
> The type arguments *A*<sub>1</sub>, ... , *A*<sub>*r*</sub> are evaluated in the order they appear in the program, producing types *t*<sub>1</sub>, ... , *t*<sub>*r*</sub>.
>
> The argument expressions *e*<sub>1</sub>, ... , *e*<sub>*m+l*</sub> are evaluated in the order they appear in the program, producing objects *o*<sub>1</sub>, ... , *o*<sub>*m+l*</sub>.
>
> _Simply stated, an argument part consisting of *r* type arguments, *m* positional arguments, and *l* named arguments (in any order) is evaluated from left to right.
> Note that the type argument list is omitted when *r* = 0._
>
> The evaluated argument list is then \<*t*<sub>1</sub>, ... , *t*<sub>*r*</sub>>(*o*<sub>*v*<sub>1</sub></sub>, ... , *o*<sub>*v*<sub>*m*</sub></sub>, *q*<sub>*d*<sub>1</sub></sub>: *o*<sub>*d*<sub>1</sub></sub>, ... , *q*<sub>*d*<sub>*l*</sub></sub>: *o*<sub>*d*<sub>*l*</sub></sub>).

The semantics described above can be implemented entirely in the front-end, and the implementation can be described by the following desugaring step.

Let *e* be an invocation expression of the form <code>*e*<sub>0</sub>.*f*\<*A*<sub>1</sub>, ... , *A*<sub>*r*</sub>>(*p*<sub>1</sub>, ... , *p*<sub>*m*+*l*</sub>)</code> with positional arguments *p*<sub>*v*<sub>1</sub></sub>, ... , *p*<sub>*v*<sub>*m*</sub></sub> of the form <code>*e*<sub>*v*<sub>*i*</sub></sub></code> and named arguments *p*<sub>*d*<sub>1</sub></sub>, ... , *p*<sub>*d*<sub>*l*</sub></sub> of the form <code>*q*<sub>*d*<sub>*i*</sub></sub>: *e*<sub>*d*<sub>*i*</sub></sub></code>, where *e*<sub>0</sub> is the receiver and *f* is the member name. In this case *e* can be desugared to an equivalent of <code>**_let_** *x* = *e*<sub>0</sub>, *x*<sub>1</sub> = *e*<sub>1</sub>, ... , *x*<sub>*m*+*l*</sub> = *e*<sub>*m*+*l*</sub> **_in_** *x*.*f*\<*A*<sub>1</sub>, ... , *A*<sub>*r*</sub>>(*x*<sub>*v*<sub>1</sub></sub>, ... , *x*<sub>*v*<sub>*m*</sub></sub>, *q*<sub>*d*<sub>1</sub></sub> : *x*<sub>*d*<sub>1</sub></sub>, ... , *q*<sub>*d*<sub>*l*</sub></sub> : *x*<sub>*d*<sub>*l*</sub></sub>)</code>. Invocations of other forms can be desugared similarly.

Hoisting of some arguments can be avoided by the implementation if that doesn't change the evaluation order.

## Summary

We allow named arguments anywhere in the argument list, even before positional arguments.

The only real difference is that it changes evaluation order, allowing you to evaluate an argument to a named parameter before the argument to a positional argument. After evaluation, we can trivially normalize the ordering and keep our current specifications and implementations.

## Versions

1.0, 2021-11-01; Initial version
