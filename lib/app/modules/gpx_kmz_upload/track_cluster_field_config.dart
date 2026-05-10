import 'package:flutter/material.dart';

/// Single place to adjust **max time apart** / **max distance apart** on every upload screen.
///
/// | What | Where |
/// |------|--------|
/// | Choice list keys | [maxTimeApartOptionKeys], [maxMeterApartOptionKeys] |
/// | Label copy | `assets/l10n/*.json` → [l10nKeyMaxTimeApart], [l10nKeyMaxMeterApart] |
/// | Field padding / row spacing | [dropdownContentPadding], [pairGap], [pairRowPadding], [pairedFieldMarginStart], [pairedFieldMarginEnd] |
/// | Default dropdown selection | [defaultClusterOptionIndex] (same index for both lists) |
/// | Time → duration | `kmz_import_pipeline.dart` → [KmzImportPipeline.durationForTimeKey] |
/// | Distance → meters | `kmz_import_pipeline.dart` → [KmzImportPipeline.metersForDistanceKey] |
abstract final class TrackClusterFieldConfig {
  TrackClusterFieldConfig._();

  /// Initial selection for both dropdowns (`0` = first option).
  static const int defaultClusterOptionIndex = 2;

  static const String l10nKeyMaxTimeApart = 'gpx_label_max_time_apart';
  static const String l10nKeyMaxMeterApart = 'gpx_label_max_meter_apart';

  static const EdgeInsets dropdownContentPadding =
      EdgeInsets.fromLTRB(12, 1, 12, 1);

  /// Space between the two fields inside [pairRowPadding] ([SizedBox] width).
  static const double pairGap = 2;

  static const EdgeInsets pairRowPadding =
      EdgeInsets.symmetric(horizontal: 10);

  /// Margins for the **left** field in a side‑by‑side pair (time/distance, dates).
  static const EdgeInsets pairedFieldMarginStart =
      EdgeInsets.fromLTRB(0, 2, 2, 2);

  /// Margins for the **right** field in a side‑by‑side pair.
  static const EdgeInsets pairedFieldMarginEnd =
      EdgeInsets.fromLTRB(2, 2, 0, 2);

  static const List<String> maxTimeApartOptionKeys = [
    'gpx_dd_time_1m',
    'gpx_dd_time_2m',
    'gpx_dd_time_5m',
    'gpx_dd_time_10m',
    'gpx_dd_time_15m',
    'gpx_dd_time_30m',
    'gpx_dd_time_1h',
  ];

  static const List<String> maxMeterApartOptionKeys = [
    'gpx_dd_dist_10m',
    'gpx_dd_dist_25m',
    'gpx_dd_dist_50m',
    'gpx_dd_dist_100m',
    'gpx_dd_dist_250m',
    'gpx_dd_dist_500m',
    'gpx_dd_dist_1km',
  ];
}
