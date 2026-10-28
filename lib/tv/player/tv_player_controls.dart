import 'dart:async';

import 'package:kazumi/tv/player/tv_frame_monitor.dart';
import 'package:kazumi/tv/player/tv_seek_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/player/tv_playback_back.dart';
import 'package:kazumi/tv/settings/tv_slider_tile.dart';

/// Presentation-only remote adapter. All playback operations are callbacks to
/// the upstream player, so seeking, sync-play and history keep one code path.
class TvPlayerControls extends StatefulWidget {
  const TvPlayerControls({
    super.key,
    required this.playbackFocus,
    required this.title,
    required this.playing,
    required this.position,
    this.reportedPosition,
    required this.duration,
    required this.danmakuEnabled,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onEpisodes,
    required this.onNext,
    required this.onToggleDanmaku,
    required this.onDanmakuSources,
    required this.onDetails,
    required this.onDanmakuSettings,
    required this.onBack,
    this.busy = false,
  });

  final FocusNode playbackFocus;
  final String title;
  final bool playing;
  final Duration position;
  /// Native position, excluding the upstream seek's optimistic UI assignment.
  final Duration? reportedPosition;
  final Duration duration;
  final bool danmakuEnabled;
  final VoidCallback onTogglePlayback;
  final FutureOr<void> Function(Duration) onSeek;
  final Future<void> Function() onEpisodes;
  final VoidCallback onNext;
  final VoidCallback onToggleDanmaku;
  final Future<void> Function() onDanmakuSources;
  final Future<void> Function() onDetails;
  final Future<void> Function() onDanmakuSettings;
  final VoidCallback onBack;
  final bool busy;

  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  final _closeFocus = FocusNode(debugLabel: 'TV player close controls');
  final _playFocus = FocusNode(debugLabel: 'TV playback toggle');
  final _actionFocus = List.generate(
    6,
    (index) => FocusNode(debugLabel: 'TV player action ${index + 1}'),
  );
  List<FocusNode> get _actionNodes => [_playFocus, ..._actionFocus];
  FocusNode? _lastActionFocus;
  final _seekControl = GlobalKey<TvSliderTileState>();
  Timer? _initialTimer;
  Timer? _seekHintTimer;
  bool _visible = false;
  bool _seekHint = false;
  bool _modalOpen = false;
  bool _disposing = false;
  DateTime? _lastSeek;
  late final TvSeekController _seeking;
  TvPlaybackBackController? _back;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TvPlaybackBackScope.of(context);
    if (identical(next, _back)) return;
    _back?.unregisterOverlay(this);
    _back = next;
    _back?.registerOverlay(this, _backWithinPlayer);
  }

  @override
  void initState() {
    super.initState();
    _seeking = TvSeekController(
      position: widget.reportedPosition ?? widget.position,
      duration: widget.duration,
      onSeek: (target) => widget.onSeek(target),
    )..addListener(_onSeekChanged);
    TvFrameMonitor.shared.start();
    FocusManager.instance.addEarlyKeyEventHandler(_handleRemote);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showControls();
      _initialTimer = Timer(const Duration(seconds: 5), _hideControls);
    });
  }

  void _onSeekChanged() {
    if (mounted && !_disposing) setState(() {});
  }

  @override
  void didUpdateWidget(covariant TvPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) _seeking.cancelPending();
    _seeking.updatePlayback(
      widget.reportedPosition ?? widget.position,
      widget.duration,
    );
  }

  bool get _ownsInput {
    if (_modalOpen || ModalRoute.of(context)?.isCurrent == false) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null ||
        (focus != widget.playbackFocus &&
            !focus.ancestors.contains(widget.playbackFocus))) {
      return false;
    }
    final focusContext = focus.context;
    return focusContext == null ||
        (focusContext.widget is! EditableText &&
            focusContext.findAncestorWidgetOfExactType<EditableText>() == null);
  }

  void _showControls() {
    if (!mounted || _disposing) return;
    _back?.cancelExit();
    _initialTimer?.cancel();
    if (!_visible) {
      TvFrameMonitor.shared.capturePlaybackWindow(
        View.of(context).display.refreshRate,
      );
      setState(() => _visible = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _visible &&
          !_modalOpen &&
          ModalRoute.of(context)?.isCurrent != false) {
        _playFocus.requestFocus();
      }
    });
  }

  void _hideControls() {
    _initialTimer?.cancel();
    if (_disposing) return;
    if (mounted && _visible) setState(() => _visible = false);
    if (mounted && !_modalOpen && ModalRoute.of(context)?.isCurrent != false) {
      widget.playbackFocus.requestFocus();
    }
  }

  void _toggleAndHide() {
    widget.onTogglePlayback();
    _hideControls();
  }

  Future<void> _openEpisodes() => _openPanel(widget.onEpisodes);

  Future<void> _openPanel(Future<void> Function() open) async {
    if (_modalOpen) return;
    _back?.cancelExit();
    _initialTimer?.cancel();
    _modalOpen = true;
    try {
      await open();
    } finally {
      _modalOpen = false;
      if (mounted && ModalRoute.of(context)?.isCurrent != false) {
        if (_visible) {
          _playFocus.requestFocus();
        } else {
          widget.playbackFocus.requestFocus();
        }
      }
    }
  }

  bool _backWithinPlayer() {
    if (_modalOpen) return true;
    if (_seekControl.currentState?.isFocused == true) {
      _seekControl.currentState!.blur();
      return true;
    } else if (_visible) {
      _hideControls();
      return true;
    }
    return false;
  }

  void _seekBy(int seconds, {bool repeat = false}) {
    if (widget.busy) return;
    final now = DateTime.now();
    if (repeat &&
        _lastSeek != null &&
        now.difference(_lastSeek!) < const Duration(milliseconds: 160)) {
      return;
    }
    _lastSeek = now;
    _seeking.seekBy(Duration(seconds: seconds));
    if (!_visible) {
      setState(() => _seekHint = true);
      _seekHintTimer?.cancel();
      _seekHintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _seekHint = false);
      });
    }
  }

  bool _canFocus(FocusNode node) =>
      node.context?.mounted == true && node.canRequestFocus;

  bool _moveVertically(LogicalKeyboardKey key) {
    final up = key == LogicalKeyboardKey.arrowUp;
    if (!up && key != LogicalKeyboardKey.arrowDown) return false;
    final seek = _seekControl.currentState;
    if (seek == null) return false;
    if (seek.hasFocus) {
      if (up) {
        _closeFocus.requestFocus();
      } else {
        final last = _lastActionFocus;
        if (last != null && _canFocus(last)) {
          last.requestFocus();
        } else {
          for (final node in _actionNodes) {
            if (_canFocus(node)) {
              node.requestFocus();
              break;
            }
          }
        }
      }
      return true;
    }
    if (_closeFocus.hasFocus) {
      if (!up) seek.requestFocus();
      return true;
    }
    final current = FocusManager.instance.primaryFocus;
    if (!_actionNodes.contains(current)) return false;
    _lastActionFocus = current;
    final rect = current!.rect;
    // Wrap can put buttons on several rows. Traverse the nearest button row
    // first; above the top row, always enter the full-width seek control.
    final candidates = _actionNodes.where((node) {
      if (node == current || !_canFocus(node)) return false;
      return up
          ? node.rect.bottom <= rect.top - 1
          : node.rect.top >= rect.bottom + 1;
    }).toList()
      ..sort((a, b) {
        final aGap = up ? rect.top - a.rect.bottom : a.rect.top - rect.bottom;
        final bGap = up ? rect.top - b.rect.bottom : b.rect.top - rect.bottom;
        final vertical = aGap.compareTo(bGap);
        return vertical != 0
            ? vertical
            : (a.rect.center.dx - rect.center.dx).abs().compareTo(
                (b.rect.center.dx - rect.center.dx).abs(),
              );
      });
    if (candidates.isNotEmpty) {
      candidates.first.requestFocus();
    } else if (up) {
      seek.requestFocus();
    }
    return true;
  }

  KeyEventResult _handleRemote(KeyEvent event) {
    if (!_ownsInput || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    _initialTimer?.cancel();
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (!repeat) {
        if (_back != null) {
          _back!.request(TvBackOrigin.key);
        } else if (_visible) {
          _backWithinPlayer();
        } else {
          widget.onBack();
        }
      }
      return KeyEventResult.handled;
    }
    _back?.cancelExit();
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      if (!repeat &&
          !widget.busy &&
          (key == LogicalKeyboardKey.mediaPlayPause ||
              (key == LogicalKeyboardKey.mediaPlay && !widget.playing) ||
              (key == LogicalKeyboardKey.mediaPause && widget.playing))) {
        widget.onTogglePlayback();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      if (!repeat && !widget.busy) widget.onNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu) {
      if (!repeat) _showControls();
      return KeyEventResult.handled;
    }
    if (_visible && _moveVertically(key)) return KeyEventResult.handled;
    // Keep the seven action buttons reachable even when Wrap changes rows or the
    // surrounding player contributes other spatial focus candidates.
    if (_visible &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      final nodes = _actionNodes;
      final index = nodes.indexOf(FocusManager.instance.primaryFocus!);
      if (index >= 0) {
        final step = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
        for (
          var next = index + step;
          next >= 0 && next < nodes.length;
          next += step
        ) {
          if (nodes[next].context?.mounted == true &&
              nodes[next].canRequestFocus) {
            nodes[next].requestFocus();
            break;
          }
        }
        return KeyEventResult.handled;
      }
    }
    // Other controls retain normal vertical traversal and focused adjustment.
    if (_visible) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-10, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(10, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (!repeat) _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (!repeat) unawaited(_openEpisodes());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      if (!repeat && !widget.busy) {
        widget.onTogglePlayback();
        _showControls();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _disposing = true;
    _seeking.dispose();
    TvFrameMonitor.shared.stop();
    _back?.unregisterOverlay(this);
    FocusManager.instance.removeEarlyKeyEventHandler(_handleRemote);
    _initialTimer?.cancel();
    _seekHintTimer?.cancel();
    _closeFocus.dispose();
    _playFocus.dispose();
    for (final node in _actionFocus) {
      node.dispose();
    }
    super.dispose();
  }

  String _time(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final minutes = seconds ~/ 60;
    return minutes >= 60
        ? '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _button(
    String title,
    IconData icon,
    VoidCallback? onPressed, {
    FocusNode? focusNode,
    bool iconOnly = false,
  }) => TvFocusable(
    onPressed: onPressed,
    focusNode: focusNode,
    semanticLabel: iconOnly ? title : null,
    focusedColor: const Color(0x24FFFFFF),
    padding: iconOnly
        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: iconOnly ? Tooltip(
      message: title,
      child: Icon(icon, size: 20, color: Colors.white),
    ) : Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.white),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(
          fontSize: 16, height: 1.1, color: Colors.white,
        )),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => _back != null
      ? _buildControls(context)
      : PopScope(
          canPop: !_visible,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && !_modalOpen) _backWithinPlayer();
          },
          child: _buildControls(context),
        );

  Widget _buildControls(BuildContext context) {
    if (!_visible) {
      return _seekHint
          ? Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Text(
                      '${_time(_seeking.position)} / ${_time(widget.duration)}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Color(0xFFF5F1E8),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink();
    }
    final max = widget.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Color(0x88000000),
              Color(0xCC000000),
            ],
            stops: [0, .35, 1],
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(24, 18, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _button(
                    '收起菜单',
                    Icons.keyboard_arrow_down_rounded,
                    _hideControls,
                    focusNode: _closeFocus,
                    iconOnly: true,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    _time(_seeking.position),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TvSliderTile(
                      key: _seekControl,
                      parentHandlesBack: true,
                      compact: true,
                      semanticLabel: '播放进度',
                      title: const Text('播放进度'),
                      valueLabel: _time(_seeking.position),
                      value: _seeking.position.inMilliseconds
                          .toDouble()
                          .clamp(0.0, max),
                      min: 0,
                      max: max,
                      divisions: (widget.duration.inSeconds ~/ 10)
                          .clamp(1, 100000),
                      enabled: !widget.busy && widget.duration > Duration.zero,
                      onStep: (delta) => _seeking.seekBy(
                        Duration(milliseconds: delta.round()),
                      ),
                      onChangeStart: (_) => _seeking.beginDrag(),
                      onChangeEnd: (_) => _seeking.endDrag(),
                      onChanged: (value) => _seeking.seekTo(
                        Duration(milliseconds: value.round()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _time(widget.duration),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  _button(
                    widget.playing ? '暂停' : '播放',
                    widget.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    widget.busy ? null : _toggleAndHide,
                    focusNode: _playFocus,
                  ),
                  _button(
                    '选集 / 线路',
                    Icons.grid_view_rounded,
                    () => unawaited(_openEpisodes()),
                    focusNode: _actionFocus[0],
                  ),
                  _button(
                    '下一集',
                    Icons.skip_next_rounded,
                    widget.busy ? null : widget.onNext,
                    focusNode: _actionFocus[1],
                  ),
                  _button(
                    widget.danmakuEnabled ? '弹幕开' : '弹幕关',
                    Icons.subtitles_outlined,
                    widget.onToggleDanmaku,
                    focusNode: _actionFocus[2],
                  ),
                  _button(
                    '弹幕匹配',
                    Icons.manage_search_rounded,
                    () => unawaited(_openPanel(widget.onDanmakuSources)),
                    focusNode: _actionFocus[3],
                  ),
                  _button(
                    '弹幕设置',
                    Icons.tune_rounded,
                    () => unawaited(_openPanel(widget.onDanmakuSettings)),
                    focusNode: _actionFocus[4],
                  ),
                  _button(
                    '播放信息',
                    Icons.info_outline_rounded,
                    () => unawaited(_openPanel(widget.onDetails)),
                    focusNode: _actionFocus[5],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
