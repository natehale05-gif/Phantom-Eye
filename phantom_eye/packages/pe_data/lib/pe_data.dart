/// Pure-Dart network clients and response parsers for Phantom Eye.
///
/// Two rules keep this layer testable without a network or a device:
///  - every client takes an injected `http.Client`, so tests supply
///    `MockClient`;
///  - every response parser is a pure function over already-decoded JSON,
///    separate from the IO that fetched it.
///
/// Like `pe_core` and `pe_domain`, this package must never depend on Flutter.
/// Storage lives behind interfaces here; the concrete drift / secure-storage
/// implementations belong to a later Flutter package.
library;

export 'src/parse/open_meteo_parser.dart';
export 'src/parse/osrm_parser.dart';
export 'src/parse/photon_parser.dart';
export 'src/remote/open_meteo_client.dart';
export 'src/remote/overpass_client.dart';
export 'src/remote/photon_client.dart';
export 'src/remote/reverse_geocoder.dart';
