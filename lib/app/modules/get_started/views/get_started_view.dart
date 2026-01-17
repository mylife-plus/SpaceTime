import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../ui/controllers/ui_controller.dart';
import '../controllers/get_started_controller.dart';

class GetStartedView extends GetView<GetStartedController> {
  const GetStartedView({super.key});

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Scaffold(
      body: Container(
        width: MediaQuery.sizeOf(context).width,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/Start.jpg'),
            fit: BoxFit.fitWidth,
          ),
        ),
        child: SafeArea(
          child: Obx(() {
            if (controller.showWelcomeAnimation.value) {
              return _buildWelcomeSection(uiController);
          } else if (controller.isNoInternet.value) {
            return _buildNoInternetSection(uiController);
            } else {
              return _buildDownloadSection(uiController);
            }
          }),
        ),
      ),
    );
  }

  /// Build the welcome animation section
  Widget _buildWelcomeSection(UiController uiController) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.4),
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),

            // Welcome to text
            Text(
              'Welcome to',
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontSize: 32,
                fontWeight: FontWeight.w400,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),

            // const SizedBox(height: 8),

            // SpaceTime text
            Text(
              'SpaceTime',
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontSize: 48,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 40),

            // Book icon
            Image.asset(
              'assets/images/book.png',
              width: 120,
              height: 120,
            ),

            const SizedBox(height: 40),

            // "your" text
            Text(
              'your',
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontSize: 28,
                fontWeight: FontWeight.w200,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // "100% offline" text
            Text(
              '100% offline',
              style: GoogleFonts.mako(
                fontSize: 32,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                // shadows: [
                //   Shadow(
                //     color: Colors.black.withValues(alpha: 0.8),
                //     blurRadius: 8,
                //     offset: const Offset(0, 1),
                //   ),
                // ],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 4),

            // "100% open source" text
            Text(
              '100% open source',
              style: GoogleFonts.mako(
                fontSize: 32,
                fontWeight: FontWeight.w400,
                color: Colors.white,
                // shadows: [
                //   Shadow(
                //     color: Colors.black.withValues(alpha: 0.8),
                //     blurRadius: 8,
                //     offset: const Offset(0, 1),
                //   ),
                // ],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // "personal diary app" text
            Text(
              'personal diary app',
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontSize: 28,
                fontWeight: FontWeight.w200,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),

            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }

  /// Build the download section
  Widget _buildDownloadSection(UiController uiController) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.4),
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(Get.context!).size.height - MediaQuery.of(Get.context!).padding.top,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // Welcome to text
                  Text(
                    'Welcome to',
                    style: TextStyle(
                      fontFamily: 'KumbhSans',
                      fontSize: 32,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // SpaceTime text
                  Text(
                    'SpaceTime',
                    style: TextStyle(
                      fontFamily: 'KumbhSans',
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // Book icon
                  Image.asset(
                    'assets/images/book.png',
                    width: 100,
                    height: 100,
                  ),

                  const SizedBox(height: 32),

                  // "your" text
                  Text(
                    'your',
                    style: TextStyle(
                      fontFamily: 'KumbhSans',
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // "100% offline" text
                  Text(
                    '100% offline',
                    style: GoogleFonts.mako(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 4),

                  // "100% open source" text
                  Text(
                    '100% open source',
                    style: GoogleFonts.mako(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // "personal diary app" text
                  Text(
                    'personal diary app',
                    style: TextStyle(
                      fontFamily: 'KumbhSans',
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  // Download text
                  Text(
                    'download 4.5GB of map tiles now',
                    style: TextStyle(
                      fontFamily: 'KumbhSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                // Progress section (only show when downloading)
                Obx(() {
                  if (controller.isDownloading.value) {
                    return Column(
                      children: [
                        _buildProgressCard(uiController),
                        const SizedBox(height: 24),
                      ],
                    );
                  } else {
                    return const SizedBox.shrink();
                  }
                }),

                // Start button
                _buildStartButton(uiController),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  /// Build the progress card
  Widget _buildProgressCard(UiController uiController) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Status text
          Obx(() => Text(
            controller.statusText.value,
            style: TextStyle(
              fontFamily: 'KumbhSans',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          )),

          const SizedBox(height: 4),

          // Progress indicator
          Obx(() {
            if (controller.hasError.value) {
              return _buildErrorState(uiController);
            } else if (controller.isCompleted.value) {
              return _buildCompletedState(uiController);
            } else {
              return _buildProgressState(uiController);
            }
          }),

          // const SizedBox(height: 12),

          // Tile count
          // Obx(() => Text(
          //   '${controller.downloadedTileCount.value} tiles downloaded',
          //   style: TextStyle(
          //     fontFamily: 'KumbhSans',
          //     fontSize: 12,
          //     fontWeight: FontWeight.w400,
          //     color: Colors.white.withValues(alpha: 0.8),
          //     shadows: [
          //       Shadow(
          //         color: Colors.black.withValues(alpha: 0.8),
          //         blurRadius: 6,
          //         offset: const Offset(0, 1),
          //       ),
          //     ],
          //   ),
          // )),
        ],
      ),
    );
  }

  /// Build progress state
  Widget _buildProgressState(UiController uiController) {
    return Obx(() => Column(
      children: [
        LinearProgressIndicator(
          value: controller.downloadProgress.value,
          backgroundColor: Colors.white.withValues(alpha: 0.3),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
          minHeight: 6,
        ),

        const SizedBox(height: 8),

        Text(
          '${(controller.downloadProgress.value * 100).toStringAsFixed(1)}%',
          style: TextStyle(
            fontFamily: 'KumbhSans',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF007AFF),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    ));
  }

  /// Build completed state
  Widget _buildCompletedState(UiController uiController) {
    return Column(
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 32,
          color: Colors.green,
        ),

        const SizedBox(height: 8),

        Text(
          'Download completed!',
          style: TextStyle(
            fontFamily: 'KumbhSans',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.green,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build error state
  Widget _buildErrorState(UiController uiController) {
    return Column(
      children: [
        Icon(
          Icons.error_rounded,
          size: 32,
          color: Colors.red,
        ),

        const SizedBox(height: 8),

        Text(
          'Download failed',
          style: TextStyle(
            fontFamily: 'KumbhSans',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.red,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),

        if (controller.errorMessage.value.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            controller.errorMessage.value,
            style: TextStyle(
              fontFamily: 'KumbhSans',
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.8),
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Build the blue start button
  Widget _buildStartButton(UiController uiController) {
    return Obx(() {
      if (controller.isCompleted.value) {
        // Show "Get Started" button when download is complete
        return Container(
          width: 200,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF007AFF), Color(0xFF0051D5)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF007AFF).withValues(alpha: 0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: controller.navigateToMainApp,
              child: Center(
                child: Text(
                  'Get Started',
                  style: TextStyle(
                    fontFamily: 'KumbhSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      } else if (controller.hasError.value) {
        // Show retry button on error
        return Container(
          width: 200,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF007AFF), Color(0xFF0051D5)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF007AFF).withValues(alpha: 0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: controller.retryDownload,
              child: Center(
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'KumbhSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        // Show "Download Tiles" or "Continue" button based on download status
        return Column(
          children: [
            // Main action button
            Container(
              width: 200,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF0051D5)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(25),
                  onTap: controller.isDownloading.value ? null : controller.startDownload,
                  child: Center(
                    child: controller.isDownloading.value
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Download Tiles',
                            style: TextStyle(
                              fontFamily: 'KumbhSans',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),

            // Skip/Continue button removed - tiles must be downloaded to proceed
            const SizedBox(height: 16),
          ],
        );
      }
    });
  }

  /// Build no internet section
  Widget _buildNoInternetSection(UiController uiController) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.4),
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),

            // Book icon
            Image.asset(
              'assets/images/book.png',
              width: 120,
              height: 120,
            ),

            const SizedBox(height: 40),

            // No Internet message
            Text(
              'Internet Required',
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            // Status text
            Obx(() => Text(
              controller.statusText.value,
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            )),

            const SizedBox(height: 20),

            // Instructions
            Text(
              'Please turn on internet and restart the app',
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontSize: 16,
                fontWeight: FontWeight.w300,
                color: Colors.white.withValues(alpha: 0.8),
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),

            const Spacer(flex: 2),

            // Close button
            Container(
              width: 200,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF0051D5)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(25),
                  onTap: controller.closeApp,
                  child: Center(
                    child: Text(
                      'Close App',
                      style: TextStyle(
                        fontFamily: 'KumbhSans',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

}
