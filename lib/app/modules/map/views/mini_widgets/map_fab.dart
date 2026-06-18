import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/routes/memory_view_navigation.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import '../../controllers/map_controller_new.dart';

class MapFab extends StatelessWidget {
  const MapFab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Obx(() {
      return Positioned(
        bottom: 20,
        left: MediaQuery.of(context).size.width / 2 - 28,
        child: GestureDetector(
          onTap: () async {
            Get.put(MemoryController());
            final result = await openMemoryView();

            if (result == true) {
              try {
                final addMemoriesController = Get.find<AddMemoriesController>();
                addMemoriesController.onAgainInit();

                final mapController = Get.find<MapControllerNew>();
                await mapController.refreshLocation();

                debugPrint('Map refreshed after memory creation');
              } catch (e) {
                debugPrint('MapControllerNew not found: $e');
              }
            }
          },
          child: Container(
            width: 49,
            height: 51,
            padding: EdgeInsets.all(7),
            decoration: BoxDecoration(
              // image: DecorationImage(
              borderRadius: BorderRadius.circular(8),
              color:
                  controller.darkMode.value
                      ? (controller.mainColor.value == 'blue'
                          ? const Color(0xFF002B62)
                          : (controller.curentHomeIconColorDark))
                      : controller.currentHomeIconColor, // ✔ correct
            ),
            child: Image.asset(AppImages.addIcon, fit: BoxFit.contain),
          ),
        ),
      );
    });
  }
}
