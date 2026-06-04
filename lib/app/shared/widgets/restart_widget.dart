import 'package:flutter/widgets.dart';

/// Wraps the app root so it can be soft-restarted without a native process
/// relaunch. Re-keying the subtree forces the whole tree (incl. GetMaterialApp,
/// which starts again at its initial route) to rebuild from scratch.
///
/// This is the reliable cross-platform alternative to `restart_app` on iOS,
/// where Apple forbids true programmatic restarts and the plugin can leave the
/// app stuck on the same page. GetX permanent services (e.g. AppLockController)
/// survive the rebuild, so there is no re-lock hang.
class RestartWidget extends StatefulWidget {
  RestartWidget({required this.child}) : super(key: _restartKey);

  final Widget child;

  static final GlobalKey<_RestartWidgetState> _restartKey =
      GlobalKey<_RestartWidgetState>();

  /// Soft-restarts the app from any context (no BuildContext required).
  static void restartApp() {
    _restartKey.currentState?._restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _subtreeKey = UniqueKey();

  void _restart() {
    setState(() {
      _subtreeKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _subtreeKey, child: widget.child);
  }
}
