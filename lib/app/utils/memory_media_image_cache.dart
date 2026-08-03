import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';

/// App-wide decoded-image cache for memory photos.
///
/// Survives [ListView] scroll (card dispose) and [PageView] swipes when combined
/// with [KeepAlivePage] and stable [cacheWidth] for card-sized thumbnails.
class MemoryMediaImageProviderCache {
  MemoryMediaImageProviderCache._();
  static final MemoryMediaImageProviderCache instance =
      MemoryMediaImageProviderCache._();

  final Map<String, ImageProvider> _providers = {};
  String? _documentsRoot;

  /// Resolves app-relative paths (`memory_images/...`) for file I/O.
  Future<void> ensureDocumentsRoot() async {
    _documentsRoot ??= (await getApplicationDocumentsDirectory()).path;
  }

  String resolveStoragePath(String imageData) {
    final normalized = MemoryController.normalizeLocalFilePath(imageData);
    if (normalized.startsWith('/')) return normalized;
    final root = _documentsRoot;
    if (root != null &&
        (normalized.startsWith('memory_images/') ||
            normalized.startsWith('memory_videos/') ||
            normalized.startsWith('memory_audios/'))) {
      return '$root/$normalized';
    }
    return normalized;
  }

  static String cacheKey(String imageData, {int? cacheWidth}) {
    final normalized = MemoryController.normalizeLocalFilePath(imageData);
    return '$normalized@w${cacheWidth ?? 0}';
  }

  static int decodeWidthForLayout(
    BuildContext context, {
    required double layoutHeight,
    double? layoutWidth,
    int maxDecode = 2048,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = layoutWidth ?? layoutHeight;
    final px = w * dpr;
    // Guard against unbounded constraints (double.infinity) or a degenerate
    // 0/NaN layout: `.round()` on Infinity/NaN throws "Infinity or NaN toInt".
    if (!px.isFinite || px <= 0) return maxDecode < 240 ? 240 : maxDecode;
    return px.round().clamp(240, maxDecode);
  }

  ImageProvider resolve(String imageData, {int? cacheWidth}) {
    final key = cacheKey(imageData, cacheWidth: cacheWidth);
    final cached = _providers[key];
    if (cached != null) return cached;
    final created = _createProvider(imageData);
    _providers[key] = created;
    return created;
  }

  /// Drop decoded providers after erase-all / bulk delete.
  void clear() {
    _providers.clear();
  }

  Future<void> precache(
    BuildContext context,
    String imageData, {
    int? cacheWidth,
  }) async {
    if (!_isDisplayableImage(imageData)) return;
    final provider = resolve(imageData, cacheWidth: cacheWidth);
    try {
      await precacheImage(
        cacheWidth != null
            ? ResizeImage(provider, width: cacheWidth)
            : provider,
        context,
      );
    } catch (_) {}
  }

  Widget buildImage({
    required BuildContext context,
    required String imageData,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    int? cacheWidth,
    int? cacheHeight,
    Color? placeholderColor,
    Widget? errorChild,
  }) {
    if (!_isDisplayableImage(imageData)) {
      return errorChild ?? _defaultError(height: height, width: width);
    }

    final decodeW = cacheWidth ??
        (height != null
            ? decodeWidthForLayout(
                context,
                layoutHeight: height,
                layoutWidth: width,
              )
            : null);

    var image = resolve(imageData, cacheWidth: decodeW);
    if (decodeW != null || cacheHeight != null) {
      image = ResizeImage(
        image,
        width: decodeW,
        height: cacheHeight,
      );
    }

    return Image(
      image: image,
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return ColoredBox(
          color: placeholderColor ?? Colors.grey.shade300,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey.shade500,
              ),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) =>
          errorChild ?? _defaultError(height: height, width: width),
    );
  }

  ImageProvider _createProvider(String imageData) {
    if (_isFilePath(imageData)) {
      final path = resolveStoragePath(imageData);
      return FileImage(File(path));
    }
    if (_isBase64Image(imageData)) {
      return MemoryImage(base64Decode(imageData));
    }
    return AssetImage(imageData);
  }

  static bool _isFilePath(String str) {
    return str.startsWith('/') ||
        str.contains('\\') ||
        str.contains('.jpg') ||
        str.contains('.jpeg') ||
        str.contains('.png') ||
        str.contains('.gif') ||
        str.contains('.webp') ||
        str.startsWith('memory_images/');
  }

  static bool _isBase64Image(String imageData) {
    if (imageData.length < 100) return false;
    if (_isFilePath(imageData)) return false;
    try {
      final test =
          imageData.length > 100 ? imageData.substring(0, 100) : imageData;
      base64Decode(test);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isDisplayableImage(String imageData) {
    if (imageData.isEmpty) return false;
    if (_isFilePath(imageData)) {
      return File(resolveStoragePath(imageData)).existsSync();
    }
    return _isBase64Image(imageData) || !imageData.contains('/');
  }

  static Widget _defaultError({double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade300,
      child: Icon(Icons.broken_image, color: Colors.grey.shade600),
    );
  }
}
