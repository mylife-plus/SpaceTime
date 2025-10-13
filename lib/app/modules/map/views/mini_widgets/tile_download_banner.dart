import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/background_tile_download_service.dart';

class TileDownloadBanner extends StatelessWidget {
  const TileDownloadBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();
    final downloadService = Get.find<BackgroundTileDownloadService>();

    return Obx(() {
      final isDownloading = downloadService.isDownloading.value;
      final totalTiles = downloadService.totalTilesDownloaded.value;
      final currentDownloadProgress = downloadService.downloadProgress.value;
      final currentRegion = downloadService.currentDownloadRegion.value;
      final quotaStatus = downloadService.getCurrentQuotaStatus();

      // Calculate overall progress towards 50,000 tiles (this should never decrease)
      final overallProgress = (totalTiles / 50000).clamp(0.0, 1.0);
      final isComplete = totalTiles >= 50000;

      debugPrint(
        '🎯 TileDownloadBanner - totalTiles: $totalTiles, overallProgress: $overallProgress, currentDownloadProgress: $currentDownloadProgress',
      );

      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getBannerColor(
                isDownloading,
                quotaStatus,
                uiController,
                isComplete,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    // Status Icon
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getStatusIcon(isDownloading, quotaStatus, isComplete),
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title and Status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTitle(isDownloading, quotaStatus, isComplete),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isComplete
                                ? 'All tiles downloaded - maps work offline'
                                : (isDownloading
                                    ? 'Progress is saved - continues from where it left off'
                                    : 'Downloads resume automatically when needed'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                          if (isDownloading && currentRegion.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Region: ${_formatRegionName(currentRegion)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Tile Count Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_formatTileCount(totalTiles)} / 50K',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Overall Progress Bar (this should never decrease)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isComplete ? 'Offline Ready' : 'Total Downloaded',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        Text(
                          '${totalTiles.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} tiles',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Progress to 50,000 tiles',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          '${(overallProgress * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: overallProgress, // This should only increase
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isComplete
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.9),
                        ),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),

                // Current Download Progress (separate from overall progress)
                if (isDownloading && currentRegion.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Downloading: ${currentRegion.length > 20 ? '${currentRegion.substring(0, 20)}...' : currentRegion}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(currentDownloadProgress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value:
                              currentDownloadProgress, // This resets for each new region
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white70,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Color _getBannerColor(
    bool isDownloading,
    TileQuotaStatus quotaStatus,
    UiController uiController,
    bool isComplete,
  ) {
    if (isComplete) {
      return Colors.green; // Green when 50K tiles reached
    }

    if (isDownloading) {
      return uiController.currentMainColor; // Theme color when downloading
    }

    return Colors.blue.shade600; // Blue when ready but not complete
  }

  IconData _getStatusIcon(
    bool isDownloading,
    TileQuotaStatus quotaStatus,
    bool isComplete,
  ) {
    if (isComplete) {
      return Icons.offline_pin; // Offline ready icon
    }

    if (isDownloading) {
      return Icons.download; // Download icon
    }

    return Icons.map; // Map icon for ready state
  }

  String _getTitle(
    bool isDownloading,
    TileQuotaStatus quotaStatus,
    bool isComplete,
  ) {
    if (isComplete) {
      return 'Offline Maps Ready';
    }

    if (isDownloading) {
      return 'Downloading Map Tiles';
    }

    return 'Building Offline Maps';
  }

  String _formatRegionName(String regionName) {
    // Clean up region name for display
    if (regionName.startsWith('hotspot_')) {
      return regionName.replaceFirst('hotspot_', 'Area ');
    }
    if (regionName.startsWith('manual_')) {
      return 'Custom Region';
    }
    return regionName;
  }

  String _formatTileCount(int count) {
    if (count < 1000) {
      return '$count';
    } else if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
  }
}
