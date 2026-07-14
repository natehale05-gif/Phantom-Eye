/// Third-party service endpoints.
///
/// Every URL here is a **free, public demo instance** with no API key —
/// perfect for building/reviewing this app, but each one has usage limits,
/// no SLA, and (for the geocoder/router) is explicitly documented by its
/// operator as "not for production traffic". Before shipping:
///   1. Stand up your own Photon / Valhalla / OSRM instances (or a paid
///      provider — Mapbox, Stadia Maps, Geoapify, etc. all host these APIs)
///      and swap the base URLs below.
///   2. Consider self-hosting map tiles too (see [MapTileEndpoints]) —
///      OpenTopoMap in particular asks non-trivial users to run their own
///      tile server.
abstract final class ApiEndpoints {
  /// Photon (OSM-based) geocoding — https://photon.komoot.io
  static const String photonBaseUrl = 'https://photon.komoot.io/api';

  /// Valhalla public demo routing — https://valhalla.openstreetmap.de
  /// Supports auto / pedestrian / bicycle costing, which is exactly the
  /// Drive/Walk/Bike profile switch the offroad route builder needs.
  static const String valhallaBaseUrl = 'https://valhalla1.openstreetmap.de';

  /// OSRM public demo — driving-only fallback if Valhalla is unreachable.
  static const String osrmBaseUrl = 'https://router.project-osrm.org';

  /// Open-Meteo — free weather + elevation API, no key required.
  static const String openMeteoForecastUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String openMeteoElevationUrl = 'https://api.open-meteo.com/v1/elevation';
}

/// Raster/vector tile sources for the map styles. See
/// `lib/src/features/map/map_styles.dart` for how these are assembled into
/// full MapLibre style documents.
abstract final class MapTileEndpoints {
  /// OSM "Carto" standard raster tiles — everyday street style base layer.
  static const String osmRasterTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// OpenTopoMap — contour lines + hillshade + trail-aware styling baked
  /// into the tiles themselves; the closest free equivalent to an
  /// onX/Gaia-style topo basemap. Please read their usage policy before any
  /// real-world traffic: https://opentopomap.org/about#verwendung
  static const String openTopoTemplate = 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';

  /// Esri World Imagery — free-tier satellite raster tiles, no key.
  static const String satelliteTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Esri hillshade overlay, blended on top of satellite/topo for terrain relief.
  static const String hillshadeTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}';

  static const List<String> otmSubdomains = ['a', 'b', 'c'];
}
