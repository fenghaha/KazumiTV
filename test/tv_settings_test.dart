import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/tv/settings/tv_rules_page.dart';
import 'package:kazumi/tv/settings/tv_settings_page.dart';
import 'package:kazumi/tv/tv_theme.dart';

Plugin _rule(String name, {bool incompatible = false}) => Plugin.fromTemplate()
  ..name = name
  ..version = '1.0'
  ..api = (ApiEndpoints.apiLevel + (incompatible ? 1 : 0)).toString();

PluginHTTPItem _catalog(String name) => PluginHTTPItem(
  name: name,
  version: '1.0',
  useNativePlayer: true,
  author: 'test',
  lastUpdate: 0,
);

void main() {
  Future<void> open(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: TvTheme.dark, home: page));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'settings exposes TV rules and upstream preferences without overflow',
    (tester) async {
      await open(tester, const TvSettingsPage(), size: const Size(960, 540));
      expect(find.text('KazumiTV'), findsOneWidget);
      expect(find.text('规则与播放源'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog load does not install sources and newer API is rejected',
    (tester) async {
      final writes = <String>[];
      final controller = PluginsController(
        catalogLoader: () async => [_catalog('Future rule')],
        pluginLoader: (_) async => _rule('Future rule', incompatible: true),
        pluginJsonWriter: (json) async => writes.add(json),
        errorReporter: (_, error, stack) {},
      );
      await open(tester, TvRulesPage(controller: controller));
      expect(controller.pluginList, isEmpty);
      expect(writes, isEmpty);
      await tester.tap(find.text('规则商店'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('安装'));
      await tester.pumpAndSettle();
      expect(find.textContaining('需要更高版本客户端'), findsOneWidget);
      expect(controller.pluginList, isEmpty);
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removal requires confirmation and cancellation retains the source',
    (tester) async {
      final writes = <String>[];
      final controller = PluginsController(
        catalogLoader: () async => [],
        pluginJsonWriter: (json) async => writes.add(json),
        errorReporter: (_, error, stack) {},
      )..pluginList.add(_rule('Home source'));
      await open(tester, TvRulesPage(controller: controller));
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留'));
      await tester.pumpAndSettle();
      expect(controller.pluginList.single.name, 'Home source');
      expect(writes, isEmpty);
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认移除'));
      await tester.pumpAndSettle();
      expect(controller.pluginList, isEmpty);
      expect(writes, ['[]']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('import preview excludes incompatible JSON before confirmation', (
    tester,
  ) async {
    final writes = <String>[];
    final controller = PluginsController(
      catalogLoader: () async => [],
      pluginJsonWriter: (json) async => writes.add(json),
      errorReporter: (_, error, stack) {},
    );
    await open(tester, TvRulesPage(controller: controller));
    await tester.tap(find.text('导入规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JSON / kazumi://'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        _rule('Compatible').toJson(),
        _rule('Future', incompatible: true).toJson(),
      ]),
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('可导入 1 条 · 不可导入 1 条'), findsOneWidget);
    expect(find.textContaining('规则需要更高版本客户端'), findsOneWidget);
    expect(writes, isEmpty);
    await tester.tap(find.text('确认导入 1 条'));
    await tester.pumpAndSettle();
    expect(controller.pluginList.map((rule) => rule.name), ['Compatible']);
    expect(writes.length, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
