import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';

/// One clustered memory from gallery import (may include several photos/videos).
class MediaGpsClusterCandidate {
  MediaGpsClusterCandidate({
    required this.when,
    required this.latitude,
    required this.longitude,
    required this.items,
    required this.fingerprint,
  });

  final DateTime when;
  final double latitude;
  final double longitude;
  final List<MediaGpsPickedAsset> items;
  final String fingerprint;

  static String buildFingerprint(DateTime when, double lat, double lng) {
    final utc = when.toUtc();
    return 'gallery:${utc.toIso8601String()}:${lat.toStringAsFixed(6)}:${lng.toStringAsFixed(6)}';
  }
}
