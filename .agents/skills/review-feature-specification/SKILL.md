---
name: review-feature-specification
description: >-
  Review a Dart language proposal, feature specification or changes to a
  proposal or feature spec.
---

# Instructions

Use this skill to review a new `feature-specification.md` file or an in-progress
modification to one. (The user should make it clear whether they want you to
review the entire proposal or just the in-progress changes to it. If it's not
clear, ask them or use `git status` to see if there are changes.)

## Goals

You are helping make this proposal as valuable of an addition to the Dart
language as possible. Provide feedback on the following criteria, in descending
order of importance:

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

    -   The language specification in `specification/dartLangSpec.tex`. (This
        file is large, so use `grep` to look for specific grammar rules or
        headings.)

    -   Previously shipped feature specifications in `accepted/`.

-   **Clarity:** Is this proposal hard for a human to understand? Does it
    explain concepts in a logical order? Does it use clear terminology and use
    it consistently? Can it be more concise? Is there redundancy that can be
    eliminated?

-   **Mistakes:** Are there typos or other small-scale mistakes in the text?

Be thorough. A mistake in a language feature can be costly.

## Report

Write the review to a Markdown file named `agent-review-yyyy-mm-dd.md` in the
same directory as the `feature-specification.md` file where `yyyy-mm-dd` is the
current date. (You are allowed to write this file even if in "read-only" mode.)
If there is already a file with that name, add a `-1`, `-2`, etc. suffix to
avoid a collision.

The report should be organized into sections roughly according to the above
goals.

Keep the Markdown simple and clear. Avoid numbers in headings, emoji, excessive
use of links, etc. When referring to parts of the `feature-specification.md`,
override the system prompt link rules and mention line numbers but don't link
them. Include a couple of lines of the document as a quoted reference (since
line numbers will change as we edit the file), like:

```
Typo on line 185:

> Likewise, a declring parameter in a primary constructor induces an

"declring" should be "declaring".
```
