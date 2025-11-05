import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/data/models/location_data.dart';

class LocationPickerRepository {
  static const String _selectedLocationKey = 'selected_location_data';
  static const String _radiusKey = 'selected_radius';
  static const String _recentLocationsKey = 'recent_locations';

  /// Save selected location data
  Future<void> saveSelectedLocation(LocationData locationData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationJson = jsonEncode(locationData.toJson());
      await prefs.setString(_selectedLocationKey, locationJson);
    } catch (e) {
      throw Exception('Failed to save location: $e');
    }
  }

  /// Get saved location data
  Future<LocationData?> getSavedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationJson = prefs.getString(_selectedLocationKey);
      if (locationJson != null) {
        final locationMap = jsonDecode(locationJson) as Map<String, dynamic>;
        return LocationData.fromJson(locationMap);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get saved location: $e');
    }
  }

  /// Save selected radius
  Future<void> saveRadius(double radius) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_radiusKey, radius);
    } catch (e) {
      throw Exception('Failed to save radius: $e');
    }
  }

  /// Get saved radius
  Future<double> getSavedRadius() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_radiusKey) ?? 10.0; // Default 10km
    } catch (e) {
      throw Exception('Failed to get saved radius: $e');
    }
  }

  /// Save recent location to history
  Future<void> saveRecentLocation(LocationData locationData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentJson = prefs.getString(_recentLocationsKey);
      
      List<Map<String, dynamic>> recentLocations = [];
      if (recentJson != null) {
        final decoded = jsonDecode(recentJson) as List<dynamic>;
        recentLocations = decoded.cast<Map<String, dynamic>>();
      }

      // Remove if already exists to avoid duplicates
      recentLocations.removeWhere((location) => 
        location['latitude'] == locationData.latitude &&
        location['longitude'] == locationData.longitude);

      // Add to beginning
      recentLocations.insert(0, locationData.toJson());

      // Keep only last 10 locations
      if (recentLocations.length > 10) {
        recentLocations = recentLocations.take(10).toList();
      }

      await prefs.setString(_recentLocationsKey, jsonEncode(recentLocations));
    } catch (e) {
      throw Exception('Failed to save recent location: $e');
    }
  }

  /// Get recent locations
  Future<List<LocationData>> getRecentLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentJson = prefs.getString(_recentLocationsKey);
      
      if (recentJson != null) {
        final decoded = jsonDecode(recentJson) as List<dynamic>;
        return decoded
            .cast<Map<String, dynamic>>()
            .map((json) => LocationData.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to get recent locations: $e');
    }
  }

  /// Check location permissions
  Future<bool> hasLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always || 
             permission == LocationPermission.whileInUse;
    } catch (e) {
      return false;
    }
  }

  /// Request location permissions
  Future<bool> requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      return permission == LocationPermission.always || 
             permission == LocationPermission.whileInUse;
    } catch (e) {
      return false;
    }
  }

  /// Get current position
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) {
        final granted = await requestLocationPermission();
        if (!granted) return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      throw Exception('Failed to get current position: $e');
    }
  }

  /// Clear all saved data
  Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_selectedLocationKey),
        prefs.remove(_radiusKey),
        prefs.remove(_recentLocationsKey),
      ]);
    } catch (e) {
      throw Exception('Failed to clear data: $e');
    }
  }
}
