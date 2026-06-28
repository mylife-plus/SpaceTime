import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'package:spacetime/app/modules/gpx_kmz_upload/models/kmz_ignore_rule.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_inspector.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/spacetime_backup_zip.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_parser.dart';
import 'package:spacetime/app/services/memory_db.dart';

/// One clustered memory candidate (representative point + time).
class KmzMemoryCandidate {
  KmzMemoryCandidate({
    required this.latitude,
    required this.longitude,
    required this.when,
    required this.fingerprint,
  });

  final double latitude;
  final double longitude;
  final DateTime when;
  final String fingerprint;
}

/// Thrown when the picked file is not a readable GPX/KMZ track archive.
class InvalidTrackFileException implements Exception {
  InvalidTrackFileException([this.reason = 'invalid']);

  final String reason;

  @override
  String toString() => 'InvalidTrackFileException($reason)';
}

class KmzImportStats {
  KmzImportStats({
    required this.rawEntries,
    required this.ignoredEntries,
    required this.duplicateEntries,
    required this.totalAfterFilter,
    required this.newMemories,
    required this.candidates,
  });

  final int rawEntries;
  final int ignoredEntries;
  final int duplicateEntries;
  final int totalAfterFilter;
  final int newMemories;
  final List<KmzMemoryCandidate> candidates;
}

class KmzImportPipeline {
  static Archive? _decodeZipArchive(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (e, st) {
      debugPrint('[KmzImportPipeline] zip decode failed: $e\n$st');
      return null;
    }
  }

  static bool _archiveHasTrackData(Archive archive) {
    for (final f in archive) {
      final n = f.name.toLowerCase();
      if (n.endsWith('.kml') || n.endsWith('.gpx')) return true;
    }
    return false;
  }

  static bool _looksLikeGpxXml(String xml) {
    final lower = xml.toLowerCase();
    return lower.contains('<gpx') || lower.contains('<trkpt');
  }

  static List<KmzTrackPoint> _parseGpxBytes(List<int> bytes) {
    final xml = utf8.decode(bytes, allowMalformed: true);
    _debugLogGpxFileData(xml);
    var pts = KmzKmlParser.parseGpxString(xml);
    return pts;
  }

  static Duration durationForTimeKey(String key) {
    switch (key) {
      case 'gpx_dd_time_1m':
        return const Duration(minutes: 1);
      case 'gpx_dd_time_2m':
        return const Duration(minutes: 2);
      case 'gpx_dd_time_5m':
        return const Duration(minutes: 5);
      case 'gpx_dd_time_10m':
        return const Duration(minutes: 10);
      case 'gpx_dd_time_15m':
        return const Duration(minutes: 15);
      case 'gpx_dd_time_30m':
        return const Duration(minutes: 30);
      case 'gpx_dd_time_1h':
        return const Duration(hours: 1);
      default:
        return const Duration(minutes: 5);
    }
  }

  static double metersForDistanceKey(String key) {
    switch (key) {
      case 'gpx_dd_dist_10m':
        return 10;
      case 'gpx_dd_dist_25m':
        return 25;
      case 'gpx_dd_dist_50m':
        return 50;
      case 'gpx_dd_dist_100m':
        return 100;
      case 'gpx_dd_dist_250m':
        return 250;
      case 'gpx_dd_dist_500m':
        return 500;
      case 'gpx_dd_dist_1km':
        return 1000;
      default:
        return 50;
    }
  }

  static const Distance _distance = Distance();

