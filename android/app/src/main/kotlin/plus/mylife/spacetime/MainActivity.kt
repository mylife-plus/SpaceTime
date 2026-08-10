package plus.mylife.spacetime

import android.content.ContentValues
import android.location.Address
import android.location.Geocoder
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.*

/// [FlutterFragmentActivity] is required for local_auth / BiometricPrompt on Android.
class MainActivity : FlutterFragmentActivity() {
    private val LOCATION_SEARCH_CHANNEL = "com.spacetime.location_search"
    private val TILE_DOWNLOAD_CHANNEL = "com.spacetime.tile_download"
    private val APP_LOCALE_CHANNEL = "com.spacetime/app_locale"
    private val BACKUP_DOWNLOADS_CHANNEL = "com.spacetime/backup_downloads"

    private lateinit var geocoder: Geocoder
    private var tileDownloader: MapboxTileDownloader? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        geocoder = Geocoder(this, Locale.getDefault())

        // Register backup Downloads channel FIRST. Mapbox class-loading can throw
        // Errors (not Exception) and previously aborted the rest of this method,
        // which caused MissingPluginException for saveToDownloads.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_DOWNLOADS_CHANNEL)
            .setMethodCallHandler { call, result ->
                Log.d("MainActivity", "backup_downloads call=${call.method}")
                when (call.method) {
                    "saveToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val fileName = call.argument<String>("fileName")
                        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "sourcePath and fileName required", null)
                        } else {
                            Thread {
                                saveBackupToDownloads(sourcePath, fileName, result)
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        Log.i("MainActivity", "Registered channel $BACKUP_DOWNLOADS_CHANNEL")

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

        // Initialize tile downloader (must not abort other channel registration).
        var tileDownloaderReady = false
        try {
            Log.d("MainActivity", "Creating MapboxTileDownloader instance...")
            tileDownloader = MapboxTileDownloader()
            tileDownloaderReady = true
            Log.d("MainActivity", "MapboxTileDownloader created successfully")
        } catch (t: Throwable) {
            Log.e("MainActivity", "Failed to create MapboxTileDownloader: ${t.message}", t)
        }

        // Tile download channel
        Log.d("MainActivity", "Setting up tile download channel: $TILE_DOWNLOAD_CHANNEL")
        val tileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TILE_DOWNLOAD_CHANNEL)
        tileChannel.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")
            if (!tileDownloaderReady) {
                result.error("TILE_DOWNLOADER_UNAVAILABLE", "Mapbox tile downloader failed to init", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "initializeTileStore" -> {
                    Log.d("MainActivity", "Calling tileDownloader.initialize()")
                    tileDownloader!!.initialize(result)
                }
                "downloadTiles" -> {
                    val regionGeometry = call.argument<Map<String, Any>>("regionGeometry")
                    val minZoom = call.argument<Int>("minZoom") ?: 14
                    val maxZoom = call.argument<Int>("maxZoom") ?: 14

                    if (regionGeometry != null) {
                        tileDownloader!!.downloadTiles(
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
                        tileDownloader!!.downloadZoomTiles(
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
                    result.success(tileDownloader!!.getDownloadProgress())
                }
                "cancelDownload" -> {
                    tileDownloader!!.cancelDownload(result)
                }
                "isDownloadInProgress" -> {
                    result.success(tileDownloader!!.isDownloadInProgress())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /// Copies [sourcePath] into the public Downloads folder so the backup is
    /// visible in Files / Download (not only the app sandbox).
    /// May run off the main thread; always replies via [mainHandler].
    private fun saveBackupToDownloads(
        sourcePath: String,
        fileName: String,
        result: MethodChannel.Result,
    ) {
        fun replyOk(payload: Map<String, Any>) {
            mainHandler.post { result.success(payload) }
        }
        fun replyError(code: String, message: String?) {
            mainHandler.post { result.error(code, message, null) }
        }

        try {
            val source = File(sourcePath)
            if (!source.exists() || !source.isFile) {
                replyError("NOT_FOUND", "Backup file missing: $sourcePath")
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = applicationContext.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/zip")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val collection =
                    MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val uri = resolver.insert(collection, values)
                if (uri == null) {
                    replyError("INSERT_FAILED", "Could not create Downloads entry")
                    return
                }
                resolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(source).use { input -> input.copyTo(out) }
                } ?: run {
                    resolver.delete(uri, null, null)
                    replyError("WRITE_FAILED", "Could not open Downloads stream")
                    return
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                Log.i("MainActivity", "saveBackupToDownloads ok uri=$uri")
                replyOk(
                    mapOf(
                        "ok" to true,
                        "uri" to uri.toString(),
                        "relativePath" to "${Environment.DIRECTORY_DOWNLOADS}/$fileName",
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                val downloads =
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!downloads.exists()) {
                    downloads.mkdirs()
                }
                val dest = File(downloads, fileName)
                source.copyTo(dest, overwrite = true)
                MediaScannerConnection.scanFile(
                    applicationContext,
                    arrayOf(dest.absolutePath),
                    arrayOf("application/zip"),
                    null,
                )
                Log.i("MainActivity", "saveBackupToDownloads ok path=${dest.absolutePath}")
                replyOk(
                    mapOf(
                        "ok" to true,
                        "uri" to dest.absolutePath,
                        "relativePath" to dest.absolutePath,
                    ),
                )
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "saveBackupToDownloads failed", e)
            replyError("SAVE_FAILED", e.message)
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
