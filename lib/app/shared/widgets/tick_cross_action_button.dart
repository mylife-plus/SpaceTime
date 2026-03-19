import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

/// Shared large tick/cross action button used across location pickers.
/// Matches the 60x60 design used in MemoryView.
class TickCrossActionButton extends StatelessWidget {
  final String iconPath;
  final VoidCallback onTap;

  const TickCrossActionButton({
    super.key,
    required this.iconPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Use app's GetX dark mode source of truth (more reliable than Theme brightness).
    final isDark = Get.isRegistered<UiController>()
        ? Get.find<UiController>().darkMode.value
        : (Theme.of(context).brightness == Brightness.dark);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isDark
              ? Border.all(
                  color: Colors.white.withOpacity(0.22),
                  width: 2,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Image.asset(
            iconPath,
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

