import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:spacetime/app/app_bootstrap.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/theme/app_system_ui.dart';

import '../../../config/app_colors.dart';
import '../controllers/add_memories_controller.dart';
import '../../memories/controllers/memory_controller.dart';
import '../../../routes/memory_view_navigation.dart';
import '../../filter/controllers/filter_controller.dart';
import 'mini_widgets/header.dart';
import 'mini_widgets/memory_card.dart';
import 'mini_widgets/year_separator.dart';
import 'mini_widgets/search_overly.dart';
import 'mini_widgets/filter_overlay.dart';
import 'mini_widgets/search_indicator.dart';
import 'mini_widgets/filter_indicator.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

// App lifecycle is now handled in AddMemoriesController via WidgetsBindingObserver.
// The controller registers/unregisters itself in onInit/onClose, so the view
// stays a pure stateless widget with no lifecycle side-effects.
class AddMemoriesView extends GetView<AddMemoriesController> {
  AddMemoriesView({super.key});

  final UiController uiController = Get.find<UiController>();

  Widget _buildMemoryList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo is ScrollUpdateNotification) {
          controller.handleScrollUpdate(
            scrollInfo.metrics.pixels,
            scrollInfo.metrics.maxScrollExtent,
          );
          if (scrollInfo.metrics.pixels >=
              scrollInfo.metrics.maxScrollExtent - 600) {
            controller.scheduleLoadMoreDisplayItems();
          }
        }
        return false;
      },
      child: Obx(() {
        final _ = uiController.selectedLanguage.value;

        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.displayMemories.isEmpty) {
          final filteredOrSearch =
              controller.isSearching.value || controller.hasActiveFilters.value;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  filteredOrSearch
                      ? Icons.search_off
                      : Icons.photo_library_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  filteredOrSearch
                      ? 'text_no_memories_found'.tr
                      : 'text_no_memories_yet'.tr,
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  filteredOrSearch
                      ? 'text_try_adjusting_your_search_or_filters'.tr
                      : 'text_start_creating_your_first_memory'.tr,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        final loaded = controller.loadedDisplayCount.value;
        final hasMore = controller.hasMoreDisplayItems;
        final loadingMore = controller.isLoadingMoreDisplay.value;
        final footerCount = (hasMore || loadingMore) ? 1 : 0;

        return ListView.builder(
          controller: controller.scrollController,
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          cacheExtent: 800,
          itemCount: loaded + footerCount,
          itemBuilder: (context, index) {
            if (index >= loaded) {
              if (hasMore && !loadingMore) {
                controller.scheduleLoadMoreDisplayItems();
              }
              return ColoredBox(
                color: !uiController.darkMode.value
                    ? Colors.white
                    : Colors.transparent,
                child: SizedBox(
                  height: loadingMore ? 72 : 100,
                  child: loadingMore
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              );
            }
            final memory = controller.displayMemories[index];
            return MemoryCard(
              key: ValueKey(memory['id']),
              memoryData: memory,
            );
          },
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    ensureHeavyAppControllersRegistered();

    // NOTE: Lifecycle observer registration was intentionally removed from here.
    // It now lives in AddMemoriesController.onInit() so it is registered exactly
    // once and cleaned up in onClose(), preventing duplicate observer callbacks
    // on every widget rebuild.
    return Obx(() {
      final _ = uiController.selectedLanguage.value;
      final isDark = uiController.darkMode.value;

      return AnnotatedRegion<SystemUiOverlayStyle>(
        // Light mode: status-bar area uses the current main color (matching the
        // Header app bar) with white icons. Dark mode: unchanged.
        value: isDark
            ? AppSystemUi.overlayStyle(dark: true)
            : AppSystemUi.overlayStyleLightStatusIcons(dark: false),
        child: ColoredBox(
          color: isDark
              ? uiController.darkBackgroundColor
              : uiController.currentMainColor,
          child: SafeArea(
            bottom: false,
            child: Scaffold(
              // Light mode: opaque white body so only the top safe-area shows
              // the main color (continuing into the Header); dark mode keeps
              // the prior transparent behavior over the dark background.
              backgroundColor:
                  isDark ? Colors.transparent : Colors.white,
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
          
                        final result = await openMemoryView();
                        // Always refresh memories when returning from memory creation
                        debugPrint(
                          'Returned from memory creation, refreshing add memories screen',
                        );
                        controller.onAgainInit();
          
                        // Show success message if memory was saved
                        if (result == true) {
                          showTrSnackbar('snackbar_success', 
                            backgroundColor: Colors.green.withValues(
                              alpha: 0.8,
                            ),
                            colorText: Colors.white,
        duration: const Duration(seconds: 2),);
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
                // Dim map/list behind filter sheet (lighter in light mode).
                if (controller.isFilterOpen.value)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(
                        alpha: uiController.darkMode.value ? 0.74 : 0.52,
                      ),
                    ),
                  ),
                if (controller.isSearchActive.value) const SearchOverlay(),
                if (controller.isFilterOpen.value)
                  MemoriesFilterOverlay(isOpenedFromMap: false),
              ],
            ),
          ),
        ),
      ),
    );
    });
  }
}
