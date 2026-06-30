import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/l10n/place_category_l10n.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import '../../controllers/add_memories_controller.dart';

class SearchOverlay extends StatefulWidget {
  const SearchOverlay({super.key});

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    final controller = Get.find<AddMemoriesController>();
    _textController = TextEditingController(text: controller.searchQuery.value);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AddMemoriesController>();
    final uiController = Get.find<UiController>();
    final searchSurface = uiController.searchOverlayBackgroundColor;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: searchSurface,
              child: Container(
                height: 61,
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Image.asset(
                      AppImages.searchNormal,
                      width: 25,
                      height: 25,
                      color: uiController.darkMode.value ? Colors.white : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        textAlign: TextAlign.start,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (val) {
                          controller.searchQuery.value = val;
                          controller.generateSearchSuggestions(val);
                        },
                        onSubmitted: (val) async {
                          await controller.performSearch();
                          controller.isSearchActive.value = false;
                          FocusScope.of(context).unfocus();
                        },
                        decoration: InputDecoration(
                          hintText: 'hinttext_search_memories'.tr,
                          hintStyle: GoogleFonts.kumbhSans(
                            color: uiController.darkMode.value
                                ? Colors.white
                                : const Color(0xFF9A9A9A),
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: uiController.darkMode.value
                            ? Colors.white
                            : const Color(0xFF9A9A9A),
                      ),
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        unawaited(controller.closeSearchAndMaybeReloadMap());
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Obx(() {
            if (!controller.showSuggestions.value ||
                controller.searchSuggestionsWithMetadata.isEmpty) {
              return const SizedBox.shrink();
            }

            final _ = uiController.selectedLanguage.value;
            final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
            final screenHeight = MediaQuery.of(context).size.height;
            final maxHeight =
                screenHeight - 61 - keyboardHeight - 20;

            return Positioned(
              top: 61,
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: searchSurface,
                elevation: 2,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxHeight > 0 ? maxHeight : 200,
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: controller.searchSuggestionsWithMetadata.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final suggestionData =
                          controller.searchSuggestionsWithMetadata[index];
                      final type = suggestionData['type'] ?? '';
                      final text = suggestionData['text'] ?? '';

                      if (type == 'hashtag' || type == 'mention') {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          title: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.kumbhSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: uiController.darkMode.value
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                          onTap: () => controller.selectHashtagOrMentionSuggestion(
                            text,
                            suggestionData: suggestionData,
                          ),
                        );
                      }

                      final date = suggestionData['date'] ?? '';
                      final year = suggestionData['year'] ?? '';
                      final time = suggestionData['time'] ?? '';
                      final category = '${suggestionData['category'] ?? ''}';
                      final locationCity =
                          suggestionData['location_city'] ?? '';
                      final locationCountry =
                          suggestionData['location_country'] ?? '';
                      final locationFlag =
                          suggestionData['location_flag'] ?? '';

                      String locationDisplay = '';
                      if (locationCity.isNotEmpty &&
                          locationCountry.isNotEmpty) {
                        locationDisplay = '$locationCity, $locationCountry';
                        if (locationFlag.isNotEmpty) {
                          locationDisplay += ' $locationFlag';
                        }
                      } else if (locationCity.isNotEmpty) {
                        locationDisplay = locationCity;
                        if (locationFlag.isNotEmpty) {
                          locationDisplay += ' $locationFlag';
                        }
                      } else if (locationCountry.isNotEmpty) {
                        locationDisplay = locationCountry;
                        if (locationFlag.isNotEmpty) {
                          locationDisplay += ' $locationFlag';
                        }
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$date $year',
                                  style: GoogleFonts.kumbhSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: uiController.darkMode.value
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                                Text(
                                  time,
                                  style: GoogleFonts.kumbhSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: uiController.darkMode.value
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    category.isEmpty
                                        ? ''
                                        : localizedPlaceCategoryStoredLabel(
                                            category,
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.kumbhSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: uiController.darkMode.value
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    locationDisplay,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.kumbhSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: uiController.darkMode.value
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => controller.selectSuggestion(
                          text,
                          suggestionData: suggestionData,
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
