import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';

/// Presentation snapshots only. Network requests, rule compatibility, search
/// parsing, and persistence stay owned by the upstream Kazumi services.
abstract class TvHomeData extends ChangeNotifier {
  List<BangumiItem> popular = [];
  List<List<BangumiItem>> calendar = [];
  List<CollectedBangumi> collection = [];
  List<History> histories = [];
  List<BangumiItem> searchResults = [];
  List<String> recentSearches = [];
  bool popularLoading = false;
  bool calendarLoading = false;
  bool searchLoading = false;
  bool hasMoreSearchResults = false;
  String popularError = '';
  String calendarError = '';
  String searchError = '';
  String query = '';

  Future<void> initialize();
  Future<void> refreshDiscovery();
  void refreshLocal();
  Future<void> search(String query, {bool more = false});
}

class UpstreamTvHomeData extends TvHomeData {
  UpstreamTvHomeData()
    : _collect = inject<ICollectCrudRepository>(),
      _history = inject<IHistoryRepository>(),
      _popular = PopularController(),
      _timeline = TimelineController(inject<ICollectRepository>()),
      _search = SearchPageController(
        inject<ICollectRepository>(),
        inject<ISearchHistoryRepository>(),
      );

  final ICollectCrudRepository _collect;
  final IHistoryRepository _history;
  final PopularController _popular;
  final TimelineController _timeline;
  final SearchPageController _search;
  StreamSubscription<void>? _collectChanges;
  StreamSubscription<void>? _historyChanges;
  bool _disposed = false;
  int _searchGeneration = 0;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> initialize() async {
    refreshLocal();
    _collectChanges = _collect.changes.listen((_) => refreshLocal());
    _historyChanges = _history.changes.listen((_) => refreshLocal());
    _search.loadSearchHistories();
    recentSearches = _search.searchHistories.map((e) => e.keyword).toList();
    await refreshDiscovery();
  }

  @override
  void refreshLocal() {
    if (_disposed) return;
    collection = _collect.getAllCollectibles()
      ..sort((a, b) => b.time.compareTo(a.time));
    histories = _history.getAllHistories();
    _publish();
  }

  @override
  Future<void> refreshDiscovery() async {
    if (popularLoading || calendarLoading || _disposed) return;
    popularLoading = true;
    calendarLoading = true;
    popularError = '';
    calendarError = '';
    _publish();
    await Future.wait([_loadPopular(), _loadCalendar()]);
  }

  Future<void> _loadPopular() async {
    try {
      await _popular.queryBangumiByTrend(type: 'init');
      if (_disposed) return;
      popular = _popular.trendList.toList();
      if (popular.isEmpty) popularError = '热门番剧暂时未能加载';
    } catch (_) {
      popularError = '热门番剧暂时未能加载';
    } finally {
      popularLoading = false;
      _publish();
    }
  }

  Future<void> _loadCalendar() async {
    try {
      await _timeline.loadSeason(DateTime.now());
      if (_disposed) return;
      calendar = _timeline.bangumiCalendar.map((day) => day.toList()).toList();
      if (_timeline.isTimeOut) calendarError = '新番日历暂时未能加载';
    } catch (_) {
      calendarError = '新番日历暂时未能加载';
    } finally {
      calendarLoading = false;
      _publish();
    }
  }

  @override
  Future<void> search(String query, {bool more = false}) async {
    final text = query.trim();
    if (text.isEmpty || _disposed || (more && searchLoading)) return;
    final generation = more ? _searchGeneration : ++_searchGeneration;
    this.query = text;
    searchLoading = true;
    searchError = '';
    if (!more) searchResults = [];
    _publish();
    try {
      await _search.searchBangumi(text, type: more ? 'add' : 'init');
      if (_disposed || generation != _searchGeneration) return;
      searchResults = _search.bangumiList.toList();
      hasMoreSearchResults = _search.hasMoreSearchResults;
      if (_search.isTimeOut && hasMoreSearchResults) {
        searchError = '搜索暂时不可用，请重试';
      }
      recentSearches = _search.searchHistories.map((e) => e.keyword).toList();
    } catch (_) {
      if (generation == _searchGeneration) searchError = '搜索暂时不可用，请重试';
    } finally {
      if (generation == _searchGeneration) {
        searchLoading = false;
        _publish();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _collectChanges?.cancel();
    _historyChanges?.cancel();
    super.dispose();
  }
}
