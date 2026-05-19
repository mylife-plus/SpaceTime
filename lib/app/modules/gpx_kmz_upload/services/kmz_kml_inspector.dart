import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_parser.dart';

DateTime? _parseKmlWhenForInspect(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '').trim();
  if (s.isEmpty) return null;
  if (!s.contains('T') && RegExp(r'^\d{4}-\d{2}-\d{2}\s+\d').hasMatch(s)) {
    s = s.replaceFirst(RegExp(r'\s+'), 'T');
  }
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

/// Values discovered in the current KMZ/KML for building ignore-rule pickers.
class KmzFileInspect {
  KmzFileInspect({
    required this.styleUrls,
    required this.styleColorsAbgr,
    required this.styleIdToAbgr,
    required this.trackWhenValuesIso,
    required this.tagValues,
    this.minWhen,
    this.maxWhen,
  });

  final List<String> styleUrls;
  final List<String> styleColorsAbgr;
  final Map<String, String> styleIdToAbgr;
  /// Distinct UTC ISO-8601 values parsed from `<when>` in KML.
  final List<String> trackWhenValuesIso;
  /// Dynamic text tags and their distinct values discovered in Placemarks.
  final Map<String, List<String>> tagValues;
  final DateTime? minWhen;
  final DateTime? maxWhen;

  static KmzFileInspect empty() => KmzFileInspect(
        styleUrls: const [],
        styleColorsAbgr: const [],
        styleIdToAbgr: const {},
        trackWhenValuesIso: const [],
        tagValues: const {},
      );
}

