import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_dropdown_tile.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/tv/settings/tv_sync_service_card.dart';
import 'package:kazumi/tv/tv_mode.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

void main() {
  setUp(() => TvMode.enabled = true);
  tearDown(() => TvMode.enabled = false);
  Future<void> open(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TvTheme.dark,
        home: SettingsDetailScaffold(title: const Text('设置'), body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> focus(WidgetTester tester, String text) async {
    final row = find
        .ancestor(of: find.text(text).first, matching: find.byType(TvFocusable))
        .first;
    final detector = find
        .descendant(of: row, matching: find.byType(GestureDetector))
        .first;
    Focus.of(tester.element(detector)).requestFocus();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'switch row has one remote target, toggles, retains focus while disabled, and moves down',
    (tester) async {
      var value = false;
      var busy = false;
      await open(
        tester,
        StatefulBuilder(
          builder: (context, change) => SettingsList(
            sections: [
              SettingsSection(
                tiles: [
                  SettingsTile.switchTile(
                    title: const Text('自动同步追番'),
                    initialValue: value,
                    enabled: !busy,
                    onToggle: (v) => change(() {
                      value = v ?? !value;
                      busy = true;
                    }),
                  ),
                  SettingsTile(title: const Text('下一项'), onPressed: (_) {}),
                ],
              ),
            ],
          ),
        ),
      );
      await focus(tester, '自动同步追番');
      final node = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(FocusManager.instance.primaryFocus, node);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(node));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dropdown enters focused choices, selects with remote, Back closes before page and restores focus',
    (tester) async {
      var value = 0;
      await open(
        tester,
        StatefulBuilder(
          builder: (context, change) => SettingsList(
            sections: [
              SettingsSection(
                tiles: [
                  SettingsDropdownTile<int>(
                    title: const Text('追番默认布局'),
                    value: value,
                    options: const {0: '列表', 1: '卡片'},
                    onChanged: (v) => change(() => value = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await focus(tester, '追番默认布局');
      final original = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(original));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(value, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(FocusManager.instance.primaryFocus, original);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('追番默认布局'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('common operation menu also has a modal Back boundary', (
    tester,
  ) async {
    var selected = false;
    await open(
      tester,
      KazumiMenuButton(
        builder: (context, toggle) =>
            TvFocusable(onPressed: toggle, child: const Text('菜单')),
        menuChildren: [
          KazumiMenuItem(label: '执行', onPressed: () => selected = true),
        ],
      ),
    );
    await focus(tester, '菜单');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(selected, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, isTrue);
  });

  testWidgets(
    'sync cards reveal all content with Down and restore intro with Up at 540p',
    (tester) async {
      Widget card(String name) => TvSyncServiceCard(
        title: name,
        description: '在其他设备接着看，同步追番状态。',
        content: '观看记录 · 收藏 · 弹幕屏蔽词',
        status: const Text('未配置'),
        action: '连接服务',
        icon: Icons.sync,
        onPressed: () {},
      );
      await open(
        tester,
        SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 150, child: Text('同步介绍')),
                card('Bangumi'),
                const SizedBox(height: 20),
                card('WebDAV'),
              ],
            ),
          ),
        ),
      );
      await focus(tester, 'Bangumi');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.getBottomRight(find.text('WebDAV')).dy, lessThan(540));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
