import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/tv/home/tv_home_data.dart';
import 'package:kazumi/tv/player/tv_playback_back.dart';
import 'package:kazumi/tv/input/tv_text_input.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/widgets/tv_poster.dart';
import 'package:kazumi/tv/widgets/tv_scroll_boundary.dart';

enum _Destination { discover, search, calendar, library, history }

/// TV presentation shell. It consumes the same repositories and controllers as
/// upstream and opens the existing subject/player routes.
class TvHomePage extends StatefulWidget {
  const TvHomePage({
    super.key,
    this.data,
    this.onOpenBangumi,
    this.onResume,
    this.startInSearch = false,
    this.initialQuery = '',
    this.initialLocation = '/tab/popular',
  });

  /// Tests and visual previews may inject data without network or Hive access.
  final TvHomeData? data;
  final Future<void> Function(BangumiItem)? onOpenBangumi;
  final Future<void> Function(History)? onResume;
  final bool startInSearch;
  final String initialQuery;
  final String initialLocation;

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends State<TvHomePage> {
  late final TvHomeData _data = widget.data ?? UpstreamTvHomeData();
  final _searchInput = TextEditingController();
  final _contentFocus = GlobalKey<TvScrollBoundaryState>();
  final _navFocus = List.generate(6, (i) => FocusNode(debugLabel: 'tv-nav-$i'));
  _Destination _destination = _Destination.discover;
  late final int _initialNavIndex;
  int _weekday = DateTime.now().weekday - 1;
  int _collectionType = CollectType.watching.value;
  bool _openingHistory = false;
  RuleCancelToken? _resumeToken;
  double _posterWidth = 150;
  late final TvPlaybackBackController _exitGuard = TvPlaybackBackController(
    exit: () {
      unawaited(SystemNavigator.pop().whenComplete(_exitGuard.exitCancelled));
    },
  );

  bool _consumeHomeBack() {
    if (_openingHistory) {
      setState(_cancelResume);
      return true;
    }
    if (_destination != _Destination.discover) {
      _select(_Destination.discover);
      _navFocus[0].requestFocus();
      return true;
    }
    return false;
  }

  KeyEventResult _homeKey(KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent == false ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) _exitGuard.request(TvBackOrigin.key);
      return KeyEventResult.handled;
    }
    _exitGuard.cancelExit();
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _exitGuard.addListener(_onData);
    _exitGuard.registerOverlay(this, _consumeHomeBack);
    FocusManager.instance.addEarlyKeyEventHandler(_homeKey);
    final startupPath = (Uri.tryParse(widget.initialLocation)?.path ?? '')
        .replaceFirst(RegExp(r'/+$'), '');
    _destination = switch (startupPath) {
      '/tab/timeline' => _Destination.calendar,
      '/tab/collect' => _Destination.library,
      _ => _Destination.discover,
    };
    final searchTakesPriority =
        widget.startInSearch || widget.initialQuery.trim().isNotEmpty;
    if (searchTakesPriority) {
      _destination = _Destination.search;
    }
    _initialNavIndex = _destination.index;
    _data.addListener(_onData);
    unawaited(_data.initialize());
    if (widget.initialQuery.trim().isNotEmpty) {
      _searchInput.text = widget.initialQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submitSearch(widget.initialQuery);
      });
    } else if (startupPath == '/tab/my' && !searchTakesPriority) {
      // Keep a discovery shell underneath settings so Back always has a
      // usable destination, including when settings was the startup page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_settings());
      });
    }
  }

  void _onData() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_homeKey);
    _exitGuard.dispose();
    _resumeToken?.cancel();
    _data.removeListener(_onData);
    if (widget.data == null) _data.dispose();
    _searchInput.dispose();
    for (final node in _navFocus) {
      node.dispose();
    }
    super.dispose();
  }

  void _select(_Destination destination) {
    _exitGuard.cancelExit();
    _cancelResume();
    setState(() => _destination = destination);
    _data.refreshLocal();
  }

  Future<void> _open(BangumiItem item) async {
    _exitGuard.cancelExit();
    if (_openingHistory) setState(_cancelResume);
    final focus = FocusManager.instance.primaryFocus;
    if (widget.onOpenBangumi != null) {
      await widget.onOpenBangumi!(item);
    } else {
      await context.pushNamed('/info', arguments: item);
    }
    if (!mounted) return;
    _data.refreshLocal();
    if (focus != null && focus.context != null && focus.canRequestFocus) {
      focus.requestFocus();
    }
  }

  Future<void> _resume(History history) async {
    if (_openingHistory) return;
    final focus = FocusManager.instance.primaryFocus;
    final token = RuleCancelToken();
    _resumeToken = token;
    setState(() => _openingHistory = true);
    try {
      if (widget.onResume != null) {
        await widget.onResume!(history);
      } else {
        final result = await inject<HistoryPlaybackService>().open(
          history,
          cancelToken: token,
        );
        if (!mounted || token.isCancelled) return;
        switch (result) {
          case HistoryPlaybackReady(:final args):
            await context.pushNamed('/video', arguments: args);
          case HistoryPlaybackUnavailable(:final reason):
            if (!mounted) return;
            await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('需要重新选择播放源'),
                content: Text(reason),
                actions: [
                  TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(_open(history.bangumiItem));
                    },
                    child: const Text('查看番剧'),
                  ),
                ],
              ),
            );
        }
      }
    } catch (_) {
      if (mounted && !token.isCancelled) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法继续播放，请进入番剧重新选择播放源')));
      }
    } finally {
      if (mounted && identical(_resumeToken, token)) {
        _resumeToken = null;
        setState(() => _openingHistory = false);
        _data.refreshLocal();
        if (focus != null && focus.context != null && focus.canRequestFocus) {
          focus.requestFocus();
        }
      }
    }
  }

  void _cancelResume() {
    _resumeToken?.cancel();
    _resumeToken = null;
    _openingHistory = false;
  }

  Future<void> _settings() async {
    _exitGuard.cancelExit();
    if (_openingHistory) setState(_cancelResume);
    await context.pushNamed('/tv/settings');
    if (mounted) _data.refreshLocal();
  }

  void _submitSearch(String text) {
    _exitGuard.cancelExit();
    final query = text.trim();
    if (query.isEmpty) return;
    _searchInput.text = query;
    unawaited(_data.search(query));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && ModalRoute.of(context)?.isCurrent != false) {
          _exitGuard.request(TvBackOrigin.system);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFF101C2C),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1100;
              _posterWidth = compact ? 128 : 150;
              return DefaultTextStyle(
                style: const TextStyle(
                  fontFamily: 'MI_Sans_Regular',
                  color: Color(0xFFF5F1E8),
                  fontSize: 18,
                ),
                child: IconTheme(
                  data: const IconThemeData(color: Color(0xFFF5F1E8), size: 24),
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: Row(
                      children: [
                        Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                              _contentFocus.currentState?.focusContent();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: _navigation(compact),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: TvScrollBoundary(
                                  key: _contentFocus,
                                  onLeft: () => _navFocus[_destination.index]
                                      .requestFocus(),
                                  child: _body(),
                                ),
                              ),
                              _remoteHint(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _navigation(bool compact) {
    const destinations = [
      (Icons.explore_outlined, '发现'),
      (Icons.search_rounded, '搜索'),
      (Icons.calendar_month_outlined, '新番日历'),
      (Icons.bookmark_border_rounded, '我的追番'),
      (Icons.history_rounded, '观看记录'),
      (Icons.settings_outlined, '设置'),
    ];
    return Container(
      width: compact ? 164 : 190,
      color: const Color(0xFF142235),
      padding: const EdgeInsets.fromLTRB(12, 24, 10, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(
              'KazumiTV',
              style: TextStyle(
                fontSize: compact ? 22 : 26,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: TvFocusable(
                        key: ValueKey('tv-nav-$i'),
                        focusNode: _navFocus[i],
                        autofocus: i == _initialNavIndex,
                        selected: i == _destination.index,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        onPressed: () => i == 5
                            ? unawaited(_settings())
                            : _select(_Destination.values[i]),
                        child: Row(
                          children: [
                            Icon(destinations[i].$1, size: 23),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                destinations[i].$2,
                                style: TextStyle(fontSize: compact ? 16 : 18),
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
        ],
      ),
    );
  }

  Widget _remoteHint() => Padding(
    padding: const EdgeInsets.fromLTRB(32, 9, 32, 12),
    child: Row(
      children: [
        if (_openingHistory) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          const Text('正在恢复播放…  返回键取消', style: TextStyle(fontSize: 14)),
        ] else
          Text(
            _exitGuard.awaitingSecondBack
                ? '再按一次返回退出应用'
                : '方向键浏览    确认键打开    连按两次返回退出',
            style: TextStyle(fontSize: 14, color: Color(0xFFAAB9CB)),
          ),
      ],
    ),
  );

  Widget _body() => switch (_destination) {
    _Destination.discover => _discover(),
    _Destination.search => _search(),
    _Destination.calendar => _calendar(),
    _Destination.library => _library(),
    _Destination.history => _history(),
  };

  Widget _scroll(List<Widget> children, {String? keyName}) =>
      SingleChildScrollView(
        key: PageStorageKey(keyName ?? _destination.name),
        padding: const EdgeInsets.fromLTRB(30, 24, 26, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _heading(String title, {String? subtitle}) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Color(0xFFAAB9CB)),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _discover() {
    final today = DateTime.now().weekday - 1;
    final day = today < _data.calendar.length
        ? _data.calendar[today]
        : <BangumiItem>[];
    return _scroll([
      _heading('今晚看什么', subtitle: '发现故事，回到喜欢的世界'),
      if (_data.popular.isNotEmpty) _hero(_data.popular.first),
      if (_data.histories.isNotEmpty)
        _historyShelf('接着看', _data.histories.take(12).toList()),
      if (_data.popularLoading && _data.popular.isEmpty) _loading('正在加载热门番剧'),
      if (_data.popularError.isNotEmpty)
        _message(
          _data.popularError,
          '检查网络后重试，追番与观看记录仍可浏览。',
          action: '重试',
          onPressed: () => unawaited(_data.refreshDiscovery()),
        ),
      if (_data.popular.isNotEmpty) _shelf('大家在看', _data.popular),
      if (day.isNotEmpty) _shelf('今天放送', day),
      if (_data.calendarError.isNotEmpty && day.isEmpty)
        _message(_data.calendarError, '可稍后在新番日历中重试。'),
    ]);
  }

  Widget _hero(BangumiItem item) => Container(
    margin: const EdgeInsets.only(bottom: 24),
    height: 244,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFF1C2C41),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tvBangumiTitle(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Text(
                    item.summary.isEmpty ? '看看这部番剧的故事、播放源和剧集。' : item.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Color(0xFFAAB9CB),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TvFocusable(
                  onPressed: () => unawaited(_open(item)),
                  selected: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 9,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded),
                      SizedBox(width: 6),
                      Text(
                        '查看番剧',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        NetworkImgLayer(
          src: item.images['large'] ?? item.images['common'],
          width: 216,
          height: 244,
          borderRadius: BorderRadius.zero,
        ),
      ],
    ),
  );

  Widget _shelf(String title, List<BangumiItem> items) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(title),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TvPoster(
                    key: ValueKey(item.id),
                    item: item,
                    width: _posterWidth,
                    onPressed: () => unawaited(_open(item)),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _historyShelf(String title, List<History> entries) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(title),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _historyPoster(entry),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _historyPoster(History history) => TvPoster(
    key: ValueKey(history.key),
    item: history.bangumiItem,
    width: _posterWidth,
    subtitle: '继续第 ${history.lastWatchEpisode} 集',
    onPressed: () => unawaited(_resume(history)),
  );

  Widget _grid(List<BangumiItem> items) => Wrap(
    spacing: 12,
    runSpacing: 18,
    children: [
      for (final item in items)
        TvPoster(
          key: ValueKey(item.id),
          item: item,
          width: _posterWidth,
          onPressed: () => unawaited(_open(item)),
        ),
    ],
  );

  Widget _search() => _scroll([
    _heading('找一部想看的番剧'),
    TvTextInput(
      controller: _searchInput,
      label: '番剧名称',
      hintText: '输入名称，或使用手机扫码输入',
      onSubmitted: _submitSearch,
    ),
    const SizedBox(height: 12),
    TvFocusable(
      onPressed: () => _submitSearch(_searchInput.text),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(Icons.search_rounded), SizedBox(width: 8), Text('搜索')],
      ),
    ),
    const SizedBox(height: 24),
    if (_data.query.isEmpty && _data.recentSearches.isNotEmpty) ...[
      _heading('最近搜索'),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final query in _data.recentSearches)
            TvFocusable(
              onPressed: () => _submitSearch(query),
              child: Text(query),
            ),
        ],
      ),
    ],
    if (_data.searchLoading && _data.searchResults.isEmpty) _loading('正在搜索'),
    if (_data.searchError.isNotEmpty)
      _message(
        _data.searchError,
        '你的输入已保留。',
        action: '重试',
        onPressed: () => _submitSearch(_data.query),
      ),
    if (_data.query.isNotEmpty &&
        !_data.searchLoading &&
        _data.searchError.isEmpty &&
        _data.searchResults.isEmpty)
      _message('没有找到“${_data.query}”', '试试中文名、日文名或更短的关键词。'),
    if (_data.searchResults.isNotEmpty) ...[
      _heading('搜索结果', subtitle: '${_data.searchResults.length} 部'),
      _grid(_data.searchResults),
      if (_data.hasMoreSearchResults)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: TvFocusable(
            onPressed: _data.searchLoading
                ? null
                : () => unawaited(_data.search(_data.query, more: true)),
            child: Text(_data.searchLoading ? '正在加载…' : '加载更多'),
          ),
        ),
    ],
  ]);

  Widget _calendar() {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final entries = _weekday < _data.calendar.length
        ? _data.calendar[_weekday]
        : <BangumiItem>[];
    return _scroll([
      _heading('新番日历', subtitle: '本季度放送'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < weekdays.length; i++)
            TvFocusable(
              selected: _weekday == i,
              onPressed: () => setState(() => _weekday = i),
              child: Text(weekdays[i]),
            ),
        ],
      ),
      const SizedBox(height: 24),
      if (_data.calendarLoading) _loading('正在加载新番日历'),
      if (_data.calendarError.isNotEmpty)
        _message(
          _data.calendarError,
          '检查网络后重新加载。',
          action: '重试',
          onPressed: () => unawaited(_data.refreshDiscovery()),
        ),
      if (!_data.calendarLoading &&
          _data.calendarError.isEmpty &&
          entries.isEmpty)
        _message('这一天没有放送记录', '选择其他日期继续看看。'),
      _grid(entries),
    ]);
  }

  Widget _library() {
    final entries = _data.collection
        .where((e) => _collectionType == 0 || e.type == _collectionType)
        .map((e) => e.bangumiItem)
        .toList();
    return _scroll([
      _heading('我的追番', subtitle: '喜欢的故事，都在这里'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in [
            CollectType.none,
            CollectType.watching,
            CollectType.planToWatch,
            CollectType.watched,
            CollectType.onHold,
            CollectType.abandoned,
          ])
            TvFocusable(
              selected: _collectionType == type.value,
              onPressed: () => setState(() => _collectionType = type.value),
              child: Text(type == CollectType.none ? '全部' : type.label),
            ),
        ],
      ),
      const SizedBox(height: 24),
      if (entries.isEmpty)
        _message(
          '这里还没有番剧',
          '在番剧详情里加入追番，之后就能从这里打开。',
          action: '去发现',
          onPressed: () => _select(_Destination.discover),
        ),
      _grid(entries),
    ]);
  }

  Widget _history() => _scroll([
    _heading('观看记录', subtitle: '从上次停下的地方继续'),
    if (_data.histories.isEmpty)
      _message(
        '还没有观看记录',
        '开始播放后，你的进度会自动出现在这里。',
        action: '去发现',
        onPressed: () => _select(_Destination.discover),
      ),
    Wrap(
      spacing: 12,
      runSpacing: 18,
      children: _data.histories.map(_historyPoster).toList(),
    ),
  ]);

  Widget _loading(String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Row(
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 16),
        Text(label, style: const TextStyle(color: Color(0xFFAAB9CB))),
      ],
    ),
  );

  Widget _message(
    String title,
    String detail, {
    String? action,
    VoidCallback? onPressed,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          style: const TextStyle(fontSize: 17, color: Color(0xFFAAB9CB)),
        ),
        if (action != null) ...[
          const SizedBox(height: 14),
          TvFocusable(onPressed: onPressed, child: Text(action)),
        ],
      ],
    ),
  );
}
