import 'dart:async';

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
    required this.duration,
    required this.danmakuEnabled,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onSeekBy,
    required this.onEpisodes,
    required this.onNext,
    required this.onToggleDanmaku,
    required this.onDanmakuSources,
    required this.onDetails,
    required this.onBack,
    this.busy = false,
  });

  final FocusNode playbackFocus;
  final String title;
  final bool playing;
  final Duration position;
  final Duration duration;
  final bool danmakuEnabled;
  final VoidCallback onTogglePlayback;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekBy;
  final Future<void> Function() onEpisodes;
  final VoidCallback onNext;
  final VoidCallback onToggleDanmaku;
  final Future<void> Function() onDanmakuSources;
  final Future<void> Function() onDetails;
  final VoidCallback onBack;
  final bool busy;

  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  final _playFocus = FocusNode(debugLabel: 'TV playback toggle');
  final _actionFocus = List.generate(
    5,
    (index) => FocusNode(debugLabel: 'TV player action ${index + 1}'),
  );
  List<FocusNode> get _actionNodes => [_playFocus, ..._actionFocus];
  final _seekControl = GlobalKey<TvSliderTileState>();
  Timer? _initialTimer;
  Timer? _seekHintTimer;
  bool _visible = false;
  bool _seekHint = false;
  bool _modalOpen = false;
  bool _disposing = false;
  DateTime? _lastSeek;
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
    FocusManager.instance.addEarlyKeyEventHandler(_handleRemote);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showControls();
      _initialTimer = Timer(const Duration(seconds: 5), _hideControls);
    });
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
    if (!_visible) setState(() => _visible = true);
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
    if (_seekControl.currentState?.isEditing == true) {
      _seekControl.currentState!.finishEditing();
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
    widget.onSeekBy(Duration(seconds: seconds));
    if (!_visible) {
      setState(() => _seekHint = true);
      _seekHintTimer?.cancel();
      _seekHintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _seekHint = false);
      });
    }
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
    // Keep the six action buttons reachable even when Wrap changes rows or the
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
    // Other controls retain normal vertical traversal and slider editing.
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
    _back?.unregisterOverlay(this);
    FocusManager.instance.removeEarlyKeyEventHandler(_handleRemote);
    _initialTimer?.cancel();
    _seekHintTimer?.cancel();
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
  }) => TvFocusable(
    onPressed: onPressed,
    focusNode: focusNode,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 18)),
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
                padding: const EdgeInsets.only(bottom: 50),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xEB101C2C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      '${_time(widget.position)} / ${_time(widget.duration)}',
                      style: const TextStyle(
                        fontSize: 26,
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
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x55000000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 24, 36, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _button('收起菜单', Icons.arrow_back_rounded, _hideControls),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 25,
                        color: Color(0xFFF5F1E8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xF0101C2C),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            _time(widget.position),
                            style: const TextStyle(fontSize: 19),
                          ),
                          Expanded(
                            child: TvSliderTile(
                              key: _seekControl,
                              title: const Text('播放进度'),
                              valueLabel: _time(widget.position),
                              value: widget.position.inMilliseconds
                                  .toDouble()
                                  .clamp(0.0, max),
                              min: 0,
                              max: max,
                              divisions: (widget.duration.inSeconds ~/ 10)
                                  .clamp(1, 100000),
                              enabled:
                                  !widget.busy &&
                                  widget.duration > Duration.zero,
                              onChanged: (value) => widget.onSeek(
                                Duration(milliseconds: value.round()),
                              ),
                            ),
                          ),
                          Text(
                            _time(widget.duration),
                            style: const TextStyle(fontSize: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
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
                            () =>
                                unawaited(_openPanel(widget.onDanmakuSources)),
                            focusNode: _actionFocus[3],
                          ),
                          _button(
                            '播放信息',
                            Icons.info_outline_rounded,
                            () => unawaited(_openPanel(widget.onDetails)),
                            focusNode: _actionFocus[4],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '返回收起菜单 · 连按两次返回退出播放 · 左右快进 / 后退 10 秒',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFFAAB9CB),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
