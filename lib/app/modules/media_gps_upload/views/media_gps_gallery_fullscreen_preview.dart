import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/modules/media_gps_upload/controllers/media_gps_upload_controller.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_gallery_asset_pages.dart';
import 'package:spacetime/app/widgets/keep_alive_page.dart';

class MediaGpsGalleryFullscreenPreview extends StatefulWidget {
  const MediaGpsGalleryFullscreenPreview({super.key, required this.initialIndex});

  final int initialIndex;

  @override
  State<MediaGpsGalleryFullscreenPreview> createState() =>
      _MediaGpsGalleryFullscreenPreviewState();
}

class _MediaGpsGalleryFullscreenPreviewState
    extends State<MediaGpsGalleryFullscreenPreview> {
  late final PageController _pageController;
  late int _pageIndex;

  MediaGpsUploadController get _c => Get.find<MediaGpsUploadController>();

  Widget _buildPage(MediaGpsPickedAsset picked, int index) {
    return MediaGpsAssetPage(
      picked: picked,
      isActive: index == _pageIndex,
      fit: BoxFit.contain,
      placeholderColor: Colors.black,
    );
  }

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.initialIndex;
    _pageController = PageController(
      initialPage: widget.initialIndex,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Obx(() {
            final assets = _c.galleryAssets;
            if (assets.isEmpty) {
              return const Center(
                child: Icon(Icons.photo_library_outlined,
                    color: Colors.white54, size: 48),
              );
            }
            return PageView.builder(
              controller: _pageController,
              clipBehavior: Clip.hardEdge,
              onPageChanged: (i) => setState(() => _pageIndex = i),
              itemCount: assets.length,
              itemBuilder: (context, index) {
                final picked = assets[index];
                return KeepAlivePage(
                  child: ColoredBox(
                    color: Colors.black,
                    child: _buildPage(picked, index),
                  ),
                );
              },
            );
          }),
          SafeArea(
            bottom: false,
            child: Obx(() {
              final assets = _c.galleryAssets;
              final i = _pageIndex.clamp(0, assets.isEmpty ? 0 : assets.length - 1);
              final noGps = assets.isNotEmpty && !assets[i].hasGps;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (noGps)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'media_gps_no_gps_badge'.tr,
                          style: AppFonts.bold(11, color: Colors.white),
                        ),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Get.back<void>(),
                  ),
                ],
              );
            }),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Obx(() {
                  final assets = _c.galleryAssets;
                  if (assets.isEmpty) return const SizedBox.shrink();
                  final i = _pageIndex.clamp(0, assets.length - 1);
                  final id = assets[i].id;
                  final sel = _c.isSelected(id);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        trKey('media_gps_gallery_position_of_total', [
                          i + 1,
                          assets.length,
                        ]),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => _c.toggleAssetSelection(id),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white70, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: sel
                              ? Image.asset(
                                  'assets/images/ic_tick.png',
                                  width: 32,
                                  height: 32,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
