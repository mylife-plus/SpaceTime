import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/services/memory_processing_isolate_service.dart';

/// Widget to display memory processing progress from isolate
class MemoryProcessingProgressWidget extends StatelessWidget {
  const MemoryProcessingProgressWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = MemoryProcessingIsolateService.instance;

    return Obx(() {
      if (!service.isProcessingMemories.value) return const SizedBox.shrink();

      return _buildProgressIndicator(service);
    });
  }

  /// Build the progress indicator
  Widget _buildProgressIndicator(MemoryProcessingIsolateService service) {
    return Positioned(
      top: 60,
      left: 16,
      right: 16,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Processing Memories',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showProcessingDetails(service),
                  child: const Icon(
                    Icons.info_outline,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Obx(
              () => LinearProgressIndicator(
                value: service.processingProgress.value,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Obx(
                    () => Text(
                      service.processingStatus.value,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Obx(
                  () => Text(
                    '${(service.processingProgress.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Show processing details dialog
  void _showProcessingDetails(MemoryProcessingIsolateService service) {
    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.memory, color: Colors.green),
            SizedBox(width: 8),
            Text('Memory Processing'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(
              () => Text(
                'Progress: ${(service.processingProgress.value * 100).toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(height: 8),
            Obx(() => Text('Status: ${service.processingStatus.value}')),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                'Processed Memories: ${service.processedMemories.length}',
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                'Generated Clusters: ${service.processedClusters.length}',
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text('Generated Arrows: ${service.processedArrows.length}'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Memories are being processed in a background isolate for better performance. This won\'t affect app responsiveness.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('OK')),
        ],
      ),
    );
  }
}

/// Status widget for settings screen
class MemoryProcessingStatusWidget extends StatelessWidget {
  const MemoryProcessingStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = MemoryProcessingIsolateService.instance;
    final status = service.getCurrentStatus();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Memory Processing Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (status.isProcessing) ...[
              LinearProgressIndicator(
                value: status.progress,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              const SizedBox(height: 8),
              Text(
                '${(status.progress * 100).toStringAsFixed(1)}% - ${status.status}',
              ),
            ] else ...[
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text('Processing Complete'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text('Memories: ${status.memoriesCount}'),
            Text('Clusters: ${status.clustersCount}'),
            Text('Arrows: ${status.arrowsCount}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        status.isProcessing
                            ? null
                            : () => _reprocessMemories(service),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reprocess Memories'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showProcessingDetails(service),
                  icon: const Icon(Icons.info, size: 16),
                  label: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Reprocess memories
  void _reprocessMemories(MemoryProcessingIsolateService service) {
    service.loadAndProcessMemories(
      onCompleted: (memories, clusters, arrows) {
        Get.snackbar(
          'Processing Complete',
          'Processed ${memories.length} memories into ${clusters.length} clusters',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      },
    );
  }

  /// Show processing details
  void _showProcessingDetails(MemoryProcessingIsolateService service) {
    const MemoryProcessingProgressWidget()._showProcessingDetails(service);
  }
}
