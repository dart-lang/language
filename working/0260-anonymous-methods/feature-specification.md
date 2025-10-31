# Anonymous Methods

Author: eernst@google.com<br>
Version: 1.0

## Introduction



## Proposal

This proposal specifies anonymous methods. This is a new kind of expression
that allows general expressions or blocks of code to be executed in a way
that is similar to a method invocation, but inlining the code into the
expression itself.

### Syntax

The grammar is modified as follows:

```ebnf
<anonymousMethod> ::= // New rule.
    <formalParameterList>? <block> 
  | <formalParameterList>? '=>' <expressionWithoutCascade>;

<cascadeSelector> ::= // Modified rule.
    '[' <expression> ']'
  | <identifier>
  | <anonymousMethod>;

<selector> ::= // Modified rule.
    '!'
  | <assignableSelector>
  | <argumentPart>
  | <typeArguments>
  | <anonymousMethodInvocation>;

<anonymousMethodInvocation> ::=
    ('.' | '?.') <anonymousMethod>;
```

### Static analysis

Anonymous methods come in several forms, each of which is handled in
a separate section in the following.

#### Block bodied anonymous methods

Consider an anonymous method invocation of the form `e.{ S }` where `e` is
an expression and `S` is a sequence of statements. The static analysis
proceeds as follows.

First, `e` is subject to static analysis. Let `T` be the static type of
`e`. Next, `S` is subject to static analysis where the reserved word `this`
is considered to have the type `T`, and `S` has access to `this`.

*That implies that `this` can have a different meaning inside and outside
an anonymous method, and it is also possible that `this` does not have a
meaning at all outside the anonymous method. Moreover, an anonymous method
can be nested inside another anonymous method, which will generally cause
`this` to have different meanings.*

During this analysis, a name `n` is resolved by a lexical lookup following
the existing rules. In particular, if no declaration whose basename is the
basename of `n` is found in an enclosing scope then the name is
treated as if it had been prepended by `this.`.

Consider the situation where lexical lookup finds a declaration whose
basename is the basename of `n`, and it occurs in the body scope of an
enclosing membered declaration *(a class, mixin, mixin class, enum,
extension type, or extension declaration)*, and it is an instance member
*(i.e., not `static`)*. In this situation, the name is again treated as if
it had been prepended by `this.`.

*This means that even in the case where the lexical lookup found an
instance member of an enclosing class, the resulting treatment is that the
search is considered to have found nothing, and the prepended `this.`
forces the name to be resolved as a member of the receiver of the innermost
anonymous method, not as a member of the enclosing class.*

Otherwise, when the lexical lookup found a declaration which is not an
instance member, the result obtained from the lexical lookup is used.

*For example:*

```dart
String x = 'global';
String z = 'shadowed global';

class A {
  static String y = 'static';
  String z = 'instance';
  void foo() {
    this.z; // OK, `this` is the current instance of `A`.
    z; // OK, treated as `this.z`.
    1.{
      this.isEven; // OK, because `this` is `1`.
      isEven; // Treated as `this.isEven`.
      x; // Top-level variable.
      y; // Static variable.
      z; // Extension member on `int`.
    }
  }
}

extension on int {
  String get z => 'extension';
}
```

*The result of the last lookup of `z` is the extension member. This is
because it cannot be the instance member of `A` (the enclosing `A` instance
is not the current meaning of `this`), and it cannot be the top-level
variable (because it is shadowed by `A.z`), so we find nothing and start
afresh with `this.z` where `this` is `1`.*

During the static analysis, the context type for `r` in each statement of
the form `return r;` that occurs in `S` and not inside another function
expression or anonymous method is the context type of the entire anonymous
method invocation.

The static type of the anonymous method invocation is computed from the
static types of the returned expressions, following the same rules as for
the return type inference on a synchronous non-generator function literal
with body `{ S }`.

#### Expression bodied anonymous methods

Consider an anonymous method invocation of the form `e1.=> e2` where `e1`
and `e2` are expressions. The static analysis proceeds as follows.

First, `e1` is subject to static analysis. Let `T` be the static type of
`e1`. Next, `e2` is subject to static analysis where the reserved word `this`
is considered to have the type `T`, and `e2` has access to `this`.

Lexical lookups proceed as described in the previous section.

The static type of the anonymous method invocation is the static type of
`e2`.

#### Block bodied anonymous methods with a parameter

Consider an anonymous method invocation of the form `e.(P) { S }` where `e`
is an expression, `S` is a sequence of statements, and `P` is a formal
parameter list.

A compile-time error occurs if `P` declares zero or more than one
parameters, or if the parameter is named or optional. Let `p` be the
single parameter which is declared by `P`.

