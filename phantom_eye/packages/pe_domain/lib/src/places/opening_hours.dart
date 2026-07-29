/// Result of evaluating an OSM `opening_hours` string.
///
/// [openNow] is null when the spec could not be confidently parsed — the UI
/// then shows the raw string rather than guessing.
final class HoursInfo {
  const HoursInfo({required this.openNow, required this.today});

  const HoursInfo.unknown() : openNow = null, today = null;

  final bool? openNow;

  /// Today's hours rendered for display, e.g. `9 AM–5 PM`, or
  /// `Open 24 hours`.
  final String? today;

  bool get isKnown => openNow != null;
}

/// Sunday-first day indices, matching the legacy `DAY_INDEX` in
/// `src/hours.ts:14` (and JavaScript's `Date.getDay()`).
const Map<String, int> _dayIndex = {
  'Su': 0,
  'Mo': 1,
  'Tu': 2,
  'We': 3,
  'Th': 4,
  'Fr': 5,
  'Sa': 6,
};

/// Convert Dart's `DateTime.weekday` (Mon=1 … Sun=7) to the Sunday-first
/// index this parser uses (Sun=0 … Sat=6).
///
/// **This is a genuine port trap.** The legacy code used JavaScript's
/// `getDay()`, which is already Sunday-first; Dart's `weekday` is not. Getting
/// it wrong shifts every day by one and is easy to miss, because it still
/// "works" six days out of seven for a Mo-Fr spec.
int sundayFirstWeekday(DateTime when) => when.weekday % 7;

final RegExp _twentyFourSeven = RegExp(r'^24\s*/\s*7$');

final RegExp _timeSpans = RegExp(
  r'(\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}'
  r'(?:\s*,\s*\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2})*)',
);

final RegExp _dayRange = RegExp(r'^([A-Za-z]{2})\s*-\s*([A-Za-z]{2})$');

/// A lightweight OSM `opening_hours` evaluator.
///
/// Full `opening_hours` syntax is famously large; this handles the common
/// cases — day ranges/lists with one or more time spans, plus `24/7` — well
/// enough for an Apple-Maps-style Open/Closed state plus today's hours.
/// Anything it cannot confidently parse yields [HoursInfo.unknown].
///
/// Ported from `parseOpeningHours` in `src/hours.ts`, with one deliberate
/// behaviour change — see [_selectRule].
///
/// Known unsupported forms (all degrade to unknown, as in the original):
/// `off`/`closed` modifiers, `PH`/`SH` (public/school holidays), month, week
/// and date ranges, `sunrise`/`sunset`, nth-weekday selectors like `Su[1]`,
/// and comments.
final class OpeningHoursParser {
  const OpeningHoursParser({this.preferMostSpecificRule = true});

  /// When true (the default) the rule naming the fewest days wins, so a
  /// specific override is honoured. See [_selectRule] for why.
  ///
  /// Set false to reproduce the legacy first-match-wins behaviour exactly.
  final bool preferMostSpecificRule;

  HoursInfo parse(String? spec, {DateTime? now}) {
    if (spec == null) return const HoursInfo.unknown();
    final s = spec.trim();
    if (s.isEmpty) return const HoursInfo.unknown();
    if (_twentyFourSeven.hasMatch(s)) {
      return const HoursInfo(openNow: true, today: 'Open 24 hours');
    }

    final at = now ?? DateTime.now();
    final weekday = sundayFirstWeekday(at);
    final minutes = at.hour * 60 + at.minute;

    final candidates = <_Rule>[];
    for (final raw in s.split(';')) {
      final rule = raw.trim();
      if (rule.isEmpty) continue;

      final timeMatch = _timeSpans.firstMatch(rule);
      if (timeMatch == null) continue;

      final dayPart = rule.substring(0, timeMatch.start).trim();
      final days = dayPart.isEmpty
          ? const [0, 1, 2, 3, 4, 5, 6]
          : _parseDays(dayPart);
      if (days == null || !days.contains(weekday)) continue;

      final ranges = _parseRanges(timeMatch.group(1)!);
      if (ranges == null) continue;
      candidates.add(_Rule(dayCount: days.length, ranges: ranges));
    }

    final chosen = _selectRule(candidates);
    if (chosen == null) return const HoursInfo.unknown();

    var open = false;
    for (final r in chosen.ranges) {
      // A range whose end is after its start is a plain half-open interval;
      // otherwise it crosses midnight and the test inverts. Note a == b lands
      // in the second branch and reads as always-open, matching the original.
      if (r.end > r.start) {
        open = open || (minutes >= r.start && minutes < r.end);
      } else {
        open = open || (minutes >= r.start || minutes < r.end);
      }
    }

    final today = chosen.ranges
        .map((r) => '${_formatMinutes(r.start)}–${_formatMinutes(r.end)}')
        .join(', ');
    return HoursInfo(openNow: open, today: today);
  }

