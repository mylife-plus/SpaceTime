import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/custom_dialogue_box.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/utils/memory_media_image_cache.dart';

class MemoryImageWidget extends StatelessWidget {
  final String? imagePath;
  final VoidCallback? onImageTap;

  const MemoryImageWidget({super.key, this.imagePath, this.onImageTap});

  Widget _buildImageWidget(BuildContext context, String imagePath) {
    return MemoryMediaImageProviderCache.instance.buildImage(
      context: context,
      imageData: imagePath,
      fit: BoxFit.cover,
      width: 120,
      height: 170,
      errorChild: Container(
        color: Colors.grey[300],
        child: const Icon(Icons.error, color: Colors.red),
      ),
    );
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
                  child: _buildImageWidget(context, imagePath!),
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
