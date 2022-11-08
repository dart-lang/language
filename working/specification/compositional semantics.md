# Dart Compositional Semantics

The Dart specification currently has individual specifications of `x += 1`, `x ??= 1`, `C.x += 1`, `C.x ??= 1`, `e.x += 1`, `e.x ??= 1`, `e[e2] += 1`, `e[e2] ??= 1`, `e?.x += 1`, `e?.x ??= 1`, `e?[e2] += 1`, `e?[e2] ??= 1`, `super.x += 1`, `super ??= 1`, `super[e2] += 1`, `super[e2] ??= 1`, `Ext(e).x += 1;`, `Ext(e).x ??= 1`, `Ext(e)[e2] += 1;`, `Ext(e)[e2] ??= 1`, etc. 

That is, for each kind of receiver *r*, we treat <Code>*r*.x</code> differently, and for each operation on </code>*r*.x</code> we specify it for each possible left-hand side. For *M* left-hand-sides and *N* operations, we need *M*&times;*N* sections in the specification. If we add `||=` and `&&=` assignment operators (as planned for years), we will need to duplicate a lot of cases.

This is an attempt to define a *compositional* semantics where we define an intermediate partially evaluated form for the *M* receivers, and abstract semantic ***read*** and ***write*** operations on those *M* forms, then define the individual *N* operations in terms of those abstract operations, for a total of *O*(*M*+*N*) cases in the specification. This allows new operations to be added more easily.



## Specification

A *Partial Evaluation Result* (or just *partial result*) is an abstract datatype representing a partial evaluation of an expression or term. The partial result can be used either as a receiver for a selector, or (for some of them) as the target of a read or write.

A partial result can have the following shapes, depending on what was partially evaluated.

* Receivers:
  * **OBJECT**(*object*)  — An expression with no special partially evaluated form
  * **SUPER**(*superclass*, *object*)  — The `super` keyword for accessing super-properties.
  * **EXTENSION**(*extensionDecl*, *typeArgs*?, *object*)  — The partial evaluation of something of the form `Ext<typeargs>(o)`
* Properties (potentially assignable if the property is writable):
  * **LOOKUP**(*namespace*, *identifier*)  — Something of the form <code>*ns*.*x*</code> or a <Code>*x*</code> in a lexical scope.
  * **INDEX**(*receiver*, *index*)  — Something of the form <Code>*e1*[e2]</code>
* Special value:
  * **PROPAGATING_NULL**  — Partial result of something which was omitted because of null-shortening.



The first three are called receivers, because they represent objects that can have instance members invoked on them.

We define the *lookup-type* and *receiver-object* of a receiver as follows:

* *lookupType*(**OBJECT**(*object*)) = the run-time type of *object*.
* *lookupType*(**SUPER**(*superclass*, *object*)) = *superclass*
* *lookupType*(**EXTENSION**(*extensionDecl*, *typeArgs*?, *object*)) = *extensionDecl*\<*typeArgs*>

and

* *receiverObject*(**OBJECT**(*object*)) = *object*
* *receiverObject*(**SUPER**(*superclass*, *object*)) = *object*
* *receiverObject*(**EXTENSION**(*extensionDecl*, *typeArgs*?, *object*)) = *object*



When we need to look up a name on a partial result, we first convert it to a *namespace*, which has one of the following forms:

* **INSTANCE**(*object*, *type*) — object is the instance being accessed, type is the type to perform look-up from.
  * Uses **INSTANCE**(o, runtime-type of o) for virtual lookup.
  * Uses **INSTANCE**(o, superclass type) for super lookups.
* **STATIC**(*declaration*) — class/mixin/enum/extension declaration with static members and/or constructors.
* **EXTENSION**(*extensionDecl*, *typeArgs*?, *object*)  — same as the receiver, its only job is to be used as a scope.
* **SCOPE**(*source scope*) – Any source scope, for statically resolved names.



A *source name* is one of:

