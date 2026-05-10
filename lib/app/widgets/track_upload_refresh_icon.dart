import 'package:flutter/material.dart';
import 'package:spacetime/app/config/app_images.dart';

Widget trackUploadRefreshAppBarIcon() => ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      child: Image.asset(
        AppImages.refresh,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
      ),
    );

Widget trackUploadRefreshListIcon(Color color) => ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        AppImages.refresh,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
      ),
    );
