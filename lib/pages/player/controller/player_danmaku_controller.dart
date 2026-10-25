// ignore_for_file: library_private_types_in_public_api

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/utils/danmaku.dart';
import 'package:kazumi/utils/async_session.dart';

part 'player_danmaku_controller.g.dart';

class PlayerDanmakuController = _PlayerDanmakuController
    with _$PlayerDanmakuController;

enum DanmakuLoadStatus {
  success,
  empty,
  failed,
}

class DanmakuLoadResult {
  const DanmakuLoadResult({
    required this.danmakus,
    required this.bangumiID,
    required this.status,
  });

  factory DanmakuLoadResult.success({
    required List<DanmakuEntry> danmakus,
    required int bangumiID,
  }) {
    return DanmakuLoadResult(
      danmakus: danmakus,
      bangumiID: bangumiID,
      status: danmakus.isEmpty
          ? DanmakuLoadStatus.empty
          : DanmakuLoadStatus.success,
    );
  }

  factory DanmakuLoadResult.failed({
    required int bangumiID,
  }) {
    return DanmakuLoadResult(
      danmakus: const [],
      bangumiID: bangumiID,
      status: DanmakuLoadStatus.failed,
    );
  }

  final List<DanmakuEntry> danmakus;
  final int bangumiID;
  final DanmakuLoadStatus status;

  bool get hasDanmakus => status == DanmakuLoadStatus.success;

  bool get isFailed => status == DanmakuLoadStatus.failed;
}

class DanmakuTimeline {
  static int? resolveSourceSecond(
    Duration playbackPosition,
    double timelineOffsetSeconds,
  ) {
    final sourceMilliseconds = playbackPosition.inMilliseconds -
        (timelineOffsetSeconds * 1000).round();
    if (sourceMilliseconds < 0) {
      return null;
    }
    return Duration(milliseconds: sourceMilliseconds).inSeconds;
  }

  static int staggerDelayMilliseconds({
    required int index,
    required int total,
  }) {
    if (total <= 0) {
      return 0;
    }
    return index * 1000 ~/ total;
  }
}

abstract class _PlayerDanmakuController with Store {
  _PlayerDanmakuController({
    required this.isLocalPlayback,
    required this.downloadController,
  });

  final bool Function() isLocalPlayback;
  final DownloadController downloadController;

  canvas.DanmakuController? _canvasController;

  canvas.DanmakuController get canvasController => _canvasController!;
  set canvasController(canvas.DanmakuController value) =>
      _canvasController = value;

  final Map<int, List<DanmakuEntry>> danDanmakus = {};
  @observable
  bool danmakuOn = false;
  @observable
  bool danmakuLoading = false;

  int bangumiID = 0;
  int _scheduledDanmakuGeneration = 0;
  int? _lastDispatchedSecond;
  final AsyncSessionOwner _manualLoads = AsyncSessionOwner();

  int get scheduledDanmakuGeneration => _scheduledDanmakuGeneration;

  double get timelineOffsetSeconds {
    final offset = GStorage.getSetting(SettingsKeys.danmakuTimeOffset);
    return offset;
  }

  int? resolveDanmakuSecond(Duration playbackPosition) {
    return DanmakuTimeline.resolveSourceSecond(
      playbackPosition,
      timelineOffsetSeconds,
    );
  }

  List<DanmakuEntry> danmakusForPlaybackPosition(Duration playbackPosition) {
    final danmakuSecond = resolveDanmakuSecond(playbackPosition);
    if (danmakuSecond == null) {
      return const [];
    }
    return danDanmakus[danmakuSecond] ?? const [];
  }

