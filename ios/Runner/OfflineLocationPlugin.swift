import Flutter
import UIKit
import MapboxMaps
import MapboxSearch

public class OfflineLocationPlugin: NSObject, FlutterPlugin {
    private var offlineSearchEngine: OfflineSearchEngine?
    private var offlineManager: OfflineManager?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "offline_location_service", binaryMessenger: registrar.messenger())
        let instance = OfflineLocationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(result: result)
        case "searchLocations":
            searchLocations(call: call, result: result)
        case "reverseGeocode":
            reverseGeocode(call: call, result: result)
        case "isOfflineDataAvailable":
            isOfflineDataAvailable(call: call, result: result)
        case "downloadOfflineRegion":
            downloadOfflineRegion(call: call, result: result)
        case "getOfflineRegions":
            getOfflineRegions(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func initialize(result: @escaping FlutterResult) {
        do {
            // Initialize Mapbox Search SDK
            let offlineSearchEngineSettings = OfflineSearchEngineSettings()
            offlineSearchEngine = try OfflineSearchEngine(settings: offlineSearchEngineSettings)
            
            // Initialize offline manager
            offlineManager = OfflineManager.shared
            
            print("Offline location service initialized successfully")
            result(true)
        } catch {
            print("Error initializing offline location service: \(error)")
            result(false)
        }
    }
    
    private func searchLocations(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let query = args["query"] as? String else {
            result([])
            return
        }
        
        let latitude = args["latitude"] as? Double
        let longitude = args["longitude"] as? Double
        let radius = args["radius"] as? Double
        let limit = args["limit"] as? Int ?? 10
        
        guard let searchEngine = offlineSearchEngine else {
            result([])
            return
        }
        
        var searchOptions = SearchOptions()
        searchOptions.limit = limit
        
        if let lat = latitude, let lng = longitude {
            searchOptions.proximity = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        
        let searchTask = searchEngine.search(query: query, options: searchOptions) { [weak self] response in
            switch response {
            case .success(let searchResults):
                let locations = searchResults.map { searchResult in
                    return [
                        "name": searchResult.name,
                        "address": searchResult.address?.formattedAddress(style: .full) ?? "",
                        "latitude": searchResult.coordinate?.latitude ?? 0.0,
                        "longitude": searchResult.coordinate?.longitude ?? 0.0,
                        "country": searchResult.address?.country ?? "",
                        "region": searchResult.address?.region ?? "",
                        "city": searchResult.address?.place ?? "",
                        "postcode": searchResult.address?.postcode ?? "",
                        "relevance": searchResult.distance ?? 0.0
                    ]
                }
                result(locations)
            case .failure(let error):
                print("Search error: \(error)")
                result([])
            }
        }
    }
    
    private func reverseGeocode(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let latitude = args["latitude"] as? Double,
              let longitude = args["longitude"] as? Double else {
            result(nil)
            return
        }
        
        guard let searchEngine = offlineSearchEngine else {
            result(nil)
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let options = ReverseGeocodingOptions(point: coordinate)
        
        let reverseTask = searchEngine.reverseGeocoding(options: options) { response in
            switch response {
            case .success(let searchResults):
                if let firstResult = searchResults.first {
                    let location = [
                        "name": firstResult.name,
                        "address": firstResult.address?.formattedAddress(style: .full) ?? "",
                        "latitude": latitude,
                        "longitude": longitude,
                        "country": firstResult.address?.country ?? "",
                        "region": firstResult.address?.region ?? "",
                        "city": firstResult.address?.place ?? "",
                        "postcode": firstResult.address?.postcode ?? "",
                        "relevance": 1.0
                    ]
                    result(location)
                } else {
                    result(nil)
                }
            case .failure(let error):
                print("Reverse geocoding error: \(error)")
                result(nil)
            }
        }
    }
    
    private func isOfflineDataAvailable(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let latitude = args["latitude"] as? Double,
              let longitude = args["longitude"] as? Double else {
            result(false)
            return
        }
        
        guard let manager = offlineManager else {
            result(false)
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        // Check if any offline regions contain this coordinate
        let offlineRegions = manager.allOfflineRegions
        let hasData = offlineRegions.contains { region in
            // Check if coordinate is within region bounds
            // This is a simplified check - you might need more sophisticated logic
            return true // Placeholder - implement proper bounds checking
        }
        
        result(hasData)
    }
    
    private func downloadOfflineRegion(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let regionId = args["regionId"] as? String,
              let northLat = args["northLatitude"] as? Double,
              let southLat = args["southLatitude"] as? Double,
              let eastLng = args["eastLongitude"] as? Double,
              let westLng = args["westLongitude"] as? Double else {
            result(false)
            return
        }
        
        let minZoom = args["minZoom"] as? Double ?? 0.0
        let maxZoom = args["maxZoom"] as? Double ?? 16.0
        
        guard let manager = offlineManager else {
            result(false)
            return
        }
        
        // Create coordinate bounds
        let northeast = CLLocationCoordinate2D(latitude: northLat, longitude: eastLng)
        let southwest = CLLocationCoordinate2D(latitude: southLat, longitude: westLng)
        let bounds = CoordinateBounds(southwest: southwest, northeast: northeast)
        
        // Create tile region load options
        let tileRegionLoadOptions = TileRegionLoadOptions(
            geometry: Geometry.polygon(Polygon([bounds.toRing()])),
            descriptorsOptions: [
                TilesetDescriptorOptions(styleURI: .streets, minZoom: UInt8(minZoom), maxZoom: UInt8(maxZoom))
            ],
            metadata: ["name": regionId],
            acceptExpired: true
        )
        
        // Start download
        let cancelable = manager.loadTileRegion(forId: regionId, loadOptions: tileRegionLoadOptions) { progress in
            print("Download progress: \(progress)")
        } completion: { downloadResult in
            switch downloadResult {
            case .success:
                result(true)
            case .failure(let error):
                print("Download error: \(error)")
                result(false)
            }
        }
        
        // Store cancelable if needed for cancellation
    }
    
    private func getOfflineRegions(result: @escaping FlutterResult) {
        guard let manager = offlineManager else {
            result([])
            return
        }
        
        let regions = manager.allOfflineRegions.map { region in
            return [
                "id": region.id,
                "name": region.id, // Using ID as name for simplicity
                "northLatitude": 0.0, // Placeholder - extract from region metadata
                "southLatitude": 0.0,
                "eastLongitude": 0.0,
                "westLongitude": 0.0,
                "minZoom": 0.0,
                "maxZoom": 16.0,
                "downloadState": 2, // Assume completed for simplicity
                "downloadProgress": 1.0
            ]
        }
        
        result(regions)
    }
}

// Helper extension for coordinate bounds
extension CoordinateBounds {
    func toRing() -> [CLLocationCoordinate2D] {
        return [
            southwest,
            CLLocationCoordinate2D(latitude: southwest.latitude, longitude: northeast.longitude),
            northeast,
            CLLocationCoordinate2D(latitude: northeast.latitude, longitude: southwest.longitude),
            southwest
        ]
    }
}
