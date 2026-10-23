import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/version.dart';

/// TV-only source metadata; installed rules still use upstream persistence.
/// URLs may contain private access tokens: never log or echo them in errors.
class TvRuleSubscriptions {
  TvRuleSubscriptions({
    List<String> Function()? read,
    Future<void> Function(List<String>)? write,
    Future<String> Function(Uri)? fetch,
  }) : _read = read ?? (() => GStorage.getStringListSettingByName(_key)),
       _write =
           write ??
           ((value) => GStorage.putStringListSettingByName(_key, value)),
       _fetch = fetch ?? download;

  static const _key = 'kazumitv.ruleSources.v1';
  static const maxBytes = 2 * 1024 * 1024;
  final List<String> Function() _read;
  final Future<void> Function(List<String>) _write;
  final Future<String> Function(Uri) _fetch;

  Map<String, String> _sources() {
    final result = <String, String>{};
    for (final entry in _read()) {
      try {
        final item = jsonDecode(entry) as Map<String, dynamic>;
        final name = item['name'] as String;
        final url = item['url'] as String;
        if (inputUrl(url) != null) result[name] = url;
      } catch (_) {
        // Ignore malformed TV metadata without touching installed upstream rules.
      }
    }
    return result;
  }

  String? sourceFor(String name) => _sources()[pluginNameKey(name)];

  Future<void> _store(Map<String, String> sources) => _write([
    for (final entry in sources.entries)
      jsonEncode({'name': entry.key, 'url': entry.value}),
  ]);

  static Uri? inputUrl(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'\s').hasMatch(value)) {
      throw const FormatException('请填写完整的 HTTP/HTTPS 规则链接');
    }
    return uri.removeFragment();
  }

  Future<PluginImportParseResult> inspect(Uri uri) async {
    final raw = await _fetch(uri);
    // A subscription is rule JSON, not an HTML page containing share links.
    final data = jsonDecode(raw);
    if (data is! Map && data is! List) {
      throw const FormatException('链接未返回规则 JSON');
    }
    final entries = data is List ? data : [data];
    if (entries.any(
      (entry) =>
          entry is! Map ||
          !entry.containsKey('api') ||
          (!entry.containsKey('searchURL') &&
              !entry.containsKey('searchApiConfig')),
    )) {
      throw const FormatException('链接必须返回完整规则，不能是规则商店目录');
    }
    return PluginImportParser.parse(raw);
  }

  Future<void> install(
    PluginsController controller,
    List<Plugin> rules, {
    Uri? source,
  }) async {
    final previous = _sources();
    final next = Map<String, String>.from(previous);
    for (final rule in rules) {
      final key = pluginNameKey(rule.name);
      if (source == null) {
        next.remove(key);
      } else {
        next[key] = source.toString();
      }
    }
    await _store(next);
    try {
      await controller.updatePlugins(rules);
    } catch (_) {
      await _store(previous);
      rethrow;
    }
  }

  Future<void> remove(PluginsController controller, Plugin rule) async {
    final previous = _sources();
    await _store(
      Map<String, String>.from(previous)..remove(pluginNameKey(rule.name)),
    );
    try {
      await controller.removePlugin(rule);
    } catch (_) {
      await _store(previous);
      rethrow;
    }
  }

  /// Refresh only installed, source-bound names. A feed cannot add unrelated
  /// rules, resurrect removed rules, or overwrite rules owned by another feed.
  Future<String> update(PluginsController controller, {String? name}) async {
    final sources = _sources();
    final rules = controller.pluginList
        .where(
          (rule) =>
              sources.containsKey(pluginNameKey(rule.name)) &&
              (name == null || pluginNameKey(rule.name) == pluginNameKey(name)),
        )
        .toList();
    final downloads = <String, PluginImportParseResult?>{};
    var updated = 0, unchanged = 0, rejected = 0;
    for (final local in rules) {
      final url = sources[pluginNameKey(local.name)]!;
      if (!downloads.containsKey(url)) {
        try {
          downloads[url] = await inspect(inputUrl(url)!);
        } catch (_) {
          downloads[url] = null;
        }
      }
      final remote = downloads[url]?.plugins
          .where(
            (rule) => pluginNameKey(rule.name) == pluginNameKey(local.name),
          )
          .firstOrNull;
      if (remote == null) {
        rejected++;
        continue;
      }
      try {
        if (!needUpdate(local.version, remote.version)) {
          unchanged++;
          continue;
        }
        await controller.updatePlugins([remote]);
        updated++;
      } catch (_) {
        rejected++;
      }
    }
    return '订阅更新 $updated 条 · 无新版本 $unchanged 条 · 未更新 $rejected 条'
        '${rejected == 0 ? '' : '（连接失败、内容异常或不兼容，原规则保留）'}';
  }

  static Future<String> download(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = true;
        request.maxRedirects = 5;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw const HttpException('规则地址暂时不可用');
        }
        if (response.contentLength > maxBytes) {
          throw const FormatException('规则内容超过 2 MB');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException('规则内容超过 2 MB');
          }
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      })().timeout(const Duration(seconds: 20));
    } finally {
      client.close(force: true);
    }
  }
}
