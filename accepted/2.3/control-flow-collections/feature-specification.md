# Control Flow Collections

Author: rnystrom@google.com

Status: Draft

Allow `if` and `for` in collection literals to build collections using
conditionals and repetition.

**Note: Because this feature interacts heavily with [Set Literals][] and [Spread Collections][], which are all being implemented concurrently, we have a [unified proposal][] that covers the behavior of all three. That proposal is now the source of truth. This document is useful for motivation, but may be otherwise out of date.**

[set literals]: https://github.com/dart-lang/language/blob/master/accepted/2.2/set-literals/feature-specification.md
[spread collections]: https://github.com/dart-lang/language/blob/master/accepted/2.3/spread-collections/feature-specification.md
[unified proposal]: https://github.com/dart-lang/language/tree/master/accepted/2.3/unified-collections/feature-specification.md

## Motivation

A key goal of Flutter's API design is that, as much as possible, the textual
layout of the code reflects the nesting structure of the resulting user
interface. If a Button constructor call is nested inside a Padding constructor,
that button is surrounded by that padding on the screen. Ideally, a `build()`
method for a widget is a single nested expression tree that you can read from
top-to-bottom and outside-in:

```dart
Widget build(BuildContext context) {
  return Row(
    children: [
      IconButton(icon: Icon(Icons.menu)),
      Expanded(child: title),
      IconButton(icon: Icon(Icons.search)),
    ],
  );
}
```

Dart's terse constructor syntax and list literals are enough to achieve that in
simple cases like this. But real widgets often get more complex. In particular,
widgets often need to conditionally omit or swap out certain child widgets.

Let's say we only want to show that search button on Android. Because there's no
graceful way to omit an element from a list literal, we have to hoist that
entire list out to the statement level where we can use control flow:

```dart
Widget build(BuildContext context) {
  var buttons = <Widget>[
      IconButton(icon: Icon(Icons.menu)),
      Expanded(child: title),
  ];

  if (isAndroid) {
    buttons.add(IconButton(icon: Icon(Icons.search)));
  }

  return Row(
    children: buttons,
  );
}
```

The code has lost its top-down structure. The reader first sees some list of
buttons being built but doesn't know what they're for. Only when they reach the
end do they see the outermost widget that contains them.

Also notice how much the code had to *change* to go from its original form to
the modified one. All we wanted to do was omit a single element, but we had to
reorganize the entire function.

Clever users have come up with workarounds like:

```dart
Widget build(BuildContext context) {
  return Row(
    children: [
      IconButton(icon: Icon(Icons.menu)),
      Expanded(child: title),
      isAndroid ? IconButton(icon: Icon(Icons.search)) : null,
    ].where((child) => child != null).toList(),
  );
}
```

It's arguably better than the above code, but it's not obvious or terse. Adding
[spread syntax][spread] would let you do:

[spread]: https://github.com/dart-lang/language/blob/master/accepted/2.3/spread-collections/feature-specification.md

```dart
Widget build(BuildContext context) {
  return Row(
    children: [
      IconButton(icon: Icon(Icons.menu)),
      Expanded(child: title),
      ...isAndroid ? [IconButton(icon: Icon(Icons.search))] : [],
    ],
  );
}
```

Is that better? Maybe. It still doesn't make the *intent* of the code clear. The
user wants to express "if we're on Android, include the search button" and they
have to cobble together a few syntaxes to approximate that.

With this proposal, the code is:

```dart
Widget build(BuildContext context) {
  return Row(
    children: [
      IconButton(icon: Icon(Icons.menu)),
      Expanded(child: title),
      if (isAndroid) IconButton(icon: Icon(Icons.search)),
    ]
  );
}
```

Compare this to the original non-conditional form. In order to make one child
widget conditionally omitted, all we had to do was add `if (isAndroid)` before
an element.

