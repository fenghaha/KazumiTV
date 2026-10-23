import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/danmaku_source_sheet.dart';
import 'package:kazumi/pages/settings/sync/bangumi_sync_page.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_page.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/tv/input/tv_text_input.dart';
import 'package:kazumi/tv/platform/tv_native_input.dart';
import 'package:kazumi/tv/tv_mode.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _UnusedDownloads implements DownloadController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements HttpClientAdapter {
  String? keyword;
  Map<String, dynamic> headers = {};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    keyword = options.queryParameters['anime'] as String?;
    headers = options.headers;
    return ResponseBody.fromString(
      '{"animes":[],"hasMore":false}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('tv_real_pages');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() {
    TvMode.enabled = true;
    BangumiSyncService().resetForTesting();
  });
  tearDown(() {
    TvMode.enabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvNativeInput.channel, null);
  });
  Future<void> open(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TvTheme.dark,
        navigatorObservers: [KazumiDialog.observer],
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> focus(WidgetTester tester, String label) async {
    final tile = find
        .ancestor(
          of: find.text(label).first,
          matching: find.byType(TvFocusable),
        )
        .first;
    Focus.of(
      tester.element(
        find.descendant(of: tile, matching: find.byType(GestureDetector)).first,
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'actual sync page shows complete second card and can return to intro in a narrow TV pane',
    (tester) async {
      await open(
        tester,
        const Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: 650, child: SyncSettingsPage()),
        ),
      );
      await focus(tester, 'Bangumi · 追番同步');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.text('确认键 · 设置 WebDAV')).dy,
        lessThanOrEqualTo(540),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('让追番保持同步')).dy, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'actual configured Bangumi switch responds to OK and saves off state',
    (tester) async {
      await tester.runAsync(() async {
        await GStorage.putSetting(
          SettingsKeys.bangumiAccessToken,
          'fixture-token',
        );
        await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
      });
      await open(
        tester,
        const Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: 650, child: BangumiSyncPage()),
        ),
      );
      await focus(tester, '自动同步追番');
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(GStorage.getSetting(SettingsKeys.bangumiSyncEnable), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'actual player danmaku search opens native editor, cancel stays in sheet, submitted text reaches request',
    (tester) async {
      await tester.runAsync(() => GStorage.putSetting(SettingsKeys.privateMode, true));
      await tester.runAsync(() => GStorage.putSetting(
          SettingsKeys.danmakuApiBaseUrl, 'https://fixture.invalid/danmaku'));
      final controller = PlayerDanmakuController(
        isLocalPlayback: () => false,
        downloadController: _UnusedDownloads(),
      );
      final adapter = _Adapter();
      DioFactory.danmakuCustomDio.httpClientAdapter = adapter;
      String? result;
      var edits = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvNativeInput.channel, (call) async {
            edits++;
            return result;
          });
      await open(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDanmakuSourceSheet(
                context,
                bangumiId: 999,
                initialKeyword: '原关键词',
                danmakuController: controller,
                onBeforeApply: () {},
              ),
              child: const Text('弹幕搜索'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('弹幕搜索'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      final input = tester.widget<TvTextInput>(find.byType(TvTextInput));
      Focus.of(tester.element(find.text('原关键词'))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(find.text('选择弹幕源'), findsOneWidget);
      expect(input.controller.text, '原关键词');
      result = '新的搜索词';
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(edits, 2);
      expect(adapter.keyword, '新的搜索词');
      expect(adapter.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-appid')));
      expect(adapter.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-signature')));
      expect(find.text('未找到番剧'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
