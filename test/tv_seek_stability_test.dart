import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/player/tv_player_controls.dart';
import 'package:kazumi/tv/player/tv_seek_controller.dart';
import 'package:kazumi/tv/settings/tv_slider_tile.dart';

void main() {
  late List<Duration> submitted;
  late TvSeekController seeking;

  setUp(() {
    submitted = [];
    seeking = TvSeekController(
      position: const Duration(seconds: 100),
      duration: const Duration(seconds: 600),
      onSeek: submitted.add,
    );
  });

  testWidgets('rapid steps accumulate despite stale playback reports', (
    tester,
  ) async {
    for (var i = 0; i < 20; i++) {
      seeking.seekBy(const Duration(seconds: 10));
      seeking.updatePlayback(
        const Duration(seconds: 100),
        const Duration(seconds: 600),
      );
      expect(seeking.position, Duration(seconds: 110 + i * 10));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(submitted, isEmpty);
    await tester.pump(TvSeekController.inputDelay);
    expect(submitted, [const Duration(seconds: 300)]);
    seeking.updatePlayback(
      const Duration(seconds: 110),
      const Duration(seconds: 600),
    );
    expect(seeking.position, const Duration(seconds: 300));
    seeking.updatePlayback(
      const Duration(seconds: 300),
      const Duration(seconds: 600),
    );
    seeking.updatePlayback(
      const Duration(seconds: 301),
      const Duration(seconds: 600),
    );
    expect(seeking.position, const Duration(seconds: 301));
    seeking.dispose();
  });

  testWidgets('drag previews locally and submits only its final position', (
    tester,
  ) async {
    seeking.beginDrag();
    for (var seconds = 120; seconds <= 400; seconds += 20) {
      seeking.seekTo(Duration(seconds: seconds));
      await tester.pump(const Duration(milliseconds: 250));
      seeking.updatePlayback(
        const Duration(seconds: 100),
        const Duration(seconds: 600),
      );
      expect(seeking.position, Duration(seconds: seconds));
    }
    expect(submitted, isEmpty);
    seeking.endDrag();
    await tester.pump();
    expect(submitted, [const Duration(seconds: 400)]);
    seeking.dispose();
  });

  testWidgets(
    'slow seek keeps only newest queued target and ignores old completion',
    (tester) async {
      seeking.dispose();
      final completions = <Completer<void>>[];
      seeking = TvSeekController(
        position: const Duration(seconds: 100),
        duration: const Duration(seconds: 600),
        onSeek: (target) {
          submitted.add(target);
          final completion = Completer<void>();
          completions.add(completion);
          return completion.future;
        },
      );
      seeking.seekTo(const Duration(seconds: 200));
      await tester.pump(TvSeekController.inputDelay);
      seeking.seekTo(const Duration(seconds: 250));
      seeking.seekTo(const Duration(seconds: 300));
      await tester.pump(TvSeekController.inputDelay);
      expect(submitted, [const Duration(seconds: 200)]);
      seeking.updatePlayback(
        const Duration(seconds: 200),
        const Duration(seconds: 600),
      );
      expect(seeking.position, const Duration(seconds: 300));
      completions.first.complete();
      await tester.pump();
      expect(submitted, [
        const Duration(seconds: 200),
        const Duration(seconds: 300),
      ]);
      expect(seeking.position, const Duration(seconds: 300));
      completions.last.complete();
      await tester.pump();
      seeking.updatePlayback(
        const Duration(seconds: 300),
        const Duration(seconds: 600),
      );
      seeking.seekBy(const Duration(seconds: -20));
      expect(seeking.position, const Duration(seconds: 280));
      seeking.dispose();
    },
  );

  testWidgets('reverse input, boundaries and missing duration', (tester) async {
    seeking.seekBy(const Duration(seconds: 1000));
    expect(seeking.position, const Duration(seconds: 600));
    seeking.seekBy(const Duration(seconds: -10));
    expect(seeking.position, const Duration(seconds: 590));
    seeking.seekBy(const Duration(seconds: -1000));
    expect(seeking.position, Duration.zero);
    await tester.pump(TvSeekController.inputDelay);
    expect(submitted, [Duration.zero]);
    seeking.updatePlayback(Duration.zero, Duration.zero);
    seeking.seekBy(const Duration(seconds: 10));
    await tester.pump(TvSeekController.inputDelay);
    expect(submitted, [Duration.zero]);
    seeking.dispose();
  });

  testWidgets(
    'unacknowledged seek falls back to actual playback after timeout',
    (tester) async {
      seeking.seekTo(const Duration(seconds: 400));
      await tester.pump(TvSeekController.inputDelay);
      await tester.pump();
      expect(seeking.position, const Duration(seconds: 400));
      await tester.pump(TvSeekController.settleTimeout);
      expect(seeking.position, const Duration(seconds: 100));
      seeking.dispose();
    },
  );

  testWidgets('failed seek releases preview and allows another seek', (
    tester,
  ) async {
    seeking.dispose();
    seeking = TvSeekController(
      position: const Duration(seconds: 100),
      duration: const Duration(seconds: 600),
      onSeek: (_) => Future<void>.error(StateError('failed')),
    );
    seeking.seekTo(const Duration(seconds: 200));
    await tester.pump(TvSeekController.inputDelay);
    await tester.pump();
    expect(seeking.position, const Duration(seconds: 100));
    seeking.seekBy(const Duration(seconds: -10));
    expect(seeking.position, const Duration(seconds: 90));
    seeking.dispose();
  });

  testWidgets(
    'native confirmation resumes ticks while completion is still waiting',
    (tester) async {
      seeking.dispose();
      final completion = Completer<void>();
      seeking = TvSeekController(
        position: const Duration(seconds: 100),
        duration: const Duration(seconds: 600),
        onSeek: (_) => completion.future,
      );
      seeking.seekTo(const Duration(seconds: 200));
      await tester.pump(TvSeekController.inputDelay);
      seeking.updatePlayback(
        const Duration(seconds: 200),
        const Duration(seconds: 600),
      );
      seeking.updatePlayback(
        const Duration(seconds: 205),
        const Duration(seconds: 600),
      );
      expect(seeking.position, const Duration(seconds: 205));
      completion.complete();
      await tester.pump();
      expect(seeking.position, const Duration(seconds: 205));
      seeking.dispose();
    },
  );

  testWidgets('source loading cancels queued input and its preview', (
    tester,
  ) async {
    seeking.seekTo(const Duration(seconds: 400));
    seeking.cancelPending();
    await tester.pump(TvSeekController.inputDelay);
    expect(submitted, isEmpty);
    expect(seeking.position, const Duration(seconds: 100));
    seeking.seekTo(const Duration(seconds: 200));
    seeking.updatePlayback(Duration.zero, Duration.zero);
    await tester.pump(TvSeekController.inputDelay);
    expect(submitted, isEmpty);
    expect(seeking.position, Duration.zero);
    seeking.dispose();
  });

  testWidgets('dispose drops delayed input and late completions', (
    tester,
  ) async {
    seeking.seekTo(const Duration(seconds: 200));
    seeking.dispose();
    await tester.pump(TvSeekController.inputDelay);
    expect(submitted, isEmpty);
    final completion = Completer<void>();
    seeking = TvSeekController(
      position: Duration.zero,
      duration: const Duration(seconds: 600),
      onSeek: (target) {
        submitted.add(target);
        return completion.future;
      },
    );
    seeking.seekTo(const Duration(seconds: 300));
    await tester.pump(TvSeekController.inputDelay);
    seeking.seekTo(const Duration(seconds: 400));
    seeking.dispose();
    completion.complete();
    await tester.pump(TvSeekController.settleTimeout);
    expect(submitted, [const Duration(seconds: 300)]);
  });

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets('TV slider and hidden remote resist stale ticks at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final focus = FocusNode();
      final reported = ValueNotifier(const Duration(seconds: 100));
      final optimistic = ValueNotifier(const Duration(seconds: 100));
      addTearDown(optimistic.dispose);
      addTearDown(focus.dispose);
      addTearDown(reported.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              focusNode: focus,
              autofocus: true,
              child: ValueListenableBuilder<Duration>(
                valueListenable: optimistic,
                builder: (context, position, child) =>
                    ValueListenableBuilder<Duration>(
                      valueListenable: reported,
                      builder: (context, nativePosition, child) => Stack(
                        children: [
                          const SizedBox.expand(),
                          TvPlayerControls(
                            playbackFocus: focus,
                            title: '进度回归',
                            playing: true,
                            position: position,
                            reportedPosition: nativePosition,
                            duration: const Duration(seconds: 600),
                            danmakuEnabled: true,
                            onTogglePlayback: () {},
                            onSeek: (target) {
                              submitted.add(target);
                              optimistic.value = target;
                            },
                            onEpisodes: () async {},
                            onNext: () {},
                            onToggleDanmaku: () {},
                            onDanmakuSources: () async {},
                            onDetails: () async {},
                            onDanmakuSettings: () async {},
                            onBack: () {},
                          ),
                        ],
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        tester.state<TvSliderTileState>(find.byType(TvSliderTile)).isFocused,
        isTrue,
      );
      // Deliver input before a frame as well as between delayed position reports.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 150000);
      reported.value = const Duration(seconds: 101);
      optimistic.value = reported.value;
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 150000);
      expect(find.text('2:30'), findsOneWidget);
      expect(submitted, isEmpty);
      await tester.pump(TvSeekController.inputDelay);
      expect(submitted, [const Duration(seconds: 150)]);
      reported.value = const Duration(seconds: 102);
      optimistic.value = reported.value;
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 150000);
      // Actual pointer drag uses the same preview and commits on release.
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(150000);
      slider.onChanged!(300000);
      await tester.pump(const Duration(seconds: 1));
      expect(submitted.length, 1);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 300000);
      slider.onChangeEnd!(300000);
      await tester.pump();
      expect(submitted.last, const Duration(seconds: 300));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 30));
        reported.value += const Duration(seconds: 1);
        optimistic.value = reported.value;
        await tester.pump();
      }
      expect(find.text('5:30 / 10:00'), findsOneWidget);
      await tester.pump(TvSeekController.inputDelay);
      expect(submitted.last, const Duration(seconds: 330));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
