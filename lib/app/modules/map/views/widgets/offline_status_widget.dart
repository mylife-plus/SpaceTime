import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/map_controller.dart';

/// Widget to display offline mode status for maps
class OfflineStatusWidget extends StatelessWidget {
  const OfflineStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mapController = Get.find<MapController>();

    return Obx(() {
      if (!mapController.isOfflineMode.value) {
        return const SizedBox.shrink();
      }

      return Container(
        margin: const EdgeInsets.all(8.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4.0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.offline_bolt, color: Colors.white, size: 16.0),
            const SizedBox(width: 6.0),
            const Text(
              'Offline Mode',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Detailed offline status widget with more information
class DetailedOfflineStatusWidget extends StatelessWidget {
  const DetailedOfflineStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mapController = Get.find<MapController>();

    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8.0),
                const Text(
                  'Map Status',
                  style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            Obx(
              () => _buildStatusRow(
                'Offline Mode',
                mapController.isOfflineMode.value,
                mapController.isOfflineMode.value ? Colors.blue : Colors.grey,
              ),
            ),
            const SizedBox(height: 8.0),
            FutureBuilder<Map<String, dynamic>>(
              future: mapController.getOfflineStatus(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                final status = snapshot.data ?? {};
                return Column(
                  children: [
                    _buildStatusRow(
                      'Offline Components',
                      status['hasOfflineComponents'] ?? false,
                      (status['hasOfflineComponents'] ?? false)
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(height: 8.0),
                    _buildStatusRow(
                      'Downloaded Tiles',
                      status['hasDownloadedTiles'] ?? false,
                      (status['hasDownloadedTiles'] ?? false)
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(height: 8.0),
                    _buildInfoRow(
                      'Tiles Downloaded',
                      '${status['totalTilesDownloaded'] ?? 0}',
                    ),
                    const SizedBox(height: 8.0),
                    _buildInfoRow(
                      'Storage Usage',
                      '${status['usagePercentage'] ?? 0}%',
                    ),
                    const SizedBox(height: 8.0),
                    _buildStatusRow(
                      'Force Offline',
                      status['forceOfflineMode'] ?? false,
                      (status['forceOfflineMode'] ?? false)
                          ? Colors.orange
                          : Colors.grey,
                    ),
                    const SizedBox(height: 8.0),
                    _buildStatusRow(
                      'Currently Downloading',
                      status['isCurrentlyDownloading'] ?? false,
                      (status['isCurrentlyDownloading'] ?? false)
                          ? Colors.blue
                          : Colors.grey,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => mapController.updateOfflineStatus(),
                  icon: const Icon(Icons.refresh, size: 16.0),
                  label: const Text('Refresh Status'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8.0),
                TextButton.icon(
                  onPressed: () => _showDetailedInfo(context, mapController),
                  icon: const Icon(Icons.info, size: 16.0),
                  label: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool status, Color color) {
    return Row(
      children: [
        Icon(
          status ? Icons.check_circle : Icons.cancel,
          color: color,
          size: 16.0,
        ),
        const SizedBox(width: 8.0),
        Text(label),
        const Spacer(),
        Text(
          status ? 'Active' : 'Inactive',
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        const Icon(Icons.info, color: Colors.grey, size: 16.0),
        const SizedBox(width: 8.0),
        Text(label),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showDetailedInfo(BuildContext context, MapController mapController) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Offline Status Details'),
            content: FutureBuilder<Map<String, dynamic>>(
              future: mapController.getOfflineStatus(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                final status = snapshot.data ?? {};
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children:
                        status.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 120,
                                  child: Text(
                                    '${entry.key}:',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(child: Text('${entry.value}')),
                              ],
                            ),
                          );
                        }).toList(),
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}

/// Simple offline indicator for the map view
class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mapController = Get.find<MapController>();

    return Positioned(
      top: 100,
      right: 16,
      child: Obx(() {
        if (!mapController.isOfflineMode.value) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.offline_bolt, color: Colors.white, size: 14.0),
              SizedBox(width: 4.0),
              Text(
                'OFFLINE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
