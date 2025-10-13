import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class UiController extends GetxController {
  RxBool darkMode = false.obs;
  RxBool togglePlayPause = false.obs;
  RxBool isPlaying = false.obs;
  RxString selectedLanguage = 'en'.obs;
  RxString mainColor = 'blue'.obs;

  var phoneVerificationEnabled = false.obs;

  bool isTagMode = true; // Default to tag mode

  void setTagMode(bool tagMode) {
    isTagMode = tagMode;
  }

  void setMainColor(String color) {
    mainColor.value = color;
  }

  Color get currentMainColor {
    switch (mainColor.value) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'purple':
        return Colors.purple;
      case 'blue':
      default:
        return Colors.blue;
    }
  }

  Color get currentEditIconColor {
    switch (mainColor.value) {
      case 'red':
        return Colors.red[300]!;
      case 'green':
        return Colors.green[300]!;
      case 'purple':
        return Colors.purple[300]!;
      case 'blue':
      default:
        return Colors.blue[300]!;
    }
  }

  Color get currentIconColor {
    switch (mainColor.value) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'purple':
        return Colors.purple;
      case 'blue':
      default:
        return Colors.blue;
    }
  }

  Color getLightModeBackgroundColor(String mainColor) {
    switch (mainColor.toLowerCase()) {
      case 'blue':
        return const Color(0xFFF6FAFF);
      case 'red':
        return const Color(0xFFFAE7E7);
      case 'green':
        return const Color(0xFFE8FBE8);
      case 'purple':
        return const Color(0xFFF3E9FF);
      default:
        return const Color(0xFFF6FAFF);
    }
  }

  ColorFilter? get rectangleColorFilter {
    if (mainColor.value == 'blue') return null;

    return ColorFilter.mode(
      currentMainColor.withOpacity(0.9),
      BlendMode.srcATop,
    );
  }

  Color? get iconColor {
    if (mainColor.value == 'blue') return null;
    return Color.alphaBlend(Colors.black.withOpacity(0.3), currentMainColor);
  }

  Color? get iconColor2 {
    if (mainColor.value == 'blue') return null;
    return Color.alphaBlend(Colors.black.withOpacity(0.5), currentMainColor);
  }

  Color? get primaryColor {
    if (mainColor.value == 'blue') return null;
    return currentMainColor.withOpacity(0.7);
  }

  Color? get primaryColorDark {
    if (mainColor.value == 'blue') return null;
    return currentMainColor.withOpacity(0.3);
  }

  Color? get secondaryColor {
    if (mainColor.value == 'blue') return null;
    return currentMainColor.withOpacity(0.4);
  }

  Color? get secondaryColorDark {
    if (mainColor.value == 'blue') return null;
    return currentMainColor.withOpacity(0.1);
  }

  Color getPopUpColors(bool isTagMode) {
    if (mainColor.value == 'blue') {
      return isTagMode ? Color(0xFFF4FFF5) : Color(0xFFF0F7FF);
    }
    return currentMainColor.withOpacity(0.1);
  }

  final count = 0.obs;
  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onReady() {
    super.onReady();
  }

  @override
  void onClose() {
    super.onClose();
  }

  void increment() => count.value++;
}
