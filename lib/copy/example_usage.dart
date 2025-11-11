import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'download_service_copy_helper.dart';

/// Example usage of the BackgroundTileDownloadServiceCopy
/// 
/// This file demonstrates how to use the copy version of the download service
/// in your application.

class DownloadServiceCopyExample extends StatefulWidget {
  const DownloadServiceCopyExample({Key? key}) : super(key: key);

  @override
  State<DownloadServiceCopyExample> createState() =>
      _DownloadServiceCopyExampleState();
}

class _DownloadServiceCopyExampleState
    extends State<DownloadServiceCopyExample> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  /// Initialize the copy service
  Future<void> _initializeService() async {
    try {
      // Note: In a real app, you would get these from your map controller
      // For this example, we're passing null (the service will handle it)
      await DownloadServiceCopyHelper.initialize(
        tileStore: null, // Replace with actual TileStore
        offlineManager: null, // Replace with actual OfflineManager
      );

      setState(() {
        _isInitialized = true;
      });

      debugPrint('Download service copy initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize download service copy: $e');
    }
  }

  /// Download a specific city region
  Future<void> _downloadCity(String cityName, double lat, double lng) async {
    if (!_isInitialized) {
      Get.snackbar(
        'Error',
        'Service not initialized yet',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // Create bounds around the city (approximately 10km radius)
    final bounds = mapbox.CoordinateBounds(
      southwest: mapbox.Point(
        coordinates: mapbox.Position(lng - 0.1, lat - 0.1),
      ),
      northeast: mapbox.Point(
        coordinates: mapbox.Position(lng + 0.1, lat + 0.1),
      ),
      infiniteBounds: false,
    );

    // Start download
    await DownloadServiceCopyHelper.downloadRegion(
      bounds: bounds,
      zoomLevels: [10, 11, 12],
    );

    Get.snackbar(
      'Download Started',
      'Downloading map tiles for $cityName',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Service Copy Example'),
      ),
      body: !_isInitialized
          ? const Center(
            child: CircularProgressIndicator(),
          )
          : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status Card
                _buildStatusCard(),

                const SizedBox(height: 16),

                // Download Progress Card
                _buildProgressCard(),

                const SizedBox(height: 16),

                // Quota Status Card
                _buildQuotaCard(),

                const SizedBox(height: 16),

                // City Download Buttons
                _buildCityButtons(),

                const SizedBox(height: 16),

                // Control Buttons
                _buildControlButtons(),
              ],
            ),
          ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Service Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Obx(() {
              final service = DownloadServiceCopyHelper.getService();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Initialized: ${_isInitialized ? "Yes" : "No"}'),
                  Text(
                    'Auto Download: ${service.autoDownloadEnabled.value ? "Enabled" : "Disabled"}',
                  ),
                  Text(
                    'Queue Length: ${service.downloadQueue.length} regions',
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Download Progress',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Obx(() {
              final service = DownloadServiceCopyHelper.getService();
              final isDownloading = service.isDownloading.value;
              final progress = service.downloadProgress.value;
              final currentRegion = service.currentDownloadRegion.value;

              if (!isDownloading) {
                return const Text('No active downloads');
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Region: $currentRegion'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 4),
                  Text('${(progress * 100).toStringAsFixed(1)}%'),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotaCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tile Quota',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Obx(() {
              final status = DownloadServiceCopyHelper.getQuotaStatus();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Downloaded: ${status.currentTiles} / ${status.maxTiles} tiles',
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: status.usagePercentage / 100,
                    backgroundColor: Colors.grey[300],
                    color: status.shouldForceOffline
                        ? Colors.red
                        : status.shouldWarn
                            ? Colors.orange
                            : Colors.green,
                  ),
                  const SizedBox(height: 4),
                  Text('${status.usagePercentage.toStringAsFixed(1)}%'),
                  if (status.shouldWarn)
                    const Text(
                      '⚠️ Approaching quota limit',
                      style: TextStyle(color: Colors.orange),
                    ),
                  if (status.shouldForceOffline)
                    const Text(
                      '🚫 Quota reached - offline mode',
                      style: TextStyle(color: Colors.red),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCityButtons() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Download Cities',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => _downloadCity('New York', 40.7128, -74.0060),
                  child: const Text('New York'),
                ),
                ElevatedButton(
                  onPressed: () => _downloadCity('London', 51.5074, -0.1278),
                  child: const Text('London'),
                ),
                ElevatedButton(
                  onPressed: () => _downloadCity('Tokyo', 35.6762, 139.6503),
                  child: const Text('Tokyo'),
                ),
                ElevatedButton(
                  onPressed: () => _downloadCity('Paris', 48.8566, 2.3522),
                  child: const Text('Paris'),
                ),
                ElevatedButton(
                  onPressed: () => _downloadCity('Sydney', -33.8688, 151.2093),
                  child: const Text('Sydney'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    await DownloadServiceCopyHelper.enableAutoDownloads();
                    Get.snackbar(
                      'Success',
                      'Auto downloads enabled',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Enable Auto'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await DownloadServiceCopyHelper.disableAutoDownloads();
                    Get.snackbar(
                      'Success',
                      'Auto downloads disabled',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                  icon: const Icon(Icons.pause),
                  label: const Text('Disable Auto'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await DownloadServiceCopyHelper.clearAllDownloads();
                    Get.snackbar(
                      'Success',
                      'Download queue cleared',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear Queue'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final confirmed = await Get.dialog<bool>(
                      AlertDialog(
                        title: const Text('Reset Quota'),
                        content: const Text(
                          'Are you sure you want to reset the tile quota? This will reset the download count to 0.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Get.back(result: false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Get.back(result: true),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      await DownloadServiceCopyHelper.resetQuota();
                      Get.snackbar(
                        'Success',
                        'Quota reset successfully',
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset Quota'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

