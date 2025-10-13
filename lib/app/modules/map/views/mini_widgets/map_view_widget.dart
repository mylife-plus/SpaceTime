import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/map_controller.dart';
import 'internet_required_screen.dart';
import 'permission_required_screen.dart';
import '../../../ui/controllers/ui_controller.dart';

class MapViewWidget extends StatelessWidget {
  const MapViewWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MapController>();

    debugPrint('🔄 MapViewWidget build() called');
    debugPrint(
      '🔄 MapViewWidget - currentZoom: ${controller.currentZoom.value}',
    );
    debugPrint(
      '🔄 MapViewWidget - isShowingNewLocations: ${controller.isShowingNewLocations.value}',
    );

    // Make it reactive to the sequential initialization state
    return Obx(() {
      debugPrint(
        '🔄 MapViewWidget Obx - current state: ${controller.currentInitializationState.value}',
      );
      return controller.buildMapWidget(context);
    });
  }
}
