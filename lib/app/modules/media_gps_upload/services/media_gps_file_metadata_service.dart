import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:video_player/video_player.dart';

/// Reads GPS coordinates and capture time from image EXIF and container metadata.
class MediaGpsFileMetadataService {
  static const _imageExt = {
    'jpg',
    'jpeg',
    'png',
    'heic',
    'heif',
    'webp',
    'tif',
    'tiff',
    'dng',
  };
  static const _videoExt = {
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mkv',
    '3gp',
    'webm',
  };
  static const _audioExt = {
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
  };

  static MediaGpsFileKind kindForPath(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (_imageExt.contains(ext)) return MediaGpsFileKind.image;
    if (_videoExt.contains(ext)) return MediaGpsFileKind.video;
    if (_audioExt.contains(ext)) return MediaGpsFileKind.audio;
    return MediaGpsFileKind.unknown;
  }

  static bool isSupportedMediaPath(String path) => isPickableMediaPath(path);

  /// Images and videos only — no audio, documents, or other types.
  static bool isPickableMediaPath(String path) {
    final kind = kindForPath(path);
    return kind == MediaGpsFileKind.image || kind == MediaGpsFileKind.video;
  }

  static const List<String> pickableFileExtensions = [
    'jpg',
    'jpeg',
    'png',
    'heic',
    'heif',
    'webp',
    'tif',
    'tiff',
    'dng',
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mkv',
    '3gp',
    'webm',
  ];

  static bool isAllowedPickerExtension(String? extension, String path) {
    var ext = extension?.toLowerCase() ?? '';
    if (ext.startsWith('.')) ext = ext.substring(1);
    if (ext.isEmpty) {
      ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    }
    return pickableFileExtensions.contains(ext);
  }

  static Future<({
    double? latitude,
    double? longitude,
    DateTime? createTime,
    Duration videoDuration,
  })> readMetadata(String path) async {
    final kind = kindForPath(path);
    final file = File(path);
    if (!await file.exists()) {
      return (latitude: null, longitude: null, createTime: null, videoDuration: Duration.zero);
    }

    DateTime? createTime;
    Duration videoDuration = Duration.zero;
    double? lat;
    double? lng;

    try {
      final stat = await file.stat();
      createTime = stat.modified;
    } catch (_) {}

    if (kind == MediaGpsFileKind.image) {
      final exif = await _readImageExif(path);
      lat ??= exif.latitude;
      lng ??= exif.longitude;
      createTime = exif.createTime ?? createTime;
    } else if (kind == MediaGpsFileKind.video) {
      final loc = await _readVideoLocation(path);
      lat = loc.latitude;
      lng = loc.longitude;
      createTime = loc.createTime ?? createTime;
      videoDuration = await _readVideoDuration(path);
      if (lat == null || lng == null) {
        final exif = await _readImageExif(path);
        lat ??= exif.latitude;
        lng ??= exif.longitude;
        createTime = exif.createTime ?? createTime;
      }
    } else if (kind == MediaGpsFileKind.audio) {
      final loc = await _scanContainerForGps(path);
      lat = loc.latitude;
      lng = loc.longitude;
    }

    if (lat == null || lng == null) {
      final scanned = await _scanContainerForGps(path);
      lat ??= scanned.latitude;
      lng ??= scanned.longitude;
      createTime ??= scanned.createTime;
    }

    return (
      latitude: lat,
      longitude: lng,
      createTime: createTime,
      videoDuration: videoDuration,
    );
  }

