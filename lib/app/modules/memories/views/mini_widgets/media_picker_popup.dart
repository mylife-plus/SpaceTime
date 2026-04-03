import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
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
        final dividerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300;

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
              Divider(height: 1, color: dividerColor),
              _buildOption(
                context,
                icon: Icons.camera_alt,
                label: 'Camera (Photo)',
                onTap: () => _handleCameraPhoto(context),
                isDark: isDark,
                textColor: textColor,
              ),
              Divider(height: 1, color: dividerColor),
              _buildOption(
                context,
                icon: Icons.videocam,
                label: 'Camera (Video)',
                onTap: () => _handleCameraVideo(context),
                isDark: isDark,
                textColor: textColor,
              ),
              Divider(height: 1, color: dividerColor),
              _buildOption(
                context,
                icon: Icons.photo_library,
                label: 'Gallery',
                onTap: () => _handleGallery(context),
                isDark: isDark,
                textColor: textColor,
              ),
              Divider(height: 1, color: dividerColor),
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.kumbhSans(
                      fontSize: 16,
                      color: isDark ? Colors.grey.shade400 : Colors.grey,
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
    required Color textColor,
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
              color: textColor,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: GoogleFonts.kumbhSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _popDialogIfOpen(BuildContext context) {
    if (!context.mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<bool> _ensureCameraAndMicForVideo() async {
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    return cam.isGranted && mic.isGranted;
  }

  Future<bool> _ensurePhotosPermission() async {
    if (Platform.isIOS) {
      final p = await Permission.photos.request();
      return p.isGranted || p.isLimited;
    }
    if (Platform.isAndroid) {
      final photos = await Permission.photos.request();
      if (photos.isGranted) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
    return true;
  }

  Future<void> _handleCameraPhoto(BuildContext context) async {
    if (!await _ensureCameraPermission()) {
      Get.snackbar(
        'Permissions Required',
        'Camera permission is required to take photos',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
      );
      return;
    }

    final imagePicker = ImagePicker();
    final photoFile = await imagePicker.pickImage(source: ImageSource.camera);

    _popDialogIfOpen(context);

    if (photoFile != null) {
      onMediaSelected([photoFile.path], []);
    }
  }

  Future<void> _handleCameraVideo(BuildContext context) async {
    if (!await _ensureCameraAndMicForVideo()) {
      Get.snackbar(
        'Permissions Required',
        'Camera and microphone are required to record video',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
      );
      return;
    }

    final imagePicker = ImagePicker();
    final videoFile = await imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 10),
    );

    _popDialogIfOpen(context);

    if (videoFile != null) {
      onMediaSelected([], [videoFile.path]);
    }
  }

  Future<void> _handleGallery(BuildContext context) async {
    if (!await _ensurePhotosPermission()) {
      Get.snackbar(
        'Photo Library Permission',
        'Photo library permission is required to select images and videos',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
      );
      return;
    }

    final List<String> imagePaths = [];
    final List<String> videoPaths = [];

    if (Platform.isIOS) {
      // iOS: use ImagePicker so limited photo access is respected.
      final imagePicker = ImagePicker();
      final selected = await imagePicker.pickMultipleMedia();
      for (final media in selected) {
        final path = media.path;
        final ext = path.split('.').last.toLowerCase();
        if (['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv', 'm4v', '3gp'].contains(ext)) {
          videoPaths.add(path);
        } else {
          imagePaths.add(path);
        }
      }
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
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
      }
    }

    _popDialogIfOpen(context);

    if (imagePaths.isNotEmpty || videoPaths.isNotEmpty) {
      onMediaSelected(imagePaths, videoPaths);
    }
  }

}

