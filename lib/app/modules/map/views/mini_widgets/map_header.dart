import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../../../config/app_images.dart';
import '../../../settings/views/settings_view.dart';

class MapHeader extends StatelessWidget {
  const MapHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Get.to(() => SettingsView());
            },
            child: Container(
              padding: EdgeInsets.all(2),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(AppImages.rectangle),
                  fit: BoxFit.cover,
                ),
              ),
              child: Image.asset(AppImages.settings2, fit: BoxFit.contain),
            ),
          ),
          // Image.asset(AppImages.settings2, width: 28, height: 28),
          SizedBox(width: 5),

          Container(
            padding: EdgeInsets.all(6),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(AppImages.rectangle),
                fit: BoxFit.cover,
              ),
            ),
            child: Image.asset(AppImages.filter, fit: BoxFit.contain),
          ),

          Spacer(),

          Container(
            padding: EdgeInsets.all(6),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(AppImages.rectangle),
                fit: BoxFit.cover,
              ),
            ),
            child: Image.asset(AppImages.memory, fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }
}
