# Lifecycle of a language feature

This document describes how a language change goes from a vague description of a
user problem to a shipped language feature.

At a high level, for a language change to ship, it needs to have all of:

*   **Enthusiasm about the problem and solution.** The language team and larger
    Dart team needs to be convinced that this feature will be a big enough
    improvement for Dart users to be worth the engineering cost to build and
    maintain it and the cognitive load for users to learn and understand it. We
    need at least enough informal enthusiasm to commit to the long work of
    designing the feature.

*   **A complete specification.** Even a seemingly simple language feature can
    have subtle problematic interactions with other corners of the language.
    Users rightly expect programming languages to be internally consistent and
    easy to understand. To do that, we need well-thought out, detailed feature
    specification. It needs to explain how the feature interacts with the
    language's grammar, static type system, type inference, runtime semantics,
    and other tools.

*   **Priority over other features.** A programming language is a product and we
    don't have unlimited resources to spend on it. Even a good feature may be
    paused if the Dart team feels there are other areas that are more important
    to focus on.

    Once we begin working on a feature, that incomplete implementation is
    [technical debt][] until the feature is complete and ships. We don't want to
    leave a half-complete feature in our codebase, even if it's disabled behind
    an experiment flag. So before implementation begins, we want some confidence
    that we will be able to complete and ship the feature.

*   **A robust implementation.** Users rightly expect a programming language
    implementation [to be rock solid][never the compiler]. A bug in the compiler
    or runtime can break the workflow of thousands of Dart developers and
    millions of end users. When we decide to ship a feature, we commit to
    writing a robust implementation with very thorough tests.

    It's not enough for the compiler and runtime to do the right thing. "Dart"
    encompasses an entire developer user experience: IDEs, automated
    refactoring, formatting, debugging, documentation, etc. All of that needs to
    be carefully updated to support the new feature.

[technical debt]: https://en.wikipedia.org/wiki/Technical_debt
[never the compiler]: https://blog.codinghorror.com/the-first-rule-of-programming-its-always-your-fault/

We work through this list roughly in order. At any point in the process, we may
decide to not move forward with a feature (or to not move forward with it *right
now*). Designing a language is hard and many features that seem worthwhile at
first end up not holding together. The process here lets us incrementally commit
to a feature and minimize spending time on dead ends.

It does mean that contributing to the language process can be challenging. We
welcome the help, but it requires patience before reaching the point where
anyone gets to write some code, and the willingness to accept that many
proposals won't work out.

## User issues and feature requests

Features arise from perceived user issues or feature requests. These issues are
documentation of the user issue to be solved.

> [!NOTE]
> These [feature requests][] are filed in the language repo, and are labelled
> [`request`][request].

[feature requests]: https://github.com/dart-lang/language/issues/new?labels=request
[request]: https://github.com/dart-lang/language/labels/request

We may close issues that we believe we won't address for whatever reason. We may
also keep issues open indefinitely if we believe they are something that we
might want to address in the future.

### How does the team choose which feature request to accept?

There are many factors that determine why we might choose to do one feature over
another, such as feasibility, difficulty, or popularity. Often, we will take a
look through the most 👍-reacted issues to see what our users are interested in.

## Design, feedback, and iteration

Interested parties may propose several (competing) language features to a
single request/problem. 

