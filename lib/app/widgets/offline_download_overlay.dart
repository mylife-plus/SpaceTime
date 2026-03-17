import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/widgets/tappable_back_button.dart';
import '../services/offline_map_service.dart';

class OfflineDownloadOverlay extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onStartDownload;

  const OfflineDownloadOverlay({Key? key, this.onClose, this.onStartDownload})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final offlineService = Get.find<OfflineMapService>();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Obx(() {
        if (offlineService.isOfflineReady.value) {
          return _buildOfflineReadyStatus(offlineService);
        } else if (offlineService.isDownloading.value) {
          return _buildDownloadProgress(offlineService);
        } else {
          return _buildDownloadPrompt(offlineService);
        }
      }),
    );
  }

  /// Build the download prompt widget
  Widget _buildDownloadPrompt(OfflineMapService offlineService) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.cloud_download,
                  color: Colors.blue.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Download Offline Maps',
                      style: Get.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Download maps for offline use',
                      style: Get.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              TappableBackButton(
                isClose: true,
                color: Colors.grey.shade600,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onClose,
                  child: const Text('Later'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onStartDownload,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build the download progress widget
  Widget _buildDownloadProgress(OfflineMapService offlineService) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.orange.shade600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Downloading Maps...',
                      style: Get.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Obx(
                      () => Text(
                        offlineService.downloadStatusText.value,
                        style: Get.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.minimize),
                iconSize: 20,
                color: Colors.grey.shade600,
                tooltip: 'Minimize',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Style pack progress
          Obx(
            () => Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Style Pack',
                      style: Get.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${(offlineService.stylePackProgress.value * 100).toStringAsFixed(0)}%',
                      style: Get.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.blue.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: offlineService.stylePackProgress.value,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.blue.shade600,
                  ),
                  minHeight: 6,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Tile region progress
          Obx(
            () => Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Map Tiles',
                      style: Get.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${offlineService.downloadedTileCount.value} tiles',
                      style: Get.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color:
                            offlineService.downloadedTileCount.value >= 40000
                                ? Colors.green.shade600
                                : Colors.orange.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: offlineService.tileRegionProgress.value,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    offlineService.downloadedTileCount.value >= 40000
                        ? Colors.green.shade600
                        : Colors.orange.shade600,
                  ),
                  minHeight: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the offline ready status widget
  Widget _buildOfflineReadyStatus(OfflineMapService offlineService) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.wifi_off, color: Colors.green.shade600, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offline Maps Ready',
                  style: Get.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Obx(
                  () => Text(
                    '${offlineService.downloadedTileCount.value} tiles downloaded',
                    style: Get.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('OK'),
            style: TextButton.styleFrom(foregroundColor: Colors.green.shade600),
          ),
        ],
      ),
    );
  }
}

/// Compact version of the overlay for minimal space usage
class CompactOfflineDownloadOverlay extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const CompactOfflineDownloadOverlay({Key? key, this.onTap, this.onClose})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final offlineService = Get.find<OfflineMapService>();

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Obx(
            () => Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    value:
                        offlineService.isDownloading.value
                            ? offlineService.tileRegionProgress.value
                            : (offlineService.isOfflineReady.value ? 1.0 : 0.0),
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      offlineService.isOfflineReady.value
                          ? Colors.green.shade600
                          : Colors.blue.shade600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    offlineService.isOfflineReady.value
                        ? 'Offline Ready (${offlineService.downloadedTileCount.value} tiles)'
                        : offlineService.isDownloading.value
                        ? 'Downloading... ${offlineService.downloadedTileCount.value} tiles'
                        : 'Tap to download offline maps',
                    style: Get.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (onClose != null)
                  TappableBackButton(
                    isClose: true,
                    color: Colors.grey.shade600,
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