  /// Pick which of today's matching rules to report.
  ///
  /// The legacy version returned the **first** matching rule, which is a bug:
  /// `Mo-Su 09:00-17:00; Sa 10:00-14:00` reported 9–5 on Saturday, because the
  /// broad rule matched first and the specific override never got a chance.
  /// Real-world `opening_hours` strings routinely put the general rule first
  /// and refine it afterwards, so this was wrong on exactly the data it was
  /// most likely to meet.
  ///
  /// Preferring the rule that names the fewest days makes an override win.
  /// Ties keep the earlier rule, so behaviour is unchanged whenever the legacy
  /// output was already right.
  _Rule? _selectRule(List<_Rule> candidates) {
    if (candidates.isEmpty) return null;
    if (!preferMostSpecificRule) return candidates.first;
    var best = candidates.first;
    for (final c in candidates.skip(1)) {
      if (c.dayCount < best.dayCount) best = c;
    }
    return best;
  }

  /// Expand a day part such as `Mo-Fr`, `Sa,Su` or `Fr-Mo` into indices.
  ///
  /// Returns null on any unrecognised token, which makes the whole rule be
  /// skipped. Ranges walk forward modulo 7, so `Fr-Mo` correctly wraps
  /// through the weekend.
  List<int>? _parseDays(String part) {
    final out = <int>{};
    for (final raw in part.split(',')) {
      final token = raw.trim();
      final range = _dayRange.firstMatch(token);
      if (range != null) {
        final start = _dayIndex[_capitalizeDay(range.group(1)!)];
        final end = _dayIndex[_capitalizeDay(range.group(2)!)];
        if (start == null || end == null) return null;
        for (var i = 0; i < 7; i++) {
          final idx = (start + i) % 7;
          out.add(idx);
          if (idx == end) break;
        }
      } else {
        final idx = _dayIndex[_capitalizeDay(token)];
        if (idx == null) return null;
        out.add(idx);
      }
    }
    return out.toList(growable: false);
  }

  List<_TimeRange>? _parseRanges(String spans) {
    final out = <_TimeRange>[];
    for (final span in spans.split(',')) {
      final parts = span.split('-');
      if (parts.length != 2) return null;
      final a = _toMinutes(parts[0].trim());
      final b = _toMinutes(parts[1].trim());
      if (a == null || b == null) return null;
      out.add(_TimeRange(a, b));
    }
    return out.isEmpty ? null : out;
  }
}

/// First letter upper, second lower — so only exactly-two-letter tokens can
/// resolve, matching the legacy `cap()` in `src/hours.ts:73`.
String _capitalizeDay(String s) {
  if (s.length < 2) return s;
  return s[0].toUpperCase() + s[1].toLowerCase();
}

int? _toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Render minutes-since-midnight as 12-hour time, omitting `:00`.
///
/// `% 24` on the hour means `24:00` renders as `12 AM`, as in the original.
String _formatMinutes(int min) {
  final h24 = (min ~/ 60) % 24;
  final m = min % 60;
  final period = h24 < 12 ? 'AM' : 'PM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return m == 0
      ? '$h12 $period'
      : '$h12:${m.toString().padLeft(2, '0')} $period';
}

final class _TimeRange {
  const _TimeRange(this.start, this.end);
  final int start;
  final int end;
}

final class _Rule {
  const _Rule({required this.dayCount, required this.ranges});
  final int dayCount;
  final List<_TimeRange> ranges;
}
