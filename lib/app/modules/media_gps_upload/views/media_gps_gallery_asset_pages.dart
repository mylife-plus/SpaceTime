import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

String formatInlineMediaDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class GalleryThumbResult {
  GalleryThumbResult._({this.bytes, this.path});
  final Uint8List? bytes;
  final String? path;

  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
  bool get hasPath => path != null && path!.isNotEmpty;
}

/// In-memory cache so [PageView] swipes do not re-decode gallery assets.
class GalleryStillImageCache {
  GalleryStillImageCache._();
  static final GalleryStillImageCache instance = GalleryStillImageCache._();

  final Map<String, GalleryThumbResult> _byId = {};

  GalleryThumbResult? get(String assetId) => _byId[assetId];

  void put(String assetId, GalleryThumbResult result) {
    _byId[assetId] = result;
  }
}

class GalleryStillPage extends StatefulWidget {
  const GalleryStillPage({
    super.key,
    required this.entity,
    this.fit = BoxFit.cover,
    this.placeholderColor,
  });

  final AssetEntity entity;
  final BoxFit fit;
  final Color? placeholderColor;

  @override
  State<GalleryStillPage> createState() => _GalleryStillPageState();
}

class _GalleryStillPageState extends State<GalleryStillPage>
    with AutomaticKeepAliveClientMixin {
  late Future<GalleryThumbResult> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cached = GalleryStillImageCache.instance.get(widget.entity.id);
    _future = cached != null ? Future.value(cached) : _loadAndCache();
  }

  @override
  void didUpdateWidget(GalleryStillPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entity.id != widget.entity.id) {
      final cached = GalleryStillImageCache.instance.get(widget.entity.id);
      _future = cached != null ? Future.value(cached) : _loadAndCache();
    }
  }

  Future<GalleryThumbResult> _load() async {
    final e = widget.entity;
    final sizes = <ThumbnailSize>[
      const ThumbnailSize(1024, 1024),
      const ThumbnailSize(512, 512),
      const ThumbnailSize(256, 256),
    ];
    for (final s in sizes) {
      try {
        final b = await e.thumbnailDataWithSize(s);
        if (b != null && b.isNotEmpty) {
          return GalleryThumbResult._(bytes: b);
        }
      } catch (_) {}
    }
    try {
      final f = await e.file;
      if (f != null && await f.exists()) {
        return GalleryThumbResult._(path: f.path);
      }
    } catch (_) {}
    return GalleryThumbResult._();
  }

  Future<GalleryThumbResult> _loadAndCache() async {
    final result = await _load();
    GalleryStillImageCache.instance.put(widget.entity.id, result);
    return result;
  }

  Color get _placeholder =>
      widget.placeholderColor ?? Colors.grey.shade300;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<GalleryThumbResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return ColoredBox(
            color: _placeholder,
            child: Center(
              child: CircularProgressIndicator(
                color: _placeholder == Colors.black
                    ? Colors.white54
                    : null,
              ),
            ),
          );
        }
        final r = snap.data ?? GalleryThumbResult._();
        if (r.hasBytes) {
          return Image.memory(
            r.bytes!,
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: _placeholder,
              child: Icon(Icons.broken_image, color: Colors.grey.shade600),
            ),
          );
        }
        if (r.hasPath) {
          return Image.file(
            File(r.path!),
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: _placeholder,
              child: Icon(Icons.broken_image, color: Colors.grey.shade600),
            ),
          );
        }
        return ColoredBox(
          color: _placeholder,
          child: Icon(Icons.image_not_supported, color: Colors.grey.shade600),
        );
      },
    );
  }
}

class GalleryVideoPage extends StatefulWidget {
  const GalleryVideoPage({
    super.key,
    required this.entity,
    required this.isActive,
  });

  final AssetEntity entity;
  final bool isActive;

  @override
  State<GalleryVideoPage> createState() => _GalleryVideoPageState();
}