Next, `e` is subject to static analysis. Let `T` be the static type of
`e`. If `p` has a type annotation `U`, a compile-time error occurs if `T`
is not assignable to `U`. If `p` has no type annotation then the declared
type of `p` is `T`, otherwise it is said type annotation `U`.

Next, `S` is subject to static analysis in a scope where `p` is bound to
its declared type, and the enclosing scope is the current scope for the
anonymous method invocation as a whole.

During the static analysis, the context type for `r` in each statement of
the form `return r;` that occurs in `S` and not inside another function
expression or anonymous method is the context type of the entire anonymous
method invocation.

The static type of the anonymous method invocation is computed from the
static types of the returned expressions, following the same rules as for
the return type inference on a synchronous non-generator function literal
with body `{ S }`.

#### Expression bodied anonymous methods with a parameter

Consider an anonymous method invocation of the form `e1.(P) => e2` where
`e1` and `e2` are expressions, and `P` is a formal parameter list.

A compile-time error occurs if `P` declares zero or more than one
parameters, or if the parameter is named or optional. Let `p` be the
single parameter which is declared by `P`.

First, `e1` is subject to static analysis. Let `T` be the static type of
`e1`. If `p` has a type annotation `U`, a compile-time error occurs if `T`
is not assignable to `U`. If `p` has no type annotation then the declared
type of `p` is `T`, otherwise it is said type annotation `U`.

Next, `e2` is subject to static analysis in a scope where `p` is bound to
its declared type, and the enclosing scope is the current scope for the
anonymous method invocation as a whole.

During the static analysis, the context type schema for `e2` is the context
type of the entire anonymous method invocation.

The static type of the anonymous method invocation is the static type of
`e2`.

#### Conditional forms

Consider an anonymous method invocation of the form `e1?.{ S }`,
`e1?.=> e2`, `e1?.(P) { S }`, or `e1?.(P) => e2`.

The static analysis proceeds in the same way as with the corresponding form
without the `?`, except that the static type of `this` respectively the
declared type of the parameter `p` is `NonNull(T)`, where `T` is the static
type of the receiver `e1`.

Similarly, the static type of the anonymous method invocation as a whole is
`Nullable(R)` where `R` is the type which is computed from the return
statements in `S` respectively the static type of `e2`, following the rules
for the corresponding form without the `?`.

#### Cascaded forms

Consider an anonymous method invocation of one of the forms
`e1..{ S }`, `e1..=> e2`, `e1..(P) { S }`, `e1..(P) => e2`,
`e1?..{ S }`, `e1?..=> e2`, `e1?..(P) { S }`, or `e1?..(P) => e2`.

Cascades are specified to be treated as let expressions containing
member invocations, and the treatment of all the forms above follows from
this.

*For example, `e1..{ S }` where `e1` is a conditional expression is treated
as `let v = e1, _  = v.{ S } in v`, and `e1?..{ S }` is treated as
`let v = e1 in v != null ? (let _  = v.{ S } in v) : null`.*

### Dynamic semantics

Consider an anonymous method invocation of one of the forms
`e1.{ S }`, `e1.=> e2`, `e1.(P) { S }`, `e1.(P) => e2`,
`e1?.{ S }`, `e1?.=> e2`, `e1?.(P) { S }`, or `e1?.(P) => e2`.

First, `e1` is evaluated to an object `o`.

If the form has a `?` and `o` is null, the anonymous method invocation
evaluates to null.

Otherwise, a dynamic type error occurs if `o` has a run-time type which is
not a subtype of the declared type of the parameter. 

*By soundness, this kind of failure cannot occur when there is no
parameter, and it can only occur when the static type of `e1` is
`dynamic`.*

Next, if the form has an expression body `e2`, the expression `e2` is
evaluated to an object `o2`, and the anonymous method invocation evaluates
to `o2`. If the form has a block body `{ S }`, the statements `S` are
executed in a run-time scope where the parameter `p` is bound to `o` if
there is a parameter, and `this` is bound to `o` if there is no
parameter. If the execution of `S` completes normally, the value of the
anonymous method expression is null; if it completes returning a value `o2`
then the anonymous method expression evaluates to `o2`; if it throws then
the anonymous method expression throws, with the same exception and stack
trace.

The dynamic semantics of cascaded forms is determined by the fact that they
are treated as specific let expressions containing non-cascaded anonymous
methods.

### Migration

This feature does not introduce any breaking changes, hence there is no
need to consider breakage management.

### Revisions

- 1.0, 2025-Oct-31: Initial version of this feature specification.