  static Future<({
    double? latitude,
    double? longitude,
    DateTime? createTime,
  })> _readImageExif(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) {
        return (latitude: null, longitude: null, createTime: null);
      }
      final data = await readExifFromBytes(bytes);
      if (data.isEmpty) {
        return (latitude: null, longitude: null, createTime: null);
      }
      final gps = data['GPS GPSLatitude'];
      final latRef = data['GPS GPSLatitudeRef']?.printable;
      final gpsLng = data['GPS GPSLongitude'];
      final lngRef = data['GPS GPSLongitudeRef']?.printable;
      final lat = _dmsToDecimal(gps, latRef);
      final lng = _dmsToDecimal(gpsLng, lngRef);
      final when = _parseExifDate(
        data['EXIF DateTimeOriginal']?.printable ??
            data['Image DateTime']?.printable ??
            data['EXIF DateTimeDigitized']?.printable,
      );
      return (latitude: lat, longitude: lng, createTime: when);
    } catch (e, st) {
      debugPrint('[MediaGpsFileMetadata] image exif $path: $e\n$st');
      return (latitude: null, longitude: null, createTime: null);
    }
  }

  static Future<({
    double? latitude,
    double? longitude,
    DateTime? createTime,
  })> _readVideoLocation(String path) async {
    final scanned = await _scanContainerForGps(path);
    if (scanned.latitude != null && scanned.longitude != null) {
      return scanned;
    }
    return (latitude: null, longitude: null, createTime: null);
  }

  static Future<Duration> _readVideoDuration(String path) async {
    VideoPlayerController? vc;
    try {
      vc = VideoPlayerController.file(File(path));
      await vc.initialize();
      return vc.value.duration;
    } catch (_) {
      return Duration.zero;
    } finally {
      await vc?.dispose();
    }
  }

  static Future<({
    double? latitude,
    double? longitude,
    DateTime? createTime,
  })> _scanContainerForGps(String path) async {
    try {
      final file = File(path);
      final len = await file.length();
      if (len == 0) {
        return (latitude: null, longitude: null, createTime: null);
      }
      const headMax = 48 * 1024 * 1024;
      const tailMax = 8 * 1024 * 1024;
      final headLen = len < headMax ? len : headMax;
      final raf = await file.open();
      try {
        final head = await raf.read(headLen);
        final loc = _parseIso6709FromBytes(head);
        if (loc != null) {
          return (
            latitude: loc.$1,
            longitude: loc.$2,
            createTime: null,
          );
        }
        if (len > headLen) {
          final tailSize = len - headLen > tailMax ? tailMax : len - headLen;
          await raf.setPosition(len - tailSize);
          final tail = await raf.read(tailSize);
          final locTail = _parseIso6709FromBytes(tail);
          if (locTail != null) {
            return (
              latitude: locTail.$1,
              longitude: locTail.$2,
              createTime: null,
            );
          }
        }
      } finally {
        await raf.close();
      }
    } catch (e, st) {
      debugPrint('[MediaGpsFileMetadata] scan $path: $e\n$st');
    }
    return (latitude: null, longitude: null, createTime: null);
  }

  /// ISO6709 e.g. +37.3318-122.0302/ or +37.3318+122.0302/
  /// Requires at least 4 decimal places to avoid false-positive matches in
  /// binary data (version strings, matrix values, etc.). Prefers the strict
  /// ISO 6709 form that ends with `/` over the relaxed form without it.
  static (double, double)? _parseIso6709FromBytes(Uint8List bytes) {
    final text = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

    // Strict: trailing `/` + 4+ decimals — standard iPhone/MOV GPS atom format.
    final reStrict = RegExp(
      r'([+-])(\d{1,2}\.\d{4,})([+-])(\d{1,3}\.\d{4,})/',
    );
    // Relaxed: no slash but still 4+ decimals — handles edge-case containers.
    final reLax = RegExp(
      r'([+-])(\d{1,2}\.\d{4,})([+-])(\d{1,3}\.\d{4,})',
    );

    for (final re in [reStrict, reLax]) {
      for (final m in re.allMatches(text)) {
        final latSign = m.group(1) == '-' ? -1.0 : 1.0;
        final lat = double.tryParse(m.group(2) ?? '');
        final lngSign = m.group(3) == '-' ? -1.0 : 1.0;
        final lng = double.tryParse(m.group(4) ?? '');
        if (lat == null || lng == null) continue;
        final la = lat * latSign;
        final lo = lng * lngSign;
        if (la.abs() <= 90 && lo.abs() <= 180 &&
            (la.abs() > 1e-4 || lo.abs() > 1e-4)) {
          return (la, lo);
        }
      }
    }
    return null;
  }

  static double? _dmsToDecimal(dynamic dms, String? ref) {
    if (dms == null) return null;
    try {
      List<double> values;
      if (dms is List) {
        values = dms.map((e) => (e as num).toDouble()).toList();
      } else if (dms is IfdTag) {
        values = dms.values.toList().map((e) {
          if (e is Ratio) return e.toDouble();
          if (e is num) return e.toDouble();
          return 0.0;
        }).toList();
      } else {
        return null;
      }
      if (values.length < 3) return null;
      var decimal = values[0] + values[1] / 60 + values[2] / 3600;
      final r = ref?.toUpperCase();
      if (r == 'S' || r == 'W') decimal = -decimal;
      return decimal;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseExifDate(String? raw) {
    if (raw == null || raw.length < 10) return null;
    try {
      final normalized = raw.replaceFirst(':', '-').replaceFirst(':', '-');
      return DateTime.tryParse(normalized.replaceAll(' ', 'T'));
    } catch (_) {
      return null;
    }
  }
}
