import 'package:photo_manager/photo_manager.dart';

/// Gallery library item or a file picked via the system file browser.
enum MediaGpsAssetSource { gallery, file }

enum MediaGpsFileKind { image, video, audio, unknown }

/// One importable item with GPS when metadata still has coordinates.
class MediaGpsPickedAsset {
  MediaGpsPickedAsset._({
    required this.source,
    required this.id,
    required this.createTime,
    this.latitude,
    this.longitude,
    this.width = 0,
    this.height = 0,
    this.orientation = 0,
    required this.modifiedTime,
    this.fileTitle,
    this.videoDuration = Duration.zero,
    this.entity,
    this.localPath,
    this.fileKind = MediaGpsFileKind.unknown,
  });

  factory MediaGpsPickedAsset.fromGallery({
    required AssetEntity entity,
    required DateTime createTime,
    double? latitude,
    double? longitude,
    int width = 0,
    int height = 0,
    int orientation = 0,
    required DateTime modifiedTime,
    String? fileTitle,
    Duration videoDuration = Duration.zero,
  }) {
    return MediaGpsPickedAsset._(
      source: MediaGpsAssetSource.gallery,
      id: entity.id,
      entity: entity,
      createTime: createTime,
      latitude: latitude,
      longitude: longitude,
      width: width,
      height: height,
      orientation: orientation,
      modifiedTime: modifiedTime,
      fileTitle: fileTitle,
      videoDuration: videoDuration,
    );
  }

  factory MediaGpsPickedAsset.fromFile({
    required String id,
    required String localPath,
    required MediaGpsFileKind fileKind,
    required DateTime createTime,
    double? latitude,
    double? longitude,
    int width = 0,
    int height = 0,
    required DateTime modifiedTime,
    String? fileTitle,
    Duration videoDuration = Duration.zero,
  }) {
    return MediaGpsPickedAsset._(
      source: MediaGpsAssetSource.file,
      id: id,
      localPath: localPath,
      fileKind: fileKind,
      createTime: createTime,
      latitude: latitude,
      longitude: longitude,
      width: width,
      height: height,
      modifiedTime: modifiedTime,
      fileTitle: fileTitle,
      videoDuration: videoDuration,
    );
  }

  final MediaGpsAssetSource source;
  final String id;
  final AssetEntity? entity;
  final String? localPath;
  final MediaGpsFileKind fileKind;
  final DateTime createTime;
  final double? latitude;
  final double? longitude;
  final int width;
  final int height;
  final int orientation;
  final DateTime modifiedTime;
  final String? fileTitle;
  final Duration videoDuration;

  bool get isFromFile => source == MediaGpsAssetSource.file;

  bool get isFromGallery => source == MediaGpsAssetSource.gallery;

  bool get isVideo {
    if (isFromFile) {
      return fileKind == MediaGpsFileKind.video;
    }
    return entity?.type == AssetType.video;
  }

  bool get isAudio {
    if (isFromFile) {
      return fileKind == MediaGpsFileKind.audio;
    }
    return entity?.type == AssetType.audio;
  }

  bool get isImage {
    if (isFromFile) {
      return fileKind == MediaGpsFileKind.image;
    }
    final e = entity;
    if (e == null) return false;
    return e.type == AssetType.image;
  }

  bool get hasGps =>
      latitude != null &&
      longitude != null &&
      latitude!.abs() > 1e-6 &&
      longitude!.abs() > 1e-6;

  /// Short line for UI: size, date, optional video length.
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
