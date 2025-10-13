import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/memories/views/memory_view.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import '../../controllers/map_controller_new.dart';

import '../../../../config/app_colors.dart';

class MapFab extends StatelessWidget {
  const MapFab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Obx(() {
      final Color baseColor =
          controller.darkMode.value
              ? (controller.mainColor.value == 'blue'
                  ? const Color(0xFF001937)
                  : (controller.iconColor ?? AppColors.blue))
              : controller.currentMainColor ?? AppColors.blue;

      return Positioned(
        bottom: 20,
        left: MediaQuery.of(context).size.width / 2 - 28,
        child: GestureDetector(
          onTap: () async {
            // Properly initialize MemoryController
            Get.put(MemoryController());

            // Ensure controller is properly initialized
            await Future.delayed(
              const Duration(milliseconds: 50),
            ); // Small delay to ensure initialization

            // Navigate to MemoryView and check result
            final result = await Get.to(() => MemoryView());

            // If memory was saved successfully, refresh the map
            if (result == true) {
              try {
                final mapController = Get.find<MapControllerNew>();
                await mapController.refreshLocation();();
                debugPrint('Map refreshed after memory creation');
              } catch (e) {
                debugPrint('MapControllerNew not found: $e');
              }
            }

            // Refresh AddMemoriesController if it exists (similar to other FAB implementations)
            try {
              final addMemoriesController = Get.find<AddMemoriesController>();
              addMemoriesController.onAgainInit();
              debugPrint(
                'AddMemoriesController refreshed after memory creation from map',
              );
            } catch (e) {
              debugPrint('AddMemoriesController not found: $e');
            }
          },
          child: SizedBox(
            width: 49,
            height: 51,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Unified ColorFiltered usage
                ColorFiltered(
                  colorFilter: ColorFilter.mode(baseColor, BlendMode.srcIn),
                  child: Image.asset(
                    AppImages.rectangle,
                    width: 49,
                    height: 51,
                    fit: BoxFit.contain,
                  ),
                ),

                // Foreground icon stays same
                Image.asset(
                  AppImages.addIcon,
                  width: 30,
                  height: 30,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
