import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Shared capture-time helpers for Add Memories ↔ Media GPS dedupe.
///
/// EXIF DateTimeOriginal has no timezone (camera wall-clock). PhotoManager on
/// Android returns MediaStore DATE_TAKEN as a real UTC instant. Naively calling
/// `.toUtc()` on a locally-parsed EXIF string shifts the clock by the device
/// offset (e.g. −5h on UTC+5) while gallery times stay correct — iOS often
/// lined up by luck, Android did not.
///
/// Android FilePicker copies videos into cache — [File.stat.modified] is the
/// **copy** time, not capture. Prefer MP4/MOV [mvhd] creation time instead.
class MediaCaptureTime {
  MediaCaptureTime._();

  /// QuickTime/MP4 epoch: 1904-01-01 UTC.
  static final DateTime _mp4Epoch = DateTime.utc(1904, 1, 1);

  /// Parse EXIF `yyyy:MM:dd HH:mm:ss` as a **local wall-clock** DateTime.
  static DateTime? parseExif(String? raw) {
    if (raw == null || raw.length < 19) return null;
    final normalized = raw
        .replaceFirst(':', '-')
        .replaceFirst(':', '-')
        .replaceAll(' ', 'T');
    final m = RegExp(
      r'(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(normalized);
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  /// Wall-clock y/m/d h/m/s for stable cross-source keys (ignores TZ shifts).
  static DateTime wallClock(DateTime dt) {
    final l = dt.toLocal();
    return DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second);
  }

  /// UTC epoch **seconds** of the local wall-clock (not timezone-shifted instant).
  static int dedupeEpochSeconds(DateTime dt) {
    final w = wallClock(dt);
    return DateTime.utc(
          w.year,
          w.month,
          w.day,
          w.hour,
          w.minute,
          w.second,
        ).millisecondsSinceEpoch ~/
        1000;
  }

  /// Creation time + duration from MP4/MOV `mvhd` (scan head+tail of [bytes]).
  static ({DateTime? createdAt, int durationMs}) parseMp4Mvhd(Uint8List bytes) {
    DateTime? createdAt;
    var durationMs = 0;
    final limit = bytes.length - 24;
    for (var i = 0; i < limit; i++) {
      if (bytes[i] != 0x6d ||
          bytes[i + 1] != 0x76 ||
          bytes[i + 2] != 0x68 ||
          bytes[i + 3] != 0x64) {
        continue;
      }
      final version = bytes[i + 4];
      final base = i + 8; // past 'mvhd' + version + flags
      try {
        if (version == 1) {
          if (base + 28 > bytes.length) continue;
          final ct = _readU64be(bytes, base);
          final timescale = _readU32be(bytes, base + 16);
          final duration = _readU64be(bytes, base + 20);
          createdAt ??= _mp4SecondsToDateTime(ct);
          if (timescale > 0 && duration > 0) {
            durationMs = ((duration * 1000) ~/ timescale);
          }
          if (createdAt != null) break;
        } else {
          if (base + 16 > bytes.length) continue;
          final ct = _readU32be(bytes, base);
          final timescale = _readU32be(bytes, base + 8);
          final duration = _readU32be(bytes, base + 12);
          createdAt ??= _mp4SecondsToDateTime(ct);
          if (timescale > 0 && duration > 0) {
            durationMs = ((duration * 1000) ~/ timescale);
          }
          if (createdAt != null) break;
        }
      } catch (_) {
        // Malformed atom — keep scanning.
      }
    }
    return (createdAt: createdAt, durationMs: durationMs);
  }

  static DateTime? _mp4SecondsToDateTime(int secondsSince1904) {
    if (secondsSince1904 <= 0) return null;
    // Clamp absurd values (corrupt atoms).
    if (secondsSince1904 > 4000000000) return null;
    final utc = _mp4Epoch.add(Duration(seconds: secondsSince1904));
    if (utc.year < 1990 || utc.year > 2100) return null;
    return wallClock(utc);
  }

  static int _readU32be(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _readU64be(Uint8List b, int o) {
    // Creation times fit in 32-bit until year ~2040; read low 32 if high is 0.
    final hi = _readU32be(b, o);
    final lo = _readU32be(b, o + 4);
    if (hi == 0) return lo;
    return (hi << 32) + lo;
  }

  /// Read head+tail windows so moov-at-end files still yield `mvhd`.
  static Future<Uint8List> readVideoProbeBytes(
    File file, {
    int headMax = 2 * 1024 * 1024,
    int tailMax = 1 * 1024 * 1024,
  }) async {
    final raf = await file.open();
    try {
      final len = await raf.length();
      if (len <= 0) return Uint8List(0);
      final headLen = math.min(len, headMax);
      final head = await raf.read(headLen);
      if (len <= headLen) return head;
      final tailSize = math.min(len - headLen, tailMax);
      await raf.setPosition(len - tailSize);
      final tail = await raf.read(tailSize);
      final out = Uint8List(head.length + tail.length);
      out.setRange(0, head.length, head);
      out.setRange(head.length, out.length, tail);
      return out;
    } finally {
      await raf.close();
    }
  }
}
