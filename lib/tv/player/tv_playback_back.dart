import 'dart:async';

import 'package:flutter/material.dart';

enum TvBackOrigin { key, system, button }

/// One owner for a playback route, even while its controls are loading/absent.
class TvPlaybackBackController extends ChangeNotifier {
  TvPlaybackBackController({required this.exit});
  final VoidCallback exit;
  bool Function()? _consumeOverlay;
  Object? _overlayOwner;
  Timer? _confirmation;
  Timer? _duplicateWindow;
  TvBackOrigin? _lastOrigin;
  bool _exiting = false;
  bool get awaitingSecondBack => _confirmation?.isActive == true;

  void registerOverlay(Object owner, bool Function() consume) {
    _overlayOwner = owner;
    _consumeOverlay = consume;
  }

  void unregisterOverlay(Object owner) {
    if (identical(owner, _overlayOwner)) {
      _overlayOwner = null;
      _consumeOverlay = null;
    }
  }

  void cancelExit() {
    if (!awaitingSecondBack) return;
    _confirmation?.cancel();
    _confirmation = null;
    notifyListeners();
  }

  void request(TvBackOrigin origin) {
    debugPrint(
      '[KazumiTV Back] origin=${origin.name} armed=$awaitingSecondBack exiting=$_exiting',
    );
    if (_exiting) return;
    // Some Android remotes can deliver a key plus a platform pop for one press.
    // Only coalesce cross-channel events; two real presses on the same channel
    // still count, and held KeyRepeatEvents are rejected by the key handler.
    final paired =
        (_lastOrigin == TvBackOrigin.key && origin == TvBackOrigin.system) ||
        (_lastOrigin == TvBackOrigin.system && origin == TvBackOrigin.key);
    if (paired && _duplicateWindow?.isActive == true) {
      debugPrint('[KazumiTV Back] paired event ignored');
      return;
    }
    _lastOrigin = origin;
    _duplicateWindow?.cancel();
    _duplicateWindow = Timer(const Duration(milliseconds: 300), () {});
    if (_consumeOverlay?.call() == true) {
      debugPrint('[KazumiTV Back] overlay consumed');
      cancelExit();
      return;
    }
    if (awaitingSecondBack) {
      cancelExit();
      debugPrint('[KazumiTV Back] exit confirmed');
      _exiting = true;
      exit();
      return;
    }
    debugPrint('[KazumiTV Back] waiting for second press');
    _confirmation = Timer(const Duration(seconds: 2), () {
      _confirmation = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void exitCancelled() {
    _exiting = false;
  }

  @override
  void dispose() {
    _confirmation?.cancel();
    _duplicateWindow?.cancel();
    super.dispose();
  }
}

class TvPlaybackBackScope extends InheritedWidget {
  const TvPlaybackBackScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final TvPlaybackBackController controller;
  static TvPlaybackBackController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TvPlaybackBackScope>()
      ?.controller;
  @override
  bool updateShouldNotify(TvPlaybackBackScope oldWidget) =>
      controller != oldWidget.controller;
}

class TvPlaybackBackBoundary extends StatefulWidget {
  const TvPlaybackBackBoundary({super.key, required this.child});
  final Widget child;
  @override
  State<TvPlaybackBackBoundary> createState() => TvPlaybackBackBoundaryState();
}

class TvPlaybackBackBoundaryState extends State<TvPlaybackBackBoundary> {
  late final _controller = TvPlaybackBackController(exit: _exit);
  bool _allowExit = false;

  void requestBack([TvBackOrigin origin = TvBackOrigin.button]) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _controller.request(origin);
  }

  void _exit() {
    setState(() => _allowExit = true);
    // Apply PopScope's notifier before asking the navigator to pop the route.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != false) {
        await Navigator.of(context).maybePop();
      }
      if (mounted) {
        _controller.exitCancelled();
        setState(() => _allowExit = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvPlaybackBackScope(
    controller: _controller,
    child: PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) requestBack(TvBackOrigin.system);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.awaitingSecondBack
                ? Positioned(
                    left: 24,
                    right: 24,
                    bottom: 36,
                    child: IgnorePointer(
                      child: Center(
                        child: Semantics(
                          liveRegion: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xEE101C2C),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              child: Text(
                                '再按一次返回退出播放',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}
