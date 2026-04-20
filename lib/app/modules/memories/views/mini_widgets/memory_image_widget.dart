import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/custom_dialogue_box.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

class MemoryImageWidget extends StatelessWidget {
  final String? imagePath;
  final VoidCallback? onImageTap;

  const MemoryImageWidget({super.key, this.imagePath, this.onImageTap});

  // Build image widget that handles both file paths and base64 data
  Widget _buildImageWidget(String imagePath) {
    // Check if it's a file path (starts with / or contains file extension)
    if (imagePath.startsWith('/') || imagePath.contains('.')) {
      // It's a file path
      if (File(imagePath).existsSync()) {
        return Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Icon(Icons.error, color: Colors.red),
            );
          },
        );
      } else {
        // File doesn't exist, might be an asset
        return Image.asset(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Icon(Icons.error, color: Colors.red),
            );
          },
        );
      }
    } else {
      // Assume it's base64 data
      try {
        final bytes = base64Decode(imagePath);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Icon(Icons.error, color: Colors.red),
            );
          },
        );
      } catch (e) {
        return Container(
          color: Colors.grey[300],
          child: const Icon(Icons.error, color: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return SizedBox(
      width: 120,
      height: 170,

      child:
          imagePath != null
              ? ClipRRect(
                // borderRadius: BorderRadius.circular(12)
                child: GestureDetector(
                  onLongPress: () {
                    showDeleteConfirmationDialog(
                      title: 'title_literal_delete_image'.tr,
                      message: 'dialog_content_delete_this_image'.tr,
                      onConfirm: () {
                        showTrSnackbar('snackbar_deleted', 
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: Colors.red.shade400,
                          colorText: Colors.white,
                          margin: const EdgeInsets.all(12),        duration: const Duration(seconds: 2),);
                      },
                    );
                  },
                  child: _buildImageWidget(imagePath!),
                ),
              )
              : Obx(
                () => Container(
                  decoration: BoxDecoration(
                    color:
                        controller.darkMode.value
                            ? Colors.white
                            : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey[300]!,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onImageTap,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 32,
                              // color: Colors.grey[600],
                              color:
                                  controller.darkMode.value
                                      ? Colors.white
                                      : Colors.grey[600],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'text_add_photo'.tr,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    controller.darkMode.value
                                        ? Colors.white
                                        : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
    );
  }
}
