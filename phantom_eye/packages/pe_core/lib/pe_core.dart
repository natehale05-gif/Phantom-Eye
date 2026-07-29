/// Pure-Dart core for Phantom Eye: geometry, models and utilities.
///
/// This package must never depend on Flutter or on any map engine. That
/// constraint is what makes the navigation logic built on top of it
/// headlessly unit-testable — the property the legacy TypeScript app never
/// had, where every behaviour could only be verified by driving a car.
library;

export 'src/geo/format.dart';
export 'src/geo/geo_math.dart';
export 'src/geo/lng_lat.dart';
export 'src/models/location_fix.dart';
export 'src/models/route.dart';
export 'src/util/lru_cache.dart';
export 'src/util/race.dart';
export 'src/util/rate_limit.dart';
