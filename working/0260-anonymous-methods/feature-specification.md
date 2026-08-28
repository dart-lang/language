# Anonymous Methods

Author: eernst@google.com<br>
Version: 1.0

## Introduction

An anonymous method is an expression that allows for an object (the
_receiver_) to be captured and made available to an expression or a block
of statements (the _body_).

Consider the following example:

```dart
void main() {
  final String halfDone, result;
  final sb = StringBuffer('Hello');
  sb.write(',');
  halfDone = sb.toString();
  sb.write(' ');
  sb.write('world!');
  result = sb.toString();
  print('Creating an important string: $halfDone then $result');
}
```

This example could have been expressed nicely as a cascade, except for the
fact that we need to do something which is not an invocation of a member of
`sb`:

```dart
void main() {
  final String halfDone, result;
  final sb = StringBuffer('Hello')
    ..write(',')
    // halfDone = sb.toString(); // Oops, can't do this!
    ..write(' ')
    ..write('world!');
  result = sb.toString();
  print('Creating an important string: $halfDone then $result');
}
```

Anonymous methods can be used to do this. First, an anonymous method with
an expression body (recognizable because it has an `=>`) can be used to
"inject" expressions into a cascade:

```dart
void main() {
  final String halfDone, result;
  final sb = StringBuffer('Hello')
    ..write(',')
    ..=> halfDone = toString()
    ..write(' ')
    ..write('world!')
    ..=> result = toString();
  print('Creating an important string: $halfDone then $result');
}
```

Next, we could also use a single anonymous method with a block body to do
all of it:

```dart
void main() => StringBuffer('Hello').{
  final String halfDone, result;
  write(',');
  halfDone = toString();
  write(' ');
  write('world!');
  result = toString();
  print('Creating an important string: $halfDone then $result');
};
```

A crucial point in both forms of anonymous method shown above is that they
evaluate the receiver (the expression before the `.`) and make it available
as the value of `this` in the body. As usual, members of `this` can be
accessed with an implicit receiver (for example, `toString()` will call the
`toString` method of the `StringBuffer` which is the value of `this`).

The code has now been reorganized because there is no need to have the
variable `sb` any more: All the work which is done with the string buffer
is now handled in the body of the anonymous method, and the two other
variables `halfDone` and `result` have been moved into the same body.

This illustrates that it is possible to do work in a single expression
which would currently be expressed using several statements, and it also
illustrates that all the work on the string buffer is gathered into a
single block, which can make the code easier to understand at a glance.

The semantics of an anonymous method of the form `e.{ S }` where `e` is an
expression and `S` is a sequence of statements is that `e` is evaluated to
an object `o` and then `S` is executed with `this` bound to `o`. Note that
it is possible to get `this.` prepended to an identifier which is not
otherwise in scope, just like `foo()` may mean `this.foo()` when it occurs
in an instance method of a class. (Hence the name 'anonymous _methods_'.)

In `e.{ S }`, `S` may contain return statements, and the returned value is
the value of the expression as a whole. For example:

```dart
void main() {
  StringBuffer('Hello').{
    write(', world!');
    return toString();
  }.{
    // `this` is the string returned by `toString()`.
    print(length); // Prints '13'.
    return length > 10;
  }.=> print('That was a ${this ? 'very' : '') long string!');
}
```

To avoid name clashes and preserve access to an enclosing `this`, it is
possible to give a name to the captured object. In this case there is no
change to the value of `this` (if any):

```dart
class A {
  void bar() {}
  void foo() {
    StringBuffer('Hello').(sb) {
      sb.write(', world!');
      this.bar(); // `this` refers to the current instance of `A`.
      return sb.toString();
    }.(s) {
      print(s.length);
      bar(); // An implicit `this` also refers to the current `A`.
      return s.length > 10;
    }.(cond) => print('That was a ${cond ? 'very' : '') long string!');
  }
}
```

A useful example is where we have an expression `e` whose value is used
multiple times:

```dart
void main() {
  // Current code could be like this:
  if (e.one && e.two && e.three) {...}
  
  // However, it may be slow or even wrong to execute `e` thrice.
  
  // With an anonymous method, we can do this:
  if (e.=> one && two && three) {...}
}
```

Another example which may be quite useful is that we can use an anonymous
method to do or not do something, based on whether a given expression has
the value null:

```dart
void main() {
  // Current approach:
  if (e case final x?) {
    foo(x);
  }
  
  // With anonymous methods we can do this:
  e?.=> foo(this);
}
```

Consider another example where we use the explicitly named form in order to
have access to more than one captured object in the same expression:

```dart
void main() {
  // Using anonymous methods.
  e1.foo(e2, e3?.(x) => e4?.(y) => bar(x, 42, y));
  
  // Expressing the same thing today, assuming that
  // we can change the evaluation order slightly.
  SomeType? arg;
  if (e3 case final x?) {
    if (e4 case final y?) {
      arg = bar(x, 42, y);
    }
  }
  e1.foo(e2, arg);
}
```

### Reading anonymous method invocations

In order to grasp the meaning of an expression that uses an anonymous method,
the following reading technique can be helpful:

To recognize an anonymous method at a glance, note that it has a period
immediately followed by a parameter list (look for `.(`, or a conditional
and/or cascaded form like `?.(`, `..(`, or `?..(`). Otherwise, it has a
period immediately followed by a function body (look for `.{` or `.=>`, or
a conditional/cascaded variant).

For an anonymous method invocation as a whole, it may be helpful to read it
as follows:

```dart
e.=> one && two && three
```

reads as "evaluate `e`; call it `this`; then evaluate `one && two && three`.

```dart
e?.=> foo(this)

```

reads as "evaluate `e`; bail out if null, otherwise call it `this`; then
evaluate `foo(this)`.

```dart
e3?.(x) => e4?.(y) => bar(x, 42, y)
```

reads as "evaluate `e3`; bail out if null, otherwise call it `x`; then
evaluate `e4`; bail out if null, otherwise call it `y`; then evaluate
`bar(x, 42, y)`".


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

#### Flow analysis

The flow analysis of an anonymous method invocation recognizes that the code in
the body of the anonymous method will be executed exactly once for the
unconditional variants, at most once for the conditional variants, and it
is recognized that the execution takes place immediately after the
evaluation of the receiver.

*This implies that an assignment to a local variable `v` in the body of an
anonymous method does not cause `v` to be considered non-promotable, which
makes anonymous methods more convenient to work with than function
literals.*

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

- 1.1, 2025-Nov-3: Add a section in the introduction about how to read the
  code, and a section in the proposal about flow analysis.

- 1.0, 2025-Oct-31: Initial version of this feature specification.