Note that the "body" of the `if` is not a statement. It's a list
element&mdash;an expression whose result is directly inserted into the resulting
list. This keeps the code declarative and expression-oriented. You don't state
*how* the element is inserted by *modifying* a list. It's less like "control
flow" and more like the [conditional][if-1] [expansion][if-2] [tags][if-3] in
various template languages.

[if-1]: https://docs.angularjs.org/api/ng/directive/ngIf
[if-2]: http://handlebarsjs.com/builtin_helpers.html
[if-3]: https://docs.djangoproject.com/en/2.1/ref/templates/builtins/#if

Of course, `else` is supported too. Let's say we want to show an "about" button
instead of "search" when we're not on Android. With this proposal, it's:

```dart
Widget build(BuildContext context) {
  return Row(
    children: [
      IconButton(icon: Icon(Icons.menu)),
      Expanded(child: title),
      if (isAndroid)
        IconButton(icon: Icon(Icons.search))
      else
        IconButton(icon: Icon(Icons.about)),
    ]
  );
}
```

Users can and do use the conditional operator (`?:`) for cases like this today.
It works OK, but isn't very easy on the eyes. And, of course, it falls down in
cases where you don't have an "else" widget that you want to use instead of the
"then" one.

I admit it *is* a little strange seeing the familiar `if` keyword in a place
where it's never appeared before. But my hope is that the semantics are fairly
intuitive.

### Repetition

This is less common than conditional control flow, but repetition comes up too.
At the statement level, you can loop if you want to execute something a certain
number of times or for each of a series of items in an Iterable. In an
expression context, it's useful if you want to produce more than one value.

Spread syntax covers some of these use cases, but when you want to do more than
just insert a sequence in place, it forces you to chain a series of higher-order
methods together to express what you want. That can get cumbersome, especially
if you're mixing both repetition and conditional logic. You always *can* solve
that using some combination of `map()`, `where()`, and `expand()`, but the
result isn't always readable.

So this proposal also lets you use `for` inside a collection literal. That
turns, for example, this code:

```dart
var command = [
  engineDartPath,
  frontendServer,
];
for (var root in fileSystemRoots) {
  command.add('--filesystem-root=$root');
}
for (var entryPointsJson in entryPointsJsonFiles) {
  if (fileExists("$entryPointsJson.json")) {
    command.add(entryPointsJson);
  }
}
command.add(mainPath);
```

Into:

```dart
var command = [
  engineDartPath,
  frontendServer,
  for (var root in fileSystemRoots) '--filesystem-root=$root',
  for (var entryPointsJson in entryPointsJsonFiles)
    if (fileExists("$entryPointsJson.json")) entryPointsJson,
  mainPath
];
```

Note the `if` nested inside the `for` and consider what that would look like if
using higher-order methods on Iterable instead.

A nice bonus of allowing `for` is that it gives us something not too far from
the "[list comprehension][]" syntax supported by some other languages. We now
have a nice short syntax for creating a list from a computation:

[list comprehension]: https://en.wikipedia.org/wiki/List_comprehension

```dart
var integers = [for (var i = 1; i < 5; i++) i]; // [1, 2, 3, 4]
var squares = [for (var n in integers) n * n]; // [1, 4, 9, 16]
```

It may seem surprising, but `for` also works perfectly well for map literals.
It lets you turn this:

```dart
Map<String, WidgetBuilder>.fromIterable(
  kAllGalleryDemos,
  key: (demo) => '${demo.routeName}',
  value: (demo) => demo.buildRoute,
);
```

Into:

```dart
return {
  for (var demo in kAllGalleryDemos)
    '${demo.routeName}': demo.buildRoute,
};
```

You can think of it as a more direct way of expressing what you'd use
`Map.fromIterable()` for today.

If we're going to support `for`, we may as well also support its asynchronous
sister `await for`:

```dart
main() async {
  var stream = getAStream();
  var elements = [await for (var element in stream) element];
}
```

