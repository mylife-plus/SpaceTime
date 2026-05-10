import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_gallery_service.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

String _appLangCode() {
  if (Get.isRegistered<UiController>()) {
    return Get.find<UiController>().selectedLanguage.value;
  }
  return '';
}

/// Explains why access is needed (localized), then requests OS permission; opens Settings if still denied.
Future<bool> ensureMediaGalleryPermissionForPicker(BuildContext context) async {
  final lang = _appLangCode();
  var state = await PhotoManager.getPermissionState(
      requestOption: kMediaGpsGalleryPermissionRequest);
  // iOS Limited Library is `limited`, not `authorized`; use hasAccess.
  if (state.hasAccess) return true;
  if (!context.mounted) return false;

  final prime = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(trForLang('media_gps_permission_dialog_title', lang)),
      content: SingleChildScrollView(
        child: Text(trForLang('media_gps_permission_dialog_body', lang)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(trForLang('text_cancel', lang)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(trForLang('title_text_grant_permission', lang)),
        ),
      ],
    ),
  );
  if (prime != true) return false;
  if (!context.mounted) return false;

  state = await PhotoManager.requestPermissionExtend(
    requestOption: kMediaGpsGalleryPermissionRequest,
  );
  if (state.hasAccess) return true;

  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(trForLang('title_literal_photos_access_needed', lang)),
      content: Text(trForLang('dialog_content_permission_storage_gallery', lang)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(trForLang('text_cancel', lang)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            PhotoManager.openSetting();
          },
          child: Text(trForLang('label_open_settings', lang)),
        ),
      ],
    ),
  );
  return false;
}

/// Uses [Get.context] when non-null; otherwise denies without UI.
Future<bool> ensureMediaGalleryPermissionForPickerNav() async {
  final ctx = Get.context;
  if (ctx == null) return false;
  return ensureMediaGalleryPermissionForPicker(ctx);
}
