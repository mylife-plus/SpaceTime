import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_inspector.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_parser.dart';
import 'package:spacetime/app/widgets/appbar.dart';

class KmzFileDetailsView extends StatelessWidget {
  const KmzFileDetailsView({super.key, required this.kmzPath});

  final String kmzPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'KMZ File Details',
        icon: const Icon(Icons.description_outlined, color: Colors.white, size: 22),
      ),
      body: FutureBuilder<_KmzDetailsData>(
        future: _KmzDetailsData.load(kmzPath),
        builder: (context, snap) {
          if (!snap.hasData) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: ${snap.error}'),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _box('File', [
                'Path: ${d.path}',
                'Name: ${d.name}',
                'Size: ${d.fileSizeBytes} bytes',
                'Zip entries: ${d.zipEntries.length}',
              ]),
              _box('ZIP Entries', d.zipEntries),
              _box('Styles', [
                'styleUrl count: ${d.inspect.styleUrls.length}',
                ...d.inspect.styleUrls.take(120),
              ]),
              _box('Colors (KML aabbggrr)', [
                'color count: ${d.inspect.styleColorsAbgr.length}',
                ...d.inspect.styleColorsAbgr.take(120),
              ]),
              _box('Time Info', [
                'min when: ${d.inspect.minWhen?.toLocal() ?? '-'}',
                'max when: ${d.inspect.maxWhen?.toLocal() ?? '-'}',
                'parsed <when> values: ${d.inspect.trackWhenValuesIso.length}',
                ...d.inspect.trackWhenValuesIso.take(120),
              ]),
              _box('Parsed Track Points', [
                'total points: ${d.points.length}',
                ...d.points
                    .take(200)
                    .map((e) => '${e.latitude}, ${e.longitude} @ ${e.when?.toLocal()}'),
              ]),
              _box('KML Content (raw)', [d.kmlXml]),
            ],
          );
        },
      ),
    );
  }

  Widget _box(String title, List<String> lines) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppFonts.bold(15, color: Colors.black87)),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(l, style: AppFonts.medium(13, color: Colors.black87)),
            ),
        ],
      ),
    );
  }
}

class _KmzDetailsData {
  _KmzDetailsData({
    required this.path,
    required this.name,
    required this.fileSizeBytes,
    required this.zipEntries,
    required this.kmlXml,
    required this.inspect,
    required this.points,
  });

  final String path;
  final String name;
  final int fileSizeBytes;
  final List<String> zipEntries;
  final String kmlXml;
  final KmzFileInspect inspect;
  final List<KmzTrackPoint> points;

  static Future<_KmzDetailsData> load(String kmzPath) async {
    final file = File(kmzPath);
    if (!await file.exists()) {
      throw Exception('File not found: $kmzPath');
    }
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final entries = archive.map((e) => e.name).toList();
    ArchiveFile? kmlFile;
    for (final f in archive) {
      final n = f.name.toLowerCase();
      if (n.endsWith('.kml')) {
        if (n.endsWith('doc.kml') || kmlFile == null) kmlFile = f;
        if (n.endsWith('doc.kml')) break;
      }
    }
    if (kmlFile == null) {
      throw Exception('No KML found inside KMZ');
    }
    final xml = utf8.decode(kmlFile.content as List<int>, allowMalformed: true);
    return _KmzDetailsData(
      path: kmzPath,
      name: p.basename(kmzPath),
      fileSizeBytes: await file.length(),
      zipEntries: entries,
      kmlXml: xml,
      inspect: KmzKmlInspector.inspectXml(xml),
      points: KmzKmlParser.parseKmlString(xml),
    );
  }
}
