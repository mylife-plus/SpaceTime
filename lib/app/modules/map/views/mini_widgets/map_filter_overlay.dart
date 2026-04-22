import 'package:flutter/material.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_overlay.dart';

/// Map filter UI; filter sync runs in [MemoriesFilterOverlay] (post-frame).
class MapFilterOverlay extends StatelessWidget {
  const MapFilterOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const MemoriesFilterOverlay(isOpenedFromMap: true);
  }
}
