import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// One-shot, near-invisible warm-up of the shapes/effects MemoryCard draws
/// repeatedly in Add Memories (rounded rects, a gradient, a circular
/// progress indicator placeholder). Android's Skia backend compiles a
/// shader the first time it draws a given shape/paint combination — with no
/// bundled SkSL warm-up in this project, that first-time compile cost was
/// landing during Add Memories' very first reveal (many cards mounting
/// within ~400ms), contributing to the reported "list is laggy at first,
/// smooths out after a while" symptom independently of any caching.
///
/// This can't precompile every shader MemoryCard might ever need — that
/// requires an on-device `--cache-sksl` capture bundled at build time — but
/// drawing the same primitives once, off the user's path, moves that first
/// paid compile earlier (during app startup) rather than during the first
/// screen the user actually cares about.
///
/// Mounted once from [MyApp]'s `builder`; removes itself after two frames.
class ShaderWarmup extends StatefulWidget {
  const ShaderWarmup({super.key});

  @override
  State<ShaderWarmup> createState() => _ShaderWarmupState();
}

class _ShaderWarmupState extends State<ShaderWarmup> {
  static bool _hasRun = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (_hasRun || kIsWeb || !Platform.isAndroid) return;
    _hasRun = true;
    _visible = true;
    // Paint once, then remove — two frames so the compiled shaders are
    // actually rasterized, not just built into a display list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    // 1x1, top-left corner — technically on-screen (so it actually gets
    // rasterized, unlike Offstage) but imperceptible for two frames.
    return Positioned(
      top: 0,
      left: 0,
      child: SizedBox(
        width: 1,
        height: 1,
        child: ClipRect(
          child: OverflowBox(
            maxWidth: 260,
            maxHeight: 260,
            alignment: Alignment.topLeft,
            child: Stack(
              children: [
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [Colors.black12, Colors.black26],
                    ),
                  ),
                ),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
