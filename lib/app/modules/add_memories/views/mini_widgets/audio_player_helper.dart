import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_player_popup.dart';

class AudioPlayerHelper {
  /// Resolve the full audio file path from filename or partial path
  static Future<String?> _resolveAudioPath(String audioPath) async {
    try {
      // If it's already a full path and file exists, return it
      final file = File(audioPath);
      if (await file.exists()) {
        return audioPath;
      }

      // If it's just a filename, construct the full path
      final fileName = audioPath.split('/').last;
      final directory = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${directory.path}/audio_files');
      final fullPath = '${audioDir.path}/$fileName';

      final fullPathFile = File(fullPath);
      if (await fullPathFile.exists()) {
        return fullPath;
      }

      // Try alternative locations
      final altPath = '${directory.path}/$fileName';
      final altFile = File(altPath);
      if (await altFile.exists()) {
        return altPath;
      }

      debugPrint('Audio file not found at any location: $audioPath');
      return null;
    } catch (e) {
      debugPrint('Error resolving audio path: $e');
      return null;
    }
  }

  /// Show audio player popup with the given audio file
  static Future<void> showAudioPlayer({
    required String audioPath,
    String? duration,
    String? fileName,
  }) async {
    // Resolve the full audio path
    final resolvedPath = await _resolveAudioPath(audioPath);

    if (resolvedPath == null) {
      Get.snackbar(
        'Error',
        'Audio file not found: ${audioPath.split('/').last}',
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    // Extract filename from path if not provided
    final displayFileName = fileName ?? resolvedPath.split('/').last;

    Get.dialog(
      AudioPlayerPopup(
        audioPath: resolvedPath,
        duration: duration,
        fileName: displayFileName,
      ),
      barrierDismissible: true,
    );
  }

  /// Show audio player popup for a list of audio files at specific index
  static Future<void> showAudioPlayerFromList({
    required List<String> audioPaths,
    required int index,
    List<String>? durations,
    List<String>? fileNames,
  }) async {
    if (index < 0 || index >= audioPaths.length) {
      Get.snackbar(
        'Error',
        'Invalid audio file index',
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final audioPath = audioPaths[index];
    final duration = (durations != null && index < durations.length)
        ? durations[index]
        : null;
    final fileName = (fileNames != null && index < fileNames.length)
        ? fileNames[index]
        : audioPath.split('/').last;

    await showAudioPlayer(
      audioPath: audioPath,
      duration: duration,
      fileName: fileName,
    );
  }

  /// Show error message when audio is not available
  static void showAudioNotAvailable() {
    Get.snackbar(
      'Audio Player',
      'Audio file not available for playback',
      backgroundColor: Colors.orange.shade400,
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }
}
