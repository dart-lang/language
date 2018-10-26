# Spread Collections

Author: rnystrom@google.com

Allow the `...` in list and map literals to insert multiple elements into a
collection.

## Motivation

List and map literals are excellent when you want to create a new collection out
of individual items. But, often some of those existing items are already stored
in another collection.

Code like this is pretty common:

```dart
var args = testArgs.toList()
  ..add('--packages=${PackageMap.globalPackagesPath}')
  ..add('-rexpanded')
  ..addAll(filePaths);
```

The cascade operator does help somewhat, but it's still pretty cumbersome. It
feels imperative when it should be declarative. The user wants to say *what* the
list is, but they are forced to write how it should be *built*, one step at a
time.

With this proposal, it becomes:

```dart
var args = [
  ...testArgs,
  '--packages=${PackageMap.globalPackagesPath}',
  '-rexpanded',
  ...filePaths
];
```

The `...` syntax evaluates the following expression and unpacks the resulting
values and inserts them into the new list at that position.

Use cases for this also occur in Flutter UI code, like:

```dart
Widget build(BuildContext context) {
  return CupertinoPageScaffold(
    child: ListView(
      children: [
        Tab2Header(),
      ]..addAll(buildTab2Conversation()),
    ),
  );
}
```

That becomes:

```dart
Widget build(BuildContext context) {
  return CupertinoPageScaffold(
    child: ListView(
      children: [
        Tab2Header(),
        ...buildTab2Conversation(),
      ],
    ),
  );
}
```

Note now how the `]` hangs cleanly at the end instead of being buried by the
trailing `..addAll()`.

The problem is less common when working with maps, but you do sometimes see code
like:

```dart
var params = {
  "userId": 123,
  "timeout": 300,
}..addAll(uri.queryParameters);
```

With this proposal, it becomes:

```dart
var params = {
  "userId": 123,
  "timeout": 300,
  ...uri.queryParameters
};
```

In this case, the `...` takes an expression that yields a map and inserts all of
that map's entries into the new map.

### Type inference

A non-obvious extra advantage to this syntax is that it makes type inference
more powerful. By moving elements out of trailing calls to `addAll()` and into
the collection literal itself, we have more context available for bottom-up
inference.

Code like this is fairly common:

```dart
var containingParts = <String>[]..addAll(info.outputUnit.imports)..add('main');
```

The `<String>` is necessary because otherwise we can't infer a type for the
list. With spread, the elements let us infer it:

```dart
var containingParts = [
  ...info.outputUnit.imports,
  'main'
];
```

### Null-aware spread

In the above example, what happens if `uri.queryParameters` returns null? We
could treat that as a runtime error, or silently treat null like an empty
collection.

The latter has some convenience appeal, but clashes with the rest of the
language where null is never silently ignored. A null if statement condition
expression causes an exception instead of being implicitly treated as false as
in most other languages.

Most of the time, if you have a null in a place you don't expect, the sooner you
can find out, the better. Even JavaScript does not silently ignore null in
spreads. So I don't think we either. But, when looking through a corpus for
places where a spread argument would be useful, I found a number of examples
like:

```dart
var command = [
  engineDartPath,
  '--target=flutter',
];
if (extraFrontEndOptions != null) {
  command.addAll(extraFrontEndOptions);
}
command.add(mainPath);
```

To handle these gracefully, we support a `...?` "null-aware spread" operator. In
cases where the spread expression evaluates to null, that expands to an empty
collection instead of throwing a runtime expression.

That turns the example to:

```dart
var command = [
  engineDartPath,
  '--target=flutter',
  ...?extraFrontEndOptions,
  mainPath
];
```

More complex conditional expressions than simple null checks come up often too,
but those are out of scope for this proposal.

## Syntax

We extend the list grammar to allow *spread elements* in addition to regular
elements:

