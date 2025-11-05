import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
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
          controller.closeSearch();
          FocusScope.of(context).unfocus();
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
                          onChanged: (val) {
                            controller.searchQuery.value = val;
                            controller.generateSearchSuggestions(val);
                          },
                          onSubmitted: (val) {
                            // Remove automatic search on keyboard submit
                            controller.searchQuery.value = val;
                            controller.showSuggestions.value = false;
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
                          controller.closeSearch();
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
                  controller.searchSuggestions.isEmpty) {
                return const SizedBox.shrink();
              }

              return Positioned(
                top: 61,
                left: 0,
                right: 0,
                child: Container(
                  width: MediaQuery.sizeOf(context).width,
                  // margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color:
                        controller2.darkMode.value
                            ? Colors.black
                            : Colors.white,
                    // borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.11),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,

                    itemCount: controller.searchSuggestions.length,
                    separatorBuilder:
                        (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final suggestion = controller.searchSuggestions[index];
                      return ListTile(
                        title: Text(
                          suggestion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                controller2.darkMode.value
                                    ? Colors.white
                                    : Colors.black,
                          ),
                        ),
                        onTap: () => controller.selectSuggestion(suggestion),
                      );
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
