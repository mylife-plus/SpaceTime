import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

// class FilterPanel extends StatefulWidget {
//   final List<Widget> children;
//   final VoidCallback onReset;
//   final VoidCallback onApply;
//   final VoidCallback? onBack;
//   final ScrollController? scrollController;
//   final bool hideButtons; // Hide reset and filter buttons when search is focused

//   const FilterPanel({
//     super.key,
//     required this.children,
//     required this.onReset,
//     required this.onApply,
//     this.onBack,
//     this.scrollController,
//     this.hideButtons = false,
//   });

//   @override
//   State<FilterPanel> createState() => _FilterPanelState();
// }

// class _FilterPanelState extends State<FilterPanel> {
//   bool _isKeyboardVisible = false;

//   @override
//   void initState() {
//     super.initState();
//     // Listen to keyboard visibility changes
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       final keyboardVisibility = MediaQuery.of(context).viewInsets.bottom;
//       setState(() {
//         _isKeyboardVisible = keyboardVisibility > 0;
//       });
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final controller = Get.find<UiController>();

//     // Update keyboard visibility on every build
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       final keyboardVisibility = MediaQuery.of(context).viewInsets.bottom;
//       final isVisible = keyboardVisibility > 0;
//       if (_isKeyboardVisible != isVisible) {
//         setState(() {
//           _isKeyboardVisible = isVisible;
//         });
//       }
//     });

//     return Stack(
//       children: [
//         // Scrollable content
//         Positioned(
//           top: 0,
//           left: 0,
//           right: 0,
//           bottom: _isKeyboardVisible ? 0 : 0, // Leave space for buttons when keyboard is hidden
//           child: SingleChildScrollView(
//             controller: widget.scrollController,
//             child: Padding(
//               padding: const EdgeInsets.all(0),
//               child: GestureDetector(
//                 onTap: () {
//                   // Dismiss keyboard when tapping on the panel
//                   FocusScope.of(context).unfocus();
//                 },
//                 child: Padding(
//                   padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8, top: 8),
//                   child: Column(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Stack(
//                         children: [
//                           // Back button on the left
//                           if (widget.onBack != null)
//                             Positioned(
//                               left: 0,
//                               top: 0,
//                               child: InkWell(
//                                 onTap: widget.onBack,
//                                 child: ColorFiltered(
//                                   colorFilter: ColorFilter.mode(
//                                     controller.darkMode.value ? Colors.white : Colors.white,
//                                     BlendMode.srcIn,
//                                   ),
//                                   child: Image.asset(
//                                     AppImages.arrowBack,
//                                     width: 24,
//                                     height: 24,
//                                     fit: BoxFit.contain,
//                                   ),
//                                 ),
//                               ),
//                             ),
//                           // Filter icon in the center
//                           Row(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               ColorFiltered(
//                                 colorFilter: ColorFilter.mode(
//                                   controller.darkMode.value ? Colors.white : Colors.white,
//                                   BlendMode.srcIn,
//                                 ),
//                                 child: Image.asset(
//                                   AppImages.filter,
//                                   width: 24,
//                                   height: 24,
//                                   fit: BoxFit.contain,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 8),
//                       ...widget.children,
//                       const SizedBox(height: 10),
//                       // if (!_isKeyboardVisible)
//           if (!widget.hideButtons) // Hide buttons when search is focused
//             Positioned(
//               bottom: 0,
//               left: 0,
//               right: 0,
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
//                 decoration: BoxDecoration(
//                   color: controller.darkMode.value
//                       ? controller.mainColor.value == 'blue'
//                           ? const Color(0xFF001937)
//                           : controller.iconColor2
//                       : controller.mainColor.value == 'blue'
//                           ? const Color(0xFF92C3FF)
//                           : controller.primaryColor,
//                 ),
//                 child: Row(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     ElevatedButton(
//                       style: ElevatedButton.styleFrom(
//                         minimumSize: const Size(120, 44),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(10),
//                         ),
//                         backgroundColor: controller.darkMode.value
//                             ? Colors.white.withValues(alpha: 0.2)
//                             : Colors.white,
//                         side: BorderSide(
//                           color: controller.darkMode.value
//                               ? Colors.red.withValues(alpha: 0.5)
//                               : Colors.red,
//                         ),
//                       ),
//                       onPressed: widget.onReset,
//                       child: Text(
//                         'reset',
//                         style: GoogleFonts.kumbhSans(
//                           fontSize: 16,
//                           color: controller.darkMode.value ? Colors.red : Colors.red,
//                           fontWeight: FontWeight.w500,
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 20),
//                     ElevatedButton(
//                       style: ElevatedButton.styleFrom(
//                         minimumSize: const Size(120, 44),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(10),
//                         ),
//                         backgroundColor: controller.darkMode.value
//                             ? Colors.white.withValues(alpha: 0.2)
//                             : Colors.white,
//                         side: const BorderSide(color: Colors.blue),
//                       ),
//                       onPressed: widget.onApply,
//                       child: Text(
//                         'filter',
//                         style: GoogleFonts.kumbhSans(
//                           fontSize: 16,
//                           color: Colors.blue,
//                           fontWeight: FontWeight.w500,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
         
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ),