  /// A timer tick is not proof that playback advanced. Seek/load/offset changes
  /// reset this cursor explicitly; repeated or jittering position reports do not.
  List<DanmakuEntry> takeDanmakusForPlaybackPosition(Duration playbackPosition) {
    final second = resolveDanmakuSecond(playbackPosition);
    if (second == null ||
        (_lastDispatchedSecond != null && second <= _lastDispatchedSecond!)) {
      return const [];
    }
    final previous = _lastDispatchedSecond;
    _lastDispatchedSecond = second;
    // Cover short gaps caused by timer jitter or playback speed. Large jumps
    // start at the new position rather than flooding the screen with history.
    if (previous != null && second - previous <= 5) {
      return [
        for (var bucket = previous + 1; bucket <= second; bucket++)
          ...?danDanmakus[bucket],
      ];
    }
    return danDanmakus[second] ?? const [];
  }

  @action
  void setDanmakuEnabled(bool value) {
    if (danmakuOn != value) {
      clearAndInvalidateScheduledDanmakus();
    }
    danmakuOn = value;
  }

  void clearAndInvalidateScheduledDanmakus() {
    invalidateScheduledDanmakus();
    _lastDispatchedSecond = null;
    _canvasController?.clear();
  }

  /// Pause/buffering cancels pending emissions without replaying a claimed
  /// second or clearing the already visible, paused canvas.
  void invalidateScheduledDanmakus() {
    _scheduledDanmakuGeneration++;
  }

  /// Called synchronously before native stop/disposal can yield to a late load.
  void cancelPendingDanmakuLoad() {
    _manualLoads.cancel();
    clearAndInvalidateScheduledDanmakus();
    danDanmakus.clear();
    runInAction(() {
      danmakuLoading = false;
      danmakuOn = false;
    });
  }

  void dispose() {
    cancelPendingDanmakuLoad();
    _manualLoads.close();
  }

  // Apply fetched data only after VideoPageController validates the session.
  Future<DanmakuLoadResult> fetchDanmaku(
    int bangumiId,
    String pluginName,
    int episode,
  ) async {
    if (isLocalPlayback()) {
      return await _fetchCachedDanmaku(
        bangumiId,
        pluginName,
        episode,
      );
    }
    return await _fetchDanDanmakuByBgmBangumiID(
      bangumiId,
      episode,
    );
  }

  @action
  void beginDanmakuLoad() {
    _manualLoads.cancel();
    clearAndInvalidateScheduledDanmakus();
    danDanmakus.clear();
    danmakuLoading = true;
  }

  @action
  void applyDanmakuLoad(
    DanmakuLoadResult result, {
    required bool enableDanmaku,
  }) {
    bangumiID = result.bangumiID;
    addDanmakus(result.danmakus);
    danmakuOn = enableDanmaku;
    danmakuLoading = false;
  }

  @action
  void applyUnavailableDanmakuLoad(DanmakuLoadResult result) {
    cancelPendingDanmakuLoad();
    bangumiID = result.bangumiID;
    danDanmakus.clear();
    danmakuOn = false;
    danmakuLoading = false;
  }

  @action
  void finishDanmakuLoad({bool disableDanmaku = false}) {
    if (disableDanmaku) {
      cancelPendingDanmakuLoad();
    }
    danmakuLoading = false;
  }

