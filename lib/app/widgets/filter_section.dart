import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class FilterPanel extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback onReset;
  final VoidCallback onApply;
  final VoidCallback? onBack;

  const FilterPanel({
    super.key,
    required this.children,
    required this.onReset,
    required this.onApply,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping on the panel background
        FocusScope.of(context).unfocus();
      },
      child: Container(
        color: Colors.black.withAlpha(0),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(0),
            child: Container(
              decoration: BoxDecoration(
      color: controller.darkMode.value
                ? controller.mainColor.value == 'blue'
                    ? Color(0xFF001937)
                    : controller.iconColor2
                : controller.mainColor.value == 'blue'
                ? Color(0xFF92C3FF)
                : controller.primaryColor,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(10),
        bottomRight: Radius.circular(10),
      ),
    // boxShadow: [
    //   BoxShadow(
    //     color: Colors.black.withOpacity(0.11),
    //     blurRadius: 10,
    //     offset: const Offset(0, 2),
    //   ),
    // ],
  ),
            //  color:
          
            child: Padding(
              padding: EdgeInsets.only(left : 8, right: 8, bottom: 8, top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      // Back button on the left
                      if (onBack != null)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: InkWell(
                            onTap: onBack,
                            child: ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                controller.darkMode.value ? Colors.white : Colors.white,
                                BlendMode.srcIn,
                              ),
                              child: Image.asset(
                                AppImages.arrowBack,
                                width: 24,
                                height: 24,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      // Filter icon in the center
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              controller.darkMode.value ? Colors.white : Colors.white,
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              AppImages.filter,
                              width: 24,
                              height: 24,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...children,
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              controller.darkMode.value
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.white,
                          side: BorderSide(
                            color:
                                controller.darkMode.value
                                    ? Colors.red.withOpacity(0.5)
                                    : Colors.red,
                          ),
                        ),
                        onPressed: onReset,
                        child: Text(
                          'reset',
                          style: GoogleFonts.kumbhSans(
                            color:
                                controller.darkMode.value ? Colors.red : Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              controller.darkMode.value
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.white,
                          side: const BorderSide(color: Colors.blue),
                        ),
                        onPressed: onApply,
                        child: Text(
                          'filter',
                          style: GoogleFonts.kumbhSans(
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ); // GestureDetector
  }
}