//         // Bottom buttons - hidden when keyboard is visible
        
//       ],
//     );
//   }
// }

class FilterPanel extends StatefulWidget {
  final List<Widget> children;
  final VoidCallback onReset;
  final VoidCallback onApply;
  final VoidCallback? onBack;
  final ScrollController? scrollController;
  final bool hideButtons;

  const FilterPanel({
    super.key,
    required this.children,
    required this.onReset,
    required this.onApply,
    this.onBack,
    this.scrollController,
    this.hideButtons = false,
  });

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel>
    with WidgetsBindingObserver {
  bool _isKeyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final bottomInset =
        WidgetsBinding.instance.window.viewInsets.bottom;
    setState(() {
      _isKeyboardVisible = bottomInset > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Obx(() {
      uiController.darkMode.value;
      uiController.mainColor.value;
      return SingleChildScrollView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(uiController),
              const SizedBox(height: 8),
              ...widget.children,
              const SizedBox(height: 8),
              if (!widget.hideButtons && !_isKeyboardVisible)
                _buildBottomButtons(uiController),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    });
  }

  // ─────────────────────────────────────────────
  // Header (Back + Filter Icon)
  // ─────────────────────────────────────────────

  Widget _buildHeader(UiController controller) {
    return SizedBox(
      width: double.infinity,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.onBack != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: InkWell(
                onTap: widget.onBack,
                child: Image.asset(
                  AppImages.arrowBack,
                  width: 24,
                  height: 24,
                  color: Colors.white,
                ),
              ),
            ),
          ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            child: Image.asset(
              AppImages.filter,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Bottom Action Buttons
  // ─────────────────────────────────────────────

  Widget _buildBottomButtons(UiController controller) {
    final accent = controller.currentMainColor;
    return Container(
      // padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      // decoration: BoxDecoration(
        // color: controller.darkMode.value
        //     ? controller.mainColor.value == 'blue'
        //         ? const Color(0xFF001937)
        //         : controller.iconColor2
        //     : controller.mainColor.value == 'blue'
        //         ? const Color(0xFF92C3FF)
        //         : controller.primaryColor,
      // ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              backgroundColor: controller.darkMode.value
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white,
              side: BorderSide(
                color: controller.darkMode.value
                    ? Colors.red.withValues(alpha: 0.5)
                    : Colors.red,
              ),
            ),
            onPressed: widget.onReset,
            child: Text(
              'text_reset'.tr,
              style: GoogleFonts.kumbhSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.red,
              ),
            ),
          ),
          const SizedBox(width: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              backgroundColor: controller.darkMode.value
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white,
              side: BorderSide(color: accent),
            ),
            onPressed: widget.onApply,
            child: Text(
              'text_filter'.tr,
              style: GoogleFonts.kumbhSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
