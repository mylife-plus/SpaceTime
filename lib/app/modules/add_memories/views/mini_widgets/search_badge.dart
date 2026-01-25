import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/add_memories_controller.dart';
import '../../../filter/controllers/filter_controller.dart';

/// Search badge widget that shows when there's an active text search
/// Can be used on both AddMemories and Map views
class SearchBadge extends StatelessWidget {
  const SearchBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final filterController = Get.find<FilterController>();
    final addMemoriesController = Get.find<AddMemoriesController>();
 return Container();
  }
}

