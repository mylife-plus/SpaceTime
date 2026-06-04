import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/shared/widgets/permission_open_settings_dialog.dart';

class MediaPickerPopup extends StatelessWidget {
  final Future<void> Function(
    List<String> imagePaths,
    List<String> videoPaths,
  ) onMediaSelected;
  /// MemoryView (or parent) context — valid after this dialog is popped.
  final BuildContext? hostContext;
  /// After the select-media dialog is closed, before the native picker opens.
  final VoidCallback? onNativePickerWillOpen;
  /// Native picker closed with no files (cancel or empty selection).
  final VoidCallback? onNativePickerCancelled;

  const MediaPickerPopup({
    super.key,
    required this.onMediaSelected,
    this.hostContext,
    this.onNativePickerWillOpen,
    this.onNativePickerCancelled,
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
                  'text_select_media'.tr,
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
                label: 'label_media_camera_photo'.tr,
                onTap: () => _handleCameraPhoto(context),
                isDark: isDark,
                textColor: textColor,
              ),
              Divider(height: 1, color: dividerColor),
              _buildOption(
                context,
                icon: Icons.videocam,
                label: 'label_media_camera_video'.tr,
                onTap: () => _handleCameraVideo(context),
                isDark: isDark,
                textColor: textColor,
              ),
              Divider(height: 1, color: dividerColor),
              _buildOption(
                context,
                icon: Icons.photo_library,
                label: 'label_media_gallery'.tr,
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
                    'text_cancel_7'.tr,
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

  BuildContext get _overlayContext =>
      hostContext ?? Get.overlayContext ?? Get.context!;

  /// Close select-media first so the staging loader is not stacked on this dialog.
  Future<void> _closeSelectMediaPopup(BuildContext dialogContext) async {
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> _openNativePickerWithLoader(
    Future<void> Function() openNativePicker,
  ) async {
    onNativePickerWillOpen?.call();
    await WidgetsBinding.instance.endOfFrame;
    await openNativePicker();
  }

  void _notifyNativePickerCancelled() => onNativePickerCancelled?.call();

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Android only — [FilePicker] needs storage/photos access.
  Future<bool> _ensureAndroidGalleryPermission() async {
    if (!Platform.isAndroid) return true;
    final photos = await Permission.photos.request();
    if (photos.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<void> _handleCameraPhoto(BuildContext dialogContext) async {
    await _closeSelectMediaPopup(dialogContext);

    if (!await _ensureCameraPermission()) {
      await showPermissionOpenSettingsDialog(
        _overlayContext,
        title: 'title_literal_camera_access_needed'.tr,
        message: 'dialog_content_permission_camera_photos'.tr,
      );
      return;
    }

    await _openNativePickerWithLoader(() async {
      final photoFile =
          await ImagePicker().pickImage(source: ImageSource.camera);
      if (photoFile == null) {
        _notifyNativePickerCancelled();
        return;
      }
      await onMediaSelected([_normalizePickerPath(photoFile.path)], []);
    });
  }

  Future<void> _handleCameraVideo(BuildContext dialogContext) async {
    await _closeSelectMediaPopup(dialogContext);

    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      await showPermissionOpenSettingsDialog(
        _overlayContext,
        title: 'title_literal_camera_access_needed_2'.tr,
        message: 'dialog_content_permission_camera_video'.tr,
      );
      return;
    }

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      await showPermissionOpenSettingsDialog(
        _overlayContext,
        title: 'title_literal_microphone_access_needed_2'.tr,
        message: 'dialog_content_permission_microphone_video'.tr,
      );
      return;
    }

    await _openNativePickerWithLoader(() async {
      final videoFile = await ImagePicker().pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 10),
      );
      if (videoFile == null) {
        _notifyNativePickerCancelled();
        return;
      }
      await onMediaSelected([], [_normalizePickerPath(videoFile.path)]);
    });
  }

  static String _normalizePickerPath(String path) {
    if (!path.contains('%')) return path;
    try {
      return Uri.decodeFull(path);
    } catch (_) {
      return path;
    }
  }

  Future<void> _handleGallery(BuildContext dialogContext) async {
    await _closeSelectMediaPopup(dialogContext);

    if (!Platform.isIOS) {
      if (!await _ensureAndroidGalleryPermission()) {
        await showPermissionOpenSettingsDialog(
          _overlayContext,
          title: 'title_literal_photos_access_needed'.tr,
          message: 'dialog_content_permission_storage_gallery'.tr,
        );
        return;
      }
    }

    await _openNativePickerWithLoader(() async {
      final imagePaths = <String>[];
      final videoPaths = <String>[];

      if (Platform.isIOS) {
        final selected = await ImagePicker().pickMultipleMedia();
        for (final media in selected) {
          final path = _normalizePickerPath(media.path);
          final ext = path.split('.').last.toLowerCase();
          if (['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv', 'm4v', '3gp']
              .contains(ext)) {
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
            if (file.path == null) continue;
            final extension = file.extension?.toLowerCase() ?? '';
            if (['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv', 'm4v', '3gp']
                .contains(extension)) {
              videoPaths.add(file.path!);
            } else {
              imagePaths.add(file.path!);
            }
          }
        }
      }

      if (imagePaths.isEmpty && videoPaths.isEmpty) {
        _notifyNativePickerCancelled();
        return;
      }
      await onMediaSelected(imagePaths, videoPaths);
    });
  }

}

