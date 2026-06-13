import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/tappable_back_button.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Plain title when [titleWidget] is null.
  final String title;
  /// When set, replaces the centered title text (e.g. mixed-weight l10n).
  final Widget? titleWidget;
  /// Optional icon left of the title (omit for title-only bar).
  final Widget? icon;
  final VoidCallback? onBack;
  /// Optional trailing widget (e.g. + action), aligned top-right like Places screen.
  final Widget? trailing;

  CustomAppBar({
    super.key,
    this.title = '',
    this.titleWidget,
    this.icon,
    this.onBack,
    this.trailing,
  }) : assert(
          title.isNotEmpty || titleWidget != null,
          'Provide title or titleWidget',
        );

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Obx(
      () => AppBar(
        automaticallyImplyLeading: false,
        backgroundColor:
            controller.darkMode.value
                ? controller.mainColor.value == 'blue'
                    ? Color(0xFF001937)
                    : controller.primaryColorDark
                : controller.currentMainColor,
        elevation: 0,
        centerTitle: true,
        title: Row(
          children: [
            TappableBackArea(
              onTap: onBack ?? Get.back,
              child: Image.asset(
                AppImages.arrowBack,
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: FittedBox(fit: BoxFit.contain, child: icon!),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: titleWidget != null
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: titleWidget!,
                          )
                        : AutoSizeText(
                            title,
                            maxLines: 2,
                            minFontSize: 10,
                            style: AppFonts.bold(18, color: Colors.white),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),
            trailing ?? const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}