```
listLiteral:
  const? typeArguments? '[' listElementList? ']'
  ;

listElementList:
  listElement ( ',' listElement )* ','?
  ;

listElement:
  expression |
  ( '...' | '...?' ) expression
  ;
```

Instead of `expressionList`, this uses a new `listElementList` rule since
`expressionList` is used elsewhere in the grammar where spreads aren't allowed.
Each element in a list is either a normal expression or a *spread element*. If
the spread element starts with `...?`, it's a *null-aware spread element*.

The changes for map literals are similar:

```
mapLiteral:
  const? typeArguments? '{' mapLiteralEntryList? '}' ;

mapLiteralEntryList:
  mapLiteralEntry ( ',' mapLiteralEntry )* ','?
  ;

mapLiteralEntry:
  expression ':' expression |
  ( '...' | '...?' ) expression
  ;
```

Note that a *spread entry* for a map is an expression, not a key/value pair.
Similar to lists, a spread entry that starts with `...?` is a *null-aware spread
entry*.

## Static Semantics

Since the spread is unpacked and its individual elements added to the containing
collection, we don't require the spread expression *itself* to be assignable to
the collection's type. For example, this is allowed:

```dart
var numbers = <num>[1, 2, 3];
var ints = <int>[...numbers];
```

This works because the individual elements in `numbers` do happen to have the
right type even though the list that contains them does not. As long as the
spread object is "spreadable"&mdash;it implements Iterable&mdash; there is no
static error. This is true even if the object being spread is a user-defined
class that implements Iterable but isn't even a subtype of List. For spreading
into map literals, we require the spread object to be a class that implements
Map, but not necessarily a subtype of the map being spread into.

It is a static error if:

*   A spread element in a list literal has a static type that is not assignable
    to `Iterable<Object>`.

*   If a list spread element's static type implements `Iterable<T>` for some `T`
    and `T` is not assignable to the element type of the list.

*   A spread element in a map literal has a static type that is not assignable
    to `Map<Object, Object>`.

*   If a map spread element's static type implements `Map<K, V>` for some `K`
    and `V` and `K` is not assignable to the key type of the map or `V` is not
    assignable to the value type of the map.

If implicit downcasts are disabled, then the "is assignable to" parts here
become strict subtype checks instead.

### Const spreads

Spread elements are not allowed in const lists or maps. Because the spread must
be imperatively unpacked, this could require arbitrary code to be executed at
compile time:

```dart
class InfiniteSequence implements Iterable<int> {
  const InfiniteSequence();

  Iterator<int> get iterator {
    return () sync* {
      var i = 0;
      while (true) yield i ++;
    }();
  }
}

const forever = [...InfiniteSequence()];
```

### Type inference

Inference propagates upwards and downwards like you would expect:

*   If a list literal has a downwards inference type of `List<T>` for some `T`,
    then the downwards inference context type of a spread element in that list
    is `Iterable<T>`.

*   If a spread element in a list literal has static type `Iterable<T>` for some
    `T`, then the upwards inference element type is `T`.

*   If a map literal has a downwards inference type of `Map<K, V>` for some `K`
    and `V`, then the downwards inference context type of a spread element in
    that map is `Map<K, V>`.

*   If a spread element in a map literal has static type `Map<K, V>` for some
    `K` and `V`, then the upwards inference key type is `K` and the value type
    is `V`.

## Dynamic Semantics

The new dynamic semantics are a superset of the original behavior:

### Lists

A list literal `<E>[elem_1 ... elem_n]` is evaluated as follows:

1.  Create a fresh instance of `list` of a class that implements `List<E>`.

    An implementation is, of course, free to optimize pre-allocate a list of the
    correct capacity when its size is statically known. Note that when spread
    arguments come into play, it's no longer always possible to statically tell
    the final size of the resulting flattened list.