  Future<DanmakuLoadResult> _fetchCachedDanmaku(
      int bangumiId, String pluginName, int episode) async {
    KazumiLogger().i(
        'PlayerController: attempting to load cached danmaku for episode $episode');
    var nextBangumiID = bangumiID;
    try {
      final cachedDanmakus = await downloadController.getCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
      );

      if (cachedDanmakus != null && cachedDanmakus.isNotEmpty) {
        KazumiLogger().i(
            'PlayerController: loaded ${cachedDanmakus.length} cached danmakus');
        return DanmakuLoadResult.success(
          danmakus: cachedDanmakus,
          bangumiID: nextBangumiID,
        );
      } else {
        KazumiLogger()
            .i('PlayerController: no cached danmaku, attempting online fetch');
        try {
          nextBangumiID =
              await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bangumiId);
          if (nextBangumiID != 0) {
            var res = await DanmakuApi.getDanDanmaku(nextBangumiID, episode);
            if (res.isNotEmpty) {
              KazumiLogger()
                  .i('PlayerController: fetched ${res.length} danmakus online');
              _saveDanmakuToCache(downloadController, bangumiId, pluginName,
                  episode, res, nextBangumiID);
            }
            return DanmakuLoadResult.success(
              danmakus: res,
              bangumiID: nextBangumiID,
            );
          }
        } catch (e) {
          KazumiLogger().w(
              'PlayerController: failed to fetch danmaku online (may be offline)',
              error: e);
          return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
        }
      }
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to load cached danmaku', error: e);
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }
    return DanmakuLoadResult.success(
      danmakus: const [],
      bangumiID: nextBangumiID,
    );
  }

  void _saveDanmakuToCache(
      DownloadController downloadController,
      int bangumiId,
      String pluginName,
      int episode,
      List<DanmakuEntry> danmakus,
      int danDanID) {
    try {
      downloadController.updateCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
        danmakus,
        danDanID,
      );
      KazumiLogger()
          .i('PlayerController: saved ${danmakus.length} danmakus to cache');
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to save danmaku to cache', error: e);
    }
  }

  Future<DanmakuLoadResult> _fetchDanDanmakuByBgmBangumiID(
      int bgmBangumiID, int episode) async {
    KazumiLogger().i(
        'PlayerController: attempting to get danmaku [BgmBangumiID] $bgmBangumiID');
    var nextBangumiID = bangumiID;
    try {
      nextBangumiID =
          await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bgmBangumiID);
      if (nextBangumiID == 0) {
        return DanmakuLoadResult.success(
          danmakus: const [],
          bangumiID: nextBangumiID,
        );
      }
      var res = await DanmakuApi.getDanDanmaku(nextBangumiID, episode);
      return DanmakuLoadResult.success(
        danmakus: res,
        bangumiID: nextBangumiID,
      );
    } catch (e) {
      KazumiLogger().w(
          'PlayerController: failed to get danmaku [BgmBangumiID] $bgmBangumiID',
          error: e);
    }
    return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
  }

  @action
  Future<bool> getDanDanmakuByEpisodeID(int episodeID) async =>
      await loadManualDanmaku(episodeID) ?? false;

  /// Null means superseded/dismissed, so the caller must not change UI state.
  Future<bool?> loadManualDanmaku(
    int episodeID, {
    bool Function()? canApply,
  }) async {
    if (_manualLoads.isClosed) return null;
    KazumiLogger().i('PlayerController: attempting to get danmaku $episodeID');
    beginDanmakuLoad();
    final request = _manualLoads.begin();
    try {
      final res = await DanmakuApi.getDanDanmakuByEpisodeID(episodeID);
      if (request.isStale || !(canApply?.call() ?? true)) return null;
      runInAction(() {
        addDanmakus(res);
        setDanmakuEnabled(res.isNotEmpty);
      });
      return res.isNotEmpty;
    } catch (e) {
      if (request.isStale || !(canApply?.call() ?? true)) return null;
      KazumiLogger().w('PlayerController: failed to get danmaku', error: e);
      rethrow;
    } finally {
      if (request.isActive) {
        runInAction(() => danmakuLoading = false);
      }
    }
  }

  void addDanmakus(List<DanmakuEntry> danmakus) {
    clearAndInvalidateScheduledDanmakus();
    danDanmakus.clear();
    final bool danmakuDeduplicationEnable =
        GStorage.getSetting(SettingsKeys.danmakuDeduplication);

    final List<DanmakuEntry> listToAdd = danmakuDeduplicationEnable
        ? mergeDuplicateDanmakus(danmakus, timeWindowSeconds: 5)
        : danmakus;

    for (final element in listToAdd) {
      final danmakuSecond = element.time.toInt();
      (danDanmakus[danmakuSecond] ??= <DanmakuEntry>[]).add(element);
    }
  }

  void updateDanmakuSpeed(double playerSpeed) {
    final baseDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    final followSpeed = GStorage.getSetting(SettingsKeys.danmakuFollowSpeed);

    final duration = followSpeed ? (baseDuration / playerSpeed) : baseDuration;
    canvasController
        .updateOption(canvasController.option.copyWith(duration: duration));
  }
}
