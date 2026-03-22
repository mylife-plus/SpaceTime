/// Shared admin-area rules: [locationCity] stores `City/Town, State/Province`
/// (split on the **first** comma). Edit screen: city field = 1st part, state field = 2nd.
class MemoryLocationLineFormat {
  MemoryLocationLineFormat._();

  /// First comma splits city/town (left) from state/province (right).
  static ({String cityTown, String state}) parseAdminArea(String locationCity) {
    final s = locationCity.trim();
    if (s.isEmpty) {
      return (cityTown: '', state: '');
    }
    final i = s.indexOf(',');
    if (i == -1) {
      return (cityTown: s, state: '');
    }
    return (
      cityTown: s.substring(0, i).trim(),
      state: s.substring(i + 1).trim(),
    );
  }

  static String displayLine({
    required String flag,
    required String locationCity,
    String locationName = '',
    double? lat,
    double? lng,
  }) {
    final p = parseAdminArea(locationCity);
    String place;
    if (p.cityTown.isNotEmpty && p.state.isNotEmpty) {
      place = '${p.cityTown}, ${p.state}';
    } else if (p.cityTown.isNotEmpty) {
      place = p.cityTown;
    } else if (p.state.isNotEmpty) {
      place = p.state;
    } else {
      place = '';
    }

    final f = flag.trim();
    if (f.isNotEmpty && place.isNotEmpty) {
      return '$f $place';
    }
    if (f.isNotEmpty) {
      return f;
    }
    if (place.isNotEmpty) {
      return place;
    }
    final n = locationName.trim();
    if (n.isNotEmpty) {
      return n;
    }
    if (lat != null && lng != null) {
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    return '';
  }
}
