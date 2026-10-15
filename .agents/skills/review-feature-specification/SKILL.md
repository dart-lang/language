---
name: review-feature-specification
description: >-
  Review a Dart language proposal, feature specification or changes to a
  proposal or feature spec.
---

# Instructions

Use this skill to review a Dart language proposal or feature specification
Markdown file (typically named `feature-specification.md`), or a change to one
(such as uncommitted local edits, a commit, or a pull request). If it's not
clear whether the user wants you to review the entire proposal or just a
specific change to it, check the version control state or ask them.

## Goals

You are helping make this proposal as valuable an addition to the Dart language
as possible. Provide feedback on the following criteria, in descending order of
importance:

-   **Unintended changes:** Does the proposal change the behavior of the
    existing Dart language in ways that don't appear to be deliberate? Pay
    particular attention to potential *breaking* changes to the language.

-   **Completeness:** Are there parts of the language that *should* be affected
    by the proposal that aren't mentioned? Is the specification ambiguous or
    under-specified? Does it refer to concepts that are not defined? Are there
    things an implementer would need to know that are not answered?

    In particular, does the feature cover:

    -   **Grammar and syntax:** Are there parsing ambiguities? Does the grammar
        require unbounded lookahead? Are there uses of undefined grammar rules?

    -   **All declaration kinds:** If the feature applies to classes, does it
        also specify what happens for mixins, enums, extensions, and extension
        types? Does it cover top-level, static, and instance variables? Does it
        cover functions, getters, setters, constructors, and operators?

    -   **Induced declarations:** When the feature induces getters, setters,
        fields, or constructors, are all properties specified (return type,
        covariant, annotations, scope, `const`-ness, etc.)?

    -   **Scope:** If the feature uses or declares names, are the interactions
        with scoping and namespaces spelled out? How does the feature interact
        with privacy?

    -   **Static types:** Does the feature need to affect type inference, flow
        analysis, type promotion, subtyping, least upper bound, or
        exhaustiveness checking?

    -   **Const:** Does the feature interact with `const`? Can it be used in a
        `const` expression or not?

    -   **Migration and tooling:** Is the feature clear about whether it has any
        breaking changes? If so, are they language-versioned? Is the migration
        experience explained? Does the specification discuss automated tooling
        to use the feature?

-   **Internal consistency:** Is this proposal internally coherent? Do parts of
    it conflict with other parts of the same proposal? Does the grammar allow
    syntax whose semantics aren't specified? Or does the prose describe behavior
    for syntax the grammar doesn't allow?

    If reviewing a change to a proposal, are the changes described in the
    changelog at the end of the proposal? Does the version number of the
    changelog at the top of the proposal match the latest changelog entry?

-   **Consistency with Dart:** Is this proposal consistent with the existing
    Dart language specification? Since the document proposes a *change* to the
    language, there will be some parts that are in conflict, but those should be
    explicitly spelled out as parts of the proposal. Are there other parts of
    the proposal that seem to implicitly disagree with how the language works?

    References:

    -   The language specification in `specification/dartLangSpec.tex`.

    -   Previously shipped feature specifications in `accepted/`.

-   **Clarity:** Is this proposal hard for a human to understand? Does it
    explain concepts in a logical order? Does it use clear terminology and use
    it consistently? Can it be more concise? Is there redundancy that can be
    eliminated?

-   **Mistakes:** Are there typos or other small-scale mistakes in the text?

Be thorough. A mistake in a language feature can be costly.

## Report

Unless the user (or their personal agent configuration) specifies a different
review structure or style, organize the report into sections roughly according
to the above goals, and keep the Markdown simple and clear (avoiding numbers in
headings, emoji, etc.).

When referring to specific parts of the proposal, mention line numbers and
include a couple of lines of the document as a quoted reference (since line
numbers will change as the file is edited), like:

```
Typo on line 185:

> Likewise, a declring parameter in a primary constructor induces an

"declring" should be "declaring".
```
