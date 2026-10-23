import 'package:kazumi/modules/danmaku/danmaku_ch_convert.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/network/danmaku_server.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

class DanmakuApi {
  static final DanmakuClient _client = DanmakuClient.instance;
  static String get _base => DanmakuServer.normalizeBase(
    GStorage.getSetting(SettingsKeys.danmakuApiBaseUrl),
  );

  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    if (!DanmakuServer.isOfficial(_base)) {
      // Compatible servers need not implement the official bgmtv mapping API.
      final subject = await BangumiApi.getBangumiInfoByID(bgmBangumiID);
      if (subject == null) throw Exception('获取番剧名称失败，请手动检索弹幕');
      final title = subject.nameCn.isNotEmpty ? subject.nameCn : subject.name;
      final found = await searchAnimes(title);
      return DanmakuServer.exactAnimeId(
        found.animes.map(
          (a) => {'animeId': a.animeId, 'animeTitle': a.animeTitle},
        ),
        [subject.name, subject.nameCn, ...subject.alias],
      );
    }
    final path = ApiEndpoints.formatUrl(
      ApiEndpoints.dandanAPIInfoByBgmBangumiId,
      [bgmBangumiID],
    );
    final endPoint = _base + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData).bangumiId;
  }

  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
    int bangumiID,
  ) async {
    final path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    final endPoint = _base + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData);
  }

  // v2 episode search avoids the anime search's 25-result cap.
  // Fetch full episode lists separately; search results can truncate them.
  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    final endPoint = _base + ApiEndpoints.dandanAPISearchEpisodes;
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {'anime': title, 'v2': 'true'},
    );
    return DanmakuSearchResponse.fromJson(jsonData);
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
    int bangumiID,
    int episode,
  ) async {
    if (bangumiID == 0) {
      return [];
    }
    if (!DanmakuServer.isOfficial(_base)) {
      final json = await _client.get(
        '$_base${ApiEndpoints.dandanAPIInfo}$bangumiID',
      );
      final rows = (json['bangumi']['episodes'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final id = DanmakuServer.episodeId(rows, episode);
      if (id == null) return [];
      return _getComments(id.toString());
    }
    // Preserve the upstream convention only for the official service.
    return _getComments('$bangumiID${episode.toString().padLeft(4, '0')}');
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(int episodeID) =>
      _getComments(episodeID.toString());

  static Future<List<DanmakuEntry>> _getComments(String episodeID) async {
    final endPoint = '$_base${ApiEndpoints.dandanAPIComment}$episodeID';
    final conversion = DanmakuChConvert.fromValue(
      GStorage.getSetting(SettingsKeys.danmakuChConvert),
    );
    KazumiLogger().i('Danmaku: requesting episode comments');
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {
        'withRelated': 'true',
        'chConvert': conversion.value.toString(),
      },
    );
    final List<dynamic> comments = jsonData['comments'];
    return [for (final comment in comments) _entry(comment)];
  }

  static DanmakuEntry _entry(Map<String, dynamic> comment) {
    final entry = DanmakuEntry.fromJson(comment);
    if (!DanmakuServer.isOfficial(_base)) {
      entry.source = DanmakuServer.sourceLabel(entry.source);
    }
    return entry;
  }
}