* an identifier,
* an identifier followed by `=` (a setter name),
* an identifier followed by `.` and another identifier (a constructor name, the "unnamed constructor" uses the class name as name), or
* an operator name (`+`, `-`, `*`, `/`, `~/`, `%`, `~`, `<`, `>`, `<=`, `>=`, `<<`, `>>>` , `>>>`, `[]`, `[]=`, and `unary-`).

and we define the *basename*: *source name* &map; identifier functions as (where *x* and *y* range over identifiers):

* *basename*(*x*) = *x*
* *basename*(*x*=) = *x*
* *basename*(*x*.*y*) = *y*
* *basename*(`[]=`) = `[]`
* basename(*op*) = *op*  – for all operators other than `[]=`.  



To convert a partial result to a *namespace*, which can be used to look up *identifiers* we define a function, *toNamespace*: partial &map; namespace, as follows:

* *toNamespace*(**OBJECT**(*object*)) = **INSTANCE**(*object*, *runtime-type of object*)
* *toNamespace*(**SUPER**(*superclass*)) = **INSTANCE**(`this`, *superclass*).
* *toNamespace*(**EXTENSION**(*extensionDecl*, *typeArgs*?, *object*)) = **EXTENSION**(*extensionDecl*, *typeArgs*?, *object*)
* *toNamespace*(**LOOKUP**(*namespace*, *identifier*)): Look up *identifier* in *namespace* to see what it denotes.
  * If *identifier* denotes a prefix, the result is **SCOPE**(*S*) where *S* is the import scope denoted by that prefix.
  * If *identifier* denotes a class, mixin, enum, or extension declaration *D*, the result is **STATIC**(*D*)
  * If *identifier* denotes a type alias, and the type alias aliases a class, mixin or enum type, then let *D* be the declaration of that class, mixin or enum and the result is **STATIC**(*D*).
    * A type alias aliases a class, mixin or enum type if the RHS of the type alias is either a (possibly qualified) identifier denoting a class, mixin or enum declaration, or one such followed by type arguments. If the RHS is a type variable, the type alias doesn't alias a class, even though it might expand to a class type by instantiate to bounds. Whether a type alias aliases a class, mixin or enum, and which class, mixin or enum it is, is a fixed static property of the declaration, independent of the type arguments that apply to a generic type alias.
  * Otherwise evaluate id to a value *v* with runtime-type *R*, and the result is **INSTANCE**(*v*, *R*).
* *toNamespace*(**INDEX**(receiver, index)):
  * Let *o* = ***read***(**INDEX**(receiver, index)).
  * The result is *toNamespace*(**OBJECT**(*o*)).
* *toNamespace*(**PROPAGATING_NULL**) = **INSTANCE**(`null`, `Null`)



Partial evaluation of expressions and terms.

We define semantic functions:

***evalPartial***: \<expression> &map; partial result

***evalSelector***: partial result &times; \<selector> &map; partial result

***read***: partial result &map; object

***read***: namespace &times; identifier &map; object

***write***: partial result &times; object &map; unit

***write***: namespace &times; identifier &times; object &map; unit



The ***read*** function on partial results is defined as:

