// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:get/get_core/src/get_main.dart';
// import 'package:spacetime/app/modules/settings/views/settings_view.dart';
//
// import '../../../../config/app_images.dart';
// import '../../../map/views/map_view.dart';
// import '../../../ui/controllers/ui_controller.dart';
// import '../../controllers/add_memories_controller.dart';
//
// class Header extends StatelessWidget {
//   const Header({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     final controller2 = Get.find<UiController>();
//     final controller = Get.find<AddMemoriesController>();
//     return Obx(
//       () => Container(
//         color: controller2.currentMainColor,
//         height: 60,
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//         child: Row(
//           children: [
//             GestureDetector(
//               onTap: () {
//                 Get.to(() => SettingsView());
//               },
//               child: Container(
//                 padding: EdgeInsets.all(2),
//                 width: 28,
//                 height: 28,
//                 decoration: BoxDecoration(
//                   image: DecorationImage(
//                     image: AssetImage(AppImages.rectangle),
//                     fit: BoxFit.cover,
//                   ),
//                 ),
//                 child: Image.asset(AppImages.settings2, fit: BoxFit.contain),
//               ),
//             ),
//             SizedBox(width: 5),
//
//             GestureDetector(
//               onTap: controller.openFilter,
//               child: Container(
//                 padding: EdgeInsets.all(6),
//                 width: 44,
//                 height: 44,
//                 decoration: BoxDecoration(
//                   image: DecorationImage(
//                     image: AssetImage(AppImages.rectangle),
//                     fit: BoxFit.cover,
//                   ),
//                 ),
//                 child: Image.asset(AppImages.filter, fit: BoxFit.contain),
//               ),
//             ),
//             SizedBox(width: 5),
//
//             GestureDetector(
//               onTap: controller.openSearch,
//               child: SizedBox(
//                 width: 44,
//                 height: 44,
//                 child: Image.asset(AppImages.search, fit: BoxFit.cover),
//               ),
//             ),
//
//             Spacer(),
//             GestureDetector(
//               onTap: () {
//                 Get.to(() => MapView());
//               },
//               child: Container(
//                 padding: EdgeInsets.all(6),
//                 width: 44,
//                 height: 44,
//                 decoration: BoxDecoration(
//                   image: DecorationImage(
//                     image: AssetImage(AppImages.rectangle),
//                     fit: BoxFit.cover,
//                   ),
//                 ),
//                 child: Image.asset(AppImages.earth, fit: BoxFit.contain),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_colors.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller.dart';
import 'package:spacetime/app/modules/settings/views/settings_view.dart';

import '../../../../config/app_images.dart';
import '../../../map/controllers/map_controller.dart';

import '../../../ui/controllers/ui_controller.dart';
import '../../controllers/add_memories_controller.dart';

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
    final controller2 = Get.find<UiController>();
    final controller = Get.find<AddMemoriesController>();

    return Obx(
      () => Container(
        // color: controller2.currentMainColor,
        color:
            controller2.darkMode.value
                ? controller2.mainColor.value == 'blue'
                    ? Color(0xFF001937)
                    : controller2.primaryColorDark
                : controller2.currentMainColor,
        height: 65,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),

        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,

          children: [
            GestureDetector(
              onTap: () {
                Get.to(() => SettingsView());
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  // width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    // border: BorderRadius.circular(0),
                    image: DecorationImage(
                      image: AssetImage(AppImages.rectangle),
                      fit: BoxFit.contain,
                      colorFilter:
                          controller2.darkMode.value
                              ? controller2.mainColor.value == 'blue'
                                  ? const ColorFilter.mode(
                                    Color(0xFF002B62),
                                    BlendMode.srcIn,
                                  )
                                  : ColorFilter.mode(
                                    (controller2.primaryColorDark ??
                                        AppColors.blue),
                                    BlendMode.srcIn,
                                  )
                              : (controller2.rectangleColorFilter ??
                                  const ColorFilter.mode(
                                    AppColors.blue,
                                    BlendMode.srcIn,
                                  )),
                    ),
                  ),

                  child: Image.asset(AppImages.settings3, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(width: 5),

            GestureDetector(
              onTap: controller.openFilter,
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    height: 44,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(AppImages.rectangle),
                        fit: BoxFit.contain,
                        colorFilter:
                            controller2.darkMode.value
                                ? controller2.mainColor.value == 'blue'
                                    ? const ColorFilter.mode(
                                      Color(0xFF002B62),
                                      BlendMode.srcIn,
                                    )
                                    : ColorFilter.mode(
                                      (controller2.primaryColorDark ??
                                          AppColors.blue),
                                      BlendMode.srcIn,
                                    )
                                : (controller2.rectangleColorFilter ??
                                    const ColorFilter.mode(
                                      AppColors.blue,
                                      BlendMode.srcIn,
                                    )),
                      ),
                    ),
                    child: Image.asset(AppImages.filter, fit: BoxFit.contain),
                  ),

                  // Filter badge indicator with count
                  Obx(() {
                    final filterCount = controller.activeFilterCount;
                    return filterCount > 0
                        ? Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: controller2.darkMode.value ? Colors.black : Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Center(
                                child: Text(
                                  filterCount > 9 ? '9+' : filterCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink();
                  }),
                ],
              ),
            ),
            const SizedBox(width: 5),
            // search filed
            GestureDetector(
              onTap: () {
                controller.searchQuery.value = '';
                controller.isSearchActive.value = true;
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                // width: 42,
                height: 44,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(AppImages.rectangle),
                    fit: BoxFit.contain,
                    colorFilter:
                        controller2.darkMode.value
                            ? controller2.mainColor.value == 'blue'
                                ? const ColorFilter.mode(
                                  Color(0xFF002B62),
                                  BlendMode.srcIn,
                                )
                                : ColorFilter.mode(
                                  (controller2.primaryColorDark ??
                                      AppColors.blue),
                                  BlendMode.srcIn,
                                )
                            : (controller2.rectangleColorFilter ??
                                const ColorFilter.mode(
                                  AppColors.blue,
                                  BlendMode.srcIn,
                                )),
                  ),
                ),

                child: Image.asset(
                  AppImages.searchNormal,
                  fit: BoxFit.contain,
                  color: Colors.white,
                  // width: 31,
                  // height: 31,
                ),
              ),
            ),

            const Spacer(),

            GestureDetector(
              onTap: () async {
                try {
                  final mapController = Get.find<MapController>();

                  await mapController.resetToOriginalLocations();

                 Navigator.of(context).pop(true); 

                  debugPrint(
                    '🌍 HEADER - Earth tapped: Reset to original locations completed',
                  );
                } catch (e) {
                  debugPrint('Error navigating to map: $e');

                 Navigator.of(context).pop(true); 
                }
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                // width: 42,
                height: 44,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(AppImages.rectangle),
                    fit: BoxFit.contain,
                    colorFilter:
                        controller2.darkMode.value
                            ? controller2.mainColor.value == 'blue'
                                ? const ColorFilter.mode(
                                  Color(0xFF002B62),
                                  BlendMode.srcIn,
                                )
                                : ColorFilter.mode(
                                  (controller2.primaryColorDark ??
                                      AppColors.blue),
                                  BlendMode.srcIn,
                                )
                            : (controller2.rectangleColorFilter ??
                                const ColorFilter.mode(
                                  AppColors.blue,
                                  BlendMode.srcIn,
                                )),
                  ),
                ),

                child: Image.asset(AppImages.earth, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
