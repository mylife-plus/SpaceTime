import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/widgets/appbar.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_images.dart';
import '../../../config/app_text.dart';
import '../../memories/controllers/memory_controller.dart';
import '../../memories/views/mini_widgets/mention_bottom_sheet_widget.dart';
import '../../ui/controllers/ui_controller.dart';
import '../controllers/contact_groups_controller.dart';
import 'mini_widgets/contact_detail_page.dart';
import 'mini_widgets/contact_group_tile.dart';

class ContactGroupsView extends GetView<ContactGroupsController> {
  const ContactGroupsView({super.key});

  void _showNewHashtagGroupPopup(BuildContext context) {
    final TextEditingController groupNameController = TextEditingController();
    final TextEditingController searchController = TextEditingController();
    final controller = Get.find<UiController>();

    final RxList<String> selectedMentions = <String>[].obs;
    OverlayEntry? overlayEntry;
    bool isPopupOpen = false;

    void _removePopup() {
      if (overlayEntry != null) {
        overlayEntry!.remove();
        overlayEntry = null;
        isPopupOpen = false;
      }
    }

    void _showHashtagPopup() {
      if (isPopupOpen) return;

      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      isPopupOpen = true;
      final memoryController = Get.put(TagMentionController(isTagMode: true));
      memoryController.loadSavedItems();

      overlayEntry = OverlayEntry(
        builder:
            (context) => Positioned(
              left: 20,
              right: 20,
              top: 200,
              child: Material(
                elevation: 8,
                color: Colors.transparent,
                child: TagMentionBottomSheet(
                  onItemSelected: (item) {
                    final mention = item.substring(1);
                    if (!selectedMentions.contains(mention)) {
                      selectedMentions.add(mention);
                    }
                    searchController.clear();
                    _removePopup();
                  },
                  isTagMode: false,
                  initialKeyword: '',
                  searchNotifier: ValueNotifier<String>(''),
                  onEditingComplete: _removePopup,
                ),
              ),
            ),
      );

      Overlay.of(context).insert(overlayEntry!);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.5,
            // height: 360,
            decoration: BoxDecoration(
              color:
                  controller.darkMode.value ? Colors.grey[900] : Colors.white,
              boxShadow: [
                BoxShadow(
                  color:
                      controller.darkMode.value
                          ? Colors.white.withOpacity(0.6)
                          : Colors.black.withOpacity(0.6),
                  blurRadius: 10,
                  offset: Offset(0, -5),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 16),
                  Text(
                    'new @ Group',

                    style: AppFonts.regular(19, color: AppColors.blue),
                  ),
                  SizedBox(height: 16),

                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color:
                          controller.darkMode.value
                              ? Colors.grey[800]
                              : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 3,
                          spreadRadius: 0.6,
                          offset: Offset(0, 0),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10.0, right: 10),
                      child: TextField(
                        controller: groupNameController,
                        decoration: InputDecoration(
                          hintText: 'Contact Group Name',
                          hintStyle: AppFonts.regular(19, color: Colors.grey),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 5),
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color:
                          controller.darkMode.value
                              ? Colors.grey[800]
                              : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 3,
                          spreadRadius: 0.6,
                          offset: Offset(0, 0),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: TextField(
                        controller: searchController,
                        onChanged: (value) {
                          if (value.contains('@')) {
                            _showHashtagPopup();
                          } else {
                            _removePopup();
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Search Contacts',
                          hintStyle: AppFonts.regular(19, color: Colors.grey),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 12),
                  // Selected hashtags display
                  Obx(
                    () =>
                        selectedMentions.isEmpty
                            ? SizedBox.shrink()
                            : SizedBox(
                              height: 40,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: selectedMentions.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    margin: EdgeInsets.only(right: 8),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppColors.blue),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${selectedMentions[index]}',
                                          style: TextStyle(
                                            color:
                                                controller.darkMode.value
                                                    ? Colors.white
                                                    : Colors.black,
                                            fontWeight: FontWeight.w400,
                                            fontSize: 16,
                                          ),
                                        ),
                                        SizedBox(width: 4),
                                        GestureDetector(
                                          onTap:
                                              () => selectedMentions.removeAt(
                                                index,
                                              ),
                                          child: Icon(Icons.close, size: 16),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                  ),
                  Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 40.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: () {
                            _removePopup();
                            Navigator.pop(context);
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            padding: EdgeInsets.all(17),
                            decoration: BoxDecoration(
                              color:
                                  controller.darkMode.value
                                      ? Colors.black
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Image.asset(AppImages.rejectImg),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            _removePopup();
                            Navigator.pop(context);

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '@ contact groups added successfully',
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            padding: EdgeInsets.all(17),
                            decoration: BoxDecoration(
                              color:
                                  controller.darkMode.value
                                      ? Colors.black
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Image.asset(AppImages.acceptImg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Scaffold(
      backgroundColor:
          controller.darkMode.value
              ? Colors.black
              : controller.getLightModeBackgroundColor(
                controller.mainColor.value,
              ),
      appBar: CustomAppBar(
        title: AppTexts.contactGroups,
        icon: Image.asset(
          AppImages.contact,
          color: controller.darkMode.value ? Colors.white : Colors.black,
        ),
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              Container(
                color: Colors.white,
                child: Column(
                  children: [
                    ContactGroupTile(
                      title: AppTexts.family,
                      trailingText: '6',
                      trailingIcon: Icons.arrow_forward_ios,
                      onTap: () {
                        Get.to(() => ContactDetailPage());
                      },
                      showDivider: true,
                    ),
                    ContactGroupTile(
                      title: AppTexts.homes,
                      trailingText: '10',
                      trailingIcon: Icons.arrow_forward_ios,
                      onTap: () => debugPrint('Tapped edit'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 30,
            left: MediaQuery.of(context).size.width / 2 - 24.5,
            child: GestureDetector(
              onTap: () {
                _showNewHashtagGroupPopup(context);
              },
              child: Container(
                width: 49,
                height: 51,
                padding: EdgeInsets.all(7),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: const AssetImage(AppImages.rectangle),
                    colorFilter:
                        controller.darkMode.value
                            ? controller.mainColor.value == 'blue'
                                ? const ColorFilter.mode(
                                  Color(0xFF002B62),
                                  BlendMode.srcIn,
                                )
                                : ColorFilter.mode(
                                  (controller.iconColor ?? AppColors.blue),
                                  BlendMode.srcIn,
                                )
                            : (controller.rectangleColorFilter ??
                                const ColorFilter.mode(
                                  AppColors.blue,
                                  BlendMode.srcIn,
                                )),
                  ),
                ),
                child: Image.asset(AppImages.addIcon, fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
