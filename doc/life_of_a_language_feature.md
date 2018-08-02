# Dart language change process

## User issue or feature request

Features and changes arise from perceived user issues or feature requests.
Feature requests should be filed in
the [language repo](http://github.com/dart-lang/language/issues/).  We may close issues
that we believe that we will not adress for whatever reason, or we may keep
issues open indefinitely if we believe they are something that we may wish to
address in the future.  Feature request/problem issues are primarily for
documentation of the user problem to be solved.

## Design, feedback, and iteration

When (a member of) the language team decides to take up an issue, it may be
desireable to file a specific meta issue for tracking the user problem or
feature under consideration, separate from the issues for the specific
proposals.  Alternatively, an already filed feature request/user problem may
serve this purpose.

Language team members may propose specific feature or solutions to a problem.
Generally, this will involve one or more of:
 - Filing an issue for discussion of a proposed solution.
 - Preparing an initial writeup of the proposed solution and checking it into
the "working" sub-directory of the language repository.

Additional materials may be added along side the writeup.

Proposals may be iterated on in place.

Alternative proposals should generally have their own issue and/or writeup.

All proposals should be linked from and link to the the meta issue for the user
problem/feature request they are trying to address.

### External (outside of the language team) feedback

We expect to use the github issue tracker as the primary place for accepting
feedback on proposals, solicited or unsolicited.  If we solicit feedback, we
anticipate opening an issue for discussion and feedback, but also encouraging
filing and splitting off different issues for different threads of discussion.

We generally expect to formally solicit at least one round of feedback on
significant changes.

## Acceptance and implementation

If consensus is reached on a specific proposal and we decide to accept it, a
member of the language team will be chosen to shepherd the implementation.  An
implementation plan document will be created in a named sub-directory of the
`accepted` folder with details about the implementation plan and **a link to the
single canonical writeup of the language feature** which is to serve as the
implementation reference.  The implementation plan should generally include at
least:
  - Affected implementation teams.
  - Schedule and release milestones.
  - Release flag if required, plan for shipping.

A meta-issue will be filed in the language repository for tracking the
implementation process.  The first task in the meta-issue will be to get
sign-off from all of the relevant implementation teams indicating that they
understand the proposal, believe that it can reasonably be implemented, and feel
that they have sufficient details to proceed.  There may be further iteration on
the proposal in this phase.  Changes will be done in place on the writeup.

## Testing

The language team will generally write a preliminary set of language tests for a
feature.  These tests are not intended to be exhaustive, but should illustrate
and exercise important and non-obvious features.  Implementation teams are
encouraged to write additional language or unit tests.  The language team may
also coordinate the writing of additional tests.

## Shipping

Implementated features will be released according to the implementation plan.
The language team will contribute to:
  - Helping internal and external teams through any required migration.
  - Communicating and advertising the change.
  - Documenting the change.
  - Releasing the change.