A "language feature" issue (labelled
[`feature`](https://github.com/dart-lang/language/labels/feature))
will be created for tracking the solution to the user issue/problem or feature
under consideration. 

### Proposal checklist

- [ ] An issue labelled `feature` for discussion of a proposed solution.
  - [ ] Links to and from the `request` issue they are trying to address.
- [ ] A link to an initial feature specification writeup of the proposed
solution in the `feature` issue.
  - [ ] Located in a sub-directory with the name of the feature (`/
[feature-name]/`), inside the
[`working`](https://github.com/dart-lang/language/tree/master/working)
directory of the language repository.
  - [ ] File is named `feature-specification.md`.
    - All written plans, specs, and materials must be written using [GitHub
Markdown format](https://guides.github.com/features/mastering-markdown/#GitHub-flavored-markdown) format, and must use the `.md` extension.
  
Proposals may be iterated on in-place.

For smaller and non-controversial features, we will sometimes skip this step and
proceed directly to the [Acceptance](#acceptance) phase.

### External (outside of the language team) feedback

We use the Github issue tracker as the primary place for accepting feedback on
proposals, solicited or unsolicited. 

If we solicit feedback, we will open an issue for discussion and feedback. We
highly recommend filing and splitting off different issues for different threads
of discussion. We generally expect to formally solicit at least one round of
feedback on significant changes.

## Acceptance

If consensus is reached on a specific proposal and we decide to accept it, a
member of the language team will be chosen to shepherd the implementation.

The implementation will be tracked via two artifacts:

  - The feature specification document
  - The feature project

### Feature specification

The 'feature specification' is **a single canonical writeup of the language
feature** which serves as the implementation reference. The feature
specification should follow the [Proposal Checklist](https://github.com/dart-lang/language/blob/main/doc/life_of_a_language_feature.md#proposal-checklist).

Once we've chosen a specification, we'll update it throughout the implementation
process. For example, we could add new information to the specification if we
encounter edge-cases we didn't think of initially or remove parts of it if a
certain behavior isn't feasible to implement.

### Feature project

We'll [create a project](https://github.com/orgs/dart-lang/projects) in
dart-lang with the title `[Language] <feature-name>`. This project will link to
and from all the Github issues that we need to track to complete and ship the
feature.

> [!TIP]
> Generate all the issues for the project automatically with
> https://github.com/itsjustkevin/aviary.
>
> This script generates all the issues that need to be tracked and added to the
> project. If there are any issues or implementation areas that are unnecessary,
> you can close them out immediately, but each issue is worth thinking through.

#### Meta implementation issue

The meta implementation issue (labelled `implementation`) will be filed in the
language repository for tracking the implementation process. 

This issue must contain links to:

  - [ ] The related `request` and `feature` issues (if they exist)
  - [ ] A link to the feature specification
  - [ ] All implementation issues

> [!NOTE]
> Once you're done making the implementation issue, copy the link of the issue and add it to the [Dash Feature Tracker board](https://github.com/orgs/flutter/projects/82/views/1).

## Team communication

One of the most important parts of the language feature process is communicating
with all the implementation teams and any other stakeholders.

### Tracking doc

Create a tracking doc to allow the Dash team and other stakeholders to track the
progress of the feature. Keep this document up to date.

The tracking doc includes the following:
- [ ] A go-link that clearly describes the feature
(e.g. `go/dart-dot-shorthands`)
- [ ] A brief introduction on what the feature is and how it's used
- [ ] Useful links, background context, and other resources
- [ ] A task breakdown table with status and owners for each task
- [ ] Tables and links to the test tracking sheet
- [ ] (Optional) An FAQ section

### Channels for communication

We'll send out an announcement email to the entire team, letting them know that
work for the feature is beginning.

We may create a mailing list or a Google chat group to organize communication
between the different teams working on the language feature.

### Kick-off meetings

We need to get sign-off from all of the relevant implementation teams indicating
that they understand the proposal, believe that it can reasonably be
implemented, and feel that they have sufficient details to proceed. We do this
in the form of kick-off meetings.

Since feature specification documents are usually long and very detailed, we
like to begin this sign-off process with a set of kick-off meetings, typically
one for each affected implementation team. These meetings are on opportunity for
a language team representative to present a broad outline of the new feature,
give some concrete examples, and collect insights from the implementation teams
about what aspects of the implementation might need special attention.

Get sign-off from the following teams:
- [ ] Model team (parser, CFE, analyzer)
- [ ] Developer experience team
- [ ] Back-end teams:
  - [ ] Dart VM Team
  - [ ] Dart Web Team
  - [ ] Dart2Wasm Team

> [!NOTE]
> If a feature consists entirely of a new piece of syntactic sugar, it can be
> tempting to assume that it's not necessary to consult with any back-end teams
> since the CFE will lower the new syntax into a kernel form that is already
> supported, but this can be a dangerous assumption. It's easy to forget that
> even in features that appear to consist purely of syntactic sugar, some
> back-end support may be needed in order to properly support single-step
> debugging or hot reload. 
>
> Also, some work may need to be done on back-end code generators in order to
> make sure that the new feature is lowered into a form that can be well
> optimized.

To avoid missing things, we prefer to err on the side of asking teams whether
they're affected, rather than assuming they won't be.

## Implementation and testing

### Feature flag

Most new language features should be implemented using a feature flag. The
feature flag serves several purposes:

- It allows the feature to be implemented over a series of CLs without
  destabilizing the SDK. If it comes time to ship a new release of the SDK
  before the feature is ready, the feature flag can remain off, so users won't
  be exposed to a partially-implemented or buggy feature before it's ready.
- It allows users to opt in to trying out features that have not yet been
  released, by turning on the feature flag locally.
- Once the feature is enabled, the feature flag logic ensures that it will only
  affect users who have set their language version to a version that includes
  the new feature. This is especially important for package developers who may
  want to support a range of versions of the Dart SDK.

> [!NOTE]
> Implementing a language feature using a feature flag is frequently
> more work than implementing it without a feature flag, since the compiler and
> analyzer must faithfully implement both the old and new behaviors.
> Occasionally the language team may decide that the benefits of using a feature
> flag don't justify this extra work. But this is a rare scenario. If you are
> working on a feature and believe you don't need to use a feature flag, please
> consult with the language team to be sure.

#### How to add a new language feature flag

- [ ] Add an entry to `tools/experimental_features.yaml` describing the feature, in
  the top section (above the line that says `Flags below this line are
  shipped`).
- [ ] Run `dart pkg/front_end/tool/fasta.dart generate-experimental-flags` to update
  `pkg/_fe_analyzer_shared/lib/src/experiments/flags.dart` and
  `pkg/front_end/lib/src/api_prototype/experimental_flags_generated.dart`.
- [ ] Run `dart pkg/analyzer/tool/experiments/generate.dart` to update
  `pkg/analyzer/lib/src/dart/analysis/experiments.g.dart`.
- [ ] Add a static final declaration to the `Feature` class in
  `pkg/analyzer/lib/dart/analysis/features.dart`.
- [ ] Increment the value of `AnalysisDriver.DATA_VERSION` in
  `pkg/analyzer/lib/src/dart/analysis/driver.dart`.

Example CL: https://dart-review.googlesource.com/c/sdk/+/365545

> [!TIP]
> Keep a WIP CL which enables your feature flag by default in the latest
> version. Rebase it occasionally to get a good idea of how your feature breaks
> the SDK and other dependencies. This is very helpful for getting insight on
> what migrations and breaking changes you'll be making.

### Language testing

The language team will generally write a preliminary set of language tests for a
feature, in the SDK's `tests/language` subdirectory.  These tests are not
intended to be exhaustive, but should illustrate and exercise important and
non-obvious features.  Implementation teams are encouraged to write additional
language or unit tests.  The language team may also coordinate the writing of
additional tests.

An important use case for any new language feature is to ensure that the feature
isn't accidentally used by package authors that have not yet opted into a
language version that supports it. So in addition to testing that the new
language feature works when the feature flag is turned on, the tests added to
`tests/language` should verify that when the feature flag is turned off, the
previous behavior of the SDK is preserved.

One important exception to preserving previous SDK behavior is that it's
permissible (and even encouraged) to improve error messages so that if the user
tries to use a disabled language feature, they receive an error explaining that
they need to enable it, rather than, say, a confusing set of parse errors.

#### To enable the feature in a language test

```dart
// SharedOptions=--enable-experiment=$FEATURE
```

Include this comment near the top of the test (before the first directive),
where `$FEATURE` is replaced with the feature name.

#### To disable the feature in a language test

```dart
// @dart=$VERSION
```

Include this comment near the top of the test (before the first directive),
where `$VERSION` is the current stable release of Dart (and therefore is the
largest version that is guaranteed _not_ to contain the feature).

### Google3 testing

A new feature should be tested in Google's internal codebase before its
experiment flag is permanently switched on. Details of how to do this will be
described in a separate (Google internal) document.

### Implementation work

This is the bulk of creating a new language feature and this stage takes the
most time.

Here are some tips for the implementation stage:

- All implementation code should be under the experiment flag.
- Use the language tests as a pseudo-checklist for what's left to
implement.
- Some teams may have their own checklist for what needs to be considered in a
new language feature implementation. For example, 
[this analyzer doc](https://github.com/dart-lang/sdk/blob/main/pkg/analyzer/doc/process/new_language_feature.md) 
and [this analysis server doc](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/doc/process/new_language_feature.md).
- As we work through an implementation, we may encounter problems or holes in
the spec. If so, create a new issue, add the feature label to it, and cc
@dart-lang/language-team to discuss if we should make any changes in the
specification.

> [!NOTE]
> Remember that making a language feature is a two way street between the spec
> writers and the implementers. The implementation may change because the spec
> changed, or the spec might change after finding out the implementation is too
> complex.

## Migrations

Once the implementation is finished, you should start a CL that enables the
feature by default, if you haven't already. Use this CL to check what code your
feature will break and determine if you need any other lints or quick-fixes to
help these migrations.

See [Google3 testing](#google3-testing) for more information on fixing breakages
within Google3.

## Shipping

> [!NOTE]
> We typically enable the feature by default in a version's beta 2 release. This
> is so that we have time to test the feature in beta 3 and we can give
> ourselves some leeway to fix any surprise bugs.
>
> If the implementation teams aren't confident by beta 2 of an intended release
> version, we'll re-evaluate and push the feature forward to the next version.

This is a general checklist for shipping a feature:
- [ ] Make sure all pre-migrations are complete.
- [ ] Submit a CL that enables the feature by default in the upcoming version.
- [ ] Follow up on documentation changes which should come out when the stable
version with your feature comes out.
- [ ] Communicate with the team that there's a new feature and invite everyone
to test it out.

Congratulations! You've now shipped the feature.

Keep an eye out for breakages and any new QOL requests that surface from the
usage of the feature. Sometimes people use features in ways we don't expect and
we can learn a lot from seeing how the feature is used in the real world.

### Moving the feature spec

After a feature has been shipped, the documents pertaining to the feature should
be copied into the subfolder carrying the name of the release in which they were
shipped (e.g. `2.1`).

The original file should have a forwarding stub to the new location of the file.

For example, moving `super-mixins` to `/accepted/2.1/` after shipping:

```
/language

  /working
    super-mixins.md
    super-mixins-extra.md
    mikes-mixins.md
    spread-operator.md
    mega-constructors/
      proposal.md
      alternate.md
      illustration.png

  /accepted
    2.0/
    2.1/
      super-mixins/
        feature-specification.md
    future-releases/
      spread-operator/
        feature-specification.md
  /resources/
    [various supporting documents and resources]
```

### Sharing the feature release

Send an email to the Dash team to notify them that the flag has been flipped and
that they can start testing out the feature. Invite everyone to dogfood the
feature and provide feedback through Github issues.

You may also want to send a similar email to `flutter-insiders@`.

Reach out to DevRel to discuss other means of advertising the new feature to
users. This can involve a YouTube video, an X tweet, a LinkedIn post, or other
types of social media posts.

### Using the feature in the SDK

The Dart tryjobs need to update their pre-built SDK to allow the feature to be
used. Remember to update `DEPS` in the SDK once you've flipped the flag.

```
# The `sdk_tag` in DEPS needs to be updated to the commit SHA of a recent tag.
"sdk_tag": "git_revision:4bb26ad346b166d759773e01ffc8247893b9681e",
```
