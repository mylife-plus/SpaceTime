import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import '../../controllers/add_memories_controller.dart';

class SearchOverlay extends StatelessWidget {
  const SearchOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AddMemoriesController>();
    final controller2 = Get.find<UiController>();

    final textController = TextEditingController(
      text: controller.isSearchActive.value ? '' : controller.searchQuery.value,
    );

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          // controller.closeSearch();
          // FocusScope.of(context).unfocus();
        },
        child: Stack(
          children: [
            // BackdropFilter(
            //   filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            //   child: Container(color: Colors.black.withOpacity(0.6)),
            // ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  height: 61,
                  color:
                      controller2.darkMode.value ? Colors.black : Colors.white,
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
                        color: controller2.darkMode.value ? Colors.white : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: textController,
                          textAlign: TextAlign.start,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: (val) {
                            controller.searchQuery.value = val;
                            controller.generateSearchSuggestions(val);
                          },
                          onSubmitted: (val) {
                            // Perform search and hide keyboard
                            controller.performSearch();
                            controller.isSearchActive.value = false;
                            FocusScope.of(context).unfocus();
                          },
                          decoration: InputDecoration(
                            hintText: 'search memories',
                            hintStyle: GoogleFonts.kumbhSans(
                              // color: Color(0xFF9A9A9A),
                              color:
                                  controller2.darkMode.value
                                      ? Colors.white
                                      : Color(0xFF9A9A9A),
                              fontSize: 20,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            // contentPadding: EdgeInsets.only(top: 16),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.clear,
                          color:
                              controller2.darkMode.value
                                  ? Colors.white
                                  : Color(0xFF9A9A9A),
                        ),
                        onPressed: () {
                          if (controller.isOpenedFromMap) {
      Navigator.of(Get.context!).pop(true);
    }
                          controller.closeSearch();
                           controller.resetFilters();
                        controller?.resetFilters();
                       Future.delayed(Duration(milliseconds: 500), () {
                        var c = Get.find<MapControllerNew>();
                        closefilterAndReset(c);
                       });
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Search suggestions popup
            Obx(() {
              if (!controller.showSuggestions.value ||
                  controller.searchSuggestionsWithMetadata.isEmpty) {
                return Positioned(
                top: 61,
                left: 0,
                right: 0,
                bottom: 0,
                  child: Container(
                    
                       decoration: BoxDecoration(
                      color:
                          controller2.darkMode.value
                              ? Colors.black
                              : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.11),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    ),
                );
              }

              // Calculate max height to prevent keyboard overlap
              final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
              final screenHeight = MediaQuery.of(context).size.height;
              final maxHeight =
                  screenHeight -
                  61 -
                  keyboardHeight -
                  20; // 61 for search bar, 20 for padding

              return Positioned(
                top: 61,
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: maxHeight > 0 ? maxHeight : 200,
                  ),
                  width: MediaQuery.sizeOf(context).width,
                  decoration: BoxDecoration(
                    color:
                        controller2.darkMode.value
                            ? Colors.black
                            : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.11),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min, // Take only necessary height
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount:
                              controller.searchSuggestionsWithMetadata.length,
                          separatorBuilder:
                              (context, index) => const Divider(height: 1),
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
                                    color:
                                        controller2.darkMode.value
                                            ? Colors.white
                                            : Colors.black,
                                  ),
                                ),
                                onTap:
                                    () => controller.selectSuggestion(
                                      text,
                                      suggestionData: suggestionData,
                                    ),
                              );
                            } else {
                              final date = suggestionData['date'] ?? '';
                              final year = suggestionData['year'] ?? '';
                              final time = suggestionData['time'] ?? '';
                              final category = suggestionData['category'] ?? '';
                              final locationCity =
                                  suggestionData['location_city'] ?? '';
                              final locationCountry =
                                  suggestionData['location_country'] ?? '';
                              final locationFlag =
                                  suggestionData['location_flag'] ?? '';

                              // Build location display - works with or without flag
                              String locationDisplay = '';
                              if (locationCity.isNotEmpty &&
                                  locationCountry.isNotEmpty) {
                                locationDisplay =
                                    '$locationCity, $locationCountry';
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '$date $year',
                                          style: GoogleFonts.kumbhSans(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color:
                                                controller2.darkMode.value
                                                    ? Colors.white
                                                    : Colors.black,
                                          ),
                                        ),
                                        Text(
                                          time,
                                          style: GoogleFonts.kumbhSans(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color:
                                                controller2.darkMode.value
                                                    ? Colors.white
                                                    : Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            category,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.kumbhSans(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w400,
                                              color:
                                                  controller2.darkMode.value
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
                                              color:
                                                  controller2.darkMode.value
                                                      ? Colors.white70
                                                      : Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap:
                                    () => controller.selectSuggestion(
                                      text,
                                      suggestionData: suggestionData,
                                    ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> closefilterAndReset(MapControllerNew? mapController) async {
     mapController?.isFilterOpen.value = false;
                        await mapController?.loadMemoriesFromDB(null);
                                                mapController?.showLoadedDataOnMap();

}
}