class _GalleryVideoPageState extends State<GalleryVideoPage>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(GalleryVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _controller?.pause();
    }
  }

  Future<void> _open() async {
    try {
      // entity.file returns null for iCloud-only assets; originFile triggers download.
      var file = await widget.entity.file;
      if (!mounted) return;
      if (file == null) {
        file = await widget.entity.originFile;
        if (!mounted) return;
      }
      if (file == null) {
        setState(() => _failed = true);
        return;
      }
      final vc = VideoPlayerController.file(file);
      _controller = vc;
      await vc.initialize();
      vc.addListener(_onTick);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      c.dispose();
    }
    super.dispose();
  }

  void _togglePlay() {
    final vc = _controller;
    if (vc == null || !vc.value.isInitialized) return;
    setState(() {
      vc.value.isPlaying ? vc.pause() : vc.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_failed) {
      return ColoredBox(
        color: Colors.black26,
        child: Icon(Icons.videocam_off, color: Colors.grey.shade600, size: 46),
      );
    }
    final vc = _controller;
    if (vc == null || !vc.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final ui = Get.find<UiController>();
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: vc.value.size.width,
              height: vc.value.size.height,
              child: VideoPlayer(vc),
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: vc.value.isPlaying ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: IconButton(
            iconSize: 64,
            onPressed: _togglePlay,
            icon: const Icon(
              Icons.play_circle_filled,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  vc,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: ui.currentMainColor,
                    bufferedColor: Colors.white.withValues(alpha: 0.3),
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Icon(
                        vc.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatInlineMediaDuration(vc.value.position),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    const Text(
                      ' / ',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    Text(
                      formatInlineMediaDuration(vc.value.duration),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Thumbnail for gallery or file-picked media.
class MediaGpsThumbTile extends StatelessWidget {
  const MediaGpsThumbTile({super.key, required this.picked});

  final MediaGpsPickedAsset picked;

  @override
  Widget build(BuildContext context) {
    if (picked.isFromFile) {
      return _FileThumbTile(picked: picked);
    }
    final entity = picked.entity;
    if (entity == null) {
      return const ColoredBox(color: Colors.black26);
    }
    return _GalleryEntityThumbTile(entity: entity);
  }
}

class _GalleryEntityThumbTile extends StatelessWidget {
  const _GalleryEntityThumbTile({required this.entity});

  final AssetEntity entity;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: entity.thumbnailDataWithSize(const ThumbnailSize(240, 240)),
      builder: (context, snap) {
        if (snap.hasData && snap.data != null && snap.data!.isNotEmpty) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }
        return _mediaPlaceholder(entity.type);
      },
    );
  }
}

class _FileThumbTile extends StatelessWidget {
  const _FileThumbTile({required this.picked});

  final MediaGpsPickedAsset picked;

  @override
  Widget build(BuildContext context) {
    final path = picked.localPath;
    if (path == null || path.isEmpty) {
      return const ColoredBox(color: Colors.black26);
    }
    if (picked.isVideo) {
      return FutureBuilder<String?>(
        future: VideoThumbnail.thumbnailFile(
          video: path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 240,
          quality: 70,
        ),
        builder: (context, snap) {
          final thumb = snap.data;
          if (thumb != null && thumb.isNotEmpty) {
            return Image.file(File(thumb), fit: BoxFit.cover);
          }
          return _mediaPlaceholder(AssetType.video);
        },
      );
    }
    if (picked.isAudio) {
      return _mediaPlaceholder(AssetType.audio);
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _mediaPlaceholder(AssetType.image),
    );
  }
}

Widget _mediaPlaceholder(AssetType type) {
  return ColoredBox(
    color: Colors.grey.shade300,
    child: Icon(
      type == AssetType.video
          ? Icons.videocam
          : type == AssetType.audio
              ? Icons.audiotrack
              : Icons.image,
      size: 40,
      color: Colors.grey.shade600,
    ),
  );
}

/// Full-screen page for one [MediaGpsPickedAsset].
class MediaGpsAssetPage extends StatelessWidget {
  const MediaGpsAssetPage({
    super.key,
    required this.picked,
    required this.isActive,
    this.fit = BoxFit.cover,
    this.placeholderColor,
  });

  final MediaGpsPickedAsset picked;
  final bool isActive;
  final BoxFit fit;
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    if (picked.isFromFile) {
      final path = picked.localPath;
      if (path == null || path.isEmpty) {
        return const ColoredBox(color: Colors.black26);
      }
      if (picked.isVideo) {
        return FileVideoPage(path: path, isActive: isActive);
      }
      if (picked.isAudio) {
        return FileAudioPage(
          path: path,
          isActive: isActive,
          title: picked.fileTitle,
        );
      }
      return FileStillPage(path: path, fit: fit, placeholderColor: placeholderColor);
    }
    final entity = picked.entity;
    if (entity == null) {
      return const ColoredBox(color: Colors.black26);
    }
    if (entity.type == AssetType.video) {
      return GalleryVideoPage(entity: entity, isActive: isActive);
    }
    if (entity.type == AssetType.audio) {
      return GalleryAudioPage(
        entity: entity,
        isActive: isActive,
        title: picked.fileTitle,
      );
    }
    return GalleryStillPage(
      entity: entity,
      fit: fit,
      placeholderColor: placeholderColor,
    );
  }
}

class FileStillPage extends StatelessWidget {
  const FileStillPage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.placeholderColor,
  });

  final String path;
  final BoxFit fit;
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => ColoredBox(
        color: placeholderColor ?? Colors.grey.shade300,
        child: Icon(Icons.broken_image, color: Colors.grey.shade600),
      ),
    );
  }
}

class FileVideoPage extends StatefulWidget {
  const FileVideoPage({
    super.key,
    required this.path,
    required this.isActive,
  });

  final String path;
  final bool isActive;

