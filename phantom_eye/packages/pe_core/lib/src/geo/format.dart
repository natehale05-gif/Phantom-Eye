/// US-friendly imperial distance formatting.
///
/// Ported verbatim from `formatDistance` in `src/routing.ts:182` — under
/// 1000 ft it reports feet rounded to the nearest 10, otherwise miles with
/// one decimal below 10 mi and none above.
String formatDistance(double meters) {
  final feet = meters * 3.28084;
  if (feet < 1000) return '${(feet / 10).round() * 10} ft';
  final miles = meters / 1609.344;
  return '${miles.toStringAsFixed(miles < 10 ? 1 : 0)} mi';
}

/// Ported verbatim from `formatDuration` in `src/routing.ts:189`.
String formatDuration(double seconds) {
  final min = (seconds / 60).round();
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final m = min % 60;
  return m != 0 ? '$h hr $m min' : '$h hr';
}

/// Clock time of arrival, e.g. "3:45 PM", given seconds remaining.
///
/// Ported from `arrivalClock` in `src/navigation.ts`. The legacy version used
/// `toLocaleTimeString`; this renders 12-hour time directly so the pure-Dart
/// layer stays free of locale/intl dependencies. [now] is injectable so the
/// result is deterministic under test.
String arrivalClock(double remainingSeconds, {DateTime? now}) {
  final at = (now ?? DateTime.now()).add(
    Duration(seconds: remainingSeconds.round()),
  );
  final hour24 = at.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  final suffix = hour24 < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $suffix';
}

/// Relative age of a timestamp, e.g. "just now", "12 min ago", "3 hrs ago".
///
/// Ported from `formatRelativeTime` in `src/gasprices.ts`.
String formatRelativeTime(DateTime timestamp, {DateTime? now}) {
  final minutes = ((now ?? DateTime.now()).difference(timestamp).inSeconds / 60)
      .round();
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = (minutes / 60).round();
  if (hours < 24) return '$hours hr${hours == 1 ? '' : 's'} ago';
  final days = (hours / 24).round();
  return '$days day${days == 1 ? '' : 's'} ago';
}