This gives you a concise way to transform each element of a stream and store
the result in a list.

### Composing

As some of the previous examples have shown, `if` and `for` can be freely
composed. That enables some interesting patterns and techniques:

```dart
[for (var x in hor) for (var y in vert) Point(x, y)]
```

This produces the Cartesian product of all points in the rectangle.

```dart
[for (var i in integers) if (i.isEven) i * i]
```

This produces the squares of the even integers.

This proposal can be composed with spread syntax to include multiple elements
based on a single `if` condition:

```dart
Widget build(BuildContext context) {
  return Row(
    children: [
      IconButton(icon: Icon(Icons.menu)),
      Expanded(child: title),
      if (isAndroid) ...[
        IconButton(icon: Icon(Icons.search)),
        IconButton(icon: Icon(Icons.refresh)),
        IconButton(icon: Icon(Icons.help))
      ],
    ]
  );
}
```

Again, this works in maps too. Here's an example I found in Flutter:

```dart
var routes = Map<String, String>.fromIterable(
  kAllGalleryDemos.where((demo) => demo.documentationUrl != null),
  key: (dynamic demo) => demo.routeName,
  value: (dynamic demo) => demo.documentationUrl,
);
```

This could become:

```dart
var routes = {
  for (var demo in kAllGalleryDemos)
    if (demo.documentationUrl != null)
       demo.routeName: demo.documentationUrl
};
```

### A large example

You can sell basically any language syntax using toy examples. For a better
sense of how this would look in reality, here's a less-contrived piece of code
taken from Flutter:

```dart
// flutter/examples/flutter_gallery/lib/demo/contacts_demo.dart:54
Widget build(BuildContext context) {
  final themeData = Theme.of(context);
  final columnChildren = lines
      .sublist(0, lines.length - 1)
      .map((line) => Text(line))
      .toList();
  columnChildren.add(Text(lines.last, style: themeData.textTheme.caption));

  final rowChildren = [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columnChildren
      )
    )
  ];

  if (icon != null) {
    rowChildren.add(SizedBox(
      width: 72.0,
      child: IconButton(
        icon: Icon(icon),
        color: themeData.primaryColor,
        onPressed: onPressed
      )
    ));
  }

  return MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: rowChildren
      )
    ),
  );
}
```

I don't want to belabor the point, but again note how the top-down structure is
lost. It's pretty imperative too. In order to visualize the resulting UI, the
user doesn't have to just *read* the code, they have to *simulate its execution*
in their head.

With this proposal, that becomes:

```dart
Widget build(BuildContext context) {
  final themeData = Theme.of(context);

  return MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var line in lines .sublist(0, lines.length - 1))
                  Text(line),
                Text(lines.last, style: themeData.textTheme.caption)
              ]
            )
          ),
          if (icon != null) SizedBox(
            width: 72.0,
            child: IconButton(
              icon: Icon(icon),
              color: themeData.primaryColor,
              onPressed: onPressed
            )
          )
        ]
      )
    ),
  );
}
```

### Type inference

This proposal is mostly about readability, but that isn't the only benefit. By
turning imperative, mutating code into declarative expressions inside the
collection literal, type inference becomes more effective. Both upwards and
downwards inference has more code to chew on.

Consider:

```dart
Widget build(BuildContext context) {
  var buttons = <Widget>[];

  if (isAndroid) {
    buttons.add(IconButton(icon: Icon(Icons.search)));
  }

  buttons.add(IconButton(icon: Icon(Icons.menu)));

  return Row(children: buttons);
}
```

Note that explicit type annotation on the list literal. That's needed because we
don't know any of its elements at creation time. By moving that `if` inside the
list, we can use the elements to infer the list's type:

```dart
Widget build(BuildContext context) {
  var buttons = [
    if (isAndroid) IconButton(icon: Icon(Icons.search)),
    IconButton(icon: Icon(Icons.menu))
  ];

  return Row(children: buttons);
}
```

