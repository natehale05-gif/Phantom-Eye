export interface Place {
  id: string;
  name: string;
  region: string;
  /** Longitude, latitude in degrees. */
  lon: number;
  lat: number;
  /** Camera height above the target in meters. */
  height: number;
  /** Camera heading / pitch in degrees for a cinematic framing. */
  heading: number;
  pitch: number;
}

/**
 * A curated set of iconic destinations with full photorealistic 3D coverage.
 * Framings are hand-tuned for a cinematic, "hero shot" arrival.
 */
export const PLACES: Place[] = [
  {
    id: 'nyc',
    name: 'Manhattan',
    region: 'New York City',
    lon: -73.9857,
    lat: 40.7484,
    height: 1400,
    heading: 25,
    pitch: -28,
  },
  {
    id: 'sf',
    name: 'Golden Gate',
    region: 'San Francisco',
    lon: -122.4783,
    lat: 37.8199,
    height: 1200,
    heading: 320,
    pitch: -22,
  },
  {
    id: 'paris',
    name: 'Eiffel Tower',
    region: 'Paris',
    lon: 2.2945,
    lat: 48.8584,
    height: 900,
    heading: 300,
    pitch: -25,
  },
  {
    id: 'dubai',
    name: 'Burj Khalifa',
    region: 'Dubai',
    lon: 55.2744,
    lat: 25.1972,
    height: 1500,
    heading: 200,
    pitch: -20,
  },
  {
    id: 'rome',
    name: 'Colosseum',
    region: 'Rome',
    lon: 12.4922,
    lat: 41.8902,
    height: 700,
    heading: 40,
    pitch: -30,
  },
  {
    id: 'sydney',
    name: 'Opera House',
    region: 'Sydney',
    lon: 151.2153,
    lat: -33.8568,
    height: 900,
    heading: 210,
    pitch: -24,
  },
  {
    id: 'tokyo',
    name: 'Shibuya',
    region: 'Tokyo',
    lon: 139.7005,
    lat: 35.6595,
    height: 1100,
    heading: 15,
    pitch: -26,
  },
  {
    id: 'grand-canyon',
    name: 'Grand Canyon',
    region: 'Arizona',
    lon: -112.1129,
    lat: 36.0999,
    height: 3200,
    heading: 90,
    pitch: -20,
  },
];
