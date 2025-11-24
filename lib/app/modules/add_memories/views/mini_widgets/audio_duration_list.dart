import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../../../config/app_images.dart';
import '../../../memories/bindings/memory_binding.dart';
import '../../../memories/views/memory_view.dart';
import '../../../ui/controllers/ui_controller.dart';
import 'audio_player_helper.dart';

class AudioDurationList extends StatefulWidget {
  final List<String> durations;
  final List<String>? audioPaths;
  final VoidCallback? onLongPress;

  const AudioDurationList({
    required this.durations,
    this.audioPaths,
    this.onLongPress,
    super.key,
  });

  @override
  State<AudioDurationList> createState() => _AudioDurationListState();
}

class _AudioDurationListState extends State<AudioDurationList>
    with TickerProviderStateMixin {
  String? selected;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Row(
      children:
          widget.durations.asMap().entries.map((entry) {
            final index = entry.key;
            final d = entry.value;
            final isSelected = selected == d;
            final isDark = controller.darkMode.value;

            final borderColor = isDark ? Colors.white : Colors.black;

            return Padding(
              padding: const EdgeInsets.only(
                left: 4,
                right: 4.0,
                top: 8,
                bottom: 8,
              ),
              child: GestureDetector(
                onTap: () async {
                  setState(() {
                    selected = d;
                  });

                  // Show audio player popup if audio path is available
                  if (widget.audioPaths != null &&
                      index < widget.audioPaths!.length) {
                    await AudioPlayerHelper.showAudioPlayerFromList(
                      audioPaths: widget.audioPaths!,
                      index: index,
                      durations: widget.durations,
                    );
                  } else {
                    AudioPlayerHelper.showAudioNotAvailable();
                  }
                },
                onLongPress: widget.onLongPress,
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      // if (isSelected)
                      BoxShadow(
                        color: Colors.blue.withOpacity(
                          isDark ? 0.4 : 0.3,
                        ), // Stronger in dark
                        blurRadius: 6,
                        spreadRadius: 0.5,
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            controller.darkMode.value
                                ? Colors.white.withOpacity(0.4)
                                : Colors.black.withOpacity(0.1),
                        width: 0.5,
                      ),
                      boxShadow: [
                        if (!isSelected)
                          BoxShadow(
                            color:
                                isDark
                                    ? Colors.white.withOpacity(0.3)
                                    : Colors.grey.withOpacity(0.3),
                            blurRadius: 5,
                            spreadRadius: 0.05,
                            offset: Offset(0, 0),
                          ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Image.asset(
                          AppImages.audioWaves,
                          width: 45,
                          height: 45,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}