In many cases, this upwards inference infers the type that you want, and being
able to move more of the list's contents inside the literal improves that. In
this case, though, the inferred type is a little more precise than desired.
Fortunately, downwards inference is improved too. If the code is fully
refactored to:

```dart
Widget build(BuildContext context) {
  return Row(children: [
    if (isAndroid) IconButton(icon: Icon(Icons.search)),
    IconButton(icon: Icon(Icons.menu))
  ]);
}
```

Now, the fact that Row's `children` parameter has type `List<Widget>` causes
that to be the inferred type of the list. We're able to do this because the
entire list creation is now a single expression so it can be moved right into
the constructor call for `Row()`.

## Syntax

We extend the list and set grammars to allow *control flow elements* in addition
to regular elements:

```
listLiteral:
  const? typeArguments? '[' collectionElementList? ']'
  ;

setLiteral:
  const? typeArguments? '{' collectionElementList? '}' ;

collectionElementList:
  collectionElement ( ',' collectionElement )* ','?
  ;

collectionElement:
  expression |
  'if' '(' expression ')' collectionElement ( 'else' collectionElement )? |
  'await'? 'for' '(' forLoopParts ')' collectionElement
  ;
```

Instead of `expressionList`, this uses a new `collectionElementList` rule since
`expressionList` is used elsewhere in the grammar like argument lists where
control flow isn't allowed.

Each element in a list or set can be one of a few things:

* A normal expression.
* An `if` element.
* A `for` element.

The body of `if` and `for` elements use `collectionElement`, not `expression`,
which allows nesting.

The changes for map literals are similar:

```
mapLiteral:
  const? typeArguments? '{' mapLiteralEntryList? '}' ;

mapLiteralEntryList:
  mapLiteralEntry ( ',' mapLiteralEntry )* ','?
  ;

mapLiteralEntry:
  expression ':' expression |
  'if' '(' expression ')' mapLiteralEntry ( 'else' mapLiteralEntry )? |
  'await'? 'for' '(' forLoopParts ')' mapLiteralEntry
  ;
```

**Note: The final grammar once spread is taken into account will be somewhat
different to account for the ambiguity between sets and maps that contain only
spreads, but the differences between this proposal and the final grammar should
be fairly obvious.**

## Static Semantics

Let the *element type* of a list literal be the static type of the type argument
used to create the list. So `<int>[]` has an element type of `int`. It may be
explicit or filled in by type inference. So `[1, 2.0]` has an element type of
`num`.

Let the *key type* and *value type* of a map literal be the corresponding
static types of the type arguments for a map literal. So `<int, String>{}` and
`{1: "s"}` both have a key type of `int` and a value type of `String`.

Let the *body elements* of an `if` element be the "then" element and the "else"
element if there is one. Let the *body elements* of a `for` element be the
single element it contains.

### Scoping

Both styles of `for` element may introduce a local variable, as in:

```dart
[
  for (var i = 1; i < 4; i++) i,
  for (var i in [1, 2, 3]) i
]
```

If a `for` element declares a variable, then a new namespace is created on each
iteration where that variable is defined. The body of the `for` element is
resolved and evaluated in that namespace. The variable goes out of scope at the
end of the for element's body.

Each iteration of the loop binds a new fresh variable:

```dart
var closures = [for (var i = 1; i < 4; i++) () => i];
for (var closure in closures) print(closure());
// Prints "1", "2", "3".
```

### Static errors

The static semantics of collection `if` and `for` mostly follow their statement
analogues.

If is a static error when:

*   The collection is a list and the type of any of the body elements may not be
    assigned to the list's element type.

    ```dart
    <int>[if (true) "not int"] // Error.
    ```

*   The collection is a map and the key type of any of the body elements may not
    be assigned to the map's key type.

    ```dart
    <int, int>{if (true) "not int": 1} // Error.
    ```

