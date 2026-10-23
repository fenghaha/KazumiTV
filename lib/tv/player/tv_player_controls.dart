import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

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
  final VoidCallback onDanmakuSources;
  final VoidCallback onDetails;
  final VoidCallback onBack;
  final bool busy;

  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  final _playFocus = FocusNode(debugLabel: 'TV playback toggle');
  LocalHistoryEntry? _controlsEntry;
  Timer? _initialTimer;
  Timer? _seekHintTimer;
  bool _visible = false;
  bool _seekHint = false;
  bool _modalOpen = false;
  bool _disposing = false;
  DateTime? _lastSeek;

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
    _initialTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _controlsEntry ??= LocalHistoryEntry(
      onRemove: () {
        _controlsEntry = null;
        _entryAttached = false;
        if (mounted && !_disposing) {
          setState(() => _visible = false);
          widget.playbackFocus.requestFocus();
        }
      },
    );
    final route = ModalRoute.of(context);
    if (route != null && !_entryAttached) {
      route.addLocalHistoryEntry(_controlsEntry!);
      _entryAttached = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible && !_modalOpen) _playFocus.requestFocus();
    });
  }

  bool _entryAttached = false;

  void _hideControls() {
    _initialTimer?.cancel();
    if (_disposing) return;
    final entry = _controlsEntry;
    _controlsEntry = null;
    _entryAttached = false;
    entry?.remove();
    if (mounted && _visible) setState(() => _visible = false);
    if (mounted && !_modalOpen) widget.playbackFocus.requestFocus();
  }

  void _toggleAndHide() {
    widget.onTogglePlayback();
    _hideControls();
  }

  Future<void> _openEpisodes() async {
    if (_modalOpen) return;
    _hideControls();
    _modalOpen = true;
    try {
      await widget.onEpisodes();
    } finally {
      _modalOpen = false;
      if (mounted) widget.playbackFocus.requestFocus();
    }
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
        if (_visible) {
          _hideControls();
        } else {
          widget.onBack();
        }
      }
      return KeyEventResult.handled;
    }
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
    // Visible buttons and sliders retain Flutter's normal directional traversal.
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
    FocusManager.instance.removeEarlyKeyEventHandler(_handleRemote);
    _initialTimer?.cancel();
    _seekHintTimer?.cancel();
    _controlsEntry?.remove();
    _playFocus.dispose();
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
  Widget build(BuildContext context) {
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
                  _button('返回', Icons.arrow_back_rounded, widget.onBack),
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
                            child: Slider(
                              value: widget.position.inMilliseconds
                                  .toDouble()
                                  .clamp(0.0, max),
                              max: max,
                              divisions: (widget.duration.inSeconds ~/ 10)
                                  .clamp(1, 100000),
                              onChanged:
                                  widget.busy ||
                                      widget.duration <= Duration.zero
                                  ? null
                                  : (value) => widget.onSeek(
                                      Duration(milliseconds: value.round()),
                                    ),
                              semanticFormatterCallback: (value) =>
                                  _time(Duration(milliseconds: value.round())),
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
                          ),
                          _button(
                            '下一集',
                            Icons.skip_next_rounded,
                            widget.busy ? null : widget.onNext,
                          ),
                          _button(
                            widget.danmakuEnabled ? '弹幕开' : '弹幕关',
                            Icons.subtitles_outlined,
                            widget.onToggleDanmaku,
                          ),
                          _button(
                            '弹幕匹配',
                            Icons.manage_search_rounded,
                            widget.onDanmakuSources,
                          ),
                          _button(
                            '播放信息',
                            Icons.info_outline_rounded,
                            widget.onDetails,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '返回收起控制栏  ·  播放时左右快进 / 后退 10 秒  ·  下键选集',
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
