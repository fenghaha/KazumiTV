import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/tv/home/tv_home_data.dart';
import 'package:kazumi/tv/home/tv_home_page.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/widgets/tv_poster.dart';

BangumiItem _item(int id, String name) => BangumiItem(
  id: id,
  type: 2,
  name: name,
  nameCn: name,
  summary: '在旅途中，寻找时间与记忆留下的答案。一次告别，也是新的故事的开始。',
  airDate: '2026-10-01',
  airWeekday: 1,
  rank: 12,
  images: {},
  tags: [],
  alias: [],
  ratingScore: 8.6,
  votes: 100,
  votesCount: [],
  info: '',
);

/// Offline presentation fixture, deliberately not wired to production routes.
class _FixtureData extends TvHomeData {
  _FixtureData({bool withItems = true, bool withHistory = true}) {
    if (withItems) {
      popular = [
        _item(1, '葬送的芙莉莲'),
        _item(2, '夏目友人帐'),
        _item(3, '紫罗兰永恒花园'),
        _item(4, '摇曳露营'),
        _item(5, '四叠半神话大系'),
        _item(6, '昭和元禄落语心中'),
        _item(7, '冰菓'),
        _item(8, '星际牛仔'),
      ];
      calendar = List.generate(7, (_) => popular.take(3).toList());
      collection = [CollectedBangumi(popular[1], DateTime(2026, 10, 23), 1)];
      if (withHistory) {
        histories = [
          History(popular[2], 3, 'fixture', DateTime(2026, 10, 23), '', '第3集'),
        ];
      }
    }
    recentSearches = ['东京食尸鬼', '夏目友人帐'];
  }

  int refreshCount = 0;
  final submitted = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshDiscovery() async {
    refreshCount++;
  }

  @override
  void refreshLocal() {}

  @override
  Future<void> search(String query, {bool more = false}) async {
    submitted.add(query);
    this.query = query;
    searchResults = [_item(99, query)];
    notifyListeners();
  }
}

void main() {
  Future<void> setTvSize(
    WidgetTester tester, [
    Size size = const Size(1280, 720),
  ]) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child) => MaterialApp(
    theme: ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(primary: Color(0xFFEBC889)),
    ),
    home: child,
  );

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets('Up restores the whole discovery header at ${size.width}', (
      tester,
    ) async {
      await setTvSize(tester, size);
      await tester.pumpWidget(
        app(TvHomePage(data: _FixtureData(withHistory: false))),
      );
      await tester.pumpAndSettle();
      final vertical = find
          .descendant(
            of: find.byKey(const PageStorageKey('discover')),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(vertical).position;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(50));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      expect(
        tester.getTopLeft(find.text('今晚看什么')).dy,
        greaterThanOrEqualTo(20),
      );
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('tv-nav-0'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('tv-nav-0'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-0');
    });
  }

  testWidgets(
    'home needs two Back presses, coalesces key/system, and navigation cancels exit',
    (tester) async {
      var exits = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') exits++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await setTvSize(tester);
      await tester.pumpWidget(app(TvHomePage(data: _FixtureData())));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(exits, 0);
      expect(find.text('再按一次返回退出应用'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('再按一次返回退出应用'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('再按一次返回退出应用'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(exits, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(exits, 1);
    },
  );

  testWidgets('remote moves from navigation to feature and opens the subject', (
    tester,
  ) async {
    await setTvSize(tester);
    final data = _FixtureData();
    final opened = <int>[];
    await tester.pumpWidget(
      app(
        TvHomePage(
          data: data,
          onOpenBangumi: (item) async {
            opened.add(item.id);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(opened, [1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote can enter the library and back returns to discovery', (
    tester,
  ) async {
    await setTvSize(tester);
    await tester.pumpWidget(app(TvHomePage(data: _FixtureData())));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-3');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('喜欢的故事，都在这里'), findsOneWidget);
    expect(find.text('夏目友人帐'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('今晚看什么'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('search route preserves and submits its initial query once', (
    tester,
  ) async {
    await setTvSize(tester);
    final data = _FixtureData();
    await tester.pumpWidget(
      app(
        TvHomePage(
          data: data,
          startInSearch: true,
          initialQuery: '夏目友人帐',
          initialLocation: '/tab/my',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('找一部想看的番剧'), findsOneWidget);
    expect(data.submitted, ['夏目友人帐']);
    expect(data.query, '夏目友人帐');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'timeline startup selects calendar data and calendar navigation focus',
    (tester) async {
      await setTvSize(tester);
      final data = _FixtureData();
      await tester.pumpWidget(
        app(TvHomePage(data: data, initialLocation: '/tab/timeline/')),
      );
      await tester.pumpAndSettle();
      final nav = tester.widget<TvFocusable>(
        find.byKey(const ValueKey('tv-nav-2')),
      );
      expect(nav.selected, isTrue);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-2');
      expect(
        tester
            .widgetList<TvPoster>(find.byType(TvPoster))
            .map((e) => e.item.id),
        [1, 2, 3],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collect startup selects watching collection and its navigation focus',
    (tester) async {
      await setTvSize(tester);
      await tester.pumpWidget(
        app(TvHomePage(data: _FixtureData(), initialLocation: '/tab/collect')),
      );
      await tester.pumpAndSettle();
      final nav = tester.widget<TvFocusable>(
        find.byKey(const ValueKey('tv-nav-3')),
      );
      expect(nav.selected, isTrue);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-3');
      expect(
        tester
            .widgetList<TvPoster>(find.byType(TvPoster))
            .map((e) => e.item.id),
        [2],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed discovery preserves a focusable retry and local navigation',
    (tester) async {
      await setTvSize(tester);
      final data = _FixtureData(withItems: false)..popularError = '热门番剧暂时未能加载';
      await tester.pumpWidget(app(TvHomePage(data: data)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(data.refreshCount, 1);
      expect(find.byKey(const ValueKey('tv-nav-4')), findsOneWidget);
    },
  );

  testWidgets(
    'off-screen controls scroll into view and disabled controls are skipped',
    (tester) async {
      await setTvSize(tester);
      final nodes = List.generate(8, (i) => FocusNode(debugLabel: 'item-$i'));
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var activated = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  controller: scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < nodes.length; i++)
                        SizedBox(
                          width: 150,
                          child: TvFocusable(
                            autofocus: i == 0,
                            focusNode: nodes[i],
                            onPressed: i == 1 ? null : () => activated = i,
                            child: Text('Item $i'),
                          ),
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
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[2].hasFocus, isTrue);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(scroll.offset, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(activated, 6);
    },
  );

  testWidgets('1280x720 offline presentation fixture has no overflow', (
    tester,
  ) async {
    await setTvSize(tester);
    final font = FontLoader('MI_Sans_Regular')
      ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      app(
        RepaintBoundary(
          key: boundaryKey,
          // This preview shows the discovery shelf. Other interaction tests
          // retain history entries and continue to cover the resume path.
          child: TvHomePage(data: _FixtureData(withHistory: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final output = Platform.environment['TV_HOME_PREVIEW'];
    if (output != null && output.isNotEmpty) {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets(
    '960x540 TV and projector layout keeps navigation and content reachable',
    (tester) async {
      await setTvSize(tester, const Size(960, 540));
      await tester.pumpWidget(app(TvHomePage(data: _FixtureData())));
      await tester.pumpAndSettle();
      expect(find.text('KazumiTV'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('从上次停下的地方继续'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
