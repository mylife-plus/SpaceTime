import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/media_gps_upload/controllers/media_gps_upload_controller.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_gallery_asset_pages.dart';

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

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
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
              onPageChanged: (i) => setState(() => _pageIndex = i),
              itemCount: assets.length,
              itemBuilder: (context, index) {
                final picked = assets[index];
                final e = picked.entity;
                if (e.type == AssetType.video) {
                  return GalleryVideoPage(
                    entity: e,
                    isActive: index == _pageIndex,
                  );
                }
                if (e.type == AssetType.audio) {
                  return GalleryAudioPage(
                    entity: e,
                    isActive: index == _pageIndex,
                    title: picked.fileTitle,
                  );
                }
                return GalleryStillPage(entity: e);
              },
            );
          }),
          SafeArea(bottom: false,
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Get.back<void>(),
              ),
            ),
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
