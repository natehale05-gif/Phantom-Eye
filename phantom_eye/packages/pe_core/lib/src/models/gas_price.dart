/// A user-reported fuel price at one station.
///
/// Mirrors `GasPriceReport` in `src/gasprices.ts:9`. There is no free,
/// keyless API for live per-station fuel prices, so — as GasBuddy and Waze
/// did at the start — the app remembers what you report at the pump.
final class GasPriceReport {
  const GasPriceReport({
    required this.pricePerGallon,
    required this.reportedAt,
  });

  final double pricePerGallon;
  final DateTime reportedAt;

  static GasPriceReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final price = json['price'];
    final reportedAt = json['reportedAt'];
    if (price is! num || !price.isFinite || price <= 0) return null;
    if (reportedAt is! String) return null;
    final at = DateTime.tryParse(reportedAt);
    if (at == null) return null;
    return GasPriceReport(pricePerGallon: price.toDouble(), reportedAt: at);
  }

  Map<String, dynamic> toJson() => {
    'price': pricePerGallon,
    'reportedAt': reportedAt.toIso8601String(),
  };

  @override
  String toString() =>
      'GasPriceReport($pricePerGallon @ ${reportedAt.toIso8601String()})';
}
