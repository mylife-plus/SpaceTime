import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

void showDeleteConfirmationDialog({
  required String title,
  required String message,
  required VoidCallback onConfirm,
}) {
  final uiController = Get.find<UiController>();
  final isDark = uiController.darkMode.value;

  Get.defaultDialog(
    titlePadding: const EdgeInsets.only(top: 20, left: 20, right: 20),
    contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
    title: title,
    titleStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white : Colors.black,
    ),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        Text(
          message,
          style: TextStyle(
            fontSize: 16,
            height: 1.5,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 25),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Get.back(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark ? Colors.white60 : Colors.grey,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'text_no_2'.tr,
                  style: TextStyle(color: uiController.currentMainColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Get.back();
                  onConfirm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('text_yes_2'.tr),
              ),
            ),
          ],
        ),
      ],
    ),
    backgroundColor: isDark ? Colors.grey[900] : Colors.white,
    radius: 12,
  );
}
