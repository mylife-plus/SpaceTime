import Foundation
import MapboxMaps

/**
 * Native iOS implementation for Mapbox tile downloading
 * Supports downloading up to 6000 tiles using native Mapbox SDK
 */
class MapboxTileDownloader {
    
    private static let TAG = "MapboxTileDownloader"
    private static let TILE_REGION_ID = "spacetime-native-tiles"
    private static let ZOOM_REGION_ID = "spacetime-native-zoom-tiles"
    private static let MAPBOX_STREETS_STYLE = "mapbox://styles/mapbox/streets-v12"
    private static let MAX_TILES = 6000
    
    private var tileStore: TileStore?
    private var isDownloading = false
    private var downloadedTileCount: Int = 0
    private var totalTileCount: Int = 0
    
    /**
     * Initialize the TileStore
     */
    func initialize(result: @escaping FlutterResult) {
        do {
            tileStore = TileStore.default
            print("\(MapboxTileDownloader.TAG): TileStore initialized successfully")
            result(true)
        } catch {
            print("\(MapboxTileDownloader.TAG): Failed to initialize TileStore: \(error)")
            result(FlutterError(code: "INIT_ERROR",
                              message: "Failed to initialize TileStore: \(error.localizedDescription)",
                              details: nil))
        }
    }
    
    /**
     * Download offline map tiles
     */
    func downloadTiles(
        regionGeometry: [String: Any],
        minZoom: Int,
        maxZoom: Int,
        onProgress: @escaping (Int, Int) -> Void,
        result: @escaping FlutterResult
    ) {
        guard let tileStore = tileStore else {
            result(FlutterError(code: "NOT_INITIALIZED",
                              message: "TileStore not initialized",
                              details: nil))
            return
        }
        
        if isDownloading {
            result(FlutterError(code: "ALREADY_DOWNLOADING",
                              message: "Download already in progress",
                              details: nil))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.isDownloading = true
            self.downloadedTileCount = 0
            self.totalTileCount = 0
            
            print("\(MapboxTileDownloader.TAG): Starting tile download - Zoom: \(minZoom)-\(maxZoom)")
            
            do {
                // Convert region geometry to Mapbox Geometry
                let geometry = try self.createGeometryFromMap(regionGeometry)
                
                // Create tileset descriptor options
                let tilesetDescriptor = TilesetDescriptorOptions(
                    styleURI: MapboxTileDownloader.MAPBOX_STREETS_STYLE,
                    minZoom: UInt8(minZoom),
                    maxZoom: UInt8(maxZoom)
                )
                
                // Create tile region load options
                let loadOptions = TileRegionLoadOptions(
                    geometry: geometry,
                    descriptors: [tilesetDescriptor],
                    acceptExpired: false,
                    networkRestriction: .none
                )
                
                // Start tile download
                let cancellable = tileStore.loadTileRegion(
                    forId: MapboxTileDownloader.TILE_REGION_ID,
                    loadOptions: loadOptions
                ) { progress in
                    // Progress callback
                    self.downloadedTileCount = Int(progress.completedResourceCount)
                    self.totalTileCount = Int(progress.requiredResourceCount)
                    
                    print("\(MapboxTileDownloader.TAG): Download progress: \(self.downloadedTileCount)/\(self.totalTileCount) tiles")
                    
                    // Notify Flutter about progress
                    DispatchQueue.main.async {
                        onProgress(self.downloadedTileCount, self.totalTileCount)
                    }
                    
                    // Check if we've reached the max tile limit
                    if self.downloadedTileCount >= MapboxTileDownloader.MAX_TILES {
                        print("\(MapboxTileDownloader.TAG): Reached max tile limit: \(MapboxTileDownloader.MAX_TILES)")
                    }
                } completion: { completionResult in
                    self.isDownloading = false
                    
                    switch completionResult {
                    case .success(let region):
                        print("\(MapboxTileDownloader.TAG): Tile download completed: \(self.downloadedTileCount) tiles")
                        DispatchQueue.main.async {
                            result([
                                "success": true,
                                "tilesDownloaded": self.downloadedTileCount,
                                "totalTiles": self.totalTileCount
                            ])
                        }
                    case .failure(let error):
                        print("\(MapboxTileDownloader.TAG): Tile download failed: \(error)")
                        DispatchQueue.main.async {
                            result(FlutterError(code: "DOWNLOAD_ERROR",
                                              message: error.localizedDescription,
                                              details: nil))
                        }
                    }
                }
                
            } catch {
                self.isDownloading = false
                print("\(MapboxTileDownloader.TAG): Error during tile download: \(error)")
                DispatchQueue.main.async {
                    result(FlutterError(code: "DOWNLOAD_ERROR",
                                      message: "Download failed: \(error.localizedDescription)",
                                      details: nil))
                }
            }
        }
    }
    
