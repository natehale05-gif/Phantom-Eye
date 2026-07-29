import 'dart:async';

import 'package:pe_core/pe_core.dart';
import 'package:test/test.dart';

/// A future that completes with [value] after [delay].
Future<T> _after<T>(Duration delay, T value) =>
    Future<T>.delayed(delay, () => value);

/// A future that fails after [delay].
Future<T> _failAfter<T>(Duration delay, Object error) =>
    Future<T>.delayed(delay, () => throw error);

void main() {
  group('raceForFirstSuccess', () {
    test('returns the only success', () async {
      final result = await raceForFirstSuccess<String>([() async => 'ok']);
      expect(result, 'ok');
    });

    test('returns the fastest success', () async {
      final result = await raceForFirstSuccess<String>([
        () => _after(const Duration(milliseconds: 80), 'slow'),
        () => _after(const Duration(milliseconds: 10), 'fast'),
      ]);
      expect(result, 'fast');
    });

    test('a FAST FAILURE alongside a slow success yields the success — this is '
        'the exact case Future.any gets wrong', () async {
      final result = await raceForFirstSuccess<String>([
        () => _failAfter(const Duration(milliseconds: 5), 'mirror 504'),
        () => _after(const Duration(milliseconds: 40), 'the good mirror'),
      ]);
      expect(result, 'the good mirror');
    });

    test('demonstrates the Future.any behaviour being avoided', () async {
      // Same inputs as the test above, but through Future.any: the fast
      // failure wins and the slow success is lost. Kept as executable
      // documentation of why raceForFirstSuccess exists.
      await expectLater(
        Future.any<String>([
          _failAfter(const Duration(milliseconds: 5), 'mirror 504'),
          _after(const Duration(milliseconds: 40), 'the good mirror'),
        ]),
        throwsA('mirror 504'),
      );
    });

    test('survives several fast failures before a slow success', () async {
      final result = await raceForFirstSuccess<int>([
        () => _failAfter(const Duration(milliseconds: 1), 'a'),
        () => _failAfter(const Duration(milliseconds: 2), 'b'),
        () => _failAfter(const Duration(milliseconds: 3), 'c'),
        () => _after(const Duration(milliseconds: 30), 42),
      ]);
      expect(result, 42);
    });

    test(
      'throws AllAttemptsFailedException only when every attempt fails',
      () async {
        await expectLater(
          raceForFirstSuccess<String>([
            () => _failAfter(const Duration(milliseconds: 1), 'first'),
            () => _failAfter(const Duration(milliseconds: 5), 'second'),
          ]),
          throwsA(
            isA<AllAttemptsFailedException>().having(
              (e) => e.errors,
              'errors',
              ['first', 'second'],
            ),
          ),
        );
      },
    );

    test(
      'errors are reported in attempt order, not completion order',
      () async {
        try {
          await raceForFirstSuccess<String>([
            () => _failAfter(const Duration(milliseconds: 30), 'slow-first'),
            () => _failAfter(const Duration(milliseconds: 1), 'fast-second'),
          ]);
          fail('should have thrown');
        } on AllAttemptsFailedException catch (e) {
          expect(e.errors, ['slow-first', 'fast-second']);
        }
      },
    );

    test('an empty attempt list fails rather than hanging', () async {
      await expectLater(
        raceForFirstSuccess<String>(const []),
        throwsA(isA<AllAttemptsFailedException>()),
      );
    });

    test(
      'a synchronously-throwing factory counts as that attempt failing',
      () async {
        final result = await raceForFirstSuccess<String>([
          () => throw StateError('bad factory'),
          () async => 'still fine',
        ]);
        expect(result, 'still fine');
      },
    );

    test('all factories throwing synchronously still aggregates', () async {
      await expectLater(
        raceForFirstSuccess<String>([
          () => throw StateError('one'),
          () => throw StateError('two'),
        ]),
        throwsA(
          isA<AllAttemptsFailedException>().having(
            (e) => e.errors.length,
            'error count',
            2,
          ),
        ),
      );
    });

    test('losers are abandoned exactly once, and the winner is not', () async {
      final abandoned = <int>[];
      final result = await raceForFirstSuccess<String>([
        () => _after(const Duration(milliseconds: 60), 'slow'),
        () => _after(const Duration(milliseconds: 5), 'fast'),
        () => _after(const Duration(milliseconds: 90), 'slowest'),
      ], onAbandon: abandoned.add);
      expect(result, 'fast');
      expect(abandoned, unorderedEquals([0, 2]));
      expect(abandoned, isNot(contains(1)), reason: 'winner is not abandoned');
    });

    test('nothing is abandoned when every attempt fails', () async {
      final abandoned = <int>[];
      await raceForFirstSuccess<String>([
        () async => throw 'x',
        () async => throw 'y',
      ], onAbandon: abandoned.add).catchError((Object _) => '');
      expect(abandoned, isEmpty);
    });

    group('attemptTimeout', () {
      test('a hung attempt times out while a responsive one wins', () async {
        // The timeout must sit *above* the good mirror's latency, otherwise it
        // would (correctly) kill that attempt too.
        final result = await raceForFirstSuccess<String>([
          () => _after(const Duration(seconds: 30), 'hung mirror'),
          () => _after(const Duration(milliseconds: 20), 'good mirror'),
        ], attemptTimeout: const Duration(milliseconds: 200));
        expect(result, 'good mirror');
      });

      test(
        'the timeout applies per attempt, not to the race as a whole',
        () async {
          // Three attempts each just inside a 100 ms budget; the race as a
          // whole runs longer than any single attempt's timeout, which must not
          // itself cause a failure.
          final result = await raceForFirstSuccess<String>([
            () => _failAfter(const Duration(milliseconds: 20), 'a'),
            () => _failAfter(const Duration(milliseconds: 40), 'b'),
            () => _after(const Duration(milliseconds: 60), 'c'),
          ], attemptTimeout: const Duration(milliseconds: 100));
          expect(result, 'c');
        },
      );

      test('all attempts timing out aggregates as TimeoutExceptions', () async {
        await expectLater(
          raceForFirstSuccess<String>([
            () => _after(const Duration(seconds: 30), 'a'),
            () => _after(const Duration(seconds: 30), 'b'),
          ], attemptTimeout: const Duration(milliseconds: 10)),
          throwsA(
            isA<AllAttemptsFailedException>().having(
              (e) => e.errors.every((x) => x is TimeoutException),
              'all timeouts',
              isTrue,
            ),
          ),
        );
      });

      test('a success inside the timeout is unaffected', () async {
        final result = await raceForFirstSuccess<String>([
          () => _after(const Duration(milliseconds: 5), 'quick'),
        ], attemptTimeout: const Duration(seconds: 5));
        expect(result, 'quick');
      });
    });
  });
}
