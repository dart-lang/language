# Static Enough Metaprogramming

**Author**: Slava Egorov (@mraleph, vegorov@google.com)

**Status**: Draft

**Version**: 1.0

**Summary**: I propose we follow the lead of **D**, **Zig** and **C++26** when it
comes to metaprogramming. We introduce an optional (toolchain) feature to force
compile-time execution of certain constructs. We add library functions to
introspect program structure which are _required_ to execute at compile time
if the toolchain supports that. These two together should give enough expressive
power to solve a wide range of problems where metaprogramming is currently
wanted.

## History of `dart:mirrors`

In the first days of 2017 I have written a blog post ["The fear of
`dart:mirrors`"][the-fear-of-dartmirrors] which started with the
following paragraph:

> [`dart:mirrors`][dart-mirrors-1-21-1] might be the most misunderstood,
> mistreated, neglected component of the Dart's core libraries. It has been a
> part of Dart language since the very beginning and is still surrounded by the
> fog of uncertainty and marked as _Status: Unstable_ in the documentation -
> even though APIs have not changed for a very long time.

In 2017 the type system was still optional, AOT was a glorified
_"ahead-off-time-JIT"_, and the team maintained at least 3 different Dart
front-ends (VM, dart2js and analyzer). Things really started shifting with the
Dart 2 release: it had replaced optional types with a static type system and
introduced a _common front-end (CFE)_ infrastructure to be shared by all
backends. Dart 3 introduced null-safety by default (NNBD).

And so 8 years and many stable releases later Dart language and its toolchains
have changed in major ways, but [`dart:mirrors`][dart-mirrors] remained in the
same sorrowful state: a core library only supported by the native implementation
on Dart, only in JIT mode and only outside of Flutter.

How did this happen?

The root of the answer lies in the conflict between _Dart 1 design philosophy_
and the necessity to use _AOT-compilation_ for deployment.

Dart 1 was all in on dynamic typing. You don't know what a variable contains -
but you can do anything with it. Can pass it anywhere. Can call any methods on
it. Any class can override a catch-all `noSuchMethod` and intercept invocations
of methods it does not define. Dart's reflection system `dart:mirrors` is
similarly unrestricted: you can [reflect][dart-mirrors-reflect] on any value,
then ask information about its [type][dart-mirrors-type], ask a type about its
[declarations][dart-mirrors-declarations], ask declared members about their
[parameters][dart-mirrors-parameters] and so on. Having an appropriate _mirror_
you can invoke methods, read and write fields, instantiate new objects.

This ability to _indirectly_ act on the state of the program creates a problem
for the static analysis of the program and that in turn affects the ability
of the AOT compiler to produce a small and fast binary.

To put this complexity in simple terms consider two pieces of code:

```dart
// Direct
T0 e0; /* ... */; Tn en;
e0.method(e1, /* ... */, en);

// Reflective
InstanceMirror m; List args; Symbol name;
m.invoke(name, args);
```

When a compiler sees the first piece of code it can easily figure out which
`method` implementation this call can reach and what kind of parameters are
passed through. With the second piece of code, analysis complexity skyrockets -
none of the information is directly available in the source code: to know
anything about the invocation a compiler needs to know a lot about contents of
`m`, `args` and `name`.

While it is not impossible to built static analysis which is capable to see
through reflective access - in practice such analyses are complicated, slow
and suffer from precision issues on real world code.

AOT compilation and reflection is pulling into opposite directions: the AOT
compiler wants to know which parts of the program are accessed and how, while
reflection obscures this information and provides developer with indirect
access to the whole program. When trying to resolve this conflict you can choose
between three options:

- The first option is to **make reflection system _just work_ even after AOT
  compilation**. This means retaining all information (and code) which can be
  indirectly accessed via reflection. In practice this means retaining _most_ of
  the original program - because most uses of reflection are notoriously hard to
  analyze statically.
- The second option is to **allow an AOT-compiler to ignore reflection uses it
  can't analyze** and providing developer with a way to feed additional
  information about reflective uses into the compiler. If developer forgets (or
  feeds incomplete or incorrect information) reflective code _might_ break after
  compilation if the compiler decides to remove part of the program which it
  deems unreachable.
- The third option is to capitulate and **disable reflection APIs in AOT
  compiled code**.

Facing this choice is not unique to Dart: Java faces exactly the same challenge.
On one hand, the package [`java.lang.reflect`][java-reflect] provides indirect
APIs for accessing and modifying the state and structure of the running program.
On the other hand, developers want to obfuscate and shrink their apps before
deployment. The Java ecosystem went with the second option: shrinking tools
more-or-less ignore reflection and developers have to [manually inform
toolchain][android-shrink-code] about the program elements which are accessed
reflectively.

> [!NOTE]
>
> There has been a number of attempts to statically analyze reflection in Java
> projects, but they have all hit issues around scalability and precision of the
> analysis. See:
>
> - [Reflection Analysis for Java][paper-java-suif-reflection]
> - [Understanding and Analyzing Java Reflection][paper-java-reflection-2019]
> - [Challenges for Static Analysis of Java Reflection – Literature Review and Empirical Study][paper-java-reflection-challenges]
>
> Graal VM Native Image (AOT compiler for Java) attempts to fold away as much of
> reflection uses as it can, but otherwise just like ProGuard and similar tools
> [relies][java-native-image-reflection] on a developer to inform the compiler
> about reflection uses it could not resolve statically.
>
> R8 (Android bytecode shrinker) has a special
> [troubleshooting][r8-troubleshooting] section in its `README` to cover obscure
> situations which might arise if developer fails to properly configure ProGuard
> rules to cover reflection uses.
>
> [Reflekt: a Library for Compile-Time Reflection in Kotlin][paper-reflekt]
> describes a compiler plugin based compile time reflection system similar in
> some ways to `reflectable`.
>
> [Compile-time Reflection and Metaprogramming for Java][paper-miao-siek] covers
> a metaprograming system which proposes metaprogramming system based on
> compile-time reflection.

Dart initially went with the first option and tried to make `dart:mirrors` _just
work_ when compiling Dart to JavaScript. However, rather quickly the `dart2js`
team started facing performance and code size issues caused by `dart:mirrors` in
large Web applications. So they switched gears and tried the second option:
they introduced [`@MirrorsUsed`][dart-mirrors-used] annotation. However it
provided only a temporary and partial reprieve from the problems and was
eventually abandoned together with `dart:mirrors`.

There were two other attempts to address code size issues caused by mirrors,
while retaining some amount of reflective capabilities: now abandoned package
[`smoke`][pkg-smoke] and still maintained package
[`reflectable`][pkg-reflectable]. Both of these apply similar approach: instead
of relying on the toolchain to provide unrestricted reflection, have a developer
opt-in into specific reflective capabilities for specific parts of the program
then generate a pile of auxiliary Dart code implementing these capabilities.

> [!NOTE]
>
> Another exploration similar in nature was
> [go/const-tree-shakeable-reflection-objects](http://go/const-tree-shakeable-reflection-objects).

Fundamentally both `smoke` and `reflectable` were dead ends and Web applications
written in Dart solved their code size and performance issues by moving away
from reflection to _code generation_, effectively abandoning runtime
metaprogramming in favor of build time metaprogramming. Code generators are
usually written on top of Dart's [analyzer][pkg-analyzer] package: they inspect
a (possibly incomplete) program structure and produce additional code which
needs to be compiled together with the program.

Following this experience, we have decided to completely disable `dart:mirrors`
when implementing a native AOT compiler.

> [!NOTE]
>
> For the sake of brevity I am ignoring discussion of performance problems
> associated with reflection for now. It is sufficient to say that naive
> implementation of reflection is guaranteed to be _slow_ and minimizing the
> cost likely requires runtime code generation - which is not possible in all
> environments.

> [!NOTE]
>
> If you are familiar with the intricacies of Dart VM / Flutter engine embedding
> you might know that the Dart VM C API is largely reflective in nature: it
> allows you to look up libraries, classes and members by their names. It allows
> you to invoke methods and set fields indirectly. That why
> `@pragma('vm:entry-point')` exists - and that is why you are required to
> place it on entities which are accessed from outside of Dart.

## `const`

Let me change gears for a moment and discuss Dart's `const` and its limitations.
This feature gives you just enough power at compile time to:

- construct objects (via `const` constructors),
- create constant list and map literals,
- perform arithmetic on `int` and `double` values
- perform logical operations on `bool` values
- compare primitive values
- ask the `length` of a constant `String`

Exhaustive list is given in section 17.3 of
[Dart Programming Language Specification](https://spec.dart.dev/DartLangSpecDraft.pdf)
and even though the description occupies 5 pages the sublanguage it defines is
very small and excludes a lot of expressions which feel like they should
actually be included. It just feels wrong that `const x = [].length` is invalid
while `const x = "".length` is valid. For some seemingly arbitrary reason
`String.length` is the only blessed property which can be accessed in a
constant expression. You can't write `[for (var i = 0; i < 10; i++) i]` and so
on.

Consider
[the following code](https://github.com/dart-lang/sdk/blob/b7178c2b58502f383fcb10a1f0fd0d96a8d354f1/sdk/lib/_internal/vm/lib/convert_patch.dart#L1010-L1039)
from `dart:convert` internals:

````dart
static const int CHAR_SIMPLE_STRING_END = 1;
static const int CHAR_WHITESPACE = 2;

/**
 * [_characterAttributes] string was generated using the following code:
 *
 * ```
 * int $(String ch) => ch.codeUnitAt(0);
 * final list = Uint8List(256);
 * for (var i = 0; i < $(' '); i++) {
 *   list[i] |= CHAR_SIMPLE_STRING_END;
 * }
 * list[$('"')] |= CHAR_SIMPLE_STRING_END;
 * list[$('\\')] |= CHAR_SIMPLE_STRING_END;
 * list[$(' ')] |= CHAR_WHITESPACE;
 * list[$('\r')] |= CHAR_WHITESPACE;
 * list[$('\n')] |= CHAR_WHITESPACE;
 * list[$('\t')] |= CHAR_WHITESPACE;
 * for (var i = 0; i < 256; i += 64) {
 *   print("'${String.fromCharCodes([
 *         for (var v in list.skip(i).take(64)) v + $(' '),
 *       ])}'");
 * }
 * ```
 */
static const String _characterAttributes =
    '!!!!!!!!!##!!#!!!!!!!!!!!!!!!!!!" !                             '
    '                            !                                   '
    '                                                                '
    '                                                                ';
````

It feels strangely limiting that the only way to update this constant is to
modify the comment above it, copy that comment into a temporary file, run it and
paste the output back into the source. What we really want is to define
`_characterAttributes` in the following way:

```dart
static const int CHAR_SIMPLE_STRING_END = 1;
static const int CHAR_WHITESPACE = 2;

static const String _characterAttributes = _computeCharacterAttributes();

static String _computeCharacterAttributes() {
  int $(String ch) => ch.codeUnitAt(0);
  final list = Uint8List(256);
  for (var i = 0; i < $(' '); i++) {
    list[i] |= CHAR_SIMPLE_STRING_END;
  }
  list[$('"')] |= CHAR_SIMPLE_STRING_END;
  list[$('\\')] |= CHAR_SIMPLE_STRING_END;
  list[$(' ')] |= CHAR_WHITESPACE;
  list[$('\r')] |= CHAR_WHITESPACE;
  list[$('\n')] |= CHAR_WHITESPACE;
  list[$('\t')] |= CHAR_WHITESPACE;
  return String.fromCharCodes(list);
}
```

This requires the definition of a constant expression to be expanded to cover a
significantly larger subset of Dart than it currently includes. Such a feature
does however exist in other programming languages, most notably **C++**, **D**,
and **Zig**.

### C++

Originally, the metaprogramming facilities provided by **C++** were limited to
preprocessor macros and [template metaprogramming][cpp-tmp]. However, **C++11**
added [`constexpr`][cpp-constexpr] and **C++20** added
[`consteval`][cpp-consteval].

The following code is valid in modern **C++** and computes
`kCharacterAttributes` table in compile-time.

```cpp
constexpr uint8_t CHAR_SIMPLE_STRING_END = 1;
constexpr uint8_t CHAR_WHITESPACE = 2;

constexpr auto kCharacterAttributes = []() {
  std::array<uint8_t, 256> list {};
  for (int i = 0; i < ' '; i++) {
    list[i] |= CHAR_SIMPLE_STRING_END;
  }
  list['"'] |= CHAR_SIMPLE_STRING_END;
  list['\\'] |= CHAR_SIMPLE_STRING_END;
  list[' '] |= CHAR_WHITESPACE;
  list['\r'] |= CHAR_WHITESPACE;
  list['\n'] |= CHAR_WHITESPACE;
  list['\t'] |= CHAR_WHITESPACE;
  return list;
}();
```

> [!NOTE]
>
> **C++26** will most likely include [reflection][cpp-reflection] support which
> would allow the program to introspect and modify its structure in compile
> time. Reflection would allow programmer achieve results similar to those
> described in the next section about **D**. I am omitting it from discussion
> here because it is not part of the language _just yet_.

### D

**C++** example given above can be trivially translated to **D**, which also
supports [compile time function execution (CTFE)][dlang-ctfe].

```d
static immutable CHAR_SIMPLE_STRING_END = 1;
static immutable CHAR_WHITESPACE = 2;

static immutable ubyte[256] CharacterAttributes = () {
    ubyte[256] list;
    for (int i = 0; i < ' '; i++) {
      list[i] |= CHAR_SIMPLE_STRING_END;
    }
    list['"'] |= CHAR_SIMPLE_STRING_END;
    list['\\'] |= CHAR_SIMPLE_STRING_END;
    list[' '] |= CHAR_WHITESPACE;
    list['\r'] |= CHAR_WHITESPACE;
    list['\n'] |= CHAR_WHITESPACE;
    list['\t'] |= CHAR_WHITESPACE;
    return list;
}();
```

**D** however takes this further: it provides developer means to introspect and
modify the structure of the program itself in compile time. Introspection is
achieved via [traits][dlang-traits] and modifications are possible via
[templates][dlang-templates] and [template mixins][dlang-template-mixins].

Consider the following example which defines a template function `fmt` capable
of formatting arbitrary structs:

```d
string fmt(T)(T o)
{
    // T.stringof will return the name of a type
    string result = T.stringof ~ " { ";
    bool comma = false;

//  This foreach loop is expanded in compile time by copying
//  the body of the loop for each element of the aggregate
//  and substituting memberName with the corresponding constant.
//  vvvvvvvvvvvvvv
    static foreach (memberName; [__traits(allMembers, T)])
    //                                    ^^^^^^^^^^
    // Trait allMembers returns names of all members of T
    // as sequence of string literals.
    {
        if (comma)
            result ~= ", ";
        result ~= memberName ~ ": "
        result ~= fmt(__traits(getMember, o, memberName));
        //                     ^^^^^^^^^
        // Trait getMember allows to construct member access
        // expression o.memberName - memberName has to be
        // a compile time constant string.
        comma = true;
    }
    result ~= "}";
    return result;
}

string fmt()(int o)
{
    return format("%d", o);
}

string fmt()(string o)
{
    return o;
}

struct Person {
  string name;
  int age;
}

write(fmt(Person("Nobody", 42))); // Person { name: Nobody, age: 42 }
```

When you instantiate `fmt!Person` compiler effectively produces the following
code

```d
// Specialization of fmt for a Person.
string fmt!Person(Person o)
{
    // T.stringof will return the name of a type
    string result = "Person" ~ " { ";
    bool comma = false;
    {
        if (comma)
            result ~= ", ";
        result ~= "name" ~ ": "
        result ~= fmt(o.name);
        comma = true;
    }
    {
        if (comma)
            result ~= ", ";
        result ~= "age" ~ ": "
        result ~= fmt(o.age);
        comma = true;
    }
    result ~= "}";
    return result;
}
```

See [Compile-time vs. compile-time][dlang-compiletime] for an introduction into
**D**'s compile-time metaprogramming.

### Zig

**Zig** metaprogramming facilities are centered around
[`comptime`][zig-comptime] - a modifier which requires variable to be known at
compile-time. **Zig** elevates types to be first-class values, meaning that you
can put type into a variable or write a function which transforms one type into
another type, but requires that types are only used in expressions which can be
evaluated in compile-time.

While **Zig**'s approach to types is fairly unique, the core of its
metaprogramming facilities is strikingly similar to **D**:

- A number of builtin functions are provided which allow program to interact
  with the compiler as it is being compiled. For example, **Zig**'s
  `std.meta.fields(@TypeOf(o))` is equivalent of **D**'s
  `__traits(allMembers, T)`, while `@field(o, name)` is equivalent of
  `__traits(getMember, o, name)`.
- A number of constructs are provided to facilitate compile-time specialization,
  e.g. **Zig**'s `inline for` is expanded in compile time just like **D**'s
  `static foreach`.

Here is an example which implements a generic function `print`, similar to
generic `fmt` we have implemented above:

```zig
const std = @import("std");
const builtin = @import("builtin");

// anytype is a placeholder for a type, asking compiler to
// infer type at callsite.
//              vvvvvvv
pub fn print(o: anytype) void {
    const t: type = @TypeOf(o);
    //              ^^^^^^^
    // @TypeOf is a builtin function which returns type
    // of an expression.


    // Types are values so you can just switch over them
    switch (t) {
        // Handle u8 and u8 slices
        u8 => std.debug.print("{}", .{o}),
        []const u8, []u8 => std.debug.print("{s}", .{o}),

        // Handle everything else
        else => switch (@typeInfo(t)) {
            .Struct => |info| {
                // @typeName provides name of the given type
                std.debug.print("{s} {{ ", .{@typeName(t)});
                var comma = false;

                // inline loops are expanded in compile time.
        inline for (info.fields) |field| {
                    if (comma) {
                        std.debug.print(", ", .{});
                    }
                    std.debug.print("{s}: ", .{field.name});
                    // @field allows to access a field by name known
                    // at compile time. @as performs a cast.
                    print(@as(field.type, @field(o, field.name)));
                    comma = true;
                }
                std.debug.print("}}", .{});
            },
            else => @compileError("Unable to format " ++ @typeName(t)),
        },
    }
}

const Person = struct {
    name: []const u8,
    age: u8,
};

pub fn main() !void {
    print(Person{ .name = "Nobody", .age = 42 });
}
```

### Dart and Platform-specific code

Dart's does not have a powerful compile time execution mechanism similar to
those described above. Or does it?

Consider the following chunk of code which one could write in their Flutter
application:

```dart
static Widget get _buttonText => switch (defaultTargetPlatform) {
    TargetPlatform.android => AndroidSpecificWidget(),
    TargetPlatform.iOS => IOSSpecificWidget(),
    TargetPlatform.fuchsia => throw UnimplementedError(),
  };
```

Developer compiling their application for Android would naturally expect that
the final build only contains `AndroidSpecificWidget()` and not
`IOSSpecificWidget()` and vice versa. This expectation is facing one challenge:
`defaultTargetPlatform` is not a simple constant - it is defined as result of a
computation. Here is its definition from Flutter
[internals][flutter-default-target-platform]:

```dart
platform.TargetPlatform get defaultTargetPlatform {
  platform.TargetPlatform? result;
  if (Platform.isAndroid) {
    result = platform.TargetPlatform.android;
  } else if (Platform.isIOS) {
    result = platform.TargetPlatform.iOS;
  } else if (Platform.isFuchsia) {
    result = platform.TargetPlatform.fuchsia;
  } else if (Platform.isLinux) {
    result = platform.TargetPlatform.linux;
  } else if (Platform.isMacOS) {
    result = platform.TargetPlatform.macOS;
  } else if (Platform.isWindows) {
    result = platform.TargetPlatform.windows;
  }
  assert(() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      result = platform.TargetPlatform.android;
    }
    return true;
  }());
  if (kDebugMode && platform.debugDefaultTargetPlatformOverride != null) {
    result = platform.debugDefaultTargetPlatformOverride;
  }
  if (result == null) {
    throw FlutterError(
      'Unknown platform.\n'
      '${Platform.operatingSystem} was not recognized as a target platform. '
      'Consider updating the list of TargetPlatforms to include this platform.',
    );
  }
  return result!;
}
```

None of `Platform.isX` values are `const`'s either: they are all getters on the
`Platform` class.

This seems rather wasteful: even though AOT compiler knows precisely which
platform it targets developer has no way of writing their code in a way that is
guaranteed to be tree-shaken based on this information. At least not within the
language itself - last year we have introduced support for two `@pragma`s:
`vm:platform-const-if` and `vm:platform-const` which allow developer to inform
the compiler that a function can and should be evaluated at compile time if
compiler knows the platform it targets.

These annotations were placed on all API surfaces in Dart and Flutter SDK which
are supposed to evaluate to constant when performing release builds:

```dart
// Dart SDK
abstract final class Platform {
  @pragma("vm:platform-const")
  static final pathSeparator = _Platform.pathSeparator;
  // ...
  @pragma("vm:platform-const")
  static final operatingSystem = _Platform.operatingSystem;

  @pragma("vm:platform-const")
  static final bool isLinux = (operatingSystem == "linux");

  // ...
}

// Flutter SDK
@pragma('vm:platform-const-if', !kDebugMode)
platform.TargetPlatform get defaultTargetPlatform {
  // ...
}
```

An implementation of this feature leans heavily on an earlier implementation of
`const-functions` [experiment][dart-const-functions]. This experiment never
shipped as a real language feature, but CFE's implementation of constant
evaluation was expanded to support significantly larger subset of Dart than
specification currently permits for `const` expressions, including imperative
loops, if-statements, `List` and `Map` operations.

## Static _Enough_ Metaprogramming for Dart

Let us first recap [History of `dart:mirrors`](#history-of-dartmirrors):
reflection posed challenges for Dart because it often makes code impossible to
analyze statically. The ability to analyze the program statically is crucial for
AOT compilation, which is the main deployment mode for Dart. Dart answer to this
was to shift metaprogramming from _run_ time to _(pre)build_ time by requiring
code generation: an incomplete program structure can be inspected via
[`analyzer`][pkg-analyzer] package and additional code can be generated to
complete the program. This way AOT compilers see a static program structure and
don't need to retain any reflective information.

To put it simply, we avoid reflection because our AOT compilers can't analyze it
and fold it away. Conversely, _if compiler could analyze and fold reflection
away we would not need to avoid it_. **Dart** could have its cake and eat it
too. **D**, **Zig** (and **C++26**) show us the path: we need to lean on compile
time constant evaluation to achieve that.

I propose we introduce a special metadata constant `konst` in the
`dart:metaprogramming` which would allow developer to request enhanced constant
evaluation at compile time _if the underlying compiler supports it_.

```dart
/// Forces Dart compiler which supports enhanced constant evaluation to
/// compute the value of the annotated variable at compile time.
const konst = pragma('konst');
```

> [!NOTE]
>
> The actual name `konst` is a subject to discussion and change. It can be
> `comptime`, `constexpr` or anything else. Concrete name is irrelevant and
> choosing a different name does not change the core of this proposal.
>
> I have chosen metadata instead of introducing a new keyword for pragmatic
> reasons - it does not require syntax changes.
>
> It is important to understand that concrete syntax is secondary, the
> capability is more important.

Applying `@konst` to normal variables and fields simply requests compiler to
compute their value at compile time:

```dart
@konst
static final String _characterAttributes = _computeCharacterAttributes();
// _computeCharacterAttributes() is evaluated at compile time if compiler
// supports it.
```

When `@konst` is applied to parameters (including type parameters) it turns
functions into _templates_: compiler will require that annotated parameter is a
constant known at compile time and clone the function for a specific combination
of parameters. The original function is removed from the program: it is
impossible to invoke it dynamically or tear it off. To annotate `this` as
`@konst` developer will need to place `@konst` on the declaration of the
function itself.

> [!IMPORTANT]
>
> Here and below we assume that _constant evaluator_ supports
> execution of functions (i.e. as implemented by `const-functions` language
> experiment) - rather than just a limited subset of Dart required by the
> language specification. This means `[1].first` and even
> `[1].map((v) => v + 1).first` can be folded to a constant when used in
> `@konst`-context.

```dart
class X {
  final int v;
  const X(this.v);

  @konst
  String fmt() => '$v';
}

void foo<@konst T>(@konst T value) {
  // ...
}

void bar(@konst String v) {
  foo(v);  // ok: T is String and v is @konst itself
}

foo(1);  // ok: T is int, value is 1
foo([1].first);  // OK: T is int, value is 1
bar('a'); // ok
const X(1).fmt(); // ok
X(1).fmt(); // ok

void baz(String v, X x) {
  foo(v);  // error: v is not a constant
  x.fmt();  // error: x is not a constant
}
```

When `@konst` is applied to loop iteration variables it instructs the compiler
to expand the loop at compile time by first computing the sequence of values for
that iteration variable, then cloning the body for each value in order and
substituting iteration variable with the corresponding constant.

```dart
void foo(@konst int v) {
  //
}

for (@konst final v in [1, 2, 3]) {
  foo(v);
}
// expands to: foo(1); foo(2); foo(3);
```

Generics introduce an interesting caveat though:

```dart
void bar<@konst T>(@konst T v) {

}

for (@konst final v in [1, '2', [3]]) {
  bar(v);
}
// expands to: bar<Object>(1); bar<Object>('2'); bar<Object>([3]);
// but what if developer wants specialization to a type?
```

We could expand `dart:metaprogramming` with a `typeOf(...)` helper:

```dart
/// Returns the type of the given object.
///
/// Note: similar to [Object.runtimeType] but will error if v is not a constant
/// and we are running in environment which supports @konst.
external Type typeOf(@konst Object? v);
```

But that does not solve the problem. Type arguments and normal values are
separated in Dart - which means you can't invoke a generic function with the
given `Type` value as type argument, even if `Type` value is a compile time
constant. To breach this boundary we need a helper which would allow us to
constructing function invocations during compile time execution.

For example:

```dart
external T invoke<T>(@konst Function f, List positional, {
  Map<String, Object?> named = const {},
  List<Type> types = const [],
});
```

> [!NOTE]
>
> `Function.apply` does not support passing type arguments to
> functions, but even if it did we would not want to use it here because we want
> to enforce compile time expansion of `invoke(...)` into a corresponding call
> or an error, if such expansion it not possible.

Combining `typeOf` and `invoke` yields expected result:

```dart
void bar<@konst T>(@konst T v) { }

for (@konst final v in [1, '2', [3]]) {
  invoke(bar, [v], types: [typeOf(v)]);
}
// expands to: bar<int>(1); bar<String>('2'); bar<List<int>>(3);
```

You might notice that `invoke` is a bit _wonky_: `f` is `@konst`, but neither
`position`, nor `named`, nor `types` are. Why is that? Well, that's because
`invoke` tries to capture expressivity of a normal function call site: each call
site has constant _shape_ (e.g. known number of positional and type arguments,
known names for named arguments), but actual arguments are not required to be
constant. Dart's type system does not provide good tools to express this, `List`
and `Map` don't have their shape (e.g. length or keys) as part of their type.

This unfortunately means that compiler needs to be capable of figuring out the
_shape_ of lists and maps that flow into `invoke`. Consider for example that we
might want to construct argument sequence imperatively:

```dart
void invokeBar(Map<String, Object> values) {
  final named = <String, Object?>{};
  for (@konst final k in ['a', 'b']) {
    named[k] = values[k];
  }
  invoke(bar, [], named: named); // expands to bar(a: input['a'], b: input['b'])
}
```

Should this code compile? Maybe we could limit ourselves to supporting only
collection literals as arguments to `invoke`:

```dart
void invokeBar(Map<String, Object> values) {
  invoke(bar, [], named: {
    for (@konst final k in ['a', 'b'])
      k: input['k'],
  });
  // expands to bar(a: input['a'], b: input['b'])
}
```

### `@konst` reflection

Features described above lay the foundation of compile time metaprogramming, but
for it to be complete we need to expose more information about the structure of
the program.

For example (these are not exhaustive or exact):

```dart
// dart:metaprogramming

final class TypeInfo<T> {
  const TypeInfo._();

  /// Obtain `TypeInfo` for the given type `T`.
  external static TypeInfo<T> of<@konst T>();

  /// Is `T` nullable?
  @konst external bool isNullable;

  /// Erase nullability of `T` if it is nullable.
  @konst external TypeInfo<T> get nonNullable;

  /// Return underlying type `T`.
  @konst external Type type;

  /// Check if `T` is subtype of `Base`.
  @konst external bool isSubtypeOf<@konst Base>();

  /// Find instantiation of `Base` in supertypes
  /// of `T` and return the corresponding `TypeInfo`.
  @konst external TypeInfo<Base>? instantiationOf<@konst Base>();

  /// Return type-arguments of `T` if any.
  @konst external List<TypeInfo> get typeArguments;

  /// Return `T` default constructor.
  @konst external Function defaultConstructor;

  /// Return the list of fields in `T`.
  @konst external List<FieldInfo<T, Object?>> get fields;
}

/// Information about the field of type [FieldType] in the
/// object of type [HostType].
final class FieldInfo<HostType, FieldType> {
  const FieldInfo._();

  @konst external String get name;

  @konst external bool get isStatic;

  @konst external TypeInfo<FieldType> get type;

  /// Get the value of this field from the given object.
  @konst external FieldType getFrom(HostType value);
}
```

Note that all methods are annotated with `@konst` so if the compiler supports
`@konst` these must be invoked on constant objects and will be folded away -
compiler does not need to store any information itself.

> [!NOTE]
>
> `dart:mirrors` allows developer to ignore privacy, enumerate and access
> private fields and methods. However Dart VM does mark `dart:*` classes
> as non-reflectable. Similar approach should be probably taken with compile
> time reflection: `FieldInfo.getFrom` should ignore privacy unless target
> is marked as non-reflectable.

#### It's a spectrum of choice

I have intentionally avoided saying that `@konst` has to be a language feature
and that any Dart implementation needs to support compile time constant
evaluation of `@konst`. I think we should implement this as a toolchain feature, similar to how `platform-const` is implemented.

For example, a native JIT or DDC (development mode JS compiler) could simply
implement `TypeInfo` on top of runtime reflection. This way developer can debug
their reflective code as if it was any other Dart code. A deployment compiler
(native, Wasm or JS) can then fold the cost of reflection away by enforcing
const-ness requirements implied by `@konst` and folding away reflective
operations.

> [!NOTE]
>
> A deployment compiler can even choose between producing specialized
> code by cloning and specializing functions with `@konst`-parameters _or_ it
> could choose to retain reflective metadata and forego cloning at the cost of
> runtime performance. This reduces the size of deployed applications but
> decreases peak performance.

There are multiple reasons for going this route. First of all, I believe that
this allows to considerably simplify the design and implementation of this
feature. But there is another reason for this: _you can't actually perform
compile time evaluation without knowing compile time environment_. Consider for
example the following code:

```dart
void foo(@konst String id) {
  if (id.length != 10) {
    throw 'Incorect value for $id';
  }

  // Do various things with id.
}

void bar() {
  foo(const String.fromEnvironment('some.define'));
}
```

Dart Analyzer can't really say what happens here because it does not know
a specific value of `id` - the value is only known when compiling. The example
can be made even more complicated by adding dependency on various platform
specific defines (e.g. to distinguish between target platforms and specialize
for them).

Fundamentally this means that _compiling_ an application can reveal compile
time error which are not revealed by running Dart analyzer on the same code.
Furthermore compiling for different platforms can reveal different errors.

The fact that these errors surface in compile time is an intrinsic property
of this proposal - and is a direct consequence of its powerful ability to
specialize code based on the compile time computation. It can't be fully
avoided for the reasons which are explained above - though we could eventually
_choose_ to implement subset of this proposal in analyzer as well and surface
some of the errors earlier. However I currently don't see direct analyzer
support as a necessary requirement to shipping this feature.

> [!NOTE]
>
> If we decide that `@konst` is a no-op in debug (development) mode and
> `@konst` reflection falls back to actual reflection then it is reasonable
> to expect that developer could still opt-in into full `@konst` evaluation
> for debug (development) mode. This is important to enable testing this code
> without forcing developers to build their code in release mode.

> [!NOTE]
>
> Some of our tools (most notably analyzer and DDC) are capable of
> analyzing/compiling libraries only given the _outlines_ of their dependencies.
> This was one of the showstoppers for enhanced constant proposal, which did not
> introduce a syntactic marker to delineate code potentially needed for
> `const`-evaluation from the rest of the program, which would mean that
> outlines had to contain bodies for most methods - making them impractically
> large and erasing their benefits.
>
> One possible way to address this issue is to separate imports into two
> categories: imports that only provide outline (default) and imports that
> provide full libraries. It then becomes a compile time error if you attempt
> to evaluate a call and corresponding method is coming from "outline-only"
> import.

#### Non-Goals

This proposal does _not_ intend to cover all cases which are supportable via
Dart source code generation or which are supported by macro systems in other
programming languages. For example the following capabilities are out of scope:

- injecting new declarations into the program;
- changing or expanding Dart syntax.

This means that certain things are not possible with this proposal which are
possible with code generation. Most notably it is not possible to declare
fields, methods or parameters. This means for example that it is impossible
to use `@konst` to inject a `copyWith` method based on the list of fields.

#### Applicability

Let's consider a number of motivational use cases considered during `macros`
development.

##### auto constructor

Not directly applicable. Can't declare a constructor out of the list of fields
or declare parameters based on the list of fields.

FWIW this use case might not be as relevant if Dart has primary constructors.

##### `hashCode`, `==`

Applicable. Allows you to write a generic function
`int hashCodeOf<@konst T>(T self)`. Can also make a mixin for better ergonomics.

See [example](#example-defining-hashcode-and-) below.

##### `copyWith`

Not directly applicable because you can't synthesize parameter list.

It is however possible to define method like this:

```dart
// Universal function to apply updates specified by the record.
T copyWith<@konst T, @konst R extends Record>(T obj, R updates) {
   // ...
}
```

Though usability of this method will be questionable as there will be no good
autocomplete available for `updates` parameter.

##### data class

Mostly applicable. Given normal complete class declaration `@konst` can be used
to synthesize most of the boilerplate methods: `operator==`, `get hashCode`,
`toString`, serialization and deserialization support.

Can't synthesize constructor or `copyWith`.

##### (de)serialization

Applicable. See [JSON example](#example-synthesizing-json-serialization) below.

> [!NOTE]
>
> We should consider if `@konst` reflection should have a capability to
> construct instances from the list of field values bypassing constructors.
>
> Consider for example something like this:
>
> ```dart
> class Foo {
>   final String x;
>   final int y;
>
>   // Empty external constructor.
>   external Foo._();
> }
>
> /// Construct an instance of `T` using values from `r`.
> T construct<@konst T>(Record r);
>
> Foo f = construct<Foo>((x: '', y: 10));
> ```


##### json serializable

Applicable.

##### field validation

Not directly applicable. But can be coupled with
[property wrappers](http://go/dart-property-wrappers) to achieve this.

##### Server side routing

Applicable. You can build routing table at compile time by iterating methods.

##### ORM

Applicable.

##### observable fields

Not directly applicable. But can be coupled with
[property wrappers](http://go/dart-property-wrappers) to achieve this.

One possible extension here is allowing interplay between constant evaluation
and method forwarding

```dart
class A {
  external int foo;
}

// Which is basically
class A {
  int get foo => noSuchMethod(Invocation(...));
  set foo(int v) => noSuchMethod(Invocation(...));
}

// Could actually be more like:

class A {
  int get foo => A.resolve(#foo)(receiver: this, args: []);
  set foo(int v) => A.resolve(#foo)(receiver: this, args: [v]);
}

// And developer could do:
class A {
  int get foo => A.resolve(#foo)(receiver: this, args: []);
  set foo(int v) => A.resolve(#foo)(receiver: this, args: [v]);

  R Function({A receiver, ...}) resolve<@konst R>(@konst Symbol method) {
    // ...
  }
}
```

But maybe this gets too complicated and something less generic (property
wrappers) is better.

##### Proxy classes

Not directly applicable because we can't create new classes using this proposal.

That being said we could consider a reflective capability to declare an
anonymous class from a list of methods, e.g. something along the lines of:

```dart
Class<Base> createClass<@konst Base>(@konst Map<String, Function> methods);
```

Such capability can then be used to implement proxy classes.

##### js_wrapping

Not directly applicable.

##### auto dispose

Partially applicable. Can be used to synthesize `dispose` body.

##### functional widget

See this [package][package-functional-widget] for context.

Not directly applicable, though might be covered if we allow to
create anonymous classes (see [Proxy classes](#proxy-classes) section).

##### stateful widget/state boilerplate

Similar to [the previous section](#functional-widget) to make this proposal
applicable we need some way to allow injecting new classes into the program.

##### union types (ala freezed)

TODO: unclear what this means.

##### auto listenable

TODO: unclear what this means.

##### render accessors

TODO: unclear what this means.

##### angular

Not applicable.

##### template languages

Not applicable.

##### mockito

Not applicable.

##### analytics

TODO: what does this mean?

##### flutter widget transformer

Not applicable.

##### protos

Not applicable.

#### pigeon

Not applicable

##### DI

I think applicable to statically resolvable DI variants where constructors
are threaded through from the root of the application.

#### Prototype implementation

To get the feeling of expressive power, implementation complexity and costs I
have thrown together a very rough prototype implementation which can be found
[here][konst-prototype-branch]. When comparing manual toJSON implementation with
a similar (but not equivalent!) one based on `@konst` reflection I got the
following numbers:

- Average code size overhead per class: 270 bytes
- Average JIT kernel generation overhead per-class: 0.2ms (cost of producing
  specialized functions using Kernel-to-Kernel AST transformation)
- Average AOT compilation overhead per-class: 2.6ms

I think the main difference between manual and reflective implementations is
handling of nullable types and lists. Manual implementation inlined both - while
reflective leaned on having helper methods for these. I will take a closer look
at this an update this section accordingly.

#### Example: Synthesizing JSON serialization

> [!NOTE]
>
> These are toy examples to illustrate the capabilities rather than full
> fledged competitor to `json_serializable`. I have written this code to
> experiment with the prototype implementation which I have concocted in a very
> limited time frame.

##### `toJson<@konst T>`

```dart
Map<String, Object?> toJson<@konst T>(T value) => {
    for (@konst final field in TypeInfo.of<T>().fields)
      if (!field.isStatic) field.name: field.getFrom(value),
  };
```

```dart
// Example
class A {
  final int a;
  final String b;
  A({required this.a, required this.b});
}

// Calling toJson<A>(A(...)) produces specialization
Map<...> toJson$A(A value) => {a: value.a, b: value.b};
```

##### `fromJson<@konst T>`

```dart
T fromJson<@konst T>(Map<String, Object?> json) {
  final typeInfo = TypeInfo.of<T>();
  return invoke<T>(
        typeMirror.defaultConstructor,
        [],
        named: {
          for (@konst final field in typeInfo.fields)
            if (!field.isStatic)
              field.name: invoke(
                _valueFromJson,
                [json[field.name]],
                types: [field.type.type],
              ),
        },
      );
}

FieldType _valueFromJson<@konst FieldType>(Object? value) {
  var fieldType = TypeInfo.of<FieldType>();
  if (fieldType.isNullable) {
    if (value == null) {
      return null as FieldType;
    }
    fieldType = fieldType.nonNullable;
  } else {
    if (value == null) {
      throw ArgumentError('Field not found in incoming json');
    }
  }

  // Primitive values are mapped directly.
  if (fieldType.isSubtypeOf<String>() ||
      fieldType.isSubtypeOf<num>() ||
      fieldType.isSubtypeOf<bool>()) {
    return value as FieldType;
  }

  // Lists are unpacked element by element.
  if (fieldType.instantiationOf<List>() case final instantiation?) {
    final elementType = instantiation.typeArguments.first.type;
    return invoke<FieldType>(
          listFromJson,
          [value as List<Object?>],
          typeArguments: [elementType],
        );
  } else {
    // We assume that this is Map -> class conversion then.
    return fromJson<FieldType>(value as Map<String, Object?>);
  }
}

List<E> _listFromJson<@konst E>(List<Object?> list) {
  return <E>[for (var v in list) _valueFromJson<E>(v)];
}
```

```dart
// Example
class A {
  final int a;
  final String b;
  A({required this.a, required this.b});
}

// Calling fromJson<A>({...}) produces specializations:

A fromJson$A(Map<String, Object?> map) {
  return A(
    a: _valueFromJson$int(map['a']),
    b: _valueFromJson$String(map['a']),
  );
}

int _valueFromJson$int(Object? value) {
  if (value == null) {
    throw ArgumentError('Field not found in incoming json');
  }
  return value as int;
}

String _valueFromJson$String(Object? value) {
  if (value == null) {
    throw ArgumentError('Field not found in incoming json');
  }
  return value as String;
}
```

#### Example: Defining `hashCode` and `==`

We could also instruct the compiler to handle `mixin`'s (and possibly all
generic classes) with `@konst` type parameters in a special way: _clone_ their
declarations with known type arguments. This would allow to write the following
code:

```dart
mixin DataClass<@konst T> {
  @override
  operator ==(Object? other) {
    if (other is! T) {
      return false;
    }

    final typeInfo = TypeInfo.of<T>();
    for (@konst final field in typeInfo.fields) {
      final value1 = field.getFrom(this as T);
      final value2 = field.getFrom(other);
      if (field.type.isSubtypeOf<List>()) {
        if ((value1 as List).length != (value2 as List).length) {
          return false;
        }
        for (var i = 0; i < value1.length; i++) {
          if (value1[i] != value2[i]) {
            return false;
          }
        }
      } else if (value1 != value2) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    final typeInfo = TypeInfo.of<T>();
    var hash = HashHelpers._seed;
    for (@konst final field in typeInfo.fields) {
      hash = HashHelpers.combine(hash, field.getFrom(this as T).hashCode);
    }
    return HashHelpers.finish(hash);
  }

  Map<String, Object?> toJson() => toJsonImpl<T>(this as T);
}
```

```dart
// Example
class A with DataClass<A> {
  final int a;
  final String b;
  // ...
}

// Bodies of members in DataClass<A> are copied and specialized for a known
// value of T. This means A automatically gets definitions of operator== and
// get hashCode in terms of its fields.
```

## Changelog

### 1.0 - May 16, 2025

* Initial version

<!-- References -->

[r8-troubleshooting]: https://r8.googlesource.com/r8/+/refs/heads/master/compatibility-faq.md#troubleshooting
[paper-miao-siek]: https://dl.acm.org/doi/abs/10.1145/2543728.2543739
[paper-reflekt]: https://arxiv.org/pdf/2202.06033
[paper-java-suif-reflection]: https://suif.stanford.edu/papers/aplas05r.pdf
[paper-java-reflection-2019]: https://arxiv.org/pdf/1706.04567
[paper-java-reflection-challenges]: https://core.ac.uk/download/pdf/301639072.pdf
[java-native-image-reflection]: https://www.graalvm.org/22.1/reference-manual/native-image/Reflection/
[the-fear-of-dartmirrors]: https://mrale.ph/blog/2017/01/08/the-fear-of-dart-mirrors.html
[dart-mirrors]: https://api.dart.dev/stable/latest/dart-mirrors/index.html
[dart-mirrors-1-21-1]: https://api.dartlang.org/stable/1.21.1/dart-mirrors/dart-mirrors-library.html
[dart-mirrors-reflect]: https://api.dart.dev/stable/latest/dart-mirrors/reflect.html
[dart-mirrors-type]: https://api.dart.dev/stable/latest/dart-mirrors/InstanceMirror/type.html
[dart-mirrors-declarations]: https://api.dart.dev/stable/latest/dart-mirrors/ClassMirror/declarations.html
[dart-mirrors-parameters]: https://api.dart.dev/stable/latest/dart-mirrors/MethodMirror/parameters.html
[dart-mirrors-used]: https://api.dart.dev/stable/1.17.0/dart-mirrors/MirrorsUsed-class.html
[flutter-default-target-platform]: https://github.com/flutter/flutter/blob/39b4951f8f0bb7a32532ee2f67e83a783b065b58/packages/flutter/lib/src/foundation/_platform_io.dart#L12-L46
[dart-const-functions]: https://github.com/dart-lang/sdk/tree/dd93f6fae0bb246adebbe86158b2eecd653699ac/tests/language/const_functions
[pkg-reflectable]: https://github.com/google/reflectable.dart
[pkg-analyzer]: https://pub.dev/packages/analyzer
[pkg-smoke]: https://github.com/dart-archive/smoke
[java-reflect]: https://docs.oracle.com/en/java/javase/22/docs/api/java.base/java/lang/reflect/package-summary.html
[android-shrink-code]: https://developer.android.com/build/shrink-code#keep-code
[cpp-tmp]: https://en.wikibooks.org/wiki/C%2B%2B_Programming/Templates/Template_Meta-Programming
[cpp-constexpr]: https://en.cppreference.com/w/cpp/language/constexpr
[cpp-consteval]: https://en.cppreference.com/w/cpp/language/consteval
[cpp-reflection]: https://isocpp.org/files/papers/P2996R4.html
[dlang-ctfe]: https://dlang.org/spec/function.html#interpretation
[dlang-template-mixins]: https://dlang.org/spec/template-mixin.html
[dlang-templates]: https://dlang.org/articles/templates-revisited.html
[dlang-traits]: https://dlang.org/spec/traits.html
[dlang-compiletime]: https://wiki.dlang.org/Compile-time_vs._compile-time
[zig-comptime]: https://ziglang.org/documentation/master/#toc-comptime
[konst-prototype-branch]: https://github.com/mraleph/sdk/tree/static_enough_reflection
[std-source-location]: https://en.cppreference.com/w/cpp/utility/source_location
[package-functional-widget]: https://pub.dev/packages/functional_widget