*   The collection is a map and the value type of any of the body elements may
    not be assigned to the map's value type.

    ```dart
    <int, int>{if (true) 1: "not int"} // Error.
    ```

*   The type of the condition expression in an `if` element may not be assigned
    to `bool`.

    ```dart
    [if ("not bool") 1] // Error.
    ```

*   The type of the iterator expression in a synchronous `for-in` element may
    not be assigned to `Iterable<T>` for some type `T`. Otherwise, the *iterable
    type* of the iterator is `T`.

    ```dart
    [for (var i in "not iterable") i] // Error.
    ```

*   The iterable type of the iterator in a synchronous `for-in` element may not
    be assigned to the `for-in` variable's type.

    ```dart
    [for (int i in ["not", "int"]) i] // Error.
    ```

*   The type of the stream expression in an asynchronous `await for-in`
    element may not be assigned to `Stream<T>` for some type `T`. Otherwise,
    the *stream type* of the stream is `T`.

    ```dart
    [await for (var i in "not stream") i] // Error.
    ```

*   The stream type of the iterator in an asynchronous `await for-in` element
    may not be assigned to the `for-in` variable's type.

    ```dart
    [await for (int i in Stream.fromIterable(["not", "int"])) i] // Error.
    ```

*   `await` is used when the collection literal is not inside an asynchronous
    function.

*   `await` is used before a C-style `for` element. `await` can only be used
    with `for-in` loops.

*   The type of the condition expression (the second clause) in a C-style `for`
    element may not be assigned to `bool`.

    ```dart
    [for (; "not bool";) 1] // Error.
    ```

### Type inference

Inference propagates upwards and downwards like you would expect. For the most
part, inference flows "through" the `if` and `for` into the body element(s).

*   If a list literal has a downwards inference type of `List<T>` for some `T`,
    then the downwards inference context type of the body elements is `T`.

    Thus:

    ```dart
    List<List<String>> i = [
      if (true) [],
      if (false) [] else [],
      for (var i = 0; i < 1; i++) []
    ];
    ```

    Produces a `List<List<String>>` containing three empty `List<String>`.

*   The upwards inference element type of an `if` list element without an `else`
    is the type of the "then" element.

*   The upwards inference element type of an `if-else` list element is the least
    upper bound of the types of the "then" and "else" elements.

*   The upwards inference element type of a `for` list element is the type of
    the body element.

*   If a map literal has a downwards inference type of `Map<K, V>` for some `K`
    and `V`, then the downwards inference context type of the keys in the body
    elements is `K` and the values is `V`.

    Thus:

    ```dart
    Map<List<String>, List<int>> i = {
      if (true) []: [],
      if (false) []: [] else []: [],
      for (var i = 0; i < 1; i++) []: []
    };
    ```

    Produces a `Map<List<String>, List<int>>` containing three entries. Each key
    is an empty `List<String>` and each value is an empty `List<int>`.

*   The upwards inference key type of an `if` map element without an `else` is
    the key type of the "then" element, likewise for the value type.

*   The upwards inference key type of an `if-else` map element is the least
    upper bound of the key types of the "then" and "else" elements, likewise for
    the value type.

*   The upwards inference key type of a `for` map element is the key type of the
    body element, likewise for the value type.

### Type promotion

As with the `if` statement, the condition expression of an `if` element induces
type promotion in the "then" element of the `if` when the condition expression
shows that a variable has some type and promotion isn't otherwise aborted.

### Const collections

A collection literal is now a series of *elements* (some of which may contain
nested subelements) instead of just expressions (for lists and sets) or entries
(for maps). A constant collection takes that tree of elements and *expands* it
to a series of values (lists and sets) or entries (maps). The resulting
collection contains that series of values/entries, in order.

We have to be careful to ensure that arbitrary computation doesn't happen due to
control flow appearing in a constant collection. There are five kinds of
elements to consider:

