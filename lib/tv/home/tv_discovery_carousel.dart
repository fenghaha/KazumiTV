import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/widgets/tv_poster.dart';

/// A single, stable remote target: Right browses, Select opens, and Left at
/// the first recommendation falls through to the home pane's sidebar exit.
class TvDiscoveryCarousel extends StatefulWidget {
  const TvDiscoveryCarousel({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<BangumiItem> items;
  final Future<void> Function(BangumiItem) onOpen;

  @override
  State<TvDiscoveryCarousel> createState() => _TvDiscoveryCarouselState();
}

class _TvDiscoveryCarouselState extends State<TvDiscoveryCarousel>
    with WidgetsBindingObserver {
  static const _interval = Duration(seconds: 8);
  final _focus = FocusNode(debugLabel: 'tv-discovery-carousel');
  List<BangumiItem> _items = [];
  int _index = 0;
  Timer? _timer;
  bool _opening = false;
  bool _hovered = false;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _updateItems();
    _timer = Timer.periodic(_interval, (_) => _autoAdvance());
  }

  @override
  void didUpdateWidget(covariant TvDiscoveryCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateItems();
  }

  void _updateItems() {
    final currentId = _items.isEmpty ? null : _items[_index].id;
    final seen = <int>{};
    _items = widget.items.where((item) => seen.add(item.id)).take(6).toList();
    final retained = _items.indexWhere((item) => item.id == currentId);
    _index = retained >= 0 ? retained : 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
  }

  void _autoAdvance() {
    if (!mounted ||
        !_resumed ||
        _opening ||
        _hovered ||
        _focus.hasFocus ||
        _items.length < 2 ||
        MediaQuery.disableAnimationsOf(context) ||
        ModalRoute.of(context)?.isCurrent == false ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    // Don't keep replacing the recommendation while the viewer browses shelves.
    final scroll = Scrollable.maybeOf(context);
    if (scroll != null && scroll.position.pixels > 24) return;
    _move(1);
  }

  void _move(int delta) {
    if (_items.length < 2 || _opening) return;
    setState(() => _index = (_index + delta) % _items.length);
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _items.length > 1) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _index > 0) {
      _move(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _open() async {
    if (_opening || _items.isEmpty) return;
    _opening = true;
    try {
      await widget.onOpen(_items[_index]);
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final item = _items[_index];
    final multiple = _items.length > 1;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        final height = compact ? 260.0 : 280.0;
        final posterWidth = compact ? 182.0 : 206.0;
        return MouseRegion(
          onEnter: (_) => _hovered = true,
          onExit: (_) => _hovered = false,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _key,
            child: TvFocusable(
              key: const ValueKey('tv-discovery-feature'),
              focusNode: _focus,
              onPressed: () => unawaited(_open()),
              semanticLabel:
                  '${tvBangumiTitle(item)}，${_index + 1}/${_items.length}，'
                  '${multiple ? '左右切换推荐，' : ''}确认查看番剧',
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(20),
              focusedColor: const Color(0xFF263D54),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF20384F), Color(0xFF142235)],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: posterWidth + 64,
                        child: AnimatedSwitcher(
                          duration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 320),
                          child: NetworkImgLayer(
                            key: ValueKey(item.id),
                            src: item.images['large'] ?? item.images['common'],
                            width: posterWidth + 64,
                            height: height,
                            borderRadius: BorderRadius.zero,
                            fadeInDuration: reducedMotion
                                ? Duration.zero
                                : null,
                            fadeOutDuration: reducedMotion
                                ? Duration.zero
                                : null,
                          ),
                        ),
                      ),
                      Positioned(
                        right: posterWidth,
                        top: 0,
                        bottom: 0,
                        width: 64,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF1B3045), Color(0x001B3045)],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          22,
                          posterWidth + 36,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Fade only the artwork: text and the focus/activation
                            // target always refer to exactly the same subject.
                            Text(
                              tvBangumiTitle(item),
                              key: const ValueKey('tv-discovery-title'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 27 : 32,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (item.ratingScore > 0 || item.airDate.isNotEmpty)
                              Text(
                                [
                                  if (item.ratingScore > 0)
                                    '★ ${item.ratingScore.toStringAsFixed(1)}',
                                  if (item.airDate.isNotEmpty) item.airDate,
                                ].join('   '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFFEBC889),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Text(
                                item.summary.trim().isEmpty
                                    ? '发现下一部喜欢的故事。'
                                    : item.summary,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.45,
                                  color: Color(0xFFBDCBDA),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow_rounded, size: 23),
                                SizedBox(width: 5),
                                Text(
                                  '查看番剧',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                for (var i = 0; i < _items.length; i++)
                                  Container(
                                    margin: const EdgeInsets.only(right: 5),
                                    width: i == _index ? 22 : 6,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: i == _index
                                          ? const Color(0xFFEBC889)
                                          : const Color(0xFF64778C),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_index + 1} / ${_items.length}',
                                  key: const ValueKey('tv-discovery-page'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFBDCBDA),
                                  ),
                                ),
                                if (multiple) ...[
                                  const SizedBox(width: 16),
                                  const Flexible(
                                    child: Text(
                                      '← → 切换推荐',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFFBDCBDA),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
