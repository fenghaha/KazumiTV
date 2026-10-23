import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/input/tv_text_input.dart';
import 'package:kazumi/tv/platform/tv_native_input.dart';

void main() {
  testWidgets(
    'fallback confirmation opens an editor; cancelling preserves text and focus',
    (tester) async {
      final controller = TextEditingController(text: '原内容');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvTextInput(
              controller: controller,
              focusNode: focus,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(find.byType(TextField), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '未提交内容');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.text, '原内容');
      expect(focus.hasFocus, isTrue);
    },
    // Flutter widget tests otherwise default to Android and use the native
    // channel. This case deliberately exercises the non-Android editor.
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('editor Done updates the controller and submits exactly once', (
    tester,
  ) async {
    final controller = TextEditingController();
    final submitted = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvTextInput(
            controller: controller,
            autofocus: true,
            onSubmitted: submitted.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '东京食尸鬼');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, '东京食尸鬼');
    expect(submitted, ['东京食尸鬼']);
    expect(find.byType(TextField), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'Android OK opens native editing; Done and Cancel restore remote focus',
    (tester) async {
      final controller = TextEditingController(text: '原内容');
      final focus = FocusNode();
      final submitted = <String>[];
      final calls = <MethodCall>[];
      String? nextResult = '原生输入结果';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(TvNativeInput.channel, (call) async {
        calls.add(call);
        return nextResult;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(TvNativeInput.channel, null);
        controller.dispose();
        focus.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvTextInput(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              onSubmitted: submitted.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty); // Browsing alone must not open a keyboard.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(calls.single.method, 'editText');
      expect(calls.single.arguments['text'], '原内容');
      expect(controller.text, '原生输入结果');
      expect(submitted, ['原生输入结果']);
      expect(focus.hasFocus, isTrue);
      expect(find.byType(TextField), findsNothing);

      nextResult = null; // The native dialog reports Back/Cancel as null.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
      expect(controller.text, '原生输入结果');
      expect(submitted, ['原生输入结果']);
      expect(focus.hasFocus, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'field disabled while a native editor is open ignores its result',
    (tester) async {
      final result = Completer<String?>();
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(TvNativeInput.channel, (call) async {
        calls.add(call);
        return result.future;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(TvNativeInput.channel, null);
      });
      final controller = TextEditingController(text: '保留');
      final submitted = <String>[];
      addTearDown(controller.dispose);
      Widget app(bool enabled) => MaterialApp(
        home: Scaffold(
          body: TvTextInput(
            controller: controller,
            enabled: enabled,
            autofocus: true,
            onSubmitted: submitted.add,
          ),
        ),
      );
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(calls.single.method, 'editText');
      expect(calls.single.arguments['text'], '保留');
      await tester.pumpWidget(app(false));
      result.complete('丢弃');
      await tester.pumpAndSettle();
      expect(controller.text, '保留');
      expect(submitted, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'large existing rules pass the native boundary intact with the import limit',
    (tester) async {
      final original = '规则' * 20000;
      final controller = TextEditingController(text: original);
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(TvNativeInput.channel, (call) async {
        calls.add(call);
        return call.arguments['text'];
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(TvNativeInput.channel, null);
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvTextInput(
              controller: controller,
              maxLength: 131072,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(calls.single.arguments['maxLength'], 131072);
      expect(calls.single.arguments['text'], original);
      expect(controller.text, original);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'oversized fallback input is shown intact and cannot replace the controller',
    (tester) async {
      final controller = TextEditingController(text: '保留');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvTextInput(
              controller: controller,
              maxLength: 8,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '完整保留的超长输入内容');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(controller.text, '保留');
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, '完整保留的超长输入内容');
      expect(find.textContaining('内容过长'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.text, '保留');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'closing phone input returns focus to its launcher after the transition',
    (tester) async {
      final controller = TextEditingController(text: '保留');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvTextInput(controller: controller, autofocus: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('扫码输入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('返回电视'));
      await tester.pumpAndSettle();
      final launcher = tester.widget<OutlinedButton>(
        find.byWidgetPredicate((widget) => widget is OutlinedButton),
      );
      expect(launcher.focusNode!.hasFocus, isTrue);
      expect(controller.text, '保留');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'input completion does not steal focus from the submitted destination',
    (tester) async {
      final controller = TextEditingController();
      final fieldFocus = FocusNode();
      final destinationFocus = FocusNode();
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(controller.dispose);
      addTearDown(fieldFocus.dispose);
      addTearDown(destinationFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: TvTextInput(
              controller: controller,
              focusNode: fieldFocus,
              autofocus: true,
              onSubmitted: (_) => navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: TextButton(
                      focusNode: destinationFocus,
                      autofocus: true,
                      onPressed: () {},
                      child: const Text('搜索结果'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '搜索内容');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('搜索结果'), findsOneWidget);
      expect(destinationFocus.hasFocus, isTrue);
      expect(fieldFocus.hasFocus, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('password field renders no secret text in the TV view', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hidden-password');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvTextInput(controller: controller, obscureText: true),
        ),
      ),
    );
    expect(find.text('hidden-password'), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);
  });
}
