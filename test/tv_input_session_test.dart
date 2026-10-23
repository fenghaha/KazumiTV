import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/tv/input/remote_input_session.dart';
import 'package:kazumi/tv/input/tv_input_limits.dart';

void main() {
  late HttpClient client;
  late RemoteInputSession session;
  final received = <String>[];
  var enabled = true;

  Future<(int, String)> post(Uri url, Object body, {String? origin}) async {
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType.json;
    if (origin != null) request.headers.set('origin', origin);
    request.write(jsonEncode(body));
    final response = await request.close();
    return (response.statusCode, await utf8.decoder.bind(response).join());
  }

  setUp(() async {
    client = HttpClient();
    received.clear();
    enabled = true;
    session = await RemoteInputSession.start(
      title: '搜索',
      initialText: '东京',
      addressProvider: () async => InternetAddress.loopbackIPv4,
      onInput: (text, submit) {
        if (!enabled) return false;
        received.add(text);
        return true;
      },
    );
  });

  tearDown(() async {
    client.close(force: true);
    await session.close();
  });

  test(
    'fill and submit acknowledge input, then signal dialog completion',
    () async {
      expect(
        (await post(session.url, {'text': '东京食尸鬼', 'submit': false})).$1,
        HttpStatus.ok,
      );
      expect(received, ['东京食尸鬼']);
      final submitted = session.submitted.first;
      expect(
        (await post(session.url, {'text': '东京喰种', 'submit': true})).$1,
        HttpStatus.ok,
      );
      await submitted;
      expect(received, ['东京食尸鬼', '东京喰种']);
    },
  );

  test('a disabled TV field rejects an already opened phone page', () async {
    enabled = false;
    expect(
      (await post(session.url, {'text': 'do not apply', 'submit': true})).$1,
      HttpStatus.conflict,
    );
    expect(received, isEmpty);
  });

  test(
    'wrong capability and cross-origin requests cannot modify a field',
    () async {
      expect(
        (await post(session.url.replace(path: '/wrong'), {
          'text': 'wrong',
          'submit': true,
        })).$1,
        HttpStatus.notFound,
      );
      expect(
        (await post(session.url, {
          'text': 'cross-origin',
          'submit': true,
        }, origin: 'https://example.org')).$1,
        HttpStatus.forbidden,
      );
      expect(received, isEmpty);
    },
  );

  test(
    'invalid payload and excessive text are rejected before applying',
    () async {
      expect(
        (await post(session.url, {'text': 17, 'submit': true})).$1,
        HttpStatus.badRequest,
      );
      expect(
        (await post(session.url, {'text': 'x' * 4097, 'submit': false})).$1,
        HttpStatus.requestEntityTooLarge,
      );
      expect(received, isEmpty);
    },
  );

  test(
    'large Chinese rule JSON exceeding 32 KB is applied without truncation',
    () async {
      final controller = TextEditingController(text: '原内容');
      addTearDown(controller.dispose);
      await session.close();
      session = await RemoteInputSession.start(
        title: '导入规则',
        initialText: controller.text,
        maxLength: TvInputLimits.maximumLength,
        addressProvider: () async => InternetAddress.loopbackIPv4,
        onInput: (text, _) {
          controller.text = text;
          return true;
        },
      );
      final rule = jsonEncode({'name': '规则', 'chapter': '中文' * 20000});
      expect(utf8.encode(rule).length, greaterThan(32768));
      final result = await post(session.url, {'text': rule, 'submit': false});
      expect(result.$1, HttpStatus.ok);
      expect(controller.text, rule);
    },
  );

  test(
    'over-field and over-body requests leave the existing controller intact',
    () async {
      final controller = TextEditingController(text: '不能截断的原内容');
      addTearDown(controller.dispose);
      await session.close();
      session = await RemoteInputSession.start(
        title: '导入规则',
        initialText: controller.text,
        maxLength: 64,
        addressProvider: () async => InternetAddress.loopbackIPv4,
        onInput: (text, _) {
          controller.text = text;
          return true;
        },
      );
      final overField = await post(session.url, {
        'text': '中' * 65,
        'submit': false,
      });
      expect(overField.$1, HttpStatus.requestEntityTooLarge);
      expect(jsonDecode(overField.$2)['error'], 'input_too_long');
      expect(controller.text, '不能截断的原内容');
      final overBody = await post(session.url, {
        'text': '合法文字',
        'submit': false,
        'padding': 'x' * (TvInputLimits.bodyBytes(64) + 1),
      });
      expect(overBody.$1, HttpStatus.requestEntityTooLarge);
      expect(jsonDecode(overBody.$2)['error'], 'request_too_large');
      expect(controller.text, '不能截断的原内容');
    },
  );

  test('input policy keeps the ordinary default and bounds larger fields', () {
    expect(TvInputLimits.normalize(null), 4096);
    expect(TvInputLimits.normalize(131072), 131072);
    expect(TvInputLimits.normalize(1000000), 131072);
    expect(TvInputLimits.bodyBytes(131072), 131072 * 6 + 1024);
  });

  test('secret values never prefill the phone HTML', () async {
    await session.close();
    session = await RemoteInputSession.start(
      title: 'Token',
      initialText: 'existing-private-value',
      obscureText: true,
      addressProvider: () async => InternetAddress.loopbackIPv4,
      onInput: (_, _) => true,
    );
    final response = await (await client.getUrl(session.url)).close();
    final page = await utf8.decoder.bind(response).join();
    expect(page, isNot(contains('existing-private-value')));
    expect(page, contains('type="password"'));
    expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
  });

  test('closing the dialog revokes its server and is idempotent', () async {
    final url = session.url;
    await session.close();
    await session.close();
    expect(session.isClosed, isTrue);
    await expectLater(
      () async => (await client.getUrl(url)).close(),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'no LAN address fails without a cached bad session; retry can work',
    () async {
      await expectLater(
        RemoteInputSession.start(
          title: '搜索',
          initialText: '',
          addressProvider: () async => null,
          onInput: (_, _) => true,
        ),
        throwsA(isA<SocketException>()),
      );
      final retry = await RemoteInputSession.start(
        title: '搜索',
        initialText: '',
        addressProvider: () async => InternetAddress.loopbackIPv4,
        onInput: (_, _) => true,
      );
      expect(retry.isClosed, isFalse);
      expect(retry.url.path, isNot(session.url.path));
      await retry.close();
    },
  );

  test('expiry revokes an idle session', () async {
    final temporary = await RemoteInputSession.start(
      title: '搜索',
      initialText: '',
      lifetime: const Duration(milliseconds: 20),
      addressProvider: () async => InternetAddress.loopbackIPv4,
      onInput: (_, _) => true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(temporary.isClosed, isTrue);
    await temporary.close();
  });
}