*   An **expression element** (the base case in lists and sets):

    *   It is a compile-time error if the expression is not a constant
        expression.

    The expansion is the value of the expression.

*   An **entry element** (the base case in maps):

    *   It is a compile-time error if the key or value expressions are not
        constant expressions.

    *   As is already the case in Dart, it is a compile-time error if the key is
        an instance of a class that implements the operator `==` unless the key
        is a Boolean, string, integer, literal symbol or the result of invoking
        a constant constructor of class Symbol. It is a compile-time error if
        the type arguments of a constant map literal include a type parameter.

    The expansion is the entry formed by the key and value expression values.

*   A **spread element**:

    See the [relevant proposal][const spread] for how these are handled.

    [const spread]: https://github.com/dart-lang/language/blob/master/accepted/2.3/spread-collections/feature-specification.md#const-spreads

*   An **if element**:

    *   It is a compile-time error if the condition expression is not constant
        or does not evaluate to `true` or `false`.

    *   It is a compile-time error if the then and else branches are not
        potentially const expressions. The "potentially const" is to allow a
        the unchosen branch to throw an exception. In other words, if elements
        short-circuit.

    *   It is a compile-time error if the condition evaluates to `true` and the
        then expression is not a constant expression.

    *   It is a compile-time error if the condition evaluates to `false` and the
        else expression, if it exists, is not a constant expression.

    The expansion is:

    *   The then element if the condition expression evaluates to `true`.

    *   The else element if the condition is `false` and there is one.

    *   Otherwise, the `if` element expands to nothing.

*   A **for element**:

    These are disallowed in constant collections. In order to fit within the
    restrictions on constants, the set of things you could conceivably do with
    `for` is so limited that we felt the best option was to omit it entirely.

The description here merges maps with lists and sets, but note that, of course,
a const list or set may not contain entry elements and a map may not contain
expression elements. (The grammar prohibits this anyway.)

Dart allows the `const` keyword to be omitted in "constant contexts". All of the
expressions inside elements in a constant collection are const contexts,
transitively. This includes the `if` condition expression, spread expression,
etc.

## Dynamic Semantics

The new dynamic semantics are a superset of the original behavior. To avoid
redundancy and handle nested uses, the semantics are expressed in terms of a
separate procedure below:

### Lists

1.  Create a fresh instance `collection` of a class that implements `List<E>`.

    An implementation is, of course, free to optimize by pre-allocating a list
    of the correct capacity when its size is statically known. Note that when
    `if` and `for` come into play, it's no longer always possible to statically
    tell the final size of the resulting flattened list.

1.  For each `element` in the list literal:

    1.  Evaluate `element` using the procedure below.

1.  The result of the literal expression is `collection`.

### Sets

1.  Create a fresh instance `collection` of a class that implements `Set<E>`.

1.  For each `element` in the set literal:

    1.  Evaluate `element` using the procedure below.

1.  The result of the literal expression is `collection`.

### Maps

A map literal of the form `<K, V>{entry_1 ... entry_n}` is evaluated as follows:

1.  Allocate a fresh instance `map` of a class that implements `LinkedHashMap<K,
    V>`.

1.  For each `element` in the map literal:

    1.  Evaluate `element` using the procedure below.

1.  The result of the map literal expression is `map`.

### To evaluate a collection `element`:

This procedure handles elements in both list and map literals because the only
difference is how a base expression element or entry element is handled. The
control flow parts are the same so are unified here.

1.  If `element` is an `if` element:

    1.  Evaluate the condition expression to a value `condition`.

    1.  Subject `condition` to boolean conversion to a value `result`.

    1.  If `result` is `true`:

        1.  Evaluate the "then" element using this procedure.

    1.  Else, if there is an "else" element of the `if`:

        1.  Evaluate the "else" element using this procedure.

