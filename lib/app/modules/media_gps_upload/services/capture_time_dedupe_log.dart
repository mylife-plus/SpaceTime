import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_capture_time.dart';
import 'package:spacetime/app/services/memory_db.dart';

/// Shared debug tag for Add Memories gallery pick ↔ Media GPS capture times.
const String kCaptureTimeDedupeLogTag = '[CaptureTimeDedupe]';

/// Prints filename + filesystem + EXIF timeline so Android TZ mismatches are visible.
class CaptureTimeDedupeLog {
  CaptureTimeDedupeLog._();

  static const _exifHeadBytes = 256 * 1024;

  static const _dateExifKeys = <String>[
    'EXIF DateTimeOriginal',
    'EXIF DateTimeDigitized',
    'EXIF OffsetTime',
    'EXIF OffsetTimeOriginal',
    'EXIF OffsetTimeDigitized',
    'EXIF SubSecTime',
    'EXIF SubSecTimeOriginal',
    'EXIF SubSecTimeDigitized',
    'Image DateTime',
    'GPS GPSDate',
    'EXIF GPSDateStamp',
    'GPS GPSTimeStamp',
  ];

  static void _line(String source, String msg) {
    debugPrint('$kCaptureTimeDedupeLogTag [$source] $msg');
  }

  static String _fmt(DateTime? dt) {
    if (dt == null) return 'null';
    return '${dt.toIso8601String()} local=${dt.toLocal().toIso8601String()} '
        'isUtc=${dt.isUtc} epochSec=${dt.millisecondsSinceEpoch ~/ 1000} '
        'wall=${MediaCaptureTime.wallClock(dt).toIso8601String()}';
  }

  /// Memory View / file-picker path — full FS + EXIF dump.
  static Future<void> logPickedFile({
    required String source,
    required String path,
    required String mediaKind,
    DateTime? resolvedCaptureTime,
    String? galleryAssetId,
  }) async {
    final name = p.basename(path);
    _line(source, '—— file="$name" kind=$mediaKind ——');
    _line(source, 'path=$path');
    if (galleryAssetId != null && galleryAssetId.isNotEmpty) {
      _line(source, 'galleryAssetId=$galleryAssetId');
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        _line(source, 'EXISTS=false');
        return;
      }
      final stat = await file.stat();
      _line(
        source,
        'fs size=${stat.size} modified=${_fmt(stat.modified)} '
        'accessed=${_fmt(stat.accessed)} changed=${_fmt(stat.changed)} '
        'type=${stat.type}',
      );

      if (mediaKind == 'image') {
        await _logExifTimeline(source, file);
      } else if (mediaKind == 'video') {
        await _logVideoMvhd(source, file);
      } else {
        _line(source, 'exif=skipped (not image/video)');
      }

      final capture = resolvedCaptureTime;
      if (capture != null) {
        final key = DatabaseHelper.mediaTimeKindDedupeKey(capture, mediaKind);
        _line(source, 'resolvedCapture=${_fmt(capture)} dedupeKey=$key');
      } else {
        _line(source, 'resolvedCapture=null');
      }
    } catch (e, st) {
      _line(source, 'ERROR $e\n$st');
    }
  }

  /// Media GPS gallery / file asset (PhotoManager or file pick).
  static void logGalleryAsset({
    required String source,
    required MediaGpsPickedAsset asset,
    bool? alreadyImported,
  }) {
    final name = (asset.fileTitle?.isNotEmpty == true)
        ? asset.fileTitle!
        : (asset.localPath != null ? p.basename(asset.localPath!) : asset.id);
    final kind = asset.isVideo ? 'video' : (asset.isImage ? 'image' : 'other');
    final key = DatabaseHelper.mediaTimeKindDedupeKey(asset.createTime, kind);
    _line(source, '—— file="$name" kind=$kind ——');
    _line(
      source,
      'id=${asset.id} fromFile=${asset.isFromFile} hasGps=${asset.hasGps} '
      'path=${asset.localPath ?? "-"}',
    );
    _line(source, 'createTime=${_fmt(asset.createTime)}');
    _line(source, 'modifiedTime=${_fmt(asset.modifiedTime)}');
    _line(
      source,
      'dedupeKey=$key'
      '${alreadyImported == null ? '' : ' alreadyImported=$alreadyImported'}',
    );
    if (asset.entity != null) {
      final e = asset.entity!;
      _line(
        source,
        'photoManager createDateTime=${_fmt(e.createDateTime)} '
        'modifiedDateTime=${_fmt(e.modifiedDateTime)} '
        'type=${e.type} w=${e.width} h=${e.height} '
        'durationMs=${e.videoDuration.inMilliseconds}',
      );
    }
  }

  static Future<void> _logVideoMvhd(String source, File file) async {
    try {
      final bytes = await MediaCaptureTime.readVideoProbeBytes(file)
          .timeout(const Duration(seconds: 2));
      final mvhd = MediaCaptureTime.parseMp4Mvhd(bytes);
      _line(
        source,
        'mvhd createdAt=${_fmt(mvhd.createdAt)} durationMs=${mvhd.durationMs}',
      );
    } catch (e) {
      _line(source, 'mvhdERROR $e');
    }
  }

  static Future<void> _logExifTimeline(String source, File file) async {
    try {
      final raf = await file.open();
      final Uint8List bytes;
      try {
        final len = await raf.length();
        final n = math.min(len, _exifHeadBytes);
        bytes = n <= 0 ? Uint8List(0) : await raf.read(n);
      } finally {
        await raf.close();
      }
      if (bytes.isEmpty) {
        _line(source, 'exif=empty-head');
        return;
      }
      final data = await readExifFromBytes(bytes);
      if (data.isEmpty) {
        _line(source, 'exif=no-tags');
        return;
      }

      final parts = <String>[];
      for (final key in _dateExifKeys) {
        final v = data[key]?.printable;
        if (v != null && v.isNotEmpty) parts.add('$key=$v');
      }
      if (parts.isEmpty) {
        _line(source, 'exifDates=(none of known date tags)');
      } else {
        _line(source, 'exifDates ${parts.join(' | ')}');
      }

      final raw = data['EXIF DateTimeOriginal']?.printable ??
          data['Image DateTime']?.printable ??
          data['EXIF DateTimeDigitized']?.printable;
      final parsed = MediaCaptureTime.parseExif(raw);
      _line(
        source,
        'exifParsedRaw="$raw" parsed=${_fmt(parsed)}',
      );
    } catch (e) {
      _line(source, 'exifERROR $e');
    }
  }
}
