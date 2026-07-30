package com.example.spacetime

import android.content.Context
import android.location.Address
import android.location.Geocoder
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

/// [FlutterFragmentActivity] is required for local_auth / BiometricPrompt on Android.
class MainActivity : FlutterFragmentActivity() {
    private val LOCATION_SEARCH_CHANNEL = "com.spacetime.location_search"
    private val TILE_DOWNLOAD_CHANNEL = "com.spacetime.tile_download"
    private val APP_LOCALE_CHANNEL = "com.spacetime/app_locale"

    private lateinit var geocoder: Geocoder
    private lateinit var tileDownloader: MapboxTileDownloader
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        geocoder = Geocoder(this, Locale.getDefault())

        // Initialize tile downloader
        try {
            Log.d("MainActivity", "Creating MapboxTileDownloader instance...")
            tileDownloader = MapboxTileDownloader()
            Log.d("MainActivity", "MapboxTileDownloader created successfully")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to create MapboxTileDownloader: ${e.message}", e)
            e.printStackTrace()
            throw e
        }

        // Location search channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_SEARCH_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNativeSearchAvailable" -> {
                    result.success(Geocoder.isPresent())
                }
                "searchLocations" -> {
                    val query = call.argument<String>("query")
                    val limit = call.argument<Int>("limit") ?: 10

                    if (query != null) {
                        searchLocations(query, limit, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Query cannot be null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Sync Flutter in-app language with Android application locales (permission dialogs, etc.)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_LOCALE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setApplicationLocales" -> {
                    val raw = call.argument<String>("languageTag") ?: "en"
                    val tag = when (raw.lowercase()) {
                        "de", "es", "fr", "en" -> raw.lowercase()
                        else -> "en"
                    }
                    AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Tile download channel
        Log.d("MainActivity", "Setting up tile download channel: $TILE_DOWNLOAD_CHANNEL")
        val tileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TILE_DOWNLOAD_CHANNEL)
        tileChannel.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")
            when (call.method) {
                "initializeTileStore" -> {
                    Log.d("MainActivity", "Calling tileDownloader.initialize()")
                    tileDownloader.initialize(result)
                }
                "downloadTiles" -> {
                    val regionGeometry = call.argument<Map<String, Any>>("regionGeometry")
                    val minZoom = call.argument<Int>("minZoom") ?: 14
                    val maxZoom = call.argument<Int>("maxZoom") ?: 14

                    if (regionGeometry != null) {
                        tileDownloader.downloadTiles(
                            regionGeometry,
                            minZoom,
                            maxZoom,
                            onProgress = { downloaded, total ->
                                mainHandler.post {
                                    tileChannel.invokeMethod("onProgress", mapOf(
                                        "downloaded" to downloaded,
                                        "total" to total
                                    ))
                                }
                            },
                            result
                        )
                    } else {
                        result.error("INVALID_ARGUMENT", "Region geometry cannot be null", null)
                    }
                }
                "downloadZoomTiles" -> {
                    val regionGeometry = call.argument<Map<String, Any>>("regionGeometry")
                    val zoomLevel = call.argument<Int>("zoomLevel") ?: 14

                    if (regionGeometry != null) {
                        tileDownloader.downloadZoomTiles(
                            regionGeometry,
                            zoomLevel,
                            onProgress = { downloaded, total ->
                                mainHandler.post {
                                    tileChannel.invokeMethod("onZoomProgress", mapOf(
                                        "downloaded" to downloaded,
                                        "total" to total
                                    ))
                                }
                            },
                            result
                        )
                    } else {
                        result.error("INVALID_ARGUMENT", "Region geometry cannot be null", null)
                    }
                }
                "getDownloadProgress" -> {
                    result.success(tileDownloader.getDownloadProgress())
                }
                "cancelDownload" -> {
                    tileDownloader.cancelDownload(result)
                }
                "isDownloadInProgress" -> {
                    result.success(tileDownloader.isDownloadInProgress())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun searchLocations(query: String, limit: Int, result: MethodChannel.Result) {
        try {
            if (!Geocoder.isPresent()) {
                result.success(emptyList<Map<String, Any>>())
                return
            }

            val addresses = geocoder.getFromLocationName(query, limit)
            val locations = mutableListOf<Map<String, Any>>()

            addresses?.forEach { address ->
                val location = mutableMapOf<String, Any?>(
                    "name" to (address.featureName ?: address.locality ?: query),
                    "displayName" to formatDisplayName(address),
                    "shortDisplayName" to formatShortDisplayName(address),
                    "latitude" to address.latitude,
                    "longitude" to address.longitude,
                    "country" to (address.countryName ?: ""),
                    "state" to (address.adminArea ?: address.subAdminArea),
                    "city" to (address.locality ?: address.subLocality ?: ""),
                    "type" to determineLocationType(address),
                    "population" to null
                )
                locations.add(location as Map<String, Any>)
            }

            result.success(locations)
        } catch (e: Exception) {
            result.error("SEARCH_ERROR", "Failed to search locations: ${e.message}", null)
        }
    }

    private fun formatDisplayName(address: Address): String {
        val parts = mutableListOf<String>()

        address.featureName?.let { if (it != address.locality) parts.add(it) }
        address.locality?.let { parts.add(it) }
        address.adminArea?.let { parts.add(it) }
        address.countryName?.let { parts.add(it) }

        return parts.joinToString(", ")
    }

    private fun formatShortDisplayName(address: Address): String {
        val parts = mutableListOf<String>()

        address.locality?.let { parts.add(it) }
        address.countryName?.let { parts.add(it) }

        return parts.joinToString(", ")
    }

    private fun determineLocationType(address: Address): String {
        return when {
            address.featureName != null && address.featureName != address.locality -> "landmark"
            address.locality != null -> "city"
            address.subAdminArea != null -> "town"
            address.adminArea != null -> "state"
            address.countryName != null -> "country"
            else -> "city"
        }
    }
}
