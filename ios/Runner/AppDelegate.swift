import Flutter
import UIKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let locationSearchChannel = FlutterMethodChannel(name: "com.spacetime.location_search",
                                                   binaryMessenger: controller.binaryMessenger)

    locationSearchChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

      switch call.method {
      case "isNativeSearchAvailable":
        result(true) // iOS always has CoreLocation available

      case "searchLocations":
        guard let args = call.arguments as? Dictionary<String, Any>,
              let query = args["query"] as? String,
              let limit = args["limit"] as? Int else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
          return
        }

        self.searchLocations(query: query, limit: limit, result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func searchLocations(query: String, limit: Int, result: @escaping FlutterResult) {
    let geocoder = CLGeocoder()

    geocoder.geocodeAddressString(query) { (placemarks, error) in
      if let error = error {
        result(FlutterError(code: "SEARCH_ERROR",
                          message: "Failed to search locations: \(error.localizedDescription)",
                          details: nil))
        return
      }

      guard let placemarks = placemarks else {
        result([])
        return
      }

      let locations = placemarks.prefix(limit).compactMap { placemark -> [String: Any]? in
        guard let location = placemark.location else { return nil }

        return [
          "name": placemark.name ?? placemark.locality ?? query,
          "displayName": self.formatDisplayName(placemark: placemark),
          "shortDisplayName": self.formatShortDisplayName(placemark: placemark),
          "latitude": location.coordinate.latitude,
          "longitude": location.coordinate.longitude,
          "country": placemark.country ?? "",
          "state": placemark.administrativeArea ?? placemark.subAdministrativeArea,
          "city": placemark.locality ?? placemark.subLocality ?? "",
          "type": self.determineLocationType(placemark: placemark),
          "population": NSNull()
        ]
      }

      result(locations)
    }
  }

  private func formatDisplayName(placemark: CLPlacemark) -> String {
    var parts: [String] = []

    if let name = placemark.name, name != placemark.locality {
      parts.append(name)
    }
    if let locality = placemark.locality {
      parts.append(locality)
    }
    if let administrativeArea = placemark.administrativeArea {
      parts.append(administrativeArea)
    }
    if let country = placemark.country {
      parts.append(country)
    }

    return parts.joined(separator: ", ")
  }

  private func formatShortDisplayName(placemark: CLPlacemark) -> String {
    var parts: [String] = []

    if let locality = placemark.locality {
      parts.append(locality)
    }
    if let country = placemark.country {
      parts.append(country)
    }

    return parts.joined(separator: ", ")
  }

  private func determineLocationType(placemark: CLPlacemark) -> String {
    if placemark.name != nil && placemark.name != placemark.locality {
      return "landmark"
    } else if placemark.locality != nil {
      return "city"
    } else if placemark.subAdministrativeArea != nil {
      return "town"
    } else if placemark.administrativeArea != nil {
      return "state"
    } else if placemark.country != nil {
      return "country"
    } else {
      return "city"
    }
  }
}
