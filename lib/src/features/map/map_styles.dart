import 'dart:convert';

import '../../core/network/endpoints.dart';
import '../../state/map_style_provider.dart';

/// Builds MapLibre style documents from raster tile sources.
///
/// Vector tiles would look better (label collision, rotation-aware type,
/// hillshade blending) but every genuinely free/keyless vector tile source
/// requires either self-hosting or a "demo, don't build a real app on
/// this" disclaimer even louder than the raster ones we already lean on —
/// so raster is the honest MVP choice; swapping in a paid vector source
/// (Stadia Maps, MapTiler, self-hosted) later is a one-file change here.
abstract final class MapStyles {
  static String styleJsonFor(MapBaseStyle style, {required bool hillshade}) {
    final doc = switch (style) {
      MapBaseStyle.streets => _streets(),
      MapBaseStyle.satellite => _satellite(hillshade: hillshade),
      MapBaseStyle.topo => _topo(),
    };
    return jsonEncode(doc);
  }

  static Map<String, dynamic> _rasterSource(String tiles, {int tileSize = 256, int maxzoom = 19}) => {
        'type': 'raster',
        'tiles': [tiles],
        'tileSize': tileSize,
        'maxzoom': maxzoom,
      };

  static Map<String, dynamic> _base({required Map<String, dynamic> sources, required List<Map<String, dynamic>> layers}) => {
        'version': 8,
        'name': 'phantom-eye',
        'glyphs': 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
        'sources': sources,
        'layers': layers,
      };

  static Map<String, dynamic> _streets() {
    return _base(
      sources: {
        'osm': _rasterSource(MapTileEndpoints.osmRasterTemplate),
      },
      layers: [
        {
          'id': 'bg',
          'type': 'background',
          'paint': {'background-color': '#0d0f14'},
        },
        {'id': 'osm', 'type': 'raster', 'source': 'osm'},
      ],
    );
  }

  static Map<String, dynamic> _satellite({required bool hillshade}) {
    final sources = <String, dynamic>{
      'satellite': _rasterSource(MapTileEndpoints.satelliteTemplate, maxzoom: 19),
    };
    final layers = <Map<String, dynamic>>[
      {
        'id': 'bg',
        'type': 'background',
        'paint': {'background-color': '#000000'},
      },
      {'id': 'satellite', 'type': 'raster', 'source': 'satellite'},
    ];
    if (hillshade) {
      sources['hillshade'] = _rasterSource(MapTileEndpoints.hillshadeTemplate, maxzoom: 15);
      layers.add({
        'id': 'hillshade',
        'type': 'raster',
        'source': 'hillshade',
        'paint': {'raster-opacity': 0.35},
      });
    }
    return _base(sources: sources, layers: layers);
  }

  static Map<String, dynamic> _topo() {
    return _base(
      sources: {
        'topo': _rasterSource(
          MapTileEndpoints.openTopoTemplate.replaceFirst('{s}', MapTileEndpoints.otmSubdomains.first),
          maxzoom: 17,
        ),
      },
      layers: [
        {
          'id': 'bg',
          'type': 'background',
          'paint': {'background-color': '#e8e4d8'},
        },
        {'id': 'topo', 'type': 'raster', 'source': 'topo'},
      ],
    );
  }
}
