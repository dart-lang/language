# Dart Constructor Tear-offs

Dart allows you to tear off (aka. closurize) methods instead of just calling them. It does not allow you to tear off *constructors*, even though they are just as callable as methods (and for factory methods, the distinction is mainly philosophical).

It's an annoying shortcoming. We want to allow constructors to be torn off, and users have requested it repeatedly ([#216](https://github.com/dart-lang/language/issues/216), [#1429](https://github.com/dart-lang/language/issues/1429)).

This is a proposal for constructor tear-offs which does not introduce any new syntax, but which is therefore somewhat limited. There is also a discussion of possible extensions to the feature.

## Proposal

If an expression *e* denotes a constructor and is evaluated for its function value, it's equivalent to <code>(*params*) => *e*(*args*)</code>, where *params* are the parameters of that constructor and *args* is the argument list passing those parameters on directly. This is how we otherwise handle tear-offs, and constructors are no different, they just have a few complications.

A term of the form <code>*qualified*.*name*</code> which denotes a constructor (<code>*qualified*</code> denotes a class *C* with a named constructor <code>*C*.*name*</code>) is currently not a valid stand-alone expression. The term is allowed by the expression grammar, but it has no semantics except when immediately invoked. This proposal allows it as an expression evaluated for its value, and gives it static and run-time semantics.

The expression will be equivalent to <code>(*params*) => *qualified*.*name*(*args*)</code>.

An expression of the form `qualified` which denotes a class *is* currently a valid expression evaluating to a `Type` object. This proposal changes its meaning in certain contexts.

If such an expression occurs with a context type which is `Function`  or a function type (in which case the program would currently have a compile-time type error), and the denoted class has an unnamed constructor, then the expression will instead be equivalent to <code>(*params*) => *qualified*(*args*)</code>. *If the class has no unnamed constructor, compilers may want to make `Function x = C;` report that "C has no unnamed constructor" rather than "Type is not assignable to Function", but the language only cares that it's still a compile-time error*.

If *C* is not generic, the function expression is a compile-time constant expression and is canonicalized *just like a non-generic static function tear-off*. 

If *C* is generic, then the type arguments to `qualified` are inferred as normal for such function literals. _If the context type of the tear-off expression is a function type, then the type inference of <code>*qualified*.*name*(*args*)</code> or <code>*qualified*(*args*)</code> happens with that function type's return type as the instance creation's context type. If that's not sufficient to infer type arguments for *qualified*, or if there is no context type, the type arguments are found by instantiate-to-bounds of the type parameters of *C*._ Such a tear-off is not a compile-time constant. If the two arguments inferred for two different tear-offs of the same constructor are "the same", then the two resulting functions are *equal* (according to `==`), and it's unspecified whether they are *identical*, *just as for an instantiated generic static function tear-off*.

The static type of the tear-off is the same as the static type of the equivalent function literal, after inference of type arguments if necessary.

This is a *minimal* proposal in that it is *non breaking* and introduces no new *syntax*, it only assigns new semantics to terms that are currently allowed by the grammar, but would otherwise be compile-time errors.

### Consequences

This proposal is deliberately non-breaking and minimally intrusive (no new grammar rules).

That means that it won't change the meaning of an expression which currently evaluates to a `Type` object. That also means that absent of any context type hint, a reference to a class will keep evaluating to a type object, and `var makeSymbol = Symbol;` is not enough to tear off the `Symbol` constructor. You need to write at least `Function makeSymbol = Symbol;`, which then doesn't get type inference for the variable, or `Symbol Function(String) makeSymbol = Symbol;` to get the full type. There is no syntax for *explicitly* tearing off an unnamed constructor. (Also `var makeSymbol = Symbol as Function` won't work because `as` does not introduce a context type. It would be nice if we could change that.)

In most cases, the tear-off does happen in a context where a function type is already expected, and the unnamed tear-off will work perfectly for that.

There is no way to abstract over the type parameters of the class. We could make `Set<T> Function<T>() makeSet = HashSet;` tear off as `<T>() => HashSet<T>()`, providing a generic function matching the generic class. *However*, we also want to introduce *generic constructors*, say `Map.fromIterable<T>(Iterable<T> elements, K key(T element), V value(T element))`, and tearing off that should create a generic function. Making generic tear-offs work with the *class* type parameters could interfere with this later feature. Not doing so is still a choice with consequence, we can't just allow it later if we change our minds. If `var makeFilled = List.filled;` is not generic now, it would be a breaking change to make it generic later.

## Alternatives

### Explicit unnamed constructor tear-off

Because a plain class reference can be either a `Type` literal or an unnamed constructor tear-off, we have to have a default behavior when there is no context clue. That makes context clues important. If we had a separate syntax, we wouldn't *need* to rely on context clues.

Syntax examples:

*  `var x = new Symbol;`
*  `var x = Symbol.new;`
*  `var x = (Symbol.);`

All three uses syntax which is currently not valid. I would personally recommend the first one. It would still allow you to *omit* the `new` when it's allowed by the context type (and we'd probably allow `new qualified.name` as a named constructor tear-off as well). You can omit `new` in other cases, so there is precedence for that. Also `[new Symbol]` is one way to refer to a constructor in DartDoc.

See also [#691 - Uniform tear-off syntax](https://github.com/dart-lang/language/issues/691).

### Explicitly instantiated generics

We can only instantiate generic classes based on type inference. That means that `var makeIntList = List.filled;` won't work, you have to write out the type as  `List<int> Function(int args, int value) = List.filled;`.

If we instead allow you to write `var makeIntList = List<int>.filled;`, then you would not need the context type. 

This would be *new syntax*. It's not currently allowed by the grammar. It's fairly uncontroversial, but it blurs the lines between constructor invocations and selector chains, and we might need to rewrite the specification around those.

Then we would probably *also* want to allow `Set<int>` as a constructor literal. If we allow *that*, then we can also allow `Set<int>` as a *type* literal, which is a very old request. See also [#123 - Allow type instantiation as expression](https://github.com/dart-lang/language/issues/123).
