import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/tv/settings/tv_slider_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/tv/player/tv_episode_picker.dart';
import 'package:kazumi/tv/player/tv_player_controls.dart';

void main() {
  late FocusNode playbackFocus;
  late GlobalKey<NavigatorState> navigator;
  late int sourceOpens;
  late int detailsOpens;
  late int toggles;
  late int episodeOpens;
  late List<Duration> seeks;

  setUp(() {
    playbackFocus = FocusNode();
    navigator = GlobalKey<NavigatorState>();
    toggles = 0;
    sourceOpens = 0;
    detailsOpens = 0;
    episodeOpens = 0;
    seeks = [];
  });

  tearDown(() => playbackFocus.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Focus(
            focusNode: playbackFocus,
            autofocus: true,
            child: Stack(
              children: [
                const SizedBox.expand(),
                TvPlayerControls(
                  playbackFocus: playbackFocus,
                  title: '东京食尸鬼',
                  playing: true,
                  position: const Duration(minutes: 3),
                  duration: const Duration(minutes: 24),
                  danmakuEnabled: true,
                  onTogglePlayback: () => toggles++,
                  onSeek: seeks.add,
                  onSeekBy: seeks.add,
                  onEpisodes: () async {
                    episodeOpens++;
                  },
                  onNext: () {},
                  onToggleDanmaku: () {},
                  onDanmakuSources: () async {
                    sourceOpens++;
                  },
                  onDetails: () async {
                    detailsOpens++;
                  },
                  onBack: () => navigator.currentState!.maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('back closes controls before leaving playback; they can reopen', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('暂停'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(TvPlayerControls)))!
          .popDisposition,
      RoutePopDisposition.doNotPop,
    );
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('暂停'), findsNothing);
    expect(navigator.currentState!.canPop(), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('暂停'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(TvPlayerControls)))!
          .popDisposition,
      RoutePopDisposition.doNotPop,
    );
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(navigator.currentState!.canPop(), isFalse);
    expect(find.byType(TvPlayerControls), findsOneWidget);
  });

  testWidgets('D-pad navigates controls, seeks only when controls are hidden', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(seeks, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(seeks, [const Duration(seconds: 10), const Duration(seconds: -10)]);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(toggles, 1);
    expect(find.text('暂停'), findsOneWidget);
  });

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'all six player actions are reachable and both final buttons activate at $size',
      (tester) async {
        await mount(tester, size: size);
        for (var i = 0; i < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'TV player action 4',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(sourceOpens, 1);
        for (var i = 0; i < 5; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'TV player action 5',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(detailsOpens, 1);
        expect(toggles, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('down opens episodes from playback and does not seek', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(episodeOpens, 1);
    expect(seeks, isEmpty);
  });

  testWidgets('remote adapter leaves dialogs and editable fields alone', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final dialog = showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(toggles, 0);
    expect(seeks, isEmpty);
    navigator.currentState!.pop();
    await dialog;
    await tester.pumpAndSettle();
  });

  testWidgets('controls fit a 960 by 540 TV surface', (tester) async {
    await mount(tester, size: const Size(960, 540));
    expect(tester.takeException(), isNull);
    expect(find.text('弹幕匹配'), findsOneWidget);
  });

  testWidgets(
    'episode picker returns the selected road and one-based episode',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TvEpisodeSelection? selected;
      final roads = [
        Road(
          name: '第一线路',
          data: List.generate(12, (i) => '/$i'),
          identifier: List.generate(12, (i) => '第 ${i + 1} 集'),
        ),
        Road(name: '备用线路', data: ['/a', '/b'], identifier: ['第一集', '第二集']),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showTvEpisodePicker(
                    context,
                    roads: roads,
                    selectedRoad: 0,
                    selectedEpisode: 12,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('备用线路'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tv-episode-1-2')));
      await tester.pumpAndSettle();
      expect(selected, (episode: 2, road: 1));
    },
  );
  testWidgets(
    'real router: progress Up/Down never seeks, Back ends edit then controls then playback; modal closes first',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var exits = 0;
      final module = createModule(
        register: (c) {
          c.route(
            '/',
            child: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.pushNamed('/player'),
                child: const Text('打开播放器'),
              ),
            ),
          );
          c.route(
            '/player',
            child: (context, state) => PopScope(
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) exits++;
              },
              child: Scaffold(
                body: Focus(
                  focusNode: playbackFocus,
                  autofocus: true,
                  child: Stack(
                    children: [
                      const SizedBox.expand(),
                      TvPlayerControls(
                        playbackFocus: playbackFocus,
                        title: '测试播放',
                        playing: true,
                        position: const Duration(minutes: 3),
                        duration: const Duration(minutes: 24),
                        danmakuEnabled: true,
                        onTogglePlayback: () {},
                        onSeek: seeks.add,
                        onSeekBy: seeks.add,
                        onEpisodes: () async {},
                        onNext: () {},
                        onToggleDanmaku: () {},
                        onDanmakuSources: () async {},
                        onDetails: () async {
                          await showDialog<void>(
                            context: context,
                            builder: (_) =>
                                const AlertDialog(content: Text('播放信息弹窗')),
                          );
                        },
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
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
      await tester.tap(find.text('打开播放器'));
      await tester.pumpAndSettle();
      final slider = find.byType(TvSliderTile);
      final control = find
          .descendant(of: slider, matching: find.byType(GestureDetector))
          .first;
      Focus.of(tester.element(control)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(seeks, isEmpty);
      Focus.of(tester.element(control)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(seeks.length, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('按确认调节 · 上下换项'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(exits, 0);
      await tester.tap(find.text('播放信息'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('播放信息弹窗'), findsNothing);
      expect(find.text('暂停'), findsOneWidget);
      expect(exits, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('暂停'), findsNothing);
      expect(exits, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('打开播放器'), findsOneWidget);
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
