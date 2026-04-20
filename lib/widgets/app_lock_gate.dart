import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/app_lock_controller.dart';

/// Full-screen overlay when [AppLockController.isLocked] is true.
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = Get.find<AppLockController>();
    return Obx(() {
      if (!lock.isLocked.value) return child;
      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.97),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'text_app_locked'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'KumbhSans',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'text_pin_or_biometrics_required'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'KumbhSans',
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Obx(() {
                          final err = lock.authError.value;
                          if (err == null || err.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              err,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'KumbhSans',
                                fontSize: 13,
                                color: Colors.red.shade200,
                              ),
                            ),
                          );
                        }),
                        SizedBox(
                          width: 280,
                          child: ElevatedButton(
                            onPressed: () =>
                                lock.authenticate(isColdStart: false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF007AFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'text_unlock'.tr,
                              style: TextStyle(
                                fontFamily: 'KumbhSans',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
