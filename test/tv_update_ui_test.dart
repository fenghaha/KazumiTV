import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/update/tv_update_page.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

void main() {
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'update entry matches setting cards and accepts remote focus at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: TvTheme.dark,
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(24),
                child: TvUpdateSettingsTile(),
              ),
            ),
          ),
        );
        expect(find.text('软件更新'), findsOneWidget);
        final surfaces = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(TvUpdateSettingsTile),
                matching: find.byType(DecoratedBox),
              ),
            )
            .where(
              (box) =>
                  box.decoration is BoxDecoration &&
                  (box.decoration as BoxDecoration).color == TvTheme.surface,
            );
        expect(surfaces, hasLength(1));
        final decoration = surfaces.single.decoration as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(16));
        final focusable = tester.widget<TvFocusable>(find.byType(TvFocusable));
        expect(
          focusable.padding,
          const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        );
        expect(focusable.focusBorderColor, TvTheme.focus);
        expect(tester.widget<Text>(find.text('软件更新')).style?.fontSize, 23);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.context, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
