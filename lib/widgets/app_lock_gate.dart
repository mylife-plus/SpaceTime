import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/app_lock_controller.dart';

/// Draws the app lock overlay when [AppLockController.isLocked] is true.
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
              color: Colors.black.withValues(alpha: 0.96),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 56,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'SpaceTime is locked',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'KumbhSans',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Use Face ID, Touch ID, or your device PIN to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'KumbhSans',
                          fontSize: 15,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 24),
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
                        width: 220,
                        child: ElevatedButton(
                          onPressed: () => lock.authenticate(isColdStart: false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Unlock',
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
        ],
      );
    });
  }
}