* ***read***(**OBJECT**(*o*)) = *o*
* ***read***(**SUPER**(\_, \_)): A run-time error occurs. (Actually, a compile-time error occurs before that ever happens, because `super` cannot be used in a position where its value as an object is needed, it's always a receiver of member invocations).
* ***read***(**EXTENSION**(\_, \_, \_)): A run-time error occurs. (Again, prevented from happening by an earlier compile-time error).
* ***read***(**LOOKUP**(*scope*, *identifier*)) = ***read***(*scope*, *identifier*)
* ***read***(**INDEX**(*receiver*, *index*)):
  * Invoke the `[]` operator method on *receiver* with *index* as a single positional parameter.
  * The result of ***read*** is the return value of that call.
* ***read***(**PROPAGATING_NULL**) = `null`.

and on scopes and names as:

* ***read***(**INSTANCE**(*object*, *type*), *identifier*):
  * Let *d* be the concrete instance member declared or inherited by *type* with name *identifier*.
  * If no such *d* exists, invoke the `noSuchMethod` method of *object* with an invocation object representing a "get" operation with a member-name being the `Symbol` representing *identifier*. The result of that call is the result of ***read***. (This can only happen for dynamic invocations, otherwise static checks would have prevented us from reaching here).
  * If *d* is a method declaration, let *v* be the *tear-off* of that method with `this` bound to *object*.
  * If *d* is a getter, invoke *d* with `this` bound to *object*, and let *v* be the return value of that invocation.
  * Then ***read*** evaluates to *v*.

* ***read***(**STATIC**(*declaration*), *identifier*):

  * Let *d* be the *static* declaration in *declaration* with name *identifier*, or a constructor with *basename* *identifier*.
  * If no such *d* exists, a run-time error occurs (a compile-time error would already have occurred).
  * If *d* is a constructor, a run-time error occurs (a compile-time error would already have occurred). *If we supported constructor tear-offs, this is where it would happen.*
  * If *d* is a function declaration, let *v* be the *tear-off* of that static method. (If *d* is a generic function and a context type requires it to be non-generic, this will be an instantiated tear-off).
  * If *d* is a getter, let *v* be the return value of invoking *d*.
  * The result of ***read*** is *v*.

* ***read***(**EXTENSION**(*extensionDecl*, *typeArgs?*, *object*), *identifier*): 
  * Let *d* be the *instance* declaration declared or inherited by *extensionDecl* with name *identifier*.
  * If no such *d* exists, a run-time error occurs (a compile-time error would already have occurred).
  * If *d* is a function declaration, let *v* be the *tear-off* of that function declaration with the extension type arguments bound to *typeArgs* (if available) and `this` bound to *object*.
  * If *d* is a getter, let *v* be the result of invoking that getter with the extension type arguments bound to *typeArgs* (if available) and *this* bound to *object*.
  * The result of ***read*** is *v*.

* ***read***(**SCOPE**(*scope*), *identifier*): *(The scope may be lexical scope or an import "prefix" scope. Any declaration can occur in a lexical scope)*
  * Let *d* be the declaration named *identifier* in the scope *scope*.
  * If no such *d* exists, a run-time error occurs (a compile-time error would already have occurred).
  * If *d* is a prefix import scope or an extension declaration, a run-time error occurs (a compile-time error would already have occurred).
  * If *d* is a class, mixin or enum declaration, let *v* be a `Type` object representing the type of the declared class, mixin or enum, instantiated to bounds if *d* is generic.
  * If *d* is a type alias, let *v* be a `Type` object representing the aliased type, with the type arguments of *d* being instantiated to bounds if *d* is generic.
  * If *d* is a type variable, let *v* be a `Type` object representing the type bound to the type variable.
  * If *d* is a static, top-level or local function declaration, let *v* be the *tear-off* of that function in *scope* (the *scope* only matters for tear-offs of local functions, the tear-offs of top-level or static functions are compile-time constants).
  * If *d* is a static or top-level getter, invoke the getter and let let *v* be the returned value.
  * If *d* is a local variable (including function parameters), let *v* be the result of reading the variable. *(This is usually the value currently bound to the variable, but may throw for uninitialized late variables).*
  * If *d* is a non-extension instance function declaration, let *v* be the *tear-off* of that function closing over the current `this` value and any class/mixin type parameter values. (It's a compile-time error if this occurs outside of an instance member body, which includes late instance variable initializers and generative constructor bodies).
  * If *d* is a non-extension instance getter declaration, invoke *d* with `this` bound to the current `this` value and let *v* be the returned value. (It's a compile-time error if this occurs outside of an instance member body, which includes late instance variable initializers and generative constructor bodies).
  * If *d* is an extension instance method declaration, let *v* be the *tear-off* of that function closing over the current `this` value and extension type parameter values. (It's a compile-time error if this occurs outside of an extension instance member body).
  * If *d* is an extension instance getter declaration, invoke *d* with `this` bound to the current `this` value and let *v* be the returned value. (It's a compile-time error if this occurs outside of an extension instance member body).
  * The result of the ***read*** is *v*.



The ***write*** function on partial results (***write***: partial result &times; object &map; unit) is defined as:

* ***write***(**OBJECT**(*o*), *value*):
* ***write***(**SUPER**(\_, \_), *value*):
* ***write***(**EXTENSION**(\_, \_, \_)): 
* ***write***(**PROPAGATING_NULL**): 
  * A run-time error occurs. (This is prevented from happening by an earlier compile-time error).
* ***write***(**LOOKUP**(*scope*, *identifier*), *value*):
  * If *identifier* is not a single identifier, it's a compile-time error.
  * Evaluate ***write***(*scope*, *identifier*, *value*).
* ***write***(**INDEX**(*receiver*, *index*), *value*):
  * Invoke the `[]=` operator method on *receiver* with *index* and *value* as positional parameters.

and on scopes and names (***write***: *nameSpace* &times; *identifier* &times; *object*  &map; unit) as:

* ***write***(**INSTANCE**(*object*, *type*), *identifier*, *value*):
  * Look up *identifier*= on *type* to find a setter declaration, *d*.
  * If no member with that name is found, invoke the `noSuchMethod` method of *object* with an invocation object representing a "set" operation with a member-name being the `Symbol` representing *identifier*= and *value* as a single positional argument. The result of that call is the result of ***write***.
* ***write***(**STATIC**(*declaration*), *identifier*, *value*):
  * Let *d* be the *static* setter declaration in *declaration* with name *identifier*=.
  * If no such *d* exists, a run-time error occurs (a compile-time error would already have occurred).
  * Invoke *d* with *value* as a single positional argument.
* ***write***(**EXTENSION**(*extensionDecl*, *typeArgs?*, *object*), *identifier*, *value*): 
  * Let *d* be the *instance* setter declaration in *extensionDecl* with name *identifier*=.
  * If no such *d* exists, a run-time error occurs (a compile-time error would already have occurred).
  * Invoking *d* with the extension type arguments bound to *typeArgs* (if available), *this* bound to *object*, and with *value* as a single positional argument.
* ***write***(**SCOPE**(*scope*), *identifier*, *value*): *(The scope may be lexical scope or an import "prefix" scope. Any declaration can occur in a lexical scope)*
  * Let *d* be the declaration named *identifier*= in the scope *scope*.
  * If no such *d* exists (not a *setter*), which can happen for local variables which are not defined in terms of a getter and a setter:
    * let *d* be the declaration named *identifier* in the scope *scope*.
    * If *d* is not a local variable variable declaration, or it's a final non-late local variable, or it's a final late local variable declaration with an initializer, a run-time error occurs.
    * Otherwise assign *value* to the variable declared by *d*. (This may throw for a late final variable with no initializer which has already been initialized).
    * Then ***write*** completes.
  * Otherwise *d* is a setter declaration.
  * If *d* is a static or top-level setter, invoke the setter with *value* as a single positional argument.
  * If *d* is a non-extension instance setter declaration, invoke *d* with `this` bound to the current `this` value, and with *value* as a single positional argument.
  * If *d* is an extension instance setter declaration, invoke *d* with `this` bound to the current `this` value and *value* as a single positional argument. (It's a compile-time error if this occurs outside of an extension instance member body).



We now define *partial evaluation* for a subset of expressions and selectors.

In general, if nothing else is specified, partial evaluation of an expression is performed by evaluating the expression to a value *v* and then partially evaluating to the partial result **OBJECT**(*v*). Those expressions do not have a special partial form.

In the cases where we do specify a partial evaluation below, this replaces the current evaluation rules for the expression, and evaluation to a value is performed by partially evaluating the expression to a partial result *r*, then evaluating to the result of ***read***(*r*).



The relevant grammar rules are:

```ebnf
<expression> ::= <assignableExpression> <assignmentOperator> <expression>
  \alt <conditionalExpression>
  \alt <cascade>
  \alt <throwExpression>

<assignmentOperator> ::= `='
  \alt <compoundAssignmentOperator>

<compoundAssignmentOperator> ::= `*='
  \alt `/='
  \alt `~/='
  \alt `\%='
  \alt `+='
  \alt `-='
  \alt `\ltlt='
  \alt `\gtgtgt='
  \alt `\gtgt='
  \alt `\&='
  \alt `^='
  \alt `|='
  \alt `??='

<primary> ::= <thisExpression>
  \alt \SUPER{} <unconditionalAssignableSelector>
  \alt <functionExpression>
  \alt <literal>
  \alt <identifier>
  \alt <newExpression>
  \alt <constObjectExpression>
  \alt <constructorInvocation>
  \alt `(' <expression> `)'

<postfixExpression> ::= <assignableExpression> <postfixOperator>
  \alt <primary> <selector>*

<postfixOperator> ::= <incrementOperator>

<constructorInvocation> ::= \gnewline{}
  <typeName> <typeArguments> `.' <identifier> <arguments>

<selector> ::= `!'
  \alt <assignableSelector>
  \alt <argumentPart>

<argumentPart> ::=
  <typeArguments>? <arguments>

<incrementOperator> ::= `++'
  \alt `-\mbox-'

<assignableExpression> ::= <primary> <assignableSelectorPart>
  \alt \SUPER{} <unconditionalAssignableSelector>
  \alt <identifier>

<assignableSelectorPart> ::= <selector>* <assignableSelector>

<unconditionalAssignableSelector> ::= `[' <expression> `]'
  \alt `.' <identifier>

<assignableSelector> ::= <unconditionalAssignableSelector>
  \alt `?.' <identifier>
  \alt `?' `[' <expression> `]'
  
<unaryExpression> ::= <prefixOperator> <unaryExpression>
  \alt <awaitExpression>
  \alt <postfixExpression>
  \alt (<minusOperator> | <tildeOperator>) \SUPER{}
  \alt <incrementOperator> <assignableExpression>

<prefixOperator> ::= <minusOperator>
  \alt <negationOperator>
  \alt <tildeOperator>

<multiplicativeExpression> ::= \gnewline{}
  <unaryExpression> (<multiplicativeOperator> <unaryExpression>)*
  \alt \SUPER{} (<multiplicativeOperator> <unaryExpression>)+

<multiplicativeExpression> ::= \gnewline{}
  <unaryExpression> (<multiplicativeOperator> <unaryExpression>)*
  \alt \SUPER{} (<multiplicativeOperator> <unaryExpression>)+

<multiplicativeOperator> ::= `*'
  \alt `/'
  \alt `\%'
  \alt `~/'
```



We defined partial evaluation of a selector relative to a partially evaluated receiver as follows:

For *s* a `<selector>` and *p* a partial result we defined ***evalSelector***(*p*, *s*) as:

* if *s* is `!`: 

  * Let *v* = ***read***(p)
  * If *v* is `null`, a run-time type error occurs.
  * Otherwise the result is OBJECT**(*v*)

* if *s* is <code>x</code> or <code>'?' *x*</code> with *x* an identifier:

  * Let *S* be *toNamespace*(*p*).
  * If the leading `'?'` is present and either 
    * *S* is **INSTANCE**(*object*, *type*) and *object* is `null`, or
    * *S* is **EXTENSION**(*decl*, *typeArgs*, *object*) and *object* is `null`,
  * then evaluate to **PROPAGATING_NULL**.
  * Otherwise the result is **LOOKUP**(*S*, *x*).

* if *s* is <code>'[' *e* ']'</code> or <code>'?' '[' *e* ']'</code> with *e* an expression:

  * *The *p* is one of **OBJECT**, **SUPER** or **EXTENSION** because those are the only scopes capable of declaring `[]` and `[]=` operators, and we would statically have rejected the program earlier otherwise.)*
  * If the leading `'?'` is present and either 
    * *p* is **OBJECT**(*object*) and *object* is `null`, or
    * *p* is **EXTENSION**(*decl*, *typeArgs*, *object*) and *object* is `null`,
  * then the selector partially evaluates to **PROPAGATING_NULL**.
  * Otherwise evaluate *e* to a value *i*.
  * The result is **INDEX**(*p*, *i*).

* If *s* is an `<argumentPart>`, with argument list *arguments*, possibly including type arguments:

  * If *p* is **OBJECT**(*o*), **SUPER**(*t*, *o*) or **EXTENSION**(*decl*, *typeArgs*?, *o*), then:
    * let *S* be *toNamespace*(*p*).
    * Let *f* be the result of looking up `call` in *S*.
    * If *f* is not an instance method, a run-time error occurs. (Implicit extension invocations are assumed to have been made explicit in a prior step).
    * Otherwise evaluate *arguments* to an argument list *l*.
    * Invoke *f* with *l* as arguments (including type arguments if applicable, instantiate *f* to bounds if generic and *arguments* contains no type arguments) and with *o* as `this` value. Let *r* be the return value.
    * The result is **OBJECT**(*r*).
  * If *p* is **LOOKUP**(*scope*, *name*):
    * Let *d* be the result of looking up *name* in *d*
    * If *d* is an extension declaration, then:
      * evaluate *arguments* to an argument list *a*, which must have a single positional argument, and type arguments *ta* (possibly absent).
      * If *a* does not have a single positional argument, *o*, then a run-time error arises.
      * The result is **EXTENSION**(*declaration*, *ta*, *a*).
    * If *d* is a function declaration:
      * evaluate *arguments* to an argument list *a* and type arguments *ta* (possibly absent).
      * Invoke *d* with *a* as arguments and *ta* as type arguments, and let *v* be the returned value.
      * The result is **OBJECT**(*v*).
    * If *d* is a constructor declaration:
      * Invoke the constructor as if by a `new`-prefixed object creation expression and let *v* be the created object.
      * The result is **OBJECT**(*v*)
    * Otherwise:
      * Let *v* be ***read***(*p*).
      * The result is ***evaluateSelector***(**OBJECT**(*v*), *arguments*).
  * If *p* is **INDEX**(*receiver*, *index*):
    * Let *v* be ***read***(*p*).
    * The result is ***evaluateSelector***(**OBJECT**(*v*), *arguments*).
  * If *p* is **PROPAGATING_NULL** the result is **PROPAGATING_NULL**.

  

For a `<selector>` sequence of the form `<selector>*`, we define:


  ***evalSelectors***: partial result &times; selector* &map; partial result

  as follows:

  * ***evalSelectors***(*p*, *empty*) = *p*
  * ***evalSelectors***(*p*, *first* *rest*?) where *first* is a `<selector>` and *rest* is a `<selector>*` sequence.
    * If *p* is **PROPAGATING_NULL**, the result is **PROPAGATING_NULL**.
    * let *q* be ***evalSelector***(*p*, *first*)
    * If *rest* is empty, the result is *q*.
    * Otherwise the result is ***evalSelectors***(*q*, *rest*).

 

The function ***evalPartial*** implements partial evaluation of expressions to partial results. As mentioned above, unless otherwise stated the behavior of ***evalPartial***(*e*), where *e* is an expression, is the same as first evaluating *e* to an object *o*, and then returning **OBJECT**(*o*). The exceptions are listed below, andit is *always* the case that evaluating an expression *e* to a value *v* is equivalent to partially evaluating *e* to a partial result *r* and then letting *v* be the result of ***read***(*r*). (Basically ***eval*** = ***read*** ∘ ***partialEval***, if we had an ***eval*** function.)

For *e* a `<primary> `we defined ***evalPartial***(*e*) specially in two cases:

* If *e* is an `<identifier>` *x*: 
  * The result is **LOOKUP**(**SCOPE**(*L*), *x*) where *L* is the surrounding lexical scope.
* If *e* is `'super' <unconditionalAssignableSelector>` with selector *s*: 
  * The result is ***evalSelector***(**SUPER**(superclass of surrounding class, `this`), *s*).



For a  `<postfixExpression>` *e* we define ***evalPartial***(*e*) as:

  * If *e* is `<primary> <selector>*` with primary *r* and selectors *s*:

    * let *p* = ***evalPartial***(r) (as defined for a primary above).
    * if *s* is empty, the result is *p*.
    * Otherwise the result is ***evalSelectors***(*p*, *s*).

  * If *e* is `<assignableExpression> <incrementOperator>` with assignable expression *a*:

    * Let *p* = ***evalPartial***(*a*).
    * If *p* is **PROPAGATING_NULL** the result is **OBJECT**(`null`)
    * If *p* is a receiver (an **OBJECT**, **SUPER** or **EXTENSION**) value, a run-time error occurs. (Static checking should prevent this.)
    * Otherwise (*p* is either **LOOKUP**(*namespace*, *name*) or **INDEX**(*object*, *index*)):
      * Let *o* = ***read***(p)
      * Invoke the `+` method or `-` method (depending on whether the increment operator is `++` or `--`) on *o* with the integer `1` as a single positional argument and let *r* be the return value.
      * Evaluate ***write***(p, r).
      * The result is **OBJECT**(o).



For an `<assignableExpression>` *e* we define ***evalPartial***(*e*) as:

* If *e* is `<primary> <assingableSelectorPart>` with primary *p* and selector part *s*:
  * Let *r* be ***evalPartial***(p).
  * Let *q* be ***evalSelectors***(*r*, *s*).
  * The result is *q*.
* If *e* is `'super' <unconditionalAssignableSelector>` with unconditional assignable selector *s*:
  * The result is ***evalSelector***(SUPER(*U*, `this`), *s*) where *U* is the superclass of the surrounding class.
* If *e* is `<identifier>` with identifier *x*:
  * The result is **LOOKUP**(**SCOPE**(lexical scope), *x*).



For a `<unaryExpression>` *e* we define ***evalPartial***(*e*) for some cases as:

* If *e* is `<incrementOperator> <assignableExpression>` with assignable expression *a*:
  * Let *p* = ***evalPartial***(*a*).
  * If *p* is **PROPAGATING_NULL** the result is **OBJECT**(`null`)
  * If *p* is an **OBJECT**, **SUPER** or **EXTENSION** value, a run-time error occurs. (Static checking should prevent this.)
  * If *p* is **LOOKUP**(*scope*, *name*) or **INDEX**(*object*, *index*) then:
    * Let *o* = ***read***(p)
    * Invoke the `+` method or `-` method (depending on whether the increment operator is `++` or `--`) on *o* with the integer `1` as a single positional argument and let *r* be the return value.
    * Evaluate ***write***(p, r).
    * The result is **OBJECT**(r).
* If *e* is `<prefixOperator> <unaryExpression>` with operator *op* and unary expression *u*:
  * If *op* is `!`:
    * Evaluate *u* to a value *v*.
    * If *v* is not an instance of `bool`, a run-time error occurs.
    * If *v* is `true`, the result is **OBJECT**(`false`), and
    * If *v* is `false`, the result is **OBJECT**(`true`).
  * If `op` is `-`, let *opName* be `unary-`, otherwise let *opName* be *op*.
  * let *p* = ***evalPartial***(*u*).
  * If *p* is not an **OBJECT**, **SUPER** or **EXTENSION**, let *p* be **OBJECT**(***read***(*p*)).
  * Let *T* be *lookupType*(*p*) and *o* be *receiverObject*(*p*).
  * Let *d* be declaration of the operator named *opName* in the type of *T*.
  * If there is no such declaration:
    * If *S* is an **EXTENSION**, a run-time error occurs.
    * Otherwise let *n* be the declaration of `noSuchMethod` in the type of *T*.
    * Invoke *n* with an invocation representing a method operator with member name *opName*, no arguments, and let *v* be the returned value.
  * Otherwise invoke *d* with `this` bound to *o* and let *v* be the returned value.
  * The result is **OBJECT**(*v*).
* If *e* is a `<postfixExpression>` *f*:
  * The result is ***evalPartial***(*f*).



For binary operations in general, we define:

***evalOperators***: partial result &times; (\<operator> &times; \<expression>)* &map; partial result

as:

***evalOperators***(*p*, empty) = *p*

***evalOperators***(*p*, (*op*, *u*) rest?):

* If *p* is not a receiver (one of **OBJECT**, **SUPER** or **EXTENSION**, let *p* be **OBJECT**(***read***(*p*)).
* Evaluate *u* to a value *a*.
* Let *T* be *lookupType*(*p*) and let *o* be *receiverObject*(*p*).
* Let *d* be the implementation of *op* in *T*.
* If no such *d* exists:
  * If *p* is an **EXTENSION**, a run-time error occurs.
  * Otherwise let *n* be the `noSuchMethod` implementation in *T*.
  * Invoke *n* with an `Invocation` object representing a method invocation with member name *op*, *a* as a single positional argument, and with `this` bound to *o*. Let *v* be the return value of that invocation.
* Otherwise invoke *d* with *a* as a single positional argument and `this` bound to *o*. Let *v* be the return value of that invocation.
* Then ***evalOperators*** evaluates to **OBJECT**(*v*).



With that we can define ***evalPartial*** on a multiplicative expression *e*:

* If *e* is `<unaryExpression> (<multiplicativeOperator> <unaryExpression>)*` with unary expression *u* and (possibly empty) multiplications *m*:
  * Let *p* be ***evalPartial***(u).
  * The result is ***evalOperators***(*p*, *m*).
* If *e* is `\SUPER{} (<multiplciativeOperator> <unaryExpression>)}` with unary expression *u* and (non-empty) multiplications *m*:
  * Let *p* be **SUPER**(superclass of current class, `this`).
  * The result is ***evalOperators***(*p*, *m*).

*We can define all the other binary operators in the same way, except for the short-circuit operators `??`, `&&` and `||`, which all evaluate their operands to values, and therefore cannot have `super` or an extension application as receiver. They therefore need no change.*



Evaluation of an`<expression>` *e* of the form `<assignableExpression>  <assignmentOperator> <expression>, with assignable expression *a*, assignment operator *aop* and assigned expression *r*, proceeds as follows:

* Let *p* be ***evalPartial***(*a*)
* If *p* is **PROPAGATING_NULL**, the result of evaluation of *e* is **OBJECT**(`null`).
* Otherwise:
* If *aop* is `=`:
  * Evaluate *r* to a value *v*.
* If *aop* is `??=`:
  * Let *u* be ***read***(*p*).
  * If *u* is the value `null`, evaluate *r* to a value *o* and let *v* be *o*,
  * Otherwise let *v* be *u*.
* Otherwise, *aop* is *op*= for some user-definable operator *op*.
  * Let *u* be ***read***(*p*).
  * Evaluate *r* to a value *o*.
  * Invoke the operator *op* on *u* with *o* as a single positional parameter. Let *v* be the return value of this invocation.
* Then do ***write***(*p*, *v*).
* The result of evaluation of *e* is **OBJECT**(*v*).

