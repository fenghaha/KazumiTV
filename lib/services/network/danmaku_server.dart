/// Endpoint and matching rules for an optional self-hosted Dandan-compatible API.
/// Keep endpoint configuration separate from upstream rule/video resolution.
class DanmakuServer {
  static const officialBase = 'https://api.dandanplay.net';

  static String normalizeBase(String value) {
    final text = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (text.isEmpty) return officialBase;
    if (RegExp(r'[\x00-\x20\\]').hasMatch(text)) {
      throw const FormatException('服务地址不能包含空格或控制字符');
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入 HTTP(S) 弹幕服务地址，不含查询参数');
    }
    return text;
  }

  static bool isOfficial(String base) =>
      Uri.parse(base).origin == officialBase && Uri.parse(base).path.isEmpty;

  static String titleKey(String value) => value
      .replaceFirst(RegExp(r'\((?:\d{4}|N/A)\).*$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'【.*$'), '')
      .replaceFirst(RegExp(r'\s+from\s+\S+\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();

  /// Ambiguous seasons/dubs stay manual; never pick a fuzzy first search hit.
  static int exactAnimeId(
    Iterable<Map<String, dynamic>> rows,
    Iterable<String> titles,
  ) {
    final keys = titles.where((t) => t.trim().isNotEmpty).map(titleKey).toSet();
    final matches = rows.where(
      (r) => keys.contains(titleKey(r['animeTitle'] as String)),
    );
    final ids = matches.map((r) => r['animeId'] as int).toSet();
    return ids.length == 1 ? ids.single : 0;
  }

  static int? episodeId(List<Map<String, dynamic>> rows, int episode) {
    final numbered = rows.where((r) => r['episodeNumber'] != null).toList();
    if (numbered.isNotEmpty) {
      final matches = numbered
          .where((r) => num.tryParse(r['episodeNumber'].toString()) == episode)
          .toList();
      return matches.length == 1 ? matches.single['episodeId'] as int : null;
    }
    // Older compatible servers return an already ordered episode list.
    return episode > 0 && episode <= rows.length
        ? rows[episode - 1]['episodeId'] as int
        : null;
  }

  static String sourceLabel(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('bilibili')) return 'BiliBili';
    if (lower.contains('bahamut') || lower.contains('gamer')) return 'Gamer';
    return source;
  }
}
