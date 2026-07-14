import 'package:gpx/gpx.dart';

import '../models/geo_point.dart';
import '../models/route_result.dart';
import '../models/saved_route.dart';
import '../models/track.dart';
import '../models/waypoint.dart';

/// GPX 1.1 import/export — the universal interchange format for
/// tracks/routes/waypoints, so a recorded track or a custom-built route can
/// round-trip with Gaia GPS, onX, Garmin, CalTopo, etc.
class GpxService {
  String exportTrack(Track track) {
    final gpx = Gpx()
      ..creator = 'Phantom Eye'
      ..metadata = (Metadata()..name = track.name)
      ..trks = [
        Trk(
          name: track.name,
          trksegs: [
            Trkseg(
              trkpts: track.points
                  .map((p) => Wpt(
                        lat: p.point.latitude,
                        lon: p.point.longitude,
                        ele: p.elevationMeters,
                        time: p.timestamp,
                      ))
                  .toList(),
            ),
          ],
        ),
      ];
    return GpxWriter().asXml(gpx).toXmlString(pretty: true);
  }

  String exportRoute(SavedRoute route) {
    final gpx = Gpx()
      ..creator = 'Phantom Eye'
      ..metadata = (Metadata()..name = route.name)
      ..rtes = [
        Rte(
          name: route.name,
          rtepts: route.path.map((p) => Wpt(lat: p.latitude, lon: p.longitude)).toList(),
        ),
      ];
    return GpxWriter().asXml(gpx).toXmlString(pretty: true);
  }

  String exportWaypoints(List<Waypoint> waypoints) {
    final gpx = Gpx()
      ..creator = 'Phantom Eye'
      ..wpts = waypoints
          .map((w) => Wpt(
                lat: w.point.latitude,
                lon: w.point.longitude,
                name: w.name,
                desc: w.notes,
                ele: w.elevationMeters,
                time: w.createdAt,
              ))
          .toList();
    return GpxWriter().asXml(gpx).toXmlString(pretty: true);
  }

  /// Parses any GPX file into whatever it contains — tracks, routes, and/or
  /// waypoints — so a single "Import GPX" action in Settings can handle
  /// files exported from any other app.
  GpxImportResult importGpx(String xml) {
    final gpx = GpxReader().fromString(xml);

    final tracks = <Track>[];
    for (final trk in gpx.trks) {
      for (final seg in trk.trksegs) {
        if (seg.trkpts.isEmpty) continue;
        final points = seg.trkpts
            .map((pt) => TimedPoint(
                  GeoPoint(pt.lat ?? 0, pt.lon ?? 0),
                  pt.time ?? DateTime.now(),
                  elevationMeters: pt.ele,
                ))
            .toList();
        tracks.add(
          Track(
            name: trk.name ?? 'Imported track',
            points: points,
            startedAt: points.first.timestamp,
            endedAt: points.last.timestamp,
            distanceMeters: _pathLength(points.map((p) => p.point).toList()),
          ),
        );
      }
    }

    final routes = <SavedRoute>[];
    for (final rte in gpx.rtes) {
      if (rte.rtepts.isEmpty) continue;
      final path = rte.rtepts.map((pt) => GeoPoint(pt.lat ?? 0, pt.lon ?? 0)).toList();
      routes.add(
        SavedRoute(
          name: rte.name ?? 'Imported route',
          path: path,
          profile: TravelProfile.drive,
          distanceMeters: _pathLength(path),
          durationSeconds: 0,
        ),
      );
    }

    final waypoints = gpx.wpts
        .map((pt) => Waypoint(
              name: pt.name ?? 'Waypoint',
              point: GeoPoint(pt.lat ?? 0, pt.lon ?? 0),
              notes: pt.desc,
              elevationMeters: pt.ele,
              createdAt: pt.time,
            ))
        .toList();

    return GpxImportResult(tracks: tracks, routes: routes, waypoints: waypoints);
  }

  double _pathLength(List<GeoPoint> points) {
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += GeoMath.distanceMeters(points[i], points[i + 1]);
    }
    return total;
  }
}

class GpxImportResult {
  const GpxImportResult({required this.tracks, required this.routes, required this.waypoints});

  final List<Track> tracks;
  final List<SavedRoute> routes;
  final List<Waypoint> waypoints;

  bool get isEmpty => tracks.isEmpty && routes.isEmpty && waypoints.isEmpty;
}
