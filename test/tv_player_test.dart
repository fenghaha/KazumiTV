import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/tv/player/tv_episode_picker.dart';
import 'package:kazumi/tv/player/tv_player_controls.dart';

void main() {
  late FocusNode playbackFocus;
  late GlobalKey<NavigatorState> navigator;
  late int toggles;
  late int episodeOpens;
  late List<Duration> seeks;

  setUp(() {
    playbackFocus = FocusNode();
    navigator = GlobalKey<NavigatorState>();
    toggles = 0;
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
                  onDanmakuSources: () {},
                  onDetails: () {},
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
    expect(navigator.currentState!.canPop(), isTrue);
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('暂停'), findsNothing);
    expect(navigator.currentState!.canPop(), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('暂停'), findsOneWidget);
    expect(navigator.currentState!.canPop(), isTrue);
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
}