class KmzKmlInspector {
  static Future<KmzFileInspect?> inspectFromPath(String kmzPath) async {
    final file = File(kmzPath);
    if (!await file.exists()) return null;
    final lower = kmzPath.toLowerCase();
    if (lower.endsWith('.gpx')) {
      final bytes = await file.readAsBytes();
      final xml = utf8.decode(bytes, allowMalformed: true);
      return inspectGpxXml(xml);
    }
    final bytes = await file.readAsBytes();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e, st) {
      debugPrint('[KmzKmlInspector] zip decode failed: $e\n$st');
      return null;
    }
    ArchiveFile? kmlFile;
    for (final f in archive) {
      final n = f.name.toLowerCase();
      if (n.endsWith('.kml')) {
        if (n.endsWith('doc.kml') || kmlFile == null) kmlFile = f;
        if (n.endsWith('doc.kml')) break;
      }
    }
    if (kmlFile == null) return null;
    final xml = utf8.decode(kmlFile.content as List<int>, allowMalformed: true);
    return inspectXml(xml);
  }

  static KmzFileInspect inspectGpxXml(String xml) {
    final whenValuesIso = <String>{};
    final dynamicTagValues = <String, Set<String>>{};
    DateTime? minW;
    DateTime? maxW;

    final points = KmzKmlParser.parseGpxString(xml);
    for (final p in points) {
      final dt = p.when;
      if (dt != null) {
        final u = dt.toUtc();
        whenValuesIso.add(u.toIso8601String());
        if (minW == null || u.isBefore(minW)) minW = u;
        if (maxW == null || u.isAfter(maxW)) maxW = u;
      }
      p.tags.forEach((k, values) {
        final key = k.trim();
        if (key.isEmpty || key.toLowerCase().endsWith('time')) return;
        final set = dynamicTagValues.putIfAbsent(key, () => <String>{});
        for (final value in values) {
          final v = value.trim();
          if (v.isNotEmpty) set.add(v);
        }
      });
    }

    final sortedTimes = whenValuesIso.toList()..sort();
    return KmzFileInspect(
      styleUrls: const [],
      styleColorsAbgr: const [],
      styleIdToAbgr: const {},
      trackWhenValuesIso: sortedTimes,
      tagValues: {
        for (final e in dynamicTagValues.entries) e.key: (e.value.toList()..sort()),
      },
      minWhen: minW,
      maxWhen: maxW,
    );
  }

  static KmzFileInspect inspectXml(String xml) {
    final styleUrls = <String>{};
    for (final m in RegExp(
      r'<styleUrl>\s*([^<]+?)\s*</styleUrl>',
      caseSensitive: false,
    ).allMatches(xml)) {
      final s = m.group(1)!.trim();
      if (s.isNotEmpty) styleUrls.add(s);
    }

    final styleIdToAbgr = <String, String>{};
    for (final m in RegExp(
      r'<Style\b([^>]*)>([\s\S]*?)</Style>',
      caseSensitive: false,
    ).allMatches(xml)) {
      final attrs = m.group(1)!;
      final idM = RegExp(r'''id\s*=\s*["']([^"']+)["']''').firstMatch(attrs);
      if (idM == null) continue;
      final id = idM.group(1)!.trim();
      final body = m.group(2)!;
      for (final cm in RegExp(
        r'<(?:Icon|Line|Label)Style\b[\s\S]*?<color>\s*([0-9a-fA-F]{1,8})\s*</color>',
        caseSensitive: false,
      ).allMatches(body)) {
        var hex = cm.group(1)!.trim().toLowerCase();
        if (hex.length == 6) hex = 'ff$hex';
        if (hex.length == 8) {
          styleIdToAbgr[id] = hex;
          break;
        }
      }
    }

    final colors = styleIdToAbgr.values.toSet().toList()..sort();
    final whenValuesIso = <String>{};
    final dynamicTagValues = <String, Set<String>>{};

    DateTime? minW;
    DateTime? maxW;
    for (final m in RegExp(
      r'<when>\s*([^<]+?)\s*</when>',
      caseSensitive: false,
    ).allMatches(xml)) {
      final dt = _parseKmlWhenForInspect(m.group(1)!);
      if (dt == null) continue;
      final u = dt.toUtc();
      whenValuesIso.add(u.toIso8601String());
      if (minW == null || u.isBefore(minW)) minW = u;
      if (maxW == null || u.isAfter(maxW)) maxW = u;
    }

    for (final pm in RegExp(
      r'<Placemark\b[^>]*>([\s\S]*?)</Placemark>',
      caseSensitive: false,
    ).allMatches(xml)) {
      final values = extractPlacemarkTagValues(pm.group(0)!, styleIdToAbgr);
      values.forEach((k, vals) {
        final set = dynamicTagValues.putIfAbsent(k, () => <String>{});
        set.addAll(vals.where((v) => v.trim().isNotEmpty));
      });
    }

    final sortedStyles = styleUrls.toList()..sort();
    final sortedTimes = whenValuesIso.toList()..sort();
    return KmzFileInspect(
      styleUrls: sortedStyles,
      styleColorsAbgr: colors,
      styleIdToAbgr: styleIdToAbgr,
      trackWhenValuesIso: sortedTimes,
      tagValues: {
        for (final e in dynamicTagValues.entries)
          e.key: (e.value.toList()..sort()),
      },
      minWhen: minW,
      maxWhen: maxW,
    );
  }

  static Map<String, List<String>> extractPlacemarkTagValues(
    String placemarkXml,
    Map<String, String> styleIdToAbgr,
  ) {
    final out = <String, Set<String>>{};
    void add(String key, String value) {
      final v = value.trim();
      if (key.trim().isEmpty || v.isEmpty) return;
      out.putIfAbsent(key, () => <String>{}).add(v);
    }

    final styleUrl = RegExp(
      r'<styleUrl>\s*([^<]+?)\s*</styleUrl>',
      caseSensitive: false,
    ).firstMatch(placemarkXml)?.group(1)?.trim();
    if (styleUrl != null && styleUrl.isNotEmpty) {
      add('styleUrl', styleUrl);
      final styleId = styleUrl.startsWith('#') ? styleUrl.substring(1) : styleUrl;
      final abgr = styleIdToAbgr[styleId];
      if (abgr != null && abgr.isNotEmpty) {
        add('lineOrIconColor', abgr);
      }
    }

    for (final m in RegExp(
      r'<(name|description)>\s*([\s\S]*?)\s*</\1>',
      caseSensitive: false,
    ).allMatches(placemarkXml)) {
      add(m.group(1)!.trim(), m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim());
    }

    for (final m in RegExp(
      r'''<Data\b[^>]*name\s*=\s*["']([^"']+)["'][^>]*>\s*[\s\S]*?<value>\s*([\s\S]*?)\s*</value>\s*</Data>''',
      caseSensitive: false,
    ).allMatches(placemarkXml)) {
      add(m.group(1)!.trim(), m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim());
    }

    for (final m in RegExp(
      r'''<SimpleData\b[^>]*name\s*=\s*["']([^"']+)["'][^>]*>\s*([\s\S]*?)\s*</SimpleData>''',
      caseSensitive: false,
    ).allMatches(placemarkXml)) {
      add(m.group(1)!.trim(), m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim());
    }

    return {
      for (final e in out.entries) e.key: e.value.toList(),
    };
  }
}
