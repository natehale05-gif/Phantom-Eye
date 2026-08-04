import 'package:pe_core/pe_core.dart';

/// The curated destinations offered on the home screen.
///
/// Ported from `PLACES` in `src/places.ts:19`. Each framing is hand-tuned for
/// a cinematic arrival — the height, heading and pitch are not derivable from
/// the coordinate, which is why they travel with it. Flying to the Golden
/// Gate on a default overhead camera puts the bridge edge-on and out of shot.
///
/// A parity fixture generated from the real `src/places.ts` keeps this table
/// from drifting; see `tool/gen_places_fixture.mjs`.
const List<CuratedPlace> kCuratedPlaces = [
  CuratedPlace(
    id: 'nyc',
    name: 'Manhattan',
    region: 'New York City',
    position: LngLat(-73.9857, 40.7484),
    cameraHeightMeters: 1400,
    headingDegrees: 25,
    pitchDegrees: -28,
  ),
  CuratedPlace(
    id: 'sf',
    name: 'Golden Gate',
    region: 'San Francisco',
    position: LngLat(-122.4783, 37.8199),
    cameraHeightMeters: 1200,
    headingDegrees: 320,
    pitchDegrees: -22,
  ),
  CuratedPlace(
    id: 'paris',
    name: 'Eiffel Tower',
    region: 'Paris',
    position: LngLat(2.2945, 48.8584),
    cameraHeightMeters: 900,
    headingDegrees: 300,
    pitchDegrees: -25,
  ),
  CuratedPlace(
    id: 'dubai',
    name: 'Burj Khalifa',
    region: 'Dubai',
    position: LngLat(55.2744, 25.1972),
    cameraHeightMeters: 1500,
    headingDegrees: 200,
    pitchDegrees: -20,
  ),
  CuratedPlace(
    id: 'rome',
    name: 'Colosseum',
    region: 'Rome',
    position: LngLat(12.4922, 41.8902),
    cameraHeightMeters: 700,
    headingDegrees: 40,
    pitchDegrees: -30,
  ),
  CuratedPlace(
    id: 'sydney',
    name: 'Opera House',
    region: 'Sydney',
    position: LngLat(151.2153, -33.8568),
    cameraHeightMeters: 900,
    headingDegrees: 210,
    pitchDegrees: -24,
  ),
  CuratedPlace(
    id: 'tokyo',
    name: 'Shibuya',
    region: 'Tokyo',
    position: LngLat(139.7005, 35.6595),
    cameraHeightMeters: 1100,
    headingDegrees: 15,
    pitchDegrees: -26,
  ),
  CuratedPlace(
    id: 'grand-canyon',
    name: 'Grand Canyon',
    region: 'Arizona',
    position: LngLat(-112.1129, 36.0999),
    cameraHeightMeters: 3200,
    headingDegrees: 90,
    pitchDegrees: -20,
  ),
];

/// Look up a curated place by id, or null.
CuratedPlace? curatedPlaceById(String id) {
  for (final place in kCuratedPlaces) {
    if (place.id == id) return place;
  }
  return null;
}
