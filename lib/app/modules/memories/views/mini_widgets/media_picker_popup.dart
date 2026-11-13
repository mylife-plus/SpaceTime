import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_file_metadata_service.dart';
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
    final videos = await Permission.videos.request();
    if (photos.isGranted || videos.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  static bool _looksLikeVideo(String path, {String? mimeType}) {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.startsWith('video/')) return true;
    final ext = path.split('.').last.toLowerCase();
    return const {
      'mp4',
      'mov',
      'avi',
      'mkv',
      'flv',
      'wmv',
      'm4v',
      '3gp',
      'webm',
    }.contains(ext);
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
      final path = _normalizePickerPath(photoFile.path);
      // Persist to the device gallery before handing the path to the memory
      // flow so Photos/Gallery always has a copy (awaited, with failure UI).
      await _saveCaptureToDeviceGallery(path, isVideo: false);
      await onMediaSelected([path], []);
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
      final path = _normalizePickerPath(videoFile.path);
      await _saveCaptureToDeviceGallery(path, isVideo: true);
      await onMediaSelected([], [path]);
    });
  }

  /// Persist a camera capture into the system Photos / Gallery library.
  static Future<void> _saveCaptureToDeviceGallery(
    String path, {
    required bool isVideo,
  }) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          debugPrint('[MediaPicker] gallery save skipped — access denied');
          showTrSnackbar(
            'snackbar_camera_gallery_save_failed',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 3),
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }
      }
      if (isVideo) {
        await Gal.putVideo(path, album: 'SpaceTime');
      } else {
        await Gal.putImage(path, album: 'SpaceTime');
      }
      debugPrint('[MediaPicker] ✅ saved camera capture to gallery');
    } catch (e, st) {
      debugPrint('[MediaPicker] gallery save failed: $e\n$st');
      showTrSnackbar(
        'snackbar_camera_gallery_save_failed',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
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

      if (Platform.isAndroid) {
        // FileType.media is photos-only on many OEMs. Custom + MIME-safe
        // image/video extensions keeps both visible (same as Media GPS +).
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions:
              MediaGpsFileMetadataService.androidPickerExtensions,
          allowMultiple: true,
          withData: false,
        );
        if (result != null) {
          for (final file in result.files) {
            if (file.path == null) continue;
            final path = _normalizePickerPath(file.path!);
            // Content URIs may lack an extension — use picker extension too.
            final ext = (file.extension ?? '').toLowerCase();
            final hint = ext.isNotEmpty ? '$path.$ext' : path;
            if (_looksLikeVideo(hint)) {
              videoPaths.add(path);
            } else {
              imagePaths.add(path);
            }
          }
        }
      } else {
        final selected = await ImagePicker().pickMultipleMedia();
        for (final media in selected) {
          final path = _normalizePickerPath(media.path);
          if (_looksLikeVideo(path, mimeType: media.mimeType)) {
            videoPaths.add(path);
          } else {
            imagePaths.add(path);
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

