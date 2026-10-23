import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/settings/tv_settings_navigation.dart';
import 'package:kazumi/tv/settings/tv_slider_tile.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/widgets/tv_scroll_boundary.dart';

void main() {
  testWidgets('settings Left and Back return to rail, Right restores detail', (
    tester,
  ) async {
    final nav = TvSettingsNavigationController()..selectedPath = 'play';
    final first = FocusNode(debugLabel: 'first-setting');
    addTearDown(nav.dispose);
    addTearDown(first.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: TvTheme.dark,
        home: TvSettingsNavigation(
          controller: nav,
          innerCanPop: () => false,
          onBack: () => nav.focusMenu(),
          child: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: nav.menu(
                    TvFocusable(
                      focusNode: nav.menuNode('play'),
                      autofocus: true,
                      onPressed: nav.enterDetails,
                      child: const Text('播放'),
                    ),
                  ),
                ),
                Expanded(
                  child: nav.pane(
                    TvScrollBoundary(
                      child: ListView(
                        children: [
                          TvFocusable(
                            focusNode: first,
                            onPressed: () {},
                            child: const Text('第一项'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(nav.menuNode('play').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(nav.menuNode('play').hasFocus, isTrue);
    expect(find.text('第一项'), findsOneWidget);
  });

  testWidgets('slider browses with Up/Down and adjusts only after OK', (
    tester,
  ) async {
    var value = 1.0;
    final before = FocusNode(debugLabel: 'before');
    final after = FocusNode(debugLabel: 'after');
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: TvTheme.dark,
        home: Scaffold(
          body: TvScrollBoundary(
            child: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: Column(
                  children: [
                    TvFocusable(
                      focusNode: before,
                      autofocus: true,
                      onPressed: () {},
                      child: const Text('前一项'),
                    ),
                    TvSliderTile(
                      title: const Text('倍速'),
                      value: value,
                      valueLabel: '$value',
                      min: 0,
                      max: 3,
                      divisions: 30,
                      onChanged: (v) => setState(() => value = v),
                    ),
                    TvFocusable(
                      focusNode: after,
                      onPressed: () {},
                      child: const Text('后一项'),
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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'TV adjustable setting',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(value, 1.0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(after.hasFocus, isTrue);
    expect(value, 1.0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(value, closeTo(1.1, .0001));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(before.hasFocus, isTrue);
    expect(value, closeTo(1.1, .0001));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('按确认调节 · 上下换项'), findsOneWidget);
    expect(find.text('倍速'), findsOneWidget);
  });

  testWidgets(
    'sync-style cards reveal intro again when moving to the first card',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: TvTheme.dark,
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: TvScrollBoundary(
                child: SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    children: [
                      const SizedBox(
                        height: 120,
                        child: Text('让追番保持同步', key: ValueKey('intro')),
                      ),
                      TvFocusable(
                        autofocus: true,
                        onPressed: () {},
                        child: const SizedBox(
                          height: 240,
                          width: 500,
                          child: Text('Bangumi'),
                        ),
                      ),
                      TvFocusable(
                        onPressed: () {},
                        child: const SizedBox(
                          height: 240,
                          width: 500,
                          child: Text('WebDAV'),
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
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('intro'))).dy,
        greaterThanOrEqualTo(0),
      );
    },
  );
}
