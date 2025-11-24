import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';

/// Simple indicator widget to show when geocoding is active
class GeocodingIndicatorWidget extends StatelessWidget {
  const GeocodingIndicatorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = GeocodingIsolateService.instance;

    return Obx(() {
      if (service.activeRequests.value == 0) return const SizedBox.shrink();

      return Positioned(
        top: 100,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Geocoding (${service.activeRequests.value})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Status badge for service health
class GeocodingStatusBadge extends StatelessWidget {
  const GeocodingStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final service = GeocodingIsolateService.instance;

    return Obx(
      () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: service.isInitialized.value ? Colors.green : Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              service.isInitialized.value ? Icons.check_circle : Icons.error,
              color: Colors.white,
              size: 12,
            ),
            const SizedBox(width: 4),
            Text(
              service.isInitialized.value ? 'Ready' : 'Error',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating info button for geocoding service
class GeocodingInfoButton extends StatelessWidget {
  const GeocodingInfoButton({super.key});

  @override
  Widget build(BuildContext context) {
    final service = GeocodingIsolateService.instance;

    return Positioned(
      top: 140,
      right: 16,
      child: GestureDetector(
        onTap: () => _showServiceInfo(service),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.info_outline, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  void _showServiceInfo(GeocodingIsolateService service) {
    final status = service.getStatus();

    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue),
            SizedBox(width: 8),
            Text('Geocoding Service'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              'Status',
              service.isInitialized.value ? 'Ready' : 'Not Ready',
            ),
            _buildInfoRow('Active Requests', '${service.activeRequests.value}'),
            _buildInfoRow('Has Isolate', status['hasIsolate'] ? 'Yes' : 'No'),
            _buildInfoRow('Has SendPort', status['hasSendPort'] ? 'Yes' : 'No'),
            const SizedBox(height: 16),
            const Text(
              'This service handles reverse geocoding in background isolates to prevent UI blocking.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('OK')),
          if (!service.isInitialized.value)
            TextButton(
              onPressed: () async {
                Get.back();
                await service.ensureInitialized();
                Get.snackbar(
                  'Service',
                  service.isInitialized.value
                      ? 'Initialized successfully'
                      : 'Failed to initialize',
                  backgroundColor:
                      service.isInitialized.value ? Colors.green : Colors.red,
                  colorText: Colors.white,        duration: const Duration(seconds: 2),

                );
              },
              child: const Text('Retry Init'),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

/// Combined geocoding status widget for easy integration
class GeocodingStatusOverlay extends StatelessWidget {
  const GeocodingStatusOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [GeocodingIndicatorWidget(), GeocodingInfoButton()],
    );
  }
}
