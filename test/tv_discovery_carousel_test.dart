import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/tv/home/tv_home_data.dart';
import 'package:kazumi/tv/home/tv_home_page.dart';

BangumiItem _item(int id) => BangumiItem(
  id: id,
  type: 2,
  name: '推荐 $id',
  nameCn: '推荐 $id',
  summary: '这是第 $id 部番剧的故事介绍。',
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

class _Data extends TvHomeData {
  _Data(int count) {
    popular = List.generate(count, (i) => _item(i + 1));
  }
  void replace(List<BangumiItem> items) {
    popular = items;
    notifyListeners();
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<void> refreshDiscovery() async {}
  @override
  void refreshLocal() {}
  @override
  Future<void> search(String query, {bool more = false}) async {}
}

void main() {
  Finder getTitle() => find.byKey(const ValueKey('tv-discovery-title'));
  Finder getPage() => find.byKey(const ValueKey('tv-discovery-page'));
  String title(WidgetTester tester) => tester.widget<Text>(getTitle()).data!;
  String page(WidgetTester tester) => tester.widget<Text>(getPage()).data!;

  Future<void> show(
    WidgetTester tester,
    _Data data, {
    Size size = const Size(1280, 720),
    Future<void> Function(BangumiItem)? onOpen,
    GlobalKey<NavigatorState>? navigatorKey,
    bool reducedMotion = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: TvHomePage(data: data, onOpenBangumi: onOpen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey value) async {
    await tester.sendKeyEvent(value);
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'remote cycles, opens the visible subject, and exits at $size',
      (tester) async {
        final opened = <int>[];
        await show(
          tester,
          _Data(8),
          size: size,
          onOpen: (item) async {
            opened.add(item.id);
          },
        );
        expect(page(tester), '1 / 6');
        await key(tester, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'tv-discovery-carousel',
        );
        for (var i = 0; i < 5; i++) {
          await key(tester, LogicalKeyboardKey.arrowRight);
        }
        expect(title(tester), '推荐 6');
        await key(tester, LogicalKeyboardKey.select);
        expect(opened, [6]);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'tv-discovery-carousel',
        );
        await key(tester, LogicalKeyboardKey.arrowRight);
        expect(title(tester), '推荐 1');
        await key(tester, LogicalKeyboardKey.arrowRight);
        await key(tester, LogicalKeyboardKey.arrowLeft);
        expect(title(tester), '推荐 1');
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          isNot('tv-discovery-carousel'),
        );
        await key(tester, LogicalKeyboardKey.arrowUp);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'tv-discovery-carousel',
        );
        await key(tester, LogicalKeyboardKey.arrowLeft);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-0');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'auto rotation pauses for focus, scrolled shelves and background',
    (tester) async {
      await show(tester, _Data(3));
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(title(tester), '推荐 2');
      await key(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(seconds: 16));
      expect(title(tester), '推荐 2');
      await key(tester, LogicalKeyboardKey.arrowDown);
      final vertical = find
          .descendant(
            of: find.byKey(const PageStorageKey('discover')),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(vertical).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump(const Duration(seconds: 16));
      expect(title(tester), '推荐 2');
      position.jumpTo(0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 16));
      expect(title(tester), '推荐 2');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(title(tester), '推荐 3');
    },
  );

  testWidgets(
    'a route and an outstanding open cannot change the selected subject',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final pending = Completer<void>();
      var opens = 0;
      await show(
        tester,
        _Data(3),
        navigatorKey: navigator,
        onOpen: (_) {
          opens++;
          return pending.future;
        },
      );
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.select);
      await key(tester, LogicalKeyboardKey.select);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(opens, 1);
      expect(title(tester), '推荐 1');
      pending.complete();
      await tester.pumpAndSettle();
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('详情')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 24));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(title(tester), '推荐 1');
    },
  );

  testWidgets(
    'refresh deduplicates, retains subject, handles shrinking and empty lists',
    (tester) async {
      final data = _Data(4);
      await show(tester, data);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.arrowRight);
      data.replace([_item(4), _item(2), _item(2), _item(1)]);
      await tester.pumpAndSettle();
      expect(title(tester), '推荐 2');
      expect(page(tester), '2 / 3');
      data.replace([_item(3)]);
      await tester.pumpAndSettle();
      expect(title(tester), '推荐 3');
      expect(page(tester), '1 / 1');
      expect(find.text('← → 切换推荐'), findsNothing);
      await tester.pump(const Duration(seconds: 16));
      expect(title(tester), '推荐 3');
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-0');
      data.replace([]);
      await tester.pumpAndSettle();
      expect(getTitle(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion stops auto rotation but keeps remote selection', (
    tester,
  ) async {
    await show(tester, _Data(3), reducedMotion: true);
    await tester.pump(const Duration(seconds: 24));
    expect(title(tester), '推荐 1');
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(title(tester), '推荐 2');
    expect(tester.takeException(), isNull);
  });
}
