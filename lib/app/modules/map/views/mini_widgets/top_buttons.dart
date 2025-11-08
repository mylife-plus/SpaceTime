import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/add_memories/views/add_memories.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/bottom_info.dart';

import '../../../../routes/app_pages.dart';
import '../../../settings/views/settings_view.dart';
import '../../controllers/map_controller_new.dart';
import 'map_circle_button.dart';

class MapTopButtons extends StatelessWidget {
  const MapTopButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MapControllerNew>();

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
              MapCircleButton(
                overlayImagePath: AppImages.filter,

                onTap: controller.openFilter,
              ),
              const SizedBox(width: 5),
            ],
          ),
          MapCircleButton(

            overlayImagePath: AppImages.memory,

            onTap: () async {

              await controller.clearAllLines();
              controller.refreshMapView();

              // Don't clear filters when navigating to AddMemoriesView
              // Filters should persist until manually removed or reset

              var result = await Get.to(() => AddMemoriesView());

              if (result == true) {
                controller.refreshLocation();
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
