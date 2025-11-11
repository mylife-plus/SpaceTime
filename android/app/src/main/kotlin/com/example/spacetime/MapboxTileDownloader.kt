package com.example.spacetime

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.mapbox.bindgen.Value
import com.mapbox.common.Cancelable
import com.mapbox.common.NetworkRestriction
import com.mapbox.common.TileRegionLoadOptions
import com.mapbox.common.TileStore
import com.mapbox.common.TileStoreOptions
import com.mapbox.geojson.Geometry
import com.mapbox.geojson.Point
import com.mapbox.geojson.Polygon
import com.mapbox.maps.GlyphsRasterizationMode
import com.mapbox.maps.OfflineManager
import com.mapbox.maps.Style
import com.mapbox.maps.StylePackLoadOptions
import com.mapbox.maps.TilesetDescriptorOptions
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Native Mapbox tile downloader for Android
 * Supports downloading up to 6000 tiles using Mapbox Maps SDK v11 offline APIs
 */
class MapboxTileDownloader {
    companion object {
        private const val TAG = "MapboxTileDownloader"
        private const val TILE_REGION_PREFIX = "spacetime-native-tiles"
        private const val ZOOM_REGION_ID = "spacetime-native-zoom-tiles"
        private const val STYLE_PACK_ID = "spacetime-style-pack"
        private const val MAPBOX_STREETS_STYLE = Style.MAPBOX_STREETS
        private const val MAX_TILES = 6000
        private const val MAX_TILES_PER_REGION = 700 // Mapbox limit is 750, use 700 for safety
    }

    private var tileStore: TileStore? = null
    private var offlineManager: OfflineManager? = null
    private var isDownloading = false
    private var downloadedTileCount: Long = 0
    private var totalTileCount: Long = 0
    private var currentRegionIndex = 0
    private var totalRegions = 0
    private var styleCancelable: Cancelable? = null
    private var tileCancelable: Cancelable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val cancelables = mutableListOf<Cancelable>()

