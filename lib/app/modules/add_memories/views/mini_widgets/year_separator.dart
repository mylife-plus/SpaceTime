import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/routes/memory_view_navigation.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class YearSeparator extends StatelessWidget {
  final String title;
  const YearSeparator({required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Obx(
      () => GestureDetector(
        onLongPress: () {
          openMemoryView(
            binding: BindingsBuilder(() {
              Get.put(MemoryController());
            }),
          );
        },
        child: Container(
          height: 36,
          width: MediaQuery.of(context).size.width,
          color:
              controller.darkMode.value
                  ? controller.mainColor.value == 'blue'
                      ? Color(0xFF00234F)
                      : controller.secondaryColor
                  : controller.primaryColor ?? const Color(0xFF92C3FF),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color:
                  controller.darkMode.value
                      ? Colors.white
                      : const Color(0xFF4D4D4D),
            ),
          ),
        ),
      ),
    );
  }
}
