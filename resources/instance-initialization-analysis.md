Users have long asked for a lighter notation to define a class with some fields
and a constructor that initializes them. Sometimes, they ask for full "data
classes", meaning that's basically *all* the class contains. But often they
simply want a simpler syntax for declaring fields and their constructor
initializers on a regular user-defined class.

The challenge is that there are many many things that field declarations,
constructors, and constructor parameters may need to specify:

*   Is the constructor `const` or not? Is it named?
*   Is there a `super()` initializer? Initializer list?
*   Is there a constructor body?
*   Is the field `final` or mutable? `late`? Does it `@override` a supertype
    getter?
*   Is the parameter named or positional, required or optional? Does it have a
    default value?

## Corpus analysis

It's unlikely that any syntactic sugar can cover *all* of these cases, so to
make some patterns look better, we need to optimize for the most common ones. To
that end, I scraped a corpus of 2,000 pub packages (7,116,622 lines in 51,038
files) to look at how they define and initialize their fields:

```
-- Constructor type (69447 total) --
  39003 ( 56.162%): non-const          ========================
  16254 ( 23.405%): non-const factory  ==========
  13341 ( 19.210%): const              ========
    849 (  1.223%): const factory      =
```

Most constructors are not `const`, but `const` and `factory` do show up fairly
often.

```
-- Constructor name (69447 total) --
  45911 ( 66.109%): unnamed  ==================================
  23536 ( 33.891%): named    ==================
```

Unnamed constructors are twice as common as named constructors.

```
-- Non-factory body (52344 total) --
  44862 ( 85.706%): ;           ==========================================
   7064 ( 13.495%): {...}       =======
    418 (  0.799%): {} (empty)  =
```

Of generative constructors, more than 4/5ths do not have a body. This was
pretty surprising to me.

```
-- Super initializer (24633 total) --
  19489 ( 79.117%): has super()  ======================================
   5144 ( 20.883%): none         ==========
```

4/5 of constructors do have a superclass initializer in the constructor list.
Not too surprising given how many classes in modern Dart code are Flutter
widgets that need to forward `key` to the base class.

```
-- Constructor parameters (69447 total) --
  26920 ( 38.763%): only positional parameters                          ====
  25700 ( 37.007%): only named parameters                               ===
  10631 ( 15.308%): no parameters                                       ==
   3810 (  5.486%): both positional and named parameters                =
   1638 (  2.359%): only optional positional parameters                 =
    748 (  1.077%): both positional and optional positional parameters  =
```

Looking at the constructor parameter lists, we see a variety of styles. Most
have either all positional parameter or all named parameters with roughly equal
numbers of each. The latter are typically Flutter widgets and the former are
"vanilla" Dart classes.

```
-- Field initialization (188115 total) --
 103520 ( 55.030%): `this.` parameter                                    ====
  37620 ( 19.998%): not initialized                                      ==
  34274 ( 18.220%): at declaration                                       ==
   8710 (  4.630%): initializer list                                     =
   3196 (  1.699%): `this.` parameter, initializer list                  =
    675 (  0.359%): `this.` parameter, at declaration                    =
    112 (  0.060%): at declaration, initializer list                     =
      8 (  0.004%): `this.` parameter, at declaration, initializer list  =
```

This looks at the instance fields in a class and how they are initialized. It
doesn't look at assignments to fields in methods or the constructor body. It's
only looking to see if a field is initialized at its declaration, using a
`this.`-style parameter in the constructor list, or in a constructor initializer
list. A field may be initialized in multiple ways since classes can have
multiple constructors.

Also a little suprising to me. More than half of all fields are initialized
*solely* using `this.` parameters. Initializer lists are fairly rare. I
suspected that many of the field initializers in initializer lists were to
initialize a private field with a named parameter without the `_`, so I looked
at the initializing expressions:

```
-- Fields in initializer lists (13760 total) --
   9768 ( 70.988%): other            ===============================
   2420 ( 17.587%): _field = field   ========
   1572 ( 11.424%): field = literal  =====
```

So, yes, it's the most common specific reason for initializing a field in the
initializer list that I could recognize, but all sorts of expressions appear
there.

```
-- Field mutability (187575 total) --
  97385 ( 51.918%): final       =========================
  69715 ( 37.166%): var         ==================
  11263 (  6.005%): late        ===
   9212 (  4.911%): late final  ===
```

A little more than half of instance fields are `final`. Not too surprising since
it plays nice with Flutter's immutable reactive model and "Effective Dart"
recommends it.

```
-- Constructor count (70913 total) --
  22313 ( 31.465%): 0   ==================
  35526 ( 50.098%): 1   =============================
   9269 ( 13.071%): 2   ========
    986 (  1.390%): 3   =
   2518 (  3.551%): 4   ==
    136 (  0.192%): 5   =
     44 (  0.062%): 6   =
     33 (  0.047%): 7   =
     15 (  0.021%): 8   =
      6 (  0.008%): 9   =
     25 (  0.035%): 10  =
      4 (  0.006%): 11  =
      6 (  0.008%): 12  =
      6 (  0.008%): 13  =
      4 (  0.006%): 14  =
      4 (  0.006%): 15  =
      5 (  0.007%): 16  =
      3 (  0.004%): 17  =
      2 (  0.003%): 18  =
      2 (  0.003%): 19  =
      1 (  0.001%): 20  =
      2 (  0.003%): 21  =
      1 (  0.001%): 28  =
      1 (  0.001%): 68  =
      1 (  0.001%): 81  =
```

Most classes only define a single constructor. About a third of classes have
no constructor at all. They either rely on the default constructor or are
abstract classes that are either used as interfaces or static namespaces.

(The class with 81 constructors is StreamSvgIcon from stream_chat_flutter, one
for each of a large number of pre-defined icons with constructor parameters to
color and scale the icon.)

## Opinion

My impression from looking at the numbers is that we could cover a fairly large
number of classes if we aimed for:

*   Classes that define a single constructor.

*   Where all the fields can be initialized from `this.` parameters (or possibly
    at the field declaration).

*   But it has to support both positional and named parameters.

*   Supporting const constructors would be good but not necessary.

*   Likewise we can get far with just unnamed constructors, but named is pretty
    useful.

*   Some ability to call the superclass constructor is necessary, though I think
    [`super.`](https://github.com/dart-lang/language/issues/1855) would mostly
    solve this.

Script: https://gist.github.com/munificent/58a73182ca3aee6ed37a06ca2f33fc63
