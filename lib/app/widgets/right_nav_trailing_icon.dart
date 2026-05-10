import 'package:flutter/material.dart';
import 'package:spacetime/app/config/app_images.dart';

/// Tinted `ic_right_nav.png` for list/settings row trailing affordance.
class RightNavTrailingIcon extends StatelessWidget {
  const RightNavTrailingIcon({
    super.key,
    required this.color,
    this.size = 16,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: Image.asset(
          AppImages.rightNav,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
