package com.example.spacetime

import android.content.Context
import android.location.Address
import android.location.Geocoder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.spacetime.location_search"
    private lateinit var geocoder: Geocoder

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        geocoder = Geocoder(this, Locale.getDefault())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