    /**
     * Download additional zoom level tiles
     */
    func downloadZoomTiles(
        regionGeometry: [String: Any],
        zoomLevel: Int,
        onProgress: @escaping (Int, Int) -> Void,
        result: @escaping FlutterResult
    ) {
        guard let tileStore = tileStore else {
            result(FlutterError(code: "NOT_INITIALIZED",
                              message: "TileStore not initialized",
                              details: nil))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            print("\(MapboxTileDownloader.TAG): Starting zoom level \(zoomLevel) tile download")
            
            do {
                // Convert region geometry to Mapbox Geometry
                let geometry = try self.createGeometryFromMap(regionGeometry)
                
                // Create tileset descriptor for specific zoom level
                let tilesetDescriptor = TilesetDescriptorOptions(
                    styleURI: MapboxTileDownloader.MAPBOX_STREETS_STYLE,
                    minZoom: UInt8(zoomLevel),
                    maxZoom: UInt8(zoomLevel)
                )
                
                // Create tile region load options
                let loadOptions = TileRegionLoadOptions(
                    geometry: geometry,
                    descriptors: [tilesetDescriptor],
                    acceptExpired: false,
                    networkRestriction: .none
                )
                
                // Start tile download
                let cancellable = tileStore.loadTileRegion(
                    forId: MapboxTileDownloader.ZOOM_REGION_ID,
                    loadOptions: loadOptions
                ) { progress in
                    let downloaded = Int(progress.completedResourceCount)
                    let total = Int(progress.requiredResourceCount)
                    
                    print("\(MapboxTileDownloader.TAG): Zoom \(zoomLevel) progress: \(downloaded)/\(total) tiles")
                    
                    DispatchQueue.main.async {
                        onProgress(downloaded, total)
                    }
                } completion: { completionResult in
                    switch completionResult {
                    case .success:
                        print("\(MapboxTileDownloader.TAG): Zoom level \(zoomLevel) download completed")
                        DispatchQueue.main.async {
                            result(["success": true])
                        }
                    case .failure(let error):
                        print("\(MapboxTileDownloader.TAG): Zoom level \(zoomLevel) download failed: \(error)")
                        DispatchQueue.main.async {
                            result(FlutterError(code: "DOWNLOAD_ERROR",
                                              message: error.localizedDescription,
                                              details: nil))
                        }
                    }
                }
                
            } catch {
                print("\(MapboxTileDownloader.TAG): Error during zoom tile download: \(error)")
                DispatchQueue.main.async {
                    result(FlutterError(code: "DOWNLOAD_ERROR",
                                      message: "Download failed: \(error.localizedDescription)",
                                      details: nil))
                }
            }
        }
    }
    
    /**
     * Get current download progress
     */
    func getDownloadProgress() -> [String: Int] {
        return [
            "downloaded": downloadedTileCount,
            "total": totalTileCount
        ]
    }
    
    /**
     * Cancel ongoing download
     */
    func cancelDownload(result: @escaping FlutterResult) {
        isDownloading = false
        print("\(MapboxTileDownloader.TAG): Download cancelled")
        result(true)
    }
    
    /**
     * Create Mapbox Geometry from dictionary
     */
    private func createGeometryFromMap(_ geometry: [String: Any]) throws -> Geometry {
        guard let coordinates = geometry["coordinates"] as? [[[Double]]] else {
            throw NSError(domain: "MapboxTileDownloader",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid geometry coordinates"])
        }
        
        let outerRing = coordinates[0].map { coord in
            CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
        }
        
        return Geometry.polygon(Polygon([outerRing]))
    }
    
    /**
     * Check if download is in progress
     */
    func isDownloadInProgress() -> Bool {
        return isDownloading
    }
}

