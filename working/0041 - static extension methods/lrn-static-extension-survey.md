# Scoped Static Extension Methods Survey

[lrn@google.com](mailto:lrn@google.com)


# Background

Dart 2 has a design that makes it very hard to change an API, and while `.`-chain notation is convenient, it breaks down if you have to call static methods instead of instance methods.

_Scoped static extension methods_ is a language feature which introduces static methods that can be called as if they were instance methods (improved syntax) based on the static type of the receiver expression (static dispatch). The methods are only in scope if their declaration is (scoped).

There is a number of design choices that are not given from the above, and which have to be resolved before we can claim to have a full design for Dart.

We will look to other languages for inspiration, but Dart is fairly unique in having reified type arguments and _not_ having overloading on method signature. Solutions that work for other languages may not fit Dart as well.


# Other Languages

A number of other languages have something that can be described as static extension methods.


## C#

C# [Static extension methods](https://docs.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/extension-methods) were introduced in C# 3.0


> Extension methods are defined as static methods but are called by using instance method syntax. Their first parameter specifies which type the method operates on, and the parameter is preceded by the `this` modifier. Extension methods are only in scope when you explicitly import the namespace into your source code with a `using` directive.

Every declaration in C# must be inside a class, even static declarations. An example static extension method declaration could be:


```c#
public static class IntExtensions
{
    public static bool IsEven(this int i)
    {
       return ((i % 2) == 0);
    }
}
```


This declaration introduces the `IsEven` extension method on expression with type `int`, so you can write:


```c#
int x = 42;
if (x.IsEven()) Console.WriteLine("Yep!");
```


Extension methods can be put on any type, including basic types/structs (non-reference types).


### Resolution

An invocation like `x.IsEven()` first checks if the type of `x` declares a compatible `IsEven()` method, using all the normal coercions allowed for instance method overloading resolution. If one exists, it is called. If not, the compiler then checks if there is one or more static extension method declarations in scope which matches the receiver type. If there is more than one match, the best (most specific) match is chosen, similarly to how overloaded methods are selected. If there is still more than one option, it's a compile time error.

An extension method is in scope if the class containing it is.

You can still call the static function normally, as `IntExtensions.isEven(42)`.

C# has overloading on signatures, so conflict only happens for declarations with the same number of arguments and overlapping parameter types.

Letting an interface method take precedence over an extension method avoids introducing a conflict or change when you add an extension method when the interface method already exists (likely on a subclass of the extended class, otherwise the extension wouldn't be useful at all).

That is: You can't break existing functioning code by adding an extension method (well, unless the code already uses extension methods, but at the time extension methods were introduced, it was safe).


### Generics/Nullability

Extension methods can be generic, and the receiver can be nullable if it's a value type.


```c#
public static bool IsLessThan<T>(this IList<T> one, T other)
{ 
    return Nullable.Compare(one, other) < 0; 
}
public static T? print<T>(this T? input) where T : struct
{
    String output = "null";
    if (input != null) output = input.ToString();
    Console.WriteLine(output);
    return input;
}
public static T print<T>(this T input) 
{
    Console.WriteLine(input.ToString());
    return input;
}
```


Since C# implements generics by specialization for value types and it reifies the type for reference types, the type `T` here will be the actual type of the receiver.

Only non-nullable value types (not reference types) can be made "nullable".


## Swift

Swift have [class extensions](https://docs.swift.org/swift-book/LanguageGuide/Extensions.html), which are not necessarily just _static_.

Swift extensions can add instance methods, type (static) methods and initializers (constructors).

They can add computed instance properties (getters) and computed type properties (static getters) and subscripts (`[]` and `[]=` operators). They can add _nested types_ and make an existing type conform to a protocol (implement an interface) either by just introducing a protocol that the class already satisfies, or by adding the necessary members as well.

An extension method on a struct can be _mutating_ (allows modification or assignment to "self", restricting the receiver to be an assignable expression).


### Resolution

Resolution/[dispatch](https://www.raizlabs.com/dev/2016/12/swift-method-dispatch/) depends on the static type of the receiver and is always direct (static) dispatch. However, casting an object to a _protocol_ will create something that contains the statically determined extensions of the original object (like creating a class-specific wrapper or v-table for the protocol view of that particular class)

An extension on a class wins over an extension on a protocol. If two class or two protocols extensions are available, the more specific one wins.

An extension method on a specific type is not allowed to conflict with a declaration on the same type.

(Not sure if extensions are scoped).


### Generics/Nullability

It's possible to conditionally match an extension, for example to only add a protocol if the element type of a list satisfies a protocol.


```Swift
extension Array: TextRepresentable where Element: TextRepresentable {
    var textualDescription: String {
        let itemsAsText = self.map { $0.textualDescription }
        return "[" + itemsAsText.joined(separator: ", ") + "]"
    }
}
```


It may be possible to restrict extensions to nullable types.


## Kotlin

Kotlin's [static extensions](https://kotlinlang.org/docs/reference/extensions.html) are similar to C#'s.

The syntax for an extension method could be


```kotlin
fun <T> MutableList<T>?.swap(index1: Int, index2: Int) { ... }
```


You can declare extension properties (getters/setters) as well as extension on a class's _[companion objects](https://kotlinlang.org/docs/reference/object-declarations.html#companion-objects)_ (the object is used to represent the "class" and is a way to introduce static-like members).


### Resolution

Extensions are usually declared as top-level declarations, but can be declared in nested name-spaces. They apply if the declaration is in scope.

Extensions are statically dispatched, and if they have the same name and signature as an interface method, the interface method wins. 


### Generics/Nullability

Extensions can capture class type arguments, as shown above, but since generics are not reified, it will be using the type argument of the static receiver type, and it's only available at compile-time.

The receiver type can nullable, in which case `this` can be null inside the body.


## Rust

Rust does not have static extensions methods, but it has _[traits](https://blog.rust-lang.org/2015/05/11/traits.html)_ which are strictly more powerful.

You can specify a trait interface and then an implementation of that trait for a third-party class (with some restrictions, you have to be in control of either the trait or the type in order to assign a trait to a type). This allows the class to be used as if it has the trait methods as well (see, e.g., this [example](https://blog.dbrgn.ch/2015/5/25/rust-implementing-methods-on-builtins/)).

Conflicting trait member declarations (same name in multiple traits that all have implementations for the current receiver type) cause compile-time errors.

Generics are statically specialized away (like C++ template specialization), ensuring that trait invocations are static whenever the exact type is known, and only dynamic when a variable is only known to have the trait type. Rust does not have overloading, not even arity based, or nullable types.
