import 'package:photo_manager/photo_manager.dart';

/// One gallery item: GPS when the OS library still has it, plus other library metadata.
/// Stripped EXIF (e.g. WhatsApp) removes coordinates; that data cannot be recreated from the file here.
class MediaGpsPickedAsset {
  MediaGpsPickedAsset({
    required this.entity,
    required this.createTime,
    this.latitude,
    this.longitude,
    this.width = 0,
    this.height = 0,
    this.orientation = 0,
    required this.modifiedTime,
    this.fileTitle,
    this.videoDuration = Duration.zero,
  });

  final AssetEntity entity;
  final DateTime createTime;
  final double? latitude;
  final double? longitude;
  final int width;
  final int height;
  final int orientation;
  final DateTime modifiedTime;
  final String? fileTitle;
  final Duration videoDuration;

  String get id => entity.id;

  bool get isVideo => entity.type == AssetType.video;

  bool get isAudio => entity.type == AssetType.audio;

  bool get hasGps =>
      latitude != null &&
      longitude != null &&
      latitude!.abs() > 1e-6 &&
      longitude!.abs() > 1e-6;

  /// Short line for UI: size, date, optional video length (library metadata, not full EXIF).
  String get libraryMetadataSubtitle {
    final parts = <String>[];
    if (width > 0 && height > 0) {
      parts.add('$width×$height');
    }
    if ((isVideo || isAudio) && videoDuration > Duration.zero) {
      final s = videoDuration.inSeconds;
      parts.add(s >= 3600
          ? '${videoDuration.inHours}h ${(s % 3600) ~/ 60}m'
          : s >= 60
              ? '${s ~/ 60}m ${s % 60}s'
              : '${s}s');
    }
    parts.add(_shortDate(createTime));
    return parts.join(' · ');
  }

  static String _shortDate(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/'
        '${l.year}';
  }
}