1.  Else, if `element` is a synchronous `for-in` element:

    1.  Evaluate the iterator expression to a value `sequence`.

    1.  Evaluate `sequence.iterator` to a value `iterator`.

    1.  Loop:

        1.  If the boolean conversion of `iterator.moveNext()` does not return
            `true`, exit the loop.

        1.  If the `for-in` element declares a variable, create a fresh
            `variable` for it. Otherwise, use the existing `variable` it refers
            to.

        1.  Evaluate `iterator.current` and bind it to `variable`.

        1.  Evaluate the body element using this procedure in the scope of
            `variable`.

    1.  If the `for-in` element declares a variable, discard it.

1.  Else, if `element` is an asynchronous `await for-in` element:

    1.  Evaluate the stream expression to a value `stream`. It is a dynamic
        error if `stream` is not an instance of a class that implements
        `Stream`.

    1.  Create a new `Future`, `streamDone`.

    1.  Evaluate `await streamDone`.

    1.  Listen to `stream`. On each data event `event` the stream sends:

        1.  If the `for-in` element declares a variable, create a fresh
            `variable` for it. Otherwise, use the existing `variable` it refers
            to.

        1.  Bind `event` to `variable`.

        1.  Evaluate the body element using this procedure in the scope of
            `variable`. If this raises an exception, complete `streamDone` with
            it as an error.

    1.  If the `for-in` element declares a variable, discard it.

    1.  If `stream` raises an exception, complete `streamDone` with it as an
        error. Otherwise, when all events in the stream are processed, complete
        `streamDone` with `null`.

1.  Else, if `element` is a C-style `for` element:

    1.  Evaluate the initializer clause of the element, if there is one.

    1.  Loop:

        1.  Evaluate the condition expression to a value `condition`. If there
            is no condition expression, use `true`.

        1.  If the boolean conversion of `condition` is not `true`, exit the
            loop.

        1.  Evaluate the body element using this procedure in the scope of the
            variable declared by the initializer clause if there is one.

        1.  If there is an increment clause, execute it.

1.  Else, if `element` is a spread element, see the relevant proposal.

1.  Else, if `element` is an expression element:

    1.  Evaluate the element's expression to a value `value`.

    1.  Call `collection.add(value)`.

1.  Else, `element` has form `keyExpression: valueExpression`:

    1.  Evaluate `keyExpression` to a value `key`.

    1.  Evaluate `valueExpression` to a value `value`.

    1.  Call `map[key] = value`.

## Migration

This is a non-breaking change that purely makes existing semantics more easily
expressible, so there is no required migration.

### Automated fixes

It may be possible for tooling to detect some of the existing idioms that are
better expressed using this new syntax and give the user the option to
automatically change it to the new style. Cases where conditional logic has been
hoisted all the way out of a collection may be hard to detect since the
resulting code is pretty imperative.

It should be possible to detect cases like:

*   **Switching out an element using a conditional operator:**

    ```dart
    [
      before,
      condition ? first : second,
      after
    ]
    ```

    Fix:

    ```dart
    [
      before,
      if (condition) first else second,
      after
    ]
    ```

*   **Omitting an element using a conditional operator and `null` filtering:**

    ```dart
    [
      before,
      condition ? first : null,
      after
    ].where((e) => e != null).toList()
    ```

    Fix:

    ```dart
    [
      before,
      if (condition) first,
      after
    ]
    ```

*   **Using `Map.fromIterable()`:**

    ```dart
    Map.fromIterable(things,
      key: (e) => someExpression(e),
      value: (e) => anotherExpression(e)
    )
    ```

    Fix:

    ```dart
    {
      for (var e in things)
        someExpression(e): anotherExpression(e)
    }
    ```

    This may fall down if the two closures are complex but I think that's rare
    in practice.

I think we probably *don't* want to blanket apply all of these fixes without
user intervention. There may be some style preferences or the fix may not
always succeed. This is a big enough change where having a human validate it is
a good idea.

## Next Steps

As always, the immediate next step of a proposal is running it past the language
leads and stakeholders.

