import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/network/danmaku_server.dart';

void main() {
  test('Bangumi aliases bridge exact naming differences without fuzzy seasons', () {
    final rows = [
      {'animeId': 3884, 'animeTitle': '东京食尸鬼(2014)【TV动画】from bahamut'},
      {'animeId': 5989, 'animeTitle': '东京食尸鬼√A(2015)【TV动画】from bahamut'},
    ];
    expect(DanmakuServer.exactAnimeId(rows,
        ['東京喰種トーキョーグール', '东京喰种', '东京食尸鬼']), 3884);
  });
  test('compatible server source tags honor existing source switches', () {
    expect(DanmakuServer.sourceLabel('user[bilibili1]'), 'BiliBili');
    expect(DanmakuServer.sourceLabel('user[bahamut]'), 'Gamer');
    expect(DanmakuServer.sourceLabel('[other]'), '[other]');
  });
  test('blank preserves the official endpoint; custom prefixes survive', () {
    expect(DanmakuServer.normalizeBase(''), DanmakuServer.officialBase);
    expect(
      DanmakuServer.normalizeBase(' http://192.168.0.4:8668/danmaku/ '),
      'http://192.168.0.4:8668/danmaku',
    );
    expect(DanmakuServer.isOfficial('https://api.dandanplay.net'), isTrue);
    expect(
      DanmakuServer.isOfficial('https://api.dandanplay.net/token'),
      isFalse,
    );
    expect(
      DanmakuServer.isOfficial('https://api.dandanplay.net.example.com'),
      isFalse,
    );
  });

  test('invalid custom endpoints are rejected before requests', () {
    for (final value in [
      'file:///tmp/comments',
      'https://u:p@example.com',
      'https://example.com?token=x',
      'https://example.com#fragment',
      'not a URL',
    ]) {
      expect(() => DanmakuServer.normalizeBase(value), throwsFormatException);
    }
  });

  test('exact title matches preserve season and dub distinctions', () {
    final rows = [
      {'animeId': 1, 'animeTitle': '葬送的芙莉莲 中配版(2025)【TV动画】from bilibili'},
      {'animeId': 2, 'animeTitle': '葬送的芙莉莲(2023)【TV动画】from bilibili'},
    ];
    expect(DanmakuServer.exactAnimeId(rows, ['葬送的芙莉莲']), 2);
    expect(DanmakuServer.exactAnimeId(rows, ['葬送的芙莉莲 第二季']), 0);
    expect(
      DanmakuServer.exactAnimeId(
        [
          ...rows,
          {'animeId': 3, 'animeTitle': '葬送的芙莉莲(2023)【TV动画】from bahamut'},
        ],
        ['葬送的芙莉莲'],
      ),
      0,
    );
  });

  test('self-hosted episode IDs come from returned metadata', () {
    final rows = [
      {'episodeId': 10030, 'episodeNumber': '1'},
      {'episodeId': 10031, 'episodeNumber': '2'},
    ];
    expect(DanmakuServer.episodeId(rows, 1), 10030);
    expect(DanmakuServer.episodeId(rows.reversed.toList(), 1), 10030);
    expect(DanmakuServer.episodeId(rows, 3), isNull);
    expect(
      DanmakuServer.episodeId([
        ...rows,
        {'episodeId': 999, 'episodeNumber': '1'},
      ], 1),
      isNull,
    );
  });

  test('legacy ordered episodes support explicit bounds', () {
    final rows = [
      {'episodeId': 900},
      {'episodeId': 901},
    ];
    expect(DanmakuServer.episodeId(rows, 1), 900);
    expect(DanmakuServer.episodeId(rows, 0), isNull);
    expect(DanmakuServer.episodeId(rows, 3), isNull);
  });
}
