import '../../models/geo_point.dart';

/// Decoder for Google/OSRM/Valhalla-style encoded polylines.
///
/// This is the standard published algorithm (Google's "Encoded Polyline
/// Algorithm Format"); OSRM uses precision 5, Valhalla defaults to
/// precision 6 ("polyline6") — both routing services report which
/// precision they used in the response, so callers pass it in explicitly
/// rather than guessing.
abstract final class PolylineCodec {
  static List<GeoPoint> decode(String encoded, {int precision = 5}) {
    final factor = _pow10(precision);
    final points = <GeoPoint>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      lat += _decodeSignedValue(encoded, index).value;
      index = _decodeSignedValue(encoded, index).nextIndex;

      lng += _decodeSignedValue(encoded, index).value;
      index = _decodeSignedValue(encoded, index).nextIndex;

      points.add(GeoPoint(lat / factor, lng / factor));
    }
    return points;
  }

  static String encode(List<GeoPoint> points, {int precision = 5}) {
    final factor = _pow10(precision);
    final buffer = StringBuffer();
    var prevLat = 0;
    var prevLng = 0;

    for (final p in points) {
      final lat = (p.latitude * factor).round();
      final lng = (p.longitude * factor).round();
      _encodeSignedValue(lat - prevLat, buffer);
      _encodeSignedValue(lng - prevLng, buffer);
      prevLat = lat;
      prevLng = lng;
    }
    return buffer.toString();
  }

  static double _pow10(int precision) {
    double f = 1;
    for (var i = 0; i < precision; i++) {
      f *= 10;
    }
    return f;
  }

  static ({int value, int nextIndex}) _decodeSignedValue(String encoded, int index) {
    var result = 0;
    var shift = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final value = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    return (value: value, nextIndex: index);
  }

  static void _encodeSignedValue(int value, StringBuffer buffer) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      buffer.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    buffer.writeCharCode(v + 63);
  }
}
