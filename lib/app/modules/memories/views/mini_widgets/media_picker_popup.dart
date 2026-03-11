import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class MediaPickerPopup extends StatelessWidget {
  final Function(List<String> imagePaths, List<String> videoPaths) onMediaSelected;

  const MediaPickerPopup({
    super.key,
    required this.onMediaSelected,
  });

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Obx(() {
        final isDark = uiController.darkMode.value;
        final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Media',
                  style: GoogleFonts.kumbhSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              const Divider(height: 1),
              _buildOption(
                context,
                icon: Icons.camera_alt,
                label: 'Camera',
                onTap: () => _handleCamera(context),
                isDark: isDark,
              ),
              _buildOption(
                context,
                icon: Icons.photo_library,
                label: 'Gallery',
                onTap: () => _handleGallery(context),
                isDark: isDark,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.kumbhSans(
                      fontSize: 16,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: GoogleFonts.kumbhSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCamera(BuildContext context) async {
    Navigator.pop(context);
    final imagePicker = ImagePicker();
    final List<String> imagePaths = [];
    final List<String> videoPaths = [];

    final photoFile = await imagePicker.pickImage(source: ImageSource.camera);
    if (photoFile != null) {
      imagePaths.add(photoFile.path);
    }

    if (imagePaths.isNotEmpty || videoPaths.isNotEmpty) {
      onMediaSelected(imagePaths, videoPaths);
    }
  }

  Future<void> _handleGallery(BuildContext context) async {
    Navigator.pop(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final List<String> imagePaths = [];
      final List<String> videoPaths = [];

      for (final file in result.files) {
        if (file.path != null) {
          final extension = file.extension?.toLowerCase() ?? '';
          if (['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv', 'm4v', '3gp'].contains(extension)) {
            videoPaths.add(file.path!);
          } else {
            imagePaths.add(file.path!);
          }
        }
      }

      if (imagePaths.isNotEmpty || videoPaths.isNotEmpty) {
        onMediaSelected(imagePaths, videoPaths);
      }
    }
  }
}

