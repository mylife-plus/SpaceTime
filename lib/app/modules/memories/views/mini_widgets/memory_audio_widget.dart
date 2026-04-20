import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/custom_dialogue_box.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import '../../../../config/app_images.dart';
import '../../../add_memories/views/mini_widgets/audio_player_helper.dart';

class MemoryAudioWidget extends StatelessWidget {
  final VoidCallback? onPlayPause;
  final VoidCallback? onRecord;
  final Function(int)? onAudioDelete;
  final Function(int, int)? onAudioReorder;

  const MemoryAudioWidget({
    super.key,
    this.onPlayPause,
    this.onRecord,
    this.onAudioDelete,
    this.onAudioReorder,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MemoryController>();
    final uiController = Get.find<UiController>();

    return Container(
      decoration: BoxDecoration(
        color:
            uiController.darkMode.value
                ? Colors.white.withValues(alpha: 0.06)
                : uiController.getLightModeBackgroundColor(
                      uiController.mainColor.value,
                    ) ??
                    const Color(0xFFF8FBFF),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Obx(() {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recording duration and record button row
              Row(
                children: [
                  // Recording duration display
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          uiController.darkMode.value
                              ? Colors.black
                              : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.transparent,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              uiController.darkMode.value
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          spreadRadius: 0.2,
                          offset: const Offset(0, 0),
                        ),
                      ],
                    ),
                    child: Text(
                      controller.recordingDuration.value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            controller.isRecording.value
                                ? Colors.red
                                : uiController.darkMode.value
                                ? Colors.white
                                : Colors.grey[700],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Record button
                  GestureDetector(
                    onTapDown: (_) async {
                      if (!controller.isRecording.value) {
                        await controller.startRecording();
                      }
                    },
                    onTapUp: (_) async {
                      if (controller.isRecording.value) {
                        await controller.stopRecording();
                      }
                    },
                    onTapCancel: () async {
                      if (controller.isRecording.value) {
                        await controller.stopRecording();
                      }
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            controller.isRecording.value
                                ? Colors.red.withValues(alpha: 0.1)
                                : uiController.darkMode.value
                                ? Colors.black
                                : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              controller.isRecording.value
                                  ? Colors.red
                                  : uiController.darkMode.value
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.transparent,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                controller.isRecording.value
                                    ? Colors.red.withValues(alpha: 0.3)
                                    : uiController.darkMode.value
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.1),
                            blurRadius: controller.isRecording.value ? 8 : 4,
                            spreadRadius:
                                controller.isRecording.value ? 1.0 : 0.0,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        AppImages.mic,
                        fit: BoxFit.contain,
                        color:
                            controller.isRecording.value
                                ? Colors.red
                                : uiController.darkMode.value
                                ? Colors.white
                                : Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
              // Horizontal list of recorded audios
              if (controller.recordedAudios.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) {
                      if (onAudioReorder != null) {
                        onAudioReorder!(oldIndex, newIndex);
                      } else {
                        controller.reorderAudio(oldIndex, newIndex);
                      }
                    },
                    itemCount: controller.recordedAudios.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        key: ValueKey('audio_${index}_${controller.recordedAudioPaths.length > index ? controller.recordedAudioPaths[index].hashCode : index}'),
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onLongPress: () {
                                showDeleteConfirmationDialog(
                                  title: 'title_literal_delete_audio'.tr,
                                  message: 'dialog_content_delete_this_audio'.tr,
                                  onConfirm: () {
                                    if (onAudioDelete != null) {
                                      // Use custom deletion handler if provided (for edit mode)
                                      onAudioDelete!(index);
                                    } else {
                                      // Use default controller method (for new memories)
                                      controller.removeAudio(index);
                                    }
                                    // Snackbar removed as per user request
                                  },
                                );
                              },
                              onTap: () async {
                                debugPrint('🎵 Audio item tapped: index $index');
                                debugPrint(
                                  '🎵 Total audio paths: ${controller.recordedAudioPaths.length}',
                                );
                                debugPrint(
                                  '🎵 Total audio durations: ${controller.recordedAudios.length}',
                                );

                                // Show audio player popup
                                if (index < controller.recordedAudioPaths.length) {
                                  final audioPath =
                                      controller.recordedAudioPaths[index];
                                  final duration =
                                      index < controller.recordedAudios.length
                                          ? controller.recordedAudios[index]
                                          : 'Unknown';

                                  debugPrint('🎵 Playing audio: $audioPath');
                                  debugPrint('🎵 Duration: $duration');

                                  await AudioPlayerHelper.showAudioPlayerFromList(
                                    audioPaths: controller.recordedAudioPaths,
                                    index: index,
                                    durations: controller.recordedAudios,
                                  );
                                } else {
                                  debugPrint('❌ Invalid audio index: $index');
                                  AudioPlayerHelper.showAudioNotAvailable();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      uiController.darkMode.value
                                          ? Colors.black
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        uiController.darkMode.value
                                            ? Colors.white.withValues(alpha: 0.3)
                                            : Colors.transparent,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white.withValues(alpha: 0.1)
                                              : Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 6,
                                      spreadRadius: 0.2,
                                      offset: const Offset(0, 0),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                                                        const SizedBox(height: 4),

                                    Image.asset(
                                      AppImages.audioWaves,
                                      width: 42,
                                      height: 60,
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white
                                              : Colors.grey[700],
                                    ),
                                    // const SizedBox(height: 4),
                                    Text(
                                      controller.recordedAudios[index],
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color:
                                            uiController.darkMode.value
                                                ? Colors.white
                                                : Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Delete icon at top-right corner
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () {
                                  showDeleteConfirmationDialog(
                                    title: 'title_literal_delete_audio_2'.tr,
                                    message: 'dialog_content_delete_this_audio'.tr,
                                    onConfirm: () {
                                      if (onAudioDelete != null) {
                                        // Use custom deletion handler if provided (for edit mode)
                                        onAudioDelete!(index);
                                      } else {
                                        // Use default controller method (for new memories)
                                        controller.removeAudio(index);
                                      }
                                      // Snackbar removed as per user request
                                    },
                                  );
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: ReorderableDragStartListener(
                                index: index,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.drag_handle,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}
