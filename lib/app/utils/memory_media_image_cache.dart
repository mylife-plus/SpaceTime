import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture, compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';

/// Decodes a base64 image string off the main isolate — for a full-size
/// camera photo this can be several MB of base64 text, and `base64Decode`
/// is a synchronous, CPU-bound conversion. Doing it inline on the calling
/// isolate (as [MemoryImage.new] requires its caller to) blocked the UI
/// thread on every first-time render of a base64-stored memory photo,
/// contributing to "Add Memories" scroll jank / ANRs.
Uint8List _decodeBase64Isolate(String data) => base64Decode(data);

/// Like [MemoryImage], but for base64-encoded source strings: defers the
/// (synchronous, CPU-bound) base64 decode into the async image-loading
/// pipeline instead of doing it eagerly on whichever isolate constructs the
/// provider. See [_decodeBase64Isolate].
class _Base64ImageProvider extends ImageProvider<_Base64ImageProvider> {
  const _Base64ImageProvider(this.data);

  final String data;

  @override
  Future<_Base64ImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_Base64ImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _Base64ImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: 'Base64ImageProvider(${data.length} chars)',
    );
  }

  Future<ui.Codec> _loadAsync(
    _Base64ImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await compute(_decodeBase64Isolate, key.data);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is _Base64ImageProvider && other.data == data;
  }

  @override
  int get hashCode => data.hashCode;
}

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
    var w = layoutWidth ?? layoutHeight;
    // `double.infinity` is the normal Flutter idiom for "fill available
    // width" (e.g. SizedBox(width: double.infinity)) — it does NOT mean
    // unknown/unbounded. Treating it as unbounded fell through to the
    // `!px.isFinite` guard below and returned the full maxDecode (2048)
    // uncapped, so every list-view image decoded at up to 2048px wide
    // regardless of how small it actually renders (a ~260px-tall card).
    // Fall back to the real screen width instead, which is what "fill
    // available width" actually resolves to for a full-bleed card.
    if (!w.isFinite) {
      w = MediaQuery.sizeOf(context).width;
    }
    final px = w * dpr;
    // Guard against a degenerate 0/NaN layout: `.round()` on Infinity/NaN
    // throws "Infinity or NaN toInt".
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
    try {
      clearMemoryImageCache();
    } catch (_) {}
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

    final isAndroid = !kIsWeb && Platform.isAndroid;

    // On Android, reduce decode width slightly and apply lower quality for snappy list scrolling
    final rawDecodeW = cacheWidth ??
        (height != null
            ? decodeWidthForLayout(
                context,
                layoutHeight: height,
                layoutWidth: width,
                maxDecode: isAndroid ? 350 : 2048,
              )
            : null);
    final decodeW = isAndroid && rawDecodeW != null ? rawDecodeW.clamp(180, 400) : rawDecodeW;

    var provider = resolve(imageData, cacheWidth: decodeW);
    if (decodeW != null || cacheHeight != null) {
      provider = ResizeImage(
        provider,
        width: decodeW,
        height: cacheHeight,
      );
    }

    if (isAndroid) {
      return ExtendedImage(
        image: provider,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        clearMemoryCacheWhenDispose: false,
        loadStateChanged: (ExtendedImageState state) {
          switch (state.extendedImageLoadState) {
            case LoadState.loading:
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
            case LoadState.failed:
              return errorChild ?? _defaultError(height: height, width: width);
            case LoadState.completed:
              return null;
          }
        },
      );
    }

    return Image(
      image: provider,
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
      // Was MemoryImage(base64Decode(imageData)) — base64Decode of a full
      // camera photo (several MB of base64 text) is synchronous and
      // CPU-bound; calling it eagerly here (on whatever isolate builds the
      // widget) blocked the UI thread on every first-time render of a
      // base64-stored memory photo. _Base64ImageProvider defers the decode
      // into the async image-loading pipeline via compute() instead.
      return _Base64ImageProvider(imageData);
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
