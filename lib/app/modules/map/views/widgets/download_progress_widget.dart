import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/services/background_tile_download_service.dart';

/// Widget to display background tile download progress
class DownloadProgressWidget extends StatelessWidget {
  const DownloadProgressWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = BackgroundTileDownloadService.instance;

    return Obx(() {
      if (!service.isDownloading.value) return const SizedBox.shrink();

      return _buildProgressIndicator(service);
    });
  }

  /// Build the progress indicator
  Widget _buildProgressIndicator(BackgroundTileDownloadService service) {
    return Positioned(
      top: 100,
      left: 16,
      right: 16,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.download, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Downloading offline maps...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showDownloadDetails(service),
                  child: const Icon(
                    Icons.info_outline,
                    color: Colors.white70,
                    size: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Obx(
              () => LinearProgressIndicator(
                value: service.downloadProgress.value,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Obx(
                  () => Text(
                    '${service.totalTilesDownloaded.value} tiles',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
                Obx(
                  () => Text(
                    '${(service.downloadProgress.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ],
            ),
            if (service.currentDownloadRegion.value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Obx(
                  () => Text(
                    'Region: ${service.currentDownloadRegion.value}',
                    style: const TextStyle(color: Colors.white60, fontSize: 9),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Show download details dialog
  void _showDownloadDetails(BackgroundTileDownloadService service) {
    Get.dialog(
      AlertDialog(
        title: const Text('Offline Map Download'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(
              () => Text(
                'Progress: ${(service.downloadProgress.value * 100).toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                'Tiles Downloaded: ${service.totalTilesDownloaded.value}',
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                'Current Region: ${service.currentDownloadRegion.value.isEmpty ? 'None' : service.currentDownloadRegion.value}',
              ),
            ),
            const SizedBox(height: 8),
            Obx(() => Text('Queue: ${service.downloadQueue.length} regions')),
            const SizedBox(height: 16),
            const Text(
              'Maps are being downloaded in the background for offline use. This process won\'t affect app performance.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('OK')),
          TextButton(
            onPressed: () {
              Get.back();
              _showDownloadSettings(service);
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  /// Show download settings dialog
  void _showDownloadSettings(BackgroundTileDownloadService service) {
    Get.dialog(
      AlertDialog(
        title: const Text('Download Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(
              () => SwitchListTile(
                title: const Text('Auto Download'),
                subtitle: const Text(
                  'Automatically download tiles for frequently visited areas',
                ),
                value: service.autoDownloadEnabled.value,
                onChanged: (value) => service.setAutoDownloadEnabled(value),
              ),
            ),
            Obx(
              () => SwitchListTile(
                title: const Text('WiFi Only'),
                subtitle: const Text(
                  'Download tiles only when connected to WiFi',
                ),
                value: service.wifiOnlyDownloads.value,
                onChanged: (value) => service.setWifiOnlyDownloads(value),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Max Tiles: '),
                Expanded(
                  child: Obx(
                    () => Slider(
                      value: service.maxTilesLimit.value.toDouble(),
                      min: 10000,
                      max: 100000,
                      divisions: 9,
                      label: '${service.maxTilesLimit.value}',
                      onChanged:
                          (value) => service.setMaxTilesLimit(value.round()),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Close')),
        ],
      ),
    );
  }
}

/// Quota status widget for settings screen
class TileQuotaWidget extends StatelessWidget {
  const TileQuotaWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = BackgroundTileDownloadService.instance;
    final quota = service.getCurrentQuotaStatus();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Offline Map Storage',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: quota.usagePercentage / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                quota.shouldWarn ? Colors.orange : Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${quota.currentTiles} / ${quota.maxTiles} tiles (${quota.usagePercentage.toStringAsFixed(1)}%)',
            ),
            if (quota.shouldWarn)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  quota.shouldForceOffline
                      ? 'Quota reached - Offline mode enforced'
                      : 'Approaching quota limit',
                  style: TextStyle(
                    color:
                        quota.shouldForceOffline ? Colors.red : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        quota.shouldForceOffline
                            ? null
                            : () => _downloadCurrentArea(service),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Download Current Area'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showManagementDialog(service),
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Manage'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Download current area
  void _downloadCurrentArea(BackgroundTileDownloadService service) {
    // This would get current location and download tiles for that area
    Get.snackbar(
      'Download Started',
      'Downloading tiles for current area in background',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  /// Show management dialog
  void _showManagementDialog(BackgroundTileDownloadService service) {
    Get.dialog(
      AlertDialog(
        title: const Text('Manage Offline Maps'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Options:'),
            const SizedBox(height: 8),

            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Download Settings'),
              subtitle: const Text('Configure automatic downloads'),
              onTap: () {
                Get.back();
                _showDownloadSettings(service);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        ],
      ),
    );
  }

  /// Show download settings
  void _showDownloadSettings(BackgroundTileDownloadService service) {
    // Reuse the settings dialog from DownloadProgressWidget
    const DownloadProgressWidget()._showDownloadSettings(service);
  }
}
