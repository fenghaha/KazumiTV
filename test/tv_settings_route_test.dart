import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/tv/tv_mode.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class _PlayerFixture extends StatefulWidget {
  @override
  State<_PlayerFixture> createState() => _PlayerFixtureState();
}

class _PlayerFixtureState extends State<_PlayerFixture> {
  double value = 1;
  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('播放测试内容'),
    body: SettingsList(
      sections: [
        SettingsSection(
          tiles: [
            TvFocusable(onPressed: () {}, child: const Text('播放第一项')),
            SettingsSliderTile(
              title: const Text('默认倍速'),
              value: value,
              valueLabel: '$value',
              min: 0,
              max: 3,
              divisions: 30,
              onChanged: (v) => setState(() => value = v),
            ),
            TvFocusable(onPressed: () {}, child: const Text('播放最后项')),
          ],
        ),
      ],
    ),
  );
}

void main() {
  testWidgets(
    'real settings outlet returns focus before exiting and slider Back only ends editing',
    (tester) async {
      final preview = Platform.environment['TV_SETTINGS_PREVIEW'];
      final previewKey = GlobalKey();
      if (preview != null) {
        await (FontLoader(
          'MI_Sans_Regular',
        )..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
      TvMode.enabled = true;
      addTearDown(() => TvMode.enabled = false);
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = createModule(
        register: (c) {
          c.route(
            '/',
            child: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.pushNamed('/settings/player'),
                child: const Text('进入设置测试'),
              ),
            ),
          );
          c.module(
            createModule(
              path: '/settings',
              register: (s) {
                s.route(
                  '/',
                  child: (context, state) =>
                      SettingsPage(location: state.uri.path),
                  children: (sub) {
                    sub.route(
                      '/player',
                      child: (context, state) => _PlayerFixture(),
                    );
                    sub.route(
                      '/sync',
                      child: (context, state) => const SettingsDetailScaffold(
                        title: Text('同步测试内容'),
                        body: SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(height: 100, child: Text('同步介绍')),
                              TextButton(
                                onPressed: _nothing,
                                child: Text('同步第一项'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      );
      await tester.pumpWidget(
        ModularApp(
          module: module,
          child: Builder(
            builder: (context) => MaterialApp.router(
              theme: TvTheme.dark,
              routerConfig: ModularApp.routerConfigOf(context),
              builder: (_, child) =>
                  RepaintBoundary(key: previewKey, child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入设置测试'));
      await tester.pumpAndSettle();
      expect(find.text('播放测试内容'), findsOneWidget);
      if (preview != null) {
        await tester.runAsync(() async {
          final boundary =
              previewKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TV settings /settings/player',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('TV settings /settings/player'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TV adjustable setting',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('左右调节 · 确认或返回结束 · 上下换项'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('按确认调节 · 上下换项'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TV adjustable setting',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TV settings /settings/player',
      );
      expect(find.text('播放测试内容'), findsOneWidget);
      for (var i = 0; i < 7; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TV settings /settings/sync',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('同步测试内容'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TV settings /settings/sync',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('TV settings /settings/sync'),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TV settings /settings/sync',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('进入设置测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _nothing() {}
