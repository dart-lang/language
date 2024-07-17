# Macro Host Notes

Notes about macro host (analyzer, CFE) implementations.

Some related discussion
[on issue 55784](https://github.com/dart-lang/sdk/issues/55784).

## Analyzer

1.  Build library cycles. Use imports and exports to form library cycles. Sort
    them topologically.
2.  With all dependency library cycles loaded (which means that we can ask them
    for elements with all types ready), take the next library cycle.
3.  Parse all user-written Dart files, create `LibraryBuilder` objects.
4.  Build `Element`s for all declarations - classes, methods, etc. Just
    elements, types are not known yet.
5.  Create the `LibraryMacroApplier` instance, fill `LibraryBuilder`s with
    `_MacroApplication`s. The order of the macro applications is defined by the
    specification.
6.  Run the types phase. Iterate over `LibraryBuilder`s, and run the types phase
    for macro applications. We get Dart code as output. Add library
    augmentations from these Dart code strings. Build elements for these library
    augmentations, just like (4). Look for more macro applications, just like
    (5).
7.  Build export scopes for `LibraryBuilder`s. This includes any user-written
    declarations, handling re-exports.
8.  Resolve `TypeAnnotation`s in all `LibraryBuilder`s.
9.  Run the declarations phase. Like (6), but not only build elements, and find
    new macro applications, but also resolve type annotations like (8). If new
    declarations are added, rebuild export scopes.
10. Run many other element linking steps - build synthetic constructors, enum
    constants, resolve constants, resolve metadata, perform type inference, etc.
11. Run the definitions phase. Like (9), still produce new library
    augmentations.
12. Dispose all macro applications, so free resources in the remote isolate.
13. Merge all macro results into single Dart code. Discard all transitory
    library augmentations, add the new, final one. Do not create new elements,
    not like (6) or (9), instead merge `ClassElement`s, update offsets, etc.
    These elements have everything ready in them - types, resolution for
    constants, etc. We don’t want to redo this work. And we cannot create new
    elements - there are already references to these elements in other parts of
    the element model.

## CFE

TODO
