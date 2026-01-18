import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../../config/app_colors.dart';
import '../controllers/add_memories_controller.dart';
import '../../memories/controllers/memory_controller.dart';
import '../../memories/views/memory_view.dart';
import 'mini_widgets/header.dart';
import 'mini_widgets/memory_card.dart';
import 'mini_widgets/year_separator.dart';
import 'mini_widgets/search_overly.dart';
import 'mini_widgets/filter_overlay.dart';
import 'mini_widgets/search_indicator.dart';
import 'mini_widgets/filter_indicator.dart';

class AddMemoriesView extends GetView<AddMemoriesController>
    with WidgetsBindingObserver {
   AddMemoriesView({super.key});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Refresh memories when app comes back to foreground
      debugPrint('App resumed, refreshing memories');
      controller.onAgainInit();
    }
  }

                  UiController uiController = Get.find<UiController>();

  Widget _buildMemoryList() {


    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo is ScrollUpdateNotification) {
          final currentOffset = scrollInfo.metrics.pixels;
          final maxScrollExtent = scrollInfo.metrics.maxScrollExtent;
          controller.handleScrollUpdate(currentOffset, maxScrollExtent);
        }
        return false;
      },
      child: Obx(() {
        debugPrint(
          'AddMemoriesView rebuild - isLoading: ${controller.isLoading.value}, isSearching: ${controller.isSearching.value}, allMemories: ${controller.allMemories.length}',
        );

        // Show loading state
        if (controller.isLoading.value) {
          debugPrint('Showing loading state');
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.isSearching.value) {
          // Handle empty search results
          if (controller.filteredMemories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No memories found',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try adjusting your search or filters',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          final groupedMemories = <String, List<Map<String, dynamic>>>{};
          for (final memory in controller.filteredMemories) {
            final year = memory['year'] ?? '';
            if (!groupedMemories.containsKey(year)) {
              groupedMemories[year] = [];
            }
            // debugPrint('Added memory to yearrrr $year: ${memory}');
            groupedMemories[year]!.add(memory);
          }

          final sortedYears =
              groupedMemories.keys.toList()..sort((a, b) => b.compareTo(a));

          
          return Container(
                              color: (!uiController.darkMode.value ? Colors.white : Colors.transparent),

            child: ListView(
              controller: controller.scrollController,
              // shrinkWrap: false,
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                for (final year in sortedYears) ...[
                  if (year.isNotEmpty) Container(),
                  ...groupedMemories[year]!.map(
                    (memory) => MemoryCard(memoryData: memory),
                  ),
                ],
                Container(child: SizedBox(height: 100),                            color: (!uiController.darkMode.value ? Colors.white : Colors.transparent),
             ),
              ],
            ),
          );
        }

        // Handle empty memories
        if (controller.allMemories.isEmpty) {
          debugPrint('Showing empty memories state');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No memories yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start creating your first memory!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        // Group memories by year
        debugPrint(
          'Grouping ${controller.allMemories.length} memories by year',
        );
        final groupedMemories = <String, List<Map<String, dynamic>>>{};
        for (final memory in controller.allMemories) {
          final year = memory['year'] ?? '';
          if (!groupedMemories.containsKey(year)) {
            groupedMemories[year] = [];
          }
          groupedMemories[year]!.add(memory);
          debugPrint('Added memory to yearrrrrrrr $year: ${memory['date']}');
        }

        final sortedYears =
            groupedMemories.keys.toList()..sort((a, b) => b.compareTo(a));
        debugPrint('Sorted years: $sortedYears');

        return ListView(
          controller: controller.scrollController,
          // shrinkWrap: false,
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            // Debug container
            for (final year in sortedYears) ...[
              if (year.isNotEmpty) Container(),
              ...(groupedMemories[year] ?? []).map(
                (memory) => MemoryCard(memoryData: memory),
              ),
            ],
            SizedBox(height: 100),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ensure controller is available
    if (!Get.isRegistered<AddMemoriesController>()) {
      Get.find<AddMemoriesController>();
    }

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    final uiController = Get.find<UiController>();
    return Obx(() {
      final mainColor = uiController.mainColor.value;
      final useOriginalImage = mainColor == 'blue';
      return SafeArea(
        child: Scaffold(
          backgroundColor:
                         (!uiController.darkMode.value ? Colors.white : Colors.transparent),

          // backgroundColor:
          //     uiController.darkMode.value
          //         ? Colors.black
          //         : uiController.getLightModeBackgroundColor(
          //           uiController.mainColor.value,
          //         ),
          body: Stack(
            children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: controller.isUIVisible.value ? 65 : 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: controller.isUIVisible.value ? 1.0 : 0.0,
                        child:
                            controller.isUIVisible.value
                                ? const Header()
                                : const SizedBox.shrink(),
                      ),
                    ),
          
                    // Search indicator
                    const SearchIndicator(),
          
                    // Filter indicator
                    const FilterIndicator(),
          
                    Expanded(child: _buildMemoryList()),
                  ],
                ),
                // Floating action button with animation
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  bottom: controller.isUIVisible.value ? 20 : -80,
                  left: MediaQuery.of(context).size.width / 2 - 24.5,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: controller.isUIVisible.value ? 1.0 : 0.0,
                    child: GestureDetector(
                      onTap: () async {
                        // Don't reset filters when adding a new memory
                        // Filters should persist until manually removed or reset
                        Get.put(MemoryController());
          
                        final result = await Get.to(() => MemoryView());
                        // Always refresh memories when returning from memory creation
                        debugPrint(
                          'Returned from memory creation, refreshing add memories screen',
                        );
                        controller.onAgainInit();
          
                        // Show success message if memory was saved
                        if (result == true) {
                          Get.snackbar(
                            'Success',
                            'Memory added successfully!',
                            backgroundColor: Colors.green.withValues(
                              alpha: 0.8,
                            ),
                            colorText: Colors.white,
        duration: const Duration(seconds: 2),
                          );
                        }
                      },
                      child: Container(
                        width: 49,
                        height: 51,
                        padding: EdgeInsets.all(7),
                        decoration: BoxDecoration(
                     // image: DecorationImage(
                    borderRadius: BorderRadius.circular(8), 
  color: uiController.darkMode.value
    ? (uiController.mainColor.value == 'blue'
        ? const Color(0xFF002B62)
        : (uiController.curentHomeIconColorDark))
    : uiController.currentHomeIconColor,// ✔ correct
                  
                ),
                        child: Image.asset(
                          AppImages.addIcon,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                // Blur overlay when search is active
                // if (controller.isSearchActive.value)
                // Positioned.fill(
                //   child: BackdropFilter(
                //     filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                //     child: Container(color: Colors.black.withOpacity(0.1)),
                //   ),
                // ),
                // Black overlay when filter is open
                if (controller.isFilterOpen.value)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.8),
                    ),
                  ),
                if (controller.isSearchActive.value) const SearchOverlay(),
                if (controller.isFilterOpen.value)
                  MemoriesFilterOverlay(isOpenedFromMap: false),
              ],
            ),
          ),
      );
    });
  }
}
