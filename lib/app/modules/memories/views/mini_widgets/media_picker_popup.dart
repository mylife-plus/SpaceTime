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

  Future<bool> _requestCameraPermission() async {
    var status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    return status.isGranted;
  }

  Future<bool> _requestGalleryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return status.isGranted || status.isLimited;
    }
    final photos = await Permission.photos.request();
    final videos = await Permission.videos.request();
    if (photos.isPermanentlyDenied || videos.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    return (photos.isGranted || photos.isLimited) &&
        (videos.isGranted || videos.isLimited);
  }

  Future<void> _handleCameraPhoto(BuildContext context) async {
    final cameraGranted = await _requestCameraPermission();

    PermissionStatus photoLibraryStatus = PermissionStatus.granted;
    if (Platform.isIOS) {
      photoLibraryStatus = await Permission.photosAddOnly.request();
    }

    if (!cameraGranted || !photoLibraryStatus.isGranted) {
      Get.snackbar(
        'Permissions Required',
        'Camera and photo library permissions are required to take and save photos',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
      );
      return;
    }

    if (!context.mounted) return;
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

  Future<void> _handleCameraVideo(BuildContext context) async {
    final cameraGranted = await _requestCameraPermission();
    var micStatus = await Permission.microphone.request();
    if (micStatus.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }

    PermissionStatus photoLibraryStatus = PermissionStatus.granted;
    if (Platform.isIOS) {
      photoLibraryStatus = await Permission.photosAddOnly.request();
    }

    if (!cameraGranted || !micStatus.isGranted || !photoLibraryStatus.isGranted) {
      Get.snackbar(
        'Permissions Required',
        'Camera, microphone, and photo library permissions are required to record and save videos',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.pop(context);

    final imagePicker = ImagePicker();
    final List<String> imagePaths = [];
    final List<String> videoPaths = [];

    final videoFile = await imagePicker.pickVideo(source: ImageSource.camera);
    if (videoFile != null) {
      videoPaths.add(videoFile.path);
    }

    if (imagePaths.isNotEmpty || videoPaths.isNotEmpty) {
      onMediaSelected(imagePaths, videoPaths);
    }
  }

  Future<void> _handleGallery(BuildContext context) async {
    final granted = await _requestGalleryPermission();

    if (!granted) {
      Get.snackbar(
        'Photo Library Permission',
        'Photo library permission is required to select images and videos',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
      );
      return;
    }

    if (!context.mounted) return;
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

