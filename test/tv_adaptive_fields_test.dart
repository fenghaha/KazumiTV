import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/tv/input/tv_adaptive_fields.dart';
import 'package:kazumi/tv/input/tv_text_input.dart';
import 'package:kazumi/tv/platform/tv_native_input.dart';
import 'package:kazumi/tv/tv_mode.dart';
import 'package:kazumi/tv/tv_theme.dart';

void main() {
  setUp(() => TvMode.enabled = true);
  tearDown(() {
    TvMode.enabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvNativeInput.channel, null);
  });

  testWidgets(
    'TV token uses native editor, cancel stays on page and IME does not shrink body',
    (tester) async {
      final result = Completer<String?>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvNativeInput.channel, (call) {
            calls.add(call);
            return result.future;
          });
      final token = TextEditingController(text: 'fixture-token');
      addTearDown(token.dispose);
      var submits = 0;
      Widget page(double inset) => MaterialApp(
        theme: TvTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(960, 540),
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
          child: SettingsPaneScope(
            embedded: true,
            showBackButton: false,
            onBack: () {},
            child: SettingsDetailScaffold(
              title: const Text('追番同步'),
              body: Column(
                children: [
                  TvAdaptiveTextField(
                    controller: token,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Access Token',
                    ),
                    onSubmitted: (_) => submits++,
                  ),
                  const Expanded(child: SizedBox(key: ValueKey('body-space'))),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      final height = tester
          .getSize(find.byKey(const ValueKey('body-space')))
          .height;
      Focus.of(tester.element(find.text('Access Token'))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(calls.single.method, 'editText');
      expect(calls.single.arguments['obscureText'], isTrue);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(page(300));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('body-space'))).height,
        height,
      );
      result.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('追番同步'), findsOneWidget);
      expect(submits, 0);
      expect(token.text, 'fixture-token');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'TV form retains validation and change notifications with native input',
    (tester) async {
      final url = TextEditingController();
      addTearDown(url.dispose);
      final form = GlobalKey<FormState>();
      var changes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            TvNativeInput.channel,
            (_) async => 'https://example.test/dav/',
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: TvTheme.dark,
          home: Scaffold(
            body: Form(
              key: form,
              onChanged: () => changes++,
              child: TvAdaptiveTextFormField(
                controller: url,
                decoration: const InputDecoration(labelText: '服务器'),
                validator: (value) =>
                    value?.startsWith('https://') == true ? null : '地址无效',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('地址无效'), findsOneWidget);
      await tester.tap(find.text('服务器'));
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isTrue);
      expect(changes, greaterThan(0));
      expect(url.text, 'https://example.test/dav/');
      expect(find.byType(TvTextInput), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('non-TV form keeps upstream Flutter editing behavior', (
    tester,
  ) async {
    TvMode.enabled = false;
    final text = TextEditingController();
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TvAdaptiveTextFormField(controller: text)),
      ),
    );
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byType(TvTextInput), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'desktop input');
    expect(text.text, 'desktop input');
  });
}
