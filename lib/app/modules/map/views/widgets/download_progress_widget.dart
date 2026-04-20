import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/services/background_tile_download_service.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

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
                    'text_downloading_offline_maps'.tr,
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
                    trKey('text_service_totaltilesdownloaded_value_tiles', [
                      service.totalTilesDownloaded.value,
                    ]),
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
                    trKey('text_region_service_currentdownloadregion_value', [
                      service.currentDownloadRegion.value,
                    ]),
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
        title: Text('title_text_offline_map_download'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(
              () => Text(
                trKey('text_progress_service_downloadprogress_value_100_tostrin', [
                  (service.downloadProgress.value * 100).toStringAsFixed(1),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                trKey('text_tiles_downloaded_service_totaltilesdownloaded_value', [
                  service.totalTilesDownloaded.value,
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                trKey(
                  'text_region_service_currentdownloadregion_value',
                  [
                    service.currentDownloadRegion.value.isEmpty
                        ? 'l10n_literal_none'.tr
                        : service.currentDownloadRegion.value,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                trKey('text_queue_service_downloadqueue_length_regions', [
                  service.downloadQueue.length,
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'text_maps_are_being_downloaded_in_the_background_for_off'.tr,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('text_ok_3'.tr)),
          TextButton(
            onPressed: () {
              Get.back();
              _showDownloadSettings(service);
            },
            child: Text('text_settings'.tr),
          ),
        ],
      ),
    );
  }

  /// Show download settings dialog
  void _showDownloadSettings(BackgroundTileDownloadService service) {
    Get.dialog(
      AlertDialog(
        title: Text('title_text_download_settings'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(
              () => SwitchListTile(
                title: Text('title_text_auto_download'.tr),
                subtitle: Text(
                  'title_text_automatically_download_tiles_for_frequently_v'.tr,
                ),
                value: service.autoDownloadEnabled.value,
                onChanged: (value) => service.setAutoDownloadEnabled(value),
              ),
            ),
            Obx(
              () => SwitchListTile(
                title: Text('title_text_wifi_only'.tr),
                subtitle: Text(
                  'title_text_download_tiles_only_when_connected_to_wifi'.tr,
                ),
                value: service.wifiOnlyDownloads.value,
                onChanged: (value) => service.setWifiOnlyDownloads(value),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('text_max_tiles'.tr),
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
          TextButton(onPressed: () => Get.back(), child: Text('text_close_2'.tr)),
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
            Text(
              'text_offline_map_storage'.tr,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              trKey(
                'text_quota_currenttiles_quota_maxtiles_tiles_quota_usage',
                [
                  quota.currentTiles,
                  quota.maxTiles,
                  quota.usagePercentage.toStringAsFixed(1),
                ],
              ),
            ),
            if (quota.shouldWarn)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  quota.shouldForceOffline
                      ? 'text_offline_quota_enforced'.tr
                      : 'text_approaching_quota_limit'.tr,
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
                    label: Text('label_download_current_area'.tr),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showManagementDialog(service),
                  icon: const Icon(Icons.settings, size: 16),
                  label: Text('label_manage'.tr),
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
    showTrSnackbar('snackbar_download_started', 
      backgroundColor: Colors.green,
      colorText: Colors.white,        duration: const Duration(seconds: 2),);
  }

  /// Show management dialog
  void _showManagementDialog(BackgroundTileDownloadService service) {
    Get.dialog(
      AlertDialog(
        title: Text('title_text_manage_offline_maps'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('text_options'.tr),
            const SizedBox(height: 8),

            ListTile(
              leading: const Icon(Icons.settings),
              title: Text('title_text_download_settings_2'.tr),
              subtitle: Text('title_text_configure_automatic_downloads'.tr),
              onTap: () {
                Get.back();
                _showDownloadSettings(service);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('text_cancel_5'.tr)),
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
