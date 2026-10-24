import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/player/tv_playback_back.dart';
import 'package:kazumi/tv/player/tv_player_controls.dart';
import 'package:kazumi/tv/settings/tv_slider_tile.dart';

void main() {
  testWidgets(
    'paired Android key/system events consume one layer and cannot arm or confirm twice',
    (tester) async {
      var exits = 0;
      var menu = true;
      final back = TvPlaybackBackController(exit: () => exits++);

      back.registerOverlay(menu, () {
        if (!menu) return false;
        menu = false;
        return true;
      });
      back.request(TvBackOrigin.key);
      back.request(TvBackOrigin.system);
      expect(menu, isFalse);
      expect(back.awaitingSecondBack, isFalse);
      expect(exits, 0);
      await tester.pump(const Duration(milliseconds: 400));
      back.request(TvBackOrigin.system);
      back.request(TvBackOrigin.key);
      expect(back.awaitingSecondBack, isTrue);
      expect(exits, 0);
      back.request(TvBackOrigin.system);
      expect(exits, 1);
      back.request(TvBackOrigin.key);
      expect(exits, 1);
      back.dispose();
    },
  );

  testWidgets(
    'confirmation expires after two seconds and an intervening action cancels it',
    (tester) async {
      var exits = 0;
      final back = TvPlaybackBackController(exit: () => exits++);

      back.request(TvBackOrigin.system);
      await tester.pump(const Duration(seconds: 3));
      expect(back.awaitingSecondBack, isFalse);
      back.request(TvBackOrigin.system);
      expect(exits, 0);
      back.cancelExit();
      back.request(TvBackOrigin.system);
      expect(exits, 0);
      back.request(TvBackOrigin.system);
      expect(exits, 1);
      back.dispose();
    },
  );

  for (final withControls in [true, false]) {
    testWidgets(
      'real router protects ${withControls ? 'visible TV menu and paired key/system Back' : 'loading page without controls or player focus'}',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var exits = 0;
        final module = createModule(
          register: (c) {
            c.route(
              '/',
              child: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pushNamed('/player'),
                  child: const Text('进入播放'),
                ),
              ),
            );
            c.route(
              '/player',
              child: (context, state) => TvPlaybackBackBoundary(
                child: PopScope(
                  onPopInvokedWithResult: (didPop, result) {
                    if (didPop) exits++;
                  },
                  child: Scaffold(
                    body: withControls
                        ? Focus(
                            focusNode: focus,
                            autofocus: true,
                            child: Stack(
                              children: [
                                const SizedBox.expand(),
                                TvPlayerControls(
                                  playbackFocus: focus,
                                  title: '测试视频',
                                  playing: true,
                                  position: Duration.zero,
                                  duration: const Duration(minutes: 24),
                                  danmakuEnabled: true,
                                  onTogglePlayback: () {},
                                  onSeek: (_) {},
                                  onSeekBy: (_) {},
                                  onEpisodes: () async {},
                                  onNext: () {},
                                  onToggleDanmaku: () {},
                                  onDanmakuSettings: () async {},
                                  onDanmakuSources: () async {},
                                  onDetails: () async {
                                    await showDialog<void>(
                                      context: context,
                                      builder: (_) => const AlertDialog(
                                        content: Text('信息弹窗'),
                                      ),
                                    );
                                  },
                                  onBack: () =>
                                      Navigator.of(context).maybePop(),
                                ),
                              ],
                            ),
                          )
                        : const Center(child: Text('加载中')),
                  ),
                ),
              ),
            );
          },
        );
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ModularApp(
            module: module,
            child: Builder(
              builder: (context) => MaterialApp.router(
                theme: ThemeData.dark(),
                routerConfig: ModularApp.routerConfigOf(context),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('进入播放'));
        await tester.pumpAndSettle();
        if (withControls) {
          final target = find
              .descendant(
                of: find.byType(TvSliderTile),
                matching: find.byType(GestureDetector),
              )
              .first;
          Focus.of(tester.element(target)).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('按确认调节 · 上下换项'), findsOneWidget);
          expect(find.text('暂停'), findsOneWidget);
          expect(find.text('再按一次返回退出播放'), findsNothing);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('播放信息'));
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('信息弹窗'), findsNothing);
          expect(find.text('暂停'), findsOneWidget);
          expect(find.text('再按一次返回退出播放'), findsNothing);
          await tester.sendKeyEvent(
            LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape,
          );
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('暂停'), findsNothing);
          expect(find.text('再按一次返回退出播放'), findsNothing);
          expect(exits, 0);
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('再按一次返回退出播放'), findsOneWidget);
        expect(exits, 0);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('进入播放'), findsOneWidget);
        expect(exits, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
