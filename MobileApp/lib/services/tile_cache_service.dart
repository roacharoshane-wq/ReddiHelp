import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class TileCacheService {
  static const String _storeName = 'jamaicaOffline';
  static bool _initialized = false;
  static Future<void>? _initializationFuture;

  static Future<void> init() {
    if (_initialized) return Future.value();
    _initializationFuture ??= _initInternal();
    return _initializationFuture!;
  }

  static Future<void> _initInternal() async {
    await FMTCObjectBoxBackend().initialise();
    await FMTCStore(_storeName).manage.create();
    _initialized = true;
  }

  static FMTCTileProvider getTileProvider() {
    if (!_initialized) {
      _initializationFuture ??= _initInternal();
    }
    return FMTCStore(_storeName).getTileProvider();
  }

  /// Download tiles for Jamaica bounding box (zoom 7-14).
  /// Call from a settings page or on first launch.
  static Future<void> downloadJamaicaTiles({
    required String urlTemplate,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final region = RectangleRegion(
      LatLngBounds(
        const LatLng(17.6, -78.5), // SW corner
        const LatLng(18.6, -76.1), // NE corner
      ),
    );

    final downloadable = region.toDownloadable(
      minZoom: 7,
      maxZoom: 14,
      options: TileLayer(urlTemplate: urlTemplate),
    );

    // FMTC v10: startForeground returns a record with two streams
    final result = FMTCStore(_storeName).download.startForeground(
          region: downloadable,
        );

    await for (final progress in result.downloadProgress) {
      onProgress?.call(progress);
    }
  }
}
