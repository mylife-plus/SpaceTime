import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import '../../controllers/map_controller.dart';
import '../../../../config/app_colors.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

class MapRefreshFab extends StatelessWidget {
  const MapRefreshFab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MapController>();
    final uiController = Get.find<UiController>();

    return Obx(() {
      final Color baseColor =
          uiController.darkMode.value
              ? (uiController.mainColor.value == 'blue'
                  ? const Color(0xFF001937)
                  : (uiController.iconColor ?? AppColors.blue))
              : uiController.currentMainColor ?? AppColors.blue;

      return Positioned(
        bottom: 20,
        right: 20,
        child: GestureDetector(
          onTap:
              controller.isRefreshing.value
                  ? null
                  : () async {
                    try {
                      // Refresh the map view
                      await controller.refreshMapView();

                      // Show success message
                      showTrSnackbar('snackbar_refreshed', 
                        snackPosition: SnackPosition.BOTTOM,
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.green.withValues(alpha: 0.8),
                        colorText: Colors.white,
                        margin: const EdgeInsets.all(16),);
                    } catch (e) {
                      // Show error message
                      showTrSnackbar('snackbar_error_19', args: [e], 
                        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.red.withValues(alpha: 0.8),
                        colorText: Colors.white,
                        margin: const EdgeInsets.all(16),);
                    }
                  },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: baseColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child:
                controller.isRefreshing.value
                    ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : const Icon(Icons.refresh, color: Colors.white, size: 28),
          ),
        ),
      );
    });
  }
}
