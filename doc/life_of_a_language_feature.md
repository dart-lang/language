# Dart language evolution process

## User issue or feature request

Features and changes arise from perceived user issues or feature requests.
Feature requests should be filed in the [language
repo](https://github.com/dart-lang/language/issues/new?labels=request), and are
labelled [`request`](https://github.com/dart-lang/language/labels/request).
We may close issues that we believe that we will not
address for whatever reason, or we may keep issues open indefinitely if we
believe they are something that we may wish to address in the future. Feature
request issues are primarily for documentation of the user issue to be solved.

## Design, feedback, and iteration

When a member of the language team decides to take up an issue, we will create a
specific "language feature" issue (labelled [`feature`](https://github.com/dart-lang/language/labels/feature))
for tracking the solution to the user issue/problem or feature under consideration. 

Interested parties may propose several (competing) language features to a
single request/problem. Such a proposal consist of:

- A issue labelled 'feature' for discussion of a proposed solution

- A link to an initial writeup of the proposed solution. This writeup should be
checked into a sub-directory with the name of the feature (`/[feature-name]/`),
located inside the
[`working`](https://github.com/dart-lang/language/tree/master/working)
directory of the language repository. The filename should be `feature-specification.md`.

Additional materials may be added along side the writeup.

All written plans, specs, and materials must be written using [GitHub flavored
Markdown format](https://guides.github.com/features/mastering-markdown/#GitHub-flavored-markdown)
format, and must use the `.md` extension.

Proposals may be iterated on in-place.

As mentioned, alternative proposals should have their own issue and writeup.

All proposals should be linked from and link to the 'request' for
the user problem/feature request they are trying to address.

For smaller and non-controversial features, we will sometimes skip this step and
proceed directly to the [Acceptance and
implementation](#acceptance-and-implementation) phase.

### External (outside of the language team) feedback

We expect to use the github issue tracker as the primary place for accepting
feedback on proposals, solicited or unsolicited. If we solicit feedback, we
anticipate opening an issue for discussion and feedback, but also encouraging
filing and splitting off different issues for different threads of discussion.

We generally expect to formally solicit at least one round of feedback on
significant changes.

## Acceptance and implementation

If consensus is reached on a specific proposal and we decide to accept it, a
member of the language team will be chosen to shepherd the implementation.
The implementation will be tracked via two artifacts:

  - A 'implementation' issue.

  - A feature specification document

The 'feature specification' is **a single canonical writeup of the language
feature** which is to serve as the implementation reference. Feature
specifications use Markdown format. The file name should be
`feature-specification.md`, and the feature specification should be located
inside the `accepted/future-releases/` folder.

The implementation issue (labelled `implementation`) will be filed in the
language repository for tracking the implementation process. This top of this
issue must contain links to:

  - The related `request` and `feature` issues (if they exist)

  - A link to the feature specification

### Kick-off meetings

The next step of the implementation issue is to get sign-off from all of the
relevant implementation teams indicating that they understand the proposal,
believe that it can reasonably be implemented, and feel that they have
sufficient details to proceed.

At a minimum, the set of relevant implementation teams should nearly always
include both the analyzer and CFE teams. Often, back-end teams (Dart native
runtime, Dart for web, and Wasm) should be included too. Note that if a feature
consists entirely of a new piece of syntactic sugar, it can be tempting to
assume that it's not necessary to consult with any back-end teams (since the CFE
will lower the new syntax into a kernel form that is already supported). But
this can be a dangerous assumption. It's easy to forget that even in features
that appear to consist purely of syntactic sugar, some back-end support may be
needed in order to properly support single-step debugging or hot reload. Also,
some work may need to be done on back-end code generators in order to make sure
that the new feature is lowered into a form that can be well optimized. To avoid
missing things, we prefer to err on the side of asking teams whether they're
affected, rather than assuming they won't be.

Since feature specification documents are usually long and very detailed, we
like to begin this sign-off process with a set of kick-off meetings, typically
one for each affected implementation team. These meetings are on opportunity for
a language team representative to present a broad outline of the new feature,
give some concrete examples, and collect insights from the implementation teams
about what aspects of the implementation might need special attention.

There may be further iteration on the proposal
in this phase. This sign-off must be recorded in the implementation issue.
Changes will be done in place on the writeup.

### Implementation issues

A typical outcome of the kick-off meetings will be a set of implementaiton
issues in the SDK repo, to track specific pieces of work that need to be
done.

Additionally, Kevin Chisholm has a script for generating the core set of
implementation issues for a feature:
https://github.com/itsjustkevin/flutter_release_scripts/blob/main/languageFeatures.js. We
like to use this script for larger features. It creates a large number of
issues, though, so we will sometimes skip it for smaller features that only
require a small amount of work.

Some teams have checklists that they consult when creating implementation
issues, to make sure important areas of work aren't forgotten. For example:

- [Implementing a new language feature
  (analyzer)](https://github.com/dart-lang/sdk/blob/main/pkg/analyzer/doc/process/new_language_feature.md)

- [Implementing a new language feature (analysis
  server)](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/doc/process/new_language_feature.md)

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

Note that implementing a language feature using a feature flag is frequently
more work that implementing it without a feature flag, since the compiler and
analyzer must faithfully implement both the old and new behaviors. Occasionally
the language team may decide that the benefits of using a feature flag don't
justify this extra work. But this is a rare senario. If you are working on a
feature and believe you don't need to use a feature flag, please consult with
the language team to be sure.

Creating the feature flag should be one of the first implementation
tasks. Here's how to do it:

- Add an entry to `tools/experimental_features.yaml` describing the feature, in
  the top section (above the line that says `Flags below this line are
  shipped`).

- Run `dart pkg/front_end/tool/fasta.dart generate-experimental-flags` to update
  `pkg/_fe_analyzer_shared/lib/src/experiments/flags.dart` and
  `pkg/front_end/lib/src/api_prototype/experimental_flags_generated.dart`.

- Run `dart pkg/analyzer/tool/experiments/generate.dart` to update
  `pkg/analyzer/lib/src/dart/analysis/experiments.g.dart`.

- Add a static final declaration to the `Feature` class in
  `pkg/analyzer/lib/dart/analysis/features.dart`.

- Increment the value of `AnalysisDriver.DATA_VERSION` in
  `pkg/analyzer/lib/src/dart/analysis/driver.dart`.

- Example CL: https://dart-review.googlesource.com/c/sdk/+/365545

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

To enable the feature in a language test, include the line `//
SharedOptions=--enable-experiment=$FEATURE` near the top of the test (before the
first directive), where `$FEATURE` is replaced with the feature name. To disable
the feature in a language test, include the line `// @dart=$VERSION` near the
top of the test (before the first directive), where `$VERSION` is the current
stable release of Dart (and therefore is the largest version that is guaranteed
_not_ to contain the feature).

### Google3 testing

New features should be tested in Google's internal code base before they are
switched on.

Details of how to do this will be described in a separate (Google internal)
document.

## Shipping

Implemented features will be released according to the implementation plan.
The language team will contribute to:

  - Helping internal and external teams through any required migration.

  - Communicating and advertising the change.

  - Documenting the change.

  - Releasing the change.

## After shipping

After a feature has been shipped, the documents pertaining to the feature should
be moved into subfolders carrying the name of the release in which they were
shipped (e.g. `2.1`).

## Sample file layout

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