  @override
  State<FileVideoPage> createState() => _FileVideoPageState();
}

class _FileVideoPageState extends State<FileVideoPage>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(FileVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _controller?.pause();
    }
  }

  Future<void> _open() async {
    try {
      final vc = VideoPlayerController.file(File(widget.path));
      _controller = vc;
      await vc.initialize();
      vc.addListener(_onTick);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      c.dispose();
    }
    super.dispose();
  }

  void _togglePlay() {
    final vc = _controller;
    if (vc == null || !vc.value.isInitialized) return;
    setState(() {
      vc.value.isPlaying ? vc.pause() : vc.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_failed) {
      return ColoredBox(
        color: Colors.black26,
        child: Icon(Icons.videocam_off, color: Colors.grey.shade600, size: 46),
      );
    }
    final vc = _controller;
    if (vc == null || !vc.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final ui = Get.find<UiController>();
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: vc.value.size.width,
              height: vc.value.size.height,
              child: VideoPlayer(vc),
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: vc.value.isPlaying ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: IconButton(
            iconSize: 64,
            onPressed: _togglePlay,
            icon: const Icon(
              Icons.play_circle_filled,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  vc,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: ui.currentMainColor,
                    bufferedColor: Colors.white.withValues(alpha: 0.3),
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Icon(
                        vc.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatInlineMediaDuration(vc.value.position),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    const Text(
                      ' / ',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    Text(
                      formatInlineMediaDuration(vc.value.duration),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class FileAudioPage extends StatefulWidget {
  const FileAudioPage({
    super.key,
    required this.path,
    required this.isActive,
    this.title,
  });

  final String path;
  final bool isActive;
  final String? title;

  @override
  State<FileAudioPage> createState() => _FileAudioPageState();
}

class _FileAudioPageState extends State<FileAudioPage>
    with AutomaticKeepAliveClientMixin {
  AudioPlayer? _player;
  bool _failed = false;
  bool _loading = true;
  bool _playing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(FileAudioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _player?.pause();
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _prepare() async {
    try {
      final f = File(widget.path);
      if (!await f.exists()) {
        if (mounted) {
          setState(() {
            _failed = true;
            _loading = false;
          });
        }
        return;
      }
      final p = AudioPlayer();
      p.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _playing = state == PlayerState.playing);
      });
      _player = p;
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle() async {
    final p = _player;
    if (p == null) return;
    try {
      if (_playing) {
        await p.pause();
      } else {
        await p.setPlayerMode(PlayerMode.mediaPlayer);
        await p.play(DeviceFileSource(widget.path));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_failed) {
      return ColoredBox(
        color: Colors.black26,
        child: Icon(Icons.audio_file, color: Colors.grey.shade600, size: 56),
      );
    }
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final label = (widget.title ?? '').trim();
    return ColoredBox(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq,
              size: 72, color: Colors.white.withValues(alpha: 0.85)),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ],
          const SizedBox(height: 24),
          IconButton(
            iconSize: 64,
            onPressed: _toggle,
            icon: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.white,
              size: 64,
            ),
          ),
        ],
      ),
    );
  }
}

class GalleryAudioPage extends StatefulWidget {
  const GalleryAudioPage({
    super.key,
    required this.entity,
    required this.isActive,
    this.title,
  });

  final AssetEntity entity;
  final bool isActive;
  final String? title;

  @override
  State<GalleryAudioPage> createState() => _GalleryAudioPageState();
}

class _GalleryAudioPageState extends State<GalleryAudioPage>
    with AutomaticKeepAliveClientMixin {
  AudioPlayer? _player;
  String? _path;
  bool _failed = false;
  bool _loading = true;
  bool _playing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(GalleryAudioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _player?.pause();
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _prepare() async {
    try {
      final file = await widget.entity.file;
      if (!mounted) return;
      if (file == null || !await file.exists()) {
        setState(() {
          _failed = true;
          _loading = false;
        });
        return;
      }
      _path = file.path;
      final p = AudioPlayer();
      p.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _playing = state == PlayerState.playing);
      });
      _player = p;
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle() async {
    final p = _player;
    final path = _path;
    if (p == null || path == null) return;
    try {
      if (_playing) {
        await p.pause();
      } else {
        await p.setPlayerMode(PlayerMode.mediaPlayer);
        await p.play(DeviceFileSource(path));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_failed) {
      return ColoredBox(
        color: Colors.black26,
        child: Icon(Icons.audio_file, color: Colors.grey.shade600, size: 56),
      );
    }
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final label = (widget.title ?? '').trim();
    return ColoredBox(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq, size: 72, color: Colors.white.withValues(alpha: 0.85)),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ],
          const SizedBox(height: 24),
          IconButton(
            iconSize: 64,
            onPressed: _toggle,
            icon: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.white,
              size: 64,
            ),
          ),
        ],
      ),
    );
  }
}