  static double metersBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return _distance.as(
      LengthUnit.Meter,
      LatLng(lat1, lng1),
      LatLng(lat2, lng2),
    );
  }

  static String fingerprintFor(DateTime when, double lat, double lng) {
    final utc = when.toUtc();
    return 'kmz:${utc.toIso8601String()}:${lat.toStringAsFixed(6)}:${lng.toStringAsFixed(6)}';
  }

  /// Parse KMZ/GPX with ignore rules.
  static Future<List<KmzTrackPoint>> loadPointsFiltered(
    String filePath, {
    required String ignoreMarkerSub,
    required String ignoreContainsSub,
    List<KmzIgnoreRule> structuredRules = const [],
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return [];
    final baseUtc = (await file.lastModified()).toUtc();
    final lower = filePath.toLowerCase();
    final marker = ignoreMarkerSub.trim();
    final contains = ignoreContainsSub.trim();
    if (lower.endsWith('.gpx')) {
      final bytes = await file.readAsBytes();
      var pts = _parseGpxBytes(bytes);
      if (structuredRules.isNotEmpty) {
        pts = pts.where((p) => !_gpxPointIgnoredByRules(p, structuredRules)).toList();
      }
      pts = _applyTrackPointTimeRules(pts, structuredRules);
      final normalized = normalizeTimes(
        pts,
        baseUtc: baseUtc,
        missingStep: const Duration(minutes: 1),
      );
      _debugLogGpxParsedPoints(normalized);
      return normalized;
    }

    final bytes = await file.readAsBytes();
    // Some GPX files come with wrong extension; support them by content sniff.
    final rawText = utf8.decode(bytes, allowMalformed: true);
    if (_looksLikeGpxXml(rawText)) {
      var pts = KmzKmlParser.parseGpxString(rawText);
      if (structuredRules.isNotEmpty) {
        pts = pts.where((p) => !_gpxPointIgnoredByRules(p, structuredRules)).toList();
      }
      pts = _applyTrackPointTimeRules(pts, structuredRules);
      final normalized = normalizeTimes(
        pts,
        baseUtc: baseUtc,
        missingStep: const Duration(minutes: 1),
      );
      _debugLogGpxParsedPoints(normalized);
      return normalized;
    }

    final archive = _decodeZipArchive(bytes);
    if (archive != null && SpaceTimeBackupZip.archiveIsBackup(archive)) {
      throw InvalidTrackFileException('spacetime_backup');
    }
    if (archive == null || !_archiveHasTrackData(archive)) {
      throw InvalidTrackFileException('zip_no_track_data');
    }
    final zipNames = archive.map((f) => f.name).toList();
    ArchiveFile? kmlFile;
    ArchiveFile? gpxFile;
    for (final f in archive) {
      final n = f.name.toLowerCase();
      if (n.endsWith('.kml')) {
        if (n.endsWith('doc.kml') || kmlFile == null) kmlFile = f;
        if (n.endsWith('doc.kml')) break;
      }
      if (n.endsWith('.gpx') && gpxFile == null) {
        gpxFile = f;
      }
    }
    if (kmlFile == null) {
      // Some archives contain GPX directly; support those too.
      if (gpxFile == null) return [];
      final gpxBytes = gpxFile.content as List<int>;
      var pts = _parseGpxBytes(gpxBytes);
      if (structuredRules.isNotEmpty) {
        pts = pts.where((p) => !_gpxPointIgnoredByRules(p, structuredRules)).toList();
      }
      pts = _applyTrackPointTimeRules(pts, structuredRules);
      final normalized = normalizeTimes(
        pts,
        baseUtc: baseUtc,
        missingStep: const Duration(minutes: 1),
      );
      _debugLogGpxParsedPoints(normalized);
      return normalized;
    }
    final xml = utf8.decode(kmlFile.content as List<int>, allowMalformed: true);
    final inspect = KmzKmlInspector.inspectXml(xml);
    final styleMap = inspect.styleIdToAbgr;

    List<KmzTrackPoint> pts;
    final useStructured = structuredRules.isNotEmpty;
    final useLegacy = !useStructured && (marker.isNotEmpty || contains.isNotEmpty);
    if (!useStructured && !useLegacy) {
      pts = KmzKmlParser.parseKmlString(xml);
    } else {
      final parts = xml.split(RegExp(r'(?=<Placemark)', caseSensitive: false));
      final buf = StringBuffer();
      for (final part in parts) {
        final drop = useStructured
            ? _placemarkIgnoredByRules(part, structuredRules, styleMap)
            : _placemarkIgnored(part, marker, contains);
        if (!drop) buf.write(part);
      }
      pts = KmzKmlParser.parseKmlString(buf.toString());
      // Some KMZ files keep track data outside Placemark blocks; keep import alive.
      if (pts.isEmpty && useStructured) {
        pts = KmzKmlParser.parseKmlString(xml);
      }
    }
    pts = _applyTrackPointTimeRules(pts, structuredRules);
    final normalized = normalizeTimes(pts, baseUtc: baseUtc);
    _debugLogKmzFileDataSummary(
      zipEntryNames: zipNames,
      kmlEntryName: kmlFile.name,
      kmlXmlLength: xml.length,
      pointsAfterNormalize: normalized,
    );
    return normalized;
  }

  /// Lightweight summary only — printing full KML on every preview blocks the UI isolate
  /// and can freeze/kill the app when picking large KMZ files repeatedly.
  static void _debugLogKmzFileDataSummary({
    required List<String> zipEntryNames,
    required String kmlEntryName,
    required int kmlXmlLength,
    required List<KmzTrackPoint> pointsAfterNormalize,
  }) {
    if (!kDebugMode) return;
    const tag = 'KMZ FILE DATA:';
    debugPrint(
      '$tag zip_entries=${zipEntryNames.length} ${zipEntryNames.take(20).join('|')}${zipEntryNames.length > 20 ? '…' : ''}',
    );
    debugPrint('$tag using_kml=$kmlEntryName (xml_chars=$kmlXmlLength)');
    final sample = pointsAfterNormalize
        .take(12)
        .map((p) => '(${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)})@${p.when?.toUtc().toIso8601String()}')
        .join('; ');
    debugPrint('$tag normalized_points_count=${pointsAfterNormalize.length} sample=$sample');
  }

  static String _styleUrlFromPlacemarkPart(String part) {
    final m = RegExp(
      r'<styleUrl>\s*([^<]+?)\s*</styleUrl>',
      caseSensitive: false,
    ).firstMatch(part);
    return (m?.group(1) ?? '').trim();
  }

  static String _styleIdFromUrl(String styleUrl) {
    var s = styleUrl.trim();
    if (s.startsWith('#')) s = s.substring(1);
    return s;
  }

  static bool _textCondition(String haystack, String needle, KmzIgnoreCondition c) {
    final h = haystack.toLowerCase();
    final n = needle.toLowerCase().trim();
    if (n.isEmpty) return false;
    switch (c) {
      case KmzIgnoreCondition.textContains:
        return h.contains(n);
      case KmzIgnoreCondition.textEquals:
        return haystack.trim().toLowerCase() == needle.trim().toLowerCase();
      case KmzIgnoreCondition.textStartsWith:
        return h.startsWith(n);
      default:
        return false;
    }
  }

  static bool _placemarkIgnoredByRules(
    String part,
    List<KmzIgnoreRule> rules,
    Map<String, String> styleIdToAbgr,
  ) {
    if (!part.toLowerCase().contains('<placemark')) return false;
    final tagValues = KmzKmlInspector.extractPlacemarkTagValues(part, styleIdToAbgr);
    for (final r in rules) {
      final values = r.parsedValues();
      const textCondition = KmzIgnoreCondition.textEquals;
      if (r.tag == KmzIgnoreTagKey.styleUrl) {
        final s = _styleUrlFromPlacemarkPart(part);
        if (s.isNotEmpty &&
            values.any((v) => _textCondition(s, v, textCondition))) {
          return true;
        }
      } else if (r.tag == KmzIgnoreTagKey.lineOrIconColor) {
        final sid = _styleIdFromUrl(_styleUrlFromPlacemarkPart(part));
        final abgr = styleIdToAbgr[sid] ?? '';
        if (abgr.isNotEmpty && values.isNotEmpty) {
          if (values.any((v) => _textCondition(abgr, v, textCondition))) return true;
        }
      } else if (r.tag == KmzIgnoreTagKey.dynamicTag) {
        final key = r.tagKey?.trim() ?? '';
        if (key.isEmpty) continue;
        final candidates = tagValues[key] ?? const <String>[];
        if (candidates.isEmpty || values.isEmpty) continue;
        for (final c in candidates) {
          if (values.any((v) => _textCondition(c, v, textCondition))) return true;
        }
      }
    }
    return false;
  }

  static List<KmzTrackPoint> _applyTrackPointTimeRules(
    List<KmzTrackPoint> pts,
    List<KmzIgnoreRule> rules,
  ) {
    final dr = rules.where((r) => r.tag == KmzIgnoreTagKey.trackPointTime).toList();
    if (dr.isEmpty) return pts;
    return pts.where((p) {
      final w = p.when;
      if (w == null) return true;
      final wu = w.toUtc();
      for (final r in dr) {
        for (final v in r.parsedValues()) {
          DateTime? tu;
          try {
            tu = DateTime.parse(v).toUtc();
          } catch (_) {
            continue;
          }
          if (_dateRuleRemoves(wu, tu, r.condition)) return false;
        }
      }
      return true;
    }).toList();
  }

  static bool _dateRuleRemoves(
    DateTime wUtc,
    DateTime tUtc,
    KmzIgnoreCondition c,
  ) {
    switch (c) {
      case KmzIgnoreCondition.dateIgnoreAfter:
        return wUtc.isAfter(tUtc);
      case KmzIgnoreCondition.dateIgnoreBefore:
        return wUtc.isBefore(tUtc);
      case KmzIgnoreCondition.dateIgnoreOnOrAfter:
        return !wUtc.isBefore(tUtc);
      case KmzIgnoreCondition.dateIgnoreOnOrBefore:
        return !wUtc.isAfter(tUtc);
      default:
        return false;
    }
  }

  static bool _placemarkIgnored(String part, String marker, String contains) {
    if (!part.toLowerCase().contains('<placemark')) return false;
    final m = RegExp(
      r'<styleUrl>\s*([^<]+)\s*</styleUrl>',
      caseSensitive: false,
    ).firstMatch(part);
    final style = (m?.group(1) ?? '').trim();
    if (style.isEmpty) return false;
    var hit = false;
    if (contains.isNotEmpty && style.contains(contains)) hit = true;
    if (marker.isNotEmpty && style.contains(marker)) hit = true;
    return hit;
  }

  static bool _gpxPointIgnoredByRules(KmzTrackPoint point, List<KmzIgnoreRule> rules) {
    for (final r in rules) {
      if (r.tag != KmzIgnoreTagKey.dynamicTag) continue;
      final key = r.tagKey?.trim() ?? '';
      if (key.isEmpty) continue;
      final candidates = point.tags[key] ?? const <String>[];
      final values = r.parsedValues();
      if (candidates.isEmpty || values.isEmpty) continue;
      for (final c in candidates) {
        if (values.any((v) => _textCondition(c, v, KmzIgnoreCondition.textEquals))) {
          return true;
        }
      }
    }
    return false;
  }

  static void _debugLogGpxFileData(String xml) {
    if (!kDebugMode) return;
    const tag = 'GPX FILE DATA:';
    debugPrint('$tag BEGIN_XML');
    debugPrint(xml);
    debugPrint('$tag END_XML');
  }

  static void _debugLogGpxParsedPoints(List<KmzTrackPoint> pts) {
    if (!kDebugMode) return;
    const tag = 'GPX FILE DATA:';
    debugPrint('$tag parsed_points_count=${pts.length}');
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      debugPrint(
        '$tag point[$i] lat=${p.latitude} lng=${p.longitude} when=${p.when?.toUtc().toIso8601String()} tags=${p.tags}',
      );
    }
  }

  /// Fills missing [KmzTrackPoint.when] for clustering; preserves [hasSourceTimestamp]
  /// so date filtering still uses only source timestamps (not synthesized times).
  static List<KmzTrackPoint> normalizeTimes(
    List<KmzTrackPoint> raw, {
    DateTime? baseUtc,
    Duration missingStep = const Duration(milliseconds: 1),
  }) {
    if (raw.isEmpty) return [];
    final nonNullUtc = <DateTime>[];
    for (final p in raw) {
      if (p.when != null) nonNullUtc.add(p.when!.toUtc());
    }
    final anchorUtc = nonNullUtc.isEmpty
        ? (baseUtc ?? DateTime.now().toUtc())
        : nonNullUtc.reduce((a, b) => a.isAfter(b) ? a : b);
    final withIndex = List.generate(raw.length, (i) => (i, raw[i]));
    withIndex.sort((a, b) {
      final ta = a.$2.when;
      final tb = b.$2.when;
      if (ta != null && tb != null) return ta.compareTo(tb);
      if (ta != null) return -1;
      if (tb != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    var seq = 0;
    return withIndex.map((e) {
      final p = e.$2;
      final t = p.when?.toUtc() ?? anchorUtc.add(missingStep * (++seq));
      return KmzTrackPoint(
        latitude: p.latitude,
        longitude: p.longitude,
        when: t,
        tags: p.tags,
        hasSourceTimestamp: p.hasSourceTimestamp,
      );
    }).toList();
  }

  static KmzImportStats buildStats({
    required List<KmzTrackPoint> points,
    required Duration minTimeApart,
    required double minMetersApart,
    required Set<String> existingFingerprints,
    required List<Map<String, dynamic>> existingCoordinateRows,
  }) {
    if (points.isEmpty) {
      return KmzImportStats(
        rawEntries: 0,
        ignoredEntries: 0,
        duplicateEntries: 0,
        totalAfterFilter: 0,
        newMemories: 0,
        candidates: [],
      );
    }

    final timed = points;
    final rawCount = timed.length;

    final clusters = _clusterPoints(timed, minTimeApart, minMetersApart);
    final clusterReps = <KmzTrackPoint>[];
    for (final c in clusters) {
      clusterReps.add(c.first);
    }

    final candidates = <KmzMemoryCandidate>[];
    var dup = 0;
    for (final p in clusterReps) {
      final w = p.when!.toUtc();
      final fp = fingerprintFor(w, p.latitude, p.longitude);
      if (existingFingerprints.contains(fp)) {
        dup++;
        continue;
      }
      if (_matchesExistingCoordinateRow(existingCoordinateRows, w, p.latitude, p.longitude, fp)) {
        dup++;
        continue;
      }
      candidates.add(
        KmzMemoryCandidate(
          latitude: p.latitude,
          longitude: p.longitude,
          when: w,
          fingerprint: fp,
        ),
      );
    }

    final totalAfter = candidates.length + dup;
    return KmzImportStats(
      rawEntries: rawCount,
      ignoredEntries: 0,
      duplicateEntries: dup,
      totalAfterFilter: totalAfter,
      newMemories: candidates.length,
      candidates: candidates,
    );
  }

  static bool _matchesExistingCoordinateRow(
    List<Map<String, dynamic>> rows,
    DateTime when,
    double lat,
    double lng,
    String fingerprint,
  ) {
    final d = '${when.year.toString().padLeft(4, '0')}-'
        '${when.month.toString().padLeft(2, '0')}-'
        '${when.day.toString().padLeft(2, '0')}';
    for (final r in rows) {
      final fp = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
      if (fp != null && fp.isNotEmpty && fp == fingerprint) return true;
      final latE = (r['location_latitude'] as num?)?.toDouble();
      final lngE = (r['location_longitude'] as num?)?.toDouble();
      if (latE == null || lngE == null) continue;
      if ((r['date'] as String?) != d) continue;
      if (fp == null || fp.isEmpty) {
        if ((lat - latE).abs() < 1e-5 && (lng - lngE).abs() < 1e-5) return true;
      }
    }
    return false;
  }

  /// Public entry for non-KMZ flows (e.g. gallery GPS) that reuse the same
  /// area grouping + time/distance clustering rules.
  static List<List<KmzTrackPoint>> clusterTrackPoints(
    List<KmzTrackPoint> points,
    Duration minTimeApart,
    double minMetersApart,
  ) {
    return _clusterPoints(points, minTimeApart, minMetersApart);
  }

  /// Cluster: walk points in chronological order; start a new cluster when the
  /// gap to the previous kept point is at least [minDt] or at least [minM].
  static List<List<KmzTrackPoint>> _clusterPoints(
    List<KmzTrackPoint> points,
    Duration minDt,
    double minM,
  ) {
    if (points.isEmpty) return [];
    final byTime = List<KmzTrackPoint>.from(points)
      ..sort((a, b) => a.when!.toUtc().compareTo(b.when!.toUtc()));

    final out = <List<KmzTrackPoint>>[];
    List<KmzTrackPoint>? cur;
    KmzTrackPoint? lastKept;

    for (final p in byTime) {
      final t = p.when!.toUtc();
      if (cur == null || lastKept == null) {
        cur = [p];
        lastKept = p;
        continue;
      }
      final lt = lastKept.when!.toUtc();
      final dt = t.difference(lt);
      final m = _distance.as(
        LengthUnit.Meter,
        LatLng(lastKept.latitude, lastKept.longitude),
        LatLng(p.latitude, p.longitude),
      );
      if (dt >= minDt || m >= minM) {
        out.add(cur);
        cur = [p];
        lastKept = p;
      } else {
        cur.add(p);
        // Evaluate thresholds from the latest accepted point in the chain.
        lastKept = p;
      }
    }
    if (cur != null) out.add(cur);
    return out;
  }
}
