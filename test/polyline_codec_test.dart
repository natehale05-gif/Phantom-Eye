import 'package:flutter_test/flutter_test.dart';
import 'package:phantom_eye/src/core/geo/polyline_codec.dart';
import 'package:phantom_eye/src/models/geo_point.dart';

void main() {
  test('decodes the canonical Google polyline example', () {
    // From Google's published encoded polyline algorithm example.
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    final points = PolylineCodec.decode(encoded, precision: 5);
    expect(points.length, 3);
    expect(points[0].latitude, closeTo(38.5, 0.001));
    expect(points[0].longitude, closeTo(-120.2, 0.001));
    expect(points[1].latitude, closeTo(40.7, 0.001));
    expect(points[1].longitude, closeTo(-120.95, 0.001));
    expect(points[2].latitude, closeTo(43.252, 0.001));
    expect(points[2].longitude, closeTo(-126.453, 0.001));
  });

  test('encode -> decode round-trips', () {
    const original = [
      GeoPoint(38.5, -120.2),
      GeoPoint(40.7, -120.95),
      GeoPoint(43.252, -126.453),
    ];
    final encoded = PolylineCodec.encode(original, precision: 5);
    final decoded = PolylineCodec.decode(encoded, precision: 5);
    expect(decoded.length, original.length);
    for (var i = 0; i < original.length; i++) {
      expect(decoded[i].latitude, closeTo(original[i].latitude, 0.00001));
      expect(decoded[i].longitude, closeTo(original[i].longitude, 0.00001));
    }
  });

  test('supports precision 6 (Valhalla polyline6)', () {
    const original = [GeoPoint(45.123456, -122.654321), GeoPoint(45.2, -122.7)];
    final encoded = PolylineCodec.encode(original, precision: 6);
    final decoded = PolylineCodec.decode(encoded, precision: 6);
    expect(decoded[0].latitude, closeTo(original[0].latitude, 0.000001));
    expect(decoded[0].longitude, closeTo(original[0].longitude, 0.000001));
  });
}