    /**
     * Initialize the tile store and offline manager
     */
    fun initialize(result: MethodChannel.Result) {
        Log.d(TAG, "========================================")
        Log.d(TAG, "initialize() method called")
        Log.d(TAG, "========================================")

        try {
            Log.d(TAG, "Step 1: Starting TileStore and OfflineManager initialization...")

            // Create TileStore instance
            Log.d(TAG, "Step 2: Creating TileStore instance...")
            try {
                tileStore = TileStore.create()
                Log.d(TAG, "Step 2: TileStore.create() completed")
                Log.d(TAG, "Step 2: TileStore is null? ${tileStore == null}")

                if (tileStore == null) {
                    throw Exception("TileStore.create() returned null")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Step 2: FAILED to create TileStore", e)
                throw Exception("TileStore creation failed: ${e.message}", e)
            }

            // Set disk quota to allow up to 6000 tiles (approximately 1GB for zoom 15-16)
            Log.d(TAG, "Step 3: Setting disk quota to 1GB...")
            try {
                val diskQuota = 1024L * 1024 * 1024 // 1GB
                val quotaValue = Value(diskQuota)
                Log.d(TAG, "Step 3: Created Value object for quota: ${diskQuota / (1024 * 1024)}MB")
                tileStore?.setOption(TileStoreOptions.DISK_QUOTA, quotaValue)
                Log.d(TAG, "Step 3: Disk quota set successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Step 3: FAILED to set disk quota", e)
                throw Exception("Setting disk quota failed: ${e.message}", e)
            }

            // CRITICAL: Increase the tile region size limit to allow 6000 tiles
            // By default, Mapbox limits to 750 tiles per region
            Log.d(TAG, "Step 3.5: Setting max tile region size to 6000 tiles...")
            try {
                val maxTiles = 6000L
                val maxTilesValue = Value(maxTiles)
                Log.d(TAG, "Step 3.5: Created Value object for max tiles: $maxTiles")

                // Try different option keys that might work for tile limit
                try {
                    tileStore?.setOption("mapbox.common.TileStore.maxTileRegionSize", maxTilesValue)
                    Log.d(TAG, "Step 3.5: Set maxTileRegionSize option")
                } catch (e: Exception) {
                    Log.w(TAG, "Step 3.5: maxTileRegionSize option not available: ${e.message}")
                }

                try {
                    tileStore?.setOption("max-tile-region-size", maxTilesValue)
                    Log.d(TAG, "Step 3.5: Set max-tile-region-size option")
                } catch (e: Exception) {
                    Log.w(TAG, "Step 3.5: max-tile-region-size option not available: ${e.message}")
                }

                Log.d(TAG, "Step 3.5: Max tile region size configuration attempted")
            } catch (e: Exception) {
                Log.w(TAG, "Step 3.5: WARNING - Could not set max tile region size: ${e.message}")
                Log.w(TAG, "Step 3.5: Will attempt download anyway - may be limited to 750 tiles")
            }

            // Create OfflineManager instance
            Log.d(TAG, "Step 4: Creating OfflineManager instance...")
            try {
                offlineManager = OfflineManager()
                Log.d(TAG, "Step 4: OfflineManager() completed")
                Log.d(TAG, "Step 4: OfflineManager is null? ${offlineManager == null}")

                if (offlineManager == null) {
                    throw Exception("OfflineManager() returned null")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Step 4: FAILED to create OfflineManager", e)
                throw Exception("OfflineManager creation failed: ${e.message}", e)
            }

            Log.d(TAG, "========================================")
            Log.d(TAG, "✅ SUCCESS: TileStore and OfflineManager initialized")
            Log.d(TAG, "========================================")

            mainHandler.post {
                Log.d(TAG, "Posting success result to Flutter")
                result.success(mapOf("success" to true))
            }
        } catch (e: Exception) {
            Log.e(TAG, "========================================")
            Log.e(TAG, "❌ INITIALIZATION FAILED")
            Log.e(TAG, "Error type: ${e.javaClass.name}")
            Log.e(TAG, "Error message: ${e.message}")
            Log.e(TAG, "========================================")
            e.printStackTrace()

            mainHandler.post {
                Log.e(TAG, "Posting error result to Flutter")
                result.error(
                    "INIT_ERROR",
                    "Failed to initialize: ${e.message}",
                    mapOf(
                        "errorType" to e.javaClass.name,
                        "stackTrace" to e.stackTraceToString()
                    )
                )
            }
        }
    }

    /**
     * Download tiles for a given region
     */
    fun downloadTiles(
        regionGeometry: Map<String, Any>,
        minZoom: Int,
        maxZoom: Int,
        onProgress: (downloaded: Long, total: Long) -> Unit,
        result: MethodChannel.Result
    ) {
        if (isDownloading) {
            result.error("ALREADY_DOWNLOADING", "Download already in progress", null)
            return
        }

        if (tileStore == null || offlineManager == null) {
            result.error("NOT_INITIALIZED", "TileStore not initialized", null)
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                isDownloading = true
                downloadedTileCount = 0
                totalTileCount = 0

                Log.d(TAG, "Starting tile download for region with zoom $minZoom-$maxZoom")

                // Convert GeoJSON geometry to Mapbox Geometry
                val geometry = convertToGeometry(regionGeometry)
                
                // Step 1: Download style pack
                downloadStylePack(onProgress)
                
                // Step 2: Download tile region
                downloadTileRegion(geometry, minZoom, maxZoom, onProgress, result)

            } catch (e: Exception) {
                Log.e(TAG, "Download error: ${e.message}", e)
                isDownloading = false
                mainHandler.post {
                    result.error("DOWNLOAD_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * Download style pack
     */
    private fun downloadStylePack(onProgress: (downloaded: Long, total: Long) -> Unit) {
        val stylePackLoadOptions = StylePackLoadOptions.Builder()
            .glyphsRasterizationMode(GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY)
            .metadata(Value("SpaceTime offline style pack"))
            .build()

        Log.d(TAG, "Downloading style pack...")

        styleCancelable = offlineManager?.loadStylePack(
            MAPBOX_STREETS_STYLE,
            stylePackLoadOptions,
            { progress ->
                // Style pack progress
                val completed = progress.completedResourceCount
                val required = progress.requiredResourceCount
                Log.d(TAG, "Style pack progress: $completed/$required")
            },
            { expected ->
                if (expected.isValue) {
                    expected.value?.let { stylePack ->
                        Log.d(TAG, "Style pack downloaded successfully")
                    }
                }
                expected.error?.let { error ->
                    Log.e(TAG, "Style pack download error: ${error.message}")
                }
            }
        )
    }

    /**
     * Download tile region
     */
    private fun downloadTileRegion(
        geometry: Geometry,
        minZoom: Int,
        maxZoom: Int,
        onProgress: (downloaded: Long, total: Long) -> Unit,
        result: MethodChannel.Result
    ) {
        Log.d(TAG, "========================================")
        Log.d(TAG, "downloadTileRegion() called")
        Log.d(TAG, "Geometry: $geometry")
        Log.d(TAG, "Zoom range: $minZoom - $maxZoom")
        Log.d(TAG, "========================================")

        // Create tileset descriptor
        val tilesetDescriptor = offlineManager?.createTilesetDescriptor(
            TilesetDescriptorOptions.Builder()
                .styleURI(MAPBOX_STREETS_STYLE)
                .minZoom(minZoom.toByte())
                .maxZoom(maxZoom.toByte())
                .build()
        )

        if (tilesetDescriptor == null) {
            Log.e(TAG, "Failed to create tileset descriptor")
            mainHandler.post {
                result.error("DESCRIPTOR_ERROR", "Failed to create tileset descriptor", null)
            }
            return
        }

        Log.d(TAG, "Tileset descriptor created successfully")

        // Create tile region load options
        // Note: Attempting to download up to 6000 tiles (default limit is 750)
        val tileRegionLoadOptions = TileRegionLoadOptions.Builder()
            .geometry(geometry)
            .descriptors(listOf(tilesetDescriptor))
            .metadata(Value("SpaceTime offline tile region"))
            .acceptExpired(false)
            .networkRestriction(NetworkRestriction.NONE)
            .averageBytesPerSecond(null) // No bandwidth limit for faster downloads
            .build()

        Log.d(TAG, "TileRegionLoadOptions configured:")
        Log.d(TAG, "  - Geometry: $geometry")
        Log.d(TAG, "  - Network restriction: NONE")
        Log.d(TAG, "  - Attempting to download up to 6000 tiles")

        Log.d(TAG, "Starting tile region download...")
        val regionId = "${TILE_REGION_PREFIX}-${System.currentTimeMillis()}"
        Log.d(TAG, "Region ID: $regionId")

        tileCancelable = tileStore?.loadTileRegion(
            regionId,
            tileRegionLoadOptions,
            { progress ->
                // Tile region progress
                downloadedTileCount = progress.completedResourceCount
                totalTileCount = progress.requiredResourceCount

                // Log progress every 100 tiles or at key milestones
                if (downloadedTileCount % 100 == 0L || downloadedTileCount == totalTileCount) {
                    Log.d(TAG, "========================================")
                    Log.d(TAG, "Tile Download Progress:")
                    Log.d(TAG, "Downloaded: $downloadedTileCount tiles")
                    Log.d(TAG, "Total: $totalTileCount tiles")
                    Log.d(TAG, "Progress: ${if (totalTileCount > 0) (downloadedTileCount * 100 / totalTileCount) else 0}%")
                    Log.d(TAG, "========================================")
                }

                // Notify Flutter about progress
                mainHandler.post {
                    onProgress(downloadedTileCount, totalTileCount)
                }
            }
        ) { expected ->
            isDownloading = false

            if (expected.isValue) {
                expected.value?.let { tileRegion ->
                    Log.d(TAG, "========================================")
                    Log.d(TAG, "✅ TILE REGION DOWNLOAD COMPLETED")
                    Log.d(TAG, "Total tiles downloaded: $downloadedTileCount")
                    Log.d(TAG, "Total tiles expected: $totalTileCount")
                    Log.d(TAG, "Region ID: ${tileRegion.id}")
                    Log.d(TAG, "========================================")

                    mainHandler.post {
                        result.success(mapOf(
                            "success" to true,
                            "downloadedTiles" to downloadedTileCount,
                            "totalTiles" to totalTileCount
                        ))
                    }
                }
            }

            expected.error?.let { error ->
                Log.e(TAG, "========================================")
                Log.e(TAG, "❌ TILE REGION DOWNLOAD ERROR")
                Log.e(TAG, "Error: ${error.message}")
                Log.e(TAG, "Downloaded before error: $downloadedTileCount tiles")
                Log.e(TAG, "========================================")
                mainHandler.post {
                    result.error("TILE_DOWNLOAD_ERROR", error.message, null)
                }
            }
        }
    }

    /**
     * Download additional zoom level tiles
     */
    fun downloadZoomTiles(
        regionGeometry: Map<String, Any>,
        zoomLevel: Int,
        onProgress: (downloaded: Long, total: Long) -> Unit,
        result: MethodChannel.Result
    ) {
        downloadTiles(regionGeometry, zoomLevel, zoomLevel, onProgress, result)
    }

    /**
     * Get current download progress
     */
    fun getDownloadProgress(): Map<String, Any> {
        return mapOf(
            "downloadedTiles" to downloadedTileCount,
            "totalTiles" to totalTileCount,
            "isDownloading" to isDownloading
        )
    }

    /**
     * Cancel ongoing download
     */
    fun cancelDownload(result: MethodChannel.Result) {
        try {
            styleCancelable?.cancel()
            tileCancelable?.cancel()
            isDownloading = false
            
            Log.d(TAG, "Download cancelled")
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            Log.e(TAG, "Cancel error: ${e.message}", e)
            result.error("CANCEL_ERROR", e.message, null)
        }
    }

    /**
     * Check if download is in progress
     */
    fun isDownloadInProgress(): Boolean {
        return isDownloading
    }

    /**
     * Convert GeoJSON geometry map to Mapbox Geometry
     */
    private fun convertToGeometry(geometryMap: Map<String, Any>): Geometry {
        val type = geometryMap["type"] as? String
        val coordinates = geometryMap["coordinates"] as? List<*>

        Log.d(TAG, "========================================")
        Log.d(TAG, "Converting GeoJSON to Mapbox Geometry")
        Log.d(TAG, "Type: $type")
        Log.d(TAG, "Coordinates: $coordinates")
        Log.d(TAG, "========================================")

        return when (type) {
            "Polygon" -> {
                val rings = coordinates as List<List<List<Double>>>
                val points = rings[0].map { coord ->
                    Point.fromLngLat(coord[0], coord[1])
                }

                Log.d(TAG, "Polygon created with ${points.size} points")
                points.forEachIndexed { index, point ->
                    Log.d(TAG, "Point $index: (${point.longitude()}, ${point.latitude()})")
                }

                Polygon.fromLngLats(listOf(points))
            }
            "Point" -> {
                val coords = coordinates as List<Double>
                Log.d(TAG, "Point created: (${coords[0]}, ${coords[1]})")
                Point.fromLngLat(coords[0], coords[1])
            }
            else -> {
                Log.e(TAG, "Unsupported geometry type: $type")
                throw IllegalArgumentException("Unsupported geometry type: $type")
            }
        }
    }
}
