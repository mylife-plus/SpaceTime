import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_cli/common/utils/json_serialize/json_ast/utils/grapheme_splitter.dart';
import 'package:spacetime/app/config/app_colors.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/add_memories/views/add_memories.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/modules/globe_test/views/globe_test_view.dart';
import 'package:spacetime/app/modules/globe_test/controllers/globe_test_controller.dart';

import '../../../settings/views/settings_view.dart';
import '../../controllers/map_controller_new.dart';
import 'map_circle_button.dart';
import '../../../filter/controllers/filter_controller.dart';
import '../../../add_memories/views/mini_widgets/search_badge.dart';

class MapTopButtons extends StatelessWidget {
  const MapTopButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final controller2 = Get.find<UiController>();

    final controller = Get.find<MapControllerNew>();

    // Get AddMemoriesController if registered to show filter badge
    final addMemoriesController =
        Get.isRegistered<AddMemoriesController>()
            ? Get.find<AddMemoriesController>()
            : null;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        // color:
        //     controller2.darkMode.value
        //         ? controller2.mainColor.value == 'blue'
        //             ? Color(0xFF001937)
        //             : controller2.primaryColorDark
        //         : controller2.currentMainColor,
        height: 65,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),

        child: Obx(
          () => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      Get.to(() => SettingsView());
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Container(
                        child: Container(
                          padding: const EdgeInsets.all(3.5),
                          // width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color:
                                controller2.darkMode.value
                                    ? (controller2.mainColor.value == 'blue'
                                        ? const Color(0xFF002B62)
                                        : (controller2
                                                .curentHomeIconColorDark ??
                                            AppColors.blue))
                                    : controller2
                                        .currentHomeIconColor, // ✔ correct
                          ),

                          child: Image.asset(
                            AppImages.settings3,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),

                  GestureDetector(
                    onTap: controller.openFilter,
                    child: Stack(
                      children: [
                        Container(
                          child: Container(
                            padding: const EdgeInsets.all(8),

                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color:
                                  controller2.darkMode.value
                                      ? (controller2.mainColor.value == 'blue'
                                          ? const Color(0xFF002B62)
                                          : (controller2
                                                  .curentHomeIconColorDark ??
                                              AppColors.blue))
                                      : controller2
                                          .currentHomeIconColor, // ✔ correct
                            ),
                            child: Image.asset(
                              AppImages.filter,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        // Filter badge indicator with count
                        Obx(() {
                          final filterController = Get.find<FilterController>();
                          final filterCount =
                              addMemoriesController?.activeFilterCount ?? 0;
                          final hasSearch = filterController.hasActiveSearch;

                          // Show filter badge only if there are filters and no active search
                          return (filterCount > 0 && !hasSearch)
                              ? Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            controller2.darkMode.value
                                                ? Colors.black
                                                : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    child: Center(
                                      child: Text(
                                        filterCount > 9
                                            ? '9+'
                                            : filterCount.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          height: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              : const SizedBox.shrink();
                        }),

                        // Search badge - shows when there's an active search
                        const SearchBadge(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),

                  GestureDetector(
                    onTap: () async {
                      
                      final addMemoriesController =
                          Get.find<AddMemoriesController>();
                      
                      addMemoriesController.onAgainInit();
                      addMemoriesController.searchQuery.value = '';
                      addMemoriesController.isSearchActive.value = true;
                      addMemoriesController.isOpenedFromMap = true;

                      //
                      var result = await Get.to(() => AddMemoriesView());
                      addMemoriesController.isOpenedFromMap = false;

                      print('Getting back from Add Memories Search');

                        // addMemoriesController.isOpenedFromMap = false;
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      // width: 42,
                      height: 44,
                      decoration: BoxDecoration(
                        // image: DecorationImage(
                        borderRadius: BorderRadius.circular(8),
                        color:
                            controller2.darkMode.value
                                ? (controller2.mainColor.value == 'blue'
                                    ? const Color(0xFF002B62)
                                    : (controller2.curentHomeIconColorDark ??
                                        AppColors.blue))
                                : controller2.currentHomeIconColor,
                      ),

                      child: Image.asset(
                        AppImages.search,
                        fit: BoxFit.contain,
                        // color: Colors.white,
                        // width: 31,
                        // height: 31,
                      ),
                    ),
                  ),

                  const SizedBox(width: 5),

                  // Globe Test Button
           
                ],
              ),

              GestureDetector(
                onTap: () async {
                  var result = await Get.to(() => AddMemoriesView());

                  if (result == true) {
                      // final mapController = Get.find<MapControllerNew>();
        // await mapController.loadMemoriesFromDB(mapController.currentMemories);
        // mapController.showLoadedDataOnMap();
// mapController.setOptimalZoomForMemories();
                    // controller.refreshLocation();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  // width: 42,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color:
                        controller2.darkMode.value
                            ? (controller2.mainColor.value == 'blue'
                                ? const Color(0xFF002B62)
                                : (controller2.curentHomeIconColorDark ??
                                    AppColors.blue))
                            : controller2.currentHomeIconColor, // ✔ correct
                  ),

                  child: Image.asset(AppImages.memory, fit: BoxFit.contain),
                ),
              ),

            ],
          ),
        ),
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
