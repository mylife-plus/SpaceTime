import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Single parsed coordinate with optional time (from KMZ / KML).
class KmzTrackPoint {
  KmzTrackPoint({
    required this.latitude,
    required this.longitude,
    this.when,
    this.tags = const {},
    this.hasSourceTimestamp = false,
  });

  final double latitude;
  final double longitude;
  final DateTime? when;
  final Map<String, List<String>> tags;
  /// True when [when] came from a timestamp field on the point (not estimated).
  final bool hasSourceTimestamp;
}

/// Extracts [KmzTrackPoint] from a `.kmz` (zip with `doc.kml` or any `.kml`).
class KmzKmlParser {
  /// Reads file from [path] and returns ordered points (best-effort).
  static Future<List<KmzTrackPoint>> parseKmzFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return [];
    final bytes = await file.readAsBytes();
    return parseKmzBytes(bytes);
  }

  static List<KmzTrackPoint> parseKmzBytes(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? kmlFile;
    for (final f in archive) {
      final n = f.name.toLowerCase();
      if (n.endsWith('.kml')) {
        if (n.endsWith('doc.kml') || kmlFile == null) {
          kmlFile = f;
        }
        if (n.endsWith('doc.kml')) break;
      }
    }
    if (kmlFile == null) return [];
    final xml = utf8.decode(kmlFile.content as List<int>, allowMalformed: true);
    return parseKmlString(xml);
  }

  /// Parses plain GPX XML track points (`<trkpt lat="" lon="">`).
  static List<KmzTrackPoint> parseGpxString(String gpx) {
    final out = <KmzTrackPoint>[];
    for (final tagName in const ['trkpt', 'rtept', 'wpt']) {
      final fullRe = RegExp(
        '<$tagName\\b([^>]*)>([\\s\\S]*?)</$tagName>',
        caseSensitive: false,
      );
      for (final m in fullRe.allMatches(gpx)) {
        final parsed = _parseGpxPointMatch(m.group(1) ?? '', m.group(2) ?? '');
        if (parsed != null) out.add(parsed);
      }
      final selfRe = RegExp(
        '<$tagName\\b([^>]*)/>',
        caseSensitive: false,
      );
      for (final m in selfRe.allMatches(gpx)) {
        final parsed = _parseGpxPointMatch(m.group(1) ?? '', '');
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }

  static KmzTrackPoint? _parseGpxPointMatch(String attrs, String body) {
    final latS = RegExp(
      r'''lat\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(attrs)?.group(1);
    final lonS = RegExp(
      r'''lon\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(attrs)?.group(1);
    final lat = latS == null ? null : double.tryParse(latS);
    final lon = lonS == null ? null : double.tryParse(lonS);
    if (lat == null || lon == null) return null;

    final tags = <String, List<String>>{};
    void addTag(String key, String? value) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return;
      tags.putIfAbsent(key, () => <String>[]).add(v);
    }

    addTag('ele', RegExp(r'<(?:\w+:)?ele>\s*([^<]+?)\s*</(?:\w+:)?ele>', caseSensitive: false).firstMatch(body)?.group(1));
    addTag('name', RegExp(r'<(?:\w+:)?name>\s*([\s\S]*?)\s*</(?:\w+:)?name>', caseSensitive: false).firstMatch(body)?.group(1));
    addTag('desc', RegExp(r'<(?:\w+:)?desc>\s*([\s\S]*?)\s*</(?:\w+:)?desc>', caseSensitive: false).firstMatch(body)?.group(1));
    addTag('sym', RegExp(r'<(?:\w+:)?sym>\s*([^<]+?)\s*</(?:\w+:)?sym>', caseSensitive: false).firstMatch(body)?.group(1));
    addTag('type', RegExp(r'<(?:\w+:)?type>\s*([^<]+?)\s*</(?:\w+:)?type>', caseSensitive: false).firstMatch(body)?.group(1));
    for (final ext in RegExp(
      r'<((?:\w+:)?[A-Za-z_][\w:.-]*)>\s*([^<]+?)\s*</\1>',
      caseSensitive: false,
    ).allMatches(body)) {
      final key = (ext.group(1) ?? '').trim();
      if (key.isEmpty) continue;
      addTag(key, ext.group(2));
    }

    final when = resolveTimestampFromFields(
      attrs: attrs,
      body: body,
      tags: tags,
    );
    return KmzTrackPoint(
      latitude: lat,
      longitude: lon,
      when: when,
      tags: tags,
      hasSourceTimestamp: when != null,
    );
  }

  /// GPX/KMZ point timestamp resolution priority:
  /// 1. `when` → `timestamp` → `created` → `datetime` → `date`
  /// 2. Remaining tags (`time`, `begin`, `end`, …), attributes, then [tags].
  ///
  /// Date filter uses [KmzTrackPoint.hasSourceTimestamp] + source [when] only.
  /// Clustering uses [KmzImportPipeline.normalizeTimes] output. Memory [createdAt]
  /// is the cluster representative's normalized [when] (UTC).
  static const List<String> _timestampTagPriority = [
    'when',
    'timestamp',
    'created',
    'creationtime',
    'datetime',
    'date',
  ];

  static const List<String> _timestampTagRemainingPriority = [
    'time',
    'begin',
    'end',
  ];

  static DateTime? resolveTimestampFromFields({
    String attrs = '',
    String body = '',
    Map<String, List<String>> tags = const {},
  }) {
    final byLocalName = _collectXmlElementValuesByLocalName(body);

    for (final name in _timestampTagPriority) {
      final t = _firstParseableTimestamp(byLocalName[name]);
      if (t != null) return t;
    }

    for (final name in _timestampTagRemainingPriority) {
      final t = _firstParseableTimestamp(byLocalName[name]);
      if (t != null) return t;
    }

    for (final entry in byLocalName.entries) {
      final key = entry.key;
      if (_timestampTagPriority.contains(key) ||
          _timestampTagRemainingPriority.contains(key)) {
        continue;
      }
      final t = _firstParseableTimestamp(entry.value);
      if (t != null) return t;
    }

    for (final m in RegExp(
      r'''(\w+)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(attrs)) {
      final t = parseKmlWhenString(m.group(2)!);
      if (t != null) return t;
    }

    for (final values in tags.values) {
      final t = _firstParseableTimestamp(values);
      if (t != null) return t;
    }
    return null;
  }

  static Map<String, List<String>> _collectXmlElementValuesByLocalName(
    String body,
  ) {
    final out = <String, List<String>>{};
    for (final m in RegExp(
      r'<((?:\w+:)?[A-Za-z_][\w:.-]*)>\s*([^<]+?)\s*</\1>',
      caseSensitive: false,
    ).allMatches(body)) {
      final fullName = (m.group(1) ?? '').trim();
      if (fullName.isEmpty) continue;
      final local = fullName.contains(':')
          ? fullName.split(':').last.toLowerCase()
          : fullName.toLowerCase();
      out.putIfAbsent(local, () => <String>[]).add(m.group(2)!.trim());
    }
    return out;
  }

  static DateTime? _firstParseableTimestamp(List<String>? values) {
    if (values == null) return null;
    for (final raw in values) {
      final t = parseKmlWhenString(raw);
      if (t != null) return t;
    }
    return null;
  }

  /// KML/GPX-style instant strings → UTC [DateTime], or null if unknown.
  static DateTime? parseKmlWhenString(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '').trim();
    if (s.isEmpty) return null;

    // "yyyy-MM-dd HH:mm:ss" or space between date and time
    if (!s.contains('T') &&
        RegExp(r'^\d{4}-\d{2}-\d{2}\s+\d').hasMatch(s)) {
      s = s.replaceFirst(RegExp(r'\s+'), 'T');
    }
    // "yyyy/MM/dd ..."
    if (RegExp(r'^\d{4}/\d{2}/\d{2}').hasMatch(s)) {
      s = s.replaceAll('/', '-');
      if (!s.contains('T') && RegExp(r'^\d{4}-\d{2}-\d{2}\s+\d').hasMatch(s)) {
        s = s.replaceFirst(RegExp(r'\s+'), 'T');
      }
    }

    var dt = DateTime.tryParse(s);
    if (dt != null) {
      return dt.isUtc ? dt : dt.toUtc();
    }

    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      dt = DateTime.tryParse('${s}T00:00:00Z');
      if (dt != null) return dt.toUtc();
    }
    return null;
  }

  /// Order: [gx:Track] (Google Earth) → global `<when>` + `<gx:coord>` pairs →
  /// placemarks with [TimeStamp] / [TimeSpan] + LineString or Point → raw coordinates.
  static List<KmzTrackPoint> parseKmlString(String kml) {
    final gx = _parseGxTracks(kml);
    if (gx.isNotEmpty) return gx;

    final pairs = _parseWhenCoordPairs(kml);
    if (pairs.isNotEmpty) return pairs;

    final placemark = _parsePlacemarksWithCoordinatesAndTime(kml);
    if (placemark.isNotEmpty) return placemark;

    return _parseCoordinatesBlocks(kml);
  }

  static List<KmzTrackPoint> _parseGxTracks(String kml) {
    final trackRe = RegExp(
      r'<gx:Track\b[^>]*>([\s\S]*?)</gx:Track>',
      caseSensitive: false,
    );
    final out = <KmzTrackPoint>[];
    for (final m in trackRe.allMatches(kml)) {
      out.addAll(_parseWhenCoordPairs(m.group(1)!));
    }
    return out;
  }

  static List<KmzTrackPoint> _parseWhenCoordPairs(String kml) {
    final whenRe = RegExp(r'<when>\s*([^<]+?)\s*</when>', caseSensitive: false);
    final coordRe = RegExp(
      r'<(?:gx:)?coord>\s*([^<]+?)\s*</(?:gx:)?coord>',
      caseSensitive: false,
    );
    final whens = whenRe.allMatches(kml).map((m) => m.group(1)!.trim()).toList();
    final coords = coordRe.allMatches(kml).map((m) => m.group(1)!.trim()).toList();
    if (whens.isEmpty || coords.isEmpty) return [];

    final n = whens.length < coords.length ? whens.length : coords.length;
    final out = <KmzTrackPoint>[];
    for (var i = 0; i < n; i++) {
      final when = parseKmlWhenString(whens[i]);
      final p = _parseLonLatTriple(coords[i]);
      if (p != null) {
        out.add(KmzTrackPoint(
          latitude: p.$2,
          longitude: p.$1,
          when: when,
          hasSourceTimestamp: when != null,
        ));
      }
    }
    return out;
  }

  static List<KmzTrackPoint> _parsePlacemarksWithCoordinatesAndTime(String kml) {
    final pmRe = RegExp(
      r'<Placemark\b[^>]*>([\s\S]*?)</Placemark>',
      caseSensitive: false,
    );
    final out = <KmzTrackPoint>[];
    for (final m in pmRe.allMatches(kml)) {
      final body = m.group(1)!;
      if (RegExp(r'<gx:Track\b', caseSensitive: false).hasMatch(body)) {
        continue;
      }

      final span = _timeSpanBeginEnd(body);
      final stamp = _timeStampWhen(body);
      final begin = span.$1 ?? stamp;
      final end = span.$2;

      final coordStr = _firstCoordinatesIn(body);
      if (coordStr == null) continue;
      if (begin == null) continue;

      final triplets = coordStr
          .split(RegExp(r'\s+'))
          .where((t) => t.trim().isNotEmpty)
          .toList();
      if (triplets.isEmpty) continue;

      if (triplets.length == 1) {
        final p = _parseLonLatTriple(triplets.first);
        if (p != null) {
          out.add(KmzTrackPoint(
            latitude: p.$2,
            longitude: p.$1,
            when: begin,
            hasSourceTimestamp: true,
          ));
        }
        continue;
      }

      if (end != null && !end.isBefore(begin)) {
        final ms0 = begin.toUtc().millisecondsSinceEpoch;
        final ms1 = end.toUtc().millisecondsSinceEpoch;
        for (var i = 0; i < triplets.length; i++) {
          final frac = triplets.length > 1 ? i / (triplets.length - 1) : 0.0;
          final ms = (ms0 + (ms1 - ms0) * frac).round();
          final wi = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
          final p = _parseLonLatTriple(triplets[i]);
          if (p != null) {
            out.add(KmzTrackPoint(
              latitude: p.$2,
              longitude: p.$1,
              when: wi,
              hasSourceTimestamp: true,
            ));
          }
        }
      } else {
        for (var i = 0; i < triplets.length; i++) {
          final wi = begin.add(Duration(seconds: i));
          final p = _parseLonLatTriple(triplets[i]);
          if (p != null) {
            out.add(KmzTrackPoint(
              latitude: p.$2,
              longitude: p.$1,
              when: wi,
              hasSourceTimestamp: true,
            ));
          }
        }
      }
    }
    return out;
  }

  static DateTime? _timeStampWhen(String body) {
    final m = RegExp(
      r'<TimeStamp[^>]*>[\s\S]*?<when>\s*([^<]+?)\s*</when>',
      caseSensitive: false,
    ).firstMatch(body);
    return m != null ? parseKmlWhenString(m.group(1)!) : null;
  }

  static (DateTime?, DateTime?) _timeSpanBeginEnd(String body) {
    final b = RegExp(
      r'<begin>\s*([^<]+?)\s*</begin>',
      caseSensitive: false,
    ).firstMatch(body);
    final e = RegExp(
      r'<end>\s*([^<]+?)\s*</end>',
      caseSensitive: false,
    ).firstMatch(body);
    return (
      b != null ? parseKmlWhenString(b.group(1)!) : null,
      e != null ? parseKmlWhenString(e.group(1)!) : null,
    );
  }

  static String? _firstCoordinatesIn(String placemarkBody) {
    final line = RegExp(
      r'<(?:gx:)?LineString[^>]*>[\s\S]*?<coordinates>\s*([^<]+)\s*</coordinates>',
      caseSensitive: false,
    ).firstMatch(placemarkBody);
    if (line != null) return line.group(1)!.trim();
    final point = RegExp(
      r'<Point[^>]*>[\s\S]*?<coordinates>\s*([^<]+)\s*</coordinates>',
      caseSensitive: false,
    ).firstMatch(placemarkBody);
    if (point != null) return point.group(1)!.trim();
    // Fallback for KMZ variants that keep coordinates directly under Placemark.
    final any = RegExp(
      r'<coordinates>\s*([^<]+)\s*</coordinates>',
      caseSensitive: false,
    ).firstMatch(placemarkBody);
    return any?.group(1)?.trim();
  }

  static (double, double)? _parseLonLatTriple(String triplet) {
    final parts = triplet.split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;
    final nums = parts.first.split(',');
    if (nums.length < 2) return null;
    final lon = double.tryParse(nums[0].trim());
    final lat = double.tryParse(nums[1].trim());
    if (lat == null || lon == null) return null;
    return (lon, lat);
  }

  static List<KmzTrackPoint> _parseCoordinatesBlocks(String kml) {
    final coordBlock = RegExp(
      r'<coordinates>\s*([^<]+)\s*</coordinates>',
      caseSensitive: false,
    );
    final out = <KmzTrackPoint>[];
    for (final m in coordBlock.allMatches(kml)) {
      final chunk = m.group(1)!.trim();
      for (final triplet in chunk.split(RegExp(r'\s+'))) {
        if (triplet.isEmpty) continue;
        final p = _parseLonLatTriple(triplet);
        if (p != null) {
          out.add(KmzTrackPoint(latitude: p.$2, longitude: p.$1, when: null));
        }
      }
    }
    return out;
  }
}