1.  For each `element` in the list literal:

    1.  Evaluate the element's expression to a value `value`.

    1.  If `element` is a spread element:

        1.  If `element` is null-aware and `value` is null, continue to the next
            element in the literal.

        1.  Evaluate `value.iterator` to a value `iterator`.

        1.  Loop:

            1.  If `iterator.moveNext()` returns `false`, exit the loop.

            1.  Evaluate `iterator.current` and append the result to `list`.

    1.  Else:

        1.  Append `value` to `list`.

1.  The result of the literal expression is `list`.

### Maps

A map literal of the form `<K, V>{entry_1 ... entry_n}` is evaluated as follows:

1.  Allocate a fresh instance `map` of a class that implements
    `LinkedHashMap<K, V>`.

1.  For each `entry` in the map literal:

    1.  If `entry` is a spread element:

        1.  Evaluate the entry's expression to a value `value`.

        1.  If `entry` is null-aware and `value` is null, continue to the next
            entry in the literal.

        1.  Evaluate `value.entries.iterator` to a value `iterator`.

        1.  Loop:

            1.  If `iterator.moveNext()` returns `false`, exit the loop.

            1.  Evaluate `iterator.current` to a value `newEntry`.

            1.  Call `map[newEntry.key] = newEntry.value`.

    1.  Else, `entry` has form `e1: e2`:

        1.  Evaluate `e1` to a value `key`.

        1.  Evaluate `e2` to a value `value`.

        1.  Call `map[key] = value`.

1.  The result of the map literal expression is `map`.

## Migration

This is a non-breaking change that purely makes existing semantics more easily
expressible.

It would be excellent to build a quick fix for IDEs that recognizes patterns
like `[stuff]..addAll(more)` and transforms it to use `...` instead.

## Next Steps

This proposal is technically not dependent on "Parameter Freedom", but it would
be strange to support spread arguments in collection literals but nowhere else.
We probably want both. However, because they don't depend on each other, it's
possible to implement them in parallel.

Before committing to do that, we should talk to the implementation teams about
feasibility. I would be surprised if there were major concerns.

## Questions and Alternatives

### Why the `...` syntax?

[Java][java rest], [JavaScript][js rest] use `...` for declaring rest parameters
in functions. JavaScript uses `...` for [spread arguments and collection
elements][js], so I think it is the most familiar syntax to users likely to come
to Dart.

[java rest]: https://docs.oracle.com/javase/8/docs/technotes/guides/language/varargs.html

[js rest]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Functions/rest_parameters

[js]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Spread_syntax

In Dart, `sync*`, `async*`, and `yield*`, all imply that `*` means "many". We
could use that instead of `...`. This is the syntax Python, Scala, Ruby, and
Kotlin use. However, I think it's harder to read in contexts where an expression
is expected:

```dart
var args = [
  *testArgs,
  '--packages=${PackageMap.globalPackagesPath}',
  '-rexpanded',
  *filePaths
];
```

`*` is already a common infix operator, so having it mean something entirely
different in prefix position feels confusing. If this is contentious, it's an
easy question to get data on with a usability study.

### Why `...` in prefix position?

Assuming we want to use `...`, we still have the choice of putting it before or
after the expression:

```dart
var before = [1, ...more, 3];
var after = [1, more..., 3];
```

Putting it before has these advantages (some of which are marginal or dubious):

*   It's what JavaScript does. If we assume most people coming to Dart learned
    and presently know the spread operator through JS, that syntax is the most
    familiar.

*   When skimming a long multi-line collection literal, the `...` are on the
    left side of the page, so it's easy to see which elements are single and
    which are spread:

    ```dart
    var arguments = [
      executable,
      command,
      ...defaultOptions,
      debugFlag,
      ...flags,
      filePath
    ];
    ```

    With a postfix `...`, you have to find the ends of each element expression,
    which likely don't all line up. It's possible to overlook the trailing `...`
    if the preceding expression is particularly long.

    In practice, this is rare. I scraped a large corpus looking for calls to
    `addAll()` on collection literals (which are obvious candidates for this new
    syntax). 80% of the arguments to those are 36 characters or shorter. The
    median expression length was 15 characters.

