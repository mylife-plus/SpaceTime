import 'package:flutter/material.dart';

/// Minimum touch target size per Material guidelines (48x48).
const double kMinBackButtonTapSize = 48.0;

/// Padding around back/close icons for a larger tappable area.
const EdgeInsets kBackButtonPadding = EdgeInsets.all(12.0);

/// Style for back/close IconButtons to ensure 48x48 minimum tappable area.
ButtonStyle backButtonStyle() => IconButton.styleFrom(
      minimumSize: const Size(kMinBackButtonTapSize, kMinBackButtonTapSize),
      padding: kBackButtonPadding,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

/// A back or close icon button with a large tappable area (min 48x48).
class TappableBackButton extends StatelessWidget {
  const TappableBackButton({
    super.key,
    required this.onPressed,
    this.icon,
    this.isClose = false,
    this.color,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isClose;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: icon ??
          Icon(
            isClose ? Icons.close : Icons.arrow_back,
            color: color,
          ),
      style: backButtonStyle(),
      tooltip: tooltip ?? (isClose ? 'Close' : 'Back'),
    );
  }
}

/// Wraps a child (e.g. custom back icon image) in a padded tappable area.
class TappableBackArea extends StatelessWidget {
  const TappableBackArea({
    super.key,
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kMinBackButtonTapSize / 2),
        child: Padding(
          padding: kBackButtonPadding,
          child: SizedBox(
            width: kMinBackButtonTapSize - 24,
            height: kMinBackButtonTapSize - 24,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
