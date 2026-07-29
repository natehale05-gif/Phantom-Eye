import 'dart:async';

/// Thrown by [raceForFirstSuccess] when every attempt failed.
///
/// Carries all of the individual errors, since with a mirror race the useful
/// diagnostic is usually "what did each mirror say", not just the last one.
final class AllAttemptsFailedException implements Exception {
  AllAttemptsFailedException(this.errors);

  /// One entry per attempt, in the order the attempts were supplied.
  final List<Object> errors;

  @override
  String toString() =>
      'AllAttemptsFailedException: all ${errors.length} attempt(s) failed '
      '(${errors.map((e) => e.toString()).join('; ')})';
}

/// Runs every attempt concurrently and completes with the **first success**.
///
/// This is the Dart equivalent of JavaScript's `Promise.any`, and it exists
/// because **`Future.any` is not that**. `Future.any` completes with the first
/// future to *settle* — including one that settles with an error:
///
/// ```dart
/// // dart:async, Future.any
/// void onError(Object error, StackTrace stack) {
///   if (!completer.isCompleted) completer.completeError(error, stack);
/// }
/// ```
///
/// `Promise.any`, by contrast, ignores rejections and only rejects once every
/// input has rejected. The distinction is load-bearing here: the legacy app
/// raced two Overpass mirrors precisely *because* mirrors return frequent
/// 504s, so a fast failure is the common case. Ported onto `Future.any`, the
/// fastest-failing mirror would kill the whole request — silently breaking
/// street labels, trails, category search and place details at once.
///
/// Semantics:
///  - completes with the first attempt to succeed;
///  - throws [AllAttemptsFailedException] only after *every* attempt has
///    failed (or timed out);
///  - applies [attemptTimeout] to each attempt independently, when given;
///  - abandons the losers once a winner is found, invoking [onAbandon] so the
///    caller can release resources (e.g. close an HTTP client). This improves
///    on the legacy version, whose losing attempts kept their 25 s timers
///    alive after a winner had already resolved.
///
/// Each attempt is supplied as a factory so nothing starts until this
/// function decides to start it, and so an attempt can be described by an
/// index for [onAbandon].
Future<T> raceForFirstSuccess<T>(
  List<Future<T> Function()> attempts, {
  Duration? attemptTimeout,
  void Function(int index)? onAbandon,
}) {
  if (attempts.isEmpty) {
    return Future.error(AllAttemptsFailedException(const []));
  }

  final completer = Completer<T>();
  final errors = List<Object?>.filled(attempts.length, null);
  var failures = 0;
  var settled = false;

  void abandonOthers(int winner) {
    if (onAbandon == null) return;
    for (var i = 0; i < attempts.length; i++) {
      if (i != winner) onAbandon(i);
    }
  }

  for (var i = 0; i < attempts.length; i++) {
    final index = i;
    Future<T> future;
    try {
      future = attempts[index]();
    } catch (error) {
      // A factory that throws synchronously counts as that attempt failing,
      // not as a failure of the whole race.
      future = Future<T>.error(error);
    }
    if (attemptTimeout != null) {
      future = future.timeout(attemptTimeout);
    }

    future.then(
      (value) {
        if (settled) return;
        settled = true;
        abandonOthers(index);
        completer.complete(value);
      },
      onError: (Object error, StackTrace _) {
        if (settled) return;
        errors[index] = error;
        failures++;
        if (failures == attempts.length) {
          settled = true;
          completer.completeError(
            AllAttemptsFailedException(
              errors.map((e) => e ?? 'unknown error').toList(growable: false),
            ),
          );
        }
      },
    );
  }

  return completer.future;
}