*   It tells the reader what the expression is for *before* they read it. If we
    put the `...` at the end, the reader has to read the entire expression and
    then realize that it's being spread. With `...` in prefix position, that
    context is established up front.

    This may be more important for code writers. By putting the `...` first,
    they are less likely to forget to add the spread at the end by the time they
    are done writing the expression.

*   It makes it look less like a cascade. Dart allows `..` in infix position to
    mean something different. The similarity with `...` is already worrisome,
    but putting the `...` after an expression exacerbates that. It looks kind of
    like a cascade with a missing name:

    ```dart
    [things..removeLast()...]
    ```

*   In an IDE, auto-complete is likely to trigger after typing each `.`, which
    you would then have to cancel out.

*   It makes the precedence less visually confusing. The `...` syntax doesn't
    really have "operator precedence" because it isn't an operator expression.
    The syntax is part of the collection literal itself. The latter effectively
    means it has the lowest "precedence"&mdash;any kind of expression is valid
    as the spread target, such as:

    ```dart
    [...a + b]
    ```

    Here, the `...` applies to the result of the entire `a + b` expression. This
    isn't likely to occur in practice, but some custom iterable type could also
    use operator overloading. It doesn't look great either way, but I think the
    above is marginally less weird looking than:

    ```dart
    [a + b...]
    ```

    Dart does have *some* history of low-precedence prefix expressions with
    `await` and `throw`. The only postfix expressions, `++` and `--` have high
    precedence.

*   It separates the `...` from the comma. Since commas have a space after, but
    not before, this ensures the `...` and `,` don't run together as in `[1,
    more..., 3]`. Not a huge deal, but it's nice to not jam a bunch of
    punctuation together when possible.

Postfix has some advantages:

*   It's what CoffeeScript does. This isn't a large bonus, obviously, but it
    does mean some users might be familiar with the syntax.

*   It reads in execution order. If you read `...` to mean "iterate over the
    spread object", then putting it at the end mirrors the order that it is
    run. First the spread expression is evaluated, then it is iterated over.

    In particular, this makes null-aware spread operators much less confusing.
    Consider:

    ```dart
    [...?foo?.bar]
    //  | ^ |  ^
    //  | '-'  |
    //  '------'
    ```

    The first `?` in `...?` applies to whether or not evaluating `bar` returns
    null. The second `?` in `?.` looks at whether `foo` is null. In other words,
    the existing null-aware syntax is postfix, so it's confusing to add a second
    null-aware-like syntax that's prefix.

    A postfix form reads nicely from left to right where each `?` applies to the
    thing before it:

    ```dart
    [foo?.bar...?]
    //^ |  ^    |
    //'-'  '----'
    ```

The last bullet point is significant, which makes this one of those hard choices
to make. We have a lot of diffuse pros on one side and an acute but uncommon pro
on the other.

To help gauge how this looks in real code, I found a number of places in a
corpus where this syntax could be used by looking for calls to `.addAll()` on
collection literals. I converted them to use the prefix and postfix syntax
[here][spread examples].

[spread examples]: https://github.com/dart-lang/language/tree/master/working/0047.%20Spread%20Collections/examples

Only a few cases use `...?`. Some examples do have pretty complex expressions
where it's easy to overlook a trailing `...`, like:

```dart
// More...
              TableRow(
                children: [
                  const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0, bottom: 4.0),
                    child: Text('Ingredients', style: headingStyle)
                  ),
                ]
              ),
              recipe.ingredients.map(
                (RecipeIngredient ingredient) {
                  return _buildItemRow(ingredient.amount, ingredient.description);
                }
              )...,
              TableRow(
                children: [
                  const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0, bottom: 4.0),
                    child: Text('Steps', style: headingStyle)
                  ),
                ]
              ),
// More...
```

Here, the `...` almost looks like it's part of the *next* element, the TableRow,
instead of the preceding one. Given this, I think prefix `...` is the better choice.
