import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/add_memories/views/add_memories.dart';

import '../../../settings/views/settings_view.dart';
import '../../controllers/map_controller_new.dart';
import 'map_circle_button.dart';

class MapTopButtons extends StatelessWidget {
  const MapTopButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MapControllerNew>();

    // Get AddMemoriesController if registered to show filter badge
    final addMemoriesController = Get.isRegistered<AddMemoriesController>()
        ? Get.find<AddMemoriesController>()
        : null;

    return Positioned(
      top: 10,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              MapCircleButton(
                // icon: Icons.settings,
                overlayImagePath: AppImages.settings3,
                // backgroundImg: false,
                size: 35,
                onTap: () {
                  Get.to(() => SettingsView());
                },
              ),
              const SizedBox(width: 5),
              Obx(() => MapCircleButton(
                overlayImagePath: AppImages.filter,
                badgeCount: addMemoriesController?.activeFilterCount ?? 0,
                onTap: controller.openFilter,
              )),
              const SizedBox(width: 5),
            ],
          ),
          MapCircleButton(

            overlayImagePath: AppImages.memory,

            onTap: () async {

              // await controller.clearAllLines();
              // controller.refreshMapView();

              // Don't clear filters when navigating to AddMemoriesView
              // Filters should persist until manually removed or reset

              var result = await Get.to(() => AddMemoriesView());

              if (result == true) {
                // controller.refreshLocation();
              }
            },
          ),
        ],
      ),
    );
  }

  // void _showBottomPanel(BuildContext context) {
  //   showModalBottomSheet(
  //     context: context,
  //     backgroundColor: Colors.transparent,
  //     isScrollControlled: true,
  //     builder: (_) => const BottomPanel(),
  //   );
  // }
}