### Usability studies

This feature has some good things going for it:

*   It is mostly syntax sugar. A front end should be able to compile this down
    to existing Dart semantics (with perhaps some extra support needed for `if`
    in const collections). It shouldn't significantly impact the runtime or
    backends, so the implementation cost should be relatively low.

*   The semantics are narrow and fairly straightforward. It doesn't interact
    with the type system in complex ways. It doesn't touch tricky parts of the
    grammar, calling conventions, or runtime behavior. I think the
    implementation is fairly low-risk. I don't think we're likely to run into
    major surprises we didn't anticipate during implementation.

However, the human side of this is less certain. I've tried to make the behavior
intuitive by piggy-backing on syntax users already understand. But I worry that:

*   Users will find it confusing to see `if` or `for` inside a collection
    literal.

*   Even after understanding it, users may not *like* the syntax.

*   Users may be unhappy that the syntax doesn't go *far enough*. This feature
    may lead them to expect, say, `while` to work inside a collection. They may
    expect to be able to put an entire block of statements as the body of an
    `if`. They may want to use `if` outside of a collection but in other
    expression contexts.

    In other words, this may be a "garden path" feature that encourages a whole
    set of expectations, some of which are met and the rest of which are
    confounded.

*   Users may want to include multiple elements inside a body and not know how
    to accomplish that. The spread proposal gives them a mechanism, but it may
    not be a natural or obvious one.

I don't think we can reasonably resolve these on paper, so before shipping this
feature, I think we should do user studies of some of these scenarios and refine
the behavior if needed based on the results.

### Conditional arguments

This proposal only covers conditional execution in collections. A natural
extension that would be particularly useful for Flutter is to extend it to
argument lists:

```dart
IconButton(
  icon: Icon(Icons.menu),
  tooltip: 'Navigation menu',
  if (isAndroid) padding: const EdgeInsets.all(20.0),
)
```

Without [rest parameters][], `for` isn't useful and `if` probably isn't
feasible for positional arguments. But even without rest params, it's possible
to support `if` for named arguments.

[rest parameters]: https://github.com/munificent/ui-as-code/blob/master/in-progress/parameter-freedom.md

We can and should look at doing that as a separate proposal.

## Questions and Alternatives

### Why is `while` not supported?

The proposal only allows one looping construct, but Dart has three: `for`,
`while`, and `do-while`. What's special about `for`?

The key reason is that `for` loops are implicitly terminated. A `for-in` loop
ends when it reaches the end of the iterator. A C-style `for` loop ends when the
condition expression returns `false`, which is in turn based on the increment
expression.

`while` and `do-while` loops both have a condition expression that signals
termination, but that's not enough. For that to work, the body of those loops
must have some explicit *side-effect* that eventually causes the expression to
return false.

But, in this proposal, the body of a loop is an *element* whose primary role is
declarative&mdash;it emits a value that gets added to the resulting collection.
There's no room there for an imperative, side-effecting operation.

In order to make a while loop usable, you'd need some kind of block structure so
you can contain side-effectful statements (including possibly `break`). But you
also need a way to emit values, which is the primary purpose. It's hard to come
up with a syntax that supports side effects that doesn't also make the main use
case&mdash;emitting values&mdash;more verbose and less declarative.

In other words, `for` loops are declarative enough to work well in an expression
context, but `while` and `do-while` loops are not.

Also, when examining a corpus for collection literals, I found a number of cases
where `for` loops would be useful, but none where I felt the other kinds would
be.

There's also an argument that if what you're doing is so imperative that you
want a `while` loop, then you *should* hoist that out into the statement level.
The readability benefits of embedding control flow inside a collection literal
is that it keeps more of your code declarative and expression-based. If your
code *is* actually imperative, then the most familiar, readable way to express
that is using actual statements.

You can always move that imperative code into a separate function which returns
an Iterable, and then use spread syntax to insert the results of that into your
collection.
