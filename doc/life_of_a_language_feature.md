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

All proposals should be linked from and link to the the 'request' for
the user problem/feature request they are trying to address.

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
The implementation will be tracked via three artifacts:

  - An implementation plan document

  - A 'implementation' issue.

  - A feature specification document

The implementation plan must be located in a sub-directory with the name of the
feature (`/[feature-name]/`) located inside the `accepted/future-releases/`
folder. The filename should be `implementation-plan.md`. The implementation
plan should generally include at least:

  - Affected implementation teams.

  - Schedule and release milestones.

  - Release flag if required, plan for shipping.

The 'feature specification' is **a single canonical writeup of the language
feature** which is to serve as the implementation reference. Feature
specifications use Markdown format. The file name should be
`feature-specification.md`, and the feature specification should
be located in the same sub-directory as the implementation plan.

A meta-issue (labelled `implementation`) will be filed in the language
repository for tracking the implementation process. This top of this issue must
contain links to:

  - The related `request` issue

  - The related `feature` issue

  - A link to the implementation plan

  - A link to the feature specification

The next step of the implementation issue is to get sign-off from all of the
relevant implementation teams indicating that they understand the proposal,
believe that it can reasonably be implemented, and feel that they have
sufficient details to proceed.  There may be further iteration on the proposal
in this phase. This sign-off must be recorded in the implementation issue.
Changes will be done in place on the writeup.

## Testing

The language team will generally write a preliminary set of language tests for a
feature.  These tests are not intended to be exhaustive, but should illustrate
and exercise important and non-obvious features.  Implementation teams are
encouraged to write additional language or unit tests.  The language team may
also coordinate the writing of additional tests.

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
        implementation-plan.md
        feature-specification.md
    future-releases/
      spread-operator/
        implementation-plan.md
        feature-specification.md
  /resources/
    [various supporting documents and resources]
```

