import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

/// 2026-07-29 is a Wednesday. Anchoring on a known weekday keeps every
/// expectation below readable.
DateTime _at(int weekdayOffsetFromWed, int hour, [int minute = 0]) =>
    DateTime(2026, 7, 29 + weekdayOffsetFromWed, hour, minute);

const _wed = 0;
const _thu = 1;
const _fri = 2;
const _sat = 3;
const _sun = 4;
const _mon = 5;

void main() {
  const parser = OpeningHoursParser();

  group('sundayFirstWeekday (the Dart/JS day-index trap)', () {
    test('maps Dart weekday to JS getDay ordering', () {
      // Sunday must be 0, not 7.
      expect(sundayFirstWeekday(DateTime(2026, 8, 2)), 0, reason: 'Sunday');
      expect(sundayFirstWeekday(DateTime(2026, 7, 27)), 1, reason: 'Monday');
      expect(sundayFirstWeekday(DateTime(2026, 7, 29)), 3, reason: 'Wednesday');
      expect(sundayFirstWeekday(DateTime(2026, 8, 1)), 6, reason: 'Saturday');
    });
  });

  group('trivial and unparseable input', () {
    test('null, empty and whitespace are unknown', () {
      expect(parser.parse(null).isKnown, isFalse);
      expect(parser.parse('').isKnown, isFalse);
      expect(parser.parse('   ').isKnown, isFalse);
    });

    test('24/7 in its several spellings', () {
      for (final spec in ['24/7', ' 24/7 ', '24 / 7', '24/ 7']) {
        final r = parser.parse(spec, now: _at(_wed, 3));
        expect(r.openNow, isTrue, reason: spec);
        expect(r.today, 'Open 24 hours', reason: spec);
      }
    });

    test('unsupported forms degrade to unknown rather than guessing', () {
      const unsupported = [
        'Mo-Fr sunrise-sunset',
        'Su[1] 10:00-12:00',
        'Jan-Mar 09:00-17:00 off',
        'closed',
        'by appointment',
        'Mo-Fr', // days but no times
      ];
      for (final spec in unsupported) {
        expect(
          parser.parse(spec, now: _at(_wed, 12)).isKnown,
          isFalse,
          reason: spec,
        );
      }
    });

    test('an unrecognised day token skips the rule', () {
      expect(
        parser.parse('Xy 09:00-17:00', now: _at(_wed, 12)).isKnown,
        isFalse,
      );
      // Single-letter tokens cannot resolve either, matching the original.
      expect(
        parser.parse('M 09:00-17:00', now: _at(_wed, 12)).isKnown,
        isFalse,
      );
    });
  });

  group('simple day ranges', () {
    test('open inside the window, closed outside', () {
      const spec = 'Mo-Fr 09:00-17:00';
      expect(parser.parse(spec, now: _at(_wed, 12)).openNow, isTrue);
      expect(parser.parse(spec, now: _at(_wed, 8)).openNow, isFalse);
      expect(parser.parse(spec, now: _at(_wed, 18)).openNow, isFalse);
    });

    test('the window is half-open: inclusive start, exclusive end', () {
      const spec = 'Mo-Fr 09:00-17:00';
      expect(parser.parse(spec, now: _at(_wed, 9)).openNow, isTrue);
      expect(parser.parse(spec, now: _at(_wed, 17)).openNow, isFalse);
      expect(parser.parse(spec, now: _at(_wed, 16, 59)).openNow, isTrue);
    });

    test('a day outside the range is unknown, not closed', () {
      // Saturday is simply not described by a Mo-Fr rule.
      expect(
        parser.parse('Mo-Fr 09:00-17:00', now: _at(_sat, 12)).isKnown,
        isFalse,
      );
    });

    test('no day part means every day', () {
      for (final day in [_wed, _sat, _sun]) {
        expect(
          parser.parse('09:00-17:00', now: _at(day, 12)).openNow,
          isTrue,
          reason: 'day offset $day',
        );
      }
    });

    test('a comma-separated day list', () {
      const spec = 'Sa,Su 10:00-16:00';
      expect(parser.parse(spec, now: _at(_sat, 12)).openNow, isTrue);
      expect(parser.parse(spec, now: _at(_sun, 12)).openNow, isTrue);
      expect(parser.parse(spec, now: _at(_wed, 12)).isKnown, isFalse);
    });
  });

  group('wrapping day ranges', () {
    test('Fr-Mo wraps through the weekend', () {
      const spec = 'Fr-Mo 08:00-20:00';
      for (final day in [_fri, _sat, _sun, _mon]) {
        expect(
          parser.parse(spec, now: _at(day, 12)).openNow,
          isTrue,
          reason: 'day offset $day should be covered',
        );
      }
      // Wednesday and Thursday are outside the wrap.
      expect(parser.parse(spec, now: _at(_wed, 12)).isKnown, isFalse);
      expect(parser.parse(spec, now: _at(_thu, 12)).isKnown, isFalse);
    });

    test('Su-Sa covers the whole week', () {
      for (final day in [_wed, _sat, _sun, _mon]) {
        expect(
          parser.parse('Su-Sa 00:00-24:00', now: _at(day, 12)).openNow,
          isTrue,
        );
      }
    });
  });

  group('cross-midnight time spans', () {
    test('open late in the evening and early in the morning', () {
      const spec = 'Fr 20:00-02:00';
      expect(parser.parse(spec, now: _at(_fri, 23)).openNow, isTrue);
      expect(
        parser.parse(spec, now: _at(_fri, 1)).openNow,
        isTrue,
        reason: 'the pre-02:00 tail of the same rule',
      );
      expect(parser.parse(spec, now: _at(_fri, 12)).openNow, isFalse);
    });

    test('a zero-width span reads as always open, matching the original', () {
      // a == b falls into the crossing-midnight branch, where the test is
      // `minutes >= a || minutes < b` — true for every minute.
      expect(
        parser.parse('Mo-Su 12:00-12:00', now: _at(_wed, 3)).openNow,
        isTrue,
      );
    });
  });

  group('multiple spans in one rule', () {
    test('a lunch break closes the middle', () {
      const spec = 'Mo-Fr 08:00-12:00,13:00-17:00';
      expect(parser.parse(spec, now: _at(_wed, 9)).openNow, isTrue);
      expect(parser.parse(spec, now: _at(_wed, 12, 30)).openNow, isFalse);
      expect(parser.parse(spec, now: _at(_wed, 14)).openNow, isTrue);
    });

    test('both spans are rendered', () {
      final r = parser.parse(
        'Mo-Fr 08:00-12:00,13:00-17:00',
        now: _at(_wed, 9),
      );
      expect(r.today, '8 AM–12 PM, 1 PM–5 PM');
    });
  });

  group('the first-rule-wins bug (fixed)', () {
    // Legacy behaviour returned the FIRST matching rule, so the broad rule
    // shadowed the specific Saturday override.
    const spec = 'Mo-Su 09:00-17:00; Sa 10:00-14:00';

    test('a specific override now wins over a broad rule', () {
      final r = parser.parse(spec, now: _at(_sat, 15));
      expect(
        r.today,
        '10 AM–2 PM',
        reason: 'Saturday should use the Sa rule, not Mo-Su',
      );
      expect(r.openNow, isFalse, reason: '15:00 is outside 10-14');
    });

    test('non-overridden days are unaffected', () {
      final r = parser.parse(spec, now: _at(_wed, 12));
      expect(r.today, '9 AM–5 PM');
      expect(r.openNow, isTrue);
    });

    test('legacy behaviour is still available for comparison', () {
      const legacy = OpeningHoursParser(preferMostSpecificRule: false);
      final r = legacy.parse(spec, now: _at(_sat, 15));
      expect(r.today, '9 AM–5 PM', reason: 'the documented legacy bug');
      expect(r.openNow, isTrue);
    });

    test('order does not matter once the fix is in', () {
      const reversed = 'Sa 10:00-14:00; Mo-Su 09:00-17:00';
      expect(parser.parse(reversed, now: _at(_sat, 15)).today, '10 AM–2 PM');
      expect(parser.parse(spec, now: _at(_sat, 15)).today, '10 AM–2 PM');
    });
  });

  group('display formatting', () {
    test('whole hours omit minutes', () {
      expect(
        parser.parse('09:00-17:00', now: _at(_wed, 12)).today,
        '9 AM–5 PM',
      );
    });

    test('partial hours are zero-padded', () {
      expect(
        parser.parse('09:30-17:05', now: _at(_wed, 12)).today,
        '9:30 AM–5:05 PM',
      );
    });

    test('midnight and noon read as 12', () {
      expect(
        parser.parse('00:00-12:00', now: _at(_wed, 6)).today,
        '12 AM–12 PM',
      );
    });

    test('24:00 renders as 12 AM, matching the original', () {
      expect(
        parser.parse('08:00-24:00', now: _at(_wed, 12)).today,
        '8 AM–12 AM',
      );
    });

    test('single-digit hour specs are accepted', () {
      expect(parser.parse('9:00-17:00', now: _at(_wed, 12)).openNow, isTrue);
    });
  });

  group('robustness', () {
    test('extra whitespace and stray separators are tolerated', () {
      final r = parser.parse(
        '  Mo-Fr   09:00 - 17:00 ;;  ',
        now: _at(_wed, 12),
      );
      expect(r.openNow, isTrue);
    });

    test('lower- and mixed-case day tokens resolve', () {
      expect(
        parser.parse('mo-fr 09:00-17:00', now: _at(_wed, 12)).openNow,
        isTrue,
      );
      expect(
        parser.parse('MO-FR 09:00-17:00', now: _at(_wed, 12)).openNow,
        isTrue,
      );
    });

    test('a trailing comment-like fragment does not break the rule', () {
      expect(
        parser.parse('Mo-Fr 09:00-17:00; Su off', now: _at(_wed, 12)).openNow,
        isTrue,
      );
    });
  });
}
