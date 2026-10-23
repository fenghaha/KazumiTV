import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/tv/settings/tv_rule_subscriptions.dart';

Plugin rule(String name, String version) => Plugin.fromTemplate()
  ..name = name
  ..version = version;
void main() {
  test('URL import persists sources across service recreation and updates only bound names', () async {
    var stored = <String>[];
    var content = jsonEncode([
      rule('Home', '1.0').toJson(),
      rule('Other', '1.0').toJson(),
    ]);
    var downloads = 0;
    TvRuleSubscriptions service() => TvRuleSubscriptions(
      read: () => stored,
      write: (value) async => stored = value,
      fetch: (_) async {
        downloads++;
        return content;
      },
    );
    final controller = PluginsController(pluginJsonWriter: (_) async {});
    final uri = TvRuleSubscriptions.inputUrl(' http://192.168.0.4:8668/rule ')!;
    final subscriptions = service();
    await subscriptions.install(
      controller,
      (await subscriptions.inspect(uri)).plugins,
      source: uri,
    );
    expect(service().sourceFor('HOME'), uri.toString());
    await subscriptions.remove(controller, controller.pluginList.last);
    content = jsonEncode([
      rule('Home', '2.0').toJson(),
      rule('Other', '2.0').toJson(),
      rule('Unexpected', '1.0').toJson(),
    ]);
    downloads = 0;
    expect(await service().update(controller), contains('订阅更新 1 条'));
    expect(downloads, 1);
    expect(controller.pluginList.map((p) => p.name), ['Home']);
    expect(controller.pluginList.single.version, '2.0');
    content = jsonEncode(rule('Home', '1.0').toJson());
    expect(await service().update(controller), contains('无新版本 1 条'));
    expect(controller.pluginList.single.version, '2.0');
  });

  test(
    'unreachable, wrong-name and newer API feeds preserve the installed rule',
    () async {
      var stored = <String>[];
      var content = '';
      final subscriptions = TvRuleSubscriptions(
        read: () => stored,
        write: (v) async => stored = v,
        fetch: (_) async {
          if (content.isEmpty) throw const SocketException('offline');
          return content;
        },
      );
      final controller = PluginsController(pluginJsonWriter: (_) async {});
      await subscriptions.install(controller, [
        rule('Home', '1.0'),
      ], source: Uri.parse('https://example.test/rule'));
      for (final payload in [
        '',
        '{broken',
        jsonEncode(rule('Wrong', '2.0').toJson()),
        jsonEncode(
          (rule('Home', '2.0')..api = '${ApiEndpoints.apiLevel + 1}').toJson(),
        ),
      ]) {
        content = payload;
        expect(await subscriptions.update(controller), contains('未更新 1 条'));
        expect(controller.pluginList.single.version, '1.0');
      }
    },
  );

  test(
    'same feed is fetched once, and manual imports detach only replaced names',
    () async {
      var stored = <String>[];
      var count = 0;
      final subscriptions = TvRuleSubscriptions(
        read: () => stored,
        write: (v) async => stored = v,
        fetch: (_) async {
          count++;
          return jsonEncode([
            rule('A', '2.0').toJson(),
            rule('B', '2.0').toJson(),
          ]);
        },
      );
      final controller = PluginsController(pluginJsonWriter: (_) async {});
      await subscriptions.install(controller, [
        rule('A', '1.0'),
        rule('B', '1.0'),
      ], source: Uri.parse('http://test/feed'));
      expect(await subscriptions.update(controller), contains('订阅更新 2 条'));
      expect(count, 1);
      await subscriptions.install(controller, [rule('A', '3.0')]);
      expect(subscriptions.sourceFor('A'), isNull);
      expect(subscriptions.sourceFor('B'), 'http://test/feed');
    },
  );

  test(
    'failed rule persistence restores subscription mapping and rules',
    () async {
      var stored = <String>[];
      var fail = false;
      final subscriptions = TvRuleSubscriptions(
        read: () => stored,
        write: (v) async => stored = v,
      );
      final controller = PluginsController(
        pluginJsonWriter: (_) async {
          if (fail) throw StateError('disk');
        },
        errorReporter: (_, error, stack) {},
      );
      await subscriptions.install(controller, [
        rule('A', '1.0'),
      ], source: Uri.parse('http://test/original'));
      fail = true;
      await expectLater(
        subscriptions.install(controller, [
          rule('A', '2.0'),
        ], source: Uri.parse('http://test/new')),
        throwsStateError,
      );
      expect(subscriptions.sourceFor('A'), 'http://test/original');
      expect(controller.pluginList.single.version, '1.0');
    },
  );

  test('HTTP LAN download supports redirect and rejects status, malformed UTF8 and oversize bodies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final payload = jsonEncode(rule('本地', '1.0').toJson());
    server.listen((request) async {
      switch (request.uri.path) {
        case '/redirect':
          request.response.statusCode = 302;
          request.response.headers.set('location', '/rule');
        case '/rule':
          request.response.write(payload);
        case '/huge':
          request.response.add(
            List.filled(TvRuleSubscriptions.maxBytes + 1, 65),
          );
        case '/invalid':
          request.response.add([255, 255]);
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
    Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');
    expect(await TvRuleSubscriptions.download(url('/redirect')), payload);
    await expectLater(
      TvRuleSubscriptions.download(url('/missing')),
      throwsA(isA<HttpException>()),
    );
    await expectLater(
      TvRuleSubscriptions.download(url('/huge')),
      throwsFormatException,
    );
    await expectLater(
      TvRuleSubscriptions.download(url('/invalid')),
      throwsFormatException,
    );
  });
}
