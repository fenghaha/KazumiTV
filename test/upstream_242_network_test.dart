import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/settings/network_mirror_settings.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/dio_logger_interceptor.dart';
import 'package:kazumi/request/core/ech_adapter.dart';
import 'package:kazumi/services/network/rules_mirror.dart';
import 'package:kazumi/services/storage/storage.dart';
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

class _Requests implements HttpClientAdapter {
  RequestOptions? last;
  bool closed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    last = options;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumitv_242_network');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() async {
    TvMode.enabled = false;
    DioFactory.reset();
    await GStorage.resetSettings(SettingsKeys.byGroup(SettingGroup.proxy));
  });
  tearDown(() {
    TvMode.enabled = false;
    DioFactory.reset();
  });

  test('unconfigured rules mirror inherits the legacy switch and explicit mode wins', () async {
    expect(RulesMirror.current, RulesMirror.ghProxy);
    await GStorage.putSetting(SettingsKeys.enableGitProxy, false);
    expect(RulesMirror.current, RulesMirror.direct);
    await GStorage.putSetting(
      SettingsKeys.rulesMirror,
      RulesMirror.gitcode.name,
    );
    expect(RulesMirror.current, RulesMirror.gitcode);
    await GStorage.putSetting(SettingsKeys.enableGitProxy, true);
    expect(RulesMirror.current, RulesMirror.gitcode);
  });

  for (final mode in RulesMirror.values) {
    test(
      'rules mirror ${mode.name} rewrites official repository only',
      () async {
        await GStorage.putSetting(SettingsKeys.rulesMirror, mode.name);
        final dio = DioFactory.rulesRepoDio;
        expect(dio.httpClientAdapter, isA<EchAdapter>());
        final requests = _Requests();
        dio.httpClientAdapter = requests;
        final official = '${ApiEndpoints.pluginShop}index.json';
        await dio.get(official);
        final expected = switch (mode) {
          RulesMirror.ghProxy => '${ApiEndpoints.ghProxyMirror}$official',
          RulesMirror.ghfast => '${ApiEndpoints.ghfastMirror}$official',
          RulesMirror.gitcode => '${ApiEndpoints.gitcodeMirror}index.json',
          RulesMirror.direct => official,
        };
        expect(requests.last!.uri.toString(), expected);
        expect(
          requests.last!.extra['ech'] == true,
          mode == RulesMirror.ghProxy,
        );
        const custom = 'http://media.test/custom-rule?fixture=1';
        await dio.get(custom);
        expect(requests.last!.uri.toString(), custom);
        expect(requests.last!.extra['ech'], isNull);
      },
    );
  }

  test('custom danmaku pool stays non-logging, outside ECH, and resets with network clients', () {
    final custom = DioFactory.danmakuCustomDio;
    expect(identical(custom, DioFactory.danmakuCustomDio), isTrue);
    expect(custom.httpClientAdapter, isA<IOHttpClientAdapter>());
    expect(custom.interceptors.whereType<DioLoggerInterceptor>(), isEmpty);
    expect(custom.options.receiveTimeout, const Duration(seconds: 45));
    final requests = _Requests();
    custom.httpClientAdapter = requests;
    DioFactory.reset();
    expect(requests.closed, isTrue);
    expect(identical(custom, DioFactory.danmakuCustomDio), isFalse);
    expect(DioFactory.bangumiDio.httpClientAdapter, isA<EchAdapter>());
  });

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'TV rules picker confirms, cancels and restores focus at $size',
      (tester) async {
        TvMode.enabled = true;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: TvTheme.dark,
            home: const Scaffold(
              body: SettingsList(sections: [NetworkMirrorSettings()]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tile = find
            .ancestor(
              of: find.text('规则仓库加速'),
              matching: find.byType(TvFocusable),
            )
            .first;
        Focus.of(
          tester.element(
            find
                .descendant(of: tile, matching: find.byType(GestureDetector))
                .first,
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
        final original = FocusManager.instance.primaryFocus;
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.select),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        // Arrow navigation must not save or dismiss like a touch RadioGroup.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(GStorage.getSetting(SettingsKeys.rulesMirror), '');
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.select),
        );
        await tester.pumpAndSettle();
        // Keep Hive I/O out of the widget test's fake-clock zone.
        await tester.runAsync(() => Hive.box<dynamic>('setting').flush());
        await tester.pumpAndSettle();
        expect(RulesMirror.current, RulesMirror.ghfast);
        expect(find.byType(AlertDialog), findsNothing);
        expect(FocusManager.instance.primaryFocus, original);
        await tester.runAsync(
          () => tester.sendKeyEvent(LogicalKeyboardKey.select),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(RulesMirror.current, RulesMirror.ghfast);
        expect(find.byType(AlertDialog), findsNothing);
        expect(FocusManager.instance.primaryFocus, original);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
