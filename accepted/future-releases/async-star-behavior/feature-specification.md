# Behavior of `yield`/`yield*` in `async*` functions and `await for` loops.

**Author**: [lrn@google.com](mailto:lrn@google.com)

**Version**: 1.0 (2018-11-30)

## Background
See [Issue #121](http://github.com/dart-lang/language/issues/121).

The Dart language specification defines the behavior of `async*` functions,
and `yield` and `yield*` statements in those, as well as the behavior of
`await for` loops.

This specification has not always been precise, and the implemented behavior
has been causing user problems ([34775](https://github.com/dart-lang/sdk/issues/34775),
[22351](https://github.com/dart-lang/sdk/issues/22351),
[35063](https://github.com/dart-lang/sdk/issues/35063),
[25748](https://github.com/dart-lang/sdk/issues/25748)).

The specification was cleaned up prior to the Dart 2 released,
but implementations have not been unified and do not match the documented
behavior.

The goal is that users can predict when an `async*` function will block
at a `yield`, and have it interact seamlessly with `await for` consumption
of the created stream.
Assume that an `await for` loop is iterating over a stream created by an
`async*` function.
The `await for` loop pauses its stream subscription whenever its body does
something asynchronous. That pause should block the `async*` function at
the `yield` statement producing the event that caused the `await for`
loop to enter its body. When the `await for` loop finishes its body,
and resumes the subscription, only then may the `async*` function start
executing code after the `yield`.
If the `await for` loop cancels the iteration (breaking out of the loop in any
way) then the subscription is canceled,
and then the `async*` function should return at the `yield` statement
that produced the event that caused the await loop to enter its body.
The `await for` loop will wait for the cancellation future (the one
returned by `StreamSubscription.cancel`) which may capture any errors
that the `async*` function throws while returning
(typically in `finally` blocks).

That is: Execution of an `async*` function producing a stream,
and an `await for` loop consuming that stream, must occur in *lock step*.

## Feature Specification

The language specification already contains a formal specification of the
behavior.
The following is a non-normative description of the specified behavior.

An `async*` function returns a stream.
Listening on that stream executes the function body linked to the
stream subscription returned by that `listen` call.

A `yield e;` statement is specified such that it must successfully *deliver*
the event to the subscription before continuing.
If the subscription is canceled, delivering succeeds and does nothing,
if the subscription is a paused,
delivery succeeds when the event is accepted and buffered.
Otherwise, deliver is successful after the subscription's event listener
has been invoked with the event object.

After this has happened, the subscription is checked for being
canceled or paused.
If paused, the function is blocked at the `yield` statement until
the subscription is resumed or canceled.
In this case the `yield` is an asynchronous operation (it does not complete
synchronously, but waits for an external event, the resume,
before it continues).
If canceled, including if the cancel happens during a pause,
the `yield` statement acts like a `return;` statement.

A `yield* e;` statement listens on the stream that `e` evaluates to
and forwards all events to this function's subscription.
If the subscription is paused, the pause is forwarded to the yielded stream
If the subscription is canceled, the cancel is forwarded to the yielded stream,
then the `yield*` statement waits for any cancellation future, and finally
it acts like a `return;` statement.
If the yielded stream completes, the yield statement completes normally.
A `yield*` is *always* an asynchronous operation.

In an asynchronous function, an `await for (var event in stream) ...` loop
first listens on the iterated stream, then for each data event, it executes the
body. If the body performs any asynchronous operation (that is,
it does not complete synchronously because it executes any `await`,
`wait for` or `yield*` operation, or it blocks at a `yield`), then
the stream subscription must be paused. It is resumed again when the
body completes normally. If the loop body breaks the loop (by any means,
including throwing or breaking), or if the iterated stream produces an error,
then the loop is broken. Then the subscription is canceled and the cancellation
future is awaited, and then the loop completes in the same way as the body
or by throwing the produced error and its accompanying stack trace.

Notice that there is no requirement that an `async*` implementation must call
the subscription event handler *synchronously*, but if not, then it must
block at the `yield` until the event has been delivered. Since it's possible
to deliver the event synchronously, it's likely that that will be the
implementation, and it's possible that performance may improve due to this.

### Consequences
Implementations currently do not block at a `yield` when the delivery of
the event causes a pause. They simply does not allow a `yield` statement
to act asynchronously. They can *cancel* at a yield if the cancel happened
prior to the `yield`, and can easily be made to respect a cancel happening
during the `yield` event delivery, but they only check for pause *before*
delivering the event, and it requires a rewrite of the Kernel transformer
to change this behavior.

### Example
```dart
Stream<int> computedStream(int n) async* {
  for (int i = 0; i < n; i++) {
    var value = expensiveComputation(i);
    yield value;
  }
}

Future<void> consumeValues(Stream<int> values, List<int> log) async {
  await for (var value in values) {
    if (value < 0) break;
    if (value > 100) {
      var newValue = await complexReduction(value);
      if (newValue < 0) break;
      log.add(newValue);
    } else {
      log.add(value);
    }
  }
}

void main() async {
  var log = <int>[];
  await consumeValues(computedStream(25), log);
  print(log);
}
```
In this example, the `await for` in the `consumeValues` function should get a chance to abort or pause
(by doing something asynchronous) its stream subscription *before* the next `expensiveComputation` starts.

The current implementation starts the next expensive operation before it checks whether it should 
abort.
