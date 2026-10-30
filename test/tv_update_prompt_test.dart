import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/tv_theme.dart';
import 'package:kazumi/tv/update/tv_update_prompt.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

void main() {
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'TV update dialog is dark and works with directional remote at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bool? decision;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TvFocusable(
                  autofocus: true,
                  onPressed: () async {
                    decision = await showTvUpdatePrompt(
                      context,
                      revision: 'r5.8.3',
                    );
                  },
                  child: const Text('Open update prompt'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
          TvTheme.surface,
        );
        expect(
          Theme.of(tester.element(find.text('发现新版本'))).brightness,
          Brightness.dark,
        );
        expect(Focus.of(tester.element(find.text('稍后'))).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(Focus.of(tester.element(find.text('查看更新'))).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(decision, isTrue);
        expect(find.byType(Dialog), findsNothing);
        expect(
          Focus.of(tester.element(find.text('Open update prompt'))).hasFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final backKey in [
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
  ]) {
    testWidgets('TV update prompt dismisses with $backKey without accepting', (
      tester,
    ) async {
      bool? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  decision = await showTvUpdatePrompt(
                    context,
                    revision: 'r5.8.3',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(
        backKey,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pumpAndSettle();
      expect(decision, isFalse);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
