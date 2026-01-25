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

    return Obx(() {
      // Show badge only when there's an active search
      if (!filterController.hasActiveSearch) {
        return const SizedBox.shrink();
      }

      final searchKeyword = filterController.searchedTextKeyword.value;
      final resultCount = filterController.filteredMemories.length;

      return Positioned(
        right: 0,
        top: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white,
              width: 1.5,
            ),
          ),
          constraints: const BoxConstraints(
            minWidth: 18,
            minHeight: 18,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search,
                size: 10,
                color: Colors.white,
              ),
              const SizedBox(width: 2),
              Text(
                resultCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

