import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keeps TV input ahead of delayed native position reports. Only the latest
/// target is submitted after a burst; native seeks never overlap.
class TvSeekController extends ChangeNotifier {
  TvSeekController({
    required Duration position,
    required Duration duration,
    required FutureOr<void> Function(Duration) onSeek,
  }) : _reportedPosition = position,
       _duration = duration,
       _onSeek = onSeek;

  static const inputDelay = Duration(milliseconds: 200);
  static const settleTimeout = Duration(seconds: 10);
  static const positionTolerance = Duration(seconds: 1);

  final FutureOr<void> Function(Duration) _onSeek;
  Duration _reportedPosition;
  Duration _duration;
  Duration? _target;
  Timer? _inputTimer;
  Timer? _settleTimer;
  bool _dragging = false;
  bool _queued = false;
  bool _inFlight = false;
  bool _disposed = false;
  int _revision = 0;

  Duration get position => _clamp(_target ?? _reportedPosition);

  /// Called while the parent rebuilds; the caller already schedules a build.
  void updatePlayback(Duration position, Duration duration) {
    _reportedPosition = position;
    _duration = duration;
    if (duration <= Duration.zero) cancelPending();
    _acknowledgePosition();
  }

  void seekBy(Duration offset) => seekTo(position + offset);

  void seekTo(Duration target) {
    if (_disposed || _duration <= Duration.zero) return;
    _target = _clamp(target);
    _revision++;
    _queued = true;
    _inputTimer?.cancel();
    _settleTimer?.cancel();
    if (!_dragging) _inputTimer = Timer(inputDelay, _flush);
    notifyListeners();
  }

  void beginDrag() {
    _dragging = true;
    _inputTimer?.cancel();
    _inputTimer = null;
    _settleTimer?.cancel();
  }

  void endDrag() {
    _dragging = false;
    if (_queued) {
      unawaited(_flush());
    } else if (!_inFlight) {
      _waitForPosition();
    }
  }

  /// Loading or replacing a source must not submit input from the old source.
  /// The widget's player key separately disposes this controller on replacement.
  void cancelPending() {
    _revision++;
    _queued = false;
    _dragging = false;
    _target = null;
    _inputTimer?.cancel();
    _inputTimer = null;
    _settleTimer?.cancel();
  }

  Future<void> _flush() async {
    _inputTimer = null;
    if (_disposed || _dragging || _inFlight || !_queued) return;
    final target = _clamp(_target!);
    _target = target;
    final revision = _revision;
    _queued = false;
    _inFlight = true;
    var failed = false;
    try {
      await _onSeek(target);
    } catch (_) {
      failed = true;
      debugPrint('TV seek failed; restoring the reported playback position.');
    } finally {
      _inFlight = false;
    }
    if (_disposed) return;
    if (revision == _revision && !_dragging) {
      if (failed) {
        _target = null;
      } else {
        _waitForPosition();
      }
      notifyListeners();
    }
    if (_queued && _inputTimer == null) unawaited(_flush());
  }

  void _waitForPosition() {
    _acknowledgePosition();
    _settleTimer?.cancel();
    if (_target == null) return;
    // A rejected native seek must not pin the UI forever.
    _settleTimer = Timer(settleTimeout, () {
      _target = null;
      notifyListeners();
    });
  }

  void _acknowledgePosition() {
    final target = _target;
    if (target != null &&
        !_dragging &&
        !_queued &&
        (_reportedPosition - target).abs() <= positionTolerance) {
      _target = null;
      _settleTimer?.cancel();
    }
  }

  Duration _clamp(Duration value) => Duration(
    milliseconds: value.inMilliseconds.clamp(
      0,
      _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0,
    ),
  );

  @override
  void dispose() {
    _disposed = true;
    _inputTimer?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }
}
