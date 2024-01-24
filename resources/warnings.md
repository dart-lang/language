# Dart Warnings

When Dart was first designed, the intent was that Dart applications would be
deployed and run from unprocessed source code on end user machines. That meant
that a heavyweight compilation process involving complex type checking and type
inference could slow application startup. Thus the type system was optional, and
type errors were warnings.

The move to a mandatory static type system in Dart 2.0 turned most of the
warnings related to the type system into full compile errors. But there were a
few specified diagnostics that remained warnings. Further, many language
proposals define additional warnings (for example, unreachable cases in switch
statements in Dart 3.0).

It has been a source of confusion on the team as to whether every Dart tool is
required to report all of those warnings, and whether tools are prohibited from
reporting any warnings not defined by the language.

This document, along with [a corresponding update to the language spec][spec
change] clarifies that.

[spec change]: https://github.com/dart-lang/language/pull/3570

## Specifying warnings

After Dart 2.0 change most static warnings to type errors, there were few
warnings left in the spec. Because of that, we have sometimes considered
removing all warnings from the spec and leaving it entirely up to implementation
teams to define them and decide what to report and when.

However, when writing feature specifications for new language features, we often
find ourselves wanting to suggest new warnings. This is *not* because we want to
force every Dart implementation to report every one of these warnings. It's
because it's important to think holistically about the entire user experience
when defining a new language feature. The tooling experience—warnings, lints,
migration tools, quick fixes etc.—around a feature can make the difference
between a good feature and a bad feature.

Putting warnings (and lints, quick fixes, etc.) in feature proposals helps
ensure the language team does that due diligence. At the same time, we don't
want to discard the expertise of the implementation teams about what makes the
best user experience and diagnostics for their tool. We're just trying to do
good, thorough design.

## Reporting warnings

Given a set of specified warnings, what obligations do Dart implementations have
to implement them? In principle, it would be good if all of our tools behaved
the same and they all reported all warnings. That way users get a consistent
experience.

But the reality is that we have two very different static analysis
implementations: analyzer and common front end (CFE). Requiring both of them to
report all of the same warnings would be a large and continuous engineering
effort for relatively little benefit. Most warnings are seen by users and
addressed by them in their IDE. As long as analyzer reports them, most of the
user benefit is provided. The CFE isn't usually invoked until the user wants to
generate code for a runnable program. If they choose to do that, they are
implicitly ignoring warnings anyway, so having the CFE report them adds only
marginal value.

Also, some warnings are specific to certain tools. For example, a web compiler
might report warnings on `is int` and `is double` since those may not behave as
expected in JavaScript where the same representation is used for all numbers. It
would be strange and confusing if a compiler *not* targeting the web reported that
warning when it wouldn't be relevant on the platform the user is compiling for.

Consider that the reason these diagnostics being warnings and not errors is
specifically to allow variation in how they how they are reported to and handled
by users. If there's a diagnostic that we really feel should always be presented
to all users and they should definitely handle it... it should probably be an
error.

## Warning reporting requirements

Given all of the above, the position of the language team on warnings is:

*   The language specification and feature specifications for new features may
    suggest new warnings that the language team believes will help the user
    experience.

*   A conforming Dart implementation is free to report any, all, some, or none
    of those specified warnings.

*   Further, a Dart implementation may choose to report its own warnings that
    aren't part of the language spec or any feature proposal.

*In other words, both the language team and implementation teams may add to the
set of all possible warnings, and the implementation teams can decide which of
those warnings make sense for their tools to report.*

*In practice, we expect the analyzer to report them all (and let us know if we
specify any that they believe aren't helpful). Going forward, it's likely the
CFE will stop reporting any of them.*
